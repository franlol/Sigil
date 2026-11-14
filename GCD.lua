-------------------------------------------------------------------------------
-- Sigil - Global cooldown: a thin bar on the player frame that empties while
-- the global cooldown runs. Read from the game's global cooldown spell, or
-- from the spell just cast when the client has no such spell; if
-- the times are hidden, the game moves the bar with its duration object.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local GCD_SPELL = 61304

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

-- Where the global cooldown is read from: the game's global cooldown spell
-- when the client has it (WoW: Forever does not), else the spell you just
-- cast. A spell's cooldown is the global one while it has none of its own:
-- longer than MAX_GCD is its own cooldown, and is not shown.
local MAX_GCD = 1.5
local lastSpell

-- Base cooldown of a spell (game data, not hidden): spells with one of their
-- own cannot tell the global cooldown, so they are not used to read it
local BaseCooldown = (C_Spell and C_Spell.GetSpellBaseCooldown) or GetSpellBaseCooldown
local function HasOwnCooldown(id)
    if not BaseCooldown then return false end
    local ok, ms = pcall(BaseCooldown, id)
    ms = ok and ns.R(ms)
    return type(ms) == "number" and ms > 0
end

local function Source()
    if C_Spell.GetSpellCooldown(GCD_SPELL) then return GCD_SPELL, false end
    return lastSpell, true
end

-- Hides the bar when the global cooldown is over, unless a newer one started
local hideToken = 0
local function HideLater(g)
    hideToken = hideToken + 1
    local mine = hideToken
    C_Timer.After(MAX_GCD + 0.1, function()
        if hideToken == mine and not g.finish then g:Hide() end
    end)
end

-- With hidden times the bar cannot tell a running cooldown from one that
-- just ended, so it only starts on a cast: a cast starting, an instant one
-- going off, or a cooldown update right after them. The end of a cast with
-- a cast time does not start it again.
local lastCastAt, casting = 0, nil

local function Update(_, event, _, _, spellID)
    local castStart = false
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = ns.R(spellID)
        if event == "UNIT_SPELLCAST_START" then
            casting = id
            castStart = true
        elseif id and id == casting then
            casting = nil   -- the end of a cast it already showed
        else
            castStart = true
        end
        if castStart then lastCastAt = GetTime() end
        if id and not HasOwnCooldown(id) then lastSpell = id end
    end
    local f = ns.frames and ns.frames.player
    if not f or not f.gcdOn or ns.testMode then return end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local g = f.gcd
    local id, fromCast = Source()
    if not id then return end
    local info = C_Spell.GetSpellCooldown(id)
    if not info then return end
    local start, duration = info.startTime, info.duration
    if not S(start) and not S(duration) then
        if not duration or duration <= 0 then return end
        if fromCast and duration > MAX_GCD then return end
        g.finish = start + duration
        g.duration = duration
        g.bar:SetMinMaxValues(0, duration)
        local left = g.finish - GetTime()
        g.bar:SetValue(g.fillUp and duration - left or left)
        g:Show()
        return
    end
    -- hidden times: the game moves the bar
    if not castStart and GetTime() - lastCastAt > 0.3 then return end
    local ok = pcall(function()
        local d = C_Spell.GetSpellCooldownDuration(id)
        g.bar:SetTimerDuration(d, Enum.StatusBarInterpolation.Immediate,
            g.fillUp and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime)
    end)
    if ok then
        g.finish = nil
        g:Show()
        HideLater(g)
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watcher:SetScript("OnEvent", Update)
