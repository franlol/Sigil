-------------------------------------------------------------------------------
-- Sigil - Minimap button: click opens the options, drag moves it around the
-- minimap (the angle is saved for every character)
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local ACCENT = { 0.71, 0.55, 1 }

local btn = CreateFrame("Button", "SigilMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("AnyUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetPoint("TOPLEFT", 7, -5)
icon:SetTexture("Interface\\AddOns\\Sigil\\Media\\IconRound")

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local atan2 = math.atan2 or atan2

local function Settings()
    ns.db.minimap = ns.db.minimap or { angle = 200, hide = false }
    return ns.db.minimap
end

-- On the edge of the minimap, at the saved angle
local function Place()
    local a = math.rad(Settings().angle)
    local r = Minimap:GetWidth() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

-- While dragging, it follows the cursor around the minimap
local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    Settings().angle = math.deg(atan2(cy / scale - my, cx / scale - mx))
    Place()
end

btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", FollowCursor)
    GameTooltip:Hide()
end)
btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)
btn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        ns.SetTestMode(not ns.testMode)
    else
        ns.ToggleOptions()
    end
end)
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddDoubleLine("Sigil", "v" .. ns.version, ACCENT[1], ACCENT[2], ACCENT[3], 0.5, 0.5, 0.5)
    GameTooltip:AddDoubleLine(L["Profile:"], ns.profileName or "?", 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Click"], L["Open the options"], 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Right click"], L["Test mode"], 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Drag"], L["Move this button"], 1, 0.82, 0, 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function ns.UpdateMinimapButton()
    btn:SetShown(not Settings().hide)
end

-- the saved angle is only known after the saved variables load
btn:RegisterEvent("PLAYER_LOGIN")
btn:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Place()
    ns.UpdateMinimapButton()
end)
