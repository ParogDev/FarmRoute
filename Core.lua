-- Addon entry: SavedVariables, the selftest contract (docs/verify-loop.md in the scaffolding), the walk
-- through the active route (arrival check on a ticker, keybinds), /fr and event wiring.
local ADDON, ns = ...

FarmRoute = ns

local L, Nav, MapLines = ns.Logic, ns.Nav, ns.MapLines

ns.VERSION = "0.3.2"
local DB_VERSION = 1
local TICK = 0.25
local MIN_GAP = 1.0 -- seconds between two arrival advances, so a point inside the radius of the last isn't skipped

local DEFAULTS = {
	radius = L.DEFAULT_RADIUS,
	mode = "pin",
	autoAdvance = true,
	screenLine = true,
	mapLines = true,
	minimapDots = true,
	keepInteract = true,
	probe = true,
	followChests = true, -- a detected chest of the route becomes the objective
	suggestSkip = false, -- near a point with nothing detected for a while: say so
	autoSkip = false, -- ... and move on
	skipAfter = 15, -- seconds near a point with nothing detected
}

local SETTLE = 0.75 -- seconds at a point before "nothing here" counts (the soft target can appear late)
local LOST_AFTER = 1.5 -- seconds without the chest before it counts as gone (looted, or out of range)
local NEAR_YD = 20 -- "near a point" for the skip options

local counters = {
	advanceArrived = 0,
	advanceKey = 0,
	advanceNavReached = 0,
	advanceLooted = 0,
	skipKey = 0,
	autoSkip = 0,
	chestJump = 0,
	chestNoPoint = 0,
	imports = 0,
	placeFailed = 0,
}
local selftest = {}
ns.selftest = selftest
ns.counters = counters

local running, lastAdvance, lastDistance, lastDistanceWhy = false, 0, nil, nil

-- ---------------------------------------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------------------------------------
function ns.initDB(saved)
	local db = type(saved) == "table" and saved or {}
	db.dbVersion = db.dbVersion or DB_VERSION
	db.routes = db.routes or {}
	db.current = db.current or {}
	db.timers = db.timers or {}
	db.settings = db.settings or {}
	db.interactLog = db.interactLog or {}
	db.history = db.history or {} -- [route][point] = { visits = { { t, seen } }, lastSeen, rested }
	db.checked = db.checked or {} -- [route][point] = true: checked this loop
	db.objectNeed = db.objectNeed or {} -- [objectID] = minimum skill, read from the tooltip
	db.finds = db.finds or {} -- the last looted chests and what they did to the route
	db.learn = db.learn or {} -- [route] = { recording, samples = { { mapID, x, y, wx, wy, c } }, plan }
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then
			db.settings[k] = v
		end
	end
	-- each seed route is added once: one the player deleted stays deleted, one added in a later version arrives
	db.seededNames = db.seededNames or {}
	if db.seeded and not next(db.seededNames) then
		for _, name in ipairs(L.LEGACY_SEEDS) do
			db.seededNames[name] = true
		end
	end
	for _, r in ipairs(L.seedRoutes()) do
		if not db.seededNames[r.name] then
			if not db.routes[r.name] then
				db.routes[r.name] = r
			end
			db.seededNames[r.name] = true
		end
	end
	if not db.seeded then
		db.active = db.active or "Angor Battered"
		db.seeded = true
	end
	-- the seed routes take only their own chest kind (0.1.x saved them without the list)
	for name, objects in pairs(L.SEED_OBJECTS) do
		local r = db.routes[name]
		if r and r.objects == nil then
			r.objects = {}
			for id in pairs(objects) do
				r.objects[id] = true
			end
		end
	end
	-- never switched off: walking (a fresh install shows the pin, not a stopped status line)
	if db.running == nil then
		db.running = true
	end
	db.selftest = db.selftest or {}
	ns.db = db
	FarmRouteDB = db
	return db
end

function ns.activeRoute()
	return ns.db and ns.db.active and ns.db.routes[ns.db.active] or nil
end

function ns.timersFor(name)
	ns.db.timers[name] = ns.db.timers[name] or {}
	return ns.db.timers[name]
end

function ns.currentIndex()
	local route = ns.activeRoute()
	if not route then
		return nil
	end
	-- the objective is a chest in the loop: a path point or dropped seed stored there moves on to the next one
	return L.currentStop(route, ns.db.current[route.name], ns.historyFor(route.name))
end

function ns.playerMap()
	local m = C_Map.GetBestMapForUnit("player")
	return (m and not issecretvalue(m)) and m or nil
end

-- A zone name in a /way line: the player's map or one of its parents, by name.
function ns.resolveZone(name)
	local m = ns.playerMap()
	name = name:lower()
	while m do
		local info = C_Map.GetMapInfo(m)
		if not info then
			return nil
		end
		if info.name and info.name:lower() == name then
			return m
		end
		m = info.parentMapID ~= 0 and info.parentMapID or nil
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- Walking
-- ---------------------------------------------------------------------------------------------------------
local function say(line)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100FarmRoute:|r " .. line)
end
ns.say = say

-- Path points between the last chest and the objective, walked in order: { route, list = { i }, at }
local via = { list = {}, at = 1 }

-- The point the pin is on: the next via of the stretch being walked, else the objective chest.
function ns.pinIndex()
	local route = ns.activeRoute()
	local i = via.route == (route and route.name) and via.list[via.at] or nil
	if i and route.points[i] then
		return i
	end
	return ns.currentIndex()
end

local function place()
	local route, i = ns.activeRoute(), ns.pinIndex()
	if not running or not route or not i then
		return
	end
	local ok, why = Nav.place(route.points[i], ns.db.settings.mode)
	if not ok then
		counters.placeFailed = counters.placeFailed + 1
		say("can't show the point: " .. tostring(why))
	end
	MapLines.refresh()
end

-- The chest the game is soft-targeting, once matched to the route: { key, point, objectID, lastSeen, lootedAt }
local chest
local seenThisLoop = {} -- [point] = true: a chest of the route was detected there this loop
local seenRoute -- the route seenThisLoop and chest belong to
local arrivedAt, nearSince, skipSuggested

local function resetPointState()
	arrivedAt, nearSince, skipSuggested = nil, nil, false
end

-- Every move of the objective starts the point's settle and skip clocks again; a route switch also forgets
-- the chest and the points seen this loop, which belong to the other route. from: the chest the walk comes
-- from, so the pin goes through the path points in between (nil: straight to i).
local function setCurrent(i, from)
	local route = ns.activeRoute()
	if not i then
		return
	end
	if seenRoute and seenRoute ~= route.name then
		seenThisLoop, chest = {}, nil
	end
	seenRoute = route.name
	resetPointState()
	ns.db.current[route.name] = i
	via = { route = route.name, list = L.viasBetween(route, from, i), at = 1 }
	lastAdvance = GetTime()
	place()
end

-- Moves the pin past the vias the player has reached (or walked past); places it when it moved.
local function viaTick(route, i)
	if via.route ~= route.name or not via.list[via.at] then
		return
	end
	local c, x, y = Nav.playerWorld()
	local tc, tx, ty = Nav.worldPos(route.points[i].mapID, route.points[i].x, route.points[i].y)
	if not c or tc ~= c then
		return
	end
	local d, dn, vn = {}, {}, {}
	for k = via.at, #via.list do
		local p = route.points[via.list[k]]
		local vc, vx, vy
		if p then
			vc, vx, vy = Nav.worldPos(p.mapID, p.x, p.y)
		end
		if not p or vc ~= c then
			break
		end
		-- the point after via k: the next via, else the chest
		local q = via.list[k + 1] and route.points[via.list[k + 1]]
		local nc, nx, ny = tc, tx, ty
		if q then
			nc, nx, ny = Nav.worldPos(q.mapID, q.x, q.y)
		end
		d[k] = L.distance(x, y, vx, vy)
		if nc == c then
			dn[k], vn[k] = L.distance(x, y, nx, ny), L.distance(vx, vy, nx, ny)
		end
	end
	local at = L.nextVia(via.at, d, dn, vn, L.radiusOf(route, ns.db.settings))
	if at ~= via.at then
		via.at = at
		place()
	end
end

function ns.historyFor(name)
	ns.db.history[name] = ns.db.history[name] or {}
	return ns.db.history[name]
end

function ns.checkedFor(name)
	ns.db.checked[name] = ns.db.checked[name] or {}
	return ns.db.checked[name]
end

-- dir +1 / -1; why names the counter. Forward checks the current point (seen: true / false records a visit
-- in the history, nil records none, as for a skip) and goes to the objective: the next point not checked this
-- loop. Back steps one point and checks nothing.
function ns.advance(dir, why, seen)
	local route = ns.activeRoute()
	if not route or #route.points == 0 then
		say("no route or an empty route: /fr route, /fr add")
		return
	end
	local now = time()
	local timers = ns.timersFor(route.name)
	local cur = ns.currentIndex()
	counters[why] = (counters[why] or 0) + 1
	resetPointState()
	if chest and chest.point == cur then
		chest = nil
	end
	if dir < 0 then
		setCurrent((L.nextIndex(route, timers, cur, -1, now, ns.historyFor(route.name))))
		return
	end
	local m = L.respawnOf(route, cur)
	-- a skip opened nothing: no respawn timer
	if m > 0 and why ~= "skipKey" and why ~= "autoSkip" then
		timers[cur] = now + m * 60
	end
	local checked, hist = ns.checkedFor(route.name), ns.historyFor(route.name)
	checked[cur] = true
	if seen ~= nil and L.tracksVisits(route) then
		L.recordVisit(hist, cur, seen, now)
	end
	local i, objWhy = L.objective(route, timers, checked, hist, cur, now)
	if not i then
		L.newLoop(route, checked, hist)
		seenThisLoop = {}
		i, objWhy = L.objective(route, timers, checked, hist, cur, now)
	end
	local waiting = false
	if not i then
		i, waiting = L.nextIndex(route, timers, cur, 1, now, hist)
	end
	ns.objectiveWhy = waiting and "waiting" or objWhy
	setCurrent(i, cur)
	if waiting and i and timers[i] then
		say(
			string.format(
				"every point is on its respawn timer; next up: %s in %d s",
				L.formatPoint(route, i),
				timers[i] - now
			)
		)
	end
end

function FarmRoute.Next()
	if not running then
		ns.start()
	end
	ns.advance(1, "advanceKey")
end

function FarmRoute.Prev()
	if not running then
		ns.start()
	end
	ns.advance(-1, "advanceKey")
end

-- Skip keybind: the current point counts as checked (no history entry) and the objective moves on.
function FarmRoute.Skip()
	if not running then
		ns.start()
	end
	local route, i = ns.activeRoute(), ns.currentIndex()
	ns.advance(1, "skipKey")
	if route and i and ns.currentIndex() ~= i and ns.HUD and ns.HUD.flash then
		ns.guard("flash", ns.HUD.flash, "Skipped " .. i .. "/" .. #route.points)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Chests: a soft-interact target of the route's kind becomes the objective (the route point nearest the
-- player, inside detection range), and stays it until it is gone: looted at the point (a visit with a chest),
-- or lost from further away (the point stays the objective; arriving there later counts it as seen).
-- ---------------------------------------------------------------------------------------------------------
local skillCache = { at = -10 }

-- The player's rank in the skill the route's chests need (named by their tooltip), refreshed every 5 s.
function ns.skillRank()
	if GetTime() - skillCache.at > 5 then
		skillCache.at = GetTime()
		skillCache.rank = ns.Detect.skillRank(skillCache.name or "Lockpicking")
	end
	return skillCache.rank
end

-- The minimum skill of the route's chest kind, from the tooltip of one seen before.
function ns.routeNeed(route)
	if chest and chest.need then
		return chest.need
	end
	for id in pairs(route.objects or {}) do
		if ns.db.objectNeed[id] then
			return ns.db.objectNeed[id]
		end
	end
	return nil
end

-- Detection range in yards: the soft-interact range CVar plus a margin for the point's own error.
local function detectYards()
	local ok, v = pcall(C_CVar.GetCVar, "SoftTargetInteractRange")
	return (ok and tonumber(v) or 10) + 5
end

local function nearestPoint(route)
	local pm, px, py = Nav.playerPos()
	if not pm then
		return nil
	end
	local c, x, y = Nav.worldPos(pm, px, py)
	if not c then
		return nil
	end
	local list = {}
	for i, p in ipairs(route.points) do
		local pc, wx, wy = Nav.worldPos(p.mapID, p.x, p.y)
		if pc == c then
			list[#list + 1] = { i = i, x = wx, y = wy }
		end
	end
	return L.nearestIndex(list, x, y, detectYards())
end

-- ---------------------------------------------------------------------------------------------------------
-- Learned spawns: every looted chest of a route's kind is a find at the player's position (inside loot
-- range of the chest). Logic.findTarget merges it into a confirmed point, confirms the nearest seed, or adds
-- a point. Point indexes key the history, checked set and timers, so an insert moves those along.
-- ---------------------------------------------------------------------------------------------------------
local FINDS_MAX = 40

-- { { i, x, y } } in world yards for every point of the route on continent c.
local function routeYards(route, c)
	local list = {}
	for i, p in ipairs(route.points) do
		local pc, wx, wy = Nav.worldPos(p.mapID, p.x, p.y)
		if pc == c then
			list[#list + 1] = { i = i, x = wx, y = wy, point = p }
		end
	end
	return list
end

-- The map position (on the route's own map) of a world point: mapID, x, y.
local function onRouteMap(route, c, wx, wy, pm, px, py)
	local rm = route.points[1] and route.points[1].mapID or pm
	if rm == pm then
		return pm, px, py
	end
	local x, y = Nav.mapPos(rm, c, wx, wy)
	if x then
		return rm, x, y
	end
	return nil, "no position on the route's map " .. tostring(rm)
end

-- Applies an old -> new index map to everything keyed by the route's point indexes.
function ns.remapRoute(name, map)
	local db = ns.db
	db.history[name] = L.remap(db.history[name], map)
	db.checked[name] = L.remap(db.checked[name], map)
	db.timers[name] = L.remap(db.timers[name], map)
	if db.current[name] then
		-- a deleted or replaced current point hands over to the next surviving one, not to point 1
		db.current[name] = L.remapIndex(db.current[name], map)
	end
	if seenRoute == name then
		seenThisLoop = L.remap(seenThisLoop, map)
		if chest then
			chest.point = map[chest.point]
			if not chest.point then -- the detected chest's point was deleted
				chest = nil
			end
		end
	end
	-- the stretch being walked keeps its remaining vias
	if via.route == name then
		local list, at = {}, 1
		for k, i in ipairs(via.list) do
			if map[i] then
				list[#list + 1] = map[i]
				if k < via.at then
					at = at + 1
				end
			end
		end
		via.list, via.at = list, at
	end
	-- a learn plan waiting for accept names chests by index too; one whose chest was deleted is dropped
	local lr = db.learn[name]
	if lr and lr.plan then
		for k, i in ipairs(lr.plan.order) do
			if not map[i] then
				lr.plan = nil
				say("a point of the learn walk was deleted: walk discarded, /fr learn on to walk again")
				return
			end
			lr.plan.order[k] = map[i]
		end
	end
end

-- The game object id of what the open loot window came from (first slot with a GameObject source), or nil
-- and why. The same chest opened again within REOPEN seconds (loot left in it) is no new find; a chest keeps
-- its GUID when it respawns, so later it is one.
local lastLootGuid, lastLootAt = nil, 0
local REOPEN = 60
local function lootObject()
	local n = GetNumLootItems and GetNumLootItems() or 0
	for slot = 1, n do
		local ok, guid = pcall(GetLootSourceInfo, slot)
		if ok and guid ~= nil then
			if issecretvalue(guid) then
				return nil, "loot source is a secret value"
			end
			local id = L.guidObject(guid)
			if id then
				if guid == lastLootGuid and GetTime() - lastLootAt < REOPEN then
					return nil, "same chest opened again"
				end
				lastLootGuid, lastLootAt = guid, GetTime()
				return id
			end
		end
	end
	return nil, n == 0 and "loot window empty" or "loot not from a game object"
end

-- Records a find for every route that farms this object. Returns what was done, for the selftest.
function ns.recordFind(objectID)
	local c, wx, wy, pm, px, py = Nav.playerWorld()
	if not c then
		return { why = "no player position: " .. tostring(wx) }
	end
	local done
	for name, route in pairs(ns.db.routes) do
		-- a route that can't detect its objects (fishing pools) learns nothing: the player stands off the spawn
		if type(route.objects) == "table" and route.objects[objectID] and L.tracksVisits(route) then
			local list = routeYards(route, c)
			local action, i, d = L.findTarget(route, list, wx, wy)
			local mapID, mx, my = onRouteMap(route, c, wx, wy, pm, px, py)
			local noMap = not mapID and mx or nil -- why the find has no position on the route's map
			local entry -- this route's line in db.finds
			if action == "far" then -- luacheck: ignore 542
				-- the same chest kind somewhere else: not this route's
			elseif action == "new" then
				if noMap then
					i = nil -- a point on another map would vanish from the route's map
					entry = { route = name, objectID = objectID, action = "skipped", why = noMap }
				else
					local floor = route.points[1] and route.points[1].floor
					local p = { mapID = mapID, x = mx, y = my, label = "Learned", floor = floor, finds = 1 }
					ns.remapRoute(name, L.insertMap(#route.points, i))
					table.insert(route.points, i, p)
				end
			elseif noMap then
				-- an existing point: the find counts, its coordinate stays
				local p = route.points[i]
				p.finds = (L.isConfirmed(p) and p.finds or 0) + 1
			else
				L.mergeFind(route.points[i], mx, my)
			end
			if i then
				entry = { route = name, objectID = objectID, action = action, point = i, why = noMap }
				entry.yd = d and math.floor(d + 0.5)
				local what = action == "new" and "new spawn" or (action == "confirm" and "seed confirmed") or "spawn"
				say(string.format("%s learned: %s", what, L.formatPoint(route, i)))
				if name == ns.db.active then
					-- a chest held from another route (no tick since the switch) is not this loot's
					local own = seenRoute == name and chest or nil
					local objective = ns.db.current[name]
					if own and objective == own.point and objective ~= i then
						-- the looted chest is the objective, at its learned point now: no vias, fresh clocks
						setCurrent(i)
					elseif not (own and objective == own.point) and objective ~= i then
						-- another chest of the loop, looted on the way: don't send the player back to it
						ns.checkedFor(name)[i] = true
					end
					-- after setCurrent, which forgets another route's state: the loot logic follows this point
					seenThisLoop[i] = true
					if own then
						chest.point = i
					end
				end
			end
			if entry then
				entry.at = date("%Y-%m-%d %H:%M:%S")
				L.push(ns.db.finds, entry, FINDS_MAX)
				done = entry
			end
		end
	end
	if done then
		place()
		MapLines.refresh()
	end
	return done or { objectID = objectID, why = "no route farms object " .. tostring(objectID) }
end

-- LOOT_OPENED while a chest of the route is the target, or was a moment ago: it is being opened. The loot
-- source names the chest kind; a route's kind is a learned spawn.
function ns.onLootOpened()
	if chest and GetTime() - (chest.lastSeen or 0) <= LOST_AFTER * 2 then
		chest.lootedAt = GetTime()
	end
	ns.guard("recordFind", function()
		local id, why = lootObject()
		ns.lastFind = id and ns.recordFind(id) or { why = why }
	end)
end

local function chestTick(route, cur)
	local t = ns.Detect.current
	local match = t and L.matchesRoute(route, t.objectID, t.need)
	local now = GetTime()
	if match then
		if t.need then
			skillCache.name = t.need.skill
			if t.objectID then
				ns.db.objectNeed[t.objectID] = t.need.level
			end
		end
		local key = t.guid or t.name or "secret"
		if not chest or chest.key ~= key then
			local p = nearestPoint(route)
			if not p then
				counters.chestNoPoint = counters.chestNoPoint + 1
				ns.chestWhy = "chest detected but no route point within " .. detectYards() .. " yd"
				return
			end
			chest = { key = key, point = p, objectID = t.objectID, need = t.need and t.need.level }
			seenThisLoop[p] = true
			ns.chestWhy = "chest at point " .. p
			if p ~= cur and ns.db.settings.followChests then
				counters.chestJump = counters.chestJump + 1
				resetPointState()
				setCurrent(p)
				say(string.format("chest detected: %s", L.formatPoint(route, p)))
			end
		end
		chest.lastSeen = now
		chest.need = t.need and t.need.level or chest.need -- the tooltip hook may fill it later
	elseif chest and now - chest.lastSeen > LOST_AFTER then
		local d = Nav.distanceTo(route.points[chest.point])
		-- looted only with LOOT_OPENED seen for it: a chair taking the soft target looks the same otherwise
		local looted = chest.lootedAt and chest.point == cur and d and d <= ns.db.settings.radius * 2
		chest = nil
		ns.chestWhy = looted and "chest looted at the point" or "chest no longer targeted"
		if looted then
			ns.advance(1, "advanceLooted", true)
		end
	end
end

-- At the current point (inside the radius): a chest there waits for its loot; nothing there for SETTLE
-- seconds checks the point (seen this loop from afar: a chest, else empty). Near it with nothing detected for
-- skipAfter seconds: suggest a skip, or skip (both options off by default).
local function arrivalTick(route, i, d)
	local now = GetTime()
	local s = ns.db.settings
	if d <= L.radiusOf(route, s) and now - lastAdvance >= MIN_GAP and L.isUp(ns.timersFor(route.name), i, time()) then
		nearSince = nil
		if chest and chest.point == i then
			return
		end
		arrivedAt = arrivedAt or now
		if s.autoAdvance and now - arrivedAt >= SETTLE then
			-- "empty" only when detection could work; otherwise no history entry (it would turn the point cold)
			local seen = seenThisLoop[i] == true
			if not seen and (InCombatLockdown() or not ns.healthState().ok) then
				seen = nil
			end
			ns.advance(1, "advanceArrived", seen)
		end
		return
	end
	arrivedAt = nil
	if d > NEAR_YD or chest or not (s.suggestSkip or s.autoSkip) then
		nearSince = nil
		return
	end
	nearSince = nearSince or now
	if now - nearSince < s.skipAfter then
		return
	end
	if s.autoSkip then
		ns.advance(1, "autoSkip", false)
		say("nothing detected near " .. L.formatPoint(route, i) .. ": moved on")
	elseif not skipSuggested then
		skipSuggested = true
		if ns.HUD and ns.HUD.flash then
			ns.guard("flash", ns.HUD.flash, "Nothing here? Skip key")
		end
		say("nothing detected near " .. L.formatPoint(route, i) .. "; the Skip key moves on")
	end
end

-- What the marker shows: see HUD.buildMarker.
function ns.markerInfo()
	local route, i = ns.activeRoute(), ns.currentIndex()
	if not route or not i then
		return {}
	end
	local state, label = "route", i .. "/" .. #route.points
	if chest and chest.point == i then
		state = "detected"
	elseif ns.objectiveWhy == "waiting" then
		state = "waiting"
	elseif ns.pinIndex() ~= i then
		state, label = "path", "→ " .. label
	end
	return { state = state, need = ns.routeNeed(route), skill = ns.skillRank(), label = label }
end

-- /fr learn: a sample every LEARN_STEP yards walked, kept on the route's map, plus the finds made meanwhile.
local SAMPLES_MAX, LEARN_REDRAW = 2000, 1
local lastLearnDraw = 0

local function learnTick(route)
	local lr = ns.db.learn[route.name]
	if not lr or not lr.recording then
		return
	end
	if #lr.samples >= SAMPLES_MAX then
		if not lr.full then
			lr.full = true
			say("learn walk is full (" .. SAMPLES_MAX .. " samples): /fr learn off")
		end
		return
	end
	local c, wx, wy, pm, px, py = Nav.playerWorld()
	if not c then
		lr.gap = true
		return
	end
	local last = lr.samples[#lr.samples]
	if not L.shouldSample(last and { x = last.wx, y = last.wy }, wx, wy, L.LEARN_STEP) then
		return
	end
	local mapID, mx, my = onRouteMap(route, c, wx, wy, pm, px, py)
	if not mapID then
		lr.why = mx -- shown by /fr learn and the selftest
		lr.gap = true -- the next sample starts a new run of the trail
		return
	end
	lr.why = nil
	lr.samples[#lr.samples + 1] = { mapID = mapID, x = mx, y = my, wx = wx, wy = wy, c = c, gap = lr.gap }
	lr.gap = nil
	if GetTime() - lastLearnDraw >= LEARN_REDRAW then
		lastLearnDraw = GetTime()
		MapLines.refresh()
	end
end

local function tick()
	ns.guard("detect", ns.Detect.tick)
	if ns.updateHealth then
		ns.guard("health", ns.updateHealth)
	end
	if not running then
		Nav.hideMarker("stopped")
		return
	end
	local route, i = ns.activeRoute(), ns.currentIndex()
	if route and i then
		ns.guard("chest", chestTick, route, i)
		i = ns.currentIndex()
		ns.guard("via", viaTick, route, i)
		ns.guard("learn", learnTick, route)
	end
	Nav.updateScreenLine(ns.db.settings.screenLine, ns.db.settings.radius, ns.markerInfo())
	if not route or not i then
		return
	end
	local d, why = Nav.distanceTo(route.points[i])
	lastDistance, lastDistanceWhy = d, why
	if d then
		arrivalTick(route, i, d)
	end
end

function ns.start()
	running = true
	ns.db.running = true
	place()
end

function ns.stop()
	running = false
	ns.db.running = false
	ns.restoreCVars()
	Nav.clear()
	Nav.hideMarker("stopped")
	MapLines.refresh()
end

function ns.importPoints(points, replace)
	local route = ns.activeRoute()
	if replace then
		route.points = {}
		ns.db.timers[route.name] = {}
		ns.db.current[route.name] = 1
	end
	for _, p in ipairs(points) do
		route.points[#route.points + 1] = p
	end
	counters.imports = counters.imports + 1
	place()
	MapLines.refresh()
end

-- ---------------------------------------------------------------------------------------------------------
-- selftest
-- ---------------------------------------------------------------------------------------------------------
local function version()
	local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON, "Version")
	if not ok or type(v) ~= "string" or v:find("@", 1, true) then
		return ns.VERSION
	end
	return v
end
ns.version = version

-- The client's name for each seed route's map: a uiMapID this client doesn't know shows as such.
local function seedMaps()
	local out = {}
	for _, r in ipairs(L.seedRoutes()) do
		local m = r.points[1].mapID
		local info = C_Map.GetMapInfo(m)
		out[r.name] = m .. " " .. (info and info.name or "unknown to C_Map.GetMapInfo")
	end
	return out
end

function selftest.snapshot(phase)
	local okB, buildVersion, buildNumber, _, interface = pcall(GetBuildInfo)
	local route = ns.activeRoute()
	local okNav, nav = pcall(Nav.selftest)
	ns.db.selftest = {
		phase = phase,
		version = version(),
		build = okB and (tostring(buildVersion) .. "." .. tostring(buildNumber)) or "GetBuildInfo failed",
		interface = okB and interface or nil,
		project = WOW_PROJECT_ID,
		loadedAt = selftest.loadedAt,
		savedAt = date("%Y-%m-%d %H:%M:%S"),
		running = running,
		route = route and route.name or "none",
		points = route and #route.points or 0,
		current = ns.currentIndex(),
		distance = lastDistance and math.floor(lastDistance + 0.5) or nil,
		distanceWhy = lastDistanceWhy,
		nav = okNav and nav or ("Nav.selftest raised: " .. tostring(nav)),
		maps = MapLines.status,
		seedMaps = seedMaps(),
		settings = ns.db.settings,
		counters = counters,
		interact = ns.interactState(),
		interactLast = ns.db.interactLog and ns.db.interactLog[#ns.db.interactLog] or nil,
		detect = ns.Detect.selftest(),
		objective = {
			why = ns.objectiveWhy,
			chest = chest and { point = chest.point, objectID = chest.objectID, need = chest.need } or nil,
			chestWhy = ns.chestWhy,
			marker = ns.markerInfo(),
			checked = route and (function()
				local n = 0
				for _ in pairs(ns.checkedFor(route.name)) do
					n = n + 1
				end
				return n
			end)() or 0,
		},
		health = ns.healthState(),
		learned = route and (function()
			local n, hist = { chest = 0, unconfirmed = 0, dropped = 0, path = 0 }, ns.historyFor(route.name)
			for i = 1, #route.points do
				local s = L.pointStatus(route, hist, i)
				n[s] = n[s] + 1
			end
			n.lastFind = ns.lastFind
			n.finds = #ns.db.finds
			n.pin = ns.pinIndex()
			local lr = ns.db.learn[route.name]
			n.learn = lr and { recording = lr.recording, samples = #lr.samples, why = lr.why } or nil
			return n
		end)() or nil,
		lastError = selftest.lastError,
	}
	return ns.db.selftest
end

local function guard(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		selftest.lastError = { where = where, error = tostring(err), at = date("%Y-%m-%d %H:%M:%S") }
	end
	return ok
end
ns.guard = guard

-- ---------------------------------------------------------------------------------------------------------
-- /fr
-- ---------------------------------------------------------------------------------------------------------
local HELP = {
	"/fr on | off - start or stop the route",
	"/fr next | prev | goto <n> - move the pin (keybinds: Options > Keybindings > FarmRoute)",
	"/fr route [name] - list routes or switch; /fr new <name>; /fr delroute <name>",
	"/fr add [label] - add your position at the end; /fr del [n] - remove point n (default: current)",
	"/fr import - paste TomTom /way lines; /fr list - the points",
	"/fr radius <yards> - arrival distance (now %d); /fr auto on|off - advance on arrival",
	"/fr respawn <minutes> [n] - respawn timer for the route or point n (0 = off); /fr timers reset",
	"/fr mode pin|tomtom - Blizzard's in-world pin or TomTom's arrow; /fr line on|off; /fr map on|off; /fr minimap on|off",
	"/fr interact - interact key state and who changed it; /fr fixinteract - turn it on; /fr keepinteract on|off - keep it on",
	"/fr probe [on|off] - what soft-interact has measured (chat line per change when on)",
	"/fr follow on|off - a detected chest becomes the objective; /fr suggestskip | autoskip on|off - near a point with nothing detected",
	"/fr restorecvars - put back your soft-target settings (also done by /fr off); Skip keybind: Options > Keybindings",
	"/fr learn on|off|accept|discard - record your walk; off suggests path points (world map), accept saves them",
}

-- ---------------------------------------------------------------------------------------------------------
-- /fr learn: record a walk, then suggest path points between the chests it passed (Logic.learnPlan)
-- ---------------------------------------------------------------------------------------------------------
local function learnInput(route, lr)
	local c = lr.samples[1] and lr.samples[1].c
	local samples, chests = {}, {}
	for _, s in ipairs(lr.samples) do
		if s.c == c then
			samples[#samples + 1] = { x = s.wx, y = s.wy, mapID = s.mapID, mx = s.x, my = s.y, gap = s.gap }
		end
	end
	local entries = c and routeYards(route, c) or {}
	for _, e in ipairs(entries) do
		if not L.isPath(e.point) then
			chests[#chests + 1] = e
		end
	end
	return samples, chests, entries
end

function ns.learnView()
	local route = ns.activeRoute()
	local lr = route and ns.db.learn[route.name]
	if not lr then
		return nil
	end
	local v = { recording = lr.recording, mapID = route.points[1] and route.points[1].mapID }
	-- runs, not one line: a stretch off the route map or without a position is a break in the trail
	v.runs = L.trailRuns(lr.samples, v.mapID)
	local last = lr.samples[#lr.samples]
	if last and last.mapID == v.mapID and not lr.gap then -- paused: no head dot posing as the live position
		v.head = { x = last.x, y = last.y }
	end
	if lr.plan then
		v.suggestions, v.visits = {}, {}
		for _, s in ipairs(lr.plan.suggestions) do
			v.suggestions[#v.suggestions + 1] = { x = s.mx, y = s.my }
		end
		for _, i in ipairs(lr.plan.order) do
			local p = route.points[i]
			if p then
				v.visits[#v.visits + 1] = { x = p.x, y = p.y }
			end
		end
	end
	return v
end

local function learnCommand(arg)
	local route = ns.activeRoute()
	if not route then
		say("no active route")
		return
	end
	local lr = ns.db.learn[route.name]
	if arg == "on" then
		if lr and (lr.recording or lr.plan) then
			say(lr.recording and "already recording" or "a walk waits: /fr learn accept or discard first")
			return
		end
		ns.db.learn[route.name] = { recording = true, samples = {}, startedAt = date("%Y-%m-%d %H:%M:%S") }
		say("learning " .. route.name .. ": walk the loop, loot as usual, then /fr learn off")
	elseif arg == "off" then
		if not lr or not lr.recording then
			say("not recording: /fr learn on")
			return
		end
		lr.recording = false
		local samples, chests = learnInput(route, lr)
		local plan = L.learnPlan(samples, chests)
		plan.suggestions = {}
		for k = 1, #plan.order do
			for _, s in ipairs(L.planVias(plan, k)) do
				plan.suggestions[#plan.suggestions + 1] = s
			end
		end
		lr.plan = plan
		say(
			string.format(
				"%d samples, %d chests passed, %d path points suggested (world map). /fr learn accept or discard",
				#samples,
				#plan.order,
				#plan.suggestions
			)
		)
	elseif arg == "accept" then
		if not lr or not lr.plan or #lr.plan.order == 0 then
			say("nothing to accept: /fr learn on, walk, /fr learn off")
			return
		end
		local _, _, entries = learnInput(route, lr)
		local floor = route.points[1] and route.points[1].floor
		local points, map, keptVias = L.applyPlan(entries, lr.plan, function(s)
			return { mapID = s.mapID, x = s.mx, y = s.my, kind = "path", label = "path", floor = floor }
		end)
		-- points on another continent than the walk stay, appended in their order (path points too)
		local onWalk = {}
		for _, e in ipairs(entries) do
			onWalk[e.i] = true
		end
		for i, p in ipairs(route.points) do
			if not onWalk[i] then
				points[#points + 1] = p
				map[i] = #points
			end
		end
		ns.remapRoute(route.name, map)
		route.points = points
		ns.db.learn[route.name] = nil
		say(
			string.format(
				"route saved: %d points (%d new path, %d kept from stretches not walked)",
				#points,
				#lr.plan.suggestions,
				keptVias
			)
		)
		place()
	elseif arg == "discard" then
		ns.db.learn[route.name] = nil
		say("learn walk discarded")
	else
		say(
			lr
					and string.format(
						"learn: %s, %d samples%s",
						lr.recording and "recording" or "stopped",
						#lr.samples,
						lr.why and (" (not sampling: " .. lr.why .. ")") or ""
					)
				or "/fr learn on|off|accept|discard"
		)
		return
	end
	MapLines.refresh()
end

local function onOff(v)
	return v and "on" or "off"
end

local function status()
	local route, i = ns.activeRoute(), ns.currentIndex()
	if not route then
		say("no active route (/fr route)")
		return
	end
	local d = lastDistance and string.format("%d yd", lastDistance) or (lastDistanceWhy or "distance not known yet")
	say(
		string.format(
			"%s, %s; %s; %s, pin: %s",
			route.name,
			i and L.formatPoint(route, i) or "empty",
			running and "running" or "stopped",
			d,
			Nav.state.ok and (Nav.state.mode or "?") or tostring(Nav.state.why)
		)
	)
	if not running then
		say("/fr on starts the route; /fr help lists the commands")
	end
end

local function toggle(key, arg, label)
	if arg == "on" or arg == "off" then
		ns.db.settings[key] = arg == "on"
	else
		ns.db.settings[key] = not ns.db.settings[key]
	end
	say(label .. " " .. onOff(ns.db.settings[key]))
	MapLines.refresh()
end

local commands = { learn = learnCommand }

function commands.on()
	ns.start()
	status()
end

function commands.off()
	ns.stop()
	say("stopped; points kept")
end

function commands.next()
	FarmRoute.Next()
end

function commands.prev()
	FarmRoute.Prev()
end

commands["goto"] = function(arg)
	local route, n = ns.activeRoute(), tonumber(arg)
	if not route or not n or not route.points[n] then
		say("no point " .. tostring(arg))
		return
	end
	running = true
	setCurrent(n)
	status()
end

function commands.route(arg)
	if arg ~= "" then
		if not ns.db.routes[arg] then
			say("no route '" .. arg .. "'")
			return
		end
		ns.db.active = arg
		place()
		MapLines.refresh()
		status()
		return
	end
	for name, r in pairs(ns.db.routes) do
		say((name == ns.db.active and "> " or "  ") .. name .. " (" .. #r.points .. " points)")
	end
end

function commands.new(arg)
	if arg == "" or ns.db.routes[arg] then
		say(arg == "" and "/fr new <name>" or ("route '" .. arg .. "' exists"))
		return
	end
	ns.db.routes[arg] = { name = arg, points = {}, respawn = 0 }
	ns.db.active = arg
	say("new route '" .. arg .. "' is active: /fr add or /fr import")
end

function commands.delroute(arg)
	if not ns.db.routes[arg] then
		say("no route '" .. arg .. "'")
		return
	end
	ns.db.routes[arg], ns.db.timers[arg], ns.db.current[arg] = nil, nil, nil
	if ns.db.active == arg then
		ns.db.active = next(ns.db.routes)
		place()
	end
	MapLines.refresh()
	say("route '" .. arg .. "' deleted")
end

function commands.add(arg)
	local route = ns.activeRoute()
	local m, x, y = Nav.playerPos()
	if not route or not m then
		say(route and ("no position: " .. tostring(x)) or "no active route")
		return
	end
	route.points[#route.points + 1] = { mapID = m, x = x, y = y, label = arg ~= "" and arg or nil, manual = true }
	say("added " .. L.formatPoint(route, #route.points))
	MapLines.refresh()
end

function commands.del(arg)
	local route = ns.activeRoute()
	local n = tonumber(arg) or ns.currentIndex()
	if not route or not n or not route.points[n] then
		say("no point " .. tostring(arg))
		return
	end
	-- history, checked, timers, the objective and the vias are keyed by index: move them with the points. A
	-- deleted current point hands over to the next one (Logic.remapIndex, wrapping to the first).
	ns.remapRoute(route.name, L.removeMap(#route.points, n))
	table.remove(route.points, n)
	say("removed point " .. n .. "; " .. #route.points .. " left")
	place()
end

function commands.list()
	local route = ns.activeRoute()
	if not route then
		return
	end
	local timers, now = ns.timersFor(route.name), time()
	local checked, hist = ns.checkedFor(route.name), ns.historyFor(route.name)
	for i = 1, #route.points do
		local t = timers[i] and timers[i] > now and string.format(" [up in %d s]", timers[i] - now) or ""
		local seen, visits = L.seenRate(hist, i)
		local h = visits > 0 and string.format(" chest %d/%d visits", seen, visits) or ""
		local st = L.pointStatus(route, hist, i)
		local flags = (checked[i] and " checked" or "")
			.. (L.isCold(hist, i) and " cold" or "")
			.. ((st == "unconfirmed" or st == "dropped") and (" " .. st) or "")
		say((i == ns.currentIndex() and "> " or "  ") .. L.formatPoint(route, i) .. t .. h .. flags)
	end
end

function commands.import()
	ns.Import.show()
end

function commands.radius(arg)
	local r = L.clampRadius(arg)
	if r then
		ns.db.settings.radius = r
	end
	say("arrival radius " .. ns.db.settings.radius .. " yards")
end

function commands.respawn(arg)
	local route = ns.activeRoute()
	local m, n = arg:match("^(%d+%.?%d*)%s*(%d*)$")
	m = tonumber(m)
	if not route or not m then
		say("/fr respawn <minutes> [point]")
		return
	end
	n = tonumber(n)
	if n and route.points[n] then
		route.points[n].respawn = m > 0 and m or nil
		say(string.format("point %d respawn %s", n, m > 0 and (m .. " min") or "off (route default)"))
	else
		route.respawn = m
		say(string.format("%s respawn %s", route.name, m > 0 and (m .. " min") or "off"))
	end
end

function commands.timers(arg)
	local route = ns.activeRoute()
	if route and arg == "reset" then
		ns.db.timers[route.name] = {}
		MapLines.refresh()
		say("timers cleared")
	end
end

function commands.mode(arg)
	if not Nav.MODES[arg] then
		say("/fr mode pin|tomtom (now " .. ns.db.settings.mode .. ")")
		return
	end
	ns.db.settings.mode = arg
	place()
	status()
end

function commands.auto(arg)
	toggle("autoAdvance", arg, "advance on arrival")
end

function commands.line(arg)
	toggle("screenLine", arg, "on-screen line")
end

function commands.map(arg)
	toggle("mapLines", arg, "world map route")
end

function commands.keepinteract(arg)
	toggle("keepInteract", arg, "keep the interact key on")
	if ns.db.settings.keepInteract then
		ns.resetReasserts()
		ns.checkInteract("keepinteract on")
	end
end

-- /fr probe on|off: a chat line per soft-interact change; /fr probe: what it has measured so far.
function commands.probe(arg)
	if arg == "on" or arg == "off" then
		toggle("probe", arg, "soft-interact probe")
		return
	end
	local p = ns.Detect.probeDB()
	say(string.format("probe %s: %d events logged", onOff(ns.db.settings.probe), #p.events))
	for key, o in pairs(p.objects) do
		say(
			string.format(
				"  %s (%s): seen %d, needs %s, appeared %s-%s yd from the nearest point",
				tostring(o.name),
				key,
				o.seen,
				tostring(o.need or "?"),
				tostring(o.appearMin or "?"),
				tostring(o.appearMax or "?")
			)
		)
	end
	local cv = ns.Detect.cvars()
	say(
		"  Range "
			.. cv.SoftTargetInteractRange
			.. ", Arc "
			.. cv.SoftTargetInteractArc
			.. ", OnlyInRange "
			.. cv.SoftTargetInteractOnlyInRange
	)
end

function commands.follow(arg)
	toggle("followChests", arg, "follow detected chests")
end

function commands.suggestskip(arg)
	toggle("suggestSkip", arg, "suggest a skip when nothing is detected")
end

function commands.autoskip(arg)
	toggle("autoSkip", arg, "skip when nothing is detected")
end

function commands.skip()
	FarmRoute.Skip()
end

function commands.minimap(arg)
	toggle("minimapDots", arg, "minimap route")
end

SLASH_FARMROUTE1 = "/fr"
SLASH_FARMROUTE2 = "/farmroute"
SlashCmdList.FARMROUTE = function(msg)
	msg = type(msg) == "string" and msg or ""
	local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	local fn = commands[cmd]
	if fn then
		guard("/fr " .. cmd, fn, arg)
		if selftest.lastError and selftest.lastError.where == "/fr " .. cmd then
			say("error: " .. selftest.lastError.error)
			selftest.lastError = nil
		end
	elseif cmd == "" then
		status()
	else
		for _, line in ipairs(HELP) do
			say(line:format(ns.db.settings.radius))
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Interact key (CVar SoftTargetInteract, Options > Controls > "Enable Interact Key"). Chest detection will
-- need it on, and it keeps getting switched off. Say so loudly when it is off, offer /fr fixinteract, and
-- record who changed it: a Lua caller (from C_CVar.SetCVar; the global SetCVar is Blizzard's Lua wrapper in
-- Blizzard_SharedXMLBase/CvarUtil.lua, skipped when walking the stack for the caller) or,
-- with no Lua caller in the same frame, the client or the settings panel.
-- ---------------------------------------------------------------------------------------------------------
local INTERACT = "SoftTargetInteract"
local INTERACT_ON = "3" -- always on, as Lueur sets it
local lastLuaSet -- { value, by, at = GetTime() }
local selfSet = false -- true while FarmRoute itself calls SetCVar
local interactWarned

local function interactValue()
	local ok, v = pcall(C_CVar.GetCVar, INTERACT)
	return ok and v or nil
end

function ns.interactState()
	local v = interactValue()
	if v == nil then
		return { ok = false, value = "nil", why = INTERACT .. " not readable" }
	end
	-- 0 off, 1 gamepad only, 2 keyboard and mouse, 3 always: only 3 gives keyboard soft-interact (as Lueur needs)
	if v == INTERACT_ON then
		return { ok = true, value = v }
	end
	local what = v == "1" and "set to gamepad only" or (v == "0" and "off" or ("set to " .. v))
	return { ok = false, value = v, why = "Interact key is " .. what .. ": chest detection can't work" }
end

-- The addon folder of the first stack frame outside FarmRoute and Blizzard's CVar code.
local function callerAddon()
	local stack = debugstack(3, 12, 0) or ""
	for folder in stack:gmatch("AddOns[/\\]([^/\\]+)[/\\]") do
		if folder ~= ADDON and not folder:find("^Blizzard_SharedXML") then
			return folder
		end
	end
	return stack:find("AddOns", 1, true) and "Blizzard UI" or "unknown Lua"
end

local function logInteract(value, by)
	local log = ns.db.interactLog
	log[#log + 1] = { value = tostring(value), by = by, at = date("%Y-%m-%d %H:%M:%S") }
	while #log > 20 do
		table.remove(log, 1)
	end
end

local reasserts, fightWarned = {}, false
local REASSERT_MAX, REASSERT_WINDOW = 3, 10 -- more than 3 put-backs in 10 s: another addon is fighting us

-- /fr keepinteract on: put the key back to 3 whenever something changes it, outside combat. Stops and says
-- so when another addon keeps changing it back, instead of looping.
local pendingReassert = false -- a put-back skipped in combat, retried on PLAYER_REGEN_ENABLED
local pendingRestore = false -- /fr off in combat: the player's soft-target values go back after it

local function reassert(st)
	if not running or not ns.db.settings.keepInteract then
		return false
	end
	local last = ns.db.interactLog[#ns.db.interactLog] -- the change being undone, read before ours is logged
	-- the player's own change (Options > Controls, no Lua caller) is theirs to keep: only addon changes go back
	if last and last.by == "client or settings panel" and last.value == st.value then
		return false
	end
	if InCombatLockdown() then
		pendingReassert = true
		return false
	end
	local now = GetTime()
	for i = #reasserts, 1, -1 do
		if now - reasserts[i] > REASSERT_WINDOW then
			table.remove(reasserts, i)
		end
	end
	if #reasserts >= REASSERT_MAX then
		if not fightWarned then
			fightWarned = true
			say(
				"|cffff4040something keeps changing the interact key back; stopped putting it back.|r /fr interact shows who"
			)
		end
		return false
	end
	reasserts[#reasserts + 1] = now
	fightWarned = false
	selfSet = "FarmRoute (keepinteract)"
	local ok, err = pcall(C_CVar.SetCVar, INTERACT, INTERACT_ON)
	selfSet = false
	if not ok then
		say("couldn't put the interact key back: " .. tostring(err))
		return false
	end
	-- name the culprit only when the last logged change is the one being undone
	local by = last and last.value == st.value and (", set by " .. last.by) or ""
	say("interact key put back to 3 (was " .. st.value .. by .. ")")
	return ns.interactState().ok
end

function ns.resetReasserts()
	reasserts, fightWarned = {}, false
end

function ns.onCombatEnd()
	if pendingRestore then
		pendingRestore = false
		ns.restoreCVars()
	end
	if pendingReassert then
		pendingReassert = false
		ns.checkInteract("after combat")
	end
end

function ns.checkInteract(source)
	local st = ns.interactState()
	if st.ok or not running then
		interactWarned = false
		return st
	end
	if reassert(st) then
		return ns.interactState()
	end
	if not interactWarned then
		interactWarned = true
		local last = ns.db.interactLog[#ns.db.interactLog]
		local who = last and last.value ~= INTERACT_ON and (" (turned off by " .. last.by .. " at " .. last.at .. ")")
			or ""
		say("|cffff4040" .. st.why .. who .. ".|r Type /fr fixinteract to turn it on. [" .. source .. "]")
	end
	return st
end

-- CVAR_UPDATE may fire inside SetCVar, before the post-hook has recorded the caller: attribute next frame.
function ns.onCVarUpdate(name, value)
	if name ~= INTERACT then
		return
	end
	C_Timer.After(0, function()
		local by = "client or settings panel"
		if lastLuaSet and GetTime() - lastLuaSet.at < 0.5 then
			by = lastLuaSet.by
		end
		lastLuaSet = nil
		logInteract(value or interactValue(), by)
		ns.checkInteract("changed by " .. by)
	end)
end

function ns.hookInteract()
	ns.db.interactLog = ns.db.interactLog or {}
	hooksecurefunc(C_CVar, "SetCVar", function(name, value)
		if name == INTERACT then
			lastLuaSet = { value = value, by = selfSet and tostring(selfSet) or callerAddon(), at = GetTime() }
		end
	end)
	-- Blizzard's gamepad code sets the key through temporary CVars (Blizzard_GamepadTargeting/TargetLogic.lua)
	if C_CVar.SetTempCVar then
		hooksecurefunc(C_CVar, "SetTempCVar", function(name, value)
			if name == INTERACT then
				lastLuaSet = { value = value, by = callerAddon() .. " (temporary CVar)", at = GetTime() }
			end
		end)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Detection health: what soft-interact detection needs, shown on screen with a Fix button (HUD.lua). The
-- player's own values are saved before the first fix and put back by /fr off and /fr restorecvars.
-- ---------------------------------------------------------------------------------------------------------
local MIN_RANGE, FIX_RANGE = 15, 20
local health -- the last state shown

local function cvar(name)
	local ok, v = pcall(C_CVar.GetCVar, name)
	return ok and v or nil
end

function ns.healthState()
	local st = ns.interactState()
	if not st.ok then
		local last = ns.db.interactLog[#ns.db.interactLog]
		local detail = last and last.value ~= INTERACT_ON and ("turned off by " .. last.by .. " at " .. last.at) or nil
		local line = st.value == "1" and "Interact key is gamepad only: detection disabled"
			or "Interact key is off: detection disabled"
		return { ok = false, line = line, detail = detail, key = "interact" .. st.value }
	end
	if cvar("SoftTargetInteractOnlyInRange") == "1" then
		return {
			ok = false,
			line = "Detection only within interact range",
			detail = "SoftTargetInteractOnlyInRange is 1",
			key = "onlyInRange",
		}
	end
	local range = tonumber(cvar("SoftTargetInteractRange"))
	if range and range < MIN_RANGE then
		return {
			ok = false,
			line = string.format("Detection range is only %d yd", range),
			detail = "SoftTargetInteractRange; Fix sets " .. FIX_RANGE,
			key = "range" .. range,
		}
	end
	return { ok = true, key = "ok" }
end

-- Called every tick; draws only on a change.
function ns.updateHealth()
	-- stopped: FarmRoute needs nothing, and /fr off has just put the player's own values back
	local h = running and ns.healthState() or { ok = true, key = "stopped" }
	h.canFix = not h.ok
	h.fixBlocked = InCombatLockdown() and "in combat" or nil
	local key = h.key .. tostring(h.fixBlocked)
	if health and health.shownKey == key then
		return
	end
	h.shownKey = key
	health = h
	if ns.healthFrame then
		ns.healthFrame:Apply(h)
	end
end

local function setOwn(name, value)
	if ns.db.savedCVars[name] == nil then
		ns.db.savedCVars[name] = cvar(name) or false
	end
	selfSet = "FarmRoute (/fr fixinteract)"
	local ok, err = pcall(C_CVar.SetCVar, name, tostring(value))
	selfSet = false
	return ok, err
end

-- The Fix button and /fr fixinteract: the key on, detection beyond interact range, a usable range.
function ns.fixDetection()
	if InCombatLockdown() then
		say("in combat: detection can be fixed after combat")
		return false
	end
	ns.db.savedCVars = ns.db.savedCVars or {}
	local ok, err = setOwn(INTERACT, INTERACT_ON)
	if cvar("SoftTargetInteractOnlyInRange") == "1" then
		setOwn("SoftTargetInteractOnlyInRange", 0)
	end
	local range = tonumber(cvar("SoftTargetInteractRange"))
	if range and range < MIN_RANGE then
		setOwn("SoftTargetInteractRange", FIX_RANGE)
	end
	local h = ns.healthState()
	if ok and h.ok then
		say(
			"detection on ("
				.. INTERACT
				.. " = "
				.. cvar(INTERACT)
				.. ", range "
				.. tostring(cvar("SoftTargetInteractRange"))
				.. ")"
		)
	else
		say("couldn't fix detection: " .. tostring(err or h.line))
	end
	ns.updateHealth()
	return h.ok
end

-- Puts back the values the player had before the first fix.
function ns.restoreCVars(quiet)
	local saved = ns.db.savedCVars
	if not saved or not next(saved) then
		return false
	end
	if InCombatLockdown() then
		pendingRestore = true
		say("in combat: your soft-target settings are put back after combat")
		return false
	end
	for name, value in pairs(saved) do
		if value ~= false then
			pcall(C_CVar.SetCVar, name, value)
		end
	end
	ns.db.savedCVars = nil
	if not quiet then
		say("your soft-target settings are back as they were")
	end
	return true
end

function commands.fixinteract()
	ns.fixDetection()
end

function commands.restorecvars()
	if not ns.restoreCVars() then
		say("nothing to put back")
	end
end

function commands.interact()
	local st = ns.interactState()
	say(INTERACT .. " = " .. st.value .. (st.ok and " (on)" or " (off: /fr fixinteract)"))
	for i = math.max(1, #ns.db.interactLog - 4), #ns.db.interactLog do
		local e = ns.db.interactLog[i]
		say("  " .. e.at .. ": " .. e.value .. " by " .. e.by)
	end
end

BINDING_HEADER_FARMROUTE = "FarmRoute"
BINDING_NAME_FARMROUTE_NEXT = "Next point"
BINDING_NAME_FARMROUTE_PREV = "Previous point"
BINDING_NAME_FARMROUTE_SKIP = "Skip this point"

-- ---------------------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("LOOT_OPENED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.initDB(FarmRouteDB)
			guard("hookInteract", ns.hookInteract)
			guard("hookTooltips", ns.Detect.hookTooltips)
		end
	elseif event == "CVAR_UPDATE" then
		if ns.db then
			guard("cvar", ns.onCVarUpdate, ...)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- the client resets some soft-target CVars around this event: look a few seconds later
		C_Timer.After(3, function()
			guard("checkInteract", ns.checkInteract, "after loading")
		end)
	elseif event == "PLAYER_LOGIN" then
		selftest.loadedAt = date("%Y-%m-%d %H:%M:%S")
		L.pruneTimers(ns.timersFor(ns.db.active or ""), time())
		guard("screenLine", Nav.initScreenLine)
		guard("healthFrame", function()
			ns.healthFrame = ns.HUD.buildHealth(UIParent)
		end)
		guard("mapLines", MapLines.initWorld)
		running = ns.db.running == true
		guard("place", place)
		C_Timer.NewTicker(TICK, function()
			guard("tick", tick)
		end)
		guard("snapshot", selftest.snapshot, "login")
	elseif event == "LOOT_OPENED" then
		if ns.db then
			guard("lootOpened", ns.onLootOpened)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.db then
			guard("combatEnd", ns.onCombatEnd)
		end
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		if ns.db then
			guard("softChanged", ns.Detect.update, "event")
		end
	elseif event == "PLAYER_LOGOUT" then
		guard("snapshot", selftest.snapshot, "logout")
	elseif event == "NAVIGATION_DESTINATION_REACHED" then
		-- Blizzard clears a reached user waypoint in its own handler; move on after it has run.
		if running and Nav.ownsPin() and ns.db.settings.autoAdvance then
			local reached = ns.pinIndex()
			C_Timer.After(0, function()
				-- a reached via only moves the pin on (if the tick hasn't already); the chest is checked by the
				-- arrival logic
				if reached ~= ns.currentIndex() then
					if ns.pinIndex() == reached and via.list[via.at] == reached then
						via.at = via.at + 1
					end
					guard("place", place)
				elseif GetTime() - lastAdvance >= MIN_GAP then
					guard("navReached", ns.advance, 1, "advanceNavReached")
				end
			end)
		end
	end
end)
