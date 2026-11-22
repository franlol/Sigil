-------------------------------------------------------------------------------
-- Sigil - Range indicator (hunters, player frame): where your target is:
-- melee, dead zone (too close to shoot, too far to melee), ranged or too far.
--
-- From the game's own range checks, the ones the action bars use:
--   Auto Shot range (C_Spell.IsSpellInRange): ranged, from about 8 yd to
--     max range
--   Wing Clip range: melee. Learned at level 12; before it, melee and the
--     dead zone show together as "Close".
--   CheckInteractDistance(target, 4): within about 28 yd (follow distance),
--     which tells the dead zone from too far: Auto Shot reaches past it, so
--     inside it and out of Auto Shot range is the dead zone (Auto Shot's
--     minimum counts the target's size, so a shorter check leaves a gap).
--     When the game does not answer, both show as "Out of range".
-- The game sends no event when the range changes: the indicator checks
-- every 0.1 s while you have a target. A target the checks cannot measure
-- (friendly, dead) hides it.
--
-- Shown as a strip (Melee | Dead zone | Ranged, the zone you are in lit), a
-- text, or both. The swing bars can dim out of their range, as the game's
-- own swing timer does.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local AUTO_SHOT, WING_CLIP = 75, 2974
local STEP = 0.1          -- seconds between checks
local DIM = 0.4           -- swing bars out of range (as the game's swing timer)
local SEGMENTS = { "melee", "dead", "ranged" }

-- Per zone: the strip segments lit, the color they take and the text
local ALL = { melee = true, dead = true, ranged = true }
local ZONES = {
    melee = { lit = { melee = true }, color = "melee", text = "Melee" },
    dead = { lit = { dead = true }, color = "dead", text = "Dead zone" },
    ranged = { lit = { ranged = true }, color = "ranged", text = "Ranged" },
    close = { lit = { melee = true, dead = true }, color = "dead", text = "Close" },
    far = { lit = ALL, color = "far", text = "Too far" },
    out = { lit = ALL, color = "far", text = "Out of range" },
}

local function IsHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-- true / false, or nil when the game cannot tell or hides the answer
local function Check(v)
    if S(v) then return nil end
    return v
end

-- The target's zone (nil: no target the checks can measure), and whether
-- it is in melee and in ranged range (nil: unknown)
local function Zone()
    if not UnitExists("target") then return nil end
    local ranged = Check(C_Spell.IsSpellInRange(AUTO_SHOT, "target"))
    if ranged == nil then return nil end
    if ranged then return "ranged", false, true end
    local melee = Check(C_Spell.IsSpellInRange(WING_CLIP, "target"))
    if melee then return "melee", true, false end
    local near = Check(CheckInteractDistance("target", 4))
    if near == nil then return "out", melee, false end
    if not near then return "far", false, false end
    return melee == nil and "close" or "dead", melee, false
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
local function Build(f)
    local r = CreateFrame("Frame", nil, f)
    r.strip = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.strip:SetAllPoints()
    r.inner = CreateFrame("Frame", nil, r.strip)
    r.seg, r.div = {}, {}
    for i = 1, #SEGMENTS do r.seg[i] = r.inner:CreateTexture(nil, "ARTWORK") end
    for i = 1, #SEGMENTS - 1 do r.div[i] = r.inner:CreateTexture(nil, "OVERLAY") end
    local over = CreateFrame("Frame", nil, r)   -- the text above the strip
    over:SetAllPoints()
    over:SetFrameLevel(r.strip:GetFrameLevel() + 2)
    r.text = over:CreateFontString(nil, "OVERLAY")
    r:Hide()
    return r
end

local function Paint(f, zone)
    local r, c = f.range, f.cfg.range
    local z = ZONES[zone]
    local zc = c.colors[z.color]
    for i, key in ipairs(SEGMENTS) do
        local lit = z.lit[key]
        -- lit: the zone's color; the others: their own color, faint
        local col = lit and zc or c.colors[key]
        r.seg[i]:SetVertexColor(col.r, col.g, col.b, lit and 1 or (c.unlit or 0.15))
    end
    r.text:SetText(L[z.text])
    if c.textStyle.colorMode ~= "custom" then r.text:SetTextColor(zc.r, zc.g, zc.b) end
end

-- The swing bars dim out of their range (nil: full)
local function Dim(f, meleeIn, rangedIn)
    local c = f.cfg.range
    if not (c and c.dim and f.rangeOn) then meleeIn, rangedIn = nil, nil end
    if ns.SwingRangeAlpha then
        ns.SwingRangeAlpha(f, meleeIn == false and DIM or 1, rangedIn == false and DIM or 1)
    end
end

local function Refresh(f)
    local r = f.range
    if not (r and f.rangeOn) then return end
    local zone, meleeIn, rangedIn
    if ns.testMode then
        zone = "dead"
    else
        zone, meleeIn, rangedIn = Zone()
    end
    if zone ~= r.zone then
        r.zone = zone
        if zone then Paint(f, zone) end
        r:SetShown(zone ~= nil)
    end
    Dim(f, meleeIn, rangedIn)
end

-- Checks run while there is a target (or in test mode)
local driver = CreateFrame("Frame")
driver:Hide()
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < STEP then return end
    elapsed = 0
    local f = ns.frames and ns.frames.player
    if f then Refresh(f) end
end)

function ns.UpdateRange(f)
    if f.unit ~= "player" then return end
    driver:SetShown(f.rangeOn and (ns.testMode or UnitExists("target")) and true or false)
    if f.range then f.range.zone = false end   -- paint again
    if f.rangeOn then
        Refresh(f)
    else
        if f.range then f.range:Hide() end
        Dim(f)
    end
end

function ns.LayoutRange(f)
    if f.unit ~= "player" then return end
    local c = f.cfg.range
    f.rangeOn = (c and c.enabled and IsHunter()) and true or false
    if not f.rangeOn then return ns.UpdateRange(f) end
    local r = f.range or Build(f)
    f.range = r
    local w = c.width and c.width > 0 and c.width or ns.FrameWidth(f)
    r:SetSize(w, c.height)
    ns.PlacePiece(f, "range", L["Range indicator"], r, c)

    -- the strip: three equal segments with a line between them
    local st = c.style
    r.strip:SetShown(c.shows ~= "text")
    local edge = ns.StyleBox(r.strip, st, r.inner)
    local inner = w - 2 * edge
    local tex = (st.texture and st.texture ~= "") and ns.ResolveMedia(st.texture) or ns.Texture()
    local n = #SEGMENTS
    for i, t in ipairs(r.seg) do
        t:SetTexture(tex)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", r.inner, "TOPLEFT", inner * (i - 1) / n, 0)
        t:SetPoint("BOTTOMRIGHT", r.inner, "BOTTOMLEFT", inner * i / n, 0)
    end
    local bc = st.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    for i, d in ipairs(r.div) do
        d:SetColorTexture(bc.r, bc.g, bc.b, bc.a or 1)
        d:ClearAllPoints()
        d:SetWidth(math.max(1, edge))
        d:SetPoint("TOP", r.inner, "TOPLEFT", inner * i / n, 0)
        d:SetPoint("BOTTOM", r.inner, "BOTTOMLEFT", inner * i / n, 0)
    end

    -- the text
    ns.StyleText(r.text, c.textStyle, 11)
    local tp = c.textPos
    r.text:ClearAllPoints()
    r.text:SetPoint(tp.point, r, tp.relPoint, tp.x, tp.y)
    r.text:SetShown(c.shows ~= "strip")
    ns.UpdateRange(f)
end

-- A new target starts or stops the checks
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:SetScript("OnEvent", function()
    local f = ns.frames and ns.frames.player
    if f then ns.UpdateRange(f) end
end)
