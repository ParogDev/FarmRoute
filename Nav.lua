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
	local wx, wy = vec:GetXY()
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
	local x, y = pos:GetXY()
	if issecretvalue(x) or issecretvalue(y) then
		return nil, "player position is a secret value"
	end
	return mapID, x, y
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
	local x, y = wp.position:GetXY()
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
		tomtom = (TomTom and TomTom.AddWaypoint) and "loaded" or "absent",
	}
end

-- ---------------------------------------------------------------------------------------------------------
-- On-screen line: bottom centre of the screen to the in-world pin. Blizzard projects only the super-tracked
-- target to the screen, so this is the one line that can follow the world.
-- ---------------------------------------------------------------------------------------------------------
local lineFrame, line, anchoredTo

function Nav.initScreenLine()
	lineFrame = CreateFrame("Frame", nil, UIParent)
	lineFrame:SetAllPoints(UIParent)
	lineFrame:SetFrameStrata("BACKGROUND")
	lineFrame:EnableMouse(false)
	line = lineFrame:CreateLine(nil, "ARTWORK")
	line:SetThickness(3)
	line:SetColorTexture(1, 0.82, 0, 0.55)
	line:SetStartPoint("BOTTOM", UIParent, 0, 80)
	lineFrame:Hide()
end

-- Called from the ticker: shows the line only when the pin is ours and on screen.
function Nav.updateScreenLine(enabled)
	if not lineFrame then
		return
	end
	local navFrame = C_Navigation.GetFrame()
	local show = enabled
		and navFrame ~= nil
		and Nav.state.mode == "pin"
		and C_SuperTrack.IsSuperTrackingUserWaypoint()
		and Nav.ownsPin()
		and C_Navigation.HasValidScreenPosition()
		and not C_Navigation.WasClampedToScreen()
	if show then
		if anchoredTo ~= navFrame then
			line:SetEndPoint("CENTER", navFrame, 0, 0)
			anchoredTo = navFrame
		end
		lineFrame:Show()
	else
		lineFrame:Hide()
	end
end
