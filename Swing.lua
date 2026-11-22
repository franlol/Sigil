-------------------------------------------------------------------------------
-- Sigil - Swing timer: main hand, off hand and ranged (Auto Shot, wands,
-- thrown) bars on the player frame, for every class. Two pieces: the melee
-- bars (main and off hand, stacked) and the ranged bar. Each bar can be
-- turned off and fills from one end or toward the middle.
--
-- Timing works as the game's own swing timer: PLAYER_SWING fires on every
-- swing or shot with the duration of the next one (haste included) and each
-- bar fills over it. A weapon swap starts the swing over at the new weapon's
-- speed; the off-hand bar is there with an off-hand weapon. Haste that comes
-- or goes shows from the next swing on (the game hides attack speed in
-- combat).
--
-- Hunters: the aiming zone at the end of the ranged bar, where moving or
-- starting a cast delays the next Auto Shot. Its length: the aiming time
-- (option, 0.5 s by default, the cast that comes before each Auto Shot)
-- plus your latency (option). Drawn shaded or as a line where it starts;
-- the fill can take another color inside it and its length can show as a
-- text on it, each on its own.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local KINDS = { "main", "off", "ranged" }
local MELEE = { "main", "off" }
local RANGED = { "ranged" }

local state = {
    main = {}, off = {}, ranged = {},
    melee = false,      -- when auto attack was turned on (false: off)
    auto = false,       -- when Auto Shot / Shoot started repeating (false: off)
    hasOff = false,     -- an off-hand weapon is equipped (dual wield)
}
-- Each bar (state.main, .off, .ranged): start and dur of the swing in progress

local function SwingKind(kind)
    local E = Enum and Enum.PlayerSwingType
    if not E then return nil end
    if kind == E.MainHand then return "main" end
    if kind == E.OffHand then return "off" end
    if kind == E.Ranged then return "ranged" end
end

-- Attack speed of the weapon in a bar's slot (nil: none, or hidden in combat)
local function EquippedSpeed(kind)
    if not UnitAttackSpeed then return nil end
    local main, off, ranged = UnitAttackSpeed("player")
    local v = ns.R(kind == "off" and off or kind == "ranged" and ranged or main)
    if type(v) == "number" and v > 0 then return v end
end

-- Off-hand weapon, as the game's swing timer checks it. Kept as it was when
-- the speed is hidden.
local function ReadOffHand()
    if not UnitAttackSpeed then return end
    local _, off = UnitAttackSpeed("player")
    if S(off) then return end
    state.hasOff = type(off) == "number" and off > 0
end

local function Latency()
    if not GetNetStats then return 0 end
    local _, _, home, world = GetNetStats()
    local ms = ns.R(world) or ns.R(home)
    return type(ms) == "number" and ms / 1000 or 0
end

-- Seconds of the aiming zone in a reload of `dur`: the aiming time, plus
-- latency when that option is on
local function AimSeconds(dur, c)
    local lag = c.aimLatency ~= false and Latency() or 0
    return math.min(dur, (c.aimTime or 0.5) + lag)
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
    -- the zone: shaded, or a line where it starts (the zone still places it)
    bar.aim = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.aim:SetTexture(ns.FLAT)
    bar.aim:Hide()
    bar.aimLine = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.aimLine:SetTexture(ns.FLAT)
    bar.aimLine:Hide()
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
    box.aimText = over:CreateFontString(nil, "OVERLAY")   -- the zone's length
    box.aimText:Hide()
    box:Hide()
    return box
end

-- The aiming zone sits at the end the half fills toward; its line on the
-- zone's side where the fill comes in. thick: the line's thickness
local function PlaceAim(bar, frac, vertical, reverse, thick)
    local aim, line = bar.aim, bar.aimLine
    local len = vertical and bar:GetHeight() or bar:GetWidth()
    local size = math.max(1, len * frac)
    aim:ClearAllPoints()
    line:ClearAllPoints()
    if vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        local start = reverse and "TOP" or "BOTTOM"
        aim:SetPoint(edge .. "LEFT", bar, edge .. "LEFT")
        aim:SetPoint(edge .. "RIGHT", bar, edge .. "RIGHT")
        aim:SetHeight(size)
        line:SetPoint(start .. "LEFT", aim, start .. "LEFT")
        line:SetPoint(start .. "RIGHT", aim, start .. "RIGHT")
        line:SetHeight(math.min(thick, size))
    else
        local edge = reverse and "LEFT" or "RIGHT"
        local start = reverse and "RIGHT" or "LEFT"
        aim:SetPoint("TOP" .. edge, bar, "TOP" .. edge)
        aim:SetPoint("BOTTOM" .. edge, bar, "BOTTOM" .. edge)
        aim:SetWidth(size)
        line:SetPoint("TOP" .. start, aim, "TOP" .. start)
        line:SetPoint("BOTTOM" .. start, aim, "BOTTOM" .. start)
        line:SetWidth(math.min(thick, size))
    end
end

-- Fill color of a slot's halves: the zone color inside the aiming zone
local function PaintFill(box, c, kind, inZone)
    local col = c[kind].color or { r = 1, g = 1, b = 1 }
    ns.PaintBar(box.bar, c.style, col.r, col.g, col.b)
    ns.PaintBar(box.bar2, box.st2, col.r, col.g, col.b)
    if inZone then
        local z = c.aimFillColor or { r = 1, g = 0.3, b = 0.3 }
        box.bar:SetStatusBarColor(z.r, z.g, z.b)
        box.bar2:SetStatusBarColor(z.r, z.g, z.b)
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
    if kind == "off" and not state.hasOff then return false end
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
                -- ranged: inside the aiming zone, so its options show
                frac = kind == "ranged" and 0.85 or (kind == "main" and 0.6 or 0.3)
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
            -- the text: time left, left / total, or the swing speed now
            local txt = ""
            if bc.text then
                if bc.shows == "speed" then
                    -- this swing's duration, as PLAYER_SWING gave it
                    txt = dur and ns.FormatTime(box.timeRules, dur) or ""
                elseif left then
                    txt = ns.FormatTime(box.timeRules, left)
                    if bc.shows == "both" and dur then
                        -- the total changes only with the swing: written once per swing
                        if box.totalDur ~= dur or box.totalRules ~= box.timeRules then
                            box.totalDur, box.totalRules = dur, box.timeRules
                            box.totalTxt = " / " .. ns.FormatTime(box.timeRules, dur)
                        end
                        txt = txt .. box.totalTxt
                    end
                end
            end
            box.text:SetText(txt)
            -- the zone is measured when anything uses it: drawn, the bar
            -- recolored in it or its length shown, each on its own
            local aimOn = (kind == "ranged" and IsHunter() and dur
                and (c.aim or c.aimFill or c.zone.text)) and true or false
            local drawn = aimOn and c.aim and true or false
            -- placed again only when the reload or the bar's size changed
            -- (latency is read then), or after a layout (any option), not
            -- every frame
            local st = c.style
            local vertical = st.orientation == "VERTICAL"
            local len = aimOn and (vertical and box.bar:GetHeight() or box.bar:GetWidth())
            if aimOn and (box.aimDur ~= dur or box.aimLen ~= len or box.aimTest ~= g.test) then
                box.aimDur, box.aimLen, box.aimTest = dur, len, g.test
                local secs = AimSeconds(dur, c)
                box.aimFrac = secs / dur
                local thick = c.aimLine or 2
                PlaceAim(box.bar, box.aimFrac, vertical, st.reverse, thick)
                PlaceAim(box.bar2, box.aimFrac, vertical, not st.reverse, thick)
                box.aimText:SetText(ns.FormatTime(box.aimRules, secs))
            end
            local line = c.aimStyle == "line"
            box.bar.aim:SetShown(drawn and not line)
            box.bar2.aim:SetShown(drawn and middle and not line)
            box.bar.aimLine:SetShown(drawn and line)
            box.bar2.aimLine:SetShown(drawn and middle and line)
            box.aimText:SetShown(aimOn and c.zone.text and true or false)
            local inZone = (aimOn and c.aimFill and frac >= 1 - box.aimFrac) and true or false
            if inZone ~= box.inZone then
                box.inZone = inZone
                PaintFill(box, c, kind, inZone)
            end
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
    local w = pos.width and pos.width > 0 and pos.width or ns.FrameWidth(f)
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
        box.st2 = st2
        ns.StyleBar(box.bar, st)
        ns.StyleBar(box.bar2, st2)
        PaintFill(box, c, kind, false)
        box.inZone = false
        for _, half in ipairs({ box.bar, box.bar2 }) do
            half.aim:SetVertexColor(ac.r, ac.g, ac.b, ac.a or 0.45)
            half.aimLine:SetVertexColor(ac.r, ac.g, ac.b, ac.a or 0.45)
        end
        box.timeRules = ns.TimeRules(bc.timeFmt)
        ns.StyleText(box.text, bc.textStyle, ns.AutoSize("short", pos.height))
        local tp = bc.textPos
        box.text:ClearAllPoints()
        box.text:SetPoint(tp.point, box, tp.relPoint, tp.x, tp.y)
        -- the zone's length, on the zone of the first half
        box.aimRules = ns.TimeRules(c.zone.timeFmt)
        ns.StyleText(box.aimText, c.zone.textStyle, ns.AutoSize("short", pos.height))
        local ap = c.zone.textPos
        box.aimText:ClearAllPoints()
        box.aimText:SetPoint(ap.point, box.bar.aim, ap.relPoint, ap.x, ap.y)
        box.aimDur = nil   -- options changed: place the aiming zone again
    end
    g.test = ns.testMode and true or false
    Paint(g, c, GetTime(), true)
end

function ns.LayoutSwing(f)
    local c = f.cfg.swing
    if f.unit ~= "player" then return end
    if not c or not c.enabled then
        if f.swing then f.swing:Hide() end
        if f.swingRanged then f.swingRanged:Hide() end
        f.swingOn = false
        return
    end
    f.swingOn = true
    ReadOffHand()
    f.swing = f.swing or Build(f, MELEE)
    f.swingRanged = f.swingRanged or Build(f, RANGED)
    LayoutPiece(f, f.swing, c, "swing", L["Melee swing bars"])
    LayoutPiece(f, f.swingRanged, c, "swingRanged", L["Ranged swing bar"])
end

-- Range indicator (Range.lua): the opacity of the melee bars and of the
-- ranged bar, lower out of their range
function ns.SwingRangeAlpha(f, melee, ranged)
    if f.swing then f.swing:SetAlpha(melee) end
    if f.swingRanged then f.swingRanged:SetAlpha(ranged) end
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
    "STOP_AUTOREPEAT_SPELL", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "WEAPON_SLOT_CHANGED" }) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
-- as the game's own swing timer: the off-hand weapon is checked on these
-- (WEAPON_SLOT_CHANGED is not reliable on entering the world)
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_INVENTORY_CHANGED", "player")
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_ATTACK_SPEED", "player")
watcher:SetScript("OnEvent", function(_, event, a1, a2)
    local now = GetTime()
    if event == "PLAYER_SWING" then
        if S(a1) or S(a2) then return end
        local kind = SwingKind(a2)
        if not kind or type(a1) ~= "number" or a1 <= 0 or a1 == math.huge then return end
        state[kind].start, state[kind].dur = now, a1
    elseif event == "WEAPON_SLOT_CHANGED" then
        -- a weapon swap starts the swing over at the new weapon's speed, as
        -- the game's own swing timer does (hidden speed: until the next swing)
        ReadOffHand()
        for _, kind in ipairs(KINDS) do
            local s = state[kind]
            if s.start and now < s.start + s.dur then
                local speed = EquippedSpeed(kind)
                if speed then s.start, s.dur = now, speed else s.start = nil end
            end
        end
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_ATTACK_SPEED" then
        ReadOffHand()
    elseif event == "PLAYER_ENTER_COMBAT" then
        state.melee = now
    elseif event == "PLAYER_LEAVE_COMBAT" then
        state.melee = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.auto = now
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.auto = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        -- the off-hand speed can be hidden in combat: read it again after it
        ReadOffHand()
    elseif event == "PLAYER_ENTERING_WORLD" then
        state.melee, state.auto = false, false
        for _, kind in ipairs(KINDS) do state[kind].start = nil end
        ReadOffHand()
    end
    Refresh()
end)
