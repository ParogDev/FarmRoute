local ns = {}
assert(loadfile("Logic.lua"))("FarmRoute", ns)
local L = ns.Logic

describe("seed routes", function()
	it("has the Angor upstairs and downstairs loops on Badlands", function()
		local r = L.seedRoutes()
		assert.equals("Angor Battered", r[1].name)
		assert.equals(14, #r[1].points)
		assert.equals(7, #r[2].points)
		assert.equals(1418, r[1].points[1].mapID)
		assert.near(0.408, r[1].points[1].x, 1e-9)
		assert.equals("upstairs", r[1].points[1].floor)
		assert.equals("downstairs", r[2].points[7].floor)
	end)
end)

describe("parseWay", function()
	it("reads #mapID, coordinates and a label", function()
		local p = L.parseWay("/way #1418 40.8 26.7 Battered chest")
		assert.same({ mapID = 1418, x = 0.408, y = 0.267, label = "Battered chest" }, p)
	end)
	it("takes commas between x and y and decimal commas", function()
		assert.near(0.408, L.parseWay("/way 40.8, 26.7", 1418).x, 1e-9)
		local p = L.parseWay("/way 40,8 26,7", 1418)
		assert.near(0.408, p.x, 1e-9)
		assert.near(0.267, p.y, 1e-9)
	end)
	it("uses the default map without #mapID", function()
		assert.equals(99, L.parseWay("/way 10 20", 99).mapID)
	end)
	it("resolves a zone name, or says it can't", function()
		local resolve = function(n)
			return n == "Badlands" and 1418 or nil
		end
		assert.equals(1418, L.parseWay("/way Badlands 40 26", nil, resolve).mapID)
		local p, why = L.parseWay("/way Narnia 40 26", nil, resolve)
		assert.is_nil(p)
		assert.matches("Narnia", why)
	end)
	it("names what is missing", function()
		assert.is_nil(L.parseWay("/way hello"))
		local _, why = L.parseWay("/way 40 26")
		assert.matches("no map", why)
		_, why = L.parseWay("/way #1 140 26")
		assert.matches("over 100", why)
	end)
end)

describe("parseImport", function()
	it("keeps good lines and lists bad ones with line numbers", function()
		local pts, errs = L.parseImport("/way #1418 40.8 26.7\n\nrubbish\r\n/way #1418 41.4 26.3 b\n", nil)
		assert.equals(2, #pts)
		assert.equals("b", pts[2].label)
		assert.equals(1, #errs)
		assert.equals(3, errs[1].line)
	end)
end)

describe("walking the loop", function()
	local function route(n, respawn)
		local pts = {}
		for i = 1, n do
			pts[i] = { mapID = 1, x = i / 100, y = 0 }
		end
		return { name = "r", points = pts, respawn = respawn or 0 }
	end

	it("wraps both ways and keeps every point", function()
		local r, t = route(3), {}
		assert.equals(1, (L.advance(r, t, 3, 1, 0)))
		assert.equals(3, (L.advance(r, t, 1, -1, 0)))
		assert.equals(3, #r.points)
	end)

	it("starts a respawn timer going forward only and skips points that are down", function()
		local r, t = route(3, 5), {}
		local i = L.advance(r, t, 1, 1, 100)
		assert.equals(2, i)
		assert.equals(100 + 300, t[1])
		i = L.advance(r, t, 2, 1, 110)
		assert.equals(3, i)
		i = L.advance(r, t, 3, 1, 120) -- 1 and 2 down, 3 just went down
		assert.equals(1, i) -- soonest up
		L.advance(r, t, 3, -1, 130)
		assert.equals(420, t[3])
	end)

	it("a point's own timer beats the route's", function()
		local r = route(2, 5)
		r.points[1].respawn = 1
		assert.equals(1, L.respawnOf(r, 1))
		assert.equals(5, L.respawnOf(r, 2))
	end)

	it("reports waiting when every point is down", function()
		local r, t = route(2), { 50, 40 }
		local i, waiting = L.nextIndex(r, t, 1, 1, 10)
		assert.equals(2, i)
		assert.is_true(waiting)
	end)

	it("prunes run-out timers", function()
		local t = { 5, 50 }
		L.pruneTimers(t, 10)
		assert.is_nil(t[1])
		assert.equals(50, t[2])
	end)

	it("highlights the segment ending at the current point", function()
		assert.is_true(L.isCurrentSegment(5, 1, 5, 1))
		assert.is_true(L.isCurrentSegment(5, 3, 2, 3))
		assert.is_false(L.isCurrentSegment(5, 3, 3, 4))
	end)

	it("spaces minimap dots", function()
		assert.same({ 0.25, 0.5, 0.75 }, L.dotFractions(20, 5))
		assert.same({}, L.dotFractions(0, 5))
	end)

	it("clamps the radius", function()
		assert.equals(2, L.clampRadius(0))
		assert.equals(50, L.clampRadius(500))
		assert.is_nil(L.clampRadius("x"))
	end)
end)

describe("soft-interact reading", function()
	it("takes the object id from a game object GUID only", function()
		assert.equals(179490, L.guidObject("GameObject-0-4170-0-12-179490-0000123ABC"))
		assert.is_nil(L.guidObject("Creature-0-4170-0-12-2725-0000123ABC"))
		assert.is_nil(L.guidObject(nil))
	end)
	it("reads 'Requires Lockpicking (N)' through ITEM_MIN_SKILL", function()
		local pat = L.requiresPattern("Requires %s (%d)")
		local skill, level = L.parseRequires({ "Battered Footlocker", "Requires Lockpicking (150)" }, pat)
		assert.equals("Lockpicking", skill)
		assert.equals(150, level)
		assert.is_nil(L.parseRequires({ "Battered Footlocker", "Locked" }, pat))
	end)
	it("takes positional format strings", function()
		local pat = L.requiresPattern("Benötigt %1$s (%2$d)")
		local skill, level = L.parseRequires({ "Benötigt Schlossknacken (175)" }, pat)
		assert.equals("Schlossknacken", skill)
		assert.equals(175, level)
	end)
	it("keeps a list short", function()
		local t = {}
		for i = 1, 5 do
			L.push(t, i, 3)
		end
		assert.same({ 3, 4, 5 }, t)
	end)
end)

describe("objective", function()
	local function route(n)
		local r = { name = "R", points = {}, respawn = 0 }
		for i = 1, n do
			r.points[i] = { mapID = 1, x = i / 100, y = 0 }
		end
		return r
	end

	it("takes the next point not checked this loop, then says the loop is done", function()
		local r, checked, hist = route(4), {}, {}
		assert.equals(2, (L.objective(r, {}, checked, hist, 1, 0)))
		checked[2], checked[3] = true, true
		assert.equals(4, (L.objective(r, {}, checked, hist, 1, 0)))
		checked[4], checked[1] = true, true
		local i, why = L.objective(r, {}, checked, hist, 4, 0)
		assert.is_nil(i)
		assert.equals("loop done", why)
		L.newLoop(r, checked, hist)
		assert.is_nil(next(checked))
	end)

	it("passes over a point empty on its last three visits, and comes back to it after two loops", function()
		local r, checked, hist = route(3), {}, {}
		for t = 1, 3 do
			L.recordVisit(hist, 2, false, t)
		end
		assert.is_true(L.isCold(hist, 2))
		assert.equals(3, (L.objective(r, {}, checked, hist, 1, 0)))
		-- only cold points left: the cold one, flagged
		checked[1], checked[3] = true, true
		local i, why = L.objective(r, {}, checked, hist, 3, 0)
		assert.equals(2, i)
		assert.equals("cold", why)
		L.newLoop(r, checked, hist)
		L.newLoop(r, checked, hist)
		assert.is_false(L.isCold(hist, 2))
		L.recordVisit(hist, 2, true, 10)
		assert.is_false(L.isCold(hist, 2))
		assert.same({ 1, 4 }, { L.seenRate(hist, 2) })
	end)

	it("skips points on a respawn timer", function()
		local r = route(3)
		assert.equals(3, (L.objective(r, { [2] = 100 }, {}, {}, 1, 50)))
	end)

	it("matches chests by object id when the route lists them, else any locked object", function()
		local battered = { objects = L.SEED_OBJECTS["Angor Battered"] }
		assert.is_true(L.matchesRoute(battered, 179490, 150))
		assert.is_false(L.matchesRoute(battered, 179492, 175))
		assert.is_true(L.matchesRoute({}, 1, 150))
		assert.is_false(L.matchesRoute({}, 1, nil))
	end)

	it("finds the nearest point within range", function()
		local pts = { { i = 1, x = 0, y = 0 }, { i = 2, x = 10, y = 0 }, { i = 3, x = 50, y = 0 } }
		assert.equals(2, (L.nearestIndex(pts, 8, 0, 20)))
		assert.is_nil(L.nearestIndex(pts, 30, 0, 15))
	end)
end)
