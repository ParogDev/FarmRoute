-- The route on the maps: lines and dots on the world map canvas (own textures), and a dotted path on the
-- minimap through HereBeDragons-Pins when another addon has loaded it (TomTom, Questie and others embed it).
-- The current segment (previous point -> the pin) is gold; points on a respawn timer are grey.
--
-- One shape per kind of point, the same idea as the in-world marker (a diamond is a chest):
--   chest        solid diamond (a real loot confirmed it)
--   unconfirmed  hollow diamond (a seed coordinate nobody has looted yet)
--   path         small upright square the line runs through (a corner to walk, not a stop)
--   dropped      faint grey speck, left out of the loop
-- Hollow always means "not confirmed yet", so a proposed path point of learn mode is a hollow square.
-- Learn mode draws in teal, a colour the route never uses: the walked trail, the chests it passed (a teal
-- edge around their diamond) and the proposed path points.
local _, ns = ...

local M = {}
ns.MapLines = M

local GOLD = { 1, 0.82, 0, 0.95 }
local BLUE = { 0.35, 0.7, 1, 0.75 }
local GREY = { 0.5, 0.5, 0.5, 0.6 }
local FAINT = { 0.5, 0.5, 0.5, 0.35 } -- dropped
local INK = { 0.06, 0.05, 0.04, 0.9 } -- the hole of a hollow point
local TEAL = { 0.45, 0.95, 0.85, 0.6 }
local QUARTER = math.pi / 4
local MINIMAP_STEP = 5 -- yards between minimap dots
local TRAIL_MAX = 150 -- trail segments drawn at most: a longer walk is thinned, the map can't show more

M.status = { world = "not drawn yet", minimap = "not drawn yet", learn = "not learning" }

local overlay
local lines, dots, cores = {}, {}, {}
local trail, marks, markCores = {}, {}, {}

-- A route the picker is showing on the world map instead of the active one (a name, or nil).
M.preview = nil

local function routeView()
	local previewed = M.preview and ns.db and ns.db.routes[M.preview]
	if previewed and #previewed.points > 0 then
		return previewed, nil, ns.timersFor(previewed.name), time()
	end
	local route = ns.activeRoute and ns.activeRoute()
	if not route or #route.points == 0 then
		return nil
	end
	local pin = ns.pinIndex and ns.pinIndex() or ns.currentIndex()
	return route, pin, ns.timersFor(route.name), time()
end

-- status[i] for every point, and the indices still in the loop (everything but the dropped ones).
local function loopOf(route)
	local L = ns.Logic
	local hist = ns.historyFor and ns.historyFor(route.name)
	local status, loop = {}, {}
	for a = 1, #route.points do
		local st = L.pointStatus and L.pointStatus(route, hist, a) or "chest"
		status[a] = st
		if st ~= "dropped" then
			loop[#loop + 1] = a
		end
	end
	return status, loop
end

-- The k-th segment of the loop: from, to, and whether it is the one that ends at the pin. A loop of two
-- is one segment, not the same line drawn twice.
local function segment(loop, k, pin)
	local a, b = loop[k], loop[k % #loop + 1]
	return a, b, b == pin or (#loop == 2 and a == pin)
end

local function segmentCount(loop)
	return #loop < 2 and 0 or (#loop == 2 and 1 or #loop)
end

-- How a point looks: size in pixels, colour, hole size (nil = solid), diamond or upright.
local function pointStyle(st, isPin, up, mini)
	if st == "dropped" and not isPin then
		return mini and 2 or 3, FAINT, nil, false
	end
	local c = isPin and GOLD or (up and BLUE or GREY)
	if st == "path" then
		if mini then
			return isPin and 5 or 3, c, nil, false
		end
		return isPin and 8 or 4, c, isPin and 4 or nil, false
	end
	local hollow = st == "unconfirmed"
	if mini then
		return isPin and 7 or 5, c, hollow and 3 or nil, false
	end
	if hollow then
		return isPin and 11 or 8, c, isPin and 6 or 4, true
	end
	return isPin and 10 or 6, c, nil, true
end

-- ---------------------------------------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------------------------------------
local function hideFrom(list, first)
	for i = first, #list do
		list[i]:Hide()
	end
end

-- The i-th texture of a pool, sized, coloured, turned and placed (x, y in canvas pixels from TOPLEFT).
local function place(list, i, sub, c, alpha, size, x, y, turned)
	local d = list[i]
	if not d then
		d = overlay:CreateTexture(nil, "OVERLAY", nil, sub)
		list[i] = d
	end
	d:SetColorTexture(c[1], c[2], c[3], alpha)
	d:SetSize(size, size)
	if d.SetRotation then
		d:SetRotation(turned and QUARTER or 0) -- pooled: the last user may have left it turned
	end
	d:ClearAllPoints()
	d:SetPoint("CENTER", overlay, "TOPLEFT", x, y)
	d:Show()
end

local function stroke(list, i, layer, c, alpha, thickness, x1, y1, x2, y2)
	local ln = list[i]
	if not ln then
		ln = overlay:CreateLine(nil, layer)
		list[i] = ln
	end
	ln:SetColorTexture(c[1], c[2], c[3], alpha)
	ln:SetThickness(thickness)
	ln:SetStartPoint("TOPLEFT", overlay, x1, y1)
	ln:SetEndPoint("TOPLEFT", overlay, x2, y2)
	ln:Show()
end

local function drawRoute(shown, w, h, scale)
	local route, pin, timers, now = routeView()
	if not route or not ns.db.settings.mapLines then
		hideFrom(lines, 1)
		hideFrom(dots, 1)
		hideFrom(cores, 1)
		M.status.world = route and "off" or "no route"
		return
	end
	local L = ns.Logic
	local status, loop = loopOf(route)
	local li, di, ci = 0, 0, 0
	for k = 1, segmentCount(loop) do
		local a, b, cur = segment(loop, k, pin)
		local pa, pb = route.points[a], route.points[b]
		if pa.mapID == shown and pb.mapID == shown then
			li = li + 1
			local c = cur and GOLD or ((L.isUp(timers, a, now) and L.isUp(timers, b, now)) and BLUE or GREY)
			stroke(lines, li, "OVERLAY", c, c[4], (cur and 4 or 2) / scale, pa.x * w, -pa.y * h, pb.x * w, -pb.y * h)
		end
	end
	for a = 1, #route.points do
		local pa = route.points[a]
		if pa.mapID == shown then
			local size, c, hole, turned = pointStyle(status[a], a == pin, L.isUp(timers, a, now), false)
			local x, y = pa.x * w, -pa.y * h
			di = di + 1
			place(dots, di, 5, c, c == FAINT and c[4] or 1, size / scale, x, y, turned)
			if hole then
				ci = ci + 1
				place(cores, ci, 6, INK, INK[4], hole / scale, x, y, turned)
			end
		end
	end
	hideFrom(lines, li + 1)
	hideFrom(dots, di + 1)
	hideFrom(cores, ci + 1)
	M.status.world = di > 0 and ("drawn on map " .. tostring(shown)) or ("route not on map " .. tostring(shown))
end

-- Learn mode: what was walked and what would be saved. Under the route (lower sublevels), so a chest the
-- walk passed shows as a teal edge around its diamond.
local function drawLearn(shown, w, h, scale)
	local view = ns.learnView and ns.learnView()
	if not view or view.mapID ~= shown then
		hideFrom(trail, 1)
		hideFrom(marks, 1)
		hideFrom(markCores, 1)
		M.status.learn = view and ("trail is on map " .. tostring(view.mapID)) or "not learning"
		return
	end
	local runs = view.runs or {}
	local n, segs = 0, 0
	for _, run in ipairs(runs) do
		n = n + #run
		segs = segs + math.max(0, #run - 1)
	end
	local ti, mi, ki = 0, 0, 0
	local alpha = view.recording and TEAL[4] or 0.45 -- a finished walk steps back a little
	local step = math.max(1, math.ceil(segs / TRAIL_MAX))
	-- each run is its own line: nothing is drawn across a gap in the walk
	for _, samples in ipairs(runs) do
		local i = 1
		while i < #samples do
			local j = math.min(i + step, #samples)
			local a, b = samples[i], samples[j]
			ti = ti + 1
			stroke(trail, ti, "ARTWORK", TEAL, alpha, 1.5 / scale, a.x * w, -a.y * h, b.x * w, -b.y * h)
			i = j
		end
	end
	for _, v in ipairs(view.visits or {}) do
		mi = mi + 1
		place(marks, mi, 2, TEAL, 0.8, 10 / scale, v.x * w, -v.y * h, true)
	end
	for _, s in ipairs(view.suggestions or {}) do
		mi = mi + 1
		place(marks, mi, 3, TEAL, 1, 8 / scale, s.x * w, -s.y * h, false)
		ki = ki + 1
		place(markCores, ki, 4, INK, INK[4], 4 / scale, s.x * w, -s.y * h, false)
	end
	if view.recording and view.head then
		-- the head of the trail: where the recording is now
		mi = mi + 1
		place(marks, mi, 4, TEAL, 1, 5 / scale, view.head.x * w, -view.head.y * h, false)
	end
	hideFrom(trail, ti + 1)
	hideFrom(marks, mi + 1)
	hideFrom(markCores, ki + 1)
	M.status.learn = string.format(
		"%s: %d samples in %d lines, %d suggestions, %d visits",
		view.recording and "recording" or "review",
		n,
		ti,
		#(view.suggestions or {}),
		#(view.visits or {})
	)
end

function M.refreshWorld()
	if not overlay or not WorldMapFrame:IsShown() then
		return
	end
	local shown = WorldMapFrame:GetMapID()
	local w, h = overlay:GetWidth(), overlay:GetHeight()
	local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
	drawRoute(shown, w, h, scale)
	drawLearn(shown, w, h, scale)
end

function M.initWorld()
	if not WorldMapFrame or not WorldMapFrame.GetCanvas then
		M.status.world = "WorldMapFrame has no canvas"
		return
	end
	overlay = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
	overlay:SetAllPoints(WorldMapFrame:GetCanvas())
	overlay:SetFrameLevel(WorldMapFrame:GetCanvas():GetFrameLevel() + 2000)
	overlay:EnableMouse(false)
	WorldMapFrame:HookScript("OnShow", M.refreshWorld)
	hooksecurefunc(WorldMapFrame, "OnMapChanged", M.refreshWorld)
	if WorldMapFrame.OnCanvasScaleChanged then
		hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", M.refreshWorld)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Minimap (HereBeDragons-Pins, optional). Too small for diamonds: size and the hole carry the kinds.
-- ---------------------------------------------------------------------------------------------------------
local pool, used = {}, 0
local REF = "FarmRoute"

local function pins()
	return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local function dot(size, c, hole)
	used = used + 1
	local f = pool[used]
	if not f then
		f = CreateFrame("Frame")
		f.tex = f:CreateTexture(nil, "OVERLAY")
		f.tex:SetAllPoints(f)
		f.core = f:CreateTexture(nil, "OVERLAY", nil, 1)
		f.core:SetPoint("CENTER")
		f.core:SetColorTexture(INK[1], INK[2], INK[3], INK[4])
		f:EnableMouse(false)
		pool[used] = f
	end
	f:SetSize(size, size)
	f.tex:SetColorTexture(c[1], c[2], c[3], c[4])
	f.core:SetShown(hole ~= nil)
	if hole then
		f.core:SetSize(hole, hole)
	end
	return f
end

function M.refreshMinimap()
	local hbdp = pins()
	if not hbdp then
		M.status.minimap = "HereBeDragons-Pins not loaded (install TomTom or Questie): minimap path off"
		return
	end
	hbdp:RemoveAllMinimapIcons(REF)
	used = 0
	local route, pin, timers, now = routeView()
	if not route or not ns.db.settings.minimapDots then
		M.status.minimap = route and "off" or "no route"
		return
	end
	local L, Nav = ns.Logic, ns.Nav
	local status, loop = loopOf(route)
	for a = 1, #route.points do
		local pa = route.points[a]
		local size, c, hole = pointStyle(status[a], a == pin, L.isUp(timers, a, now), true)
		hbdp:AddMinimapIconMap(REF, dot(size, c, hole), pa.mapID, pa.x, pa.y, false, false)
	end
	for k = 1, segmentCount(loop) do
		local a, b, cur = segment(loop, k, pin)
		local pa, pb = route.points[a], route.points[b]
		if pa.mapID == pb.mapID then
			local c1, x1, y1 = Nav.worldPos(pa.mapID, pa.x, pa.y)
			local c2, x2, y2 = Nav.worldPos(pb.mapID, pb.x, pb.y)
			if c1 and c2 then
				local c = cur and GOLD or ((L.isUp(timers, a, now) and L.isUp(timers, b, now)) and BLUE or GREY)
				for _, f in ipairs(L.dotFractions(L.distance(x1, y1, x2, y2), MINIMAP_STEP)) do
					local x, y = pa.x + (pb.x - pa.x) * f, pa.y + (pb.y - pa.y) * f
					hbdp:AddMinimapIconMap(REF, dot(cur and 3 or 2, c), pa.mapID, x, y, false, false)
				end
			end
		end
	end
	for i = used + 1, #pool do
		pool[i]:Hide()
	end
	M.status.minimap = used .. " minimap dots"
end

function M.refresh()
	M.refreshWorld()
	M.refreshMinimap()
end
