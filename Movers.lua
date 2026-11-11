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

local function NoSkip() return false end

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
            PlaceMover(self)
            local dx, dy = ns.SnapOffset(self, NoSkip)
            if dx ~= 0 or dy ~= 0 then
                local ratio = s / UIParent:GetEffectiveScale()
                e.pos.x = math.floor(e.pos.x + dx / ratio + 0.5)
                e.pos.y = math.floor(e.pos.y + dy / ratio + 0.5)
                PlaceMover(self)
            end
            ns.Place(e.region, self.frame, e.pos)
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

-------------------------------------------------------------------------------
-- Alignment grid (shown behind everything while unlocked)
-------------------------------------------------------------------------------
local GRID_STEP = 32
local grid

-- Size of one screen pixel in UIParent units, so lines are always 1px sharp
local function PixelSize()
    local physH = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 768
    return 768 / physH / UIParent:GetScale()
end

local function BuildGrid()
    grid = grid or CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:EnableMouse(false)
    grid.lines = grid.lines or {}
    for _, t in ipairs(grid.lines) do t:Hide() end

    local px = PixelSize()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local used = 0
    local function Line(vertical, offset, center)
        used = used + 1
        local t = grid.lines[used]
        if not t then
            t = grid:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(FLAT)
            grid.lines[used] = t
        end
        t:ClearAllPoints()
        if center then
            t:SetVertexColor(1, 0.2, 0.2, 0.8)
        else
            t:SetVertexColor(0, 0, 0, 0.45)
        end
        local thick = center and px * 2 or px
        if vertical then
            t:SetSize(thick, h)
            t:SetPoint("CENTER", grid, "CENTER", offset, 0)
        else
            t:SetSize(w, thick)
            t:SetPoint("CENTER", grid, "CENTER", 0, offset)
        end
        t:Show()
    end

    -- lines grow from the center outwards so the center is always on the grid
    for i = 1, math.floor(w / 2 / GRID_STEP) do
        Line(true, i * GRID_STEP); Line(true, -i * GRID_STEP)
    end
    for i = 1, math.floor(h / 2 / GRID_STEP) do
        Line(false, i * GRID_STEP); Line(false, -i * GRID_STEP)
    end
    Line(true, 0, true)
    Line(false, 0, true)
end

-------------------------------------------------------------------------------
-- Snapping: while dragging, a box sticks to the screen center and edges, the
-- grid lines and the edges/centers of the other boxes. Hold Shift to move
-- freely.
-------------------------------------------------------------------------------
local SNAP = 8        -- distance (UI units) that sticks to centers, edges and boxes
local SNAP_GRID = 4   -- weaker pull for the plain grid lines

-- Rectangle of an object in UIParent units: left, right, bottom, top
local function Rect(obj)
    local l, r, b, t = obj:GetLeft(), obj:GetRight(), obj:GetBottom(), obj:GetTop()
    if not (l and r and b and t) then return nil end
    local s = obj:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, r * s, b * s, t * s
end

-- Best correction for one axis: edges = {low, mid, high} of the dragged box
local function Best(edges, targets, center)
    local bestD, bestDist = nil, math.huge
    for _, e in ipairs(edges) do
        for _, t in ipairs(targets) do
            local d = t - e
            if math.abs(d) <= SNAP and math.abs(d) < bestDist then bestD, bestDist = d, math.abs(d) end
        end
        local g = center + math.floor((e - center) / GRID_STEP + 0.5) * GRID_STEP
        local d = g - e
        if math.abs(d) <= SNAP_GRID and math.abs(d) < bestDist then bestD, bestDist = d, math.abs(d) end
    end
    return bestD or 0
end

-- Correction (UIParent units) that makes `box` stick to something.
-- skip(m) returns true for boxes that move together with the dragged one.
function ns.SnapOffset(box, skip)
    if IsShiftKeyDown() then return 0, 0 end
    local l, r, b, t = Rect(box)
    if not l then return 0, 0 end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local xs, ys = { 0, w / 2, w }, { 0, h / 2, h }
    local function Add(m)
        if m == box or not m:IsShown() or skip(m) then return end
        local ol, or_, ob, ot = Rect(m)
        if not ol then return end
        xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = ol, or_, (ol + or_) / 2
        ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = ob, ot, (ob + ot) / 2
    end
    for _, f in pairs(ns.frames) do
        if f.mover then Add(f.mover) end
        for _, m in pairs(f.movers or {}) do Add(m) end
    end
    return Best({ l, (l + r) / 2, r }, xs, w / 2), Best({ b, (b + t) / 2, t }, ys, h / 2)
end

function ns.ShowGrid(on)
    if on then
        BuildGrid()
        grid:Show()
    elseif grid then
        grid:Hide()
    end
end

-- Rebuild if the resolution or UI scale changes while it is visible
local gridEvents = CreateFrame("Frame")
gridEvents:RegisterEvent("UI_SCALE_CHANGED")
gridEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
gridEvents:SetScript("OnEvent", function()
    if grid and grid:IsShown() then BuildGrid() end
end)
