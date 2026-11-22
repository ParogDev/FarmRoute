-- /fr import: a paste box for TomTom /way lines. Append adds them to the active route, Replace swaps its
-- points. Lines that don't parse are listed under the box with their line number and why.
local _, ns = ...

local Import = {}
ns.Import = Import

local frame, edit, status

local function apply(replace)
	local route = ns.activeRoute()
	if not route then
		status:SetText("No active route: /fr new <name> first")
		return
	end
	local defaultMap = route.points[1] and route.points[1].mapID or ns.playerMap()
	local points, errors = ns.Logic.parseImport(edit:GetText(), defaultMap, ns.resolveZone)
	if #points == 0 then
		status:SetText(
			#errors > 0 and ("Nothing added. Line " .. errors[1].line .. ": " .. errors[1].why) or "Nothing to add"
		)
		return
	end
	ns.importPoints(points, replace)
	local msg = string.format("%s %d points to %s", replace and "Set" or "Added", #points, route.name)
	if #errors > 0 then
		msg = msg .. string.format("; %d lines skipped (line %d: %s)", #errors, errors[1].line, errors[1].why)
	end
	status:SetText(msg)
	edit:SetText("")
end

local function button(label, x, onClick)
	local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	b:SetSize(110, 22)
	b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, 10)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function build()
	frame = CreateFrame("Frame", "FarmRouteImportFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(460, 340)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "FarmRouteImportFrame")

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -5)
	title:SetText("FarmRoute: paste /way lines")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -32)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 64)
	edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(400)
	edit:SetScript("OnEscapePressed", edit.ClearFocus)
	scroll:SetScrollChild(edit)
	scroll:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)

	status = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	status:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 40)
	status:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
	status:SetJustifyH("LEFT")

	button("Replace", -12, function()
		apply(true)
	end)
	button("Append", -126, function()
		apply(false)
	end)
end

function Import.show()
	if not frame then
		build()
	end
	local route = ns.activeRoute()
	status:SetText(route and ("Route: " .. route.name .. ". One /way per line, e.g. /way #1418 40.8 26.7 Chest") or "")
	frame:Show()
	edit:SetFocus()
end
