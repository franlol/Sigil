-------------------------------------------------------------------------------
-- Sigil - Default settings (one profile per character by default)
--
-- Each unit has its size, position, portrait, bars, texts, auras, icons...
-- A text is a piece of Lua: it receives the frame's unit in `unit` and
-- returns a string, or a format string followed by its values
-- (return "%s / %s", HP(unit), MaxHP(unit)). See Texts.lua for the helpers.
-- `events`: the events that refresh the text (besides the full updates).
-- The four party frames share the "party" settings.
-------------------------------------------------------------------------------

local _, ns = ...

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end

-------------------------------------------------------------------------------
-- Texts
-------------------------------------------------------------------------------
local NAME = {
    region = "health", point = "LEFT", x = 4, y = 0, size = 12, justify = "LEFT",
    code = [[return Name(unit)]],
    events = { "UNIT_NAME_UPDATE" },
}

local HEALTH = {
    region = "health", point = "RIGHT", x = -4, y = 0, size = 12, justify = "RIGHT",
    code = [[
local status = Status(unit)
if status then return status end
return "%s / %s", Short(HP(unit)), Short(MaxHP(unit))]],
    events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" },
}

local PERCENT = {
    region = "health", point = "RIGHT", x = -4, y = 0, size = 10, justify = "RIGHT",
    code = [[
local status = Status(unit)
if status then return status end
return "%d%%", HPPercent(unit)]],
    events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" },
}

local LEVEL = {
    region = "power", point = "LEFT", x = 4, y = 0, size = 10, justify = "LEFT",
    code = [[return Colorize(Level(unit) .. Classification(unit), DifficultyColor(unit)) .. " " .. Class(unit)]],
    events = { "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED" },
}

local POWER = {
    region = "power", point = "RIGHT", x = -4, y = 0, size = 10, justify = "RIGHT",
    code = [[return "%s / %s", Short(Power(unit)), Short(MaxPower(unit))]],
    events = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
}

local function Text(base, changes)
    local t = Copy(base)
    for k, v in pairs(changes or {}) do t[k] = v end
    return t
end

-------------------------------------------------------------------------------
-- Auras: list of groups. Each group is a block of icons with its own
-- filters, look and position (its `point` on `relPoint` of the frame).
-------------------------------------------------------------------------------
function ns.NewAuraGroup(name, kind, extra)
    local g = {
        name = name, show = true, kind = kind,                 -- HELPFUL | HARMFUL
        visibility = "always", visibilityCustom = "",          -- always | combat | nocombat | custom
        reaction = "any",                                      -- any | friendly | hostile unit
        alpha = 1,
        caster = "all",                                        -- all | mine | others
        dispellable = false,                                   -- debuffs I can dispel
        boss = false,                                          -- boss auras only
        stealable = false,                                     -- buffs I can purge / steal
        maxDuration = 0,                                       -- seconds, 0 = no limit
        types = { Magic = true, Curse = true, Disease = true, Poison = true },
        listMode = "off", spells = {},                         -- off | only | hide
        sort = "default",                                      -- default | time | name
        size = 22, height = 0,                                 -- icon width; height 0 = square
        borderSize = 1, borderColor = { r = 0, g = 0, b = 0, a = 1 },
        spiral = true, borderByType = true, tooltip = true, pandemic = false,   -- look of each icon
        timer = true,                                          -- time left, and its text
        timeFmt = ns.TimeFormat(),
        timerText = ns.TextStyle(0, { point = "CENTER", x = 0, y = 0 }),
        stackText = ns.TextStyle(0, { point = "BOTTOMRIGHT", x = 2, y = -1 }),
        fill = "rows", perRow = 10, max = 10,                  -- rows | columns; icons per line
        spacing = 2, lineSpacing = 2,                          -- between icons / between lines
        relPoint = "BOTTOMLEFT", x = 0, y = -4,                -- point: set from the growth (ns.AuraCorner)
        growX = "RIGHT", growY = "DOWN",
    }
    for k, v in pairs(extra or {}) do g[k] = v end
    g.point = ns.AuraCorner(g)
    return g
end
local Group = ns.NewAuraGroup

-- The corner of a group's block that sits on the frame: the one the icons
-- grow away from (right and down: top left)
function ns.AuraCorner(g)
    return (g.growY == "UP" and "BOTTOM" or "TOP") .. (g.growX == "LEFT" and "RIGHT" or "LEFT")
end

-- Groups are a list the user edits, so profile loading does not fill them:
-- older groups get the keys they miss here (and the old text sizes move in)
local function FillGroup(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = type(v) == "table" and Copy(v) or v
        elseif type(v) == "table" and type(dst[k]) == "table" and k ~= "spells" then
            FillGroup(dst[k], v)
        end
    end
end

function ns.FillAuraGroup(g)
    if g.timerText == nil and g.timerSize then g.timerText = ns.TextStyle(g.timerSize, { point = "CENTER", x = 0, y = 0 }) end
    if g.stackText == nil and g.stackSize then g.stackText = ns.TextStyle(g.stackSize, { point = "BOTTOMRIGHT", x = 2, y = -1 }) end
    g.timerSize, g.stackSize = nil, nil
    FillGroup(g, Group(g.name, g.kind or "HELPFUL"))
    g.point = ns.AuraCorner(g)
    return g
end

-- A unit's groups, ready to use. The old "Show auras" switch is gone:
-- where it was off, its groups are hidden instead (once).
function ns.AuraGroups(auras)
    if not auras then return {} end
    if auras.enabled == false then
        for _, g in ipairs(auras.groups or {}) do g.show = false end
    end
    auras.enabled = nil
    auras.groups = auras.groups or {}
    for _, g in ipairs(auras.groups) do ns.FillAuraGroup(g) end
    return auras.groups
end

-- Default groups that start hidden (ticked on in the Auras tab)
local function Hidden(groups)
    for _, g in ipairs(groups) do g.show = false end
    return groups
end

-------------------------------------------------------------------------------
-- Icons: centered on `point` of the frame, plus x/y
-------------------------------------------------------------------------------
-- relPoint: the point of the frame; point: the point of the icon on it
local function Icon(show, relPoint, x, y, size)
    return { show = show, point = "CENTER", relPoint = relPoint, x = x, y = y, size = size, alpha = 1 }
end

-- Every icon; `on` = the ones shown, `where` = custom positions
local function Icons(on, where)
    local base = {
        combat = Icon(false, "BOTTOMLEFT", 2, 2, 18),
        resting = Icon(false, "TOPLEFT", 2, -2, 18),
        leader = Icon(false, "TOPLEFT", 26, 0, 14),
        assistant = Icon(false, "TOPLEFT", 26, 0, 14),
        masterLooter = Icon(false, "TOPLEFT", 42, 0, 12),
        role = Icon(false, "TOPRIGHT", -10, 0, 14),
        raidTarget = Icon(false, "TOP", 0, 0, 18),
        pvp = Icon(false, "TOPRIGHT", 0, 0, 26),
        readyCheck = Icon(false, "CENTER", 0, 0, 22),
        resurrect = Icon(false, "CENTER", 0, 0, 22),
        summon = Icon(false, "CENTER", 0, 0, 26),
        phase = Icon(false, "CENTER", 0, 0, 22),
        questBoss = Icon(false, "BOTTOMRIGHT", -2, 2, 16),
        happiness = Icon(false, "RIGHT", 10, 0, 16),
    }
    -- PvP: the countdown before the flag drops, on the icon (player frame).
    local pvp = base.pvp
    pvp.timer, pvp.timeFmt, pvp.timerStyle = true, ns.TimeFormat({ style = "clock" }), ns.TextStyle(0)
    pvp.timerPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    for key, v in pairs(where or {}) do
        -- `point` in the overrides below is the point of the frame
        for k, val in pairs(v) do base[key][k == "point" and "relPoint" or k] = val end
    end
    for _, key in ipairs(on) do base[key].show = true end
    return base
end

-------------------------------------------------------------------------------
-- Common blocks: every bar and every text uses the same settings
-------------------------------------------------------------------------------
-- Bar look
--   texture: nil = the general one
--   color: auto (class, reaction, power type...) | gradient (by health) | custom
--   bg: auto (the bar color, darker) | custom; bgAlpha: background opacity
--   border / borderColor: the box around bars that have one (cast bar, GCD...)
function ns.BarStyle(color, extra)
    local st = {
        texture = false, color = color or "auto", custom = { r = 0.2, g = 0.75, b = 0.3 }, alpha = 1, -- alpha: fill opacity
        bg = "auto", bgCustom = { r = 0.1, g = 0.1, b = 0.1 }, bgBrightness = 0.25, bgAlpha = 0.9,
        orientation = "HORIZONTAL", reverse = false, spark = false,
        border = 1, borderColor = { r = 0, g = 0, b = 0, a = 1 }, -- boxed bars: border (px, 0 = none)
    }
    for k, v in pairs(extra or {}) do st[k] = v end
    return st
end
local Bar = ns.BarStyle

-- Text look
--   font / outline: false = the general ones; size 0 = automatic
--   colorMode: code (the color the text code gives, white otherwise) | custom
--   show: always | mouseover | ooc (out of combat)
function ns.TextStyle(size, extra)
    local t = {
        font = false, size = size or 11, outline = false, shadow = false,
        colorMode = "code", color = { r = 1, g = 1, b = 1 }, show = "always",
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end
local Txt = ns.TextStyle

-- Time format of a countdown (drawn in Style.lua). style: short | compact | full |
-- clock | seconds; decimals below N s (0: never, 999: on every time in
-- seconds); warning
-- color below N s (0: off); text only below N s (0: always)
function ns.TimeFormat(extra)
    local t = { style = "short", decimals = 0, warnBelow = 0, warnColor = { r = 1, g = 0.2, b = 0.2 }, hideAbove = 0 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

-------------------------------------------------------------------------------
-- Cast bar, threat, combo points, experience, totems
-------------------------------------------------------------------------------
local function Castbar(enabled, below, height)
    return {
        enabled = enabled, hideBlizzard = true,
        style = Bar("auto", { spark = true }),
        nameText = Txt(0), timeText = Txt(0),   -- size 0: follows the bar height
        timeFormat = "left",                    -- left | both (left / total)
        timeFmt = ns.TimeFormat({ style = "compact", decimals = 999 }),
        fadeTime = 0.4,                         -- seconds the bar stays after it ends
        point = below and "TOPLEFT" or "BOTTOMLEFT", relPoint = below and "BOTTOMLEFT" or "TOPLEFT",
        x = 0, y = below and -4 or 12,
        width = 0, height = height or 18, icon = true,
    }
end

local function Threat(enabled)
    return { enabled = enabled, width = 2 }
end

local COMBO = {
    enabled = true, point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 3,
    width = 0, height = 7, style = Bar("custom", { custom = { r = 1, g = 0.8, b = 0.1 } }),
}

-- Fading: the frame becomes transparent when any checked situation happens
local function Fader(range, alpha)
    return { range = range, combat = false, phase = false, hostility = "none", alpha = alpha }
end

-- Small bars attached to the frame (druid mana, threat, global cooldown)
local function SmallBar(enabled, point, relPoint, y, height, style, text)
    return {
        enabled = enabled, point = point, relPoint = relPoint, x = 0, y = y, width = 0, height = height,
        style = style or Bar("auto"), text = text or false, textStyle = Txt(0),
    }
end

-- Combat text: damage and heals over the frame
local function CombatText(enabled, point, x)
    return {
        enabled = enabled, point = point, relPoint = point, x = x or 0, y = 0, duration = 1.5,   -- a text: one anchor
        textStyle = Txt(18, { shadow = true }),
    }
end

-------------------------------------------------------------------------------
ns.DEFAULTS = {
    units = {
        player = {
            enabled = true,
            point = { "CENTER", "UIParent", "CENTER", -280, -180 },
            width = 240, height = 52,
            portrait = "left",      -- left | right | none
            portraitStyle = "2d",   -- 2d | 3d | class
            power = { height = 14, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = { Copy(NAME), Copy(HEALTH), Copy(LEVEL), Copy(POWER) },
            auras = { groups = Hidden { Group("Buffs", "HELPFUL"), Group("Debuffs", "HARMFUL", { y = -30 }) } },
            icons = Icons({ "combat", "resting", "leader", "assistant", "masterLooter", "role", "raidTarget",
                "readyCheck", "resurrect", "summon" }),
            fader = Fader(false, 0.5),
            castbar = Castbar(true, true, 18),
            threat = Threat(true),
            xp = {
                enabled = false, mode = "auto", text = true,
                style = Bar("auto"), textStyle = Txt(0),
                point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -26, width = 0, height = 10,
            },
            totems = { enabled = true, point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -40, scale = 1 },
        },
        target = {
            enabled = true,
            point = { "CENTER", "UIParent", "CENTER", 280, -180 },
            width = 240, height = 52,
            portrait = "right",
            portraitStyle = "2d",
            power = { height = 14, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = { Copy(NAME), Copy(HEALTH), Copy(LEVEL), Copy(POWER) },
            auras = {
                groups = {
                    Group("Debuffs", "HARMFUL", { size = 24, perRow = 9, max = 9, y = -4 }),
                    Group("Buffs", "HELPFUL", { size = 20, perRow = 11, max = 22, y = -34 }),
                },
            },
            icons = Icons({ "combat", "leader", "raidTarget", "role", "readyCheck", "resurrect", "summon", "phase", "questBoss" },
                { combat = { point = "BOTTOMRIGHT", x = -2 }, leader = { point = "TOPRIGHT", x = -26 },
                  assistant = { point = "TOPRIGHT", x = -26 }, masterLooter = { point = "TOPRIGHT", x = -42 },
                  role = { point = "TOPLEFT", x = 10 }, pvp = { point = "TOPLEFT" }, questBoss = { point = "BOTTOMLEFT", x = 2 } }),
            fader = Fader(true, 0.5),
            castbar = Castbar(true, false, 18),
            threat = Threat(true),
            combo = COMBO,
        },
        targettarget = {
            enabled = true,
            point = { "TOPLEFT", "UIParent", "CENTER", 404, -154 },
            width = 140, height = 26,
            portrait = "none",
            portraitStyle = "2d",
            power = { height = 0, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = { Text(NAME, { point = "CENTER", x = 0, size = 11, justify = "CENTER", events = {} }) },
            auras = { groups = Hidden { Group("Debuffs", "HARMFUL", { size = 16, perRow = 8, max = 8 }) } },
            icons = Icons({ "raidTarget" }, { raidTarget = { point = "LEFT", size = 14 } }),
            fader = Fader(true, 0.5),
            castbar = Castbar(false, true, 14),
            threat = Threat(false),
        },
        targettargettarget = {
            enabled = false,
            point = { "TOPLEFT", "UIParent", "CENTER", 404, -186 },
            width = 140, height = 26,
            portrait = "none",
            portraitStyle = "2d",
            power = { height = 0, style = Bar("auto") },  -- height 0 = no power bar
            texts = { Text(NAME, { point = "CENTER", x = 0, size = 11, justify = "CENTER", events = {} }) },
            auras = { groups = Hidden { Group("Debuffs", "HARMFUL", { size = 16, perRow = 8, max = 8 }) } },
            icons = Icons({ "raidTarget" }, { raidTarget = { point = "LEFT", size = 14 } }),
            fader = Fader(true, 0.5),
            castbar = Castbar(false, true, 14),
            threat = Threat(false),
        },
        focus = {
            enabled = true,
            point = { "CENTER", "UIParent", "CENTER", -280, -100 },
            width = 200, height = 40,
            portrait = "none",
            portraitStyle = "2d",
            power = { height = 8, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = { Copy(NAME), Copy(HEALTH) },
            auras = { groups = Hidden { Group("My debuffs", "HARMFUL", { caster = "mine", pandemic = true, size = 20, perRow = 9, max = 9, y = -26 }) } },
            icons = Icons({ "raidTarget" }, { raidTarget = { size = 16 } }),
            fader = Fader(true, 0.5),
            castbar = Castbar(true, true, 16),
            threat = Threat(true),
        },
        pet = {
            enabled = true,
            point = { "TOPLEFT", "UIParent", "CENTER", -400, -250 },
            width = 140, height = 30,
            portrait = "none",
            portraitStyle = "2d",
            power = { height = 6, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = {
                Text(NAME, { size = 10 }),
                Text(PERCENT, { events = { "UNIT_HEALTH", "UNIT_MAXHEALTH" } }),
            },
            auras = { groups = Hidden { Group("Buffs", "HELPFUL", { size = 16, perRow = 8, max = 8 }) } },
            icons = Icons({ "raidTarget", "happiness" }, { raidTarget = { size = 14 } }),
            fader = Fader(false, 0.5),
            castbar = Castbar(false, true, 12),
            threat = Threat(false),
        },
        party = {
            enabled = true,
            point = { "TOPLEFT", "UIParent", "TOPLEFT", 24, -220 },
            width = 180, height = 40,
            spacing = 26, grow = "DOWN",        -- party 2-4 after the previous one
            hideInRaid = true,
            portrait = "left",
            portraitStyle = "2d",
            power = { height = 6, style = Bar("auto") },  -- height 0 = no power bar
            hideBlizzard = true,
            texts = { Text(NAME, { size = 11 }), Copy(PERCENT) },
            auras = {
                groups = {
                    Group("Debuffs", "HARMFUL", { size = 20, perRow = 4, max = 4,
                        relPoint = "TOPRIGHT", x = 4, y = 0 }),
                    Group("My buffs", "HELPFUL", { caster = "mine", size = 14, perRow = 8, max = 8, timer = false,
                        point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -3 }),
                },
            },
            icons = Icons({ "leader", "assistant", "masterLooter", "role", "raidTarget", "readyCheck", "resurrect",
                "summon", "phase" }),
            fader = Fader(true, 0.45),
            castbar = Castbar(false, true, 12),
            threat = Threat(true),
        },
    },
    smooth = true,  -- smooth bar filling (only if the client has it)
    sounds = { target = true },   -- the game sounds when you pick or lose a target
    media = {
        texture = "Interface\\Buttons\\WHITE8X8",
        font = "Fonts\\FRIZQT__.TTF",
        outline = "OUTLINE",
    },
}

-- Settings every unit has (each unit can change them)
local HIGHLIGHT_TARGET = { party = true, focus = true, targettarget = true, targettargettarget = true }
for key, u in pairs(ns.DEFAULTS.units) do
    -- detached: the bar leaves the frame and is placed with point/relPoint/x/y
    -- (width 0 = frame width)
    u.health = {
        style = Bar("auto"), healPrediction = true, absorbs = true,
        detached = false, point = "TOP", relPoint = "BOTTOM", x = 0, y = -30, width = 0, height = 20,
    }
    u.power.detached = false
    u.power.point, u.power.relPoint, u.power.x, u.power.y, u.power.width = "TOP", "BOTTOM", 0, -8, 0
    u.background = { r = 0, g = 0, b = 0, a = 0.6 }
    u.border = { r = 0, g = 0, b = 0, a = 1 }
    u.borderSize = 1
    u.scale = 1
    u.alpha = 1
    u.portraitWidth = 0                          -- 0 = square (as tall as the frame)
    u.visibility = "always"                      -- always | combat | combatTarget | custom
    u.visibilityCustom = "[combat] show; hide"
    u.highlight = { mouseover = true, target = HIGHLIGHT_TARGET[key] or false }
    u.combatText = CombatText(false, "CENTER")
    u.threatBar = SmallBar(false, "BOTTOMLEFT", "TOPLEFT", 2, 6, nil, true)
end

-- Extras of some frames
local P_ = ns.DEFAULTS.units
P_.player.combatText = CombatText(true, "LEFT", 8)
P_.player.altMana = SmallBar(true, "BOTTOMLEFT", "TOPLEFT", 2, 6)
P_.player.gcd = SmallBar(false, "TOPLEFT", "BOTTOMLEFT", -24, 4, Bar("custom", { custom = { r = 1, g = 1, b = 1 } }))
P_.player.gcd.fillUp = false
-- swing timer: melee bars (main and off hand, one piece) and the ranged bar (its own piece)
-- a time text of the swing timer: shown, time format, look and position
local function SwingText(t)
    t.text, t.timeFmt, t.textStyle = false, ns.TimeFormat({ style = "seconds", decimals = 999 }), Txt(0)
    t.textPos = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    return t
end
local function SwingBar(color, extra)
    -- shows: "left" (time left) | "both" (left / total) | "speed" (swing speed, haste included)
    local b = SwingText({ show = true, fill = "edge", color = color, shows = "left" })
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end
P_.player.swing = {
    enabled = false,
    -- the melee bars (main and off hand), stacked in one piece
    point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -34, width = 0, height = 6, gap = 2,
    -- each bar: shown, fill ("edge": from one end; "middle": two halves fill
    -- toward the middle), color and its time-left text. The ranged bar is a
    -- piece of its own.
    main = SwingBar({ r = 0.85, g = 0.85, b = 0.85 }),
    off = SwingBar({ r = 0.6, g = 0.6, b = 0.75 }),
    ranged = SwingBar({ r = 0.45, g = 0.8, b = 0.45 },
        { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -50, width = 0, height = 6 }),
    style = Bar("auto"),
    -- hunters: Auto Shot aiming zone (aimTime: seconds of the short
    -- cast before each Auto Shot; aimLatency: the zone adds your latency)
    aim = true, aimTime = 0.5, aimLatency = true,
    -- aimStyle: "shade" (the whole zone) | "line" (a line where it starts)
    aimStyle = "shade", aimLine = 2, aimColor = { r = 1, g = 0.25, b = 0.25, a = 0.45 },
    -- the fill takes aimFillColor while it is inside the zone
    aimFill = false, aimFillColor = { r = 1, g = 0.3, b = 0.3 },
    -- the zone's length, a text on the zone with the same settings as each
    -- bar's time-left text
    zone = SwingText({}),
}
-- your own casts: latency, channel ticks, crafting many: one bar for the whole batch
P_.player.castbar.latency = true
P_.player.castbar.latencyColor = { r = 1, g = 0.15, b = 0.15, a = 0.6 }
P_.player.castbar.ticks = true
P_.player.castbar.tickColor = { r = 1, g = 1, b = 1, a = 0.8 }
P_.player.castbar.batch = true
-- hunters: Multi-Shot's short cast (the game shows none) on the cast bar
P_.player.castbar.multiShot = true
P_.target.combatText = CombatText(true, "RIGHT", -8)
P_.target.threatBar = SmallBar(false, "BOTTOMLEFT", "TOPLEFT", 22, 8, nil, true)

-------------------------------------------------------------------------------
-- Colors for every frame. Class, power, reaction and debuff type colors
-- start as the game's own.
-------------------------------------------------------------------------------
local function C(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local function ThreatColor(status, fr, fg, fb)
    if GetThreatStatusColor then
        local r, g, b = GetThreatStatusColor(status)
        if r then return C(r, g, b) end
    end
    return C(fr, fg, fb)
end

local function GameColor(t, fr, fg, fb)
    if t then return C(t.r, t.g, t.b) end
    return C(fr, fg, fb)
end

local classes = {}
for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    classes[token] = GameColor(RAID_CLASS_COLORS and RAID_CLASS_COLORS[token], 1, 1, 1)
end

local power = {}
for token, fallback in pairs({ MANA = { 0, 0, 1 }, RAGE = { 1, 0, 0 }, ENERGY = { 1, 1, 0 }, FOCUS = { 1, 0.5, 0.25 } }) do
    power[token] = GameColor(PowerBarColor and PowerBarColor[token], unpack(fallback))
end

local dispel = {}
for kind, fallback in pairs({ Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }) do
    dispel[kind] = GameColor(DebuffTypeColor and DebuffTypeColor[kind], unpack(fallback))
end

ns.DEFAULTS.colors = {
    class = classes,
    power = power,
    dispel = dispel,
    reaction = {
        hostile = GameColor(FACTION_BAR_COLORS and FACTION_BAR_COLORS[2], 0.85, 0.2, 0.2),
        neutral = GameColor(FACTION_BAR_COLORS and FACTION_BAR_COLORS[4], 0.95, 0.85, 0.2),
        friendly = GameColor(FACTION_BAR_COLORS and FACTION_BAR_COLORS[5], 0.2, 0.8, 0.3),
    },
    state = { dead = C(0.45, 0.45, 0.45), offline = C(0.35, 0.35, 0.4), tapped = C(0.55, 0.55, 0.55) },
    gradient = { low = C(0.9, 0.15, 0.15), mid = C(0.95, 0.8, 0.15), high = C(0.2, 0.8, 0.3) },
    prediction = { heal = C(0.3, 0.9, 0.45, 0.55), absorb = C(0.85, 0.9, 1, 0.55) },
    cast = {
        cast = C(1, 0.7, 0), channel = C(0.3, 0.7, 1), locked = C(0.6, 0.6, 0.6),
        interrupted = C(0.9, 0.2, 0.2), done = C(0.3, 0.85, 0.3),
    },
    highlight = { mouseover = C(1, 1, 1, 0.5), target = C(1, 0.85, 0.3, 1) },
    -- threat status 1-3, from the game's own colors
    threat = { high = ThreatColor(1, 1, 1, 0.47), insecure = ThreatColor(2, 1, 0.6, 0), tanking = ThreatColor(3, 1, 0, 0) },
}
