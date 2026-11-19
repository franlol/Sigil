-------------------------------------------------------------------------------
-- Sigil - Minimap button (LibDBIcon): click opens the options, right click
-- test mode, drag moves it around the minimap (saved for the whole account)
-------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

local ACCENT = { 0.71, 0.55, 1 }
local DBI = LibStub("LibDBIcon-1.0")

-- LibDBIcon's settings (minimapPos, hide, lock). Older versions saved the
-- position as "angle": same degrees, so it carries over as it is.
local function Settings()
    ns.db.minimap = ns.db.minimap or { minimapPos = 200, hide = false }
    local m = ns.db.minimap
    if m.angle then
        m.minimapPos = m.angle
        m.angle = nil
    end
    return m
end

local broker = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
    type = "launcher",
    icon = "Interface\\AddOns\\Sigil\\Media\\IconRound",
    OnClick = function(_, button)
        if button == "RightButton" then
            ns.SetTestMode(not ns.testMode)
        else
            ns.ToggleOptions()
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddDoubleLine("Sigil", "v" .. ns.version, ACCENT[1], ACCENT[2], ACCENT[3], 0.5, 0.5, 0.5)
        tt:AddDoubleLine(L["Profile:"], ns.profileName or "?", 0.7, 0.7, 0.7, 1, 1, 1)
        tt:AddLine(" ")
        tt:AddDoubleLine(L["Click"], L["Open the options"], 1, 0.82, 0, 1, 1, 1)
        tt:AddDoubleLine(L["Right click"], L["Test mode"], 1, 0.82, 0, 1, 1, 1)
    end,
})

-- Show or hide it as the options say
function ns.UpdateMinimapButton()
    DBI:Refresh(ADDON, Settings())
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if broker and not DBI:IsRegistered(ADDON) then
        DBI:Register(ADDON, broker, Settings())
    end
end)
