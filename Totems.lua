-------------------------------------------------------------------------------
-- Sigil - Totems: the game's own totem bar, moved next to the player frame
--
-- Totem times are secret in combat; the game's bar draws them itself, so
-- Sigil only moves it (out of combat) and keeps it visible when the
-- Blizzard player frame is hidden.
-------------------------------------------------------------------------------

local _, ns = ...

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
    tf:SetPoint(c.point, f, c.relPoint, c.x or 0, c.y or 0)
    tf:SetScale(c.scale or 1)
    if tf.Update then pcall(tf.Update, tf) end
end
