-------------------------------------------------------------------------------
-- Sigil - Swing timer: main hand, off hand and ranged (Auto Shot, wands,
-- thrown) bars on the player frame, for every class. Two pieces: the melee
-- bars (main and off hand, stacked) and the ranged bar. Each bar can be
-- turned off and fills from one end or toward the middle.
--
-- Timing comes from the game: PLAYER_SWING fires on every swing or shot with
-- the time until the next one at the current speed (haste included), as
-- plain numbers in combat. Each bar fills from one swing to the next.
-- Like the game's own swing timer: the off-hand bar is there with an
-- off-hand weapon and a weapon swap starts the swing over at the new speed.
-- Haste that comes or goes during a swing (UNIT_ATTACK_SPEED,
-- UNIT_RANGEDDAMAGE) changes the rest of it, so the bar keeps up.
--
-- Hunters: the end of the ranged bar is shaded as the aiming zone, where
-- moving or starting a cast delays the next Auto Shot. Its length: the
-- wind-up (option, 0.5 s by default) shortened by ranged haste like the
-- reload (reload / speed without haste), plus your latency. On Forever the
-- wind-up is about 0.55-0.67 s and scales with the reload; the zone is
-- still an approximation, not a value the game reports.
-- A line before the zone marks the last moment to start Multi-Shot without
-- delaying Auto Shot: the aiming zone plus Multi-Shot's cast time (read from
-- the game; 0.5 s shortened by haste when the game reports none).
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
    hasOff = false,     -- an off-hand weapon is equipped (dual wield)
    meleeAt = nil,      -- last melee swing
    unhasted = nil,     -- ranged weapon speed without haste (quiver included)
    multi = false,      -- Multi-Shot is known
    multiCast = nil,    -- its cast time in seconds as the game reports it (nil: none)
}

-- Multi-Shot, every rank
local MULTI_SHOT = { 2643, 14288, 14289, 14290, 25294 }
local MULTI_CAST = 0.5      -- its cast before haste, when the game reports none
-- Each bar (state.main, .off, .ranged): start and dur of the swing in
-- progress, and speed: the weapon's attack speed when it started (nil: not
-- readable), to follow haste that comes or goes during the swing.

local function SwingKind(kind)
    local E = Enum and Enum.PlayerSwingType
    if not E then return nil end
    if kind == E.MainHand then return "main" end
    if kind == E.OffHand then return "off" end
    if kind == E.Ranged then return "ranged" end
end

-- Attack speed of the weapon in a bar's slot (nil: none, or not readable)
local function EquippedSpeed(kind)
    if not UnitAttackSpeed then return nil end
    local main, off, ranged = UnitAttackSpeed("player")
    local v = ns.R(kind == "off" and off or kind == "ranged" and ranged or main)
    if type(v) == "number" and v > 0 then return v end
end

-- Off-hand weapon, as the game's swing timer checks it. Kept as it was when
-- the speed can't be read.
local function ReadOffHand()
    if not UnitAttackSpeed then return end
    local _, off = UnitAttackSpeed("player")
    if ns.S(off) then return end
    state.hasOff = type(off) == "number" and off > 0
end

-- Ranged speed without haste: the current speed times the game's ranged
-- haste (buffs and quiver, as percents that multiply, like the character
-- sheet shows them). It only changes with the weapon, so a buff up when it
-- is read does not skew it. Kept as it was when the stats can't be read.
local function ReadUnhasted()
    if not (GetRangedHaste and UnitAttackSpeed) then return end
    local _, _, speed = UnitAttackSpeed("player")
    local haste, quiver = GetRangedHaste()
    if S(speed) or S(haste) or S(quiver) then return end
    if type(speed) ~= "number" or speed <= 0 then
        state.unhasted = nil   -- no ranged weapon
        return
    end
    if type(haste) ~= "number" then return end
    state.unhasted = speed * (1 + haste / 100) * (1 + (type(quiver) == "number" and quiver or 0) / 100)
end

-- Multi-Shot known and its cast time (haste changes it: read again then)
local function ReadMulti()
    state.multi, state.multiCast = false, nil
    local book = C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook
    if not (book and C_Spell and C_Spell.GetSpellInfo) then return end
    for _, id in ipairs(MULTI_SHOT) do
        if book(id) then
            state.multi = true
            local info = C_Spell.GetSpellInfo(id)
            local ms = info and ns.R(info.castTime)
            if type(ms) == "number" and ms > 0 then state.multiCast = ms / 1000 end
            return
        end
    end
end

local function ReadStats()
    ReadOffHand()
    ReadUnhasted()
    ReadMulti()
end

-- Haste came or went during a swing: the swing keeps how far along it is and
-- the rest goes at the new speed, as the game does
local function FollowSpeed(now)
    for _, kind in ipairs(KINDS) do
        local s = state[kind]
        if s.start and s.speed and now < s.start + s.dur then
            local speed = EquippedSpeed(kind)
            if speed and math.abs(speed - s.speed) > 0.001 then
                local ratio = speed / s.speed
                s.start = now - (now - s.start) * ratio
                s.dur, s.speed = s.dur * ratio, speed
            end
        end
    end
end

local function Latency()
    if not GetNetStats then return 0 end
    local _, _, home, world = GetNetStats()
    local ms = ns.R(world) or ns.R(home)
    return type(ms) == "number" and ms / 1000 or 0
end

-- Seconds of the aiming zone for a ranged reload of `dur`: the wind-up
-- (option) shortened by haste like the reload, plus latency. hasted: dur is a
-- real reload (the test sample is not)
local function AimSeconds(dur, windUp, hasted)
    local haste = (hasted and state.unhasted) and dur / state.unhasted or 1
    return math.min(dur, windUp * haste + Latency())
end

-- Seconds of Multi-Shot's cast: the game's value, else the default
-- shortened by haste like the reload
local function MultiSeconds(dur, hasted)
    if hasted and state.multiCast then return state.multiCast end
    local haste = (hasted and state.unhasted) and dur / state.unhasted or 1
    return MULTI_CAST * haste
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
    bar.multi = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    bar.multi:SetTexture(ns.FLAT)
    bar.multi:Hide()
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

-- The Multi-Shot line: frac of the bar away from the end it fills toward
local MULTI_LINE = 2
local function PlaceMulti(bar, frac, vertical, reverse)
    local line = bar.multi
    local len = vertical and bar:GetHeight() or bar:GetWidth()
    local off = len * frac
    line:ClearAllPoints()
    if vertical then
        local edge = reverse and "BOTTOM" or "TOP"
        local y = reverse and off or -off
        line:SetPoint("LEFT", bar, edge .. "LEFT", 0, y)
        line:SetPoint("RIGHT", bar, edge .. "RIGHT", 0, y)
        line:SetHeight(MULTI_LINE)
    else
        local edge = reverse and "LEFT" or "RIGHT"
        local x = reverse and off or -off
        line:SetPoint("TOP", bar, "TOP" .. edge, x, 0)
        line:SetPoint("BOTTOM", bar, "BOTTOM" .. edge, x, 0)
        line:SetWidth(MULTI_LINE)
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
            local hunter = (kind == "ranged" and IsHunter() and dur) and true or false
            local aimOn = (hunter and c.aim) and true or false
            local multiOn = (hunter and c.multi and (state.multi or g.test)) and true or false
            -- placed again only when the reload, the haste base, the options,
            -- Multi-Shot's cast or the bar's size changed (latency is read
            -- then), not every frame
            local windUp = c.aimTime or 0.5
            local st = c.style
            local vertical = st.orientation == "VERTICAL"
            local len = (aimOn or multiOn) and (vertical and box.bar:GetHeight() or box.bar:GetWidth())
            if (aimOn or multiOn) and (box.aimDur ~= dur or box.aimWind ~= windUp or box.aimBase ~= state.unhasted
                or box.aimLen ~= len or box.aimTest ~= g.test or box.aimMulti ~= state.multiCast) then
                box.aimDur, box.aimWind, box.aimBase, box.aimLen, box.aimTest = dur, windUp, state.unhasted, len, g.test
                box.aimMulti = state.multiCast
                local aimSec = AimSeconds(dur, windUp, not g.test)
                PlaceAim(box.bar, aimSec / dur, vertical, st.reverse)
                PlaceAim(box.bar2, aimSec / dur, vertical, not st.reverse)
                -- past the whole reload: no moment is safe, no line
                local multiFrac = (aimSec + MultiSeconds(dur, not g.test)) / dur
                box.multiFits = multiFrac < 1
                if box.multiFits then
                    PlaceMulti(box.bar, multiFrac, vertical, st.reverse)
                    PlaceMulti(box.bar2, multiFrac, vertical, not st.reverse)
                end
            end
            box.bar.aim:SetShown(aimOn)
            box.bar2.aim:SetShown(aimOn and middle)
            box.bar.multi:SetShown(multiOn and box.multiFits or false)
            box.bar2.multi:SetShown(multiOn and middle and box.multiFits or false)
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
    local mc = c.multiColor or { r = 1, g = 1, b = 1, a = 0.9 }
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
            half.multi:SetVertexColor(mc.r, mc.g, mc.b, mc.a or 0.9)
        end
        box.timeRules = ns.TimeRules(bc.timeFmt)
        ns.StyleText(box.text, bc.textStyle, ns.AutoSize("short", pos.height))
        local tp = bc.textPos
        box.text:ClearAllPoints()
        box.text:SetPoint(tp.point, box, tp.relPoint, tp.x, tp.y)
        box.aimDur = nil   -- style changed: place the aiming zone again
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
    ReadStats()
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
    "STOP_AUTOREPEAT_SPELL", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "WEAPON_SLOT_CHANGED", "SPELLS_CHANGED" }) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
-- the game's own swing timer uses this too: WEAPON_SLOT_CHANGED is not
-- reliable on entering the world
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_INVENTORY_CHANGED", "player")
-- attack speed changes (haste buffs, quiver): melee and ranged
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_ATTACK_SPEED", "player")
pcall(watcher.RegisterUnitEvent, watcher, "UNIT_RANGEDDAMAGE", "player")
watcher:SetScript("OnEvent", function(_, event, a1, a2)
    local now = GetTime()
    if event == "PLAYER_SWING" then
        if S(a1) or S(a2) then return end
        local kind = SwingKind(a2)
        if not kind or type(a1) ~= "number" or a1 <= 0 or a1 == math.huge then return end
        if kind == "ranged" and state.meleeAt and now - state.meleeAt <= RESET_GRACE then return end
        if kind ~= "ranged" then state.meleeAt = now end
        local s = state[kind]
        s.start, s.dur, s.speed = now, a1, EquippedSpeed(kind)
    elseif event == "UNIT_ATTACK_SPEED" or event == "UNIT_RANGEDDAMAGE" then
        FollowSpeed(now)
        ReadUnhasted()
        ReadMulti()
    elseif event == "SPELLS_CHANGED" then
        ReadMulti()
    elseif event == "WEAPON_SLOT_CHANGED" then
        -- a weapon swap starts the swing over at the new weapon's speed, as
        -- the game's own swing timer does
        ReadStats()
        for _, kind in ipairs(KINDS) do
            local s = state[kind]
            if s.start and now < s.start + s.dur then
                local speed = EquippedSpeed(kind)
                if speed then s.start, s.dur, s.speed = now, speed, speed else s.start = nil end
            end
        end
    elseif event == "UNIT_INVENTORY_CHANGED" then
        ReadStats()
    elseif event == "PLAYER_ENTER_COMBAT" then
        state.melee = now
    elseif event == "PLAYER_LEAVE_COMBAT" then
        state.melee = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.auto = now
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        state.auto = false
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        -- stats can be hidden in combat: read them again after it
        ReadStats()
    elseif event == "PLAYER_ENTERING_WORLD" then
        state.melee, state.auto = false, false
        for _, kind in ipairs(KINDS) do state[kind].start = nil end
        ReadStats()
    end
    Refresh()
end)
