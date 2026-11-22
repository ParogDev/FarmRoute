local mock = require("tests.wow_mock")

describe("FarmRoute core", function()
	local ns

	before_each(function()
		mock.install()
		ns = mock.load()
	end)

	it("seeds once, keeps deletions, and fills settings", function()
		mock.login(nil)
		assert.is_not_nil(FarmRouteDB.routes["Angor Battered"])
		assert.equals("Angor Battered", FarmRouteDB.active)
		assert.equals(8, FarmRouteDB.settings.radius)
		-- a fresh install is running and has placed the pin
		assert.is_true(FarmRouteDB.running)
		assert.equals(1418, mock.waypoint.uiMapID)
		local saved = FarmRouteDB
		saved.routes["Angor Dented"] = nil
		mock.install()
		ns = mock.load()
		mock.login(saved)
		assert.is_nil(FarmRouteDB.routes["Angor Dented"])
	end)

	it("writes the selftest with the code version on login", function()
		mock.login(nil)
		local st = FarmRouteDB.selftest
		assert.equals("login", st.phase)
		assert.equals(ns.VERSION, st.version)
		assert.equals("Angor Battered", st.route)
		assert.equals(14, st.points)
		assert.is_nil(st.lastError)
	end)

	it("/fr on places a super-tracked user waypoint on the current point", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("on")
		assert.equals(1418, mock.waypoint.uiMapID)
		assert.near(0.408, mock.waypoint.position.x, 1e-9)
		assert.is_true(mock.superTracked)
		assert.is_true(ns.Nav.ownsPin())
	end)

	it("advances on arrival, keeps the point, and wraps", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("on")
		local route = ns.activeRoute()
		local p = route.points[1]
		mock.pos = { p.x + 1 / mock.YARDS, p.y } -- 1 yard away
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		assert.equals(1, ns.currentIndex()) -- settling: the soft target may still appear
		mock.gameTime = mock.gameTime + 1
		mock.tick()
		assert.equals(2, ns.currentIndex())
		assert.equals(14, #route.points)
		assert.near(route.points[2].x, mock.waypoint.position.x, 1e-9)
		-- nothing detected at point 1: an empty visit in its history, and it is checked for this loop
		assert.is_false(FarmRouteDB.history["Angor Battered"][1].visits[1].seen)
		assert.is_true(FarmRouteDB.checked["Angor Battered"][1])
		-- within MIN_GAP nothing more happens even when standing on the next point
		mock.pos = { route.points[2].x, route.points[2].y }
		mock.tick()
		mock.tick()
		assert.equals(2, ns.currentIndex())
		-- from the last point, the objective wraps past point 1 (already checked this loop) to 2
		SlashCmdList.FARMROUTE("goto 14")
		mock.pos = { route.points[14].x, route.points[14].y }
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		mock.gameTime = mock.gameTime + 1
		mock.tick()
		assert.equals(2, ns.currentIndex())
	end)

	local function footlocker(id, need)
		return {
			guid = "GameObject-0-1-0-12-" .. id .. "-0000" .. need,
			name = id == 179490 and "Battered Footlocker" or "Dented Footlocker",
			tooltip = { "Footlocker", "Requires Lockpicking (" .. need .. ")" },
		}
	end

	it("a detected chest of the route becomes the objective, and its loot records a visit with a chest", function()
		mock.login(nil)
		local route = ns.activeRoute()
		local p7 = route.points[7]
		mock.pos = { p7.x + 6 / mock.YARDS, p7.y } -- 6 yd from point 7, far from point 1
		mock.soft = footlocker(179490, 150)
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		assert.equals(7, ns.currentIndex())
		assert.near(p7.x, mock.waypoint.position.x, 1e-9)
		assert.equals("detected", ns.markerInfo().state)
		assert.equals(150, ns.markerInfo().need)
		assert.equals(169, ns.markerInfo().skill)
		assert.equals(150, FarmRouteDB.objectNeed[179490])
		-- standing at it with the chest still there: no advance
		mock.pos = { p7.x, p7.y }
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		assert.equals(7, ns.currentIndex())
		-- the target flips to a chair and back: no loot, no advance
		mock.soft = { guid = "GameObject-0-1-0-12-61088-00001", name = "Wooden Chair", tooltip = {} }
		mock.tick()
		mock.gameTime = mock.gameTime + 2
		mock.tick()
		assert.equals(7, ns.currentIndex())
		mock.soft = footlocker(179490, 150)
		mock.tick()
		-- opened (LOOT_OPENED), then gone: after LOST_AFTER the point is checked with a chest
		mock.fire("LOOT_OPENED")
		mock.soft = nil
		mock.tick()
		mock.gameTime = mock.gameTime + 2
		mock.tick()
		assert.is_true(FarmRouteDB.history["Angor Battered"][7].visits[1].seen)
		assert.equals(8, ns.currentIndex())
		assert.equals(1, ns.counters.advanceLooted)
		assert.equals(1, ns.counters.chestJump)
		assert.is_nil(ns.selftest.lastError)
	end)

	it("reads the minimum skill from the mouseover tooltip when the soft target's tooltip is empty", function()
		mock.login(nil)
		local p7 = ns.activeRoute().points[7]
		mock.pos = { p7.x + 6 / mock.YARDS, p7.y }
		mock.soft = footlocker(179490, 150)
		mock.soft.tooltip = {} -- as in game
		mock.tick()
		assert.is_nil(ns.markerInfo().need)
		ns.Detect.onObjectTooltip(nil, {
			lines = { { leftText = "Battered Footlocker" }, { leftText = "Requires Lockpicking (150)" } },
		})
		assert.equals(150, FarmRouteDB.objectNeed[179490])
		assert.equals(150, ns.markerInfo().need)
		assert.equals("hooked", ns.Detect.status.tooltipHook)
	end)

	it("ignores chests of another route's kind and chests with no point in range", function()
		mock.login(nil)
		local p7 = ns.activeRoute().points[7]
		mock.pos = { p7.x, p7.y }
		mock.soft = footlocker(179492, 175) -- Dented: the downstairs route
		mock.tick()
		assert.equals(1, ns.currentIndex())
		mock.soft = footlocker(179490, 150)
		mock.pos = { 0.9, 0.9 }
		mock.tick()
		assert.equals(1, ns.currentIndex())
		assert.equals(1, ns.counters.chestNoPoint)
	end)

	it("Skip checks the point without a history entry and flashes", function()
		mock.login(nil)
		local flashed
		ns.HUD.flash = function(t)
			flashed = t
		end
		FarmRoute.Skip()
		assert.equals(2, ns.currentIndex())
		assert.equals("Skipped 1/14", flashed)
		assert.is_nil(FarmRouteDB.history["Angor Battered"][1])
		assert.is_true(FarmRouteDB.checked["Angor Battered"][1])
	end)

	it("autoskip moves on after standing near a point with nothing detected (off by default)", function()
		mock.login(nil)
		local p1 = ns.activeRoute().points[1]
		mock.pos = { p1.x + 15 / mock.YARDS, p1.y } -- near, outside the radius
		mock.gameTime = mock.gameTime + 5
		for _ = 1, 3 do
			mock.gameTime = mock.gameTime + 10
			mock.tick()
		end
		assert.equals(1, ns.currentIndex())
		SlashCmdList.FARMROUTE("autoskip on")
		for _ = 1, 3 do
			mock.gameTime = mock.gameTime + 10
			mock.tick()
		end
		assert.equals(2, ns.currentIndex())
		assert.equals(1, ns.counters.autoSkip)
	end)

	it("health names what blocks detection, Fix repairs it, /fr off puts the player's values back", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("keepinteract off")
		mock.cvars.SoftTargetInteractRange = "10"
		local h = ns.healthState()
		assert.is_false(h.ok)
		assert.matches("only 10 yd", h.line)
		mock.stack = '[string "@Interface/AddOns/Plater/Plater.lua"]:1: in function'
		C_CVar.SetCVar("SoftTargetInteract", 1)
		h = ns.healthState()
		assert.matches("gamepad only", h.line)
		assert.matches("turned off by Plater", h.detail)
		mock.combat = true
		assert.is_false(ns.fixDetection())
		mock.combat = false
		assert.is_true(ns.fixDetection())
		assert.equals("3", mock.cvars.SoftTargetInteract)
		assert.equals("20", mock.cvars.SoftTargetInteractRange)
		assert.is_true(ns.healthState().ok)
		SlashCmdList.FARMROUTE("off")
		assert.equals("1", mock.cvars.SoftTargetInteract)
		assert.equals("10", mock.cvars.SoftTargetInteractRange)
	end)

	it("does not advance when far or when the position is secret", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("on")
		mock.gameTime = mock.gameTime + 5
		mock.pos = { 0.9, 0.9 }
		mock.tick()
		assert.equals(1, ns.currentIndex())
		mock.secret[1418] = true
		mock.tick()
		assert.equals(1, ns.currentIndex())
		assert.matches("secret", FarmRouteDB.selftest and ns.selftest.snapshot("t").distanceWhy)
	end)

	it("draws its own marker on the navigation frame, and names why when it can't", function()
		mock.login(nil)
		mock.tick()
		assert.is_nil(ns.selftest.lastError) -- a tick raised every 0.25 s in 0.1.1
		assert.equals("C_Navigation.GetFrame() is nil", ns.Nav.marker.why)
		mock.navFrame, mock.navDistance = mock.widget(), 17.4
		mock.tick()
		assert.is_true(ns.Nav.marker.shown)
		local st = ns.selftest.snapshot("t").nav
		assert.equals(17.4, st.navDistance)
		SlashCmdList.FARMROUTE("off")
		mock.tick()
		assert.is_false(ns.Nav.marker.shown)
	end)

	it("keepinteract puts the key back, and stops when another addon fights it", function()
		mock.login(nil)
		mock.stack = '[string "@Interface/AddOns/Plater/Plater.lua"]:1: in function'
		C_CVar.SetCVar("SoftTargetInteract", 1)
		assert.equals("3", mock.cvars.SoftTargetInteract)
		assert.matches("put back to 3 %(was 1, set by Plater%)", table.concat(mock.chat, "\n"))
		for _ = 1, 5 do
			C_CVar.SetCVar("SoftTargetInteract", 1)
		end
		assert.equals("1", mock.cvars.SoftTargetInteract)
		assert.matches("keeps changing the interact key", table.concat(mock.chat, "\n"))
	end)

	it("keepinteract leaves the player's own change alone and retries after combat", function()
		mock.login(nil)
		-- Options > Controls: no Lua caller
		mock.cvars.SoftTargetInteract = "0"
		mock.fire("CVAR_UPDATE", "SoftTargetInteract", "0")
		assert.equals("0", mock.cvars.SoftTargetInteract)
		mock.cvars.SoftTargetInteract = "3"
		-- an addon in combat: put back once combat ends
		mock.stack = '[string "@Interface/AddOns/Plater/Plater.lua"]:1: in function'
		mock.combat = true
		C_CVar.SetCVar("SoftTargetInteract", 1)
		assert.equals("1", mock.cvars.SoftTargetInteract)
		mock.combat = false
		mock.fire("PLAYER_REGEN_ENABLED")
		assert.equals("3", mock.cvars.SoftTargetInteract)
		assert.equals("FarmRoute (keepinteract)", FarmRouteDB.interactLog[#FarmRouteDB.interactLog].by)
	end)

	it("warns when the interact key is off and names who turned it off", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("keepinteract off")
		C_CVar.SetCVar("SoftTargetInteract", 0) -- the mock stack says Lueur
		assert.equals("Lueur", FarmRouteDB.interactLog[1].by)
		assert.matches("Interact key is off.*turned off by Lueur", mock.chat[#mock.chat])
		assert.is_false(ns.selftest.snapshot("t").interact.ok)
		-- a change with no Lua caller
		mock.cvars.SoftTargetInteract = "3"
		mock.fire("CVAR_UPDATE", "SoftTargetInteract", "3")
		mock.cvars.SoftTargetInteract = "0"
		mock.fire("CVAR_UPDATE", "SoftTargetInteract", "0")
		assert.equals("client or settings panel", FarmRouteDB.interactLog[3].by)
		SlashCmdList.FARMROUTE("fixinteract")
		assert.equals("3", mock.cvars.SoftTargetInteract)
		assert.equals("FarmRoute (/fr fixinteract)", FarmRouteDB.interactLog[4].by)
		assert.is_true(ns.interactState().ok)
	end)

	it("counts gamepad-only (1) as off, as Plater set it in game", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("keepinteract off")
		mock.stack = '[string "@Interface/AddOns/Plater/Plater.lua"]:1: in function'
		C_CVar.SetCVar("SoftTargetInteract", 1)
		assert.is_false(ns.interactState().ok)
		assert.matches("gamepad only.*turned off by Plater", mock.chat[#mock.chat])
	end)

	it("fixinteract waits for combat to end", function()
		mock.login(nil)
		mock.cvars.SoftTargetInteract = "0"
		mock.combat = true
		SlashCmdList.FARMROUTE("fixinteract")
		assert.equals("0", mock.cvars.SoftTargetInteract)
		assert.matches("in combat", mock.chat[#mock.chat])
	end)

	it("keybind functions move both ways", function()
		mock.login(nil)
		FarmRoute.Prev()
		assert.equals(14, ns.currentIndex())
		FarmRoute.Next()
		assert.equals(1, ns.currentIndex())
		assert.equals(2, ns.counters.advanceKey)
	end)

	it("respawn timers grey out passed points and the loop skips them", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("route Angor Dented")
		SlashCmdList.FARMROUTE("respawn 5")
		FarmRoute.Next() -- 1 -> 2, point 1 down
		assert.equals(mock.now + 300, FarmRouteDB.timers["Angor Dented"][1])
		SlashCmdList.FARMROUTE("goto 7")
		FarmRoute.Next() -- 7 -> 1 is down -> 2
		assert.equals(2, ns.currentIndex())
	end)

	it("off removes only its own waypoint", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("on")
		mock.waypoint = { uiMapID = 1, position = { x = 0.1, y = 0.1 } }
		SlashCmdList.FARMROUTE("off")
		assert.equals(1, mock.waypoint.uiMapID)
	end)

	it("imports /way lines into the active route", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("new Test")
		ns.importPoints(ns.Logic.parseImport("/way #1418 10 10\n/way 20 20 b", 1418), false)
		assert.equals(2, #ns.activeRoute().points)
		SlashCmdList.FARMROUTE("del 1")
		assert.equals(1, #ns.activeRoute().points)
	end)

	it("falls back to TomTom with arrival clearing off", function()
		local opts
		_G.TomTom = {
			AddWaypoint = function(_, _, _, _, o)
				opts = o
				return {}
			end,
			RemoveWaypoint = function() end,
		}
		mock.login(nil)
		SlashCmdList.FARMROUTE("mode tomtom")
		SlashCmdList.FARMROUTE("on")
		assert.equals(0, opts.cleardistance)
		assert.is_false(opts.persistent)
		assert.equals("tomtom", ns.Nav.state.mode)
	end)

	it("probe logs a footlocker appearing and going, with the nearest point and the skill it needs", function()
		mock.login(nil)
		local p = ns.activeRoute().points[7]
		mock.pos = { p.x + 10 / mock.YARDS, p.y }
		mock.soft = {
			guid = "GameObject-0-1-0-12-179490-00001",
			name = "Battered Footlocker",
			tooltip = { "Battered Footlocker", "Requires Lockpicking (150)" },
			plate = true,
		}
		mock.fire("PLAYER_SOFT_INTERACT_CHANGED")
		assert.is_nil(ns.selftest.lastError)
		local ev = FarmRouteDB.probe.events[1]
		assert.equals("seen", ev.kind)
		assert.equals(179490, ev.objectID)
		assert.equals(150, ev.need)
		assert.equals("Angor Battered 7", ev.point)
		assert.near(10, ev.pointYd, 0.1)
		assert.equals(30, ev.z)
		assert.matches("Battered Footlocker %(179490%), needs Lockpicking 150", table.concat(mock.chat, "\n"))
		mock.soft = nil
		mock.tick()
		assert.equals("gone", FarmRouteDB.probe.events[2].kind)
		local st = ns.selftest.snapshot("t").detect
		assert.equals(1, st.objects["179490"].seen)
		assert.equals(169, st.lockpicking)
		assert.equals("3", st.cvars.SoftTargetInteract)
		assert.is_nil(ns.selftest.lastError)
	end)

	it("probe chat names only chests of the active route; chairs stay in the log", function()
		mock.login(nil)
		mock.soft = { guid = "GameObject-0-1-0-12-61088-00001", name = "Wooden Chair", tooltip = {} }
		mock.fire("PLAYER_SOFT_INTERACT_CHANGED")
		assert.is_nil(table.concat(mock.chat, "\n"):find("Wooden Chair"))
		assert.equals(61088, FarmRouteDB.probe.events[1].objectID)
	end)

	it("probe keeps secret soft-interact values out of the saved log", function()
		mock.login(nil)
		local guid = "GameObject-0-1-0-12-179490-00001"
		mock.secret[guid] = true
		mock.secret["Battered Footlocker"] = true
		mock.soft = { guid = guid, name = "Battered Footlocker", tooltip = { "Battered Footlocker" } }
		mock.fire("PLAYER_SOFT_INTERACT_CHANGED")
		for _, ev in ipairs(FarmRouteDB.probe.events) do
			assert.is_nil(ev.objectID)
			assert.is_nil(ev.name)
		end
		assert.is_true(ns.Detect.status.secret > 0)
	end)

	it("learns chest spawns from loot: confirms a seed, then adds a new point and moves the history", function()
		mock.login(nil)
		local route = ns.activeRoute()
		local p1 = route.points[1]
		-- a Battered Footlocker looted 9 yd east of seed 1
		mock.pos = { p1.x + 9 / mock.YARDS, p1.y }
		mock.loot = { "GameObject-0-1-2-3-179490-0000" }
		mock.fire("LOOT_OPENED")
		assert.equals("confirm", FarmRouteDB.finds[1].action)
		assert.equals(1, route.points[1].finds)
		assert.near(mock.pos[1], route.points[1].x, 1e-9)
		-- far from every point: a new spawn; history keyed by index follows the insert
		-- the same chest opened again is no new find
		mock.fire("LOOT_OPENED")
		assert.equals(1, #FarmRouteDB.finds)
		FarmRouteDB.history["Angor Battered"] = { [14] = { visits = { { t = 1, seen = true } } } }
		-- the same chest kind far from the route (another place): not learned
		mock.pos = { 0.30, 0.30 }
		mock.loot = { "GameObject-0-1-2-3-179490-0002" }
		mock.fire("LOOT_OPENED")
		assert.equals(1, #FarmRouteDB.finds)
		-- 25 yd west and north of point 1, 40+ yd from every other point: a new spawn
		mock.pos = { 0.408 - 25 / mock.YARDS, 0.267 - 25 / mock.YARDS }
		mock.loot = { "GameObject-0-1-2-3-179490-0001" }
		mock.fire("LOOT_OPENED")
		assert.equals("new", FarmRouteDB.finds[2].action)
		assert.equals(15, #route.points)
		local at = FarmRouteDB.finds[2].point
		assert.equals(1, route.points[at].finds)
		local moved = at <= 14 and 15 or 14
		assert.is_not_nil(FarmRouteDB.history["Angor Battered"][moved])
		-- a Dented loot doesn't touch the Battered route
		mock.loot = { "GameObject-0-1-2-3-179492-0000" }
		mock.fire("LOOT_OPENED")
		assert.equals("Angor Dented", FarmRouteDB.finds[3].route)
		assert.equals(15, #route.points)
		assert.is_nil(FarmRouteDB.selftest.lastError)
	end)

	it("/fr learn records a walk and accept saves path points the pin goes through", function()
		mock.login(nil)
		SlashCmdList.FARMROUTE("new Test")
		local Y = mock.YARDS
		local function at(x, y)
			mock.pos = { 0.5 + x / Y, 0.5 + y / Y }
		end
		at(0, 0)
		SlashCmdList.FARMROUTE("add A")
		at(30, 30)
		SlashCmdList.FARMROUTE("add B")
		SlashCmdList.FARMROUTE("learn on")
		for x = 0, 30, 3 do
			at(x, 0)
			mock.tick()
		end
		for y = 3, 30, 3 do
			at(30, y)
			mock.tick()
		end
		SlashCmdList.FARMROUTE("learn off")
		assert.equals(1, #FarmRouteDB.learn.Test.plan.suggestions)
		assert.equals(1, #ns.learnView().suggestions)
		SlashCmdList.FARMROUTE("learn accept")
		local route = ns.activeRoute()
		assert.equals(3, #route.points)
		assert.equals("path", route.points[2].kind)
		assert.is_nil(FarmRouteDB.learn.Test)
		-- from A the pin goes to the via first, the objective stays B
		SlashCmdList.FARMROUTE("goto 1")
		at(0, 0)
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		mock.gameTime = mock.gameTime + 1
		mock.tick()
		assert.equals(3, ns.currentIndex())
		assert.equals(2, ns.pinIndex())
		assert.equals("path", ns.markerInfo().state)
		at(30, 1)
		mock.tick()
		assert.equals(3, ns.pinIndex())
		assert.is_nil(FarmRouteDB.selftest.lastError)
	end)
end)
