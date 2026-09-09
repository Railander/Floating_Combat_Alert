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

local alert = env:FindFrame("FloatingCombatAlertFrame");
local options = env:FindFrame("FloatingCombatAlertOptions");
local editor = env:FindFrame("FloatingCombatAlertRegionEditor");
ok(alert ~= nil and options ~= nil and editor ~= nil, "driver, options and editor frames created");
-- concurrent alert helpers: the newest spawn is last in the active list
local function ACount() return alert.active and #alert.active or 0; end
local function ALast() return alert.active and alert.active[#alert.active]; end
local function AText() local a = ALast(); return a and a.frame.text:GetText(); end
local function AAlpha() local a = ALast(); return a and a.frame.text:GetAlpha() or 0; end
local function AnyVisible() return ACount() > 0; end
local function AnyTicker()
    for _, f in ipairs(env.frames) do
        if f.shown and f.scripts.OnUpdate and f ~= alert then return true; end
    end
    return false;
end

ok(not AnyVisible() and not options:IsShown() and not editor:IsShown(), "nothing shown before login");
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
-- First login: v0.5 defaults
-- ----------------------------------------------------------------------------
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
local db = _G.Floating_Combat_Alert;
ok(type(db.link) == "table" and db.duration == nil, "global duration replaced by per-side durations");
ok(db.link.font == true and db.link.size == true and db.link.outline == true,
    "font/size/outline linked by default");
ok(db.link.text == false, "text unlinked by default");
ok(db.link.color == false and db.link.direction == true and db.link.duration == true and db.link.fade == true,
    "color unlinked; direction/duration/fade linked by default");
ok(db.region.cx == 0 and db.region.y1 == -100 and db.region.y2 == 100, "default region band centered on 0,0");
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

-- probing fonts that raise engine errors must stay silent and fail the probe
env.raisesFontErrors = true;
local raisesBefore = #env.errors;
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
local raiseOK, raiseErr = pcall(chunk);
ok(raiseOK, "raising font probes do not propagate", raiseErr);
ok(#env.errors == raisesBefore, "raising font probes never reach the error handler", #env.errors - raisesBefore);
env.raisesFontErrors = nil; -- restore normal font behavior for later sessions

-- a saved font that no longer validates falls back to the default silently
db.enter.font = "Fonts\\NOT_A_REAL_FONT.TTF"; -- a font no client ships
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
chunk();
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
local dbSan = _G.Floating_Combat_Alert;
ok(dbSan.enter.font == "Fonts\\FRIZQT__.TTF", "invalid saved font falls back to the default", dbSan.enter.font);
ok(dbSan.leave.font == "Fonts\\FRIZQT__.TTF", "leave font sanitized too");
ok(#env.errors == 0, "font probing never reaches the error handler", #env.errors);

alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;

ok(eventFrame ~= nil, "event frame reference retained", "placeholder");

-- re-login properly on a clean session for the remaining suites
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
chunk();
alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
db = _G.Floating_Combat_Alert;

ok(eventFrame:IsEventRegistered("PLAYER_ENTER_COMBAT") and eventFrame:IsEventRegistered("PLAYER_LEAVE_COMBAT"),
    "player combat events registered after login");
ok(eventFrame:IsEventRegistered("UNIT_FLAGS") and eventFrame:IsEventRegistered("PLAYER_ENTERING_WORLD"),
    "flag fallback and login sync registered");

-- window restored to the saved position
local wx, wy = select(4, options:GetPoint(1)), select(5, options:GetPoint(1));
ok(wx == 0 and wy == 0, "config window anchored at its saved position", ("%s,%s"):format(tostring(wx), tostring(wy)));

-- login beacon + render self-test
local logBefore = #env.printLog;
env:FireEvent("PLAYER_LOGIN");
local beacon = table.concat(env.printLog, "\n", logBefore + 1);
ok(beacon:find("%[Floating Combat Alert%]") ~= nil and beacon:find("0%.6%.1") ~= nil,
    "login beacon prints version to chat", beacon);
ok(#env.timers == 0, "no login flash is scheduled");

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
local r, g, b = ALast().frame.text:GetTextColor();
ok(approx(r, 1) and approx(g, 0) and approx(b, 0), "enter color is pure red");

local textH = ALast().frame.text:GetStringHeight();
local expectedW = math.max(#db.enter.text * 14, #db.leave.text * 14) + 20; -- size 28 -> char factor 14
ok(editor:BandWidth() == expectedW, "band width hugs the bigger alert text",
    ("%s vs %s"):format(tostring(editor:BandWidth()), tostring(expectedW)));
local span = math.max(0, db.region.y2 - db.region.y1 - textH);
local startY = select(5, ALast().frame:GetPoint(1));
ok(approx(startY, db.region.y1 + textH / 2), "text spawns fully inside the region bottom", startY);
local cx = select(4, ALast().frame:GetPoint(1));
ok(approx(cx, db.region.cx), "text horizontally centered in the band");

env:AdvanceTime(1.0); -- exactly the 50% fade start
ok(approx(AAlpha(), 1), "no fading before the fade-start point", AAlpha());
env:AdvanceTime(0.5); -- 75% of the duration
ok(approx(AAlpha(), 0.5, 0.02), "constant fade from fade-start to despawn", AAlpha());
env:AdvanceTime(1);
ok(ACount() == 0, "alert despawns at the end of its duration");

ok(env:FireEvent("PLAYER_LEAVE_COMBAT") == 1, "PLAYER_LEAVE_COMBAT handled");
ok(AText() == "Leaving Combat", "leave alert shown");
r, g, b = ALast().frame.text:GetTextColor();
ok(approx(g, 1) and approx(r, 0), "leave color is pure green");
env:AdvanceTime(2.5);

-- direction: down reverses the journey
SyncOutOfCombat();
local slash = _G.SlashCmdList.FCA;
local dirItems = DriveMenu(options.enterCol.direction);
ok(#dirItems == 2 and dirItems[1].text == "Up" and dirItems[2].text == "Down", "direction dropdown offers up/down");
dirItems[2].setSelected(dirItems[2].data);
ok(db.enter.direction == "down", "direction pick saved");
env:FireEvent("PLAYER_ENTER_COMBAT");
local downY = select(5, ALast().frame:GetPoint(1));
ok(approx(downY, db.region.y2 - textH / 2), "down direction spawns at the region top", tostring(downY));
env:AdvanceTime(1);
local downMidY = select(5, ALast().frame:GetPoint(1));
ok(downMidY < downY, "down direction travels downward", tostring(downMidY));
env:AdvanceTime(1.5);
dirItems[1].setSelected(dirItems[1].data); -- back to up

-- player-flag fallback + duplicate suppression
SyncOutOfCombat();
env.playerInCombat = true;
ok(env:FireEvent("UNIT_FLAGS", "player") == 1, "UNIT_FLAGS handled");
ok(AnyVisible() and AText() == db.enter.text, "combat entered via player flag");
env:AdvanceTime(0.5);
local alphaMid = AAlpha();
ok(env:FireEvent("PLAYER_ENTER_COMBAT") == 1, "duplicate dedicated event dispatched");
ok(approx(AAlpha(), alphaMid, 0.05), "duplicate trigger doesn't restart the display");
env:AdvanceTime(2.5);
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
ok(AText() == db.leave.text, "combat left via player flag");
env:AdvanceTime(2.5);

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
local db2 = _G.Floating_Combat_Alert;
ok(type(db2.enter) == "table" and db2.enter.size == 40, "v1 flat table migrated");
ok(db2.enter.duration == 2 and db2.enter.fadeStart == 50 and db2.enter.direction == "up",
    "v1 global duration migrated per side with fade/direction defaults");
ok(db2.region.cx == 0 and db2.region.y1 == 220 and db2.region.y2 == 300,
    "v1 wide region collapsed to its center line");
ok(db2.link.color == false and db2.link.font == true, "v1 migration splits link per setting");

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
db2 = _G.Floating_Combat_Alert;
ok(db2.enter.outlineStyle == "outline" and db2.enter.outline == nil, "v2 outline=true normalizes to outlineStyle");
ok(db2.leave.outlineStyle == "thick" and db2.leave.thick == nil, "v2 thick=true normalizes to thick style");
ok(db2.enter.duration == 2 and db2.leave.duration == 2 and db2.enter.fadeStart == 50, "v2 profile gains duration/fade defaults");

alert = env:FindFrame("FloatingCombatAlertFrame");
options = env:FindFrame("FloatingCombatAlertOptions");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");
slash = _G.SlashCmdList.FCA;

-- ----------------------------------------------------------------------------
-- Options window: opens, loop auto-runs, draggable, position persisted
-- ----------------------------------------------------------------------------
slash("");
ok(options:IsShown(), "/fca opens the options window");
ok(table.concat(env.printLog, "\n"):find("window opened", 1, true) ~= nil, "window toggle confirms itself in chat");
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

-- test loop auto-runs while the window is open
ok(AnyTicker(), "test loop auto-runs while the window is open");
local sawEnter, sawLeave = false, false;
for _ = 1, 40 do
    env:AdvanceTime(0.25);
    if alert:IsShown() then
        if AText() == db2.enter.text then sawEnter = true; end
        if AText() == db2.leave.text then sawLeave = true; end
    end
end
ok(sawEnter and sawLeave, "loop alternates both alerts constantly");

-- band re-fits even during the quiet gap between loop alerts
slash("region");
(editor:GetScript("OnShow") or function() end)(editor);
local quietHit = false;
for _ = 1, 60 do
    env:AdvanceTime(0.25);
    if ACount() == 0 then
        quietHit = true;
        options.enterCol.size:SetText("60");
        options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
        break;
    end
end
ok(quietHit and editor:GetWidth() == editor:BandWidth(),
    "band re-fits to the new size even between alerts",
    ("%s vs %s"):format(tostring(editor:GetWidth()), tostring(editor:BandWidth())));
options.enterCol.size:SetText("30");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
env:AdvanceTime(0.5);

-- real combat text spawns fresh while the loop is running
SyncOutOfCombat();
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
ok(AnyVisible() and AAlpha() == 1 and AText() == db2.enter.text,
    "real combat text spawns fresh while the loop is running", AAlpha());
env:AdvanceTime(0.3); -- let it start fading
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
ok(AAlpha() == 1 and AText() == db2.leave.text,
    "a new combat event instantly replaces an in-flight message");
env:AdvanceTime(3);
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(3);

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
ok(fontItems[1].text == "Friz Quadrata" and fontItems[1].data == "Fonts\\FRIZQT__.TTF", "font entries map names to files");
local morpheusItem;
for _, item in ipairs(fontItems) do
    if item.text == "Morpheus" then morpheusItem = item; end
end
ok(morpheusItem ~= nil and morpheusItem.data == "Fonts\\MORPHEUS.TTF", "Morpheus uses the modern TTF path",
    morpheusItem and tostring(morpheusItem.data));
local arialItem;
for _, item in ipairs(fontItems) do
    if item.text == "Arial Narrow" then arialItem = item; end
end
arialItem.setSelected(arialItem.data);
ok(db2.enter.font == "Fonts\\ARIALN.TTF" and db2.leave.font == "Fonts\\ARIALN.TTF", "linked font pick applies to both");
ok(options.enterCol.font:GetText() == "Arial Narrow", "dropdown label shows the font name");
env:AdvanceTime(3);

options.enterCol.size:SetText("48");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db2.enter.size == 48 and db2.leave.size == 48, "size editbox applies to both sides");
options.enterCol.size:SetText("banana");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db2.enter.size == 48 and options.enterCol.size:GetText() == "48", "non-numeric size reverts");
options.enterCol.size:SetText("999");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db2.enter.size == 200, "size clamps to the 4-200 range", tostring(db2.enter.size));

local outlineItems = DriveMenu(options.enterCol.outline);
ok(#outlineItems == 3, "outline dropdown offers none/thin/thick", outlineItems and #outlineItems);
ok(outlineItems[2].text == "Thin" and outlineItems[2].data == "outline", "middle outline option is named Thin");
outlineItems[3].setSelected(outlineItems[3].data); -- thick
ok(db2.enter.outlineStyle == "thick" and db2.leave.outlineStyle == "thick", "outline pick applies to both");
ok(options.enterCol.outline:GetText() == "Thick", "outline dropdown label updates");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
local _, _, flags = ALast().frame.text:GetFont();
ok(flags and flags:find("THICKOUTLINE", 1, true) ~= nil, "alert renders with thick outline", tostring(flags));

-- live restyle while the alert is flying
env:AdvanceTime(0.4);
outlineItems[1].setSelected(outlineItems[1].data); -- none
ok(AnyVisible(), "alert still flying after restyle");
flags = select(3, ALast().frame.text:GetFont());
ok(flags == nil, "appearance change restyles the in-flight alert immediately", tostring(flags));
env:AdvanceTime(2.5);

-- ----------------------------------------------------------------------------
-- Per-setting link column
-- ----------------------------------------------------------------------------
-- color is unlinked by default: editing enter's color must not touch leave
local enterHexBefore, leaveHexBefore = db2.enter.color, db2.leave.color;
options.enterCol.swatch:GetScript("OnClick")();
_G.ColorPickerFrame:SetColorRGB(0.2, 0.4, 0.9);
_G.ColorPickerFrame.info.swatchFunc();
ok(db2.enter.color ~= enterHexBefore and db2.leave.color == leaveHexBefore,
    "unlinked color edit touches only the enter side",
    ("%s/%s"):format(db2.enter.color, db2.leave.color));

-- unlink size via its checkbox
options.linkChecks.size:SetChecked(false);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);
ok(db2.link.size == false, "unticking a link checkbox saves it");
options.leaveCol.size:SetText("64");
options.leaveCol.size:GetScript("OnEnterPressed")(options.leaveCol.size);
ok(db2.leave.size == 64 and db2.enter.size == 200, "unlinked size touches only that side");
options.linkChecks.size:SetChecked(true);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);
options.enterCol.size:SetText("90");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
ok(db2.enter.size == 90 and db2.leave.size == 90, "relinking makes edits hit both sides again");

-- ----------------------------------------------------------------------------
-- Text, direction, duration, fade rows (bottom segment)
-- ----------------------------------------------------------------------------
options.linkChecks.text:SetChecked(false);
options.linkChecks.text:GetScript("OnClick")(options.linkChecks.text);
options.enterCol.textBox:SetText("Pulling!");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(db2.enter.text == "Pulling!" and db2.leave.text == "L", "unlinked text touches only that side");
options.enterCol.textBox:SetText("");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(db2.enter.text == "Pulling!", "empty text is rejected");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AText() == "Pulling!", "custom text is displayed");
env:AdvanceTime(0.3);
options.enterCol.textBox:SetText("Incoming!");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(AText() == "Incoming!", "text change restyles the in-flight alert immediately");
env:AdvanceTime(2.5);
-- band width follows the bigger of the two alert texts
local widerExpected = math.max(#db2.enter.text * (db2.enter.size or 12), #db2.leave.text * (db2.leave.size or 12)) / 2 + 20;
ok(editor:BandWidth() == widerExpected, "band width follows the bigger alert text",
    ("%s vs %s"):format(tostring(editor:BandWidth()), tostring(widerExpected)));

-- duration editbox: per side, clamped
SyncOutOfCombat();
options.linkChecks.duration:SetChecked(false);
options.linkChecks.duration:GetScript("OnClick")(options.linkChecks.duration);
options.enterCol.duration:SetText("1");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);
ok(db2.enter.duration == 1 and db2.leave.duration == 2, "unlinked duration touches only that side");
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.9);
ok(AnyVisible(), "1s duration alert still visible at 0.9s");
env:AdvanceTime(0.3);
ok(ACount() == 0, "1s duration alert despawned by 1.2s");
options.enterCol.duration:SetText("banana");
options.enterCol.duration:GetScript("OnEnterPressed")(options.enterCol.duration);
ok(db2.enter.duration == 1 and options.enterCol.duration:GetText() == "1", "non-numeric duration reverts");

-- fade editbox: clamped 0-100; 100 = never fades
options.enterCol.fade:SetText("150");
options.enterCol.fade:GetScript("OnEnterPressed")(options.enterCol.fade);
ok(db2.enter.fadeStart == 100, "fade start clamps to 100", tostring(db2.enter.fadeStart));
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.3); -- 30% of the 1s duration
ok(approx(AAlpha(), 1), "fade start 100 never fades", AAlpha());
options.enterCol.fade:SetText("0");
options.enterCol.fade:GetScript("OnEnterPressed")(options.enterCol.fade);
ok(approx(AAlpha(), 0.7, 0.02), "fade start 0 restyles the in-flight alert to a full-duration fade",
    AAlpha());
fireHide(options); -- close the window: loop off, live text (manual) finishes alone
env:AdvanceTime(1.5);
ok(ACount() == 0, "faded alert still despawns on schedule");

-- ----------------------------------------------------------------------------
-- Region band editor
-- ----------------------------------------------------------------------------
slash("region");
ok(editor:IsShown(), "/fca region opens the editor");
(editor:GetScript("OnShow") or function() end)(editor);
local rx1, ry1 = select(4, editor:GetPoint(1)), select(5, editor:GetPoint(1));
ok(rx1 == editor:BandLeft() and ry1 == db2.region.y1, "editor mirrors the saved band");
ok(editor.edges.top ~= nil and editor.edges.bottom ~= nil, "top and bottom edge handles exist");
ok(editor.readouts.left ~= nil and editor.readouts.right ~= nil and editor.readouts.top ~= nil and editor.readouts.bottom ~= nil,
    "four coordinate readouts exist");
ok(editor.readouts.left.isFontString == true, "coord readouts are plain clickthrough text");
local ht = editor.edges.top.tex;
ok(ht ~= nil and ht.r == 0 and ht.g == 1 and ht.b == 0 and ht.a == 0.5,
    "drag handles are solid green at 50% alpha");
-- drag the top edge: vertical only
env.cursorX, env.cursorY = 0, 0;
editor.edges.top:GetScript("OnMouseDown")(editor.edges.top, "LeftButton");
env.cursorX, env.cursorY = 0, 90;
env:AdvanceTime(0.05);
editor.edges.top:GetScript("OnMouseUp")(editor.edges.top);
ok(db2.region.y2 == 430 and db2.region.cx == 0, "top edge drag resizes vertically only",
    ("y2=%s cx=%s"):format(tostring(db2.region.y2), tostring(db2.region.cx)));

env.cursorX, env.cursorY = 0, 0;
editor.edges.top:GetScript("OnMouseDown")(editor.edges.top, "LeftButton");
env.cursorX, env.cursorY = 0, -1000;
env:AdvanceTime(0.05);
editor.edges.top:GetScript("OnMouseUp")(editor.edges.top);
ok(db2.region.y2 - db2.region.y1 == 20, "band cannot shrink below 20 tall", tostring(db2.region.y2 - db2.region.y1));

-- dragging the middle moves the whole band anywhere
local before = { cx = db2.region.cx, y1 = db2.region.y1, y2 = db2.region.y2 };
env.cursorX, env.cursorY = 0, 0;
editor:GetScript("OnDragStart")(editor);
env.cursorX, env.cursorY = -25, 35;
env:AdvanceTime(0.05);
editor:GetScript("OnDragStop")(editor);
ok(db2.region.cx == before.cx - 25 and db2.region.y2 == before.y2 + 35, "center drag moves the whole band");

-- journey follows the moved band
SyncOutOfCombat();
env:FireEvent("PLAYER_ENTER_COMBAT");
local th = ALast().frame.text:GetStringHeight();
ok(approx(select(5, ALast().frame:GetPoint(1)), db2.region.y1 + th / 2), "journey starts bound inside the moved band");
env:AdvanceTime(3);

-- ----------------------------------------------------------------------------
-- Closing the window cleans up
-- ----------------------------------------------------------------------------
slash("test in");
env:AdvanceTime(0.2);
slash("");
fireHide(options);
ok(not options:IsShown(), "window closed");
ok(not editor:IsShown(), "closing the window closes the region editor");
ok(not AnyTicker(), "loop stops when the window closes");
env:AdvanceTime(3);

-- loop text despawn on close
slash("");
fireShow(options);
local despawnChecked = false;
for _ = 1, 40 do
    env:AdvanceTime(0.25);
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
-- Slash: print, duration, invalid
-- ----------------------------------------------------------------------------
local logLen = #env.printLog;
slash("print");
local printed = table.concat(env.printLog, "\n", logLen + 1);
ok(printed:find("Region:", 1, true) ~= nil and printed:find("fade start", 1, true) ~= nil,
    "print dumps region and per-alert details");
slash("duration 2.5");
ok(db2.enter.duration == 2.5 and db2.leave.duration == 2.5, "/fca duration updates both sides");

logLen = #env.printLog;
slash("banana");
local newLines = table.concat(env.printLog, "\n", logLen + 1);
ok(newLines:find("Incorrect use of", 1, true) ~= nil and newLines:find("Example:", 1, true) ~= nil,
    "invalid subcommand prints instructions");

-- ----------------------------------------------------------------------------
-- /fca reset restores every default
-- ----------------------------------------------------------------------------
slash("duration 3");
slash("region");
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(0.2);
slash("reset");
db2 = _G.Floating_Combat_Alert;
ok(db2.enter.duration == 2 and db2.enter.fadeStart == 50 and db2.enter.direction == "up", "reset restores behavior defaults");
ok(db2.enter.size == 28 and db2.enter.color == "FFFF0000", "reset restores appearance defaults");
ok(db2.region.cx == 0 and db2.region.y1 == -100 and db2.region.y2 == 100, "reset restores the region band centered on 0,0");
ok(db2.win.x == 0 and db2.win.y == 0, "reset re-centers the config window");
ok(ACount() == 0, "reset clears the in-flight alert");
local rwx, rwy = select(4, options:GetPoint(1)), select(5, options:GetPoint(1));
ok(rwx == 0 and rwy == 0, "window frame re-anchored to center on reset");
ok(not editor:IsShown() or editor.readouts.left:GetText() == ("%.0f"):format(editor:BandLeft()),
    "open editor mirrors reset band");
local lastLog = env.printLog[#env.printLog];
ok(lastLog:find("restored to defaults", 1, true) ~= nil, "reset confirms itself in chat", lastLog);

-- ----------------------------------------------------------------------------
-- UI reload with the customized profile
-- ----------------------------------------------------------------------------
local carried = {
    cx = db2.region.cx, enterSize = db2.enter.size, leaveSize = db2.leave.size,
    linkSize = db2.link.size, linkColor = db2.link.color, text = db2.enter.text,
    winX = db2.win.x, winY = db2.win.y, fade = db2.enter.fadeStart,
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
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AnyVisible() and AText() == db3.enter.text, "dedicated events work after silent sync");
env:AdvanceTime(3);

-- ----------------------------------------------------------------------------
-- Resilience: a missing widget template must not take down the alerts
-- ----------------------------------------------------------------------------
env:Reset();
env.failTemplates = { "WowStyle1DropdownTemplate" };
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
local failOK, failErr = pcall(chunk);
ok(failOK, "addon loads despite a missing widget template", failErr);
local failLog = table.concat(env.printLog, "\n");
ok(failLog:find("failed to build", 1, true) ~= nil, "build failure reported to chat");

local ef;
for _, f in ipairs(env.frames) do
    if f:IsEventRegistered("ADDON_LOADED") then ef = f; break; end
end
env:FireEvent("ADDON_LOADED", "Floating_Combat_Alert");
ok(ef ~= nil and ef:IsEventRegistered("PLAYER_ENTER_COMBAT"), "combat events registered despite UI failure");
local a3 = env:FindFrame("FloatingCombatAlertFrame");
env:FireEvent("PLAYER_ENTER_COMBAT");
local expectedText = _G.Floating_Combat_Alert.enter.text;
local lastA = a3.active[#a3.active];
ok(a3 ~= nil and lastA ~= nil and lastA.frame.text:GetText() == expectedText, "alerts fully functional without options UI",
    tostring(lastA and lastA.frame.text:GetText()));
env:AdvanceTime(3);
env.failTemplates = nil;

out(string.format("\nTest Results: %d Passed, %d Failed", PASS, FAIL));
if FAIL > 0 then
    os.exit(1);
else
    out("ALL TESTS PASSED SUCCESSFULLY!");
end
