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
-- isActive says whether it runs; with plain times the bar moves itself,
-- with hidden times the game moves it (duration object) and a short poll
-- hides it when the global cooldown ends.
local REF = 29515
local poll

local function Active(info)
    local a = info and info.isActive
    return not S(a) and a == true
end

local function StopPoll()
    if poll then
        poll:Cancel()
        poll = nil
    end
end

local function Update()
    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local g = f.gcd
    local info = C_Spell.GetSpellCooldown(REF)
    if not Active(info) then
        StopPoll()
        g.finish = nil
        g:Hide()
        return
    end
    local start, duration = info.startTime, info.duration
    if not S(start) and not S(duration) and type(duration) == "number" and duration > 0 then
        StopPoll()
        g.finish = start + duration
        g.duration = duration
        g.bar:SetMinMaxValues(0, duration)
        local left = g.finish - GetTime()
        g.bar:SetValue(g.fillUp and duration - left or left)
        g:Show()
        return
    end
    -- hidden times: the game moves the bar
    local ok = pcall(function()
        g.bar:SetTimerDuration(C_Spell.GetSpellCooldownDuration(REF), Enum.StatusBarInterpolation.Immediate,
            g.fillUp and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
    end)
    if not ok then return end
    g.finish = nil
    g:Show()
    if not poll then
        poll = C_Timer.NewTicker(0.1, function()
            if not Active(C_Spell.GetSpellCooldown(REF)) then
                StopPoll()
                if not g.finish then g:Hide() end
            end
        end)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:SetScript("OnEvent", Update)
