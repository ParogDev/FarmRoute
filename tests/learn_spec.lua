local ns = {}
assert(loadfile("Logic.lua"))("FarmRoute", ns)
local L = ns.Logic

-- points in yards directly (x, y), so distances read plainly
local function route(pts)
	local points = {}
	for i, p in ipairs(pts) do
		points[i] = { mapID = 1, x = p[1], y = p[2], kind = p.kind, finds = p.finds, manual = p.manual }
	end
	return { name = "r", points = points }
end

local function yards(r)
	local list = {}
	for i, p in ipairs(r.points) do
		list[i] = { i = i, x = p.x, y = p.y, point = p }
	end
	return list
end

local function emptyVisits(n)
	local v = {}
	for k = 1, n do
		v[k] = { t = k, seen = false }
	end
	return { visits = v }
end

describe("point kinds", function()
	it("path points are never stops; dropped seeds leave the loop once the route has confirmed points", function()
		local r = route({ { 0, 0 }, { 10, 0, kind = "path" }, { 20, 0 }, { 30, 0, finds = 2 } })
		local hist = { [3] = emptyVisits(L.DROP_VISITS) }
		assert.equals("unconfirmed", L.pointStatus(r, {}, 1))
		assert.equals("path", L.pointStatus(r, hist, 2))
		assert.equals("dropped", L.pointStatus(r, hist, 3))
		assert.equals("chest", L.pointStatus(r, hist, 4))
		-- objective from 1 skips the path point and the dropped seed
		assert.equals(4, (L.objective(r, {}, {}, hist, 1, 0)))
		assert.equals(4, (L.nextIndex(r, {}, 1, 1, 0, hist)))
		-- with no confirmed point, nothing drops
		r.points[4].finds = nil
		assert.equals("unconfirmed", L.pointStatus(r, hist, 3))
	end)
	it("never drops a point added by hand", function()
		local r = route({ { 0, 0, manual = true }, { 30, 0, finds = 1 } })
		assert.is_true(L.inLoop(r, { [1] = emptyVisits(10) }, 1))
	end)
end)

describe("finds", function()
	local r
	before_each(function()
		r = route({ { 0, 0, finds = 1 }, { 40, 0 }, { 40, 40 }, { 0, 40, finds = 3 } })
	end)

	it("merges a find near a confirmed point into its running mean", function()
		local action, i = L.findTarget(r, yards(r), 3, 0)
		assert.equals("merge", action)
		assert.equals(1, i)
		L.mergeFind(r.points[1], 3, 0)
		assert.equals(2, r.points[1].finds)
		assert.near(1.5, r.points[1].x, 1e-9)
	end)

	it("confirms the nearest seed within SEED_YD and takes the find's coordinate", function()
		local action, i = L.findTarget(r, yards(r), 40, 12)
		assert.equals("confirm", action)
		assert.equals(2, i)
		L.mergeFind(r.points[2], 40, 12)
		assert.equals(1, r.points[2].finds)
		assert.equals(12, r.points[2].y)
	end)

	it("adds a new point at the cheapest place in the loop", function()
		local action, at = L.findTarget(r, yards(r), 20, -3)
		assert.equals("new", action)
		assert.equals(2, at) -- between 1 (0,0) and 2 (40,0)
		local map = L.insertMap(4, at)
		assert.same({ 1, 3, 4, 5 }, map)
		assert.same({ [3] = "a", [5] = "b" }, L.remap({ [2] = "a", [4] = "b" }, map))
	end)
end)

describe("vias", function()
	it("lists the path points between two chests and moves past reached ones", function()
		local r = route({ { 0, 0 }, { 5, 0, kind = "path" }, { 10, 0, kind = "path" }, { 20, 0 } })
		assert.same({ 2, 3 }, L.viasBetween(r, 1, 4))
		assert.same({}, L.viasBetween(r, 4, 1))
		-- a one-chest loop walks all its path points
		assert.same({ 2, 3 }, L.viasBetween(r, 1, 1))
		-- 1 yd from via 1 (inside the 3 yd radius), 6 yd from via 2 and not past it: the pin goes to via 2
		assert.equals(2, L.nextVia(1, { 1, 6 }, { 6, 12 }, { 5, 10 }, 3))
		-- 7 yd past via 1 (closer to via 2 than via 1 is) and near it: passed
		assert.equals(2, L.nextVia(1, { 7, 4 }, { 4, 12 }, { 5, 10 }, 3))
		-- a detour via: the player is closer to the chest than the via, but far from it: not skipped
		assert.equals(1, L.nextVia(1, { 15, 14 }, { 2, 12 }, { 5, 10 }, 3))
	end)

	it("a stretch not walked straight has no vias, even before the closing one", function()
		local plan = { order = { 1, 2, 3 }, vias = { [2] = { "b" } }, closing = { "c" } }
		assert.same({}, L.planVias(plan, 1))
		assert.same({ "b" }, L.planVias(plan, 2))
		assert.same({ "c" }, L.planVias(plan, 3))
	end)

	it("drops a seed only for its last visits being empty", function()
		local r = route({ { 0, 0 }, { 30, 0, finds = 1 } })
		local h = emptyVisits(L.DROP_VISITS)
		table.insert(h.visits, 1, { t = 0, seen = true })
		assert.is_true(L.isDropped(r, { [1] = h }, 1))
		h.visits[#h.visits].seen = true
		assert.is_false(L.isDropped(r, { [1] = h }, 1))
	end)
end)

describe("learning a walk", function()
	it("samples every few yards", function()
		assert.is_true(L.shouldSample(nil, 0, 0))
		assert.is_false(L.shouldSample({ x = 0, y = 0 }, 2, 0, 3))
		assert.is_true(L.shouldSample({ x = 0, y = 0 }, 3, 0, 3))
	end)

	it("simplifies a polyline with Douglas-Peucker", function()
		local pts = { { x = 0, y = 0 }, { x = 5, y = 0.5 }, { x = 10, y = 0 }, { x = 10, y = 10 } }
		local out = L.simplify(pts, 3)
		assert.equals(3, #out)
		assert.equals(10, out[2].x)
		assert.equals(0, out[2].y)
	end)

	it("suggests the corner of an L-shaped walk between two chests, in walking order", function()
		-- chest A at (0,0), chest B at (30,30); the walk goes east along y = 0 then north along x = 30
		local chests = { { i = 1, x = 30, y = 30 }, { i = 2, x = 0, y = 0 } }
		local samples = {}
		for x = 0, 30, 3 do
			samples[#samples + 1] = { x = x, y = 0 }
		end
		for y = 3, 30, 3 do
			samples[#samples + 1] = { x = 30, y = y }
		end
		local plan = L.learnPlan(samples, chests)
		assert.same({ 2, 1 }, plan.order)
		assert.equals(1, #plan.vias[1])
		assert.equals(30, plan.vias[1][1].x)
		assert.equals(0, plan.vias[1][1].y)
		assert.is_nil(plan.closing)

		local entries = {
			{ i = 1, x = 30, y = 30, point = { name = "B" } },
			{ i = 2, x = 0, y = 0, point = { name = "A" } },
			{ i = 3, x = 31, y = 0, point = { name = "old path", kind = "path" } },
			{ i = 4, x = 60, y = 30, point = { name = "C" } },
		}
		local points, map = L.applyPlan(entries, plan, function(s)
			return { name = "via", kind = "path", x = s.x, y = s.y }
		end)
		-- the old path point is replaced; C, missed by the walk, goes back in after a chest's vias
		assert.equals(4, #points)
		assert.equals("A", points[1].name)
		assert.equals("via", points[2].name)
		assert.is_nil(map[3])
		assert.equals("A", points[map[2]].name)
		assert.equals("B", points[map[1]].name)
		assert.equals("C", points[map[4]].name)
		assert.is_true(map[4] > 2)
	end)
end)
