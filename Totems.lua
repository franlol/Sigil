-------------------------------------------------------------------------------
-- Sigil - Totems: the game's own totem bar, moved next to the player frame
--
-- Totem times are secret in combat; the game's bar draws them itself, so
-- Sigil only moves it (out of combat) and keeps it visible when the
-- Blizzard player frame is hidden.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

function ns.LayoutTotems(f)
    local c = f.cfg.totems
    local tf = TotemFrame
    if not c or not tf or f.unit ~= "player" then return end
    if not c.enabled then
        -- left where the game put it (it comes back to its place after /reload)
        return
    end
    tf:SetParent(f)
    tf:ClearAllPoints()
    ns.Place(tf, f, c)
    tf:SetScale(c.scale or 1)
    if tf.Update then pcall(tf.Update, tf) end
end

-- Test mode: four sample totem slots where the game's bar will be, so it
-- can be placed without having totems out
local SLOTS, SLOT_SIZE, SLOT_GAP = 4, 30, 4

function ns.UpdateTotems(f)
    if f.unit ~= "player" then return end
    local c = f.cfg.totems
    local s = f.totemSample
    local _, class = UnitClass("player")
    -- shamans only
    if not (ns.testMode and c and c.enabled and class == "SHAMAN") then
        if s then s:Hide() end
        return
    end
    if not s then
        s = CreateFrame("Frame", nil, f)
        s.icons = {}
        for i = 1, SLOTS do
            local icon = s:CreateTexture(nil, "ARTWORK")
            icon:SetSize(SLOT_SIZE, SLOT_SIZE)
            icon:SetPoint("LEFT", (i - 1) * (SLOT_SIZE + SLOT_GAP), 0)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local border = s:CreateTexture(nil, "BACKGROUND")
            border:SetPoint("TOPLEFT", icon, -1, 1)
            border:SetPoint("BOTTOMRIGHT", icon, 1, -1)
            border:SetColorTexture(0, 0, 0, 1)
            s.icons[i] = icon
        end
        s:SetSize(SLOTS * SLOT_SIZE + (SLOTS - 1) * SLOT_GAP, SLOT_SIZE)
        f.totemSample = s
    end
    s:SetScale(c.scale or 1)
    ns.PlacePiece(f, "totems", L["Totems"], s, c)
    s:Show()
end
