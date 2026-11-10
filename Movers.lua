-------------------------------------------------------------------------------
-- Sigil - Pieces that can be dragged
--
-- Every piece placed around a frame (cast bar, experience, combo points,
-- auras, detached bars...) is registered with ns.PlacePiece. While the frames
-- are unlocked, each visible piece gets a box with its name that can be
-- dragged; dropping it saves the new offsets in its position settings.
-- Pieces anchored to the screen stay put when their frame moves.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local FLAT = "Interface\\Buttons\\WHITE8X8"
local MIN_W, MIN_H = 40, 14

-- Places a piece and remembers it (key: unique name inside the frame)
function ns.PlacePiece(f, key, label, region, pos)
    ns.Place(region, f, pos)
    f.pieces = f.pieces or {}
    local entry = f.pieces[key] or {}
    entry.region, entry.pos, entry.label = region, pos, label
    f.pieces[key] = entry
end

-- The piece of a unit that uses these position settings (nil if none)
function ns.FindPiece(unitKey, pos)
    for _, unit in ipairs(ns.UnitsOf(ns.CfgKey(unitKey))) do
        local f = ns.frames[unit]
        for _, entry in pairs(f and f.pieces or {}) do
            if entry.pos == pos then return entry, f end
        end
    end
end

-- Frame <-> screen, keeping the piece where it is
function ns.SetPieceAnchor(unitKey, pos, anchor)
    local entry, f = ns.FindPiece(unitKey, pos)
    if entry then
        local target = anchor == "screen" and UIParent or f
        local x, y = ns.OffsetsFor(entry.region, target, pos)
        if x then pos.x, pos.y = x, y end
    end
    pos.anchor = anchor
    ns.ApplyUnit(unitKey)
end

-------------------------------------------------------------------------------
-- Drag boxes
-------------------------------------------------------------------------------
-- Puts the box where the piece is, from the piece's own settings (never
-- anchored to the piece: a text showing a secret value has a secret place,
-- and anything anchored to it would get secret sizes too)
local function PlaceMover(m)
    local e = m.entry
    local pos = e.pos
    local p = pos.point or "CENTER"
    local ratio = ns.PieceScale(e.region) / UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint(p, pos.anchor == "screen" and UIParent or m.frame, pos.relPoint or p, (pos.x or 0) * ratio, (pos.y or 0) * ratio)
end

local function NewMover(f, entry)
    local m = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    m:SetFrameStrata("HIGH")
    m:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    m:SetBackdropColor(0.3, 0.6, 0.9, 0.3)
    m:SetBackdropBorderColor(0.45, 0.75, 1, 1)
    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.text:SetPoint("CENTER")
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local e = self.entry
        local cx, cy = GetCursorPosition()
        local x0, y0 = e.pos.x or 0, e.pos.y or 0
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local s = ns.PieceScale(e.region)
            e.pos.x = math.floor(x0 + (x - cx) / s + 0.5)
            e.pos.y = math.floor(y0 + (y - cy) / s + 0.5)
            ns.Place(e.region, self.frame, e.pos)
            PlaceMover(self)
        end)
    end)
    m:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        ns.ApplyUnit(ns.CfgKey(self.frame.unit))
        if ns.OnFrameMoved then ns.OnFrameMoved(self.frame.unit) end
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.entry.label or "")
        GameTooltip:AddLine(self.entry.pos.anchor == "screen" and L["Anchored to the screen"] or L["Anchored to the frame"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag to move"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m.frame = f
    return m
end

-- Shows a drag box over every visible piece of a frame while unlocked
function ns.RefreshMovers(f)
    f.movers = f.movers or {}
    -- party 2-4 share the settings of party 1: only party 1 gets boxes
    local n = tonumber(f.unit:match("^party(%d)$"))
    local allowed = ns.unlocked and not (n and n > 1)
    for key, entry in pairs(f.pieces or {}) do
        local m = f.movers[key]
        local region = entry.region
        if allowed and region and region:IsVisible() then
            m = m or NewMover(f, entry)
            f.movers[key] = m
            m.entry = entry
            m.text:SetText(entry.label or key)
            -- the box covers the piece, never smaller than its label
            -- (a text showing a secret value has a secret size: use the minimum)
            local ratio = ns.PieceScale(region) / UIParent:GetEffectiveScale()
            local w, h = ns.R(region:GetWidth()) or 0, ns.R(region:GetHeight()) or 0
            m:SetSize(math.max(MIN_W, w * ratio), math.max(MIN_H, h * ratio))
            PlaceMover(m)
            m:Show()
        elseif m then
            m:Hide()
        end
    end
end

function ns.RefreshAllMovers()
    for _, f in pairs(ns.frames) do ns.RefreshMovers(f) end
end
