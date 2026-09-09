-- Floating Combat Alert
-- Shows floating text above the player when entering or leaving combat.
-- Type /fca in game for the options window.

local ADDON_NAME = "Floating_Combat_Alert"
local VERSION = "0.6.1"

-- ingame instructions colors
local exitColor = "|r"
local colorOrange = "|cFFDF9F1F"
local colorRed = "|cFFFF3F1F"

local unpack = table.unpack or unpack -- Lua 5.1 (WoW) global vs 5.2+ table field

-- every typeface family the game client ships (collected from the client's own
-- font references); locale variants load only on matching clients, so the list
-- is validated at startup and only working entries reach the dropdown
local FONT_CANDIDATES = {
	{ text = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ text = "Friz Quadrata (Cyrillic)", path = "Fonts\\FRIZQT___CYR.TTF" },
	{ text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ text = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ text = "Morpheus (Cyrillic)", path = "Fonts\\MORPHEUS_CYR.TTF" },
	{ text = "Skurri", path = "Fonts\\SKURRI.TTF" },
	{ text = "Skurri (Cyrillic)", path = "Fonts\\SKURRI_CYR.TTF" },
}
local FONT_LIST = {}
do
	local probe = CreateFrame("Frame"):CreateFontString(nil, "OVERLAY")
	-- probing a missing font file raises an engine error ("Invalid font asset");
	-- pcall catches it so nothing reaches Bugsack, and the false return plus the
	-- failed call together guarantee broken fonts never enter the list
	for _, e in ipairs(FONT_CANDIDATES) do
		local ok, loaded = pcall(probe.SetFont, probe, e.path, 12, "")
		if ok and loaded then
			FONT_LIST[#FONT_LIST + 1] = e
		end
	end
	if #FONT_LIST == 0 then
		FONT_LIST[1] = FONT_CANDIDATES[1] -- Friz Quadrata ships with every client
	end
end
local FONT_MENU = {}
for i, e in ipairs(FONT_LIST) do
	FONT_MENU[i] = { e.text, e.path }
end
local OUTLINE_MENU = {
	{ text = "None", style = "none" },
	{ text = "Thin", style = "outline" },
	{ text = "Thick", style = "thick" },
}

local DIRECTION_MENU = {
	{ text = "Up", style = "up" },
	{ text = "Down", style = "down" },
}

local function DirectionNameFor(style)
	for _, e in ipairs(DIRECTION_MENU) do
		if e.style == style then
			return e.text
		end
	end
	return style or "Up"
end

local function OutlineNameFor(style)
	for _, e in ipairs(OUTLINE_MENU) do
		if e.style == style then
			return e.text
		end
	end
	return style or "None"
end

local defaults = {
	link = { font = true, size = true, color = false, outline = true, text = false, direction = true, duration = true, fade = true },
	region = { cx = 0, y1 = -100, y2 = 100 }, -- travel band centered on screen CENTER: center x + bottom/top edges
	win = { x = 0, y = 0 }, -- config window position, relative to screen CENTER
	enter = { text = "Entering Combat", color = "FFFF0000", font = "Fonts\\FRIZQT__.TTF", size = 28, outlineStyle = "outline", direction = "up", duration = 2, fadeStart = 50 },
	leave = { text = "Leaving Combat", color = "FF00FF00", font = "Fonts\\FRIZQT__.TTF", size = 28, outlineStyle = "outline", direction = "up", duration = 2, fadeStart = 50 },
}

local db -- alias for the Floating_Combat_Alert SavedVariables table, set on ADDON_LOADED
local REGION_MIN = 20 -- smallest allowed region, in yards

local options, editor -- created below
local RefreshAll, UpdatePreviewLoop -- assigned below

local function FCA_instructions()
	print(colorOrange .. "Use /fca by itself to open the options window; or followed by: to preview the alerts; to adjust the travel region; display duration; to print saved config." .. exitColor)
	print(colorOrange .. "Example:" .. exitColor .. " /fca")
	print(colorOrange .. "Example:" .. exitColor .. " /fca test in")
	print(colorOrange .. "Example:" .. exitColor .. " /fca test out")
	print(colorOrange .. "Example:" .. exitColor .. " /fca region")
	print(colorOrange .. "Example:" .. exitColor .. " /fca duration 1.5")
	print(colorOrange .. "Example:" .. exitColor .. " /fca print")
	print(colorOrange .. "Example:" .. exitColor .. " /fca reset")
end

-- parse an AARRGGBB hex string into r, g, b in the 0-1 range
local function HexToRGB(hex)
	if type(hex) ~= "string" then
		return 1, 1, 1
	end
	local a, r, g, b = string.match(hex, "^(%x%x)(%x%x)(%x%x)(%x%x)$")
	if not a then
		return 1, 1, 1
	end
	return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

local function RGBToHex(r, g, b)
	return ("FF%02X%02X%02X"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function FlagsString(cfg)
	local t = {}
	if cfg.outlineStyle == "outline" then
		t[#t + 1] = "OUTLINE"
	elseif cfg.outlineStyle == "thick" then
		t[#t + 1] = "THICKOUTLINE"
	end
	return #t > 0 and table.concat(t, ", ") or nil
end

local function FontNameFor(path)
	for _, e in ipairs(FONT_LIST) do
		if e.path == path then
			return e.text
		end
	end
	return path or "?"
end

-- which alert tables an edit lands on: both sides when that setting is linked
local function TargetsFor(which, key)
	if db.link[key] then
		return { db.enter, db.leave }
	end
	return { db[which] }
end

local function MergeDefaults(t, d)
	for k, v in pairs(d) do
		if type(v) == "table" then
			if type(t[k]) ~= "table" then
				t[k] = {}
			end
			MergeDefaults(t[k], v)
		elseif t[k] == nil then
			t[k] = v
		end
	end
end

-- upgrade the flat v1 settings table to the v2 schema
local function MigrateLegacy(dbt)
	if type(dbt.enter) ~= "table" then
		local enter, leave = {}, {}
		enter.text, leave.text = dbt.enterText, dbt.leaveText
		enter.color, leave.color = dbt.enterColor, dbt.leaveColor
		if dbt.fontSize then
			enter.size, leave.size = dbt.fontSize, dbt.fontSize
		end
		dbt.enter, dbt.leave = enter, leave
		if dbt.y ~= nil then
			local x = dbt.x or 0
			local rise = dbt.rise or 80
			dbt.region = { x1 = x - 150, y1 = dbt.y, x2 = x + 150, y2 = dbt.y + rise }
		end
		for _, k in ipairs({ "duration", "x", "y", "rise", "enterText", "leaveText", "enterColor", "leaveColor", "fontSize" }) do
			dbt[k] = nil
		end
	end
	-- v2 -> v2.1: outline/thick booleans became a single outlineStyle key
	for _, side in ipairs({ "enter", "leave" }) do
		local cfg = dbt[side]
		if type(cfg) == "table" and cfg.outlineStyle == nil then
			if cfg.thick then
				cfg.outlineStyle = "thick"
			elseif cfg.outline then
				cfg.outlineStyle = "outline"
			end
			cfg.outline, cfg.thick = nil, nil
		end
	end
	dbt.testLoop = nil -- option removed; the loop now runs while the window is open
	-- v0.3 -> v0.4: monochrome removed (disabled); single linked bool became
	-- per-setting link keys, color unlinked (enter=red, leave=green by default)
	if type(dbt.linked) == "boolean" then
		dbt.link = { font = dbt.linked, size = dbt.linked, color = false, outline = dbt.linked, text = dbt.linked }
		dbt.linked = nil
	end
	for _, side in ipairs({ "enter", "leave" }) do
		local cfg = dbt[side]
		if type(cfg) == "table" then
			cfg.mono = nil
		end
	end
	-- v0.4 -> v0.5: duration became per-alert (fade/direction joined it)
	if dbt.duration ~= nil then
		local d = tonumber(dbt.duration) or 2
		for _, side in ipairs({ "enter", "leave" }) do
			local cfg = dbt[side]
			if type(cfg) == "table" and cfg.duration == nil then
				cfg.duration = d
				cfg.fadeStart = 50
				cfg.direction = "up"
			end
		end
		dbt.duration = nil
	end
	-- v0.5: the region is a band centered on cx; its width hugs the text
	local r = dbt.region
	if type(r) == "table" and r.cx == nil and r.x1 ~= nil then
		dbt.region = { cx = (r.x1 + r.x2) / 2, y1 = r.y1, y2 = r.y2 }
	end
end

-- ----------------------------------------------------------------------------
-- alert engine: every message spawns its own frame, so concurrent combat
-- transitions float side by side instead of replacing each other
-- ----------------------------------------------------------------------------
local activeAlerts = {} -- in-flight alerts, in spawn order
local alertPool = {} -- recycled hidden frames

local driver = CreateFrame("Frame", "FloatingCombatAlertFrame", UIParent)
driver:SetFrameStrata("HIGH")
driver:EnableMouse(false)
driver:Hide()
driver.active = activeAlerts -- exposed for tests/diagnostics

-- per-side text measurers: the shared band width must fit whichever alert is
-- currently the bigger one, so each side is measured with its own font/size
local measure = {
	enter = driver:CreateFontString(nil, "OVERLAY"),
	leave = driver:CreateFontString(nil, "OVERLAY"),
}

local function TextWidthFor(cfg)
	local m = measure.enter
	if cfg ~= db.enter then
		m = measure.leave
	end
	m:SetFont(cfg.font, cfg.size, FlagsString(cfg))
	m:SetText(cfg.text)
	return m:GetStringWidth()
end

-- fade lifecycle: fully opaque until the fade-start % of the duration, then a
-- constant fade reaching zero at despawn
local function FadeAlpha(cfg, progress)
	local fadeStart = math.max(0, math.min(100, cfg.fadeStart or 50)) / 100
	if fadeStart >= 1 or progress <= fadeStart then
		return 1
	end
	return 1 - (progress - fadeStart) / (1 - fadeStart)
end

local function StyleAlertText(fs, cfg)
	fs:SetFont(cfg.font, cfg.size, FlagsString(cfg)) -- font first: SetText needs one
	fs:SetText(cfg.text)
	local r, g, b = HexToRGB(cfg.color)
	fs:SetTextColor(r, g, b, 1)
end

local function PositionAlert(a, progress)
	local cfg = db[a.side]
	local r = db.region
	local h = a.frame.text:GetStringHeight()
	local span = math.max(0, r.y2 - r.y1 - h)
	local cx = r.cx
	local y = r.y1 + h / 2 + span * progress
	if cfg.direction == "down" then
		y = r.y2 - h / 2 - span * progress
	end
	a.frame:ClearAllPoints()
	a.frame:SetPoint("CENTER", UIParent, "CENTER", cx, y)
end

local function ReleaseAlert(index)
	local a = activeAlerts[index]
	a.frame.text:SetAlpha(1)
	a.frame:Hide()
	alertPool[#alertPool + 1] = a.frame
	table.remove(activeAlerts, index)
end

local function SpawnAlert(which, fromLoop)
	if #activeAlerts >= 8 then
		ReleaseAlert(1) -- safety cap: recycle the oldest in-flight alert
	end
	local frame = table.remove(alertPool) or CreateFrame("Frame", nil, UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetSize(1, 1)
	frame:EnableMouse(false)
	if not frame.text then
		frame.text = frame:CreateFontString(nil, "OVERLAY")
		frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
		frame.text:SetFont(defaults.enter.font, defaults.enter.size, FlagsString(defaults.enter))
	end
	StyleAlertText(frame.text, db[which])
	frame.text:SetAlpha(1)
	activeAlerts[#activeAlerts + 1] = {
		frame = frame,
		side = which,
		elapsed = 0,
		fromLoop = fromLoop and true or false,
	}
	PositionAlert(activeAlerts[#activeAlerts], 0)
	frame:Show()
end

local function ReleaseAllAlerts()
	for i = #activeAlerts, 1, -1 do
		ReleaseAlert(i)
	end
end

local function ReleaseLoopAlerts()
	for i = #activeAlerts, 1, -1 do
		if activeAlerts[i].fromLoop then
			ReleaseAlert(i)
		end
	end
end

-- one driver advances every in-flight alert (OnUpdate only ticks while shown;
-- the driver is shown at login and simply idles when nothing is in flight)
driver:SetScript("OnUpdate", function(_, dt)
	for i = #activeAlerts, 1, -1 do
		local a = activeAlerts[i]
		local cfg = db[a.side]
		a.elapsed = a.elapsed + dt
		if a.elapsed >= cfg.duration then
			ReleaseAlert(i)
		else
			local progress = a.elapsed / cfg.duration
			a.frame.text:SetAlpha(FadeAlpha(cfg, progress))
			PositionAlert(a, progress)
		end
	end
end)

-- ----------------------------------------------------------------------------
-- preview loop ("test messages constantly"); waits while any alert is visible
-- so previews never stack on top of each other or on top of combat text
-- ----------------------------------------------------------------------------
local previewTicker = CreateFrame("Frame")
previewTicker:Hide()
local previewAcc = 0
local previewNext = "enter"
previewTicker:SetScript("OnUpdate", function(_, dt)
	if #activeAlerts > 0 then
		previewAcc = 0
		return
	end
	previewAcc = previewAcc + dt
	if previewAcc >= 0.4 then
		previewAcc = 0
		SpawnAlert(previewNext, true)
		previewNext = (previewNext == "enter") and "leave" or "enter"
	end
end)

function UpdatePreviewLoop()
	if db ~= nil and options ~= nil and options:IsShown() then
		previewTicker:Show()
	else
		previewTicker:Hide()
		previewAcc = 0
	end
end

-- stop the loop and despawn its text (combat text, if any, stays)
local function StopLoopAndDespawn()
	previewTicker:Hide()
	previewAcc = 0
	ReleaseLoopAlerts()
end

-- ----------------------------------------------------------------------------
-- cursor helper (screen yards, relative to nothing, raw client yards)
-- ----------------------------------------------------------------------------
local function CursorXY()
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	return x / s, y / s
end

-- ----------------------------------------------------------------------------
-- region editor: semi-transparent zone the text travels in, draggable corners.
-- Built inside a function so a failure here can never take down the alerts.
-- ----------------------------------------------------------------------------
local function BuildRegionEditor()
editor = CreateFrame("Frame", "FloatingCombatAlertRegionEditor", UIParent, "BackdropTemplate")
editor:SetFrameStrata("TOOLTIP")
editor:SetMovable(true)
editor:EnableMouse(true)
editor:RegisterForDrag("LeftButton")
editor:SetClampedToScreen(true)
editor:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
editor:SetBackdropColor(1, 1, 1, 0.12)
editor:SetBackdropBorderColor(1, 0.87, 0.12, 0.9)
editor:Hide()

-- the band's horizontal extent always hugs the text so it fits snugly,
-- sized for the bigger of the two alerts
function editor:BandWidth()
	return math.max(TextWidthFor(db.enter), TextWidthFor(db.leave)) + 20
end

function editor:BandLeft()
	return db.region.cx - self:BandWidth() / 2
end

function editor:BandRight()
	return db.region.cx + self:BandWidth() / 2
end

local function CopyRect()
	local r = db.region
	return { cx = r.cx, y1 = r.y1, y2 = r.y2 }
end

local function CommitRect(rect)
	db.region = rect
	editor:LayoutRegion()
end

-- resize one edge vertically, keeping the band at least REGION_MIN tall
local function SetEdge(edge, y)
	local r = CopyRect()
	if edge == "top" then
		r.y2 = math.max(y, r.y1 + REGION_MIN)
	else
		r.y1 = math.min(y, r.y2 - REGION_MIN)
	end
	CommitRect(r)
end

-- drag bars on the top/bottom edges: vertical resize only
editor.edges = {}
local function MakeEdgeHandle(edge)
	local h = CreateFrame("Button", nil, editor)
	h:SetSize(40, 14)
	h.tex = h:CreateTexture(nil, "OVERLAY")
	h.tex:SetAllPoints(h)
	h.tex:SetColorTexture(0, 1, 0, 0.5)
	h:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	h:SetScript("OnMouseDown", function(_, btn)
		if btn == "LeftButton" and db then
			local cx, cy = CursorXY()
			editor.drag = { edge = edge, sx = cx, sy = cy, orig = CopyRect() }
		end
	end)
	h:SetScript("OnMouseUp", function()
		editor.drag = nil
	end)
	editor.edges[edge] = h
end

-- coordinate readouts: plain clickthrough text (no edit boxes)
editor.readouts = {}
local function MakeReadout()
	local fs = editor:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject("GameFontHighlightSmall")
	fs:SetTextColor(1, 1, 1, 0.9)
	return fs
end

for _, edge in ipairs({ "top", "bottom" }) do
	MakeEdgeHandle(edge)
	editor.readouts[edge] = MakeReadout()
end
editor.readouts.left = MakeReadout()
editor.readouts.right = MakeReadout()

editor.drag = nil
editor:SetScript("OnDragStart", function()
	if db then
		local cx, cy = CursorXY()
		editor.drag = { edge = nil, sx = cx, sy = cy, orig = CopyRect() }
	end
end)
editor:SetScript("OnDragStop", function()
	editor.drag = nil
end)
editor:SetScript("OnMouseUp", function()
	editor.drag = nil
end)
editor:SetScript("OnUpdate", function(self)
	local drag = self.drag
	if not drag then
		return
	end
	local cx, cy = CursorXY()
	local dx, dy = cx - drag.sx, cy - drag.sy
	local o = drag.orig
	if drag.edge then
		SetEdge(drag.edge, drag.edge == "top" and o.y2 + dy or o.y1 + dy)
	else
		CommitRect({ cx = o.cx + dx, y1 = o.y1 + dy, y2 = o.y2 + dy })
	end
end)

-- place edges/boxes to the current band and mirror values into the boxes
function editor:LayoutRegion()
	if not db then
		return
	end
	local r = db.region
	local left = self:BandLeft()
	local width = self:BandWidth()
	self:ClearAllPoints()
	self:SetPoint("BOTTOMLEFT", UIParent, "CENTER", left, r.y1)
	self:SetSize(width, r.y2 - r.y1)
	self.edges.top:SetPoint("TOP", self, "TOP", 0, 0)
	self.edges.bottom:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
	self.readouts.top:SetPoint("BOTTOM", self.edges.top, "TOP", 0, 2)
	self.readouts.bottom:SetPoint("TOP", self.edges.bottom, "BOTTOM", 0, -2)
	self.readouts.left:SetPoint("RIGHT", self, "LEFT", -6, 0)
	self.readouts.right:SetPoint("LEFT", self, "RIGHT", 6, 0)
	self.readouts.top:SetText(("%.0f"):format(r.y2))
	self.readouts.bottom:SetText(("%.0f"):format(r.y1))
	self.readouts.left:SetText(("%.0f"):format(left))
	self.readouts.right:SetText(("%.0f"):format(left + width))
end

editor:SetScript("OnShow", function()
	editor:LayoutRegion()
	UpdatePreviewLoop()
end)
editor:SetScript("OnHide", function()
	UpdatePreviewLoop()
end)
end

-- menu system bootstrap: Blizzard_Menu ships with the retail client but may be
-- absent in older flavors; fall back to cycling fonts when it's unavailable
local function EnsureMenuUtil()
	if MenuUtil then
		return true
	end
	if LoadAddOn then
		pcall(LoadAddOn, "Blizzard_Menu")
	end
	return MenuUtil ~= nil
end

-- ----------------------------------------------------------------------------
-- options window (also built defensively; see BuildRegionEditor)
-- ----------------------------------------------------------------------------
local colorPickerDragSetup = false

local function BuildOptionsWindow()
options = CreateFrame("Frame", "FloatingCombatAlertOptions", UIParent, "BackdropTemplate")
options:SetFrameStrata("HIGH")
options:SetSize(320, 414)
options:SetPoint("CENTER", UIParent, "CENTER", defaults.win.x, defaults.win.y)
options:SetMovable(true)
options:EnableMouse(true)
options:RegisterForDrag("LeftButton")
options:SetClampedToScreen(true)
options:SetScript("OnDragStart", function(self)
	self:StartMoving()
end)
options:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	if db then
		local cx, cy = self:GetCenter()
		local pw, ph = UIParent:GetSize()
		db.win = { x = cx - pw / 2, y = cy - ph / 2 }
		self:ClearAllPoints()
		self:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y)
	end
end)
options:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 16,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
options:SetBackdropColor(0, 0, 0, 0.85)
options:Hide()

-- title + close
options.title = options:CreateFontString(nil, "OVERLAY")
options.title:SetFontObject("GameFontHighlight")
options.title:SetText("Floating Combat Alert")
options.title:SetPoint("TOP", options, "TOP", 0, -10)
options.close = CreateFrame("Button", nil, options, "UIPanelCloseButton")
options.close:SetPoint("TOPRIGHT", options, "TOPRIGHT", 2, -2)
options.close:SetScript("OnClick", function()
	options:Hide()
end)

-- region editor toggle, full width above the columns
options.regionBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
options.regionBtn:SetSize(292, 22)
options.regionBtn:SetText("move region")
options.regionBtn:SetPoint("TOPLEFT", options, "TOPLEFT", 14, -30)
options.regionBtn:SetScript("OnClick", function()
	if editor:IsShown() then
		editor:Hide()
	else
		editor:Show()
	end
end)

-- link column: one checkbox per option row, left of both alert columns
local LINK_ROWS = { font = -92, size = -134, color = -164, outline = -210, text = -252, direction = -292, duration = -334, fade = -376 }
options.linkChecks = {}
local checkCount = 0
for key, rowY in pairs(LINK_ROWS) do
	checkCount = checkCount + 1
	local cb = CreateFrame("CheckButton", "FCALink" .. checkCount, options, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	cb:SetPoint("TOPLEFT", options, "TOPLEFT", 14, rowY)
	cb:SetScript("OnClick", function(self)
		if not db then
			return
		end
		db.link[key] = self:GetChecked()
		RefreshAll()
	end)
	options.linkChecks[key] = cb
end
options.linkTitle = options:CreateFontString(nil, "OVERLAY")
options.linkTitle:SetFontObject("GameFontNormalSmall")
options.linkTitle:SetText("Link")
options.linkTitle:SetPoint("TOPLEFT", options, "TOPLEFT", 18, -66)

-- one control column per alert side
local function MakeColumn(which, x)
	local col = CreateFrame("Frame", nil, options)
	col:SetSize(130, 324)
	col:SetPoint("TOPLEFT", options, "TOPLEFT", x, -76)

	col.title = col:CreateFontString(nil, "OVERLAY")
	col.title:SetFontObject("GameFontHighlightSmall")
	col.title:SetText((which == "enter") and "Entering" or "Leaving")
	col.title:SetPoint("TOPLEFT", col, "TOPLEFT", 2, 0)

	-- font dropdown: real dropdown widget, its label rendered in the picked font
	col.font = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
	col.font:SetSize(126, 22)
	col.font:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -16)
	col.font:SetupMenu(function(_, rootDescription)
		if not db then
			return
		end
		for _, e in ipairs(FONT_LIST) do
			rootDescription:CreateRadio(
				e.text,
				function(data)
					return db[which].font == data
				end,
				function(data)
					for _, t in ipairs(TargetsFor(which, "font")) do
						t.font = data
					end
					RefreshAll()
				end,
				e.path
			)
		end
	end)

	-- size: numeric text box, type any value and press enter
	col.sizeLabel = col:CreateFontString(nil, "OVERLAY")
	col.sizeLabel:SetFontObject("GameFontNormalSmall")
	col.sizeLabel:SetText("Size")
	col.sizeLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -44)
	col.size = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
	col.size:SetSize(56, 20)
	col.size:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -58)
	col.size:SetFontObject("GameFontHighlightSmall")
	col.size:SetAutoFocus(false)
	col.size:SetMaxLetters(4)
	col.size:SetJustifyH("CENTER")
	col.size:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if not db then
			return
		end
		local v = tonumber(self:GetText())
		if v == nil then
			self:SetText(tostring(db[which].size))
			return
		end
		v = math.max(4, math.min(200, math.floor(v + 0.5)))
		for _, t in ipairs(TargetsFor(which, "size")) do
			t.size = v
		end
		RefreshAll()
	end)

	-- color
	col.swatch = CreateFrame("Button", nil, col)
	col.swatch:SetSize(26, 26)
	col.swatch:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -88)
	col.swatch.tex = col.swatch:CreateTexture(nil, "OVERLAY")
	col.swatch.tex:SetAllPoints(col.swatch)
	col.swatch.label = col:CreateFontString(nil, "OVERLAY")
	col.swatch.label:SetFontObject("GameFontNormalSmall")
	col.swatch.label:SetText("Color")
	col.swatch.label:SetPoint("LEFT", col.swatch, "RIGHT", 8, 0)
	col.swatch:SetScript("OnClick", function()
		if not db then
			return
		end
		-- the stock picker opens at DIALOG strata, under our HIGH-strata window
		ColorPickerFrame:SetFrameStrata("TOOLTIP")
		if not colorPickerDragSetup then
			colorPickerDragSetup = true
			ColorPickerFrame:SetMovable(true)
			ColorPickerFrame:EnableMouse(true)
			ColorPickerFrame:RegisterForDrag("LeftButton")
			ColorPickerFrame:SetScript("OnDragStart", ColorPickerFrame.StartMoving)
			ColorPickerFrame:SetScript("OnDragStop", ColorPickerFrame.StopMovingOrSizing)
		end
		local cfg = db[which]
		local origHex = cfg.color
		local r, g, b = HexToRGB(origHex)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			swatchFunc = function()
				local r2, g2, b2 = ColorPickerFrame:GetColorRGB()
				local hex = RGBToHex(r2, g2, b2)
				for _, t in ipairs(TargetsFor(which, "color")) do
					t.color = hex
				end
				RefreshAll()
			end,
			cancelFunc = function()
				for _, t in ipairs(TargetsFor(which, "color")) do
					t.color = origHex
				end
				RefreshAll()
			end,
		})
	end)

	-- outline style dropdown
	col.outlineLabel = col:CreateFontString(nil, "OVERLAY")
	col.outlineLabel:SetFontObject("GameFontNormalSmall")
	col.outlineLabel:SetText("Outline")
	col.outlineLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -122)
	col.outline = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
	col.outline:SetSize(126, 22)
	col.outline:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -134)
	col.outline:SetupMenu(function(_, rootDescription)
		if not db then
			return
		end
		for _, e in ipairs(OUTLINE_MENU) do
			rootDescription:CreateRadio(
				e.text,
				function(data)
					return db[which].outlineStyle == data
				end,
				function(data)
					for _, t in ipairs(TargetsFor(which, "outline")) do
						t.outlineStyle = data
					end
					RefreshAll()
				end,
				e.style
			)
		end
	end)

	-- alert text
	col.textLabel = col:CreateFontString(nil, "OVERLAY")
	col.textLabel:SetFontObject("GameFontNormalSmall")
	col.textLabel:SetText("Text")
	col.textLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -170)
	col.textBox = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
	col.textBox:SetSize(126, 20)
	col.textBox:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -182)
	col.textBox:SetFontObject("GameFontHighlightSmall")
	col.textBox:SetAutoFocus(false)
	col.textBox:SetMaxLetters(40)
	col.textBox:SetJustifyH("CENTER")
	col.textBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if not db then
			return
		end
		local v = self:GetText()
		if v == "" then
			self:SetText(db[which].text)
			return
		end
		for _, t in ipairs(TargetsFor(which, "text")) do
			t.text = v
		end
		RefreshAll()
	end)

	-- direction: does the text travel up or down
	col.directionLabel = col:CreateFontString(nil, "OVERLAY")
	col.directionLabel:SetFontObject("GameFontNormalSmall")
	col.directionLabel:SetText("Direction")
	col.directionLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -210)
	col.direction = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
	col.direction:SetSize(126, 22)
	col.direction:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -222)
	col.direction:SetupMenu(function(_, rootDescription)
		if not db then
			return
		end
		for _, e in ipairs(DIRECTION_MENU) do
			rootDescription:CreateRadio(
				e.text,
				function(data)
					return db[which].direction == data
				end,
				function(data)
					for _, t in ipairs(TargetsFor(which, "direction")) do
						t.direction = data
					end
					RefreshAll()
				end,
				e.style
			)
		end
	end)

	-- duration: seconds between spawning and despawning
	col.durationLabel = col:CreateFontString(nil, "OVERLAY")
	col.durationLabel:SetFontObject("GameFontNormalSmall")
	col.durationLabel:SetText("Duration (sec)")
	col.durationLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -252)
	col.duration = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
	col.duration:SetSize(56, 20)
	col.duration:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -264)
	col.duration:SetFontObject("GameFontHighlightSmall")
	col.duration:SetAutoFocus(false)
	col.duration:SetMaxLetters(5)
	col.duration:SetJustifyH("CENTER")
	col.duration:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if not db then
			return
		end
		local v = tonumber(self:GetText())
		if v == nil then
			self:SetText(tostring(db[which].duration))
			return
		end
		v = math.max(0.2, math.min(60, v))
		for _, t in ipairs(TargetsFor(which, "duration")) do
			t.duration = v
		end
		RefreshAll()
	end)

	-- fade: percent of the duration at which fading out starts (constant rate)
	col.fadeLabel = col:CreateFontString(nil, "OVERLAY")
	col.fadeLabel:SetFontObject("GameFontNormalSmall")
	col.fadeLabel:SetText("Fade start (%)")
	col.fadeLabel:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -292)
	col.fade = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
	col.fade:SetSize(56, 20)
	col.fade:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -304)
	col.fade:SetFontObject("GameFontHighlightSmall")
	col.fade:SetAutoFocus(false)
	col.fade:SetMaxLetters(3)
	col.fade:SetJustifyH("CENTER")
	col.fade:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if not db then
			return
		end
		local v = tonumber(self:GetText())
		if v == nil then
			self:SetText(tostring(db[which].fadeStart))
			return
		end
		v = math.max(0, math.min(100, math.floor(v + 0.5)))
		for _, t in ipairs(TargetsFor(which, "fade")) do
			t.fadeStart = v
		end
		RefreshAll()
	end)

	col.Refresh = function()
		local cfg = db[which]
		col.font:SetText(FontNameFor(cfg.font))
		if col.font.Text then
			col.font.Text:SetFont(cfg.font, 12, "")
		end
		if tonumber(col.size:GetText()) ~= cfg.size then
			col.size:SetText(tostring(cfg.size))
		end
		local r, g, b = HexToRGB(cfg.color)
		col.swatch.tex:SetColorTexture(r, g, b, 1)
		col.outline:SetText(OutlineNameFor(cfg.outlineStyle))
		if col.outline.Text then
			col.outline.Text:SetFontObject("GameFontHighlight")
		end
		if col.textBox:GetText() ~= cfg.text then
			col.textBox:SetText(cfg.text)
		end
		col.direction:SetText(DirectionNameFor(cfg.direction))
		if tonumber(col.duration:GetText()) ~= cfg.duration then
			col.duration:SetText(tostring(cfg.duration))
		end
		if tonumber(col.fade:GetText()) ~= cfg.fadeStart then
			col.fade:SetText(tostring(cfg.fadeStart))
		end
	end
	return col
end

options.enterCol = MakeColumn("enter", 48)
options.leaveCol = MakeColumn("leave", 184)

-- divider between the two segments (Blizzard's standard settings divider),
-- vertically centered between the outline dropdown and the text label
options.divider = options:CreateTexture(nil, "OVERLAY")
options.divider:SetAtlas("Options_HorizontalDivider", true)
options.divider:SetPoint("LEFT", options, "LEFT", 12, 0)
options.divider:SetPoint("RIGHT", options, "RIGHT", -12, 0)
options.divider:SetPoint("TOP", options.enterCol.outline, "BOTTOM", 0, -7)

function RefreshAll()
	if not db or not options.enterCol then
		return
	end
	for key, cb in pairs(options.linkChecks) do
		cb:SetChecked(db.link[key] and true or false)
	end
	options.enterCol:Show()
	options.leaveCol:Show()
	options.enterCol.Refresh()
	options.leaveCol.Refresh()
	-- settings changed: restyle every in-flight alert immediately
	for _, a in ipairs(activeAlerts) do
		local cfg = db[a.side]
		local progress = math.min(a.elapsed / cfg.duration, 1)
		StyleAlertText(a.frame.text, cfg)
		a.frame.text:SetAlpha(FadeAlpha(cfg, progress))
		PositionAlert(a, progress)
	end
	-- ... and keep the band hugging the text even while nothing is on screen
	if editor and editor:IsShown() then
		editor:LayoutRegion()
	end
end

options:SetScript("OnShow", function()
	RefreshAll()
	UpdatePreviewLoop()
end)
options:SetScript("OnHide", function()
	-- closing the window stops the loop, despawns loop text and the editor
	StopLoopAndDespawn()
	if editor then
		editor:Hide()
	end
	UpdatePreviewLoop()
end)

end

-- build the UI last and defensively: even if a widget template is missing in
-- some client flavor, the combat alerts and /fca print keep working
local buildErr = nil
local buildOK, buildFail = pcall(function()
	EnsureMenuUtil()
	BuildRegionEditor()
	BuildOptionsWindow()
end)
if not buildOK then
	buildErr = buildFail
	print(colorRed .. "Floating Combat Alert: options UI failed to build, combat alerts still work. Error: " .. tostring(buildFail) .. exitColor)
end

-- ----------------------------------------------------------------------------
-- login and persist through sessions functionality
-- ----------------------------------------------------------------------------
local inCombatKnown = nil

-- player-unit combat flag polling via UNIT_FLAGS; the dedicated
-- PLAYER_ENTER/LEAVE_COMBAT events stay as the primary trigger, this catches
-- transitions on clients/units where those events don't arrive
local function SyncCombatState(allowAlert)
	if not db then
		return
	end
	local now = UnitAffectingCombat("player") and true or false
	if inCombatKnown == nil then
		inCombatKnown = now -- first sync (login): adopt silently, no alert
		return
	end
	if now ~= inCombatKnown then
		inCombatKnown = now
		if allowAlert then
			SpawnAlert(now and "enter" or "leave")
		end
	end
end

local function FCA_loaded(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		if type(Floating_Combat_Alert) ~= "table" then
			Floating_Combat_Alert = {}
		end
		db = Floating_Combat_Alert
		MigrateLegacy(db)
		MergeDefaults(db, defaults)
		-- a saved font can point at a file this client doesn't ship (or one that
		-- no longer exists); fall back to the default rather than error per frame
		for _, side in ipairs({ "enter", "leave" }) do
			local known = false
			for _, e in ipairs(FONT_LIST) do
				if e.path == db[side].font then
					known = true
					break
				end
			end
			if not known then
				db[side].font = defaults.enter.font
			end
		end
		options:ClearAllPoints()
		options:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y)
		driver:Show() -- start the per-alert advance loop
		-- the player unit's combat flag, not the regen lock (regen lags real
		-- combat state and can keep running in combat, e.g. troll racial)
		self:RegisterEvent("PLAYER_ENTER_COMBAT")
		self:RegisterEvent("PLAYER_LEAVE_COMBAT")
		self:RegisterUnitEvent("UNIT_FLAGS", "player")
		if RefreshAll then
			RefreshAll()
		end
		UpdatePreviewLoop()
	elseif event == "PLAYER_ENTER_COMBAT" then
		if inCombatKnown ~= true then
			inCombatKnown = true
			SpawnAlert("enter")
		end
	elseif event == "PLAYER_LEAVE_COMBAT" then
		if inCombatKnown ~= false then
			inCombatKnown = false
			SpawnAlert("leave")
		end
	elseif event == "UNIT_FLAGS" then
		SyncCombatState(true)
	elseif event == "PLAYER_ENTERING_WORLD" then
		SyncCombatState(false)
	end
end

-- event triggers
local Fr_FloatingCombatAlert = CreateFrame("Frame")
Fr_FloatingCombatAlert:RegisterEvent("ADDON_LOADED")
Fr_FloatingCombatAlert:RegisterEvent("PLAYER_LOGIN")
Fr_FloatingCombatAlert:RegisterEvent("PLAYER_ENTERING_WORLD")
Fr_FloatingCombatAlert:SetScript("OnEvent", function(self, event, arg1)
	if event == "PLAYER_LOGIN" then
		-- chat is guaranteed visible here; this line proves the addon file ran
		if buildErr then
			print(colorRed .. "[Floating Combat Alert] " .. VERSION .. " loaded, options UI failed: " .. tostring(buildErr) .. exitColor)
		else
			print(colorOrange .. "[Floating Combat Alert] " .. VERSION .. " loaded, type /fca for options" .. exitColor)
		end
		return
	end
	FCA_loaded(self, event, arg1)
end)

-- slash command functionality
SLASH_FCA1 = "/fca"
SlashCmdList.FCA = function(msg, editbox)
	if not db then
		print(colorRed .. "Floating Combat Alert is not fully loaded yet." .. exitColor)
		return
	end
	local duration = string.match(msg, "^duration (%d+%.?%d?)$")
	local reset = string.match(msg, "^reset$")
	local testIn = string.match(msg, "^test in$")
	local testOut = string.match(msg, "^test out$")
	local region = string.match(msg, "^region$")
	local printCfg = string.match(msg, "^print$")
	if msg == "" then
		if options then
			if options:IsShown() then
				options:Hide()
				print(colorOrange .. "[FCA] window closed" .. exitColor)
			else
				options:Show()
				print(colorOrange .. "[FCA] window opened" .. exitColor)
			end
		else
			print(colorRed .. "Options window failed to build; combat alerts still work. Type /fca print for config." .. exitColor)
		end
	elseif testIn then
		SpawnAlert("enter")
	elseif testOut then
		SpawnAlert("leave")
	elseif region then
		if editor then
			if editor:IsShown() then
				editor:Hide()
			else
				editor:Show()
			end
		else
			print(colorRed .. "Region editor failed to build; combat alerts still work." .. exitColor)
		end
	elseif reset then
		Floating_Combat_Alert = {}
		db = Floating_Combat_Alert
		MigrateLegacy(db)
		MergeDefaults(db, defaults)
		ReleaseAllAlerts()
		if RefreshAll then
			RefreshAll()
		end
		if editor and editor:IsShown() then
			editor:LayoutRegion()
		end
		options:ClearAllPoints()
		options:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y)
		print(colorOrange .. "[FCA] all settings restored to defaults" .. exitColor)
	elseif duration then
		local v = tonumber(duration)
		db.enter.duration, db.leave.duration = v, v
		SpawnAlert("enter")
	elseif printCfg then
		local r = db.region
		print(colorOrange .. "Region: " .. exitColor .. ("left=%s right=%s bottom=%s top=%s"):format(tostring(editor:BandLeft()), tostring(editor:BandRight()), tostring(r.y1), tostring(r.y2)))
		print(colorOrange .. "Window: " .. exitColor .. ("x=%s y=%s"):format(tostring(db.win.x), tostring(db.win.y)))
		for _, which in ipairs({ "enter", "leave" }) do
			local c = db[which]
			print(colorOrange .. c.text .. ": " .. exitColor .. ("%s, size %s, %s, outline %s, %s, duration %ss, fade start %s%%, flags [%s]"):format(FontNameFor(c.font), tostring(c.size), c.color, tostring(c.outlineStyle), tostring(c.direction), tostring(c.duration), tostring(c.fadeStart), tostring(FlagsString(c))))
		end
	else
		print(colorRed .. "Incorrect use of" .. exitColor .. " /fca")
		FCA_instructions()
	end
end
