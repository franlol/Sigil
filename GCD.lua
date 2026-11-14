-------------------------------------------------------------------------------
-- Sigil - Global cooldown: a thin bar on the player frame that empties while
-- the global cooldown runs. Read from the Classic global cooldown reference
-- spell; if the times are hidden, the game moves the bar with its duration
-- object.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local function Build(f)
    local g = CreateFrame("Frame", nil, f, "BackdropTemplate")
    g.bar = CreateFrame("StatusBar", nil, g)
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
        self.bar:SetValue(self.fillUp and self.duration - left or left)
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
    ns.PlacePiece(f, "gcd", L["Global cooldown"], g, c)
    g:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, c.height)
    ns.StyleBox(g, c.style, g.bar)
    ns.StyleBar(g.bar, c.style)
    ns.PaintBar(g.bar, c.style, 1, 1, 1)
    g.fillUp = c.fillUp and true or false
    g.test = nil
    ns.UpdateGCD(f)
end

-- Test mode shows a half-full sample bar; leaving it hides the sample
function ns.UpdateGCD(f)
    local g = f.gcd
    if not g or not f.gcdOn then return end
    if ns.testMode then
        g.finish = nil
        g.test = true
        g.bar:SetMinMaxValues(0, 1)
        g.bar:SetValue(0.5)
        g:Show()
    elseif g.test then
        g.test = nil
        g:Hide()
    end
end

-- Where the global cooldown is read from: the Classic reference spell 29515.
-- On Forever the retail global cooldown spell (61304) always reports none.
-- isActive (readable in combat too) says whether it runs:
--   plain times: the bar moves itself and hides at the end
--   hidden times (combat): the game moves the bar (duration object); it
--     hides on the cooldown update that says it stopped, and the game is
--     asked again once the longest global cooldown has passed, in case that
--     update does not come
local REF = 29515
local MAX_GCD = 1.5
local token = 0

local Update

local function Running(info)
    local a = info and info.isActive
    return a ~= nil and not S(a) and a == true
end

-- asks the game again when the longest global cooldown has passed
local function CheckLater()
    token = token + 1
    local mine = token
    C_Timer.After(MAX_GCD + 0.1, function()
        if token == mine then Update() end
    end)
end

function Update()
    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local g = f.gcd
    local info = C_Spell.GetSpellCooldown(REF)
    if not Running(info) then
        token = token + 1
        g.finish = nil
        g:Hide()
        return
    end
    local start, duration = info.startTime, info.duration
    if not S(start) and not S(duration) and type(duration) == "number" and duration > 0 then
        g.finish = start + duration
        g.duration = duration
        g.bar:SetMinMaxValues(0, duration)
        local left = g.finish - GetTime()
        g.bar:SetValue(g.fillUp and duration - left or left)
        g:Show()
        return
    end
    local ok = pcall(function()
        g.bar:SetTimerDuration(C_Spell.GetSpellCooldownDuration(REF), Enum.StatusBarInterpolation.Immediate,
            g.fillUp and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
    end)
    if not ok then return end
    g.finish = nil
    g:Show()
    CheckLater()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:SetScript("OnEvent", function() Update() end)
