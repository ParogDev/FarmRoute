-- On-screen pieces of phase 2: the look of the in-world marker (a small diamond carrying the minimum
-- Lockpicking skill, coloured the way the game colours skill-ups), the detection health line with its Fix
-- button, and the short centre-screen flash. Only drawing lives here: the callers anchor, show and hide.
--
-- No atlas is used: every shape is Interface\Buttons\WHITE8X8 tinted from the palette (a square turned 45
-- degrees is the diamond), so nothing depends on an entry of AtlasInfo.lua.
local _, ns = ...

local HUD = {}
ns.HUD = HUD

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- The one palette. The four skill tiers are the game's own skill-up colours, so the number reads like a
-- recipe in the profession window: red can't, orange and yellow skill up, green opens with room to spare.
local C = {
	cant = { 0.95, 0.20, 0.16 }, -- skill < need
	orange = { 1.00, 0.50, 0.25 }, -- opens, need within 25 of skill
	yellow = { 1.00, 0.90, 0.10 }, -- opens, need within 50 of skill
	opens = { 0.30, 0.80, 0.30 }, -- opens, further below the skill
	unknown = { 0.93, 0.89, 0.78 }, -- need or skill not read yet (parchment)
	idle = { 0.58, 0.56, 0.52 }, -- waiting: nothing to walk to
	ink = { 0.06, 0.05, 0.04 }, -- plates and dark text
	text = { 0.93, 0.89, 0.78 },
	dim = { 0.66, 0.63, 0.56 },
	ok = { 0.30, 0.80, 0.30 },
	bad = { 0.95, 0.20, 0.16 },
}

local SKILLUP_BAND = 25 -- "need within about 25 of skill"
local NEAR_ALPHA, CLAMPED_ALPHA, WAITING_ALPHA, PATH_ALPHA = 0.35, 0.75, 0.6, 0.8

-- ---------------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------------
local function tint(tex, c, a)
	tex:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function hex(c)
	local f = math.floor
	return string.format("|cff%02x%02x%02x", f(c[1] * 255 + 0.5), f(c[2] * 255 + 0.5), f(c[3] * 255 + 0.5))
end

local function solid(parent, layer, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub or 0)
	t:SetTexture(WHITE)
	return t
end

-- A font string from a Blizzard font object (by name: no SetFont on a family), resized when the client can.
local function label(parent, fontObject, height)
	local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
	if height then
		pcall(fs.SetFontHeight, fs, height)
	end
	return fs
end

-- The tier of a chest for a skill: a palette key.
function HUD.tier(need, skill)
	if not need or not skill then
		return "unknown"
	end
	if skill < need then
		return "cant"
	end
	if skill - need < SKILLUP_BAND then
		return "orange"
	end
	if skill - need < SKILLUP_BAND * 2 then
		return "yellow"
	end
	return "opens"
end

-- ---------------------------------------------------------------------------------------------------------
-- Marker. 28 px. A diamond, because nothing else in the world or on a nameplate is one.
--   detected: the diamond is filled with the tier colour, dark number, a slow ring pulses out of it and a
--             short stem points down at the chest.
--   route:    a dark diamond with a thin tier-coloured rim, the number in the tier colour.
--   waiting:  a small grey hollow diamond, no number.
--   path:     a 10 px parchment ring, no number: a point to walk through, not a chest. It is round and
--             carries no tier colour so it is never read as the diamond; the label says which chest is next.
-- The yards (and the "7/14" label, dimmer) sit above, away from the chest below.
-- ---------------------------------------------------------------------------------------------------------
local QUARTER = math.pi / 4
local RIM, CORE_ROUTE, CORE_WAITING, RIM_WAITING = 20, 17, 9, 12
local DOT_RIM, DOT_CORE = 10, 6
local READOUT_GAP, READOUT_GAP_PATH = 3, -6 -- the ring is small: pull the yards down to it
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function diamond(parent, sub, size)
	local t = solid(parent, "ARTWORK", sub)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	pcall(t.SetRotation, t, QUARTER)
	return t
end

-- A disc: a square under a circle mask. Without mask support it stays a small upright square, which
-- still isn't a diamond.
local function disc(parent, sub, size)
	local t = solid(parent, "ARTWORK", sub)
	t:SetSize(size, size)
	t:SetPoint("CENTER")
	pcall(function()
		local mask = parent:CreateMaskTexture()
		mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(t)
		t:AddMaskTexture(mask)
	end)
	t:Hide()
	return t
end

local function markerApply(self, info)
	info = info or {}
	local state = info.state or "route"
	local c = C[HUD.tier(info.need, info.skill)]
	local detected, waiting, path = state == "detected", state == "waiting", state == "path"

	-- the ring has its own two textures, so the diamond's sizes and tints are never touched by it
	self.rim:SetShown(not path)
	self.core:SetShown(not path)
	self.number:SetShown(not path)
	self.dotRim:SetShown(path)
	self.dotCore:SetShown(path)
	if self.readoutGap ~= (path and READOUT_GAP_PATH or READOUT_GAP) then
		self.readoutGap = path and READOUT_GAP_PATH or READOUT_GAP
		self.readout:ClearAllPoints()
		self.readout:SetPoint("BOTTOM", self, "TOP", 0, self.readoutGap)
	end

	if path then
		self.number:SetText("")
	elseif waiting then
		self.rim:SetSize(RIM_WAITING, RIM_WAITING)
		self.core:SetSize(CORE_WAITING, CORE_WAITING)
		tint(self.rim, C.idle)
		tint(self.core, C.ink, 0.9)
		self.number:SetText("")
	else
		self.rim:SetSize(RIM, RIM)
		self.core:SetSize(detected and RIM or CORE_ROUTE, detected and RIM or CORE_ROUTE)
		tint(self.rim, detected and C.ink or c)
		tint(self.core, detected and c or C.ink, detected and 1 or 0.92)
		self.number:SetText(info.need and tostring(info.need) or "?")
		local n = detected and C.ink or c
		self.number:SetTextColor(n[1], n[2], n[3])
		-- dark digits on a bright fill want no drop shadow; coloured digits on the dark plate keep it
		self.number:SetShadowColor(0, 0, 0, detected and 0 or 1)
	end

	local stem = detected and not info.clamped and not info.near
	self.stem:SetShown(stem)
	if stem then
		tint(self.stem, c, 0.9)
	end
	if self.pulse then
		if detected and not info.near then
			tint(self.halo, c)
			if not self.pulse:IsPlaying() then
				self.pulse:Play()
			end
		else
			self.pulse:Stop()
			self.halo:SetAlpha(0)
		end
	end

	local top = info.distance and string.format("%d yd", info.distance + 0.5) or ""
	if info.label and info.label ~= "" then
		top = top .. (top ~= "" and "  " or "") .. hex(C.dim) .. info.label .. "|r"
	end
	self.readout:SetText(top)

	local alpha = 1
	if info.near then
		alpha = NEAR_ALPHA
	elseif waiting then
		alpha = WAITING_ALPHA
	elseif info.clamped then
		alpha = CLAMPED_ALPHA
	elseif path then
		alpha = PATH_ALPHA
	end
	self:SetAlpha(alpha)
end

function HUD.buildMarker(parent)
	local m = CreateFrame("Frame", nil, parent)
	m:SetSize(28, 28)
	m:SetFrameStrata("LOW")
	m:EnableMouse(false)

	m.halo = diamond(m, -2, RIM)
	m.halo:SetAlpha(0)
	m.rim = diamond(m, 0, RIM)
	m.core = diamond(m, 1, CORE_ROUTE)

	m.dotRim = disc(m, 0, DOT_RIM)
	tint(m.dotRim, C.text)
	m.dotCore = disc(m, 1, DOT_CORE)
	tint(m.dotCore, C.ink, 0.9)

	m.stem = solid(m, "ARTWORK", 0)
	m.stem:SetSize(2, 9)
	m.stem:SetPoint("TOP", m, "BOTTOM", 0, -1)
	m.stem:Hide()

	m.number = label(m, "GameFontNormalSmall", 10)
	m.number:SetPoint("CENTER", 0, 0)
	m.readout = label(m, "GameFontHighlightSmall", 10)
	m.readoutGap = READOUT_GAP
	m.readout:SetPoint("BOTTOM", m, "TOP", 0, READOUT_GAP)
	m.readout:SetTextColor(C.text[1], C.text[2], C.text[3])

	-- The ring that leaves the diamond while a chest is detected. Without animations the fill still says it.
	pcall(function()
		local g = m.halo:CreateAnimationGroup()
		g:SetLooping("REPEAT")
		local grow = g:CreateAnimation("Scale")
		grow:SetScaleFrom(1, 1)
		grow:SetScaleTo(1.9, 1.9)
		grow:SetDuration(1.1)
		grow:SetSmoothing("OUT")
		local fade = g:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.55)
		fade:SetToAlpha(0)
		fade:SetDuration(1.1)
		m.pulse = g
	end)

	m.Apply = markerApply
	m:Hide()
	return m
end

-- ---------------------------------------------------------------------------------------------------------
-- Shared: a frame that holds for a while, fades out and hides. Without animations it hides at once on the
-- next show, which is still correct, only abrupt.
-- ---------------------------------------------------------------------------------------------------------
local function addFadeOut(frame, hold, fadeTime)
	pcall(function()
		local g = frame:CreateAnimationGroup()
		local a = g:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0)
		a:SetStartDelay(hold)
		a:SetDuration(fadeTime)
		g:SetScript("OnFinished", function()
			frame:Hide()
		end)
		frame.fadeOut = g
	end)
end

local function showThenFade(frame)
	if frame.fadeOut then
		frame.fadeOut:Stop()
	end
	frame:SetAlpha(1)
	frame:Show()
	if frame.fadeOut then
		frame.fadeOut:Play()
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Detection health. Top centre, below the zone widgets. Broken: a dark strip with a red edge, the line, the
-- detail and the Fix button. Healthy: hidden. A permanent "Detection on" would be one more thing to read
-- past while farming, so the green line shows only for 3 s after a broken state ends (the answer to the
-- click on Fix) and then fades.
-- ---------------------------------------------------------------------------------------------------------
local health
local healthPoint = { "TOP", 0, -132 }
local PAD, EDGE, BTN_W, BTN_H = 9, 3, 40, 18

local function placeHealth()
	health:ClearAllPoints()
	health:SetPoint(healthPoint[1], UIParent, healthPoint[1], healthPoint[2], healthPoint[3])
end

function HUD.setHealthPoint(point, x, y)
	healthPoint = { point or "TOP", x or 0, y or 0 }
	if health then
		placeHealth()
	end
end

local function healthLayout(self, hasDetail, hasButton)
	local w = self.line:GetStringWidth()
	if hasDetail then
		w = math.max(w, self.detail:GetStringWidth())
	end
	self:SetSize(EDGE + PAD + w + (hasButton and (PAD + BTN_W) or 0) + PAD, hasDetail and 36 or 24)
	self.line:ClearAllPoints()
	if hasDetail then
		self.line:SetPoint("TOPLEFT", EDGE + PAD, -6)
	else
		self.line:SetPoint("LEFT", EDGE + PAD, 0)
	end
end

local function healthApply(self, h)
	h = h or {}
	if h.ok then
		if self.wasBad then
			self.wasBad = false
			tint(self.edge, C.ok)
			self.line:SetText("Detection on")
			self.line:SetTextColor(C.ok[1], C.ok[2], C.ok[3])
			self.detail:SetText("")
			self.detail:Hide()
			self.fix:Hide()
			healthLayout(self, false, false)
			showThenFade(self)
			if not self.fadeOut then
				self:Hide()
			end
		elseif not (self.fadeOut and self.fadeOut:IsPlaying()) then
			self:Hide()
		end
		return
	end

	self.wasBad = true
	if self.fadeOut then
		self.fadeOut:Stop()
	end
	self:SetAlpha(1)
	tint(self.edge, C.bad)
	self.line:SetText(h.line or "Detection is off")
	self.line:SetTextColor(C.text[1], C.text[2], C.text[3])

	local detail = h.detail
	if h.canFix and h.fixBlocked then
		detail = (detail and detail ~= "" and (detail .. ", ") or "") .. "can't fix now: " .. h.fixBlocked
	end
	local hasDetail = detail ~= nil and detail ~= ""
	self.detail:SetText(hasDetail and detail or "")
	self.detail:SetShown(hasDetail)

	local hasButton = h.canFix and true or false
	self.fix:SetShown(hasButton)
	if hasButton then
		local live = not h.fixBlocked
		self.fix:SetEnabled(live)
		tint(self.fix.bg, live and C.orange or C.idle, live and 1 or 0.5)
	end
	healthLayout(self, hasDetail, hasButton)
	self:Show()
end

function HUD.buildHealth(parent)
	local f = CreateFrame("Frame", nil, parent)
	health = f
	f:SetFrameStrata("MEDIUM")
	f:EnableMouse(false) -- clicks pass through everywhere but the button
	placeHealth()

	f.bg = solid(f, "BACKGROUND")
	f.bg:SetAllPoints(f)
	tint(f.bg, C.ink, 0.82)
	f.edge = solid(f, "BORDER")
	f.edge:SetPoint("TOPLEFT")
	f.edge:SetPoint("BOTTOMLEFT")
	f.edge:SetWidth(EDGE)

	f.line = label(f, "GameFontHighlightSmall", 11)
	f.line:SetJustifyH("LEFT")
	f.detail = label(f, "GameFontHighlightSmall", 10)
	f.detail:SetJustifyH("LEFT")
	f.detail:SetPoint("TOPLEFT", f.line, "BOTTOMLEFT", 0, -3)
	f.detail:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

	-- A plain Button: the fix is an insecure call (ns.fixDetection decides what it may do, and when).
	local b = CreateFrame("Button", nil, f)
	b:SetSize(BTN_W, BTN_H)
	b:SetPoint("RIGHT", -PAD, 0)
	b.bg = solid(b, "BACKGROUND")
	b.bg:SetAllPoints(b)
	b.text = label(b, "GameFontNormalSmall", 11)
	b.text:SetPoint("CENTER")
	b.text:SetText("Fix")
	b.text:SetTextColor(C.ink[1], C.ink[2], C.ink[3])
	b.text:SetShadowColor(0, 0, 0, 0)
	b:SetScript("OnEnter", function(self)
		if self:IsEnabled() then
			tint(self.bg, C.yellow)
		end
	end)
	b:SetScript("OnLeave", function(self)
		if self:IsEnabled() then
			tint(self.bg, C.orange)
		end
	end)
	b:SetScript("OnClick", function()
		if ns.fixDetection then
			ns.fixDetection()
		end
	end)
	f.fix = b

	addFadeOut(f, 3, 0.6)
	f.Apply = healthApply
	f:Hide()
	return f
end

-- ---------------------------------------------------------------------------------------------------------
-- Flash: one line above the character for about 1.5 s ("Skipped 7/14"). A new flash replaces the old one.
-- ---------------------------------------------------------------------------------------------------------
local flashFrame

function HUD.flash(text)
	if not text or text == "" then
		return
	end
	if not flashFrame then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetFrameStrata("HIGH")
		f:EnableMouse(false)
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
		f.bg = solid(f, "BACKGROUND")
		f.bg:SetAllPoints(f)
		tint(f.bg, C.ink, 0.7)
		f.rule = solid(f, "BORDER")
		f.rule:SetPoint("BOTTOMLEFT")
		f.rule:SetPoint("BOTTOMRIGHT")
		f.rule:SetHeight(2)
		tint(f.rule, C.orange)
		f.text = label(f, "GameFontNormalLarge", 16)
		f.text:SetPoint("CENTER", 0, 1)
		f.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		addFadeOut(f, 1.2, 0.3)
		flashFrame = f
	end
	local f = flashFrame
	f.text:SetText(text)
	f:SetSize(f.text:GetStringWidth() + 28, 30)
	showThenFade(f)
	if not f.fadeOut then
		-- no animation support: at least don't leave it up forever
		pcall(C_Timer.After, 1.5, function()
			f:Hide()
		end)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Route picker (/fr, /fr routes): every route grouped by what it farms, with the zone, where in it, the
-- spot count and the trunk; "Show on map" opens the world map at the zone with that route drawn,
-- "Walk this route" makes it the active route and starts it. Core supplies ns.pickRoute(name).
-- ---------------------------------------------------------------------------------------------------------
local PICK_W, PICK_H, LIST_W, ROW_H, MAX_ROWS = 560, 360, 230, 20, 15
local picker

local function zoneName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or ("map " .. tostring(mapID) .. " (unknown to this client)")
end

local function button(parent, text, w)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 24)
	b:SetText(text)
	return b
end

local function clearPreview()
	if ns.MapLines.preview then
		ns.MapLines.preview = nil
		ns.MapLines.refresh()
	end
end

local function showDetail(f, info)
	f.selected = info and info.name
	for _, row in ipairs(f.rows) do
		row.hl:SetShown(row.info ~= nil and row.info.name == f.selected)
	end
	if not info then
		f.title:SetText("Pick a route on the left")
		f.body:SetText("")
		f.walk:Disable()
		f.map:Disable()
		return
	end
	local here = info.mapID and ns.playerMap() == info.mapID
	local lines = {
		hex(C.dim) .. "Zone|r  " .. zoneName(info.mapID) .. (here and (hex(C.ok) .. "  (you are here)|r") or ""),
		hex(C.dim) .. "Spots|r  " .. info.count,
	}
	if info.trunk then
		lines[#lines + 1] = hex(C.dim) .. "Drops|r  " .. info.trunk .. " (tier " .. info.tier .. ")"
	end
	if info.where then
		lines[#lines + 1] = " "
		lines[#lines + 1] = info.where
	end
	if info.tier then
		lines[#lines + 1] = " "
		lines[#lines + 1] = hex(C.dim)
			.. "Pools sit out in the water. A spot counts as reached within "
			.. ns.Logic.radiusOf(ns.db.routes[info.name], ns.db.settings)
			.. " yd, so fish from the shore. "
			.. '"Your fish got away" means your fishing skill plus pole and lure is too low for this zone.|r'
	end
	local active = ns.db.active == info.name
	f.title:SetText(info.name .. (active and (hex(C.ok) .. "  (active)|r") or ""))
	f.body:SetText(table.concat(lines, "\n"))
	f.walk:SetEnabled(info.count > 0)
	f.walk:SetText(active and ns.db.running and "Walking it" or "Walk this route")
	f.map:SetEnabled(info.mapID ~= nil)
end

local function fillRows(f)
	local rows = ns.Logic.pickerRows(ns.db.routes)
	local selectedInfo
	for _, r in ipairs(rows) do
		if not r.header and r.name == (f.selected or ns.db.active) then
			selectedInfo = r
		end
	end
	-- the mouse wheel scrolls the list a row at a time when it is longer than the window
	local maxOffset = math.max(0, #rows - #f.rows)
	f.offset = math.min(math.max(f.offset or 0, 0), maxOffset)
	for i, row in ipairs(f.rows) do
		local r = rows[i + f.offset]
		row.info = r and not r.header and r or nil
		if not r then
			row:Hide()
		else
			row:Show()
			if r.header then
				row.text:SetText(hex(C.orange) .. r.header .. "|r")
				row:EnableMouse(false)
			else
				local shown = r.tier and r.name:gsub("^Wreckage T%d ", "") or r.name
				local mark = ns.db.active == r.name and (hex(C.ok) .. "> |r") or "   "
				row.text:SetText(mark .. shown .. hex(C.dim) .. "  " .. r.count .. "|r")
				row:EnableMouse(true)
			end
		end
	end
	f.more:SetText(
		maxOffset > 0 and string.format("rows %d-%d of %d: scroll for more", f.offset + 1, f.offset + #f.rows, #rows)
			or ""
	)
	showDetail(f, selectedInfo)
	if f.hide then
		f.hide:SetChecked(ns.db.settings.hideMarker == true)
	end
end

local function buildPicker()
	local f = CreateFrame("Frame", "FarmRoutePicker", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(PICK_W, PICK_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("MEDIUM") -- under the world map: "Show on map" opens it on top
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "FarmRoutePicker") -- Escape closes it
	if f.TitleText then
		f.TitleText:SetText("FarmRoute: routes")
	end
	f:SetScript("OnHide", clearPreview)

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(self, delta)
		self.offset = (self.offset or 0) - delta
		fillRows(self)
	end)
	f.rows = {}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, f)
		row:SetSize(LIST_W - 16, ROW_H)
		row:SetPoint("TOPLEFT", 14, -30 - (i - 1) * ROW_H)
		row.hl = solid(row, "BACKGROUND")
		row.hl:SetAllPoints(row)
		tint(row.hl, C.orange, 0.25)
		row.hl:Hide()
		local hover = solid(row, "HIGHLIGHT")
		hover:SetAllPoints(row)
		tint(hover, C.text, 0.08)
		row.text = label(row, "GameFontHighlightSmall", 12)
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetJustifyH("LEFT")
		row:SetScript("OnClick", function(self)
			if self.info then
				showDetail(f, self.info)
				clearPreview()
			end
		end)
		f.rows[i] = row
	end
	f.more = label(f, "GameFontDisableSmall")
	f.more:SetPoint("BOTTOMLEFT", 18, 14)

	local x = LIST_W + 10
	f.title = label(f, "GameFontNormalLarge", 15)
	f.title:SetPoint("TOPLEFT", x, -34)
	f.title:SetPoint("RIGHT", -16, 0)
	f.title:SetJustifyH("LEFT")
	f.body = label(f, "GameFontHighlight", 12)
	f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -12)
	f.body:SetPoint("RIGHT", -16, 0)
	f.body:SetJustifyH("LEFT")
	f.body:SetJustifyV("TOP")
	f.body:SetSpacing(3)

	f.walk = button(f, "Walk this route", 140)
	f.walk:SetPoint("BOTTOMRIGHT", -16, 14)
	f.walk:SetScript("OnClick", function()
		if f.selected then
			clearPreview()
			ns.pickRoute(f.selected)
			fillRows(f)
		end
	end)
	f.map = button(f, "Show on map", 140)
	f.map:SetPoint("RIGHT", f.walk, "LEFT", -8, 0)
	f.map:SetScript("OnClick", function()
		local info = f.selected and ns.Logic.routeInfo(ns.db.routes[f.selected])
		if not info or not info.mapID then
			return
		end
		if InCombatLockdown() then
			ns.say("the world map can't be opened from an addon in combat; try again after the fight")
			return
		end
		ns.MapLines.preview = info.name
		if not WorldMapFrame:IsShown() then
			ToggleWorldMap()
		end
		WorldMapFrame:SetMapID(info.mapID)
		ns.MapLines.refresh()
	end)
	-- the same setting as /fr marker and Options > AddOns > FarmRoute
	f.hide = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.hide:SetSize(24, 24)
	f.hide:SetPoint("BOTTOMLEFT", f.map, "TOPLEFT", -4, 6)
	if f.hide.Text then
		f.hide.Text:SetText("Hide the on-screen marker and line")
		f.hide.Text:SetFontObject("GameFontHighlightSmall")
	end
	f.hide:SetScript("OnClick", function(self)
		ns.setHideMarker(self:GetChecked())
	end)
	if WorldMapFrame then
		WorldMapFrame:HookScript("OnHide", clearPreview)
	end
	return f
end

function HUD.showPicker()
	picker = picker or buildPicker()
	if not picker:IsShown() then
		picker.selected, picker.offset = nil, 0
	end
	fillRows(picker)
	picker:Show()
end

function HUD.togglePicker()
	if picker and picker:IsShown() then
		picker:Hide()
		return
	end
	HUD.showPicker()
end

-- After the route starts or stops: the open picker's "> " mark and "Walking it" follow.
function HUD.refreshPicker()
	if picker and picker:IsShown() then
		fillRows(picker)
	end
end
