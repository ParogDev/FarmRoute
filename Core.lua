-- Addon entry: SavedVariables, the selftest contract (docs/verify-loop.md in the scaffolding), the walk
-- through the active route (arrival check on a ticker, keybinds), /fr and event wiring.
local ADDON, ns = ...

FarmRoute = ns

local L, Nav, MapLines = ns.Logic, ns.Nav, ns.MapLines

ns.VERSION = "0.2.0-probe"
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
}

local counters = { advanceArrived = 0, advanceKey = 0, advanceNavReached = 0, imports = 0, placeFailed = 0 }
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
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then
			db.settings[k] = v
		end
	end
	if not db.seeded then
		for _, r in ipairs(L.seedRoutes()) do
			if not db.routes[r.name] then
				db.routes[r.name] = r
			end
		end
		db.active = db.active or "Angor Battered"
		db.seeded = true
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
	local i = ns.db.current[route.name]
	if not i or not route.points[i] then
		return #route.points > 0 and 1 or nil
	end
	return i
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

local function place()
	local route, i = ns.activeRoute(), ns.currentIndex()
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

local function setCurrent(i)
	local route = ns.activeRoute()
	ns.db.current[route.name] = i
	lastAdvance = GetTime()
	place()
end

-- dir +1 / -1; why names the counter.
function ns.advance(dir, why)
	local route = ns.activeRoute()
	if not route or #route.points == 0 then
		say("no route or an empty route: /fr route, /fr add")
		return
	end
	local now = time()
	local timers = ns.timersFor(route.name)
	local i, waiting = L.advance(route, timers, ns.currentIndex(), dir, now)
	counters[why] = (counters[why] or 0) + 1
	setCurrent(i)
	if waiting then
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

local function tick()
	ns.guard("detect", ns.Detect.tick)
	if not running then
		Nav.hideMarker("stopped")
		return
	end
	Nav.updateScreenLine(ns.db.settings.screenLine, ns.db.settings.radius)
	local route, i = ns.activeRoute(), ns.currentIndex()
	if not route or not i then
		return
	end
	local d, why = Nav.distanceTo(route.points[i])
	lastDistance, lastDistanceWhy = d, why
	if not d or not ns.db.settings.autoAdvance then
		return
	end
	local timers = ns.timersFor(route.name)
	if d <= ns.db.settings.radius and GetTime() - lastAdvance >= MIN_GAP and L.isUp(timers, i, time()) then
		ns.advance(1, "advanceArrived")
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
		settings = ns.db.settings,
		counters = counters,
		interact = ns.interactState(),
		interactLast = ns.db.interactLog and ns.db.interactLog[#ns.db.interactLog] or nil,
		detect = ns.Detect.selftest(),
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
}

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

local commands = {}

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
	route.points[#route.points + 1] = { mapID = m, x = x, y = y, label = arg ~= "" and arg or nil }
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
	table.remove(route.points, n)
	ns.db.timers[route.name] = {}
	local cur = ns.currentIndex()
	if cur and cur > n then
		ns.db.current[route.name] = cur - 1
	end
	say("removed point " .. n .. "; " .. #route.points .. " left")
	place()
end

function commands.list()
	local route = ns.activeRoute()
	if not route then
		return
	end
	local timers, now = ns.timersFor(route.name), time()
	for i = 1, #route.points do
		local t = timers[i] and timers[i] > now and string.format(" [up in %d s]", timers[i] - now) or ""
		say((i == ns.currentIndex() and "> " or "  ") .. L.formatPoint(route, i) .. t)
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
local function reassert(st)
	if not ns.db.settings.keepInteract or InCombatLockdown() then
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
	local last = ns.db.interactLog[#ns.db.interactLog] -- the change being undone, read before ours is logged
	selfSet = true
	pcall(C_CVar.SetCVar, INTERACT, INTERACT_ON)
	selfSet = false
	say("interact key put back to 3 (was " .. st.value .. (last and (", set by " .. last.by) or "") .. ")")
	return ns.interactState().ok
end

function ns.checkInteract(source)
	local st = ns.interactState()
	if st.ok then
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
			lastLuaSet =
				{ value = value, by = selfSet and "FarmRoute (/fr fixinteract)" or callerAddon(), at = GetTime() }
		end
	end)
end

function commands.fixinteract()
	if InCombatLockdown() then
		say("in combat: try /fr fixinteract again after combat")
		return
	end
	selfSet = true
	local ok, err = pcall(C_CVar.SetCVar, INTERACT, INTERACT_ON)
	selfSet = false
	local st = ns.interactState()
	if ok and st.ok then
		say("Interact key on (" .. INTERACT .. " = " .. st.value .. ")")
	else
		say("couldn't turn the interact key on: " .. tostring(err or st.why))
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
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == ADDON then
			ns.initDB(FarmRouteDB)
			guard("hookInteract", ns.hookInteract)
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
		guard("mapLines", MapLines.initWorld)
		running = ns.db.running == true
		guard("place", place)
		C_Timer.NewTicker(TICK, function()
			guard("tick", tick)
		end)
		guard("snapshot", selftest.snapshot, "login")
	elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
		if ns.db then
			guard("softChanged", ns.Detect.update, "event")
		end
	elseif event == "PLAYER_LOGOUT" then
		guard("snapshot", selftest.snapshot, "logout")
	elseif event == "NAVIGATION_DESTINATION_REACHED" then
		-- Blizzard clears a reached user waypoint in its own handler; move on after it has run.
		if running and Nav.ownsPin() and ns.db.settings.autoAdvance then
			C_Timer.After(0, function()
				if GetTime() - lastAdvance >= MIN_GAP then
					guard("navReached", ns.advance, 1, "advanceNavReached")
				end
			end)
		end
	end
end)
