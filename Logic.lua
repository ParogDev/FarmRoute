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
		if not checked[i] and L.isUp(timers, i, now) then
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
		if not checked[i] and L.isCold(hist, i) then
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
	return s
end
