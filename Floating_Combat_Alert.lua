-- Floating Combat Alert
-- Shows floating text above the player when entering or leaving combat.
-- Type /fca in game for the options window.

local ADDON_NAME = "Floating_Combat_Alert"

-- the game client's typefaces: Blizzard's shared font families load
-- these files on every locale, and LibSharedMedia (the font registry most
-- addons pick from) offers the same set by default. Still validated at
-- startup, so only working entries reach the dropdown
local FONT_CANDIDATES = {
	{ text = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
	{ text = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ text = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ text = "Skurri", path = "Fonts\\SKURRI.TTF" },
	{ text = "Nimrod MT", path = "Fonts\\NIM_____.ttf" },
	{ text = "MoK", path = "Fonts\\K_Pagetext.TTF" },
}
-- free-licensed fonts popular addons ship, bundled in this addon's Fonts
-- folder (licences in Fonts\Licenses), cut down to Western European
-- characters; the OFL makes trimmed PT Sans Narrow, Carlito and Gentium Plus
-- take new names
local BUNDLED_DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\"
for _, e in ipairs({
	{ "Narrow Sans", "NarrowSans-Regular.ttf" },
	{ "Narrow Sans Bold", "NarrowSans-Bold.ttf" },
	{ "Fira Sans Medium", "FiraSans-Medium.ttf" },
	{ "Fira Sans Black", "FiraSans-Black.ttf" },
	{ "Fira Sans Condensed Medium", "FiraSansCondensed-Medium.ttf" },
	{ "Fira Sans Condensed Black", "FiraSansCondensed-Black.ttf" },
	{ "Fira Mono Medium", "FiraMono-Medium.ttf" },
	{ "Oswald", "Oswald-Regular.ttf" },
	{ "Noto Sans Medium", "NotoSans-Medium.ttf" },
	{ "Noto Sans SemiCondensed", "NotoSans-SemiCondensed.ttf" },
	{ "Humanist Sans", "HumanistSans-Regular.ttf" },
	{ "Book Serif", "BookSerif-Regular.ttf" },
	{ "Francois One", "FrancoisOne-Regular.ttf" },
	{ "DejaVu Sans", "DejaVuLGCSans.ttf" },
	{ "DejaVu Serif", "DejaVuLGCSerif.ttf" },
	{ "Hack", "Hack-Regular.ttf" },
}) do
	FONT_CANDIDATES[#FONT_CANDIDATES + 1] = { text = e[1], path = BUNDLED_DIR .. e[2] }
end

-- font paths compare case- and slash-insensitively (the client resolves both)
local function FontKey(path)
	if type(path) ~= "string" then
		return nil
	end
	return (path:lower():gsub("/", "\\"))
end

-- the client loads a font file only once text in it is first drawn, and a
-- string switched to a file that is not loaded yet stays blank until it is
-- set again (a first pick showed nothing). So every offered font is drawn
-- here, invisibly, from the first frame on and stays loaded.
-- Fonts are validated on one probe string that already has a font: on a
-- string with none, SetFont refuses a file that is not loaded yet, which
-- dropped every font the game's own text had not used. A missing or broken
-- file raises an engine error ("Invalid font asset"): only that keeps a font
-- out of the list (pcall keeps it out of Bugsack). A false return alone is
-- not a broken file, so such a font stays listed and preloaded
local fontProbe = CreateFrame("Frame"):CreateFontString(nil, "OVERLAY")
pcall(fontProbe.SetFont, fontProbe, "Fonts\\FRIZQT__.TTF", 12, "")
-- FontString:SetFont itself, for strings whose own lookup refuses it (menu entries)
local FontStringSetFont = fontProbe.SetFont
local fontPreload = CreateFrame("Frame", nil, UIParent)
fontPreload:SetSize(1, 1)
fontPreload:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
local preloaded = {} -- font key -> whether the file loaded

local function PreloadFont(e)
	local key = FontKey(e.path)
	if preloaded[key] == nil then
		preloaded[key] = pcall(fontProbe.SetFont, fontProbe, e.path, 12, "")
		if preloaded[key] then
			local fs = fontPreload:CreateFontString(nil, "BACKGROUND")
			pcall(fs.SetFont, fs, "Fonts\\FRIZQT__.TTF", 12, "") -- a font first, as on the probe
			fs:SetFont(e.path, 12, "")
			fs:SetPoint("BOTTOMLEFT", fontPreload, "BOTTOMLEFT", 0, 0)
			fs:SetTextColor(1, 1, 1, 0)
			fs:SetText(e.text)
		end
	end
	return preloaded[key]
end

local FONT_LIST = {}
for _, e in ipairs(FONT_CANDIDATES) do
	if PreloadFont(e) then
		FONT_LIST[#FONT_LIST + 1] = e
	end
end
if #FONT_LIST == 0 then
	FONT_LIST[1] = FONT_CANDIDATES[1] -- Friz Quadrata ships with every client
end

-- client files whose English text looks like a listed font (they differ mainly
-- in Cyrillic or Chinese glyphs): left out of the list, also when another
-- addon shares them, and a saved pick moves to the look-alike
local FONT_TWINS = {
	[FontKey("Fonts\\2002.TTF")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\2002B.TTF")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\ARKai_T.ttf")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\ARKai_C.ttf")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\ARHei.ttf")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\FRIZQT___CYR.TTF")] = "Fonts\\FRIZQT__.TTF",
	[FontKey("Fonts\\MORPHEUS_CYR.TTF")] = "Fonts\\MORPHEUS.TTF",
	[FontKey("Fonts\\SKURRI_CYR.TTF")] = "Fonts\\SKURRI.TTF",
}
-- bundled files renamed since: a saved pick moves to the new file
local FONT_RENAMED = {
	[FontKey(BUNDLED_DIR .. "PTSansNarrow-Regular.ttf")] = BUNDLED_DIR .. "NarrowSans-Regular.ttf",
	[FontKey(BUNDLED_DIR .. "PTSansNarrow-Bold.ttf")] = BUNDLED_DIR .. "NarrowSans-Bold.ttf",
	[FontKey(BUNDLED_DIR .. "Carlito-Regular.ttf")] = BUNDLED_DIR .. "HumanistSans-Regular.ttf",
	[FontKey(BUNDLED_DIR .. "GentiumPlus-Regular.ttf")] = BUNDLED_DIR .. "BookSerif-Regular.ttf",
}

-- the client's and the bundled fonts: listed first, by file and by name
local BASE_FONT_COUNT = #FONT_LIST
local BASE_FONT_KEYS, BASE_FONT_NAMES = {}, {}
for _, e in ipairs(FONT_LIST) do
	BASE_FONT_KEYS[FontKey(e.path)] = true
	BASE_FONT_NAMES[e.text:lower()] = true
end
-- other addons share the renamed fonts untrimmed, under their own names
for _, name in ipairs({ "PT Sans Narrow", "PT Sans Narrow Bold", "Carlito", "Gentium Plus" }) do
	BASE_FONT_NAMES[name:lower()] = true
end

-- the base fonts, then every font other installed addons share through
-- LibSharedMedia (sorted by name; copies of base fonts dropped, by file or by
-- name -- other addons bundle the same families; files that fail to load
-- dropped, preloaded like the base fonts). Rebuilt in place on demand:
-- most providers load after this addon, and the dropdown regenerates its menu
-- on every open
local function FontList()
	for i = #FONT_LIST, BASE_FONT_COUNT + 1, -1 do
		FONT_LIST[i] = nil
	end
	local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
	if lsm then
		local paths = lsm:HashTable("font")
		local seen = {}
		for _, name in ipairs(lsm:List("font")) do
			local path = paths[name]
			local key = FontKey(path)
			if key and not BASE_FONT_KEYS[key] and not FONT_TWINS[key] and not BASE_FONT_NAMES[name:lower()] and not seen[key] then
				seen[key] = true
				local e = { text = name, path = path }
				if PreloadFont(e) then
					FONT_LIST[#FONT_LIST + 1] = e
				end
			end
		end
	end
	return FONT_LIST
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

-- display name of a menu value; unknown values show as themselves
local function MenuTextFor(menu, field, value)
	for _, e in ipairs(menu) do
		if e[field] == value then
			return e.text
		end
	end
	return value
end

local defaults = {
	link = { font = true, size = true, color = false, outline = true, text = false, direction = true, duration = true, fade = true },
	region = { cx = 0, y1 = -100, y2 = 100 }, -- travel band centered on screen CENTER: center x + bottom/top edges
	win = { x = 0, y = 0 }, -- config window position, relative to screen CENTER
	enter = { text = "Entering Combat", color = "FFFF0000", font = "Fonts\\FRIZQT__.TTF", size = 28, outlineStyle = "outline", direction = "up", duration = 2, fadeStart = 50 },
	leave = { text = "Leaving Combat", color = "FF00FF00", font = "Fonts\\FRIZQT__.TTF", size = 28, outlineStyle = "outline", direction = "up", duration = 2, fadeStart = 50 },
}

local db -- alias for the Floating_Combat_Alert SavedVariables table, set on ADDON_LOADED
local REGION_MIN = 20 -- smallest allowed region, in UI units

local options, editor -- created below
local RefreshAll, PumpLoop -- assigned below

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

local OUTLINE_FLAGS = { outline = "OUTLINE", thick = "THICKOUTLINE" }

local function FlagsString(cfg)
	return OUTLINE_FLAGS[cfg.outlineStyle]
end

-- dropdown name of a font; a font whose provider has not registered yet
-- shows its file name
local function FontNameFor(path)
	local key = FontKey(path)
	for _, e in ipairs(FontList()) do
		if FontKey(e.path) == key then
			return e.text
		end
	end
	return type(path) == "string" and path:match("([^\\/]+)%.%w+$") or path or "?"
end

-- a saved font must still be on offer: a client file this build lacks, or an
-- addon font whose provider is gone, falls back to the default instead of
-- erroring on every alert. Addon fonts may wait for their provider while
-- addons are still loading (re-checked on entering the world)
local function SanitizeFonts(allowPending)
	local known = {}
	for _, e in ipairs(FontList()) do
		known[FontKey(e.path)] = true
	end
	local changed = false
	for _, side in ipairs({ "enter", "leave" }) do
		local key = FontKey(db[side].font)
		local moved = FONT_TWINS[key] or FONT_RENAMED[key]
		if moved then
			db[side].font = moved
			key = FontKey(db[side].font)
			changed = true
		end
		-- an addon's font may wait for its provider to load, unless its file
		-- is gone (provider deleted): that falls back at once
		local pending = allowPending and key and key:find("^interface\\addons\\")
			and pcall(fontProbe.SetFont, fontProbe, db[side].font, 12, "")
		if not (key and known[key]) and not pending then
			db[side].font = defaults.enter.font
			changed = true
		end
	end
	return changed
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
-- transitions float side by side instead of replacing each other. Motion and
-- fading run on engine AnimationGroups -- zero per-frame Lua work.
-- ----------------------------------------------------------------------------
local activeAlerts = {} -- in-flight alerts, in spawn order
local alertPool = {} -- recycled hidden frames

-- hidden named anchor: hosts the text measurers and the active list for tests
local driver = CreateFrame("Frame", "FloatingCombatAlertFrame", UIParent)
driver:SetFrameStrata("HIGH")
driver:EnableMouse(false)
driver:Hide()
driver.active = activeAlerts -- never reassigned; the list mutates in place

-- stop, hide, pool and unregister one alert
local function ReleaseAlert(a)
	a.group:Stop()
	a:Hide()
	alertPool[#alertPool + 1] = a
	for i, active in ipairs(activeAlerts) do
		if active == a then
			table.remove(activeAlerts, i)
			break
		end
	end
end

-- seconds an in-flight alert has actually spent on its current timeline
local function AlertElapsed(a)
	local frac = a.group:IsPlaying() and a.group:GetProgress() or 0
	return (a.doneT or 0) + frac * (a.spanT or 0)
end

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

local function StyleAlertText(fs, cfg)
	fs:SetFont(cfg.font, cfg.size, FlagsString(cfg)) -- font first: SetText needs one
	fs:SetText(cfg.text)
	local r, g, b = HexToRGB(cfg.color)
	fs:SetTextColor(r, g, b, 1)
end

-- timeline for one alert: waits fadeStart% of the duration, then a constant
-- linear fade reaching zero exactly at despawn (fadeStart 100 = never fades).
-- `progress` is the elapsed fraction of the previous timeline (0 at spawn):
-- the remaining distance is rescheduled over the remaining time at the same
-- speed -- nothing restarts. Time-derived on purpose: a live Translation
-- animation renders an offset without moving the anchor, so GetPoint here
-- would read the stale spawn position and snap the text back. No negative
-- start delays: the client clamps those to zero.
local function ConfigureAlertAnimation(f, cfg, progress)
	local duration = math.max(cfg.duration or 2, 0.05)
	local fadeStart = math.max(0, math.min(100, cfg.fadeStart or 50)) / 100
	local r = db.region
	local down = cfg.direction == "down"
	local h = f.text:GetStringHeight()
	local fromY = down and (r.y2 - h / 2) or (r.y1 + h / 2)
	local toY = down and (r.y1 + h / 2) or (r.y2 - h / 2)

	local curY = fromY + (toY - fromY) * progress
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", r.cx, curY)

	local g = f.group
	g:Stop()

	-- travel: the remaining distance over the remaining time (same speed)
	local tr = f.translateAnim
	tr:SetSmoothing("NONE")
	tr:SetStartDelay(0)
	tr:SetDuration(math.max(duration * (1 - progress), 0.001))
	tr:SetOffset(0, toY - curY)

	-- fade: before fade-start, wait what is left of the wait; mid-fade,
	-- continue the same linear ramp from the alpha the frame sits at
	local fadeAt = fadeStart * duration
	local al = f.alphaAnim
	al:SetSmoothing("NONE")
	if progress * duration <= fadeAt then
		al:SetFromAlpha(1)
		al:SetToAlpha(fadeStart >= 1 and 1 or 0)
		al:SetStartDelay(fadeAt - progress * duration)
		al:SetDuration(math.max(duration - fadeAt, 0.001))
	else
		local faded = (progress * duration - fadeAt) / math.max(duration - fadeAt, 0.001)
		al:SetFromAlpha(1 - faded)
		al:SetToAlpha(0)
		al:SetStartDelay(0)
		al:SetDuration(math.max((duration - fadeAt) * (1 - faded), 0.001))
	end
	return duration
end

local function SpawnAlert(which, fromLoop)
	if #activeAlerts >= 8 then
		ReleaseAlert(activeAlerts[1]) -- safety cap: recycle the oldest in-flight alert
	end
	local a = table.remove(alertPool)
	if not a then -- pooled frames keep everything set up here
		a = CreateFrame("Frame", nil, UIParent)
		a:SetFrameStrata("HIGH")
		a:SetSize(1, 1)
		a:EnableMouse(false)
		a.text = a:CreateFontString(nil, "OVERLAY")
		a.text:SetPoint("CENTER", a, "CENTER", 0, 0)
		a.text:SetFont(defaults.enter.font, defaults.enter.size, FlagsString(defaults.enter))
		a.group = a:CreateAnimationGroup()
		a.alphaAnim = a.group:CreateAnimation("Alpha")
		a.translateAnim = a.group:CreateAnimation("Translation")
		a.group:SetScript("OnFinished", function()
			ReleaseAlert(a)
		end)
	end
	a.side = which
	a.fromLoop = fromLoop and true or false
	StyleAlertText(a.text, db[which])
	a:SetAlpha(1) -- the animation owns alpha from its first tick on
	a.doneT, a.spanT = 0, ConfigureAlertAnimation(a, db[which], 0)
	a.group:Play()
	a:Show()
	activeAlerts[#activeAlerts + 1] = a
end

local function ReleaseAllAlerts()
	for i = #activeAlerts, 1, -1 do
		ReleaseAlert(activeAlerts[i])
	end
end

local function ReleaseLoopAlerts()
	for i = #activeAlerts, 1, -1 do
		if activeAlerts[i].fromLoop then
			ReleaseAlert(activeAlerts[i])
		end
	end
end

-- ----------------------------------------------------------------------------
-- preview loop ("test messages constantly"), timer-driven: each preview
-- enters while the previous one is halfway through its travel, chaining the
-- texts with a slight overlap instead of waiting for the band to empty
-- ----------------------------------------------------------------------------
local previewNext = "enter"
local loopTimer = nil

function PumpLoop(delay) -- assigns the forward-declared upvalue
	if loopTimer then
		loopTimer:Cancel()
		loopTimer = nil
	end
	if not (db and options and options:IsShown()) then
		return
	end
	loopTimer = C_Timer.NewTimer(delay or 0.4, function()
		loopTimer = nil
		if not (db and options and options:IsShown()) then
			return
		end
		local which = previewNext
		SpawnAlert(which, true)
		previewNext = (which == "enter") and "leave" or "enter"
		PumpLoop((db[which].duration or 2) * 0.5)
	end)
end

-- stop the loop and despawn its text (combat text, if any, stays)
local function StopLoopAndDespawn()
	if loopTimer then
		loopTimer:Cancel()
		loopTimer = nil
	end
	ReleaseLoopAlerts()
end

-- ----------------------------------------------------------------------------
-- cursor helper: raw client pixels converted to UIParent units
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
editor = CreateFrame("Frame", "FloatingCombatAlertRegionEditor", UIParent)
editor:SetFrameStrata("TOOLTIP")
editor:SetMovable(true)
editor:EnableMouse(true)
editor:SetClampedToScreen(true)
-- MRM move-box pattern: plain frame + BACKGROUND texture, no BackdropTemplate
-- border. The yellow fill lives on its own sub-HIGH frame so in-flight text
-- (HIGH) and the green edge handles (TOOLTIP, on the editor) both render
-- above it; the editor itself stays a pure input layer at TOOLTIP.
local zone = CreateFrame("Frame", nil, UIParent)
zone:SetFrameStrata("MEDIUM")
zone:EnableMouse(false)
local zoneTex = zone:CreateTexture(nil, "BACKGROUND")
zoneTex:SetColorTexture(1, 1, 0, 0.25)
zoneTex:SetAllPoints()
zone.tex = zoneTex
zone:Hide()
editor.zone = zone
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

-- drag steering: the OnUpdate script exists only while a drag is active, so
-- an open editor costs nothing per-frame
local function DragOnUpdate(self)
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
end

local function DragStart(drag)
	editor.drag = drag
	editor:SetScript("OnUpdate", DragOnUpdate)
end

local function DragStop()
	editor.drag = nil
	editor:SetScript("OnUpdate", nil)
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
			DragStart({ edge = edge, sx = cx, sy = cy, orig = CopyRect() })
		end
	end)
	h:SetScript("OnMouseUp", DragStop)
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
-- handles and readouts hang off the editor's own edges: anchored once, they
-- follow every move and resize
editor.edges.top:SetPoint("TOP", editor, "TOP", 0, 0)
editor.edges.bottom:SetPoint("BOTTOM", editor, "BOTTOM", 0, 0)
editor.readouts.top:SetPoint("BOTTOM", editor.edges.top, "TOP", 0, 2)
editor.readouts.bottom:SetPoint("TOP", editor.edges.bottom, "BOTTOM", 0, -2)
editor.readouts.left:SetPoint("RIGHT", editor, "LEFT", -6, 0)
editor.readouts.right:SetPoint("LEFT", editor, "RIGHT", 6, 0)

-- the zone moves from the press itself (no drag threshold)
editor:SetScript("OnMouseDown", function(_, btn)
	if btn == "LeftButton" and db then
		local cx, cy = CursorXY()
		DragStart({ edge = nil, sx = cx, sy = cy, orig = CopyRect() })
	end
end)
editor:SetScript("OnMouseUp", DragStop)

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
	self.zone:ClearAllPoints()
	self.zone:SetPoint("BOTTOMLEFT", UIParent, "CENTER", left, r.y1)
	self.zone:SetSize(width, r.y2 - r.y1)
	self.readouts.top:SetText(("%.0f"):format(r.y2))
	self.readouts.bottom:SetText(("%.0f"):format(r.y1))
	self.readouts.left:SetText(("%.0f"):format(left))
	self.readouts.right:SetText(("%.0f"):format(left + width))
end

editor:SetScript("OnShow", function()
	zone:Show()
	editor:LayoutRegion()
end)
editor:SetScript("OnHide", function()
	zone:Hide()
end)
end

-- ----------------------------------------------------------------------------
-- options window (also built defensively; see BuildRegionEditor)
-- ----------------------------------------------------------------------------
local colorPickerDragSetup = false

-- config-window geometry (MRM lessons): uniform 12px label-above-control
-- gap, uniform 8px inter-row gap, two-column block centered via the layout
-- pass below. TextBox frames sit FCA_TEXT_SHIFT right of the dropdowns'
-- edge: frames may agree while visible art disagrees (dropdown background
-- vs InputBox caps), and live the dropdowns read right of the boxes.
-- Paint-measured, one number, live-tuned. Fractional values are legal
-- (float32 layout): the reporter's screen pixels run ~2x stored units, so
-- all Paint numbers arrive halved. The long text box keeps its right edge
-- shared and shortens from the left instead, plus a half-px grow right
-- past that edge (enlarge, not move, per live order).
local FCA_TEXT_SHIFT = 4.5
local FCA_TEXT_GROW = 0.5
local FCA_LINK_GAP = 12
local FCA_COL_GAP = 12
local FCA_LINK_W = 22
-- EditBox text insets stay left/right SYMMETRIC everywhere (10/10 numeric,
-- 6/6 text): SetJustifyH("CENTER") centers the text field, so any asymmetry
-- visibly shifts the text off the box's middle while typing.
-- dropdown chrome: historic pad, used only where the template interiors
-- are unavailable (mock client); live buttons measure their own arrow
local FCA_DROPDOWN_PAD = 40
local FCA_LABEL_BASE = 12 -- GameFontHighlight (dropdown template Text), Fonts.xml:275-284
local FCA_TEXT_BASE = 10 -- GameFontHighlightSmall (all EditBoxes), Fonts.xml:39-46
-- Friz ships with every client (same file the template resolves to); the
-- literal covers fontless harnesses where the global is absent
local FCA_TEXT_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local FCA_TEXT_MIN = 7

-- text budget for a dropdown button: the template's label field runs from
-- +8 to the arrow's left edge (arrow RIGHT-anchored at +1), so the budget
-- is that span: W - 7 - arrowW. Arrow width is measured live (atlas DB is
-- C-side); without template interiors, the historic pad.
local function FCA_DropdownBudget(button)
	local w = (button.GetWidth and button:GetWidth()) or 126
	local arrow = button.Arrow
	if not (arrow and arrow.GetWidth) then
		return w - FCA_DROPDOWN_PAD
	end
	local arrowW = arrow:GetWidth() or 27
	if arrowW <= 0 then
		arrowW = 27
	end
	local avail = w - 7 - arrowW
	if avail < 20 then
		avail = 20
	end
	return avail
end

-- shrink a dropdown's selected label until it fits the button's text area.
-- Long family names (e.g. "Fira Sans Condensed Medium") overflow at the base
-- size; stepping down keeps them visible instead of clipped by the arrow.
-- Always starts from the base size, so a shorter pick grows back. Template
-- geometry stands untouched (re-anchoring the field broke vertical
-- rendering live); only the size adapts. No-op where the template exposes
-- no label (mock client).
local function FCA_FitDropdownText(button, fontPath, baseSize)
	local label = button and button.Text
	if not button or not label or not label.SetFont or not label.GetStringWidth then
		return
	end
	local avail = FCA_DropdownBudget(button)
	local size = baseSize or FCA_LABEL_BASE
	label:SetFont(fontPath, size, "")
	while (label:GetStringWidth() or 0) > avail and size > FCA_TEXT_MIN do
		size = size - 1
		label:SetFont(fontPath, size, "")
	end
end

-- shrink an EditBox's text until it fits the box's visible text area.
-- Explicit base (FCA_TEXT_FONT at FCA_TEXT_BASE, same Friz face the
-- template resolves to) with the live size tracked on the box: never
-- resolves the template object through GetFont, whose behavior after only
-- SetFontObject is promised nowhere. Grows back from base every run, so
-- shorter text restores. No-op where the client exposes no font surface.
local function FCA_FitTextBox(box)
	if not (box and box.SetFont and box.GetText and box.GetWidth) then
		return
	end
	if not (options and options.CreateFontString) then
		return
	end
	local scratch = options.FCA_scratch
	if not scratch then
		scratch = options:CreateFontString(nil, "OVERLAY")
		options.FCA_scratch = scratch
	end
	if not (scratch and scratch.SetFont and scratch.SetText and scratch.GetStringWidth) then
		return
	end
	local avail = box:GetWidth() - (box.FCA_pad or 20) -- left+right text insets
	local size = FCA_TEXT_BASE
	scratch:SetFont(FCA_TEXT_FONT, size, "")
	scratch:SetText(box:GetText() or "")
	while (scratch:GetStringWidth() or 0) > avail and size > FCA_TEXT_MIN do
		size = size - 1
		scratch:SetFont(FCA_TEXT_FONT, size, "")
	end
	if (box.FCA_size or FCA_TEXT_BASE) ~= size then
		box.FCA_size = size
		box:SetFont(FCA_TEXT_FONT, size, "")
	end
end

local function BuildOptionsWindow()
options = CreateFrame("Frame", "FloatingCombatAlertOptions", UIParent, "BackdropTemplate")
options:SetFrameStrata("HIGH")
options:SetSize(320, 414)
options:SetPoint("CENTER", UIParent, "CENTER", defaults.win.x, defaults.win.y)
options:SetMovable(true)
options:EnableMouse(true)
options:SetClampedToScreen(true)
-- the window moves from the press itself (no drag threshold)
options:SetScript("OnMouseDown", function(self, btn)
	if btn == "LeftButton" then
		self.moving = true
		self:StartMoving()
	end
end)
options:SetScript("OnMouseUp", function(self, btn)
	if btn ~= "LeftButton" or not self.moving then
		return
	end
	self.moving = false
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

-- link column: one checkbox per option row, left of both alert columns.
-- Positions are structural (layout pass centers each check on its row's
-- control), so adding or moving a row can never drift the checks.
local LINK_KEYS = { "font", "size", "color", "outline", "text", "direction", "duration", "fade" }
-- enter-column control per link key (swatch/textBox names differ from keys)
local LINK_CONTROLS = { font = "font", size = "size", color = "swatch", outline = "outline", text = "textBox", direction = "direction", duration = "duration", fade = "fade" }
options.linkChecks = {}
for i, key in ipairs(LINK_KEYS) do
	local linkKey = key
	local cb = CreateFrame("CheckButton", "FCALink" .. i, options, "UICheckButtonTemplate")
	cb:SetSize(FCA_LINK_W, FCA_LINK_W)
	cb:SetPoint("TOPLEFT", options, "TOPLEFT", 14, -92)
	cb:SetScript("OnClick", function(self)
		if not db then
			return
		end
		db.link[linkKey] = self:GetChecked()
		RefreshAll()
	end)
	options.linkChecks[key] = cb
end
options.linkTitle = options:CreateFontString(nil, "OVERLAY")
options.linkTitle:SetFontObject("GameFontNormalSmall")
options.linkTitle:SetText("Link")
options.linkTitle:SetPoint("TOP", options, "TOPLEFT", 14 + FCA_LINK_W / 2, -66)

-- one control column per alert side
local function MakeColumn(which, x)
	local col = CreateFrame("Frame", nil, options)
	col:SetSize(130, 324)
	col:SetPoint("TOPLEFT", options, "TOPLEFT", x, -76)

	col.title = col:CreateFontString(nil, "OVERLAY")
	col.title:SetFontObject("GameFontHighlightSmall")
	col.title:SetText((which == "enter") and "Entering" or "Leaving")
	-- header row: raised to sit next to the Link label (-66 window),
	-- centered over the column like the Link label sits over its checks
	col.title:SetPoint("TOP", col, "TOPLEFT", 63, 10)

	-- row label: every row's label shares one left edge at x=2
	local function MakeLabel(text, y)
		local fs = col:CreateFontString(nil, "OVERLAY")
		fs:SetFontObject("GameFontNormalSmall")
		fs:SetText(text)
		fs:SetPoint("TOPLEFT", col, "TOPLEFT", 2, y)
		return fs
	end

	-- labeled dropdown writing `field` from a menu of { text, [valueKey] }
	-- entries; `entries` may be a function, evaluated on every menu open.
	-- With `ownFonts`, each entry is drawn in the font its `path` names
	local function MakeDropdown(label, y, entries, valueKey, field, linkKey, ownFonts)
		local fs = MakeLabel(label, y)
		local dd = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
		dd:SetSize(126, 22)
		dd:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y - 12)
		dd:SetupMenu(function(_, rootDescription)
			if not db then
				return
			end
			local list = type(entries) == "function" and entries() or entries
			if #list > 20 then
				rootDescription:SetScrollMode(20 * 20) -- 20 rows of 20px, then scroll
			end
			for _, e in ipairs(list) do
				local entry = rootDescription:CreateRadio(
					e.text,
					function(data)
						return db[which][field] == data
					end,
					function(data)
						for _, t in ipairs(TargetsFor(which, linkKey)) do
							t[field] = data
						end
						RefreshAll()
					end,
					e[valueKey]
				)
				if ownFonts then
					entry:AddInitializer(function(button)
						local text = button.fontString
						FontStringSetFont(text, e.path, FCA_LABEL_BASE, "")
						text:SetTextToFit(e.text)
					end)
				end
			end
		end)
		return dd, fs
	end

	-- labeled numeric box: type any value and press enter; it is clamped to
	-- [lo, hi] (rounded to whole numbers when `whole`), non-numbers revert.
	-- Shifted right with the other text boxes to meet the dropdowns' visible
	-- edge (see the geometry note above).
	local function MakeNumberBox(label, y, maxLetters, field, linkKey, lo, hi, whole)
		local fs = MakeLabel(label, y)
		local box = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
		box:SetSize(56, 20)
		box:SetPoint("TOPLEFT", col, "TOPLEFT", FCA_TEXT_SHIFT, y - 12)
		box:SetFontObject("GameFontHighlightSmall")
		if box.SetTextInsets then
			box:SetTextInsets(10, 10, 2, 2)
		end
		box:SetAutoFocus(false)
		box:SetMaxLetters(maxLetters)
		box:SetJustifyH("CENTER")
		box:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			if not db then
				return
			end
			local v = tonumber(self:GetText())
			if v == nil then
				self:SetText(tostring(db[which][field]))
				return
			end
			if whole then
				v = math.floor(v + 0.5)
			end
			v = math.max(lo, math.min(hi, v))
			for _, t in ipairs(TargetsFor(which, linkKey)) do
				t[field] = v
			end
			RefreshAll()
		end)
		return box, fs
	end

	-- font dropdown: real dropdown widget, its label and every entry rendered
	-- in their own font. The menu compositor wraps each entry region in a
	-- proxy whose lookup asserts on SetFont (Blizzard_Menu/Compositor.lua;
	-- `entry.fontString:SetFont` raised Bugsack 3x/7x on open), so entries
	-- call FontString:SetFont itself; releasing the entry restores the menu
	-- font (SetFontObject in the compositor's defaults)
	col.font, col.fontLabel = MakeDropdown("Font", -4, FontList, "path", "font", "font", true)

	-- size: whole points
	col.size, col.sizeLabel = MakeNumberBox("Size", -46, 4, "size", "size", 4, 200, true)

	-- color
	col.swatch = CreateFrame("Button", nil, col)
	col.swatch:SetSize(26, 26)
	col.swatch:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -86)
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
	col.outline, col.outlineLabel = MakeDropdown("Outline", -120, OUTLINE_MENU, "style", "outlineStyle", "outline")

	-- alert text: full-width InputBox sharing its right edge with the
	-- dropdowns, shortened from the left by the box shift above.
	-- Slimmer insets than the numeric boxes so typed text can use the full
	-- box width; the pad below must stay their left+right sum (fit budget).
	-- Left and right stay EQUAL: CENTER justification centers the text
	-- field, so asymmetric insets visibly shift it off the box's middle.
	col.textLabel = MakeLabel("Text", -170)
	col.textBox = CreateFrame("EditBox", nil, col, "InputBoxTemplate")
	col.textBox:SetSize(126 - FCA_TEXT_SHIFT + FCA_TEXT_GROW, 20)
	col.textBox:SetPoint("TOPLEFT", col, "TOPLEFT", FCA_TEXT_SHIFT, -182)
	col.textBox:SetFontObject("GameFontHighlightSmall")
	-- explicit base on top of the object (color stays): the fit tracks size
	-- itself instead of resolving the template object back through GetFont
	if col.textBox.SetFont then
		col.textBox:SetFont(FCA_TEXT_FONT, FCA_TEXT_BASE, "")
	end
	col.textBox.FCA_size = FCA_TEXT_BASE
	col.textBox.FCA_pad = 12
	if col.textBox.SetTextInsets then
		col.textBox:SetTextInsets(6, 6, 2, 2)
	end
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
	-- fit mid-typing, not just on enter: shrinking the font never changes
	-- the text, so this cannot recurse (SetFont fires no text event)
	col.textBox:SetScript("OnTextChanged", function(self)
		FCA_FitTextBox(self)
	end)


	-- direction: does the text travel up or down
	col.direction, col.directionLabel = MakeDropdown("Direction", -210, DIRECTION_MENU, "style", "direction", "direction")

	-- duration: seconds between spawning and despawning
	col.duration, col.durationLabel = MakeNumberBox("Duration (sec)", -252, 5, "duration", "duration", 0.2, 60, false)

	-- fade: percent of the duration at which fading out starts (constant rate)
	col.fade, col.fadeLabel = MakeNumberBox("Fade start (%)", -292, 3, "fadeStart", "fade", 0, 100, true)

	col.Refresh = function()
		local cfg = db[which]
		col.font:SetText(FontNameFor(cfg.font))
		if col.font.Text then
			col.font.Text:SetFont(cfg.font, FCA_LABEL_BASE, "")
		end
		FCA_FitDropdownText(col.font, cfg.font, FCA_LABEL_BASE)
		if tonumber(col.size:GetText()) ~= cfg.size then
			col.size:SetText(tostring(cfg.size))
		end
		local r, g, b = HexToRGB(cfg.color)
		col.swatch.tex:SetColorTexture(r, g, b, 1)
		col.outline:SetText(MenuTextFor(OUTLINE_MENU, "style", cfg.outlineStyle))
		if col.outline.Text then
			col.outline.Text:SetFontObject("GameFontHighlight")
		end
		if col.textBox:GetText() ~= cfg.text then
			col.textBox:SetText(cfg.text)
		end
		FCA_FitTextBox(col.textBox)
		col.direction:SetText(MenuTextFor(DIRECTION_MENU, "style", cfg.direction))
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

-- MRM-style layout pass: center the two-column block in the window, center
-- the link title on the window-left to options-left gap's middle with every
-- check under it, then vertically center each check on its row's control.
-- Runs once every control exists, so positions stay structural when rows move.
local function FCA_LayoutControls()
	if not (options and options.enterCol and options.leaveCol) then
		return
	end
	for _, key in ipairs(LINK_KEYS) do
		if not options.linkChecks[key] then
			return
		end
	end
	local winW = options:GetWidth() or 320
	local colW = options.enterCol:GetWidth() or 130
	local totalW = FCA_LINK_W + FCA_LINK_GAP + colW + FCA_COL_GAP + colW
	local blockX = math.floor((winW - totalW) / 2 + 0.5)
	local enterX = blockX + FCA_LINK_W + FCA_LINK_GAP
	local leaveX = enterX + colW + FCA_COL_GAP
	local function shift(frame, x)
		local point, relTo, relPoint, _, y = frame:GetPoint(1)
		if not point then
			return
		end
		frame:ClearAllPoints()
		frame:SetPoint(point, relTo, relPoint, x, y)
	end
	shift(options.enterCol, enterX)
	shift(options.leaveCol, leaveX)
	-- link column lives in the gap between the window's left edge and the
	-- options' left edge: one gap middle parents both the title center and
	-- the checkbox column, so the label and the checks can never drift
	-- apart (integer rounding may sit either half a pixel off the middle).
	local linkMiddle = enterX / 2
	local linkX = math.floor(linkMiddle - FCA_LINK_W / 2 + 0.5)
	if options.linkTitle then
		options.linkTitle:ClearAllPoints()
		options.linkTitle:SetPoint("TOP", options, "TOPLEFT", linkX + FCA_LINK_W / 2, -66)
	end
	-- link checks keep one straight column (fixed X) with each row's Y
	-- derived from its control's center: no hardcoded row table to drift
	local _, _, _, _, colY = options.enterCol:GetPoint(1)
	if not colY then
		return
	end
	for _, key in ipairs(LINK_KEYS) do
		local cb = options.linkChecks[key]
		local ctl = options.enterCol[LINK_CONTROLS[key]]
		if ctl then
			local _, _, _, _, ctlY = ctl:GetPoint(1)
			local ctlH = ctl:GetHeight() or FCA_LINK_W
			if ctlY then
				local linkTop = colY + ctlY - ctlH / 2 + FCA_LINK_W / 2
				cb:ClearAllPoints()
				cb:SetPoint("TOPLEFT", options, "TOPLEFT", linkX, linkTop)
			end
		end
	end
end

FCA_LayoutControls()

-- dividers: the stocked GM-bgOpen pair, raw stock art, no sampling. Three
-- sampling attempts are deleted history (same-pixels slice, edge-glow
-- crop, center row, full-art transpose): the verticals kept rendering the
-- native art's own striping regardless, so the sampling path was inert and
-- only added failure modes. What renders is Blizzard's art as drawn.
local FCA_DIV_H = "GM-bgOpen-divider-horizontal"
local FCA_DIV_V = "GM-bgOpen-divider-vertical"

options.divider = options:CreateTexture(nil, "OVERLAY")
options.divider:SetAtlas(FCA_DIV_H, true)
options.divider:SetPoint("LEFT", options, "LEFT", 12, 0)
options.divider:SetPoint("RIGHT", options, "RIGHT", -12, 0)
options.divider:SetPoint("TOP", options.enterCol.outline, "BOTTOM", 0, -8)

-- vertical column separators: the left one hangs 5px left of the entering
-- column's edge; the right one sits centered in its gap (6px each side --
-- Paint-measured off-center toward its right neighbors before). Both span
-- top-to-bottom, crossing the header row like the columns do. Anchored to
-- the right column of each gap so nothing can drift them.
local function FCA_MakeVSeparator(anchorTo, xOff)
	local sep = options:CreateTexture(nil, "OVERLAY")
	sep:SetAtlas(FCA_DIV_V, true)
	sep:SetPoint("TOP", anchorTo, "TOPLEFT", xOff, 20)
	sep:SetPoint("BOTTOM", anchorTo, "BOTTOMLEFT", xOff, -6)
	return sep
end
options.sepLink = FCA_MakeVSeparator(options.enterCol, -5)
options.sepCols = FCA_MakeVSeparator(options.leaveCol, -6)

function RefreshAll() -- assigns the forward-declared upvalue (see PumpLoop)
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
	-- settings changed: restyle every in-flight alert immediately, resuming
	-- from its current position and alpha -- nothing restarts, nothing jumps
	local expired = {}
	for _, a in ipairs(activeAlerts) do
		local cfg = db[a.side]
		StyleAlertText(a.text, cfg)
		local oldDur = (a.doneT or 0) + (a.spanT or 0)
		local progress = oldDur > 0 and math.min(AlertElapsed(a) / oldDur, 1) or 0
		if progress >= 1 then
			expired[#expired + 1] = a -- already outlived the new timeline
		else
			local duration = ConfigureAlertAnimation(a, cfg, progress)
			a.doneT = progress * duration
			a.spanT = duration - a.doneT
			a.group:Play()
		end
	end
	for i = 1, #expired do
		ReleaseAlert(expired[i])
	end
	-- ... and keep the band hugging the text even while nothing is on screen
	if editor and editor:IsShown() then
		editor:LayoutRegion()
	end
end

options:SetScript("OnShow", function()
	RefreshAll()
	PumpLoop()
end)
options:SetScript("OnHide", function(self)
	-- hidden mid-move (Escape): finish the move so the spot is saved
	if self.moving then
		self:GetScript("OnMouseUp")(self, "LeftButton")
	end
	-- closing the window stops the loop, despawns loop text and the editor
	StopLoopAndDespawn()
	if editor then
		editor:Hide()
	end
end)

end

-- build the UI last and defensively: even if a widget template is missing in
-- some client flavor, the combat alerts keep working
pcall(function()
	BuildRegionEditor()
	BuildOptionsWindow()
end)

-- ----------------------------------------------------------------------------
-- login and persist through sessions functionality
-- ----------------------------------------------------------------------------
-- Midnight (12.x) gate discipline: there is none. Every op below just attempts.
-- Enforcement is object-driven, not flag-driven: tainted calls on secret-clean
-- objects serve under any restriction state, and nothing here can become
-- secret-marked -- the addon ingests no unit/combat/aura data, only the boolean
-- combat flag (a control signal, never stored into frames or passed to gated
-- APIs), and renders user-configured text on its own frames. If the engine ever
-- refuses, it errors LOUDLY (Bugsack, not silence): a silent queue would hide
-- the bug, an error gets reported and fixed. The only guards left are
-- crash-safety (nil options when the defensive UI build failed) and correctness
-- (first-sync adopts silently, expired timelines release). No restriction
-- events installed; combat arrives on the REGEN pair below (plus the
-- UNIT_FLAGS sync), each verified against the player-unit flag. The single
-- Blizzard-shared touch (ColorPickerFrame
-- strata while picking) is idempotent and live-verified mid-combat on clean
-- chrome. Classic flavors run the same code: no gate system there at all.
local inCombatKnown = nil

-- combat state: the REGEN pair brackets true combat (mob hate list or PvP
-- action). PLAYER_ENTER/LEAVE_COMBAT track auto-attack only -- starting or
-- stopping melee swings fires them while combat continues -- so they stay
-- unregistered (a stop-swings LEAVE mid-fight was the false "Leaving Combat"
-- bug). Every trigger below re-reads UnitAffectingCombat("player") and alerts
-- only on an actual change (Blizzard's AssistedCombatManager pattern), so
-- spurious or duplicate events are harmless no-ops. Never query
-- InCombatLockdown() here: it lags the events by design (secure-frame grace
-- period); UnitAffectingCombat is the immediate check.
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
		if type(_G[ADDON_NAME]) ~= "table" then
			_G[ADDON_NAME] = {}
		end
		db = _G[ADDON_NAME]
		MigrateLegacy(db)
		MergeDefaults(db, defaults)
		SanitizeFonts(not IsLoggedIn())
		if options then -- the defensive UI build may have failed; alerts stand alone
			options:ClearAllPoints()
			options:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y)
		end
		-- the REGEN pair brackets true combat (hate list / PvP action);
		-- UNIT_FLAGS re-syncs on any player-flag change (combat flag included)
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterUnitEvent("UNIT_FLAGS", "player")
		if RefreshAll then
			RefreshAll()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- every addon has loaded by now: addon fonts left unregistered are gone
		if db and SanitizeFonts(false) and RefreshAll then
			RefreshAll()
		end
		SyncCombatState(false)
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "UNIT_FLAGS" then
		SyncCombatState(true)
	end
end

-- event triggers
local Fr_FloatingCombatAlert = CreateFrame("Frame")
Fr_FloatingCombatAlert:RegisterEvent("ADDON_LOADED")
Fr_FloatingCombatAlert:RegisterEvent("PLAYER_ENTERING_WORLD")
Fr_FloatingCombatAlert:SetScript("OnEvent", FCA_loaded)

-- slash command functionality: bare /fca (or anything unrecognized) toggles
-- the options window, /fca reset restores every default
SLASH_FCA1 = "/fca"
SlashCmdList.FCA = function(msg)
	if not db then
		return
	end
	if string.match(msg, "^reset$") then
		local sv = _G[ADDON_NAME]
		if type(sv) ~= "table" then
			sv = {}
			_G[ADDON_NAME] = sv
		else
			for k in pairs(sv) do -- wipe in place: db aliases elsewhere stay valid
				sv[k] = nil
			end
		end
		db = sv
		MigrateLegacy(db)
		MergeDefaults(db, defaults)
		ReleaseAllAlerts()
		if RefreshAll then
			RefreshAll() -- also re-lays the editor when it is open
		end
		if options then
			options:ClearAllPoints()
			options:SetPoint("CENTER", UIParent, "CENTER", db.win.x, db.win.y)
		end
	else
		if options and options:IsShown() then
			options:Hide()
		elseif options then
			options:Show()
		end
	end
end
