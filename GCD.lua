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
--   plain times: the bar moves itself and hides at the end
--   hidden times: the game moves the bar (duration object); it hides when
--     the game says the global cooldown stopped, or MAX_GCD after it started
--     when the game hides that too
--   hidden "is it running": the bar only starts on a cast (a cast starting,
--     an instant one going off, or a cooldown update right after them), so
--     unrelated updates and the end of a cast with a cast time do not
--     start it again
local REF = 29515
local MAX_GCD = 1.5
local lastCastAt, casting = 0, nil
local token = 0

-- true / false, or nil when the game hides it
local function Running(info)
    local a = info and info.isActive
    if a == nil or S(a) then return nil end
    return a == true
end

-- hides the bar MAX_GCD after it started, unless a newer one started
local function HideLater(g)
    token = token + 1
    local mine = token
    C_Timer.After(MAX_GCD + 0.1, function()
        if token == mine and not g.finish then g:Hide() end
    end)
end

local function Update(_, event, _, _, spellID)
    local fresh = false   -- this update comes from a cast
    if event == "UNIT_SPELLCAST_START" then
        casting = ns.R(spellID)
        fresh = true
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = ns.R(spellID)
        if id and id == casting then casting = nil else fresh = true end
    end
    if fresh then lastCastAt = GetTime() end

    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local g = f.gcd
    local info = C_Spell.GetSpellCooldown(REF)
    local running = Running(info)
    if running == false then
        token = token + 1
        g.finish = nil
        g:Hide()
        return
    end
    local start, duration = info and info.startTime, info and info.duration
    if running and not S(start) and not S(duration) and type(duration) == "number" and duration > 0 then
        g.finish = start + duration
        g.duration = duration
        g.bar:SetMinMaxValues(0, duration)
        local left = g.finish - GetTime()
        g.bar:SetValue(g.fillUp and duration - left or left)
        g:Show()
        return
    end
    -- hidden times; when it is unknown whether it runs, only right after a cast
    if running == nil and not fresh and GetTime() - lastCastAt > 0.3 then return end
    local ok = pcall(function()
        g.bar:SetTimerDuration(C_Spell.GetSpellCooldownDuration(REF), Enum.StatusBarInterpolation.Immediate,
            g.fillUp and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
    end)
    if not ok then return end
    g.finish = nil
    g:Show()
    HideLater(g)
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:SetScript("OnEvent", Update)
