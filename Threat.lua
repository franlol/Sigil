-------------------------------------------------------------------------------
-- Sigil - Threat: a colored border around the frame
--   player frame: your highest threat on any enemy
--   other frames: your threat on that unit
-- Colors: Colors page (the game's yellow, orange, red by default). Hidden
-- without threat.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

local FLAT = "Interface\\Buttons\\WHITE8X8"

function ns.LayoutThreat(f)
    ns.LayoutThreatBar(f)
    local c = f.cfg.threat
    if not c or not c.enabled then
        if f.threat then f.threat:Hide() end
        return
    end
    local t = f.threat
    if not t then
        t = CreateFrame("Frame", nil, f, "BackdropTemplate")
        t:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
        f.threat = t
    end
    local w = c.width or 2
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", -w, w)
    t:SetPoint("BOTTOMRIGHT", w, -w)
    t:SetBackdrop({ edgeFile = FLAT, edgeSize = w })
    t:Hide()
end

-- Color of a threat status 1-3 (Colors page: Threat)
local THREAT_KEYS = { "high", "insecure", "tanking" }
function ns.ThreatRGB(status)
    local c = ns.Color("threat", THREAT_KEYS[status])
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Threat status 0-3 (nil if none or hidden by the game)
local function Status(f)
    if f.unit == "player" then return R(UnitThreatSituation("player")) end
    if not R(UnitCanAttack("player", f.unit)) then return nil end
    return R(UnitThreatSituation("player", f.unit))
end

function ns.UpdateThreat(f)
    ns.UpdateThreatBar(f)
    local t = f.threat
    if not t or not f.cfg.threat or not f.cfg.threat.enabled then return end
    local status
    if ns.Fake(f.unit) or (ns.testMode and f.unit == "target") then
        status = 3 -- test mode: tanking
    else
        status = Status(f)
    end
    if status and status > 0 then
        t:SetBackdropBorderColor(ns.ThreatRGB(status))
        t:Show()
    else
        t:Hide()
    end
end

-------------------------------------------------------------------------------
-- Threat bar: your threat on the unit (0-100 %), in the threat status color
-- unless the bar look says otherwise. Hidden without threat.
-------------------------------------------------------------------------------
function ns.LayoutThreatBar(f)
    local c = f.cfg.threatBar
    if not c or not c.enabled or f.unit == "player" then
        if f.threatBar then f.threatBar:Hide() end
        return
    end
    local b = f.threatBar
    if not b then
        b = CreateFrame("Frame", nil, f, "BackdropTemplate")
        b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        b:SetBackdropColor(0, 0, 0, 0.6)
        b:SetBackdropBorderColor(0, 0, 0, 1)
        b.bar = CreateFrame("StatusBar", nil, b)
        b.bar:SetPoint("TOPLEFT", 1, -1)
        b.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        b.bar:SetMinMaxValues(0, 100)
        b.bar.bg = b.bar:CreateTexture(nil, "BACKGROUND")
        b.bar.bg:SetAllPoints()
        b.text = b.bar:CreateFontString(nil, "OVERLAY")
        b.text:SetPoint("CENTER")
        f.threatBar = b
    end
    ns.PlacePiece(f, "threatBar", L["Threat bar"], b, c)
    b:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, c.height)
    ns.StyleBar(b.bar, c.style)
    ns.StyleText(b.text, c.textStyle, math.max(8, math.floor(c.height * 0.8)))
    b.text:SetShown(c.text and true or false)
    b:Hide()
end

function ns.UpdateThreatBar(f)
    local b = f.threatBar
    local c = f.cfg.threatBar
    if not b or not c or not c.enabled or f.unit == "player" then return end
    local status, pct
    if ns.Fake(f.unit) or ns.testMode then
        status, pct = 3, 75 -- test mode: tanking
    elseif R(UnitCanAttack("player", f.unit)) then
        local _, st, scaled = UnitDetailedThreatSituation("player", f.unit)
        status, pct = R(st), R(scaled)
    end
    if not status or not pct then
        b:Hide()
        return
    end
    local r, g, bl = ns.ThreatRGB(status)
    ns.PaintBar(b.bar, c.style, r, g, bl)
    b.bar:SetValue(pct)
    b.text:SetFormattedText("%d%%", pct)
    b:Show()
end

-- Threat percentage on a unit, for the texts (nil without threat)
function ns.textHelpers.Threat(u)
    if ns.Fake(u) then return 75 end
    local _, _, pct = UnitDetailedThreatSituation("player", u)
    if S(pct) then return pct end
    if not pct then return nil end
    return math.floor(pct + 0.5)
end

ns.On("UNIT_THREAT_SITUATION_UPDATE", function(f) ns.UpdateThreat(f) end)
ns.On("UNIT_THREAT_LIST_UPDATE", function(f) ns.UpdateThreat(f) end)
