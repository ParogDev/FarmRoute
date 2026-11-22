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
		assert.equals(2, ns.currentIndex())
		assert.equals(14, #route.points)
		assert.near(route.points[2].x, mock.waypoint.position.x, 1e-9)
		-- within MIN_GAP nothing more happens even when standing on the next point
		mock.pos = { route.points[2].x, route.points[2].y }
		mock.tick()
		assert.equals(2, ns.currentIndex())
		SlashCmdList.FARMROUTE("goto 14")
		mock.pos = { route.points[14].x, route.points[14].y }
		mock.gameTime = mock.gameTime + 5
		mock.tick()
		assert.equals(1, ns.currentIndex())
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
		mock.waypoint = { uiMapID = 1, position = {
			GetXY = function()
				return 0.1, 0.1
			end,
		} }
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
end)
