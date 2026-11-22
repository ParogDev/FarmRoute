-- Minimal WoW client globals so the addon loads under busted: a player position, a user waypoint, a clock.
-- Dumb tables, not a client; the real check is the in-game reload.
local M = {}

local function noop() end

local widgetMeta = {}
local function widget(w)
	w = setmetatable(w or {}, widgetMeta)
	function w:Show()
		self._shown = true
	end
	function w:Hide()
		self._shown = false
	end
	function w:IsShown()
		return self._shown == true
	end
	function w:SetText(s)
		self._text = s
	end
	function w:GetText()
		return self._text or ""
	end
	return w
end
widgetMeta.__index = function(_, k)
	if type(k) == "string" and k:sub(1, 6) == "Create" then
		return function()
			return widget()
		end
	end
	return noop
end

local function vec(x, y)
	return {
		x = x,
		y = y,
		GetXY = function(self)
			return self.x, self.y
		end,
	}
end

-- Badlands-like map: 1 map unit = 3000 yards.
M.YARDS = 3000

function M.install()
	M.frames, M.chat, M.secret = {}, {}, {}
	M.now, M.gameTime = 1000000, 500
	M.mapID, M.pos = 1418, { 0.5, 0.5 }
	M.waypoint, M.superTracked = nil, false
	M.navFrame, M.navDistance = nil, nil
	M.widget = widget
	_G.CreateFrame = function()
		local f = widget({ _events = {} })
		function f:RegisterEvent(e)
			self._events[e] = true
		end
		function f:SetScript(k, fn)
			self["_" .. k] = fn
		end
		M.frames[#M.frames + 1] = f
		return f
	end
	_G.UIParent = widget()
	_G.WorldMapFrame = nil
	_G.UISpecialFrames = {}
	_G.tinsert = table.insert
	_G.hooksecurefunc = noop
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, line)
			M.chat[#M.chat + 1] = line
		end,
	}
	_G.SlashCmdList = {}
	_G.WOW_PROJECT_ID = 18
	_G.GetBuildInfo = function()
		return "1.60.1", "70790", "Nov 4 2026", 16001
	end
	_G.C_AddOns = {
		GetAddOnMetadata = function()
			return "@project-version@"
		end,
	}
	_G.date = function(fmt)
		return os.date(fmt)
	end
	_G.time = function()
		return M.now
	end
	_G.GetTime = function()
		return M.gameTime
	end
	_G.issecretvalue = function(v)
		return v ~= nil and M.secret[v] == true
	end
	_G.CreateVector2D = vec
	_G.UiMapPoint = {
		CreateFromCoordinates = function(m, x, y)
			return { uiMapID = m, position = vec(x, y) }
		end,
	}
	_G.C_Map = {
		GetBestMapForUnit = function()
			return M.mapID
		end,
		GetPlayerMapPosition = function()
			return M.pos and vec(M.pos[1], M.pos[2]) or nil
		end,
		GetWorldPosFromMapPos = function(_, v)
			return 0, vec(v.x * M.YARDS, v.y * M.YARDS)
		end,
		CanSetUserWaypointOnMap = function()
			return true
		end,
		SetUserWaypoint = function(p)
			M.waypoint = p
		end,
		GetUserWaypoint = function()
			return M.waypoint
		end,
		ClearUserWaypoint = function()
			M.waypoint = nil
		end,
		GetMapInfo = function(m)
			return m == 1418 and { name = "Badlands", parentMapID = 0 } or nil
		end,
	}
	_G.C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(v)
			M.superTracked = v
		end,
		IsSuperTrackingUserWaypoint = function()
			return M.superTracked
		end,
	}
	_G.C_Navigation = {
		GetFrame = function()
			return M.navFrame
		end,
		HasValidScreenPosition = function()
			return M.navFrame ~= nil
		end,
		GetDistance = function()
			return M.navDistance or 0
		end,
		WasClampedToScreen = function()
			return false
		end,
	}
	_G.C_Timer = {
		NewTicker = function(_, fn)
			M.tick = fn
		end,
		After = function(_, fn)
			fn()
		end,
	}
	_G.LibStub = nil
	_G.TomTom = nil
	_G.FarmRoute, _G.FarmRouteDB = nil, nil
end

-- Loads the addon files in .toc order with a shared namespace.
function M.load()
	local ns = {}
	for _, f in ipairs({ "Logic.lua", "Nav.lua", "MapLines.lua", "Import.lua", "Core.lua" }) do
		assert(loadfile(f))("FarmRoute", ns)
	end
	return ns
end

function M.fire(event, ...)
	for _, f in ipairs(M.frames) do
		if f._events[event] and f._OnEvent then
			f._OnEvent(f, event, ...)
		end
	end
end

function M.login(saved)
	_G.FarmRouteDB = saved
	M.fire("ADDON_LOADED", "FarmRoute")
	M.fire("PLAYER_LOGIN")
end

return M
