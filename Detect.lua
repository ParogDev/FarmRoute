-- What the game's soft-interact target tells us about chests (the "softinteract" unit, the one the interact
-- key would use): its GUID and object id, its name, its nameplate, and the "Requires Lockpicking (N)" line of
-- its tooltip. Phase 2 starts with a probe: every appearance and disappearance is logged with the player's
-- distance to the nearest route point, the navigation distance and the player's height, so the route logic
-- is built on measured behaviour. Results go to FarmRouteDB.probe and a chat line per change (/fr probe).
local _, ns = ...

local L = ns.Logic

local D = {}
ns.Detect = D

local SOFT = "softinteract"
local MAX_EVENTS, MAX_SAMPLES = 80, 40
local SAMPLE_EVERY = 2 -- seconds between navigation distance samples

-- The current soft-interact target, or nil: { guid, objectID, name, need = { skill, level }, plate, alpha }
D.current = nil
D.status = { reads = 0, secret = 0, lastWhy = "not read yet" }

-- A value safe to keep: nil for secrets (counted), else the value.
local function plain(v)
	if v ~= nil and issecretvalue(v) then
		D.status.secret = D.status.secret + 1
		return nil, true
	end
	return v
end

local function call(fn, ...)
	if not fn then
		return nil
	end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		return nil
	end
	return a, b, c, d
end

local requiresPattern
local function tooltipOf(unit)
	local data = call(C_TooltipInfo and C_TooltipInfo.GetUnit, unit)
	local texts = {}
	if type(data) == "table" and type(data.lines) == "table" then
		for i, line in ipairs(data.lines) do
			local t = plain(line.leftText)
			if type(t) == "string" then
				texts[#texts + 1] = t
			end
			if i >= 8 then
				break
			end
		end
	end
	requiresPattern = requiresPattern or L.requiresPattern(ITEM_MIN_SKILL)
	local skill, level = L.parseRequires(texts, requiresPattern)
	return texts, skill and { skill = skill, level = level } or nil
end

-- Reads the soft-interact unit now. Returns a table or nil and why.
function D.read()
	D.status.reads = D.status.reads + 1
	local isObject = plain(call(UnitIsGameObject, SOFT))
	local exists = plain(call(UnitExists, SOFT))
	if not isObject and not exists then
		D.status.lastWhy = "no soft-interact target"
		return nil, D.status.lastWhy
	end
	local guid, guidSecret = plain(call(UnitGUID, SOFT))
	local name = plain(call(UnitName, SOFT))
	local plate = call(C_NamePlate and C_NamePlate.GetNamePlateForUnit, SOFT)
	local alpha = plate and plain(call(plate.GetEffectiveAlpha, plate)) or nil
	local texts, need = tooltipOf(SOFT)
	-- in game the unit tooltip of a soft-targeted object has no lines (probe, 2026-11-21): the skill comes
	-- from the mouseover tooltip, remembered by name (D.hookTooltips)
	if not need and name and ns.db.needByName and ns.db.needByName[name] then
		need = ns.db.needByName[name]
	end
	D.status.lastWhy = guidSecret and "GUID is a secret value" or "read"
	return {
		guid = guid,
		objectID = L.guidObject(guid),
		isObject = isObject == true,
		name = name or texts[1],
		need = need,
		plate = plate ~= nil,
		alpha = alpha and math.floor(alpha * 100 + 0.5) / 100 or nil,
		tooltip = texts,
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- Player and route geometry for the probe
-- ---------------------------------------------------------------------------------------------------------
local function playerWorld()
	local m, x, y = ns.Nav.playerPos()
	if not m then
		return nil
	end
	local c, wx, wy = ns.Nav.worldPos(m, x, y)
	if not c then
		return nil
	end
	return { c = c, x = wx, y = wy, mapID = m, mx = x, my = y }
end

local function round(v, k)
	if type(v) ~= "number" then
		return nil
	end
	local f = 10 ^ (k or 1)
	return math.floor(v * f + 0.5) / f
end

-- The nearest point of every route on the player's continent: route name, index, flat yards.
local function nearestPoint(pw)
	local best
	for name, route in pairs(ns.db.routes) do
		for i, p in ipairs(route.points) do
			local c, wx, wy = ns.Nav.worldPos(p.mapID, p.x, p.y)
			if c == pw.c then
				local d = L.distance(pw.x, pw.y, wx, wy)
				if not best or d < best.d then
					best = { route = name, i = i, d = d, label = p.label, floor = p.floor }
				end
			end
		end
	end
	return best
end

local function context()
	local pw = playerWorld()
	local ux, uy, uz = call(UnitPosition, "player")
	local near = pw and nearestPoint(pw)
	local navFrame = C_Navigation.GetFrame()
	return {
		at = date("%H:%M:%S"),
		t = GetTime(),
		point = near and (near.route .. " " .. near.i) or nil,
		pointYd = near and round(near.d) or nil,
		pointFloor = near and near.floor or nil,
		z = round(plain(uz)),
		ux = round(plain(ux)),
		uy = round(plain(uy)),
		wx = pw and round(pw.x),
		wy = pw and round(pw.y),
		facing = round(plain(call(GetPlayerFacing)), 2),
		navYd = navFrame and round(plain(C_Navigation.GetDistance())) or nil,
		navOnScreen = navFrame and C_Navigation.HasValidScreenPosition() or false,
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- Probe log
-- ---------------------------------------------------------------------------------------------------------
local function probeDB()
	local p = ns.db.probe
	if type(p) ~= "table" then
		p = {}
		ns.db.probe = p
	end
	p.events = p.events or {}
	p.objects = p.objects or {}
	p.samples = p.samples or {}
	p.vignettes = p.vignettes or {}
	p.cursor = p.cursor or {}
	return p
end
D.probeDB = probeDB

-- Chat only for chests of the active route: chairs and stools take the soft target all the time in Angor
-- Fortress (probe, 2026-11-21) and stay in the SavedVariables log only.
local function say(line, target)
	local route = ns.activeRoute and ns.activeRoute()
	if not (target and route and L.matchesRoute(route, target.objectID, target.need)) then
		return
	end
	if ns.db.settings.probe then
		ns.say("|cff80c0ffprobe:|r " .. line)
	end
end

local function noteObject(p, t, ctx)
	local key = t.objectID and tostring(t.objectID) or (t.name or "?")
	local o = p.objects[key] or { name = t.name, seen = 0 }
	p.objects[key] = o
	o.seen = o.seen + 1
	o.need = t.need and t.need.level or o.need
	o.skill = t.need and t.need.skill or o.skill
	o.plate = t.plate or o.plate
	if ctx.pointYd then
		o.appearMin = math.min(o.appearMin or ctx.pointYd, ctx.pointYd)
		o.appearMax = math.max(o.appearMax or ctx.pointYd, ctx.pointYd)
	end
	return o
end

local lastSoftGUID

-- PLAYER_SOFT_INTERACT_CHANGED, and the ticker in case the event is missed.
function D.update(source)
	local t = D.read()
	-- a target whose GUID and name are secret is still a target: logged without them
	local guid = t and (t.guid or t.name or "secret") or nil
	if guid == lastSoftGUID then
		if t and D.current then
			D.current.alpha, D.current.plate = t.alpha, t.plate
		end
		return D.current
	end
	local p = probeDB()
	local ctx = context()
	if D.current then
		local gone = D.current
		ctx.kind, ctx.objectID, ctx.name = "gone", gone.objectID, gone.name
		ctx.heldFor = round(ctx.t - (gone.since or ctx.t))
		ctx.source = source
		L.push(p.events, ctx, MAX_EVENTS) -- losses are logged, not said: the target flips every 0.1 s
		ctx = context()
	end
	lastSoftGUID = guid
	D.current = t
	if t then
		t.since = ctx.t
		ctx.kind, ctx.objectID, ctx.name = "seen", t.objectID, t.name
		ctx.need = t.need and t.need.level or nil
		ctx.plate, ctx.alpha, ctx.source = t.plate, t.alpha, source
		ctx.tooltip = t.tooltip
		L.push(p.events, ctx, MAX_EVENTS)
		noteObject(p, t, ctx)
		-- one line per chest per 30 s
		local said = D.saidAt and D.saidAt[guid]
		D.saidAt = D.saidAt or {}
		if said and ctx.t - said < 30 then
			return t
		end
		D.saidAt[guid] = ctx.t
		say(
			string.format(
				"%s (%s)%s; nearest point %s at %s yd; nameplate %s",
				tostring(t.name),
				tostring(t.objectID or "no id"),
				t.need and (", needs " .. t.need.skill .. " " .. t.need.level) or "",
				tostring(ctx.point),
				tostring(ctx.pointYd),
				t.plate and ("yes, alpha " .. tostring(t.alpha)) or "no"
			),
			t
		)
	end
	return t
end

local lastSample = 0
local function sampleNav()
	local now = GetTime()
	if now - lastSample < SAMPLE_EVERY then
		return
	end
	lastSample = now
	local route, i = ns.activeRoute(), ns.currentIndex()
	if not route or not i or not C_Navigation.GetFrame() then
		return
	end
	local flat = ns.Nav.distanceTo(route.points[i])
	local nav = plain(C_Navigation.GetDistance())
	if not flat or type(nav) ~= "number" then
		return
	end
	local _, _, uz = call(UnitPosition, "player")
	L.push(probeDB().samples, {
		at = date("%H:%M:%S"),
		point = i,
		floor = route.points[i].floor,
		flat = round(flat),
		nav = round(nav),
		z = round(plain(uz)),
		clamped = C_Navigation.WasClampedToScreen(),
	}, MAX_SAMPLES)
end

local vignettesSeen = {}
local function sampleVignettes()
	local list = call(C_VignetteInfo and C_VignetteInfo.GetVignettes)
	if type(list) ~= "table" then
		return
	end
	local p = probeDB()
	p.vignetteCount = #list
	for _, g in ipairs(list) do
		local guid = plain(g) -- a secret GUID can't be a table key
		if guid and not vignettesSeen[guid] then
			vignettesSeen[guid] = true
			local info = call(C_VignetteInfo.GetVignetteInfo, guid)
			local name = info and plain(info.name)
			if name and not p.vignettes[name] then
				p.vignettes[name] = { atlas = plain(info.atlasName), objectGUID = L.guidObject(plain(info.objectGUID)) }
			end
		end
	end
end

-- The mouseover tooltip of a world object (the cursor over a chest), when it is a footlocker-like object.
local function sampleCursor()
	local data = call(C_TooltipInfo and C_TooltipInfo.GetWorldCursor)
	if type(data) ~= "table" or type(data.lines) ~= "table" or not data.lines[1] then
		return
	end
	local name = plain(data.lines[1].leftText)
	if type(name) ~= "string" then
		return
	end
	local p = probeDB()
	if p.cursor[name] then
		return
	end
	local texts = {}
	for i, line in ipairs(data.lines) do
		local tx = plain(line.leftText)
		texts[#texts + 1] = type(tx) == "string" and tx or "?"
		if i >= 6 then
			break
		end
	end
	p.cursor[name] = { type = data.type, lines = texts }
end

function D.sampledNames()
	local p, n = ns.db.probe or {}, 0
	for _ in pairs(p.cursor or {}) do
		n = n + 1
	end
	for _ in pairs(p.vignettes or {}) do
		n = n + 1
	end
	return n
end

function D.tick()
	D.update("tick")
	sampleNav()
	-- vignette and cursor sampling only while walking, and at most 60 names in SavedVariables
	if ns.db.settings.probe and ns.db.running and D.sampledNames() < 60 then
		sampleVignettes()
		sampleCursor()
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Soft-target CVars (what detection depends on)
-- ---------------------------------------------------------------------------------------------------------
D.CVARS = {
	"SoftTargetInteract",
	"SoftTargetInteractRange",
	"SoftTargetInteractArc",
	"SoftTargetInteractOnlyInRange",
	"SoftTargetInteractRangeIsHard",
	"SoftTargetNameplateInteract",
	"SoftTargetIconGameObject",
	"SoftTargetIconInteract",
	"nameplateGameObjectMaxDistance",
}

function D.cvars()
	local out = {}
	for _, n in ipairs(D.CVARS) do
		local ok, v = pcall(C_CVar.GetCVar, n)
		out[n] = ok and v or "unreadable"
	end
	return out
end

-- The mouseover tooltip of a world object ("Battered Footlocker" / "Requires Lockpicking (150)"): remember the
-- skill by name, and by object id for every object of that name the probe has seen.
function D.onObjectTooltip(_, data)
	if type(data) ~= "table" or type(data.lines) ~= "table" or not data.lines[1] then
		return
	end
	local texts = {}
	for i, line in ipairs(data.lines) do
		local t = plain(line.leftText)
		texts[#texts + 1] = type(t) == "string" and t or ""
		if i >= 8 then
			break
		end
	end
	requiresPattern = requiresPattern or L.requiresPattern(ITEM_MIN_SKILL)
	local skill, level = L.parseRequires(texts, requiresPattern)
	local name = texts[1]
	if not skill or name == "" then
		return
	end
	ns.db.needByName = ns.db.needByName or {}
	ns.db.needByName[name] = { skill = skill, level = level }
	for id, o in pairs(probeDB().objects) do
		if o.name == name and tonumber(id) then
			ns.db.objectNeed[tonumber(id)] = level
		end
	end
	if D.current and D.current.name == name then
		D.current.need = ns.db.needByName[name]
	end
	D.status.tooltipNeed = name .. " " .. level
end

function D.hookTooltips()
	local objectType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and objectType) then
		D.status.tooltipHook = "TooltipDataProcessor or Enum.TooltipDataType.Object missing"
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(objectType, function(tooltip, data)
		ns.guard("objectTooltip", D.onObjectTooltip, tooltip, data)
	end)
	D.status.tooltipHook = "hooked"
end

-- Player's skill rank by skill line name ("Lockpicking"), or nil and why.
function D.skillRank(skillName)
	local n = call(C_SkillInfo and C_SkillInfo.GetNumSkillLines)
	if not n then
		return nil, "C_SkillInfo.GetNumSkillLines unavailable"
	end
	for i = 1, n do
		local info = call(C_SkillInfo.GetSkillLineInfo, i)
		if type(info) == "table" and not info.isHeader and info.name == skillName then
			return info.rank, info.maxRank
		end
	end
	return nil, "no skill line named " .. tostring(skillName)
end

function D.selftest()
	local p = ns.db.probe or {}
	local cur = D.current
	return {
		status = D.status,
		current = cur and { name = cur.name, objectID = cur.objectID, need = cur.need, plate = cur.plate } or nil,
		events = p.events and #p.events or 0,
		objects = p.objects,
		cvars = D.cvars(),
		lockpicking = D.skillRank("Lockpicking"),
	}
end
