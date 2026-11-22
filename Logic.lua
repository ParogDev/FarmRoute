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

local function seedRoute(name, label, floor, coords)
	local points = {}
	for i, c in ipairs(coords) do
		points[i] = { mapID = BADLANDS, x = c[1] / 100, y = c[2] / 100, label = label .. " " .. i, floor = floor }
	end
	return { name = name, points = points, respawn = 0 }
end

function L.seedRoutes()
	return {
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
-- waiting = true. Returns nil for an empty route.
function L.nextIndex(route, timers, from, dir, now)
	local n = #route.points
	if n == 0 then
		return nil
	end
	from = from or (dir > 0 and 0 or 1)
	local soonest, soonestAt
	for k = 1, n do
		local i = L.wrap(from + dir * k, n)
		if L.isUp(timers, i, now) then
			return i, false
		end
		if not soonestAt or timers[i] < soonestAt then
			soonest, soonestAt = i, timers[i]
		end
	end
	return soonest, true
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

function L.formatPoint(route, i)
	local p = route.points[i]
	if not p then
		return "?"
	end
	local s = string.format("%d/%d %s (%.1f, %.1f)", i, #route.points, p.label or "point", p.x * 100, p.y * 100)
	if p.floor then
		s = s .. " " .. p.floor
	end
	return s
end
