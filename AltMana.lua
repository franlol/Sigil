-------------------------------------------------------------------------------
-- Sigil - Druid mana: while a druid is in bear or cat form (rage or energy),
-- a thin bar keeps showing the mana. Player frame only.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

local function Build(f)
    local a = CreateFrame("Frame", nil, f, "BackdropTemplate")
    a.bar = CreateFrame("StatusBar", nil, a)
    a.bar.bg = a.bar:CreateTexture(nil, "BACKGROUND")
    a.bar.bg:SetAllPoints()
    a.text = a.bar:CreateFontString(nil, "OVERLAY")
    a.text:SetPoint("CENTER")
    return a
end

function ns.LayoutAltMana(f)
    local c = f.cfg.altMana
    local _, class = UnitClass("player")
    f.altManaClass = class == "DRUID"
    if f.unit ~= "player" or not c or not c.enabled then
        if f.altMana then f.altMana:Hide() end
        f.altManaOn = false
        return
    end
    f.altManaOn = true
    local a = f.altMana or Build(f)
    f.altMana = a
    ns.PlacePiece(f, "altMana", L["Druid mana"], a, c)
    a:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, c.height)
    ns.StyleBox(a, c.style, a.bar)
    ns.StyleBar(a.bar, c.style)
    ns.PaintBar(a.bar, c.style, ns.PowerRGB("MANA"))
    ns.StyleText(a.text, c.textStyle, math.max(8, math.floor(c.height * 0.8)))
    a.text:SetShown(c.text and true or false)
end

function ns.UpdateAltMana(f)
    local a = f.altMana
    if not a or not f.altManaOn then return end
    -- druids only, also in test mode
    if not f.altManaClass then return a:Hide() end
    if ns.testMode then
        a.bar:SetMinMaxValues(0, 100)
        a.bar:SetValue(60)
        a.text:SetText("600")
        a:Show()
        return
    end
    -- only when the shown power is not mana (shapeshifted)
    local ptype = R(UnitPowerType("player"))
    if ptype == nil or ptype == MANA then
        a:Hide()
        return
    end
    -- secret values cannot be tested with "and/or": only plain ones get a fallback
    local cur, max = UnitPower("player", MANA), UnitPowerMax("player", MANA)
    if not S(max) then max = max or 1 end
    if not S(cur) then cur = cur or 0 end
    a.bar:SetMinMaxValues(0, max)
    a.bar:SetValue(cur)
    if a.text:IsShown() then
        if AbbreviateNumbers then a.text:SetText(AbbreviateNumbers(cur)) else a.text:SetText(cur) end
    end
    a:Show()
end

for _, ev in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UPDATE_SHAPESHIFT_FORM" }) do
    ns.On(ev, function(f) if f.unit == "player" then ns.UpdateAltMana(f) end end)
end
