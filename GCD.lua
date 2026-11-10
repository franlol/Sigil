-------------------------------------------------------------------------------
-- Sigil - Global cooldown: a thin bar on the player frame that empties while
-- the global cooldown runs. Read from the game's global cooldown spell; if
-- the times are hidden, the game moves the bar with its duration object.
-------------------------------------------------------------------------------

local _, ns = ...
local S = ns.S

local FLAT = "Interface\\Buttons\\WHITE8X8"
local GCD_SPELL = 61304

local function Build(f)
    local g = CreateFrame("Frame", nil, f, "BackdropTemplate")
    g:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    g:SetBackdropColor(0, 0, 0, 0.6)
    g:SetBackdropBorderColor(0, 0, 0, 1)
    g.bar = CreateFrame("StatusBar", nil, g)
    g.bar:SetPoint("TOPLEFT", 1, -1)
    g.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    g.bar.bg = g.bar:CreateTexture(nil, "BACKGROUND")
    g.bar.bg:SetAllPoints()
    g:Hide()
    g:SetScript("OnUpdate", function(self)
        if not self.finish then return end
        local left = self.finish - GetTime()
        if left <= 0 then
            self.finish = nil
            self:Hide()
            return
        end
        self.bar:SetValue(left)
    end)
    return g
end

function ns.LayoutGCD(f)
    local c = f.cfg.gcd
    if f.unit ~= "player" or not c or not c.enabled then
        if f.gcd then f.gcd:Hide() end
        f.gcdOn = false
        return
    end
    f.gcdOn = true
    local g = f.gcd or Build(f)
    f.gcd = g
    ns.Place(g, f, c)
    g:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, c.height)
    ns.StyleBar(g.bar, c.style)
    ns.PaintBar(g.bar, c.style, 1, 1, 1)
    if ns.testMode then
        g.finish = nil
        g.bar:SetMinMaxValues(0, 1)
        g.bar:SetValue(0.5)
        g:Show()
    else
        g:Hide()
    end
end

local function Update()
    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return end
    local g = f.gcd
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(GCD_SPELL)
    if not info then return end
    local start, duration = info.startTime, info.duration
    if not S(start) and not S(duration) then
        if not duration or duration <= 0 then return end
        g.finish = start + duration
        g.bar:SetMinMaxValues(0, duration)
        g.bar:SetValue(g.finish - GetTime())
        g:Show()
        return
    end
    -- hidden times: the game moves the bar
    local ok = pcall(function()
        local d = C_Spell.GetSpellCooldownDuration(GCD_SPELL)
        g.bar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
    end)
    if ok then
        g.finish = nil
        g:Show()
        C_Timer.After(1.6, function() if not g.finish then g:Hide() end end)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:SetScript("OnEvent", Update)
