-------------------------------------------------------------------------------
-- Sigil - Fading
-- The frame becomes transparent (fader.alpha) when any of its checked
-- situations happens:
--   range:     the unit is far away (about 28 yards; party: the game's check)
--   combat:    you are out of combat
--   phase:     the unit is in another phase
--   hostility: the unit is friendly / hostile ("none" = never)
-- It multiplies the frame opacity (Frame tab). Called on events and every
-- 0.2 s (Frames.lua).
-------------------------------------------------------------------------------

local _, ns = ...
local S, R = ns.S, ns.R

local function Base(f) return f.cfg.alpha or 1 end

-- Faded for a reason that is never secret
local function PlainFaded(f, c)
    local u = f.unit
    if c.combat and not InCombatLockdown() then return true end
    if c.phase and UnitPhaseReason and R(UnitPhaseReason(u)) ~= nil then return true end
    if c.hostility == "friendly" and R(UnitIsFriend("player", u)) then return true end
    if c.hostility == "hostile" and R(UnitCanAttack("player", u)) then return true end
    return false
end

-- Is the unit in range? Can be a secret yes/no
local function InRange(u)
    if u:find("^party") and UnitInRange then
        local r, checked = UnitInRange(u)
        if not S(checked) and checked == false then return true end
        return r
    end
    return CheckInteractDistance(u, 4)
end

function ns.UpdateFader(f)
    local c = f.cfg.fader or {}
    local base = Base(f)
    if ns.testMode or not UnitExists(f.unit) then
        f:SetAlpha(base)
        return
    end
    local faded = base * (c.alpha or 0.5)
    if PlainFaded(f, c) then
        f:SetAlpha(faded)
        return
    end
    if c.range and f.unit ~= "player" then
        local inRange = InRange(f.unit)
        if S(inRange) then
            -- the game paints a secret yes/no directly
            if f.SetAlphaFromBoolean then f:SetAlphaFromBoolean(inRange, base, faded) end
        else
            f:SetAlpha(inRange and base or faded)
        end
        return
    end
    f:SetAlpha(base)
end

-- Older name, used by the polling in Frames.lua
ns.UpdateRange = ns.UpdateFader

ns.On("PLAYER_REGEN_DISABLED", function(f) ns.UpdateFader(f) end)
ns.On("PLAYER_REGEN_ENABLED", function(f) ns.UpdateFader(f) end)
ns.On("UNIT_PHASE", function(f) ns.UpdateFader(f) end)
ns.On("UNIT_FACTION", function(f) ns.UpdateFader(f) end)
