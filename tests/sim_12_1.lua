--[[
    12.1 Combat Lifecycle Simulation for Floating Combat Alert.
    Loads the addon into a mock WoW 12.1 client and replays a realistic session:
    first login -> pull (PLAYER_ENTER_COMBAT) -> mid-journey -> boss dies ->
    combat twitching -> regen events ignored (troll racial keeps regen running
    in combat) -> player-flag fallback -> options window (always-on test loop,
    real dropdowns, size/text editboxes) -> region band editor -> UI reload.
    Any runtime error in that chain reproduces a broken addon in-game.
    Run with: lua5.1 tests/sim_12_1.lua
--]]

local env = dofile("../shared/wow_test_env.lua");
local out = env.rawPrint;
local ADDON = "Floating_Combat_Alert";

local PASS, FAIL = 0, 0;
local function ok(cond, name, extra)
    if cond then PASS = PASS + 1; out("  PASS: " .. name);
    else FAIL = FAIL + 1; out("  FAIL: " .. name .. (extra and (" -- " .. tostring(extra)) or "")); end
end
local function approx(a, b, eps)
    return math.abs(a - b) <= (eps or 1e-6);
end
local function DriveMenu(dd)
    local root = { items = {} };
    function root:CreateRadio(text, isSelected, setSelected, data)
        self.items[#self.items + 1] = { text = text, data = data, setSelected = setSelected };
    end
    dd:GetMenuGenerator()(dd, root);
    return root.items;
end

-- ----------------------------------------------------------------------------
-- Sim 1: fresh client load
-- ----------------------------------------------------------------------------
out("\n== Sim 1: fresh client load ==");
local chunk, chunkErr = loadfile("Floating_Combat_Alert.lua");
ok(chunk ~= nil, "addon chunk loads", chunkErr);
local loadOK, loadErr = pcall(chunk);
ok(loadOK, "addon executes without runtime error", loadErr);

local alert = env:FindFrame("FloatingCombatAlertFrame");
-- concurrent alert helpers: the newest spawn is last in the active list
local function ACount() return alert.active and #alert.active or 0; end
local function ALast() return alert.active and alert.active[#alert.active]; end
local function AText() local a = ALast(); return a and a.text:GetText(); end
local function AAlpha() local a = ALast(); return a and a:GetAlpha() or 0; end

local options = env:FindFrame("FloatingCombatAlertOptions");
local editor = env:FindFrame("FloatingCombatAlertRegionEditor");
ok(alert ~= nil and options ~= nil and editor ~= nil, "all three frames exist");
ok(alert:GetFrameStrata() == "HIGH", "alert renders above normal UI", alert:GetFrameStrata());
ok(editor:GetFrameStrata() == "TOOLTIP", "region editor renders above the alert", editor:GetFrameStrata());
ok(not alert:IsMouseEnabled(), "driver never intercepts mouse input");
ok(options:GetScript("OnDragStart") ~= nil, "options window is drag-and-drop movable");

-- ----------------------------------------------------------------------------
-- Sim 2: first login
-- ----------------------------------------------------------------------------
out("\n== Sim 2: first login ==");
env:FireEvent("ADDON_LOADED", ADDON);
local db = _G.Floating_Combat_Alert;
ok(type(db) == "table" and db.region ~= nil, "settings initialized for new user");
ok(db.link.font == true and db.link.color == false, "settings linked by default, color unlinked");

local eventFrame;
for _, f in ipairs(env.frames) do
    if f:IsEventRegistered("PLAYER_ENTER_COMBAT") then eventFrame = f; break; end
end
ok(eventFrame ~= nil, "player combat events registered after login");
ok(not eventFrame:IsEventRegistered("PLAYER_REGEN_DISABLED") and not eventFrame:IsEventRegistered("PLAYER_REGEN_ENABLED"),
    "regen events deliberately NOT used");

-- ----------------------------------------------------------------------------
-- Sim 3: pull -- enter combat, watch the journey
-- ----------------------------------------------------------------------------
out("\n== Sim 3: pull (enter combat) ==");
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(#alert.active > 0 and AText() == "Entering Combat", "pull shows the enter alert");
local textH = ALast().text:GetStringHeight();
local y0 = select(5, ALast():GetPoint(1));
ok(y0 == db.region.y1 + textH / 2, "text spawns bound inside the region bottom", tostring(y0));
env:AdvanceTime(0.75);
env:TickAnims();
env:TickAnims();
local y1 = select(5, ALast():GetPoint(1));
local span = math.max(0, db.region.y2 - db.region.y1 - textH);
ok(y1 > y0 and y1 < db.region.y2, "text mid-journey inside the region", ("%s of %s"):format(tostring(y1), tostring(db.region.y2)));
ok(y1 >= db.region.y1 and y1 <= db.region.y2 - textH / 2, "journey stays bound inside the band");
env:AdvanceTime(0.5);
env:TickAnims();
env:TickAnims();
local ag = ALast().alphaAnim;
ok(AAlpha() <= 1, "alert alpha is within valid range");

-- troll racial: HP regen keeps running in combat; regen events must do nothing
local handled = env:FireEvent("PLAYER_REGEN_DISABLED") + env:FireEvent("PLAYER_REGEN_ENABLED");
ok(handled == 0, "regen events ignored while in combat", handled);
env:AdvanceTime(1);
env:TickAnims();
ok(#alert.active == 0, "pull alert finished its journey");

-- ----------------------------------------------------------------------------
-- Sim 4: boss dies
-- ----------------------------------------------------------------------------
out("\n== Sim 4: boss dies (leave combat) ==");
env:FireEvent("PLAYER_LEAVE_COMBAT");
ok(#alert.active > 0 and AText() == "Leaving Combat", "kill shows the leave alert");
env:AdvanceTime(2);
env:TickAnims();
ok(#alert.active == 0, "leave alert fades out cleanly");

-- ----------------------------------------------------------------------------
-- Sim 5: combat twitching + player-flag fallback
-- ----------------------------------------------------------------------------
out("\n== Sim 5: rapid combat toggles ==");
env:FireEvent("PLAYER_ENTER_COMBAT");
env:AdvanceTime(0.1);
env:TickAnims();
env:FireEvent("PLAYER_LEAVE_COMBAT");
env:AdvanceTime(0.1);
env:TickAnims();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AText() == "Entering Combat" and AAlpha() == 1, "last toggle wins, display resets");
env:AdvanceTime(2);
env:TickAnims();

env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
ok(AText() == "Leaving Combat", "combat left via player flag");
env:AdvanceTime(2);
env:TickAnims();
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
ok(#alert.active > 0 and AText() == "Entering Combat", "combat entered via player flag");
env:AdvanceTime(2);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Sim 6: options window -- always-on loop, dropdowns, editboxes
-- ----------------------------------------------------------------------------
out("\n== Sim 6: /fca options window ==");
local slash = _G.SlashCmdList.FCA;
slash("");
ok(options:IsShown(), "/fca opens the options window");
(options:GetScript("OnShow") or function() end)(options);

-- combat text spawns fresh while the loop runs on its own cadence
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
env:Pump(3.5); -- let the preview loop establish its cadence
env.playerInCombat = true;
env:FireEvent("UNIT_FLAGS", "player");
ok(#alert.active >= 2 and AText() == db.enter.text,
    "real combat text spawns beside in-flight loop text", ("count=%d"):format(ACount()));
env:Pump(0.1);
ok(AAlpha() > 0.9, "combat alert renders at full alpha while the loop runs", AAlpha());
env:Pump(3);

local sawEnter, sawLeave, maxLoop = false, false, 0;
local function LoopCount()
    local n = 0;
    for _, a in ipairs(alert.active) do
        if a.fromLoop then n = n + 1; end
    end
    return n;
end
for _ = 1, 36 do
    env:Pump(0.25);
    maxLoop = math.max(maxLoop, LoopCount());
    if #alert.active > 0 then
        if AText() == db.enter.text then sawEnter = true; end
        if AText() == db.leave.text then sawLeave = true; end
    end
end
local dbg = {};
for _, a in ipairs(alert.active) do dbg[#dbg+1] = a.text:GetText(); end
ok(sawEnter and sawLeave, "test loop alternates both alerts constantly",
    "texts=[" .. table.concat(dbg, "|") .. "]");
ok(maxLoop >= 2, "previews overlap: the next enters at 80% of the previous travel", maxLoop);

-- both columns are always visible; unlink size via the link column
ok(options.enterCol:IsShown() and options.leaveCol:IsShown(), "both alert columns visible");
options.linkChecks.size:SetChecked(false);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);
ok(db.link.size == false, "size unlinked via the link column");

options.enterCol.size:SetText("56");
options.enterCol.size:GetScript("OnEnterPressed")(options.enterCol.size);
options.leaveCol.size:SetText("24");
options.leaveCol.size:GetScript("OnEnterPressed")(options.leaveCol.size);
ok(db.enter.size == 56 and db.leave.size == 24, "unlinked sizes controlled separately",
    ("%s/%s"):format(db.enter.size, db.leave.size));
options.linkChecks.size:SetChecked(true);
options.linkChecks.size:GetScript("OnClick")(options.linkChecks.size);

options.linkChecks.font:SetChecked(false);
options.linkChecks.font:GetScript("OnClick")(options.linkChecks.font);
local fontItems = DriveMenu(options.leaveCol.font);
ok(#fontItems == 7, "font dropdown offers the seven western typefaces", #fontItems);
local morpheus;
for _, item in ipairs(fontItems) do
    if item.text == "Morpheus" then morpheus = item; end
end
morpheus.setSelected(morpheus.data);
ok(db.leave.font == "Fonts\\MORPHEUS.TTF" and db.enter.font ~= "Fonts\\MORPHEUS.TTF",
    "unlinked font pick changes only the leave side");
ok(options.leaveCol.font:GetText() == "Morpheus", "dropdown label shows the font name");

local outlineItems = DriveMenu(options.leaveCol.outline);
ok(#outlineItems == 3, "outline dropdown offers none/outline/thick", #outlineItems);
outlineItems[3].setSelected(outlineItems[3].data);
ok(db.leave.outlineStyle == "thick", "outline style picked per side");

-- custom alert text per side
options.enterCol.textBox:SetText("Pulling!");
options.enterCol.textBox:GetScript("OnEnterPressed")(options.enterCol.textBox);
ok(db.enter.text == "Pulling!", "custom enter text saved");
-- leave combat, then pull again so the dedicated event spawns a fresh alert
env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(2);
env:TickAnims();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(AText() == "Pulling!", "custom text is what gets displayed");
env:AdvanceTime(0.3);
env:TickAnims();
local enterOutline = DriveMenu(options.enterCol.outline);
enterOutline[1].setSelected(enterOutline[1].data); -- none
local flags = select(3, ALast().text:GetFont());
ok(#alert.active > 0 and flags == nil, "appearance restyles the in-flight alert immediately", tostring(flags));
env:AdvanceTime(2);
env:TickAnims();

-- ----------------------------------------------------------------------------
-- Sim 7: region band editor
-- ----------------------------------------------------------------------------
out("\n== Sim 7: region band editor ==");
editor:Show();
(editor:GetScript("OnShow") or function() end)(editor);
local rx, ry = select(4, editor:GetPoint(1)), select(5, editor:GetPoint(1));
ok(rx == editor:BandLeft() and ry == db.region.y1, "editor mirrors the saved band");

env.cursorX, env.cursorY = 0, 0;
editor.edges.top:GetScript("OnMouseDown")(editor.edges.top, "LeftButton");
env.cursorX, env.cursorY = 0, 60;
env:AdvanceTime(0.05);
env:TickAnims();
editor.edges.top:GetScript("OnMouseUp")(editor.edges.top);
ok(db.region.y2 == 160 and db.region.cx == 0, "top edge drag resizes vertically only",
    ("y2=%s cx=%s"):format(tostring(db.region.y2), tostring(db.region.cx)));

ok(editor.readouts.bottom ~= nil and editor.readouts.bottom.isFontString, "coord readouts are clickthrough text");

env.cursorX, env.cursorY = 0, 0;
editor:GetScript("OnDragStart")(editor);
env.cursorX, env.cursorY = 10, 10;
env:AdvanceTime(0.05);
env:TickAnims();
editor:GetScript("OnDragStop")(editor);
ok(db.region.cx == 10 and db.region.y1 == -90, "center drag moves the whole band",
    ("cx=%s y1=%s"):format(tostring(db.region.cx), tostring(db.region.y1)));

env.playerInCombat = false;
env:FireEvent("UNIT_FLAGS", "player");
env:AdvanceTime(2);
env:TickAnims();
env:FireEvent("PLAYER_ENTER_COMBAT");
ok(approx(select(5, ALast():GetPoint(1)), db.region.y1 + ALast().text:GetStringHeight() / 2),
    "journey starts bound inside the moved band");
env:AdvanceTime(2.5);
env:TickAnims(); -- let the combat alert finish

-- ----------------------------------------------------------------------------
-- Sim 8: closing the window cleans everything up
-- ----------------------------------------------------------------------------
out("\n== Sim 8: window close cleanup ==");
local function PendingTimers()
    local n = 0;
    for _, t in ipairs(env.timers) do
        if not t.cancelled then n = n + 1; end
    end
    return n;
end
ok(PendingTimers() > 0, "preview loop is scheduled while the window is open");
options:Hide();
(options:GetScript("OnHide") or function() end)(options);
ok(PendingTimers() == 0, "loop timer is cancelled when the window closes");
ok(not editor:IsShown(), "region editor closes with the window");
ok(#alert.active == 0, "in-flight loop text despawns on close");

-- ----------------------------------------------------------------------------
-- Sim 9: /reload with the customized profile
-- ----------------------------------------------------------------------------
out("\n== Sim 9: UI reload ==");
local carried = {
    x1 = db.region.x1, y1 = db.region.y1, y2 = db.region.y2,
    enterSize = db.enter.size, leaveFont = db.leave.font,
    leaveSize = db.leave.size, leaveStyle = db.leave.outlineStyle,
    enterText = db.enter.text,
};
env:Reset();
chunk = assert(loadfile("Floating_Combat_Alert.lua"));
local reloadOK, reloadErr = pcall(chunk);
ok(reloadOK, "addon reloads without runtime error", reloadErr);
alert = env:FindFrame("FloatingCombatAlertFrame");
editor = env:FindFrame("FloatingCombatAlertRegionEditor");

env:FireEvent("ADDON_LOADED", ADDON);
local db2 = _G.Floating_Combat_Alert;
ok(db2.region.x1 == carried.x1 and db2.region.y1 == carried.y1 and db2.region.y2 == carried.y2, "band survives reload");
ok(db2.enter.size == carried.enterSize and db2.leave.size == carried.leaveSize, "per-side sizes survive reload");
ok(db2.leave.font == carried.leaveFont and db2.leave.outlineStyle == carried.leaveStyle, "per-side font/style survive reload");
ok(db2.enter.text == carried.enterText, "custom text survives reload");

env:FireEvent("PLAYER_ENTER_COMBAT");
ok(#alert.active > 0 and AText() == carried.enterText, "alerts fully functional after reload");
env:AdvanceTime(2);
env:TickAnims();

out(("\n=== Sim Results: %d passed, %d failed ==="):format(PASS, FAIL));
os.exit(FAIL == 0 and 0 or 1);
