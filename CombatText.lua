-------------------------------------------------------------------------------
-- Sigil - Combat text on the frame: damage taken, heals received, misses...
-- The game sends the amount as a secret value: it can be shown, not compared.
-- Each hit shows for `duration` seconds and fades out.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

-- Colors by kind of event
local COLORS = {
    WOUND = { 1, 0.25, 0.25 },
    HEAL = { 0.3, 1, 0.4 },
    ENERGIZE = { 0.4, 0.6, 1 },
    BLOCK = { 1, 1, 1 },
}

local function OnUpdate(fs, elapsed)
    fs.left = fs.left - elapsed
    if fs.left <= 0 then
        fs:Hide()
        fs.holder:SetScript("OnUpdate", nil)
        return
    end
    -- full for the first half, then fades
    fs:SetAlpha(math.min(1, fs.left / (fs.total * 0.5)))
end

function ns.LayoutCombatText(f)
    local c = f.cfg.combatText
    if not c or not c.enabled then
        if f.ctext then f.ctext:Hide() end
        return
    end
    if not f.ctext then
        local holder = CreateFrame("Frame", nil, f.overlay)
        holder:SetAllPoints()
        holder:SetFrameLevel(f.overlay:GetFrameLevel() + 4)
        f.ctext = holder:CreateFontString(nil, "OVERLAY")
        f.ctext.holder = holder
        f.ctext:Hide()
    end
    ns.Place(f.ctext, f, c)
    ns.StyleText(f.ctext, c.textStyle, 16)
    if ns.TestCombatText then ns.TestCombatText(f) end
end

local function Show(f, text, color, big)
    local c = f.cfg.combatText
    local fs = f.ctext
    if not fs or not c or not c.enabled then return end
    ns.StyleText(fs, c.textStyle, 16)
    if big then
        local font, size, flags = fs:GetFont()
        if font then fs:SetFont(font, math.floor(size * 1.35), flags) end
    end
    fs:SetText(text)
    if c.textStyle.colorMode ~= "custom" and color then fs:SetTextColor(color[1], color[2], color[3]) end
    fs.total = c.duration or 1.5
    fs.left = fs.total
    fs:SetAlpha(1)
    fs:Show()
    fs.holder:SetScript("OnUpdate", function(_, elapsed) OnUpdate(fs, elapsed) end)
end

local function Amount(n)
    if AbbreviateNumbers then return AbbreviateNumbers(n) end
    return n
end

-- UNIT_COMBAT: unit, event, flagText, amount (secret), schoolMask
ns.On("UNIT_COMBAT", function(f, _, event, flag, amount)
    event, flag = R(event), R(flag)
    if not event then return end
    local crit = flag == "CRITICAL" or flag == "CRUSHING"
    if event == "WOUND" then
        if not S(amount) and (amount or 0) == 0 then
            if flag and _G[flag] then Show(f, _G[flag], COLORS.BLOCK) end
            return
        end
        Show(f, "-" .. Amount(amount), COLORS.WOUND, crit)
    elseif event == "HEAL" then
        Show(f, "+" .. Amount(amount), COLORS.HEAL, crit)
    elseif event == "ENERGIZE" then
        Show(f, "+" .. Amount(amount), COLORS.ENERGIZE)
    elseif _G[event] then
        -- MISS, DODGE, PARRY, BLOCK, RESIST, ABSORB, IMMUNE, EVADE...: the game's own words
        Show(f, _G[event], COLORS.BLOCK)
    end
end)

-- Test mode: a sample hit that stays until test mode ends
function ns.TestCombatText(f)
    local fs = f.ctext
    if not fs then return end
    if ns.testMode and f.cfg.combatText and f.cfg.combatText.enabled then
        Show(f, "-1.2K", COLORS.WOUND, false)
        fs.holder:SetScript("OnUpdate", nil)
        fs:SetAlpha(1)
    elseif fs.holder:GetScript("OnUpdate") == nil then
        fs:Hide()
    end
end
