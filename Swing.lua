-------------------------------------------------------------------------------
-- Sigil - Swing timer: main hand, off hand and ranged (Auto Shot, wands,
-- thrown) bars on the player frame, for every class.
--
-- Timing comes from the game: PLAYER_SWING fires on every swing or shot with
-- the time until the next one at the current speed (haste included), as
-- plain numbers in combat. Each bar fills from one swing to the next.
--
-- Hunters: the end of the ranged bar is shaded as the aiming zone, where
-- moving or starting a cast delays the next Auto Shot. Its length: 0.5 s
-- (the Auto Shot wind-up) shortened by ranged haste like the reload, plus
-- your latency. On Forever the wind-up measures ~0.55-0.67 s and scales
-- with the reload (Nock's in-game measurements), which this matches; the
-- zone is still an approximation, not a value the game reports.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S = ns.S

local KINDS = { "main", "off", "ranged" }
local AIM_BASE = 0.5
-- Forever client bug: a melee swing also resets the ranged reload, reported
-- as a ranged PLAYER_SWING right after it (not a shot). Nock ignores those
-- the same way; drop this when the client is fixed.
local RESET_GRACE = 0.1

local state = {
    main = {}, off = {}, ranged = {},
    melee = false,      -- auto attack on
    auto = false,       -- Auto Shot / Shoot repeating
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

-- Seconds of the aiming zone for a ranged reload of `dur`
local function AimSeconds(dur)
    local haste = state.baseRanged and dur / state.baseRanged or 1
    return math.min(dur, AIM_BASE * haste + Latency())
end

local function IsHunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-------------------------------------------------------------------------------
-- Bars
-------------------------------------------------------------------------------
local AUTO_COLORS = {
    main = { 0.85, 0.85, 0.85 },
    off = { 0.6, 0.6, 0.75 },
    ranged = { 0.45, 0.8, 0.45 },
}

local function NewSlot(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box.bar = CreateFrame("StatusBar", nil, box)
    box.bar.bg = box.bar:CreateTexture(nil, "BACKGROUND")
    box.bar.bg:SetAllPoints()
    box.bar:SetMinMaxValues(0, 1)
    box.aim = box.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    box.aim:SetTexture(ns.FLAT)
    box.aim:Hide()
    box.text = box.bar:CreateFontString(nil, "OVERLAY")
    box.text:SetPoint("CENTER")
    box:Hide()
    return box
end

-- The aiming zone sits at the end the bar fills toward
local function PlaceAim(box, frac, st)
    local aim = box.aim
    local vertical = st.orientation == "VERTICAL"
    local len = vertical and box.bar:GetHeight() or box.bar:GetWidth()
    local size = math.max(1, len * frac)
    aim:ClearAllPoints()
    if vertical then
        local edge = st.reverse and "BOTTOM" or "TOP"
        aim:SetPoint(edge .. "LEFT", box.bar, edge .. "LEFT")
        aim:SetPoint(edge .. "RIGHT", box.bar, edge .. "RIGHT")
        aim:SetHeight(size)
    else
        local edge = st.reverse and "LEFT" or "RIGHT"
        aim:SetPoint("TOP" .. edge, box.bar, "TOP" .. edge)
        aim:SetPoint("BOTTOM" .. edge, box.bar, "BOTTOM" .. edge)
        aim:SetWidth(size)
    end
end

local function Wanted(c, kind, now)
    local s = state[kind]
    local running = s.start and now < s.start + s.dur
    if kind == "ranged" then return c.ranged and (state.auto or running) end
    if not c.melee then return false end
    if kind == "off" and not state.offSeen then return false end
    return state.melee or running
end

-- Stacks the shown bars top to bottom (main, off, ranged)
local function Restack(g, c)
    local y = 0
    for _, kind in ipairs(KINDS) do
        local box = g.slots[kind]
        if box:IsShown() then
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -y)
            y = y + c.height + (c.gap or 2)
        end
    end
end

-- Shows, fills and stacks the bars. The holder hides when no bar shows, so
-- nothing runs per frame while idle (the events show it again).
local function Paint(g, c, now)
    local changed, any = false, false
    for _, kind in ipairs(KINDS) do
        local box = g.slots[kind]
        local want
        if g.test then
            want = (kind == "main" and c.melee) or (kind == "ranged" and c.ranged) or false
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
                frac = kind == "ranged" and 0.4 or 0.6
                left = dur * (1 - frac)
            elseif s.start and now < s.start + s.dur then
                dur = s.dur
                left = s.start + s.dur - now
                frac = 1 - left / dur
            else
                dur, left, frac = s.dur, nil, 1   -- ready: the next swing is due
            end
            box.bar:SetValue(frac)
            box.text:SetText(c.text and left and ("%.1f"):format(left) or "")
            local aimOn = kind == "ranged" and c.aim and IsHunter() and dur
            if aimOn then PlaceAim(box, AimSeconds(dur) / dur, c.style) end
            box.aim:SetShown(aimOn and true or false)
        end
    end
    if changed then Restack(g, c) end
    g:SetShown(any)
end

local function Build(f)
    local g = CreateFrame("Frame", nil, f)
    g.slots = {}
    for _, kind in ipairs(KINDS) do g.slots[kind] = NewSlot(g) end
    g:SetScript("OnUpdate", function(self)
        local c = f.cfg.swing
        if c then Paint(self, c, GetTime()) end
    end)
    return g
end

function ns.LayoutSwing(f)
    local c = f.cfg.swing
    if f.unit ~= "player" or not c or not c.enabled then
        if f.swing then f.swing:Hide() end
        f.swingOn = false
        return
    end
    f.swingOn = true
    local g = f.swing or Build(f)
    f.swing = g
    local w = c.width and c.width > 0 and c.width or f.cfg.width
    g:SetSize(w, c.height)
    ns.PlacePiece(f, "swing", L["Swing timer"], g, c)
    local ac = c.aimColor or { r = 1, g = 0.25, b = 0.25, a = 0.45 }
    for kind, box in pairs(g.slots) do
        box:SetSize(w, c.height)
        ns.StyleBox(box, c.style, box.bar)
        ns.StyleBar(box.bar, c.style)
        local col = AUTO_COLORS[kind]
        ns.PaintBar(box.bar, c.style, col[1], col[2], col[3])
        box.aim:SetVertexColor(ac.r, ac.g, ac.b, ac.a or 0.45)
        ns.StyleText(box.text, c.textStyle, math.max(8, math.floor(c.height * 0.8)))
    end
    ns.UpdateSwing(f)
end

-- Test mode shows a sample of each bar
function ns.UpdateSwing(f)
    local g = f.swing
    if not g or not f.swingOn then return end
    g.test = ns.testMode and true or false
    Paint(g, f.cfg.swing, GetTime())
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local function Refresh()
    local f = ns.frames and ns.frames.player
    if f and f.swingOn and f.swing then Paint(f.swing, f.cfg.swing, GetTime()) end
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
        state.melee = true
    elseif event == "PLAYER_LEAVE_COMBAT" then
        state.melee = false
    elseif event == "START_AUTOREPEAT_SPELL" then
        state.auto = true
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
