-------------------------------------------------------------------------------
-- Sigil - Minimap button (LibDBIcon): click opens the options, right click
-- test mode, drag moves it around the minimap (saved for the whole account).
-- Also the addon compartment entry, named in the TOC.
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

local function OnClick(button)
    if button == "RightButton" then
        ns.SetTestMode(not ns.testMode)
    else
        ns.ToggleOptions()
    end
end

-- compartment = shown for the addon compartment (no drag there)
local function FillTooltip(tt, compartment)
    tt:AddDoubleLine("Sigil", "v" .. ns.version, ACCENT[1], ACCENT[2], ACCENT[3], 0.5, 0.5, 0.5)
    tt:AddDoubleLine(L["Profile:"], ns.profileName or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    tt:AddLine(" ")
    tt:AddDoubleLine(L["Click"], L["Open the options"], 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine(L["Right click"], L["Test mode"], 1, 0.82, 0, 1, 1, 1)
    if not compartment and not Settings().lock then
        tt:AddDoubleLine(L["Drag"], L["Move this button"], 1, 0.82, 0, 1, 1, 1)
    end
end

local broker = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
    type = "launcher",
    icon = "Interface\\AddOns\\Sigil\\Media\\IconRound",
    OnClick = function(_, button) OnClick(button) end,
    OnTooltipShow = function(tt) FillTooltip(tt) end,
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

-- Named in the TOC (AddonCompartmentFunc...)
function Sigil_OnCompartmentClick(_, button) OnClick(button) end
function Sigil_OnCompartmentEnter(_, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    FillTooltip(GameTooltip, true)
    GameTooltip:Show()
end
function Sigil_OnCompartmentLeave() GameTooltip:Hide() end
