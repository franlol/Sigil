-------------------------------------------------------------------------------
-- Sigil - Hide Blizzard's frames that Sigil replaces (option per unit)
--
-- The frame stops listening to events and is moved under a hidden parent.
-- Turning the option off brings a unit frame back after /reload; cast bars
-- come back at once.
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

-- Cast bars: hidden and given back live (they keep their events: only their
-- parent changes). One rule decides where a bar goes, also when the game
-- sets its parent again (Edit Mode attaching it to the player frame):
--   hidden by Sigil          -> under the hidden frame
--   its parent is hidden     -> on the screen (UIParent)
--   otherwise                -> where the game put it
local wanted, busy = {}, false -- [name] = true while Sigil hides it

local function Place(f, name, parent)
    local target = parent
    if wanted[name] then
        target = hidden
    elseif parent == hidden or (parent and parent:GetParent() == hidden) then
        target = UIParent
    end
    if target ~= f:GetParent() then
        busy = true
        f:SetParent(target)
        busy = false
    end
end

local function SetBarHidden(name, hide)
    local f = _G[name]
    if not f then return end
    wanted[name] = hide or nil
    if not f.sigilHooked then
        f.sigilHooked = true
        hooksecurefunc(f, "SetParent", function(self, parent)
            if busy then return end
            -- the game moved it while hidden: that is its home now
            if wanted[name] then self.sigilHome = parent end
            Place(self, name, parent)
        end)
    end
    -- given back: the game's own parent (kept as the bar's "home"), if any
    if hide then
        f.sigilHome = f.sigilHome or f:GetParent()
        Place(f, name, f:GetParent())
    else
        Place(f, name, f.sigilHome or f:GetParent())
        f.sigilHome = nil
    end
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
            local hide = c.enabled and cb and cb.enabled and cb.hideBlizzard
            for _, name in ipairs(names) do
                SetBarHidden(name, hide and true or false)
            end
        end
    end)
end
