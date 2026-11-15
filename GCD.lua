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
-- isActive (readable in combat too) says whether it runs. While the bar
-- shows, it is read every 0.1 s, so the bar hides as soon as the global
-- cooldown ends (the game sends no event for that).
--   plain times: the bar moves itself from the start and the duration
--   hidden times (combat): the game moves the bar (duration object), set
--     once when a global cooldown starts. One that starts right as the
--     last ends (still running after the longest global cooldown) starts
--     the bar again.
local REF = 29515
local MAX_GCD = 1.5
local poll, startedAt

local function Running()
    local info = C_Spell.GetSpellCooldown(REF)
    local a = info and info.isActive
    return a ~= nil and not S(a) and a == true, info
end

local function Stop(g)
    if poll then
        poll:Cancel()
        poll = nil
    end
    startedAt = nil
    g.finish = nil
    g:Hide()
end

-- a global cooldown starts: plain times, or the game's timer
local function Start(g, info)
    local start, duration = info.startTime, info.duration
    startedAt = GetTime()
    if not S(start) and not S(duration) and type(duration) == "number" and duration > 0 then
        g.finish = start + duration
        g.duration = duration
        g.bar:SetMinMaxValues(0, duration)
        local left = g.finish - GetTime()
        g.bar:SetValue(g.fillUp and duration - left or left)
    else
        g.finish = nil
        pcall(function()
            g.bar:SetTimerDuration(C_Spell.GetSpellCooldownDuration(REF), Enum.StatusBarInterpolation.Immediate,
                g.fillUp and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
        end)
    end
    g:Show()
end

local function Bar()
    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return nil end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    return f.gcd
end

local function Check()
    local g = Bar()
    if not g then
        if poll then poll:Cancel() poll = nil end
        return
    end
    local running, info = Running()
    if not running then
        Stop(g)
        return
    end
    -- a new one: nothing showing yet, other plain times, or (hidden times)
    -- the last one is longer than any global cooldown (the next started
    -- right as it ended)
    local s, d = info.startTime, info.duration
    local moved = g.finish and not S(s) and not S(d) and type(d) == "number" and s + d ~= g.finish
    if not startedAt or moved or GetTime() - startedAt > MAX_GCD + 0.05 then Start(g, info) end
    if not poll then poll = C_Timer.NewTicker(0.1, Check) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:SetScript("OnEvent", Check)
