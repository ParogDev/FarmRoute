-- The route on the maps: lines and dots on the world map canvas (own textures), and a dotted path on the
-- minimap through HereBeDragons-Pins when another addon has loaded it (TomTom, Questie and others embed it).
-- The current segment (previous point -> current point) is gold; points on a respawn timer are grey.
local _, ns = ...

local M = {}
ns.MapLines = M

local GOLD = { 1, 0.82, 0, 0.95 }
local BLUE = { 0.35, 0.7, 1, 0.75 }
local GREY = { 0.5, 0.5, 0.5, 0.6 }
local MINIMAP_STEP = 5 -- yards between minimap dots

M.status = { world = "not drawn yet", minimap = "not drawn yet" }

local overlay, lines, dots = nil, {}, {}

local function routeView()
	local route = ns.activeRoute and ns.activeRoute()
	if not route or #route.points == 0 then
		return nil
	end
	return route, ns.currentIndex(), ns.timersFor(route.name), time()
end

-- ---------------------------------------------------------------------------------------------------------
-- World map
-- ---------------------------------------------------------------------------------------------------------
local function hideFrom(list, first)
	for i = first, #list do
		list[i]:Hide()
	end
end

function M.refreshWorld()
	if not overlay or not WorldMapFrame:IsShown() then
		return
	end
	local route, current, timers, now = routeView()
	local shown = WorldMapFrame:GetMapID()
	if not route or not ns.db.settings.mapLines then
		hideFrom(lines, 1)
		hideFrom(dots, 1)
		M.status.world = route and "off" or "no route"
		return
	end
	local w, h = overlay:GetWidth(), overlay:GetHeight()
	local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
	local L = ns.Logic
	local n = #route.points
	local li, di = 0, 0
	for a = 1, n do
		local pa = route.points[a]
		local b = L.wrap(a + 1, n)
		local pb = route.points[b]
		if pa.mapID == shown and pb.mapID == shown and n > 1 then
			li = li + 1
			local ln = lines[li]
			if not ln then
				ln = overlay:CreateLine(nil, "OVERLAY")
				lines[li] = ln
			end
			local cur = L.isCurrentSegment(n, current, a, b)
			local c = cur and GOLD or ((L.isUp(timers, a, now) and L.isUp(timers, b, now)) and BLUE or GREY)
			ln:SetColorTexture(c[1], c[2], c[3], c[4])
			ln:SetThickness((cur and 4 or 2) / scale)
			ln:SetStartPoint("TOPLEFT", overlay, pa.x * w, -pa.y * h)
			ln:SetEndPoint("TOPLEFT", overlay, pb.x * w, -pb.y * h)
			ln:Show()
		end
		if pa.mapID == shown then
			di = di + 1
			local d = dots[di]
			if not d then
				d = overlay:CreateTexture(nil, "OVERLAY", nil, 7)
				dots[di] = d
			end
			local c = a == current and GOLD or (L.isUp(timers, a, now) and BLUE or GREY)
			local size = (a == current and 10 or 6) / scale
			d:SetColorTexture(c[1], c[2], c[3], 1)
			d:SetSize(size, size)
			d:ClearAllPoints()
			d:SetPoint("CENTER", overlay, "TOPLEFT", pa.x * w, -pa.y * h)
			d:Show()
		end
	end
	hideFrom(lines, li + 1)
	hideFrom(dots, di + 1)
	M.status.world = di > 0 and ("drawn on map " .. tostring(shown)) or ("route not on map " .. tostring(shown))
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
-- Minimap (HereBeDragons-Pins, optional)
-- ---------------------------------------------------------------------------------------------------------
local pool, used = {}, 0
local REF = "FarmRoute"

local function pins()
	return LibStub and LibStub("HereBeDragons-Pins-2.0", true)
end

local function dot(size, c)
	used = used + 1
	local f = pool[used]
	if not f then
		f = CreateFrame("Frame")
		f.tex = f:CreateTexture(nil, "OVERLAY")
		f.tex:SetAllPoints(f)
		f:EnableMouse(false)
		pool[used] = f
	end
	f:SetSize(size, size)
	f.tex:SetColorTexture(c[1], c[2], c[3], c[4])
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
	local route, current, timers, now = routeView()
	if not route or not ns.db.settings.minimapDots then
		M.status.minimap = route and "off" or "no route"
		return
	end
	local L, Nav = ns.Logic, ns.Nav
	local n = #route.points
	for a = 1, n do
		local pa = route.points[a]
		local b = L.wrap(a + 1, n)
		local pb = route.points[b]
		local up = L.isUp(timers, a, now)
		hbdp:AddMinimapIconMap(
			REF,
			dot(a == current and 7 or 5, a == current and GOLD or (up and BLUE or GREY)),
			pa.mapID,
			pa.x,
			pa.y,
			false,
			false
		)
		if n > 1 and pa.mapID == pb.mapID then
			local c1, x1, y1 = Nav.worldPos(pa.mapID, pa.x, pa.y)
			local c2, x2, y2 = Nav.worldPos(pb.mapID, pb.x, pb.y)
			if c1 and c2 then
				local cur = L.isCurrentSegment(n, current, a, b)
				local c = cur and GOLD or ((up and L.isUp(timers, b, now)) and BLUE or GREY)
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
