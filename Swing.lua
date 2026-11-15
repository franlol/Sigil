-------------------------------------------------------------------------------
-- Sigil - Swing timer: main hand, off hand and ranged (Auto Shot, wands,
-- thrown) bars on the player frame, for every class. Two pieces: the melee
-- bars (main and off hand, stacked) and the ranged bar. Each bar can be
-- turned off and fills from one end or toward the middle.
--
-- Timing comes from the game: PLAYER_SWING fires on every swing or shot with
-- the time until the next one at the current speed (haste included), as
-- plain numbers in combat. Each bar fills from one swing to the next.
--
-- Hunters: the end of the ranged bar is shaded as the aiming zone, where
-- moving or starting a cast delays the next Auto Shot. Its length: the
-- wind-up (option, 0.5 s by default) shortened by ranged haste like the
-- reload, plus your latency. On Forever the wind-up is about 0.55-0.67 s
-- and scales with the reload; the zone is
-- still an approximation, not a value the game reports.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local KINDS = { "main", "off", "ranged" }
local MELEE = { "main", "off" }
local RANGED = { "ranged" }
-- Forever client bug: a melee swing also resets the ranged reload, reported
-- as a ranged PLAYER_SWING right after it (not a shot), which is ignored;
-- drop this when the client is fixed.
local RESET_GRACE = 0.1

local state = {
    main = {}, off = {}, ranged = {},
    melee = false,      -- when auto attack was turned on (false: off)
    auto = false,       -- when Auto Shot / Shoot started repeating (false: off)
    offSeen = false,    -- an off-hand swing happened (dual wield)
    meleeAt = nil,      -- last melee swing
    baseRanged = nil,   -- ranged weapon speed, read out of combat
}

local function SwingKind(kind)
    local E = Enum and Enum.PlayerSwingType
    if not E then return nil end
    if kind == E.MainHand then return "main" end
    if kind == E.OffHand then return "off" end
    if kind == E.Ranged then return "ranged" end
end

-- Ranged weapon speed when the game shows it (out of combat)
local function ReadBaseRanged()
    if not UnitRangedDamage then return end
    local speed = UnitRangedDamage("player")
    if speed ~= nil and not S(speed) and type(speed) == "number" and speed > 0 then
        state.baseRanged = speed
    end
end

local function Latency()
    if not GetNetStats then return 0 end
    local _, _, home, world = GetNetStats()
    local ms = ns.R(world) or ns.R(home)
    return type(ms) == "number" and ms / 1000 or 0
end

-- Seconds of the aiming zone for a ranged reload of `dur`. base: the
-- wind-up without haste
local function AimSeconds(dur, base)
    local haste = state.baseRanged and dur / state.baseRanged or 1
    return math.min(dur, base * haste + Latency())
end

local function IsHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-------------------------------------------------------------------------------
-- Bars
-------------------------------------------------------------------------------
-- Each slot has two halves. With fill "middle" the first half (left or
-- bottom) and the second (right or top) fill toward each other; otherwise
-- only the first one shows, across the whole box.
local function NewHalf(box)
    local bar = CreateFrame("StatusBar", nil, box)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar:SetMinMaxValues(0, 1)
    bar.aim = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.aim:SetTexture(ns.FLAT)
    bar.aim:Hide()
    return bar
end

local function NewSlot(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box.bar = NewHalf(box)
    box.bar2 = NewHalf(box)
    local over = CreateFrame("Frame", nil, box)   -- holds the text above both halves
    over:SetAllPoints()
    over:SetFrameLevel(box.bar:GetFrameLevel() + 2)
    box.text = over:CreateFontString(nil, "OVERLAY")
    box:Hide()
    return box
end

-- The aiming zone sits at the end the half fills toward
local function PlaceAim(bar, frac, vertical, reverse)
    local aim = bar.aim
    local len = vertical and bar:GetHeight() or bar:GetWidth()
    local size = math.max(1, len * frac)
    aim:ClearAllPoints()
    if vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        aim:SetPoint(edge .. "LEFT", bar, edge .. "LEFT")
        aim:SetPoint(edge .. "RIGHT", bar, edge .. "RIGHT")
        aim:SetHeight(size)
    else
        local edge = reverse and "LEFT" or "RIGHT"
        aim:SetPoint("TOP" .. edge, bar, "TOP" .. edge)
        aim:SetPoint("BOTTOM" .. edge, bar, "BOTTOM" .. edge)
        aim:SetWidth(size)
    end
end

-- Places the two halves of a slot: in "middle" fill each takes half the box
local function PlaceHalves(box, edge, middle, vertical)
    box.bar2:SetShown(middle)
    if not middle then return end   -- StyleBox already put the first half across the box
    box.bar:ClearAllPoints()
    box.bar2:ClearAllPoints()
    if vertical then
        box.bar:SetPoint("TOPLEFT", box, "LEFT", edge, 0)
        box.bar:SetPoint("BOTTOMRIGHT", -edge, edge)
        box.bar2:SetPoint("TOPLEFT", edge, -edge)
        box.bar2:SetPoint("BOTTOMRIGHT", box, "RIGHT", -edge, 0)
    else
        box.bar:SetPoint("TOPLEFT", edge, -edge)
        box.bar:SetPoint("BOTTOMRIGHT", box, "BOTTOM", 0, edge)
        box.bar2:SetPoint("TOPLEFT", box, "TOP", 0, -edge)
        box.bar2:SetPoint("BOTTOMRIGHT", -edge, edge)
    end
end

local function Wanted(c, kind, now)
    if not c[kind].show then return false end
    local s = state[kind]
    local running = s.start and now < s.start + s.dur
    -- turned on and swung or shot since: a right-click out of range shows nothing yet
    if kind == "ranged" then return running or (state.auto and s.start and s.start >= state.auto) end
    if kind == "off" and not state.offSeen then return false end
    return running or (state.melee and s.start and s.start >= state.melee)
end

-- The position and size settings of a piece
local function PosOf(c, g) return g.kinds == RANGED and c.ranged or c end

-- Stacks the shown bars of a piece top to bottom; the holder takes their
-- total height
local function Restack(g, c)
    local pos = PosOf(c, g)
    local y, gap = 0, c.gap or 2
    for _, kind in ipairs(g.kinds) do
        local box = g.slots[kind]
        if box:IsShown() then
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y)
            y = y + pos.height + gap
        end
    end
    g:SetHeight(math.max(pos.height, y - gap))
end

-- Shows, fills and stacks the bars of a piece. The holder hides when none
-- of its bars shows, so nothing runs per frame while idle (the events show
-- it again). restack: stack again even if no bar changed (after a layout)
local function Paint(g, c, now, restack)
    local changed, any = restack, false
    for _, kind in ipairs(g.kinds) do
        local box = g.slots[kind]
        local want
        if g.test then
            want = c[kind].show and true or false
        else
            want = Wanted(c, kind, now) and true or false
        end
        any = any or want
        if want ~= box:IsShown() then
            box:SetShown(want)
            changed = true
        end
        if want then
            local s = state[kind]
            local frac, left, dur
            if g.test then
                dur = kind == "ranged" and 2.2 or 2.6
                frac = kind == "ranged" and 0.4 or (kind == "main" and 0.6 or 0.3)
                left = dur * (1 - frac)
            elseif s.start and now < s.start + s.dur then
                dur = s.dur
                left = s.start + s.dur - now
                frac = 1 - left / dur
            else
                dur, left, frac = s.dur, nil, 1   -- ready: the next swing is due
            end
            local middle = c[kind].fill == "middle"
            box.bar:SetValue(frac)
            box.bar2:SetValue(frac)
            local bc = c[kind]
            box.text:SetText(bc.text and left and ns.FormatTime(box.timeRules, left) or "")
            local aimOn = (kind == "ranged" and c.aim and IsHunter() and dur) and true or false
            if aimOn then
                local st = c.style
                local vertical = st.orientation == "VERTICAL"
                local aimFrac = AimSeconds(dur, c.aimTime or 0.5) / dur
                PlaceAim(box.bar, aimFrac, vertical, st.reverse)
                if middle then PlaceAim(box.bar2, aimFrac, vertical, not st.reverse) end
            end
            box.bar.aim:SetShown(aimOn)
            box.bar2.aim:SetShown(aimOn and middle)
        end
    end
    if changed then Restack(g, c) end
    g:SetShown(any)
end

local function Build(f, kinds)
    local g = CreateFrame("Frame", nil, f)
    g.kinds = kinds
    g.slots = {}
    for _, kind in ipairs(kinds) do g.slots[kind] = NewSlot(g) end
    g:SetScript("OnUpdate", function(self)
        local c = f.cfg.swing
        if c then Paint(self, c, GetTime()) end
    end)
    return g
end

local function LayoutPiece(f, g, c, key, label)
    local pos = PosOf(c, g)
    local w = pos.width and pos.width > 0 and pos.width or f.cfg.width
    g:SetSize(w, pos.height)
    ns.PlacePiece(f, key, label, g, pos)
    local st = c.style
    local vertical = st.orientation == "VERTICAL"
    -- the second half fills the other way, toward the first
    local st2 = setmetatable({ reverse = not st.reverse }, { __index = st })
    local ac = c.aimColor or { r = 1, g = 0.25, b = 0.25, a = 0.45 }
    for kind, box in pairs(g.slots) do
        local bc = c[kind]
        box:SetSize(w, pos.height)
        local edge = ns.StyleBox(box, st, box.bar)
        PlaceHalves(box, edge, bc.fill == "middle", vertical)
        local col = bc.color or { r = 1, g = 1, b = 1 }
        ns.StyleBar(box.bar, st)
        ns.StyleBar(box.bar2, st2)
        for _, half in ipairs({ box.bar, box.bar2 }) do
            ns.PaintBar(half, st, col.r, col.g, col.b)
            half.aim:SetVertexColor(ac.r, ac.g, ac.b, ac.a or 0.45)
        end
        box.timeRules = ns.TimeRules(bc.timeFmt)
        ns.StyleText(box.text, bc.textStyle, ns.AutoSize("short", pos.height))
        local tp = bc.textPos
        box.text:ClearAllPoints()
        box.text:SetPoint(tp.point, box, tp.relPoint, tp.x, tp.y)
    end
    g.test = ns.testMode and true or false
    Paint(g, c, GetTime(), true)
end

function ns.LayoutSwing(f)
    local c = f.cfg.swing
    if f.unit ~= "player" or not c or not c.enabled then
        if f.swing then f.swing:Hide() end
        if f.swingRanged then f.swingRanged:Hide() end
        f.swingOn = false
        return
    end
    f.swingOn = true
    f.swing = f.swing or Build(f, MELEE)
    f.swingRanged = f.swingRanged or Build(f, RANGED)
    LayoutPiece(f, f.swing, c, "swing", L["Melee swing bars"])
    LayoutPiece(f, f.swingRanged, c, "swingRanged", L["Ranged swing bar"])
end

-- Test mode shows a sample of each bar
function ns.UpdateSwing(f)
    if not f.swingOn then return end
    for _, g in ipairs({ f.swing, f.swingRanged }) do
        g.test = ns.testMode and true or false
        Paint(g, f.cfg.swing, GetTime(), true)
    end
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local function Refresh()
    local f = ns.frames and ns.frames.player
    if not (f and f.swingOn) then return end
    local now = GetTime()
    Paint(f.swing, f.cfg.swing, now)
    Paint(f.swingRanged, f.cfg.swing, now)
end

local watcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_SWING", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
watcher:SetScript("OnEvent", function(_, event, a1, a2)
    local now = GetTime()
    if event == "PLAYER_SWING" then
        if S(a1) or S(a2) then return end
        local kind = SwingKind(a2)
        if not kind or type(a1) ~= "number" or a1 <= 0 or a1 == math.huge then return end
        if kind == "ranged" and state.meleeAt and now - state.meleeAt <= RESET_GRACE then return end
        if kind ~= "ranged" then state.meleeAt = now end
        if kind == "off" then state.offSeen = true end
        state[kind].start, state[kind].dur = now, a1
    elseif event == "PLAYER_ENTER_COMBAT" then
        state.melee = now
    elseif event == "PLAYER_LEAVE_COMBAT" then
        state.melee = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.auto = now
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.auto = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        state.offSeen = false
        ReadBaseRanged()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ReadBaseRanged()
    elseif event == "PLAYER_ENTERING_WORLD" then
        state.melee, state.auto, state.offSeen = false, false, false
        for _, kind in ipairs(KINDS) do state[kind].start = nil end
        ReadBaseRanged()
    end
    Refresh()
end)
