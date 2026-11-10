-------------------------------------------------------------------------------
-- Sigil - Combo points (rogues and druids), on the target frame
--
-- Drawn as one bar split in 5 segments: a StatusBar accepts the value even
-- when the game hides it as secret, so no comparison is needed.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MAX = 5
local CLASSES = { ROGUE = true, DRUID = true }

local function Points()
    if GetComboPoints then return GetComboPoints("player", "target") end
    return 0
end

function ns.LayoutCombo(f)
    local c = f.cfg.combo
    local _, class = UnitClass("player")
    f.comboClass = CLASSES[class] and true or false
    if not c or not c.enabled then
        if f.combo then f.combo:Hide() end
        f.comboOn = false
        return
    end
    f.comboOn = true
    local cp = f.combo
    if not cp then
        cp = CreateFrame("Frame", nil, f, "BackdropTemplate")
        cp.bar = CreateFrame("StatusBar", nil, cp)
        cp.bar:SetStatusBarTexture(FLAT)
        cp.bar:SetMinMaxValues(0, MAX)
        cp.dividers = {}
        for i = 1, MAX - 1 do
            local d = cp.bar:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(0, 0, 0, 1)
            d:SetWidth(1)
            cp.dividers[i] = d
        end
        f.combo = cp
    end
    cp:ClearAllPoints()
    ns.PlacePiece(f, "combo", L["Combo points"], cp, c)
    local w = c.width and c.width > 0 and c.width or f.cfg.width
    cp:SetSize(w, c.height)
    local edge = ns.StyleBox(cp, c.style, cp.bar)
    local inner = w - 2 * edge
    for i, d in ipairs(cp.dividers) do
        d:ClearAllPoints()
        d:SetPoint("TOP", cp.bar, "TOPLEFT", inner * i / MAX, 0)
        d:SetPoint("BOTTOM", cp.bar, "BOTTOMLEFT", inner * i / MAX, 0)
    end
    cp.bar.bg = cp.bar.bg or cp.bar:CreateTexture(nil, "BACKGROUND")
    cp.bar.bg:SetAllPoints()
    ns.StyleBar(cp.bar, c.style)
    ns.PaintBar(cp.bar, c.style, 1, 0.8, 0.1)
end

function ns.UpdateCombo(f)
    local cp = f.combo
    if not cp or not f.comboOn then return end
    -- only for the classes that use them, also in test mode
    if not f.comboClass then return cp:Hide() end
    if ns.Fake(f.unit) or ns.testMode then
        cp.bar:SetValue(3)
        cp:Show()
        return
    end
    if not UnitExists("target") then return cp:Hide() end
    local n = Points()
    cp.bar:SetValue(n)
    -- hidden with 0 points, when the game lets us know it
    if S(n) then cp:Show() else cp:SetShown((n or 0) > 0) end
end

-- Combo points change with the player's power events, not the target's
local watcher = CreateFrame("Frame")
for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "PLAYER_COMBO_POINTS", "UNIT_POWER_UPDATE" }) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(ev) then
        if ev:find("^UNIT_") then watcher:RegisterUnitEvent(ev, "player") else watcher:RegisterEvent(ev) end
    end
end
watcher:SetScript("OnEvent", function()
    local f = ns.frames and ns.frames.target
    if f and f:IsShown() then ns.UpdateCombo(f) end
end)
