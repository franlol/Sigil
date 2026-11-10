-------------------------------------------------------------------------------
-- Sigil - Target sounds: the game's own "select" and "lost target" sounds.
-- Blizzard's target frame plays them; when Sigil hides that frame they would
-- be lost, so Sigil plays them instead (option in General).
-------------------------------------------------------------------------------

local _, ns = ...
local R = ns.R

local function Play(kit)
    if kit and PlaySound then PlaySound(kit) end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:SetScript("OnEvent", function()
    if not ns.P or not ns.P.sounds or not ns.P.sounds.target then return end
    local K = SOUNDKIT or {}
    if UnitExists("target") then
        if R(UnitIsEnemy("target", "player")) then
            Play(K.IG_CREATURE_AGGRO_SELECT)
        elseif R(UnitIsFriend("player", "target")) then
            Play(K.IG_CHARACTER_NPC_SELECT)
        else
            Play(K.IG_CREATURE_NEUTRAL_SELECT)
        end
    else
        Play(K.INTERFACE_SOUND_LOST_TARGET_UNIT)
    end
end)
