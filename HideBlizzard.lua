-------------------------------------------------------------------------------
-- Sigil - Hide Blizzard's frames that Sigil replaces (option per unit)
--
-- The frame stops listening to events and is moved under a hidden parent.
-- Turning the option off brings it back after /reload.
-------------------------------------------------------------------------------

local _, ns = ...

local BLIZZARD = {
    player = { "PlayerFrame" },
    target = { "TargetFrame" },
    targettarget = { "TargetFrameToT" },
    focus = { "FocusFrame" },
    pet = { "PetFrame" },
    party = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" },
}

-- Cast bars: hidden when the unit's Sigil cast bar is on
local BLIZZARD_CASTBARS = {
    player = { "PlayerCastingBarFrame", "CastingBarFrame" },
    pet = { "PetCastingBarFrame" },
}

local hidden = CreateFrame("Frame")
hidden:Hide()

local function Kill(name)
    local f = _G[name]
    if not f then return end
    f:UnregisterAllEvents()
    f:Hide()
    f:SetParent(hidden)
end

function ns.HideBlizzard()
    ns.RunOOC("hideBlizzard", function()
        for unit, names in pairs(BLIZZARD) do
            local c = ns.P.units[unit]
            if c.enabled and c.hideBlizzard then
                for _, name in ipairs(names) do Kill(name) end
            end
        end
        for unit, names in pairs(BLIZZARD_CASTBARS) do
            local c = ns.P.units[unit]
            local cb = c.castbar
            if c.enabled and cb and cb.enabled and cb.hideBlizzard then
                for _, name in ipairs(names) do Kill(name) end
            end
        end
    end)
end
