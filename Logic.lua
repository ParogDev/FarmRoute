-- Route logic with no client calls: the seed routes, TomTom /way parsing, which point comes next (respawn
-- timers skip points that are not up yet), and plane distance. Everything here runs under busted.
local _, ns = ...

local L = {}
ns.Logic = L

L.DEFAULT_RADIUS = 8 -- yards: a point counts as reached inside this
L.MIN_RADIUS = 2
L.MAX_RADIUS = 50

-- ---------------------------------------------------------------------------------------------------------
-- Seed: Angor Fortress, Badlands (uiMapID 1418). Spawn coordinates from Wowhead's Forever object pages
-- 179490 (Battered Footlocker, upper floor) and 179492 (Dented Footlocker, lower floor).
-- ---------------------------------------------------------------------------------------------------------
local BADLANDS = 1418

local function seedRoute(name, label, floor, coords, mapID)
	local points = {}
	for i, c in ipairs(coords) do
		points[i] =
			{ mapID = mapID or BADLANDS, x = c[1] / 100, y = c[2] / 100, label = label .. " " .. i, floor = floor }
	end
	return { name = name, points = points, respawn = 0 }
end

-- ---------------------------------------------------------------------------------------------------------
-- Seed: Floating Wreckage fishing pools, one route per zone. Spawn coordinates from Forever Questlog's object
-- pages 180662 (Watertight Trunk, tier 2), 180685 (Iron Bound Trunk, tier 3), 180751 and 180901 (Mithril
-- Bound Trunk, tier 4); the order is a short loop along the shore. A pool is out in the water and the client
-- can't soft-target it, so these routes arrive from the shore (WRECKAGE_RADIUS) and keep no visit history
-- (detect = false): every spot stays in the loop.
-- ---------------------------------------------------------------------------------------------------------
L.WRECKAGE_RADIUS = 20

local WRECKAGE = {
	{
		name = "Wreckage T2 Wetlands",
		mapID = 1437,
		object = 180662,
		coords = {
			{ 33.1, 11.3 },
			{ 32.0, 12.4 },
			{ 28.9, 15.5 },
			{ 27.7, 17.3 },
			{ 25.7, 19.0 },
			{ 14.2, 43.8 },
			{ 12.8, 61.5 },
			{ 10.8, 63.1 },
			{ 7.8, 63.0 },
			{ 5.9, 62.6 },
			{ 5.3, 58.4 },
			{ 5.9, 56.6 },
			{ 6.9, 56.7 },
			{ 6.7, 54.5 },
			{ 12.2, 44.0 },
			{ 12.1, 40.5 },
			{ 12.1, 38.6 },
			{ 12.4, 36.1 },
			{ 12.7, 33.5 },
			{ 13.3, 31.6 },
			{ 14.9, 27.5 },
			{ 15.7, 26.2 },
			{ 17.9, 22.0 },
			{ 18.7, 20.8 },
			{ 19.9, 20.2 },
			{ 21.5, 19.4 },
		},
	},
	{
		name = "Wreckage T2 Hillsbrad",
		mapID = 1424,
		object = 180662,
		coords = {
			{ 55.1, 60.8 },
			{ 55.5, 65.2 },
			{ 56.3, 67.4 },
			{ 57.5, 69.8 },
			{ 58.2, 73.6 },
			{ 59.4, 75.0 },
			{ 61.7, 78.0 },
			{ 64.3, 79.9 },
			{ 65.0, 83.3 },
			{ 65.7, 85.7 },
			{ 67.7, 87.9 },
			{ 28.3, 73.9 },
			{ 24.3, 68.3 },
			{ 22.8, 64.9 },
			{ 34.4, 70.0 },
			{ 35.9, 70.4 },
			{ 38.0, 70.7 },
			{ 40.1, 70.7 },
			{ 42.3, 70.4 },
			{ 43.9, 68.8 },
			{ 46.0, 67.2 },
			{ 49.7, 63.2 },
			{ 50.7, 62.4 },
			{ 51.1, 62.5 },
		},
	},
	{
		name = "Wreckage T3 Barrens",
		mapID = 1413,
		object = 180685,
		coords = {
			{ 64.5, 56.1 },
			{ 63.4, 59.3 },
			{ 63.9, 58.8 },
			{ 64.3, 57.8 },
			{ 64.5, 56.9 },
		},
	},
	{
		name = "Wreckage T4 Tanaris",
		mapID = 1446,
		object = 180751,
		coords = {
			{ 66.6, 18.2 },
			{ 67.9, 22.6 },
			{ 67.9, 23.4 },
			{ 67.4, 24.9 },
			{ 67.5, 25.7 },
			{ 67.9, 27.2 },
			{ 68.1, 28.3 },
			{ 68.1, 29.5 },
			{ 68.5, 34.6 },
			{ 67.7, 35.7 },
			{ 68.0, 36.8 },
			{ 67.5, 37.8 },
			{ 67.5, 38.9 },
			{ 68.2, 39.5 },
			{ 65.4, 60.2 },
			{ 65.1, 61.2 },
			{ 66.2, 60.3 },
			{ 69.9, 56.2 },
			{ 73.2, 51.4 },
			{ 73.7, 50.3 },
			{ 74.1, 49.6 },
			{ 74.7, 49.0 },
			{ 75.5, 47.1 },
			{ 73.0, 44.2 },
			{ 72.7, 43.9 },
			{ 72.1, 42.9 },
			{ 71.4, 41.8 },
			{ 71.3, 41.1 },
			{ 71.1, 40.3 },
			{ 68.6, 23.0 },
			{ 67.7, 21.0 },
			{ 67.4, 19.4 },
		},
	},
	{
		name = "Wreckage T4 Feralas",
		mapID = 1444,
		object = 180751,
		coords = {
			{ 33.6, 32.4 },
			{ 34.4, 34.2 },
			{ 35.1, 35.3 },
			{ 36.8, 36.3 },
			{ 39.5, 37.2 },
			{ 40.6, 38.6 },
			{ 41.7, 39.8 },
			{ 42.9, 40.2 },
			{ 44.2, 43.5 },
			{ 44.1, 45.1 },
			{ 44.2, 46.5 },
			{ 44.4, 47.8 },
			{ 44.1, 49.3 },
			{ 44.1, 51.0 },
			{ 45.0, 52.5 },
			{ 46.1, 53.8 },
			{ 47.9, 53.1 },
			{ 49.3, 53.5 },
			{ 49.6, 52.3 },
			{ 48.0, 50.8 },
			{ 44.2, 41.6 },
			{ 44.3, 40.4 },
			{ 44.0, 40.1 },
			{ 38.8, 33.8 },
		},
	},
	{
		name = "Wreckage T4 Stranglethorn",
		mapID = 1434,
		object = 180901,
		coords = {
			{ 34.7, 34.2 },
			{ 32.4, 35.5 },
			{ 31.8, 36.5 },
			{ 29.4, 37.2 },
			{ 28.9, 37.7 },
			{ 27.9, 39.0 },
			{ 26.9, 40.9 },
			{ 27.1, 42.3 },
			{ 26.9, 44.5 },
			{ 27.2, 46.6 },
			{ 26.0, 48.6 },
			{ 24.6, 49.9 },
			{ 23.8, 47.4 },
			{ 22.7, 48.8 },
			{ 22.1, 51.1 },
			{ 22.5, 52.8 },
			{ 22.1, 55.2 },
			{ 22.8, 56.4 },
			{ 26.2, 58.3 },
			{ 24.3, 59.4 },
			{ 23.8, 61.4 },
			{ 23.7, 63.1 },
			{ 23.9, 65.4 },
			{ 25.4, 66.8 },
			{ 26.7, 69.9 },
			{ 26.5, 74.1 },
			{ 27.3, 74.7 },
			{ 27.9, 76.0 },
			{ 27.5, 76.5 },
			{ 26.1, 82.5 },
			{ 26.5, 84.7 },
			{ 27.8, 83.5 },
			{ 29.3, 83.6 },
			{ 30.7, 83.2 },
			{ 31.7, 82.0 },
			{ 32.6, 80.6 },
			{ 33.7, 78.0 },
			{ 34.0, 74.7 },
			{ 36.4, 69.9 },
			{ 38.5, 62.8 },
			{ 41.1, 60.5 },
			{ 41.4, 59.4 },
			{ 41.7, 57.9 },
			{ 34.2, 36.6 },
			{ 35.1, 36.0 },
		},
	},
}

-- ---------------------------------------------------------------------------------------------------------
-- The route picker's view of a route: what it farms, where, and the group it is listed under.
-- ---------------------------------------------------------------------------------------------------------
L.TRUNKS = {
	[180662] = "Watertight Trunk",
	[180685] = "Iron Bound Trunk",
	[180751] = "Mithril Bound Trunk",
	[180901] = "Mithril Bound Trunk",
}

-- Where on the zone map the spots are, in words: the picker shows it under the route.
L.WHERE = {
	["Wreckage T2 Wetlands"] = "West coast, from Menethil Harbor up to the north shore.",
	["Wreckage T2 Hillsbrad"] = "South coast, on both sides of Southshore.",
	["Wreckage T3 Barrens"] = "East coast south of Ratchet. Five spots close together.",
	["Wreckage T4 Tanaris"] = "East coast, from northeast of Gadgetzan down past Lost Rigger Cove.",
	["Wreckage T4 Feralas"] = "The Forgotten Coast: the mainland shore across from Feathermoon.",
	["Wreckage T4 Stranglethorn"] = "The whole west coast, down past Booty Bay and round the southern tip.",
	["Angor Battered"] = "Angor Fortress, upper floor.",
	["Angor Dented"] = "Angor Fortress, lower floor.",
}

L.GROUPS = { "Fishing: Floating Wreckage", "Lockpicking", "Your routes" }

-- { name, group, tier, trunk, where, mapID, count } for a saved route.
function L.routeInfo(route)
	local info = { name = route.name, count = #route.points, where = L.WHERE[route.name] }
	local p = route.points[1]
	info.mapID = p and p.mapID
	local tier = route.name:match("^Wreckage T(%d) ")
	if tier then
		info.group, info.tier = L.GROUPS[1], tonumber(tier)
		local ids = {}
		for id in pairs(route.objects or {}) do
			ids[#ids + 1] = id
		end
		table.sort(ids) -- pairs has no order: the lowest id names the trunk, the same after every reload
		for _, id in ipairs(ids) do
			info.trunk = info.trunk or L.TRUNKS[id]
		end
	elseif route.name:match("^Angor ") then
		info.group = L.GROUPS[2]
	else
		info.group = L.GROUPS[3]
	end
	return info
end

-- The picker's rows: { header = group } then that group's routes, in L.GROUPS order; wreckage by tier, then
-- name. A group with no routes has no header.
function L.pickerRows(routes)
	local by = {}
	for _, r in pairs(routes) do
		local info = L.routeInfo(r)
		by[info.group] = by[info.group] or {}
		table.insert(by[info.group], info)
	end
	local rows = {}
	for _, g in ipairs(L.GROUPS) do
		local list = by[g]
		if list then
			table.sort(list, function(a, b)
				if (a.tier or 0) ~= (b.tier or 0) then
					return (a.tier or 0) < (b.tier or 0)
				end
				return a.name < b.name
			end)
			rows[#rows + 1] = { header = g }
			for _, info in ipairs(list) do
				rows[#rows + 1] = info
			end
		end
	end
	return rows
end

-- The routes every install got before seeds were tracked by name (0.3.1 and older).
L.LEGACY_SEEDS = { "Angor Battered", "Angor Dented" }

-- The arrival radius of a route: its own (wreckage routes) or the setting.
function L.radiusOf(route, settings)
	return route and route.radius or settings.radius
end

-- Whether arriving at or skipping a point records a visit. Off for routes whose objects the client can't
-- detect: every visit would count as empty and the spots would go cold.
function L.tracksVisits(route)
	return not (route and route.detect == false)
end

function L.seedRoutes()
	local routes = {
		seedRoute("Angor Battered", "Battered", "upstairs", {
			{ 40.8, 26.7 },
			{ 41.4, 26.3 },
			{ 42.2, 27.3 },
			{ 42.3, 27.8 },
			{ 42.2, 28.7 },
			{ 43.3, 28.6 },
			{ 43.5, 30.5 },
			{ 42.1, 30.9 },
			{ 42.4, 29.6 },
			{ 41.4, 29.8 },
			{ 40.9, 29.2 },
			{ 40.3, 28.5 },
			{ 40.3, 27.5 },
			{ 40.9, 27.5 },
		}),
		seedRoute("Angor Dented", "Dented", "downstairs", {
			{ 41.4, 27.2 },
			{ 42.1, 27.0 },
			{ 42.0, 28.3 },
			{ 41.8, 29.1 },
			{ 40.7, 28.8 },
			{ 40.8, 28.1 },
			{ 39.7, 27.6 },
		}),
	}
	for _, w in ipairs(WRECKAGE) do
		local r = seedRoute(w.name, "Wreckage", nil, w.coords, w.mapID)
		r.objects = { [w.object] = true }
		r.radius = L.WRECKAGE_RADIUS
		r.detect = false
		routes[#routes + 1] = r
	end
	return routes
end

-- ---------------------------------------------------------------------------------------------------------
-- TomTom /way lines
-- ---------------------------------------------------------------------------------------------------------
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One line: "/way [#mapID | zone name] x y [label]", x and y in percent ("40.8 26.7", "40.8, 26.7", "40,8 26,7").
-- resolveZone(name) returns a uiMapID for a zone name or nil. Returns a point, or nil and why.
function L.parseWay(line, defaultMap, resolveZone)
	if type(line) ~= "string" then
		return nil, "not a string"
	end
	local s = trim(line)
	if s == "" then
		return nil, "empty"
	end
	s = s:gsub("^/[%a]*way%s*", "")
	local mapID
	local id, rest = s:match("^#(%d+)%s*(.*)$")
	if id then
		mapID, s = tonumber(id), rest
	end
	-- "40,8 26,7": a comma between digits with no space is a decimal comma
	s = s:gsub("(%d),(%d)", "%1.%2")
	local before, x, y, label = s:match("^(.-)%s*(%d+%.?%d*)[,%s]+(%d+%.?%d*)%s*(.*)$")
	if not x then
		return nil, "no x y coordinates"
	end
	before = trim(before or "")
	if before ~= "" then
		if mapID then
			return nil, "text between #" .. mapID .. " and the coordinates: " .. before
		end
		mapID = resolveZone and resolveZone(before)
		if not mapID then
			return nil, "zone '" .. before .. "' not resolved: write /way #<uiMapID> x y"
		end
	end
	mapID = mapID or defaultMap
	if not mapID then
		return nil, "no map: write /way #<uiMapID> x y"
	end
	x, y = tonumber(x), tonumber(y)
	if x > 100 or y > 100 then
		return nil, "coordinates over 100"
	end
	label = trim(label or "")
	return { mapID = mapID, x = x / 100, y = y / 100, label = label ~= "" and label or nil }
end

-- A paste: one /way per line, blank lines skipped. Returns points and a list of { line = n, why = ... }.
function L.parseImport(text, defaultMap, resolveZone)
	local points, errors = {}, {}
	if type(text) ~= "string" then
		return points, { { line = 0, why = "not a string" } }
	end
	local n = 0
	for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		n = n + 1
		if trim(line) ~= "" then
			local p, why = L.parseWay(line, defaultMap, resolveZone)
			if p then
				points[#points + 1] = p
			else
				errors[#errors + 1] = { line = n, why = why }
			end
		end
	end
	return points, errors
end

-- ---------------------------------------------------------------------------------------------------------
-- Walking the loop
-- ---------------------------------------------------------------------------------------------------------
function L.wrap(i, n)
	return ((i - 1) % n) + 1
end

-- Minutes a point stays down after it is passed: its own setting, else the route's. 0 = no timer.
function L.respawnOf(route, i)
	local p = route.points[i]
	local m = p and p.respawn or route.respawn
	return (type(m) == "number" and m > 0) and m or 0
end

function L.isUp(timers, i, now)
	local t = timers and timers[i]
	return not t or t <= now
end

-- The next point from `from` in direction dir (+1 / -1) that is up. All down: the one up soonest, and
-- waiting = true. Returns nil for an empty route. Path points are never a stop; with hist, dropped seeds
-- aren't either (unless nothing else is left).
function L.nextIndex(route, timers, from, dir, now, hist)
	local n = #route.points
	if n == 0 then
		return nil
	end
	from = from or (dir > 0 and 0 or 1)
	local strict = false
	for i = 1, n do
		if L.inLoop(route, hist, i) then
			strict = true
			break
		end
	end
	local soonest, soonestAt
	for k = 1, n do
		local i = L.wrap(from + dir * k, n)
		local stop = strict and L.inLoop(route, hist, i) or (not strict and not L.isPath(route.points[i]))
		if stop then
			if L.isUp(timers, i, now) then
				return i, false
			end
			if not soonestAt or timers[i] < soonestAt then
				soonest, soonestAt = i, timers[i]
			end
		end
	end
	return soonest, soonest ~= nil
end

-- Moves the route on. Forward past a point starts its respawn timer (timers hold epoch seconds, so they
-- survive a reload); going back starts none. Returns the new index and whether every point is down.
function L.advance(route, timers, current, dir, now)
	local n = #route.points
	if n == 0 then
		return nil, false
	end
	if dir > 0 and current and route.points[current] then
		local m = L.respawnOf(route, current)
		if m > 0 then
			timers[current] = now + m * 60
		end
	end
	return L.nextIndex(route, timers, current, dir, now)
end

-- Drops timers that have run out, so the SavedVariables stay small.
function L.pruneTimers(timers, now)
	for i, t in pairs(timers) do
		if t <= now then
			timers[i] = nil
		end
	end
end

function L.clampRadius(r)
	r = tonumber(r)
	if not r then
		return nil
	end
	return math.max(L.MIN_RADIUS, math.min(L.MAX_RADIUS, r))
end

function L.distance(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

-- Points every `step` yards along a -> b (world yards in, fractions 0..1 out), ends excluded.
function L.dotFractions(lengthYards, step)
	local out = {}
	if not lengthYards or lengthYards <= 0 or not step or step <= 0 then
		return out
	end
	local count = math.floor(lengthYards / step)
	for k = 1, count do
		local f = k * step / lengthYards
		if f < 1 then
			out[#out + 1] = f
		end
	end
	return out
end

-- The segment whose end is the current point: the stretch being walked now.
function L.isCurrentSegment(n, current, a, b)
	if not current or n < 2 then
		return false
	end
	return b == current and a == L.wrap(current - 1, n)
end

-- ---------------------------------------------------------------------------------------------------------
-- Soft-interact reading (no client calls: the strings come in from Detect.lua)
-- ---------------------------------------------------------------------------------------------------------

-- The object id in a game object GUID ("GameObject-0-server-instance-zone-ID-spawn"), or nil.
function L.guidObject(guid)
	if type(guid) ~= "string" then
		return nil
	end
	return tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

-- A Lua pattern from a format string such as ITEM_MIN_SKILL ("Requires %s (%d)"), capturing the skill name
-- and the level. Positional forms ("%1$s") are taken too.
function L.requiresPattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then
		fmt = "Requires %s (%d)"
	end
	local p = fmt:gsub("%%%d?%$?([sd])", "\1%1")
	p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("\1s", "(.-)")
	p = p:gsub("\1d", "(%%d+)")
	return "^" .. p .. "$"
end

-- The first tooltip line matching the pattern: skill name, level; or nil.
function L.parseRequires(texts, pattern)
	for _, t in ipairs(texts or {}) do
		if type(t) == "string" then
			local skill, level = t:match(pattern)
			if skill and tonumber(level) then
				return skill, tonumber(level)
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- Objective: which spawn to check next. A loop checks every point once; a point is checked when the player
-- reached it (chest looted or nothing there) or skipped it. History keeps, per point, whether a chest was
-- there on each visit; a "cold" point (empty on its last COLD_VISITS visits) is passed over while warm points
-- are left, and checked again once it has been passed over COLD_REST loops.
-- ---------------------------------------------------------------------------------------------------------
L.HISTORY_MAX = 12
L.COLD_VISITS = 3
L.COLD_REST = 2

-- Object ids of the seed routes' chests (Wowhead Forever object pages).
L.SEED_OBJECTS = {
	["Angor Battered"] = { [179490] = true },
	["Angor Dented"] = { [179492] = true },
}

-- Does a soft-interact target belong to this route? A route with an object list takes those ids only; one
-- without takes anything whose tooltip asks for a skill (a locked chest).
function L.matchesRoute(route, objectID, need)
	if type(route.objects) == "table" and next(route.objects) then
		return objectID ~= nil and route.objects[objectID] == true
	end
	return need ~= nil
end

function L.recordVisit(hist, i, seen, now)
	local h = hist[i] or { visits = {} }
	hist[i] = h
	L.push(h.visits, { t = now, seen = seen and true or false }, L.HISTORY_MAX)
	if seen then
		h.lastSeen = now
		h.rested = nil
	end
	return h
end

function L.isCold(hist, i)
	local h = hist and hist[i]
	if not h or #h.visits < L.COLD_VISITS then
		return false
	end
	for k = #h.visits - L.COLD_VISITS + 1, #h.visits do
		if h.visits[k].seen then
			return false
		end
	end
	return (h.rested or 0) < L.COLD_REST
end

-- Seen / visits for a point, for /fr list and the selftest.
function L.seenRate(hist, i)
	local h = hist and hist[i]
	if not h then
		return 0, 0
	end
	local seen = 0
	for _, v in ipairs(h.visits) do
		if v.seen then
			seen = seen + 1
		end
	end
	return seen, #h.visits
end

-- The next point after `from` (forward, wrapping) that is up, not checked this loop and not cold. Returns the
-- index and why: "next", "cold" (only cold points were left: the first cold one), or nil, "loop done".
function L.objective(route, timers, checked, hist, from, now)
	local n = #route.points
	if n == 0 then
		return nil, "empty route"
	end
	from = from or 0
	local firstCold
	for k = 1, n do
		local i = L.wrap(from + k, n)
		if not checked[i] and L.inLoop(route, hist, i) and L.isUp(timers, i, now) then
			if not L.isCold(hist, i) then
				return i, "next"
			end
			firstCold = firstCold or i
		end
	end
	if firstCold then
		return firstCold, "cold"
	end
	return nil, "loop done"
end

-- A new loop: cold points that were passed over get one rest counted; the checked set empties.
function L.newLoop(route, checked, hist)
	for i = 1, #route.points do
		if not L.inLoop(route, hist, i) then -- luacheck: ignore 542
			-- path points and dropped seeds are never checked and never rest
		elseif not checked[i] and L.isCold(hist, i) then
			local h = hist[i]
			h.rested = (h.rested or 0) + 1
		elseif checked[i] and hist[i] and (hist[i].rested or 0) >= L.COLD_REST then
			hist[i].rested = nil
		end
	end
	for k in pairs(checked) do
		checked[k] = nil
	end
end

-- The route point nearest to (x, y) in world yards within maxYd; points is a list of { i, x, y }.
function L.nearestIndex(points, x, y, maxYd)
	local best, bestD
	for _, p in ipairs(points) do
		local d = L.distance(x, y, p.x, p.y)
		if d <= maxYd and (not bestD or d < bestD) then
			best, bestD = p.i, d
		end
	end
	return best, bestD
end

-- Appends to a list kept at most max long (oldest dropped).
function L.push(list, item, max)
	list[#list + 1] = item
	while #list > max do
		table.remove(list, 1)
	end
	return item
end

function L.formatPoint(route, i)
	local p = route.points[i]
	if not p then
		return "?"
	end
	local s = string.format("%d/%d %s (%.1f, %.1f)", i, #route.points, p.label or "point", p.x * 100, p.y * 100)
	if p.floor then
		s = s .. " " .. p.floor
	end
	if L.isPath(p) then
		s = s .. " path"
	elseif L.isConfirmed(p) then
		s = s .. " learned x" .. p.finds
	end
	return s
end

-- ---------------------------------------------------------------------------------------------------------
-- Learned chest points and point kinds. A route point is a chest spawn (kind nil or "chest") or a path point
-- (kind "path": a via-point the pin passes through, never checked). A chest point is confirmed once a loot
-- landed on it (p.finds); seed and imported coordinates stay unconfirmed until then, and an unconfirmed one
-- empty on its last DROP_VISITS visits leaves the loop once the route has confirmed points. Points added by
-- hand (p.manual) are never dropped. Geometry here is in world yards: callers convert map positions.
-- ---------------------------------------------------------------------------------------------------------
L.MERGE_YD = 8 -- a find this close to a confirmed point is the same spawn (looted from any side of it)
L.FIND_MAX_YD = 60 -- a find further than this from every point of a route belongs to another place
L.SEED_YD = 15 -- seed coordinates were measured up to 14 yd off the real spawn
L.DROP_VISITS = 6
L.LEARN_STEP = 3 -- yards between two path samples
L.LEARN_TOLERANCE = 3 -- Douglas-Peucker tolerance, yards
L.VISIT_YD = 6 -- a walk passes a chest point inside this
L.TRAIL_GAP_YD = 25 -- two learn samples further apart than this were not walked in between

function L.isPath(p)
	return p ~= nil and p.kind == "path"
end

function L.isConfirmed(p)
	return p ~= nil and not L.isPath(p) and type(p.finds) == "number" and p.finds >= 1
end

function L.isUnconfirmed(p)
	return p ~= nil and not L.isPath(p) and not L.isConfirmed(p) and not p.manual
end

local function hasConfirmed(route)
	for _, p in ipairs(route.points) do
		if L.isConfirmed(p) then
			return true
		end
	end
	return false
end

function L.isDropped(route, hist, i)
	if not L.isUnconfirmed(route.points[i]) then
		return false
	end
	local h = hist and hist[i]
	if not h or #h.visits < L.DROP_VISITS then
		return false
	end
	for k = #h.visits - L.DROP_VISITS + 1, #h.visits do
		if h.visits[k].seen then
			return false
		end
	end
	return hasConfirmed(route)
end

-- Is point i a stop of the loop (a chest point not dropped)?
function L.inLoop(route, hist, i)
	local p = route.points[i]
	return p ~= nil and not L.isPath(p) and not L.isDropped(route, hist, i)
end

-- "chest" | "unconfirmed" | "dropped" | "path", for the maps and /fr list. Only a real loot makes a chest:
-- a point added by hand with no find yet is unconfirmed too (it just never drops).
function L.pointStatus(route, hist, i)
	local p = route.points[i]
	if L.isPath(p) then
		return "path"
	end
	if L.isDropped(route, hist, i) then
		return "dropped"
	end
	return L.isConfirmed(p) and "chest" or "unconfirmed"
end

-- The stop the pin is at, from the stored index i: 1 when i is gone, and a path point stored there (an edited
-- route) moves on to the next chest still in the loop (hist: dropped seeds are skipped too).
function L.currentStop(route, i, hist)
	if #route.points == 0 then
		return nil
	end
	if not i or not route.points[i] then
		i = 1
	end
	if L.isPath(route.points[i]) or not L.inLoop(route, hist, i) then
		return L.nextIndex(route, {}, i, 1, 0, hist) or i
	end
	return i
end

-- Where a find (a looted chest at x, y) goes. list: { { i, x, y } } in yards, one entry per route point.
-- Returns "merge", i (a confirmed point within MERGE_YD), "confirm", i (the nearest unconfirmed point within
-- SEED_YD: its coordinate is replaced), or "new", pos (insert at route index pos, the cheapest place in the
-- loop).
function L.findTarget(route, list, x, y)
	local mi, md, ui, ud, nearest
	for _, e in ipairs(list) do
		local p = route.points[e.i]
		local d = L.distance(x, y, e.x, e.y)
		nearest = math.min(nearest or d, d)
		-- a point added by hand with no find yet is confirmed by the first one like a seed
		local unconfirmed = L.isUnconfirmed(p) or (p.manual and not L.isConfirmed(p) and not L.isPath(p))
		if L.isConfirmed(p) and d <= L.MERGE_YD and (not md or d < md) then
			mi, md = e.i, d
		elseif unconfirmed and d <= L.SEED_YD and (not ud or d < ud) then
			ui, ud = e.i, d
		end
	end
	if mi then
		return "merge", mi, md
	end
	if ui then
		return "confirm", ui, ud
	end
	-- no point of the route on this continent, or none near: the same chest kind somewhere else
	if #list == 0 or nearest > L.FIND_MAX_YD then
		return "far", nil, nearest
	end
	return "new", L.insertionIndex(list, x, y)
end

-- A find on point p at map position (mx, my): the first replaces an unconfirmed coordinate, later ones move
-- the point to the running mean.
function L.mergeFind(p, mx, my)
	local n = L.isConfirmed(p) and p.finds or 0
	if n == 0 then
		p.x, p.y = mx, my
	else
		p.x = (p.x * n + mx) / (n + 1)
		p.y = (p.y * n + my) / (n + 1)
	end
	p.finds = n + 1
	return p
end

-- The route index a new point at (x, y) goes to so the loop grows least. list: { { i, x, y } } in route order.
function L.insertionIndex(list, x, y)
	local n = #list
	if n == 0 then
		return 1
	end
	if n == 1 then
		return list[1].i + 1
	end
	local best, bestCost
	for k = 1, n do
		local a, b = list[k], list[L.wrap(k + 1, n)]
		local cost = L.distance(a.x, a.y, x, y) + L.distance(x, y, b.x, b.y) - L.distance(a.x, a.y, b.x, b.y)
		if not bestCost or cost < bestCost then
			best, bestCost = a.i + 1, cost
		end
	end
	return best
end

-- Index maps for keyed-by-point tables (history, checked, timers): old index -> new index, nil = gone.
function L.insertMap(n, at)
	local map = {}
	for i = 1, n do
		map[i] = i < at and i or i + 1
	end
	return map
end

function L.removeMap(n, at)
	local map = {}
	for i = 1, n do
		if i ~= at then
			map[i] = i < at and i or i - 1
		end
	end
	return map
end

function L.remap(t, map)
	local out = {}
	for k, v in pairs(t or {}) do
		local nk = type(k) == "number" and map[k] or nil
		if nk then
			out[nk] = v
		end
	end
	return out
end

-- Where a stored index goes under an old -> new map: its own new index, or, when that point is gone, the
-- new index of the first surviving point after it in the old loop. nil only when nothing survives.
function L.remapIndex(i, map)
	if not i then
		return nil
	end
	if map[i] then
		return map[i]
	end
	local n = i
	for k in pairs(map) do
		if type(k) == "number" and k > n then
			n = k
		end
	end
	for k = 1, n - 1 do
		local nk = map[L.wrap(i + k, n)]
		if nk then
			return nk
		end
	end
	return nil
end

-- Path points between chest `from` and chest `to` going forward: the vias of that stretch.
function L.viasBetween(route, from, to)
	local out, n = {}, #route.points
	if not from or not to or n == 0 then
		return out
	end
	-- from == to: a one-chest loop walks every path point back to it
	local i = L.wrap(from + 1, n)
	for _ = 1, n - 1 do
		if i == to then
			break
		end
		if L.isPath(route.points[i]) then
			out[#out + 1] = i
		end
		i = L.wrap(i + 1, n)
	end
	return out
end

-- The via the pin should be at: from `at`, pass every via the player is inside the radius of, or has walked
-- past (near it, and closer to the point after it than the via is). Far from a via nothing passes it, so a
-- detour around a wall is never cut short. d[k]: player to via k; dn[k]: player to the point after via k;
-- vn[k]: via k to that point. Returns the new position; #d + 1 means the target itself.
function L.nextVia(at, d, dn, vn, radius)
	local k = at
	while d[k] do
		if d[k] <= radius or (d[k] <= radius * 3 and dn[k] and vn[k] and dn[k] < vn[k]) then
			k = k + 1
		else
			break
		end
	end
	return k
end

-- Path sampling: a new sample once the player is `step` yards from the last one.
function L.shouldSample(last, x, y, step)
	return not last or L.distance(last.x, last.y, x, y) >= (step or L.LEARN_STEP)
end

-- The learn trail on map mapID as unbroken runs of { x, y } map positions. A run ends where the walk left the
-- map or sampling paused (a sample with gap = true, one on another map, or a jump over TRAIL_GAP_YD between
-- world positions wx, wy), so no straight line is drawn across ground nobody walked.
function L.trailRuns(samples, mapID, gapYd)
	gapYd = gapYd or L.TRAIL_GAP_YD
	local runs, run, last = {}, nil, nil
	for _, s in ipairs(samples) do
		if s.mapID ~= mapID then
			run = nil
		else
			local jump = last and s.wx and last.wx and L.distance(last.wx, last.wy, s.wx, s.wy) > gapYd
			if not run or s.gap or jump then
				run = {}
				runs[#runs + 1] = run
			end
			run[#run + 1] = { x = s.x, y = s.y }
		end
		last = s
	end
	return runs
end

local function segmentDistance(p, a, b)
	local dx, dy = b.x - a.x, b.y - a.y
	local len2 = dx * dx + dy * dy
	if len2 == 0 then
		return L.distance(p.x, p.y, a.x, a.y)
	end
	local t = math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
	return L.distance(p.x, p.y, a.x + t * dx, a.y + t * dy)
end

-- Douglas-Peucker: the points of a polyline that keep it within tol yards. Ends always kept.
function L.simplify(points, tol)
	local n = #points
	if n <= 2 then
		return { unpack(points) }
	end
	local keep = { [1] = true, [n] = true }
	local stack = { { 1, n } }
	while #stack > 0 do
		local s = table.remove(stack)
		local a, b = s[1], s[2]
		local far, farD = nil, tol
		for k = a + 1, b - 1 do
			local d = segmentDistance(points[k], points[a], points[b])
			if d > farD then
				far, farD = k, d
			end
		end
		if far then
			keep[far] = true
			stack[#stack + 1] = { a, far }
			stack[#stack + 1] = { far, b }
		end
	end
	local out = {}
	for k = 1, n do
		if keep[k] then
			out[#out + 1] = points[k]
		end
	end
	return out
end

-- Vias for one walked stretch: the simplified samples between two chests, ends and anything inside
-- VISIT_YD of either chest left out.
local function stretchVias(a, samples, first, last, b, tol)
	local poly = { a }
	for k = first + 1, last - 1 do
		poly[#poly + 1] = samples[k]
	end
	poly[#poly + 1] = b
	local out = {}
	local kept = L.simplify(poly, tol)
	for k = 2, #kept - 1 do
		local s = kept[k]
		if L.distance(s.x, s.y, a.x, a.y) > L.VISIT_YD and L.distance(s.x, s.y, b.x, b.y) > L.VISIT_YD then
			out[#out + 1] = s
		end
	end
	return out
end

-- What a learn walk suggests. samples: { { x, y, ... } } in yards, in walking order; chests: { { i, x, y } }
-- the route's chest points. Returns { order = { chest i, first-visit order }, vias = { [k] = samples between
-- order[k] and order[k + 1] }, closing = samples from the last chest back to the first or nil, visits = n }.
function L.learnPlan(samples, chests, tol)
	tol = tol or L.LEARN_TOLERANCE
	-- the visits: runs of samples inside VISIT_YD of one chest, anchored at the closest sample
	local visits = {}
	local runChest, runBest, runD
	local function closeRun()
		if runChest then
			local last = visits[#visits]
			if last and last.chest == runChest.i then
				visits[#visits] = { chest = runChest.i, s = runBest, c = runChest } -- came back: the later one
			else
				visits[#visits + 1] = { chest = runChest.i, s = runBest, c = runChest }
			end
		end
		runChest = nil
	end
	for k, s in ipairs(samples) do
		local near, nd
		for _, c in ipairs(chests) do
			local d = L.distance(s.x, s.y, c.x, c.y)
			if d <= L.VISIT_YD and (not nd or d < nd) then
				near, nd = c, d
			end
		end
		if near ~= runChest then
			closeRun()
			if near then
				runChest, runBest, runD = near, k, nd
			end
		elseif near and nd < runD then
			runBest, runD = k, nd
		end
	end
	closeRun()

	-- a stretch with a pause in sampling (gap) or a jump in it was not walked: it gets no vias
	local function unbroken(first, last)
		for k = first + 1, last do
			local s, p = samples[k], samples[k - 1]
			if s.gap or L.distance(p.x, p.y, s.x, s.y) > L.TRAIL_GAP_YD then
				return false
			end
		end
		return true
	end
	local function stretch(prev, cur)
		if unbroken(prev.s, cur.s) then
			return stretchVias(prev.c, samples, prev.s, cur.s, cur.c, tol)
		end
		return nil
	end

	local plan = { order = {}, vias = {}, visits = #visits }
	local pos = {} -- chest i -> position in order
	for v = 1, #visits do
		local cur = visits[v]
		if not pos[cur.chest] then
			plan.order[#plan.order + 1] = cur.chest
			pos[cur.chest] = #plan.order
			local prev = visits[v - 1]
			-- vias only for a stretch walked straight from the chest just before it in the order
			if prev and pos[prev.chest] == #plan.order - 1 then
				plan.vias[#plan.order - 1] = stretch(prev, cur)
			end
		elseif pos[cur.chest] == 1 and #plan.order > 1 and not plan.closing then
			local prev = visits[v - 1]
			if prev and pos[prev.chest] == #plan.order then
				plan.closing = stretch(prev, cur)
			end
		end
	end
	return plan
end

-- The vias after order[k]: the stretch to order[k + 1], or the closing one after the last chest. A stretch
-- not walked straight has none.
function L.planVias(plan, k)
	local v
	if k < #plan.order then
		v = plan.vias[k]
	else
		v = plan.closing
	end
	return v or {}
end

-- The new point list for an accepted plan. entries: { { i, x, y, point } } for every route point (yards);
-- makeVia(sample) builds a path point. Walked chests come in walking order with their vias; chests the walk
-- missed are put back at their cheapest place. Each old path point belongs to the chest before it: a chest
-- whose stretch the walk went straight along gets the new vias instead, every other chest (missed ones too)
-- keeps its old ones. Returns points, the old -> new index map and how many old path points were kept.
function L.applyPlan(entries, plan, makeVia)
	local byIndex, pos = {}, {}
	for k, e in ipairs(entries) do
		byIndex[e.i] = e
		pos[e.i] = k
	end
	-- the old path entries straight after chest a, up to the next chest of the old loop. They travel with a.
	local function oldVias(a)
		local list, n = {}, #entries
		for k = 1, n - 1 do
			local e = entries[(pos[a] - 1 + k) % n + 1]
			if not L.isPath(e.point) then
				break
			end
			list[#list + 1] = e
		end
		return list
	end
	local walked = function(k)
		if k < #plan.order then
			return plan.vias[k] ~= nil
		end
		return plan.closing ~= nil
	end
	local out, map, placed, kept = {}, {}, {}, 0
	local chestPos = {} -- { i = new index, x, y } of chests in out, for the insertion of missed ones
	for k, ci in ipairs(plan.order) do
		local e = byIndex[ci]
		if e then
			out[#out + 1] = e.point
			map[ci] = #out
			placed[ci] = true
			if walked(k) then
				for _, s in ipairs(L.planVias(plan, k)) do
					out[#out + 1] = makeVia(s)
				end
			else
				for _, v in ipairs(oldVias(ci)) do
					out[#out + 1] = v.point
					map[v.i] = #out
					kept = kept + 1
				end
			end
			-- i is the last index of the chest's stretch, so a missed chest goes in after its vias
			chestPos[#chestPos + 1] = { i = #out, x = e.x, y = e.y }
		end
	end
	for _, e in ipairs(entries) do
		if not placed[e.i] and not L.isPath(e.point) then
			-- the missed chest goes in as a block with its old vias, after a whole stretch, so it never
			-- splits a run of kept vias
			local block = { e }
			for _, v in ipairs(oldVias(e.i)) do
				block[#block + 1] = v
			end
			local at = L.insertionIndex(chestPos, e.x, e.y)
			local len = #block
			for old, new in pairs(map) do
				if new >= at then
					map[old] = new + len
				end
			end
			for _, c in ipairs(chestPos) do
				if c.i >= at then
					c.i = c.i + len
				end
			end
			for j, b in ipairs(block) do
				table.insert(out, at + j - 1, b.point)
				map[b.i] = at + j - 1
			end
			kept = kept + len - 1
			chestPos[#chestPos + 1] = { i = at + len - 1, x = e.x, y = e.y }
			table.sort(chestPos, function(a, b)
				return a.i < b.i
			end)
		end
	end
	return out, map, kept
end
