--[[
    Unit Test Suite for Floating Combat Alert
    Run with: lua5.1 tests/test_fca.lua   (from the addon root)
--]]

local env = dofile("../shared/wow_test_env.lua");
local out = env.rawPrint;

local PASS, FAIL = 0, 0;
local function ok(cond, name, extra)
    if cond then PASS = PASS + 1; out("  PASS: " .. name);
    else FAIL = FAIL + 1; out("  FAIL: " .. name .. (extra and (" -- " .. tostring(extra)) or "")); end
end
local function approx(a, b, eps)
    return math.abs(a - b) <= (eps or 1e-6);
end
local function fireShow(frame)
    frame:Show();
    local s = frame:GetScript("OnShow");
    if s then s(frame); end
end
local function fireHide(frame)
    frame:Hide();
    local s = frame:GetScript("OnHide");
    if s then s(frame); end
end
local function DriveMenu(dd)
    local root = { items = {} };
    function root:CreateRadio(text, isSelected, setSelected, data)
        self.items[#self.items + 1] = { text = text, data = data, isSelected = isSelected, setSelected = setSelected };
    end
    dd:GetMenuGenerator()(dd, root);
    return root.items;
end
local function SyncOutOfCombat()
    env.playerInCombat = false;
    env:FireEvent("PLAYER_ENTERING_WORLD");
end

-- concurrent alert state (activeAlerts entries ARE the alert frames, newest last)
local alert, options, editor, slash, db;
local function ACount() return alert.active and #alert.active or 0; end
local function ALast() return alert.active and alert.active[#alert.active]; end
local function AText() local a = ALast(); return a and a.text:GetText(); end
local function AAlpha() local a = ALast(); return a and a:GetAlpha() or 0; end
local function AnyVisible() return ACount() > 0; end
local function BandWidthOf(profile)
    local w = 0;
    for _, side in ipairs({ profile.enter, profile.leave }) do
        w = math.max(w, math.floor(#side.text * (side.size or 12) / 2));
    end
    return w + 20;
end

-- ----------------------------------------------------------------------------
-- Static check: every XML template the addon references must exist in the 12.1
-- source dump (mocks ignore templates, so this is the only guard we have)
-- ----------------------------------------------------------------------------
do
    local src = io.open("Floating_Combat_Alert.lua", "r");
    local body = src and src:read("*a");
    if src then src:close(); end
    if body then
        local seen = {};
        for tmpl in body:gmatch('"([%w]+Template)"') do
            if not seen[tmpl] then
                seen[tmpl] = true;
                local ok51, hit = pcall(function()
                    local p = io.popen(("grep -rl 'name=\"%s\"' ../Source_UI_12.1/Interface/AddOns 2>/dev/null | head -1"):format(tmpl));
                    local line = p and p:read("*l");
                    if p then p:close(); end
                    return line;
                end);
                ok(ok51 and hit, "template exists in 12.1 client: " .. tmpl, hit);
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Fresh client: load the addon
-- ----------------------------------------------------------------------------
local chunk, err = loadfile("Floating_Combat_Alert.lua");
ok(chunk ~= nil, "addon file parses as valid lua", err);
chunk();

alert = env:FindFrame("FloatingCombatAlertFrame"); -- the alert driver
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
ok(alert ~= nil and options ~= nil and editor ~= nil, "driver, options and editor frames created");
ok(alert.active ~= nil, "driver exposes the active alert list");
ok(not options:IsShown() and not editor:IsShown(), "windows hidden before login");
ok(_G.SLASH_FCA1 == "/fca" and type(_G.SlashCmdList.FCA) == "function", "slash command /fca registered");
ok(_G.SLASH_FCA2 == nil, "no alias slash commands (fca only)");

local eventFrame;
for _, f in ipairs(env.frames) do
    if f:IsEventRegistered("ADDON_LOADED") then eventFrame = f; break; end
end
ok(eventFrame ~= nil, "addon event frame registered for ADDON_LOADED");
ok(not eventFrame:IsEventRegistered("PLAYER_REGEN_DISABLED") and not eventFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"),
    "regen events are NOT registered (player-unit events used instead)");

-- ----------------------------------------------------------------------------
-- First login: v0.6 defaults
-- ----------------------------------------------------------------------------
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
local db = _G.Floating_Combat_Alert;
ok(type(db.link) == "table" and db.duration == nil, "global duration replaced by per-side durations");
ok(db.link.font == true and db.link.size == true and db.link.outline == true,
    "font/size/outline linked by default");
ok(db.link.text == false and db.link.color == false, "text and color unlinked by default");
ok(db.link.direction == true and db.link.duration == true and db.link.fade == true,
    "direction/duration/fade linked by default");
ok(db.region.cx == 0 and db.region.y1 == -100 and db.region.y2 == 100, "region band centered on 0,0");
ok(type(db.win) == "table" and db.win.x == 0 and db.win.y == 0, "window position defaults to screen center");
ok(db.enter.text == "Entering Combat" and db.enter.color == "FFFF0000", "enter text and pure red color");
ok(db.leave.text == "Leaving Combat" and db.leave.color == "FF00FF00", "leave text and pure green color");
ok(db.enter.font == "Fonts\\FRIZQT__.TTF" and db.enter.size == 28, "Friz Quadrata at size 28");
ok(db.enter.outlineStyle == "outline", "outline defaults to thin");
ok(db.enter.direction == "up" and db.enter.duration == 2 and db.enter.fadeStart == 50,
    "enter direction/duration/fade defaults");
ok(db.leave.duration == 2 and db.leave.fadeStart == 50 and db.leave.direction == "up",
    "leave direction/duration/fade defaults");
ok(db.enter.mono == nil, "monochrome removed from the schema");

ok(eventFrame:IsEventRegistered("PLAYER_ENTER_COMBAT") and eventFrame:IsEventRegistered("PLAYER_LEAVE_COMBAT"),
    "player combat events registered after login");
ok(eventFrame:IsEventRegistered("UNIT_FLAGS") and eventFrame:IsEventRegistered("PLAYER_ENTERING_WORLD"),
    "flag fallback and login sync registered");
ok(not eventFrame:IsEventRegistered("PLAYER_LOGIN"), "login beacon event removed");

-- login is completely silent: no chat output, no scheduled flashes
local logBefore = #env.printLog;
env:FireEvent("PLAYER_LOGIN");
ok(#env.printLog == logBefore, "login produces no chat output", #env.printLog - logBefore);
ok(#env.timers == 0, "no login flash is scheduled");
ok(ACount() == 0, "no alert on login");

-- dragging the window persists its center-relative position
UIParent:SetSize(2048, 1024);
options:SetPoint("CENTER", UIParent, "CENTER", 100, 60);
(options:GetScript("OnDragStop") or function() end)(options);
ok(db.win.x == 100 and db.win.y == 60, "dragging the window saves its position", ("%s,%s"):format(tostring(db.win.x), tostring(db.win.y)));
local wx2, wy2 = select(4, options:GetPoint(1)), select(5, options:GetPoint(1));
ok(wx2 == 100 and wy2 == 60, "window re-anchored at the saved offset");

-- ----------------------------------------------------------------------------
-- Combat: fade starts at 50%, text bound inside the band
-- ----------------------------------------------------------------------------
ok(env:FireEvent("PLAYER_ENTER_COMBAT") == 1, "PLAYER_ENTER_COMBAT handled");
ok(AnyVisible() and AText() == "Entering Combat", "enter alert shown");
local r, g, b = ALast().text:GetTextColor();
ok(approx(r, 1) and approx(g, 0) and approx(b, 0), "enter color is pure red");

local textH = ALast().text:GetStringHeight();
local span = math.max(0, db.region.y2 - db.region.y1 - textH);
local startY = select(5, ALast():GetPoint(1));
ok(approx(startY, db.region.y1 + textH / 2), "text spawns fully inside the region bottom", startY);
local cx = select(4, ALast():GetPoint(1));
ok(approx(cx, db.region.cx), "text horizontally centered in the band");

env:AdvanceTime(1.0); -- exactly the 50% fade start
env:TickAnims();
ok(approx(AAlpha(), 1), "no fading before the fade-start point", AAlpha());
env:AdvanceTime(0.5); -- 75% of the duration
env:TickAnims();
ok(approx(AAlpha(), 0.5, 0.02), "constant fade from fade-start to despawn", AAlpha());
env:AdvanceTime(1);
env:TickAnims();
ok(ACount() == 0, "alert despawns at the end of its duration");

ok(env:FireEvent("PLAYER_LEAVE_COMBAT") == 1, "PLAYER_LEAVE_COMBAT handled");
ok(AText() == "Leaving Combat", "leave alert shown");
r, g, b = ALast().text:GetTextColor();
ok(approx(g, 1) and approx(r, 0), "leave color is pure green");
env:AdvanceTime(2.5);
env:TickAnims();

-- direction: down reverses the journey
SyncOutOfCombat();
local slash = _G.SlashCmdList.FCA;
local dirItems = DriveMenu(options.enterCol.direction);
ok(#dirItems == 2 and dirItems[1].text == "Up" and dirItems[2].text == "Down", "direction dropdown offers up/down");
dirItems[2].setSelected(dirItems[2].data);
ok(db.enter.direction == "down", "direction pick saved");
env:FireEvent("PLAYER_ENTER_COMBAT");
local downY = select(5, ALast():GetPoint(1));
ok(approx(downY, db.region.y2 - textH / 2), "down direction spawns at the region top", tostring(downY));
env:AdvanceTime(1);
env:TickAnims();
local downMidY = select(5, ALast():GetPoint(1));
ok(downMidY < downY, "down direction travels downward", tostring(downMidY));
env:AdvanceTime(1.5);
env:TickAnims();
dirItems[1].setSelected(dirItems[1].data); -- back to up

-- player-flag fallback + duplicate suppression
SyncOutOfCombat();
env.playerInCombat = true;
ok(env:FireEvent("UNIT_FLAGS", "player") == 1, "UNIT_FLAGS handled");
ok(AnyVisible() and AText() == db.enter.text, "combat entered via player flag");
env:AdvanceTime(0.5);
env:TickAnims();
local alphaMid = AAlpha();
local countMid = ACount();
ok(env:FireEvent("PLAYER_ENTER_COMBAT") == 1, "duplicate dedicated event dispatched");
ok(ACount() == countMid and approx(AAlpha(), alphaMid, 0.05), "duplicate trigger doesn't double-spawn");
env:AdvanceTime(2.5);
env:TickAnims();
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
ok(AText() == db.leave.text, "combat left via player flag");
env:AdvanceTime(2.5);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- CONCURRENCY: a new combat message must not replace the old one -- both keep
-- floating in the band
-- ----------------------------------------------------------------------------
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
local d0 = {};
for i, a in ipairs(alert.active) do d0[i] = tostring(a) .. ":" .. a.text:GetText(); end
out("after enter fire: " .. #alert.active .. " -> " .. table.concat(d0, " | "));
env:AdvanceTime(0.4); -- enter alert ~20% through its journey
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player"); -- leave fires while enter is still flying
ok(ACount() == 2, "both alerts in flight at once", ACount());
local texts = {};
for _, a in ipairs(alert.active) do texts[a.text:GetText()] = true; end
local dbg = {};
for _, a in ipairs(alert.active) do dbg[#dbg+1] = a.side .. ":" .. a.text:GetText() .. ":" .. tostring(a); end
ok(texts["Entering Combat"] and texts["Leaving Combat"], "enter and leave both visible concurrently",
    table.concat(dbg, "|"));
env:AdvanceTime(0.75);
env:TickAnims();
ok(alert.active[1]:GetAlpha() < ALast():GetAlpha(),
    "older alert keeps fading while the newer is opaque");
env:AdvanceTime(2.5);
env:TickAnims();
ok(ACount() == 0, "concurrent alerts all despawn on schedule");

-- ----------------------------------------------------------------------------
-- Legacy migrations
-- ----------------------------------------------------------------------------
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
chunk();
_G.Floating_Combat_Alert = { -- v1 profile
    x = 0, y = 220, fontSize = 40, duration = 2, rise = 80,
    enterText = "Entering Combat", leaveText = "Leaving Combat",
    enterColor = "FFFFFF00", leaveColor = "FF00FFFF",
};
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
db = _G.Floating_Combat_Alert;
ok(type(db.enter) == "table" and db.enter.size == 40, "v1 flat table migrated");
ok(db.enter.duration == 2 and db.enter.fadeStart == 50 and db.enter.direction == "up",
    "v1 global duration migrated per side with fade/direction defaults");
ok(db.region.cx == 0 and db.region.y1 == 220 and db.region.y2 == 300,
    "v1 wide region collapsed to its center line");
ok(db.link.color == false and db.link.font == true, "v1 migration splits link per setting");

alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;

-- v0.4 profile with boolean appearance flags normalizes
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
chunk();
_G.Floating_Combat_Alert = {
    linked = true,
    enter = { text = "E", color = "FFFF0000", font = "Fonts\\FRIZQT__.TTF", size = 32, outline = true, thick = false, mono = false },
    leave = { text = "L", color = "FF00FF00", font = "Fonts\\FRIZQT__.TTF", size = 32, outline = nil, thick = true, mono = false },
    region = { x1 = -200, y1 = 160, x2 = 200, y2 = 340 },
};
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
db = _G.Floating_Combat_Alert;
ok(db.enter.outlineStyle == "outline" and db.enter.outline == nil, "v2 outline=true normalizes to outlineStyle");
ok(db.leave.outlineStyle == "thick" and db.leave.thick == nil, "v2 thick=true normalizes to thick style");
ok(db.enter.duration == 2 and db.leave.duration == 2 and db.enter.fadeStart == 50, "v2 profile gains duration/fade defaults");

alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;

-- ----------------------------------------------------------------------------
-- Options window: opens, loop auto-runs, draggable
-- ----------------------------------------------------------------------------
slash("");
ok(options:IsShown(), "/fca opens the options window");
ok(options:GetScript("OnDragStart") ~= nil and options:GetScript("OnDragStop") ~= nil, "window is drag-and-drop movable");
fireShow(options);
ok(options.linkChecks.font:GetChecked() == true and options.linkChecks.color:GetChecked() == false,
    "link checkboxes reflect defaults (color unlinked)");
ok(options.linkChecks.direction:GetChecked() == true and options.linkChecks.fade:GetChecked() == true,
    "direction and fade links default checked");
ok(options.enterCol:IsShown() and options.leaveCol:IsShown(), "both alert columns always visible");
ok(options.enterCol.title:GetText() == "Entering" and options.leaveCol.title:GetText() == "Leaving",
    "columns titled per side");
ok(options.regionBtn:GetWidth() == 292 and options.regionBtn:GetText() == "move region",
    "move-region button spans the whole window");
ok(options.divider ~= nil and options.divider.atlas == "Options_HorizontalDivider",
    "divider uses Blizzard's standard divider atlas");

-- test loop auto-runs while the window is open (timer-driven)
env:RunTimers();
ok(ACount() > 0, "test loop spawns while the window is open");
local sawEnter, sawLeave = false, false;
local seenTexts = {};
for _ = 1, 60 do
    env:RunTimers();
    env:AdvanceTime(0.25);
    env:TickAnims();
    if ACount() > 0 then
        seenTexts[AText()] = true;
        if AText() == db.enter.text then sawEnter = true; end
        if AText() == db.leave.text then sawLeave = true; end
    end
end
ok(sawEnter and sawLeave, "loop alternates both alerts constantly",
    table.concat((function() local k = {}; for key in pairs(seenTexts) do k[#k+1] = key end return k end)(), "|"));

-- real combat text spawns fresh while the loop is running
SyncOutOfCombat();
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
ok(AnyVisible() and AAlpha() == 1 and AText() == db.enter.text,
    "real combat text spawns fresh while the loop is running", AAlpha());
env:AdvanceTime(3);
env:TickAnims();
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(3);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Font dropdown, size editbox, outline dropdown
-- ----------------------------------------------------------------------------
local fontItems = DriveMenu(options.enterCol.font);
ok(#fontItems == 7, "font dropdown offers the seven western typefaces", fontItems and #fontItems);
local cjkFound = false;
for _, item in ipairs(fontItems) do
    if item.data:find("2002") or item.data:find("ARKai") or item.data:find("Hei") then cjkFound = true; end
end
ok(not cjkFound, "CJK locale fonts (Latin-invisible) are excluded");
local morpheusItem, arialItem;
for _, item in ipairs(fontItems) do
    if item.text == "Morpheus" then morpheusItem = item; end
    if item.text == "Arial Narrow" then arialItem = item; end
end
ok(morpheusItem ~= nil and morpheusItem.data == "Fonts\\MORPHEUS.TTF", "Morpheus uses the modern TTF path",
    morpheusItem and tostring(morpheusItem.data));
arialItem.setSelected(arialItem.data);
ok(db.enter.font == "Fonts\\ARIALN.TTF" and db.leave.font == "Fonts\\ARIALN.TTF",
    "linked font pick applies to both");
ok(options.enterCol.font:GetText() == "Arial Narrow", "dropdown label shows the font name");
env:AdvanceTime(3);
env:TickAnims();

options.enterCol.size:SetText("48");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db.enter.size == 48 and db.leave.size == 48, "size editbox applies to both sides");
options.enterCol.size:SetText("banana");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db.enter.size == 48 and options.enterCol.size:GetText() == "48", "non-numeric size reverts");
options.enterCol.size:SetText("999");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db.enter.size == 200, "size clamps to the 4-200 range", tostring(db.enter.size));

local outlineItems = DriveMenu(options.enterCol.outline);
ok(#outlineItems == 3, "outline dropdown offers none/thin/thick", outlineItems and #outlineItems);
ok(outlineItems[2].text == "Thin" and outlineItems[2].data == "outline", "middle outline option is named Thin");
outlineItems[3].setSelected(outlineItems[3].data); -- thick
ok(db.enter.outlineStyle == "thick" and db.leave.outlineStyle == "thick", "outline pick applies to both");
ok(options.enterCol.outline:GetText() == "Thick", "outline dropdown label updates");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
local _, _, flags = ALast().text:GetFont();
ok(flags and flags:find("THICKOUTLINE", 1, true) ~= nil, "alert renders with thick outline", tostring(flags));

-- live restyle while the alert is flying
env:AdvanceTime(0.4);
env:TickAnims();
outlineItems[1].setSelected(outlineItems[1].data); -- none
ok(AnyVisible(), "alert still flying after restyle");
flags = select(3, ALast().text:GetFont());
ok(flags == nil, "appearance change restyles the in-flight alert immediately", tostring(flags));
env:AdvanceTime(2.5);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Per-setting link column
-- ----------------------------------------------------------------------------
-- color is unlinked by default: editing enter's color must not touch leave
local enterHexBefore, leaveHexBefore = db.enter.color, db.leave.color;
options.enterCol.swatch:GetScript("OnClick")();
_G.ColorPickerFrame:SetColorRGB(0.2, 0.4, 0.9);
_G.ColorPickerFrame.info.swatchFunc();
ok(db.enter.color ~= enterHexBefore and db.leave.color == leaveHexBefore,
    "unlinked color edit touches only the enter side",
    ("%s/%s"):format(db.enter.color, db.leave.color));

-- unlink size via its checkbox
options.linkChecks.size:SetChecked(false);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);
ok(db.link.size == false, "unticking a link checkbox saves it");
options.leaveCol.size:SetText("64");
options.leaveCol.size:GetScript("OnEnterPressed")(options.leaveCol.size);
ok(db.leave.size == 64 and db.enter.size == 200, "unlinked size touches only that side");
options.linkChecks.size:SetChecked(true);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);
options.enterCol.size:SetText("90");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db.enter.size == 90 and db.leave.size == 90, "relinking makes edits hit both sides again");

-- ----------------------------------------------------------------------------
-- Text, direction, duration, fade rows (bottom segment)
-- ----------------------------------------------------------------------------
options.linkChecks.text:SetChecked(false);
options.linkChecks.text:GetScript("OnClick")(options.linkChecks.text);
options.enterCol.textBox:SetText("Pulling!");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(db.enter.text == "Pulling!" and db.leave.text == "L", "unlinked text touches only that side");
options.enterCol.textBox:SetText("");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(db.enter.text == "Pulling!", "empty text is rejected");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AText() == "Pulling!", "custom text is displayed");
env:AdvanceTime(0.3);
env:TickAnims();
options.enterCol.textBox:SetText("Incoming!");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(AText() == "Incoming!", "text change restyles the in-flight alert immediately");
env:AdvanceTime(2.5);
env:TickAnims();

-- duration editbox: per side, clamped
SyncOutOfCombat();
options.linkChecks.duration:SetChecked(false);
options.linkChecks.duration:GetScript("OnClick")(options.linkChecks.duration);
options.enterCol.duration:SetText("1");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);
ok(db.enter.duration == 1 and db.leave.duration == 2, "unlinked duration touches only that side");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.9);
ok(AnyVisible(), "1s duration alert still visible at 0.9s");
env:AdvanceTime(0.3);
env:TickAnims();
ok(ACount() == 0, "1s duration alert despawned by 1.2s");
options.enterCol.duration:SetText("banana");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);
ok(db.enter.duration == 1 and options.enterCol.duration:GetText() == "1", "non-numeric duration reverts");

-- fade editbox: clamped 0-100; 100 = never fades
options.enterCol.fade:SetText("150");
options.enterCol.fade:GetScript("OnEnterPressed")(options.enterCol.fade);
ok(db.enter.fadeStart == 100, "fade start clamps to 100", tostring(db.enter.fadeStart));
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.9); -- 90% of the duration with fade start 100%
env:TickAnims();
ok(approx(AAlpha(), 1), "fade start 100 never fades", AAlpha());
options.enterCol.fade:SetText("0");
options.enterCol.fade:GetScript("OnEnterPressed")(options.enterCol.fade);
env:TickAnims(); -- live restyle rebuilds the animation from current progress
ok(AAlpha() < 1, "fade change reconfigures the in-flight animation", tostring(AAlpha()));
env:AdvanceTime(1.5);
env:TickAnims();
ok(ACount() == 0, "faded alert still despawns on schedule");

-- mid-flight restyles continue from the exact position and alpha (no restart)
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.5); -- 50% of the 1s enter duration
env:TickAnims();
local yMid = select(5, ALast():GetPoint(1));
local alphaMid = AAlpha(); -- fading since spawn (fade start 0)
options.enterCol.textBox:SetText("retuned");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(approx(select(5, ALast():GetPoint(1)), yMid), "restyle keeps the in-flight text position",
    tostring(select(5, ALast():GetPoint(1))));
ok(approx(AAlpha(), alphaMid, 0.05), "restyle keeps the in-flight alpha", AAlpha());
options.enterCol.duration:SetText("3");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);
ok(approx(select(5, ALast():GetPoint(1)), yMid, 0.01), "duration change keeps the text in place",
    tostring(select(5, ALast():GetPoint(1))));
env:AdvanceTime(0.6);
env:TickAnims();
local yLater = select(5, ALast():GetPoint(1));
ok(AnyVisible() and yLater > yMid, "travel continues onward at the new pace", tostring(yLater));
env:AdvanceTime(3);
env:TickAnims();
ok(ACount() == 0, "extended alert despawns at the new duration");
-- restore the 1s duration the later window-close tests rely on
options.enterCol.duration:SetText("1");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);

-- ----------------------------------------------------------------------------
-- Region band editor (toggled by the options window's move-region button)
-- ----------------------------------------------------------------------------
editor:Show();
(editor:GetScript("OnShow") or function() end)(editor);
local rx1, ry1 = select(4, editor:GetPoint(1)), select(5, editor:GetPoint(1));
ok(rx1 == editor:BandLeft() and ry1 == db.region.y1, "editor mirrors the saved band");
ok(editor.edges.top ~= nil and editor.edges.bottom ~= nil, "top and bottom edge handles exist");
ok(editor.readouts.left ~= nil and editor.readouts.right ~= nil, "left and right X readouts exist");
ok(editor.readouts.left.isFontString == true, "coord readouts are plain clickthrough text");
local ht = editor.edges.top.tex;
ok(ht ~= nil and ht.r == 0 and ht.g == 1 and ht.b == 0 and ht.a == 0.5, "drag handles are solid green at 50% alpha");

-- band width hugs the bigger alert text
local expectedW = BandWidthOf(db);
ok(editor:GetWidth() == expectedW, "band width hugs the bigger alert text",
    ("%s vs %s"):format(tostring(editor:GetWidth()), tostring(expectedW)));

-- drag the top edge: vertical only
env.cursorX, env.cursorY = 0, 0;
editor.edges.top:GetScript("OnMouseDown")(editor.edges.top, "LeftButton");
env.cursorX, env.cursorY = 0, 90;
env:AdvanceTime(0.05);
editor.edges.top:GetScript("OnMouseUp")(editor.edges.top);
ok(db.region.y2 == 430 and db.region.cx == 0, "top edge drag resizes vertically only",
    ("y2=%s cx=%s"):format(tostring(db.region.y2), tostring(db.region.cx)));

env.cursorX, env.cursorY = 0, 0;
editor.edges.top:GetScript("OnMouseDown")(editor.edges.top, "LeftButton");
env.cursorX, env.cursorY = 0, -1000;
env:AdvanceTime(0.05);
editor.edges.top:GetScript("OnMouseUp")(editor.edges.top);
ok(db.region.y2 - db.region.y1 == 20, "band cannot shrink below 20 tall", tostring(db.region.y2 - db.region.y1));

-- dragging the middle moves the whole band anywhere
local before = { cx = db.region.cx, y1 = db.region.y1, y2 = db.region.y2 };
env.cursorX, env.cursorY = 0, 0;
editor:GetScript("OnDragStart")(editor);
env.cursorX, env.cursorY = -25, 35;
env:AdvanceTime(0.05);
editor:GetScript("OnDragStop")(editor);
ok(db.region.cx == before.cx - 25 and db.region.y2 == before.y2 + 35, "center drag moves the whole band");

-- readouts mirror the moved band edges
ok(editor.readouts.left:GetText() == ("%.0f"):format(editor:BandLeft()), "left X readout mirrors the band edge",
    editor.readouts.left:GetText());
ok(editor.readouts.right:GetText() == ("%.0f"):format(editor:BandRight()), "right X readout mirrors the band edge",
    editor.readouts.right:GetText());

-- journey follows the moved band
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
local th = ALast().text:GetStringHeight();
ok(approx(select(5, ALast():GetPoint(1)), db.region.y1 + th / 2), "journey starts bound inside the moved band");
env:AdvanceTime(3);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Closing the window cleans up
-- ----------------------------------------------------------------------------
SyncOutOfCombat(); -- a real combat alert is in flight across the close
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(0.2);
slash("");
fireHide(options);
ok(not options:IsShown(), "window closed");
ok(not editor:IsShown(), "closing the window closes the region editor");
env:RunTimers();
env:AdvanceTime(2);
env:TickAnims();
ok(ACount() == 0, "loop stops and nothing respawns after the window closes");

-- loop text despawn on close
slash("");
fireShow(options);
local despawnChecked = false;
for _ = 1, 60 do
    env:RunTimers();
    env:AdvanceTime(0.25);
    env:TickAnims();
    if ACount() > 0 then
        local wasLoop = false;
        for _, a in ipairs(alert.active) do
            if a.fromLoop then wasLoop = true; end
        end
        fireHide(options);
        despawnChecked = wasLoop and ACount() == 0;
        break;
    end
end
ok(despawnChecked, "closing the window despawns the in-flight loop text");

-- ----------------------------------------------------------------------------
-- UI reload with the customized profile
-- ----------------------------------------------------------------------------
local carried = {
    cx = db.region.cx, enterSize = db.enter.size, leaveSize = db.leave.size,
    linkSize = db.link.size, linkColor = db.link.color, text = db.enter.text,
    winX = db.win.x, winY = db.win.y, fade = db.enter.fadeStart,
};
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
local reloadOK, reloadErr = pcall(chunk);
ok(reloadOK, "addon reloads without runtime error", reloadErr);
alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
local db3 = _G.Floating_Combat_Alert;
ok(db3.region.cx == carried.cx, "region survives reload", tostring(db3.region.cx));
ok(db3.enter.size == carried.enterSize and db3.leave.size == carried.leaveSize, "per-side sizes survive reload");
ok(db3.enter.text == carried.text, "custom text survives reload");
ok(db3.link.size == carried.linkSize and db3.link.color == carried.linkColor, "per-setting link state survives reload");
ok(db3.win.x == carried.winX and db3.win.y == carried.winY, "window position survives reload");
ok(db3.enter.fadeStart == carried.fade, "fade start survives reload");

-- login while in combat syncs silently, without a stale alert
env.playerInCombat = true;
env:FireEvent("PLAYER_ENTERING_WORLD");
ok(ACount() == 0, "login mid-combat syncs silently without alert");
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
ok(AnyVisible() and AText() == db3.leave.text, "flag transition after silent sync alerts");
env:AdvanceTime(3);
env:TickAnims();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AnyVisible() and AText() == db3.enter.text, "dedicated events work after silent sync");
env:AdvanceTime(3);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Resilience: missing templates or raising fonts must not take down the alerts
-- ----------------------------------------------------------------------------
env:Reset();
env.raisesFontErrors = true;
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
local raiseOK, raiseErr = pcall(chunk);
ok(raiseOK, "raising font probes do not propagate", raiseErr);
ok(#env.errors == 0, "raising font probes never reach the error handler", #env.errors);
env.failTemplates = { "WowStyle1DropdownTemplate" };
env:Reset(); -- fresh session: drop the raises chunk's frames so events don't double-dispatch
env.raisesFontErrors = nil;
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
chunk();

-- bind to the LATEST frames (multiple loads may exist in env.frames)
alert, options, editor = nil, nil, nil;
for _, f in ipairs(env.frames) do
    if f:GetName() == "FloatingCombatAlertFrame" then alert = f; end
    if f:GetName() == "FloatingCombatAlertOptions" then options = f; end
    if f:GetName() == "FloatingCombatAlertRegionEditor" then editor = f; end
    if f:IsEventRegistered("ADDON_LOADED") then ef = f; end
end
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
ok(ef ~= nil and ef:IsEventRegistered("PLAYER_ENTER_COMBAT"), "combat events registered despite UI failure");
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AnyVisible() and AText() == _G.Floating_Combat_Alert.enter.text,
    "alerts fully functional without options UI", tostring(AText()));
env:AdvanceTime(3);
env:TickAnims();
env.failTemplates = nil;

out(string.format("\nTest Results: %d Passed, %d Failed", PASS, FAIL));
if FAIL > 0 then
    os.exit(1);
else
    out("ALL TESTS PASSED SUCCESSFULLY!");
end
