-- luacheck for a WoW: Forever addon. Run from this folder (tools\lua.ps1 does): the generated globals list
-- lives in the scaffolding root; standalone (CI in this repo) falls back to a short list.
std = "lua51"
max_line_length = 140
codes = true
ignore = {
	"212/self", -- unused self
	"212/_.*", -- unused args named _x
	"211/_.*",
}

local ok, wow = pcall(dofile, "../../tools/luacheck-wow-globals.lua")
if ok and type(wow) == "table" then
	read_globals = {}
	for _, g in ipairs(wow.read_globals) do
		if g ~= "SlashCmdList" then
			read_globals[#read_globals + 1] = g
		end
	end
else
	read_globals = {
		"CreateFrame", "C_AddOns", "C_Map", "C_SuperTrack", "C_Navigation", "C_Timer", "GetBuildInfo",
		"WOW_PROJECT_ID", "issecretvalue", "date", "time", "GetTime", "hooksecurefunc", "tinsert",
		"C_CVar", "debugstack", "InCombatLockdown",
	}
end
-- FrameXML globals the generated list doesn't carry (it is built from the C API lists).
for _, g in ipairs({
	"DEFAULT_CHAT_FRAME", "UIParent", "WorldMapFrame", "UiMapPoint", "CreateVector2D", "UISpecialFrames",
	"LibStub", "TomTom",
}) do
	read_globals[#read_globals + 1] = g
end

globals = {
	"FarmRoute", "FarmRouteDB", "SLASH_FARMROUTE1", "SLASH_FARMROUTE2", "SlashCmdList",
	"BINDING_HEADER_FARMROUTE", "BINDING_NAME_FARMROUTE_NEXT", "BINDING_NAME_FARMROUTE_PREV",
}

files["tests/"] = { std = "+busted", globals = { "FarmRoute", "FarmRouteDB", "_G" } }
exclude_files = { ".luacheckrc", ".release/" }
