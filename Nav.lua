-- Showing the current point: Blizzard's own navigation pin (a user waypoint, super-tracked, which floats in
-- the world with a yards readout), or TomTom's arrow as the fallback; plus the optional on-screen line from
-- the bottom of the screen to the pin. Also the player's position and the distance to a point.
local _, ns = ...

local Nav = {}
ns.Nav = Nav

Nav.MODES = { pin = true, tomtom = true }

-- What the last placement did, for the selftest and /fr: { mode, ok, why, mapID, x, y }
Nav.state = { ok = false, why = "nothing placed yet" }

local tomtomUid

local function setState(t)
	Nav.state = t
	return t.ok, t.why
end

-- ---------------------------------------------------------------------------------------------------------
-- Positions
-- ---------------------------------------------------------------------------------------------------------
local worldCache = {}

-- World yards of a map point: continentID, x, y; or nil and why.
function Nav.worldPos(mapID, x, y)
	local key = mapID .. ":" .. x .. ":" .. y
	local c = worldCache[key]
	if c then
		return c[1], c[2], c[3]
	end
	local ok, continent, vec = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok then
		return nil, "GetWorldPosFromMapPos raised: " .. tostring(continent)
	end
	if not continent or not vec then
		return nil, "map " .. tostring(mapID) .. " has no world position"
	end
	-- C API vectors may come back as plain { x, y } tables without the mixin: read the fields
	local wx, wy = vec.x, vec.y
	worldCache[key] = { continent, wx, wy }
	return continent, wx, wy
end

-- The player's map, x, y; or nil and why ("not now" cases: in an instance, position secret).
function Nav.playerPos()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then
		return nil, "no map for the player (loading screen?)"
	end
	if issecretvalue(mapID) then
		return nil, "player map is a secret value"
	end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then
		return nil, "no player position on map " .. mapID .. " (instance?)"
	end
	local x, y = pos.x, pos.y
	if issecretvalue(x) or issecretvalue(y) then
		return nil, "player position is a secret value"
	end
	return mapID, x, y
end

-- The player's world position: continentID, x, y, mapID, map x, map y; or nil and why. Not cached (it moves).
function Nav.playerWorld()
	local pm, px, py = Nav.playerPos()
	if not pm then
		return nil, px
	end
	local c, x, y = Nav.worldPos(pm, px, py)
	worldCache[pm .. ":" .. px .. ":" .. py] = nil
	if not c then
		return nil, x
	end
	return c, x, y, pm, px, py
end

-- A world position as map fractions on mapID: x, y; or nil and why.
function Nav.mapPos(mapID, continent, wx, wy)
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(wx, wy), mapID)
	if not ok or not pos then
		return nil, "map " .. tostring(mapID) .. " has no position for that world point"
	end
	return pos.x, pos.y
end

-- Yards from the player to a point, or nil and why. Height is not known, so floors share a distance.
function Nav.distanceTo(p)
	local pm, px, py = Nav.playerPos()
	if not pm then
		return nil, px
	end
	local c1, x1, y1 = Nav.worldPos(pm, px, py)
	if not c1 then
		return nil, x1
	end
	local c2, x2, y2 = Nav.worldPos(p.mapID, p.x, p.y)
	if not c2 then
		return nil, x2
	end
	if c1 ~= c2 then
		return nil, "point is on another continent"
	end
	-- the player moves: no cache for the player's own world position
	worldCache[pm .. ":" .. px .. ":" .. py] = nil
	return ns.Logic.distance(x1, y1, x2, y2)
end

-- ---------------------------------------------------------------------------------------------------------
-- Blizzard pin
-- ---------------------------------------------------------------------------------------------------------
local function placePin(p)
	if not C_Map.CanSetUserWaypointOnMap(p.mapID) then
		return setState({ mode = "pin", ok = false, why = "map " .. p.mapID .. " takes no user waypoint" })
	end
	local ok, err = pcall(function()
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.mapID, p.x, p.y))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end)
	if not ok then
		return setState({ mode = "pin", ok = false, why = "SetUserWaypoint raised: " .. tostring(err) })
	end
	return setState({ mode = "pin", ok = true, mapID = p.mapID, x = p.x, y = p.y })
end

-- Is the user waypoint on the map still the one this addon placed?
function Nav.ownsPin()
	local s = Nav.state
	if s.mode ~= "pin" or not s.ok then
		return false
	end
	local wp = C_Map.GetUserWaypoint()
	if not wp or wp.uiMapID ~= s.mapID then
		return false
	end
	local x, y = wp.position.x, wp.position.y
	return math.abs(x - s.x) < 1e-4 and math.abs(y - s.y) < 1e-4
end

-- ---------------------------------------------------------------------------------------------------------
-- TomTom arrow (fallback)
-- ---------------------------------------------------------------------------------------------------------
local function clearTomTom()
	if tomtomUid and TomTom and TomTom.RemoveWaypoint then
		pcall(TomTom.RemoveWaypoint, TomTom, tomtomUid)
	end
	tomtomUid = nil
end

local function placeTomTom(p)
	if not (TomTom and TomTom.AddWaypoint) then
		return setState({ mode = "tomtom", ok = false, why = "TomTom not loaded" })
	end
	clearTomTom()
	local ok, uid = pcall(TomTom.AddWaypoint, TomTom, p.mapID, p.x, p.y, {
		title = p.label or "FarmRoute",
		from = "FarmRoute",
		persistent = false,
		minimap = false,
		world = false,
		crazy = true,
		silent = true,
		cleardistance = 0, -- never removed on arrival: FarmRoute moves it
	})
	if not ok or not uid then
		return setState({ mode = "tomtom", ok = false, why = "TomTom:AddWaypoint failed: " .. tostring(uid) })
	end
	tomtomUid = uid
	return setState({ mode = "tomtom", ok = true, mapID = p.mapID, x = p.x, y = p.y })
end

-- ---------------------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------------------
function Nav.place(p, mode)
	if not p then
		return setState({ mode = mode, ok = false, why = "no point" })
	end
	if mode == "tomtom" then
		if Nav.ownsPin() then
			C_Map.ClearUserWaypoint()
		end
		return placeTomTom(p)
	end
	clearTomTom()
	return placePin(p)
end

-- Removes what this addon placed, and nothing the player placed.
function Nav.clear()
	if Nav.ownsPin() then
		C_Map.ClearUserWaypoint()
	end
	clearTomTom()
	setState({ ok = false, why = "stopped" })
end

-- A value safe to keep in SavedVariables: secrets become a note.
local function plain(v)
	if v ~= nil and issecretvalue(v) then
		return "secret"
	end
	return v
end

function Nav.selftest()
	local navFrame = C_Navigation.GetFrame()
	return {
		mode = Nav.state.mode,
		ok = Nav.state.ok,
		why = Nav.state.why,
		ownsPin = Nav.ownsPin(),
		superTrackingUserWaypoint = C_SuperTrack.IsSuperTrackingUserWaypoint(),
		navFrame = navFrame ~= nil,
		navOnScreen = navFrame ~= nil and C_Navigation.HasValidScreenPosition() or false,
		navClamped = navFrame ~= nil and C_Navigation.WasClampedToScreen() or false,
		navDistance = navFrame ~= nil and plain(C_Navigation.GetDistance()) or nil,
		marker = Nav.marker,
		tomtom = (TomTom and TomTom.AddWaypoint) and "loaded" or "absent",
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- In-world marker and on-screen line. On Forever the engine tracks the super-tracked waypoint and hands out
-- its screen anchor (C_Navigation.GetFrame), but Blizzard's SuperTrackedFrame draws nothing, so the addon
-- draws its own marker on that anchor: an icon above the point (never over the chest itself) with the yards
-- readout, faded when you are close. The line runs from the bottom centre of the screen to the marker.
-- ---------------------------------------------------------------------------------------------------------
local MARKER_LIFT = 36 -- pixels above the point
local lineFrame, line, marker, anchoredTo

Nav.marker = { shown = false, why = "not built yet" }

function Nav.initScreenLine()
	lineFrame = CreateFrame("Frame", nil, UIParent)
	lineFrame:SetAllPoints(UIParent)
	lineFrame:SetFrameStrata("BACKGROUND")
	lineFrame:EnableMouse(false)
	line = lineFrame:CreateLine(nil, "ARTWORK")
	line:SetThickness(1.5)
	line:SetColorTexture(1, 0.82, 0, 0.3)
	-- No API gives the character's screen position; with the default camera the character stands at the
	-- horizontal centre, a little below the vertical centre.
	line:SetStartPoint("CENTER", UIParent, 0, -50)
	lineFrame:Hide()
	-- The end follows the marker every frame (the marker itself is anchored, so it already moves smoothly);
	-- the route logic stays on the 0.25 s ticker.
	lineFrame:SetScript("OnUpdate", function()
		local ok, x, y = pcall(marker.GetCenter, marker)
		if ok and x and y and not issecretvalue(x) and not issecretvalue(y) then
			-- GetCenter is in the marker's scale; the end point offsets are in UIParent's
			local s = marker:GetEffectiveScale() / UIParent:GetEffectiveScale()
			line:SetEndPoint("BOTTOMLEFT", UIParent, x * s, y * s)
		end
	end)

	-- HUD.lua draws the phase 2 marker (minimum skill, coloured by the player's skill); the plain icon below
	-- stays as the fallback when it can't be built.
	local okHud, built = pcall(function()
		return ns.HUD and ns.HUD.buildMarker and ns.HUD.buildMarker(UIParent)
	end)
	if okHud and built then
		marker = built
		Nav.marker.why = "built (HUD)"
		return
	end
	Nav.marker.hudError = not okHud and tostring(built) or nil
	marker = CreateFrame("Frame", nil, UIParent)
	marker:SetSize(22, 22)
	marker:SetFrameStrata("LOW")
	marker:EnableMouse(false)
	marker.icon = marker:CreateTexture(nil, "ARTWORK")
	marker.icon:SetAllPoints(marker)
	if not pcall(marker.icon.SetAtlas, marker.icon, "Navigation-Tracked-Icon") then
		marker.icon:SetColorTexture(1, 0.82, 0, 1)
	end
	marker.text = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	marker.text:SetPoint("BOTTOM", marker, "TOP", 0, 2)
	marker:Hide()
	Nav.marker.why = "built"
end

local function hideAll(why)
	lineFrame:Hide()
	marker:Hide()
	Nav.marker.shown, Nav.marker.why = false, why
end

function Nav.hideMarker(why)
	if lineFrame then
		hideAll(why or "stopped")
	end
end

-- Called from the ticker. lineEnabled: the /fr line setting; radius: the arrival radius (fade inside 1.5x);
-- info: what the marker shows (Core's ns.markerInfo: state, need, skill, label); hidden: the "hide the marker
-- and line" setting (fishing from the shore, where the yards never come down).
function Nav.updateScreenLine(lineEnabled, radius, info, hidden)
	if not lineFrame then
		return
	end
	if hidden then
		return hideAll("hidden by setting (/fr marker)")
	end
	local navFrame = C_Navigation.GetFrame()
	if Nav.state.mode ~= "pin" or not Nav.state.ok then
		return hideAll("not in pin mode or nothing placed")
	end
	if not navFrame then
		return hideAll("C_Navigation.GetFrame() is nil")
	end
	if not (C_SuperTrack.IsSuperTrackingUserWaypoint() and Nav.ownsPin()) then
		return hideAll("our waypoint is not super-tracked")
	end
	if not C_Navigation.HasValidScreenPosition() then
		return hideAll("no valid screen position")
	end
	if anchoredTo ~= navFrame then
		marker:ClearAllPoints()
		marker:SetPoint("BOTTOM", navFrame, "CENTER", 0, MARKER_LIFT)
		anchoredTo = navFrame
	end
	local clamped = C_Navigation.WasClampedToScreen()
	local d = C_Navigation.GetDistance()
	if not d or issecretvalue(d) then
		d = nil
	end
	local near = d and radius and d <= radius * 1.5
	if marker.Apply then
		info = info or {}
		info.distance, info.near, info.clamped = d, near and true or false, clamped
		local ok, err = pcall(marker.Apply, marker, info)
		Nav.marker.applyError = not ok and tostring(err) or nil
		Nav.marker.state = info.state
	else
		marker.text:SetText(d and string.format("%d yd", d + 0.5) or "")
		marker:SetAlpha(near and 0.45 or (clamped and 0.7 or 1))
	end
	marker:Show()
	Nav.marker.shown, Nav.marker.why, Nav.marker.clamped = true, "shown", clamped
	-- A line may not anchor to the marker ("Not allowed to depend on Frame"): place its end at the marker's
	-- screen position instead, and never let the line stop the marker.
	local placed = false
	if lineEnabled and not clamped and not near then
		local ok, x, y = pcall(marker.GetCenter, marker)
		if ok and x and y and not issecretvalue(x) and not issecretvalue(y) then
			placed = pcall(line.SetEndPoint, line, "BOTTOMLEFT", UIParent, x, y)
			Nav.marker.line = placed and "shown" or "SetEndPoint refused"
		else
			Nav.marker.line = "marker position not readable"
		end
	else
		Nav.marker.line = "off, clamped or near"
	end
	if placed then
		lineFrame:Show()
	else
		lineFrame:Hide()
	end
end
