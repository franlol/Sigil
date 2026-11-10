-------------------------------------------------------------------------------
-- Sigil - Experience / reputation bar (player frame)
--   xp:   experience, with the rested part in another color
--   rep:  the reputation you watch in the reputation panel
--   auto: experience until max level, then reputation
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local XP_COLOR = { 0.58, 0.3, 0.85 }
local RESTED_COLOR = { 0.25, 0.45, 0.9 }

local function AtMaxLevel()
    local max = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    return UnitLevel("player") >= max
end

local function Watched()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local d = C_Reputation.GetWatchedFactionData()
        if d and d.name then
            return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
        end
    end
end

local function Build(f)
    local x = CreateFrame("Frame", nil, f, "BackdropTemplate")
    x.rested = CreateFrame("StatusBar", nil, x)
    x.bar = CreateFrame("StatusBar", nil, x)
    x.bar:SetAllPoints(x.rested)
    x.bar:SetFrameLevel(x.rested:GetFrameLevel() + 1)
    x.text = x.bar:CreateFontString(nil, "OVERLAY")
    x.text:SetPoint("CENTER")
    x:EnableMouse(true)
    x:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(self.tip, 1, 1, 1)
        GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return x
end

function ns.LayoutExperience(f)
    local c = f.cfg.xp
    if not c or not c.enabled then
        if f.xp then f.xp:Hide() end
        return
    end
    local x = f.xp or Build(f)
    f.xp = x
    x:ClearAllPoints()
    ns.PlacePiece(f, "xp", L["Experience / reputation"], x, c)
    x:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, c.height)
    x.bar.bg = x.bar.bg or x.rested:CreateTexture(nil, "BACKGROUND")
    x.bar.bg:SetAllPoints(x.rested)
    ns.StyleBox(x, c.style, x.rested)
    ns.StyleBar(x.bar, c.style)
    ns.StyleBar(x.rested, c.style)
    ns.StyleText(x.text, c.textStyle, math.max(8, math.floor(c.height * 0.75)))
    x:Show()
    ns.UpdateExperience(f)
end

local function Short(n)
    if AbbreviateNumbers then return AbbreviateNumbers(n) end
    return tostring(n)
end

function ns.UpdateExperience(f)
    local x = f.xp
    local c = f.cfg.xp
    if not x or not c or not c.enabled then return end
    if ns.testMode then
        x.bar:SetMinMaxValues(0, 100)
        x.bar:SetValue(60)
        ns.PaintBar(x.bar, c.style, unpack(XP_COLOR))
        x.rested:SetMinMaxValues(0, 100)
        x.rested:SetValue(75)
        x.rested:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], 0.5)
        x.rested:Show()
        x.text:SetText(c.text and "6000 / 10000 (60%)" or "")
        x.tip = nil
        x:Show()
        return
    end
    local mode = c.mode or "auto"
    if mode == "auto" then mode = AtMaxLevel() and "rep" or "xp" end

    if mode == "xp" then
        local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
        local rested = GetXPExhaustion and GetXPExhaustion() or 0
        if max <= 0 then max = 1 end
        x.bar:SetMinMaxValues(0, max)
        x.bar:SetValue(cur)
        ns.PaintBar(x.bar, c.style, unpack(XP_COLOR))
        x.rested:SetMinMaxValues(0, max)
        x.rested:SetValue(math.min(max, cur + (rested or 0)))
        x.rested:SetStatusBarColor(RESTED_COLOR[1], RESTED_COLOR[2], RESTED_COLOR[3], 0.5)
        x.rested:Show()
        local pct = math.floor(cur / max * 100)
        x.text:SetText(c.text and ("%s / %s (%d%%)"):format(Short(cur), Short(max), pct) or "")
        x.tip = L["Experience"] .. ": " .. cur .. " / " .. max
            .. ((rested and rested > 0) and ("\n" .. L["Rested"] .. ": " .. rested) or "")
        x:Show()
        return
    end

    local name, reaction, low, high, standing = Watched()
    if not name then
        x:Hide()
        return
    end
    local span = math.max(1, (high or 1) - (low or 0))
    local value = (standing or 0) - (low or 0)
    x.bar:SetMinMaxValues(0, span)
    x.bar:SetValue(value)
    local col = nil
    if col then ns.PaintBar(x.bar, c.style, col.r, col.g, col.b) else ns.PaintBar(x.bar, c.style, ns.ReactionRGB(reaction)) end
    x.rested:Hide()
    x.text:SetText(c.text and ("%s: %s / %s"):format(name, Short(value), Short(span)) or "")
    x.tip = name .. ": " .. value .. " / " .. span
    x:Show()
end

-- Player events: one watcher, it updates the player frame
local watcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "PLAYER_UPDATE_RESTING" }) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(ev) then watcher:RegisterEvent(ev) end
end
watcher:SetScript("OnEvent", function()
    local f = ns.frames and ns.frames.player
    if f then ns.UpdateExperience(f) end
end)
