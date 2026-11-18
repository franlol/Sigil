-------------------------------------------------------------------------------
-- Sigil - Options window (built with LibFlatyUI-1.0)
--
--   header: name, version, profile in use, [Test mode] [Unlock frames] [X]
--   left:   General · FRAMES (one entry per frame) · Profiles
--   right:  page title, [Enabled] [Reset], tabs, two columns of cards
--   bottom: status line (notice while in combat)
--
-- Every change is applied at once (secure frames: after combat if needed).
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.theme

local win               -- the options window (built on first open)

local UNIT_NAMES = {
    player = "Player", target = "Target", targettarget = "Target of target",
    targettargettarget = "ToTT", focus = "Focus", pet = "Pet", party = "Party",
}

-- Page titles have room for the full name (the menu does not)
local PAGE_TITLES = { targettargettarget = "Target of target of target" }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function P() return ns.P end
local function U(unit) return ns.P.units[unit] end

local function Changed()
    UI.RefreshAll()
end
UI.OnChange = Changed

local POINTS = function()
    return {
        { "TOPLEFT", L["Top left"] }, { "TOP", L["Top"] }, { "TOPRIGHT", L["Top right"] },
        { "LEFT", L["Left"] }, { "CENTER", L["Center"] }, { "RIGHT", L["Right"] },
        { "BOTTOMLEFT", L["Bottom left"] }, { "BOTTOM", L["Bottom"] }, { "BOTTOMRIGHT", L["Bottom right"] },
    }
end

-- get/set for a key of a unit's table: Bind(unit, "auras", "size")
local function Bind(unit, ...)
    local path = { ... }
    local function Parent()
        local t = U(unit)
        for i = 1, #path - 1 do t = t[path[i]] end
        return t
    end
    local key = path[#path]
    return function() return Parent()[key] end,
        function(v)
            Parent()[key] = v
            ns.ApplyUnit(unit)
        end
end

-- The same for the general settings: GBind("media", "font")
local function GBind(...)
    local path = { ... }
    local function Parent()
        local t = P()
        for i = 1, #path - 1 do t = t[path[i]] end
        return t
    end
    local key = path[#path]
    return function() return Parent()[key] end,
        function(v)
            Parent()[key] = v
            ns.ApplyAll()
        end
end

local function Px(v) return ("%d px"):format(v) end

-- Enabled only when every given condition holds (nil conditions are skipped).
-- Dependent options are greyed out instead of hidden, so the layout never moves.
local function Both(...)
    local conds = { ... }
    local n = select("#", ...)
    return function()
        for i = 1, n do
            local c = conds[i]
            if c and not c() then return false end
        end
        return true
    end
end

-- Selectable list (texts, aura groups, spells). items() -> list;
-- label(item, i) -> text; selected() -> index; onSelect(i);
-- extra(row, item, i) adds pieces to each row; onReorder(from, to) lets rows be dragged
local function SelectList(card, items, label, selected, onSelect, extra, rowH, onReorder)
    return UI.List(card, {
        items = items, label = label, selected = selected, onSelect = onSelect,
        decorate = extra, rowHeight = rowH or 20, onReorder = onReorder,
    })
end


-------------------------------------------------------------------------------
-- Shared blocks: every bar, text and placed piece offers the same settings,
-- in the same order, through these three builders.
-------------------------------------------------------------------------------
-- get/set for a key of a table returned by getTable(); apply() after a change
local function TB(getTable, key, apply)
    return function()
        local t = getTable()
        return t and t[key]
    end, function(v)
        local t = getTable()
        if not t then return end
        t[key] = v
        apply()
    end
end

local function TextureOptions(withDefault)
    local out = {}
    if withDefault then out[1] = { false, L["General texture"] } end
    for _, o in ipairs(ns.TextureList()) do out[#out + 1] = { o[1], o[2], nil, o[1] } end
    return out
end

local function FontOptions(withDefault)
    local out = {}
    if withDefault then out[1] = { false, L["General font"] } end
    for _, o in ipairs(ns.FontList()) do out[#out + 1] = { o[1], o[2], o[1] } end
    return out
end

-- Bar look card. opts: gradient (offers the health gradient), autoLabel,
-- autoTip, enableIf, showIf, subtitle, column, colors (function(card) that
-- adds its own color rows in place of the color choice)
local function BarCard(page, column, title, getStyle, apply, opts)
    opts = opts or {}
    local card = page:Add(column, UI.Card(page.content, title, opts.subtitle))
    card.showIf = opts.showIf
    local on = opts.enableIf
    local function Is(key, value) return function() return getStyle()[key] == value end end
    local function IsNot(key, value) return function() return getStyle()[key] ~= value end end

    local g, s = TB(getStyle, "texture", apply)
    card:Add(UI.Dropdown(card, L["Texture"], function() return TextureOptions(true) end, g, s, { enableIf = on }))
    if opts.colors then
        opts.colors(card)
    else
        local colors = { { "auto", opts.autoLabel or L["Automatic"] } }
        if opts.gradient then colors[#colors + 1] = { "gradient", L["Gradient"] } end
        colors[#colors + 1] = { "custom", L["Custom"] }
        g, s = TB(getStyle, "color", apply)
        card:Add(UI.Segmented(card, L["Color"], colors, g, s, { enableIf = on, tip = opts.autoTip }))
        card:Add(UI.Swatch(card, L["Custom color"], function() return getStyle().custom end, apply,
            { enableIf = Both(on, Is("color", "custom")) }))
    end
    g, s = TB(getStyle, "alpha", apply)
    card:Add(UI.Slider(card, L["Bar opacity"], 0, 1, 0.05, g, s, { format = UI.pct, enableIf = on }))
    g, s = TB(getStyle, "bg", apply)
    card:Add(UI.Segmented(card, L["Background"], { { "auto", L["Bar color, darker"] }, { "custom", L["Custom"] } },
        g, s, { enableIf = on }))
    g, s = TB(getStyle, "bgBrightness", apply)
    card:Add(UI.Slider(card, L["Background brightness"], 0, 1, 0.05, g, s,
        { format = UI.pct, enableIf = Both(on, IsNot("bg", "custom")) }))
    card:Add(UI.Swatch(card, L["Background color"], function() return getStyle().bgCustom end, apply,
        { enableIf = Both(on, Is("bg", "custom")) }))
    g, s = TB(getStyle, "bgAlpha", apply)
    card:Add(UI.Slider(card, L["Background opacity"], 0, 1, 0.05, g, s, { format = UI.pct, enableIf = on }))
    g, s = TB(getStyle, "orientation", apply)
    card:Add(UI.Segmented(card, L["Orientation"], { { "HORIZONTAL", L["Horizontal"] }, { "VERTICAL", L["Vertical"] } },
        g, s, { enableIf = on }))
    g, s = TB(getStyle, "reverse", apply)
    card:Add(UI.Check(card, L["Fill in reverse"], g, s, { enableIf = on }))
    g, s = TB(getStyle, "spark", apply)
    card:Add(UI.Check(card, L["Spark at the end of the fill"], g, s, { enableIf = on }))
    if opts.box then
        -- the box around the bar: border size (0 = none) and color
        g, s = TB(getStyle, "border", apply)
        card:Add(UI.Slider(card, L["Border"], 0, 4, 1, g, s, { format = Px, enableIf = on }))
        card:Add(UI.Swatch(card, L["Border color"], function() return getStyle().borderColor end, apply,
            { alpha = true, enableIf = Both(on, function() return (getStyle().border or 1) > 0 end) }))
    end
    return card
end

-- Page title (big white text at the top of a page)
local function PageTitle(parent, text)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    t:SetPoint("TOPLEFT", 0, -2)
    t:SetText(text)
    return t
end

-- Text look rows, added to a card. opts: auto (size 0 = automatic),
-- show (offers "show only on mouseover / out of combat"), enableIf
local function TextRows(card, getText, apply, opts)
    opts = opts or {}
    local on = opts.enableIf
    local g, s = TB(getText, "font", apply)
    card:Add(UI.Dropdown(card, L["Font"], function() return FontOptions(true) end, g, s, { enableIf = on }))
    g, s = TB(getText, "size", apply)
    card:Add(UI.Slider(card, L["Font size"], opts.auto and 0 or 6, 32, 1, g, s, { enableIf = on,
        format = function(v) return v == 0 and L["Automatic"] or Px(v) end }))
    g, s = TB(getText, "outline", apply)
    card:Add(UI.Segmented(card, L["Outline"], {
        { false, L["General"] }, { "", L["None"] }, { "OUTLINE", L["Thin"] }, { "THICKOUTLINE", L["Thick"] },
    }, g, s, { enableIf = on }))
    g, s = TB(getText, "shadow", apply)
    card:Add(UI.Check(card, L["Shadow"], g, s, { enableIf = on }))
    g, s = TB(getText, "colorMode", apply)
    card:Add(UI.Segmented(card, L["Color"], { { "code", L["Automatic"] }, { "custom", L["Custom"] } }, g, s, {
        enableIf = on, tip = L["Automatic: white, or the colors the text itself sets."] }))
    card:Add(UI.Swatch(card, L["Text color"], function()
        local t = getText()
        if not t then return { r = 1, g = 1, b = 1 } end
        t.color = t.color or { r = 1, g = 1, b = 1 }
        return t.color
    end, apply, { enableIf = Both(on, function() return getText() and getText().colorMode == "custom" end) }))
    if opts.show then
        g, s = TB(getText, "show", apply)
        card:Add(UI.Dropdown(card, L["Show"], {
            { "always", L["Always"] }, { "mouseover", L["Mouseover"] }, { "nomouseover", L["Not on mouseover"] },
            { "ooc", L["Out of combat"] },
        }, g, s, { enableIf = on }))
    end
end

-- seconds as "45 s" / "2 min 05 s"
local function Secs(v)
    return v >= 60 and ("%d min %02d s"):format(v / 60, v % 60) or ("%d s"):format(v)
end

-- Time format rows of a countdown (ns.TimeFormat), the same in every timer.
-- opts: style, decimals, warn, hide (the rows this timer offers), enableIf
local function TimeRows(card, getFmt, apply, opts)
    local on = opts.enableIf
    local g, s
    if opts.style then
        g, s = TB(getFmt, "style", apply)
        card:Add(UI.Dropdown(card, L["Time format"], {
            { "short", "3m · 45s" }, { "compact", "3m · 45" }, { "full", "3m 7s" }, { "clock", "3:07" }, { "seconds", "187" },
        }, g, s, { enableIf = on }))
    end
    if opts.decimals then
        g, s = TB(getFmt, "decimals", apply)
        card:Add(UI.Dropdown(card, L["Decimals"], {
            { 0, L["Never"] }, { 3, L["Below %d s"]:format(3) }, { 5, L["Below %d s"]:format(5) },
            { 10, L["Below %d s"]:format(10) }, { 999, L["Always"] },
        }, g, s, { enableIf = on }))
    end
    if opts.warn then
        g, s = TB(getFmt, "warnBelow", apply)
        card:Add(UI.Slider(card, L["Warning color below"], 0, 30, 1, g, s, { enableIf = on,
            format = function(v) return v == 0 and L["Off"] or Secs(v) end }))
        card:Add(UI.Swatch(card, L["Warning color"], function()
            local f = getFmt()
            return f and f.warnColor or { r = 1, g = 0.2, b = 0.2 }
        end, apply, { enableIf = Both(on, function() return (getFmt().warnBelow or 0) > 0 end) }))
    end
    if opts.hide then
        g, s = TB(getFmt, "hideAbove", apply)
        card:Add(UI.Slider(card, L["Show only below"], 0, 600, 5, g, s, { enableIf = on,
            format = function(v) return v == 0 and L["Always"] or Secs(v) end }))
    end
end

-- "Anchored to" row: frame or screen. Switching keeps the piece where it is.
-- (Party frames share settings, so their pieces always follow each frame.)
local function AnchorRow(card, unit, getPos, enableIf)
    card:Add(UI.Segmented(card, L["Anchored to"], { { "frame", L["Frame"] }, { "screen", L["Screen"] } },
        function() local p = getPos() return p and p.anchor or "frame" end,
        function(v)
            local p = getPos()
            if p and (p.anchor or "frame") ~= v then ns.SetPieceAnchor(unit, p, v) end
        end, {
            enableIf = Both(enableIf, function() return unit ~= "party" end),
            tip = L["Screen: the piece stays in its place on the screen, even when you move the frame. It still shows and hides with its unit."],
        }))
end

-- Position rows (anchored to, points, offsets, optional width), added to a
-- card. One rule for every piece:
--   fixed size (bars, icons, totems): opts.pieceLabel = "Point of the bar"...,
--     the point of the piece that sits on the point of the frame
--   grows (aura blocks): opts.grows, only the point of the frame (the
--     piece's own corner comes from its growth)
--   text: opts.text, one "Anchor" for both (as the frame texts)
-- opts.unit: the frame the piece belongs to
local function PositionRows(card, getPos, apply, opts)
    opts = opts or {}
    local on = opts.enableIf
    if opts.unit then AnchorRow(card, opts.unit, getPos, on) end
    local g, s
    if opts.text then
        g = TB(getPos, "point", apply)
        card:Add(UI.Dropdown(card, L["Anchor"], POINTS, g, function(v)
            local p = getPos()
            if not p then return end
            p.point, p.relPoint = v, v
            apply()
        end, { enableIf = on }))
    else
        g, s = TB(getPos, "relPoint", apply)
        card:Add(UI.Dropdown(card, L["Point of the frame or screen"], POINTS, g, s, { enableIf = on }))
        if not opts.grows then
            g, s = TB(getPos, "point", apply)
            card:Add(UI.Dropdown(card, opts.pieceLabel, POINTS, g, s, { enableIf = on }))
        end
    end
    g, s = TB(getPos, "x", apply)
    card:Add(UI.Slider(card, L["Horizontal offset"], -300, 300, 1, g, s, { format = Px, enableIf = on }))
    g, s = TB(getPos, "y", apply)
    card:Add(UI.Slider(card, L["Vertical offset"], -300, 300, 1, g, s, { format = Px, enableIf = on }))
    if opts.width then
        g, s = TB(getPos, "width", apply)
        card:Add(UI.Slider(card, L["Width"], 0, 500, 1, g, s, { enableIf = on,
            format = function(v) return v == 0 and L["Same as frame"] or Px(v) end }))
    end
end

-------------------------------------------------------------------------------
-- Unit tabs
-------------------------------------------------------------------------------
local Tabs = {}

-- Frame: size, look, portrait, visibility, highlight, position, Blizzard frame
function Tabs.frame(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local function Unit() return U(unit) end

    local card = page:Add(1, UI.Card(page.content, L["Size"]))
    local g, s = Bind(unit, "width")
    card:Add(UI.Slider(card, L["Width"], 40, 500, 1, g, s, { format = Px }))
    g, s = Bind(unit, "height")
    card:Add(UI.Slider(card, L["Height"], 12, 140, 1, g, s, { format = Px }))
    g, s = Bind(unit, "scale")
    card:Add(UI.Slider(card, L["Scale"], 0.5, 2, 0.05, g, s, { format = UI.pct }))

    card = page:Add(1, UI.Card(page.content, L["Look"], L["Background and border of the frame."]))
    card:Add(UI.Swatch(card, L["Background"], function() return Unit().background end, apply, { alpha = true }))
    card:Add(UI.Swatch(card, L["Border"], function() return Unit().border end, apply, { alpha = true }))
    g, s = Bind(unit, "borderSize")
    card:Add(UI.Slider(card, L["Border size"], 0, 6, 1, g, s, { format = function(v) return v == 0 and L["None"] or Px(v) end }))
    g, s = Bind(unit, "alpha")
    card:Add(UI.Slider(card, L["Opacity"], 0.1, 1, 0.05, g, s, { format = UI.pct }))

    card = page:Add(1, UI.Card(page.content, L["Portrait"], L["Picture of the unit at one side of the frame."]))
    g, s = Bind(unit, "portrait")
    card:Add(UI.Segmented(card, L["Side"], {
        { "left", L["Left"] }, { "right", L["Right"] }, { "none", L["None"] },
    }, g, s))
    local function HasPortrait() return Unit().portrait ~= "none" end
    g, s = Bind(unit, "portraitStyle")
    card:Add(UI.Segmented(card, L["Style"], {
        { "2d", "2D" }, { "3d", "3D" }, { "class", L["Class icon"] },
    }, g, s, { enableIf = HasPortrait, tip = L["Class icon: only for players; other units show the 2D picture."] }))
    g, s = Bind(unit, "portraitWidth")
    card:Add(UI.Slider(card, L["Width"], 0, 120, 1, g, s, { enableIf = HasPortrait,
        format = function(v) return v == 0 and L["Square"] or Px(v) end }))

    card = page:Add(2, UI.Card(page.content, L["When to show"], L["The game decides it, so it also works in combat."]))
    g, s = Bind(unit, "visibility")
    card:Add(UI.Segmented(card, nil, {
        { "always", L["Always"] }, { "combat", L["In combat"] }, { "combatTarget", L["Combat or target"] },
        { "custom", L["Custom"] },
    }, g, s))
    g, s = Bind(unit, "visibilityCustom")
    card:Add(UI.Input(card, L["Macro conditions"], g, s, {
        enableIf = function() return Unit().visibility == "custom" end,
        tip = L["Like in a macro, for example: [combat] show; [@target,exists] show; hide"] }))

    card = page:Add(2, UI.Card(page.content, L["Highlight"], L["Colored border (colors in the Colors page)."]))
    card:Add(UI.Check(card, L["When the mouse is over the frame"], function() return Unit().highlight.mouseover end,
        function(v) Unit().highlight.mouseover = v apply() end))
    if unit ~= "target" then
        card:Add(UI.Check(card, L["When this unit is your target"], function() return Unit().highlight.target end,
            function(v) Unit().highlight.target = v apply() end))
    end

    card = page:Add(2, UI.Card(page.content, L["Position"], L["Drag the frames on screen, or fine-tune here."]))
    card:Add(UI.Buttons(card, {
        { L["Unlock frames"], function() ns.SetUnlocked(not ns.unlocked) Changed() end, "accent" },
    }))
    local function PointBind(i)
        return function() return Unit().point[i] end,
            function(v)
                Unit().point[i] = v
                apply()
            end
    end
    g, s = PointBind(4)
    card:Add(UI.Slider(card, L["Horizontal"], -1500, 1500, 1, g, s, { format = Px }))
    g, s = PointBind(5)
    card:Add(UI.Slider(card, L["Vertical"], -1000, 1000, 1, g, s, { format = Px }))

    if unit == "party" then
        card = page:Add(1, UI.Card(page.content, L["Group"], L["The four party members, one after another."]))
        g, s = Bind(unit, "grow")
        card:Add(UI.Segmented(card, L["Next member"], {
            { "DOWN", L["Below"] }, { "UP", L["Above"] }, { "RIGHT", L["Right"] }, { "LEFT", L["Left"] },
        }, g, s))
        g, s = Bind(unit, "spacing")
        card:Add(UI.Slider(card, L["Spacing"], 0, 80, 1, g, s, { format = Px,
            tip = L["Leave room for the auras and cast bar under each member."] }))
        g, s = Bind(unit, "hideInRaid")
        card:Add(UI.Check(card, L["Hide in raids"], g, s, { tip = L["In a raid, use a raid frames addon (like Tile)."] }))
    end

    card = page:Add(2, UI.Card(page.content, L["Blizzard frame"]))
    g, s = Bind(unit, "hideBlizzard")
    local hasFrame = ns.HasBlizzardFrame(unit)
    card:Add(UI.Check(card, L["Hide the game's frame"], g, s, {
        tip = hasFrame and L["Hides the Blizzard frame this one replaces. Turning it off brings it back after /reload."]
            or L["The game has no frame for this unit."],
        enableIf = function() return hasFrame end,
    }))
end

-- Bars: health (with incoming heals and shields) and power
function Tabs.bars(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local card = page:Add(1, UI.Card(page.content, L["Health bar"]))
    local g, s = Bind(unit, "health", "healPrediction")
    card:Add(UI.Check(card, L["Incoming heals"], g, s, { tip = L["A lighter bar after the health with the heals on their way."] }))
    g, s = Bind(unit, "health", "absorbs")
    card:Add(UI.Check(card, L["Shields"], g, s, { tip = L["A bar after the health with the damage shields can absorb."] }))
    local function H() return U(unit).health end
    local function HDet() return H().detached end
    g, s = Bind(unit, "health", "detached")
    card:Add(UI.Check(card, L["Detach from the frame"], g, s, { tip = L["The bar leaves the frame and goes where you place it. Clicks on it do not target the unit."] }))
    g, s = Bind(unit, "health", "height")
    card:Add(UI.Slider(card, L["Height"], 4, 80, 1, g, s, { format = Px, enableIf = HDet }))
    PositionRows(card, H, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = HDet })
    BarCard(page, 1, L["Health bar look"], function() return U(unit).health.style end, apply, {
        gradient = true, autoLabel = L["Class / reaction"],
        autoTip = L["Class / reaction: class color for players; hostile, neutral or friendly color for the rest. Gradient: from the low to the high health color."],
    })

    card = page:Add(2, UI.Card(page.content, L["Power bar"], L["Mana, rage, energy or focus."]))
    g, s = Bind(unit, "power", "height")
    card:Add(UI.Slider(card, L["Height"], 0, 40, 1, g, s, {
        format = function(v) return v == 0 and L["Hidden"] or Px(v) end,
    }))
    local function PW() return U(unit).power end
    local function PDet() return PW().detached and (PW().height or 0) > 0 end
    g, s = Bind(unit, "power", "detached")
    card:Add(UI.Check(card, L["Detach from the frame"], g, s, {
        enableIf = function() return (PW().height or 0) > 0 end,
        tip = L["The bar leaves the frame and goes where you place it. Clicks on it do not target the unit."] }))
    PositionRows(card, PW, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = PDet })
    BarCard(page, 2, L["Power bar look"], function() return U(unit).power.style end, apply, {
        autoLabel = L["Power type"], enableIf = function() return (U(unit).power.height or 0) > 0 end,
    })
end

-- Texts: list on the left, editor on the right
local TEMPLATES = {
    { "name", "Name", [[return Name(unit)]], { "UNIT_NAME_UPDATE" } },
    { "fullname", "Name and surname", [[return FullName(unit)]], { "UNIT_NAME_UPDATE" } },
    { "health", "Health: current / max", [[
local status = Status(unit)
if status then return status end
return "%s / %s", Short(HP(unit)), Short(MaxHP(unit))]], { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" } },
    { "percent", "Health: percentage", [[
local status = Status(unit)
if status then return status end
return "%d%%", HPPercent(unit)]], { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" } },
    { "missing", "Health: missing", [[return "-%s", Short(Missing(unit))]], { "UNIT_HEALTH", "UNIT_MAXHEALTH" } },
    { "power", "Power: current / max", [[return "%s / %s", Short(Power(unit)), Short(MaxPower(unit))]],
        { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" } },
    { "level", "Level and class", [[return Colorize(Level(unit) .. Classification(unit), DifficultyColor(unit)) .. " " .. Class(unit)]],
        { "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED" } },
    { "threat", "Threat", [[
local t = Threat(unit)
if t then return "%d%%", t end]], { "UNIT_THREAT_LIST_UPDATE" } },
    { "classname", "Name in class color", [[return Colorize(Name(unit), ClassColor(unit))]], { "UNIT_NAME_UPDATE" } },
}

-- The functions a text can use, by topic: { call, what it gives }
local HELP = {
    { "Unit", {
        { "Name(unit)", "Name" },
        { "FullName(unit)", "Name with surname" },
        { "Level(unit)", "Level (?? if unknown)" },
        { "Classification(unit)", "+ elite, R rare, R+ rare elite, B boss" },
        { "Class(unit)", "Class, or creature type" },
        { "Status(unit)", "Dead, Ghost, Offline, AFK or nothing" },
    } },
    { "Health", {
        { "HP(unit)", "Current" },
        { "MaxHP(unit)", "Maximum" },
        { "Missing(unit)", "Missing" },
        { "HPPercent(unit)", "Percentage (0-100)" },
        { "HPPercentBelowMax(unit)", "Adds | health% when health is not full; long text is shortened to fit. Usage: return text, HPPercentBelowMax(unit)" },
    } },
    { "Power", {
        { "Power(unit)", "Current" },
        { "MaxPower(unit)", "Maximum" },
    } },
    { "Combat", {
        { "Threat(unit)", "Threat percentage, or nothing" },
    } },
    { "Mouse", {
        { "Hover()", "Mouse over this frame or any of its parts" },
        { "Hover(\"power\")", "Mouse over a part: \"health\", \"power\", \"portrait\", \"castbar\"..." },
    } },
    { "Format", {
        { "Short(number)", "Short number: 12.3K, 1.2M" },
        { "Colorize(text, r, g, b)", "Text in a color (0-1)" },
        { "ClassColor(unit)", "Class color: r, g, b" },
        { "UnitColor(unit)", "Class color for players, reaction color for the rest: r, g, b" },
        { "DifficultyColor(unit)", "Level color by difficulty: r, g, b" },
    } },
}

-- Help window: every function by topic, in two columns. Clicking one
-- inserts it in the code. Closes with X, Esc or a click outside.
local HELP_W, HELP_PAD, HELP_GAP = 640, 18, 18
local helpModal

local function BuildHelp()
    local A = C.accent
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetAllPoints()
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:Hide()
    local dim = m:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.55)
    m:SetScript("OnMouseDown", function(self) self:Hide() end)
    m:EnableKeyboard(true)
    m:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local box = CreateFrame("Frame", nil, m, "BackdropTemplate")
    box:SetWidth(HELP_W)
    box:SetPoint("CENTER")
    box:EnableMouse(true) -- clicks inside do not close it
    UI.Backdrop(box, C.window, { A[1], A[2], A[3], 1 })
    local inner = HELP_W - 2 * HELP_PAD
    local colW = (inner - HELP_GAP) / 2

    -- header: title, what a text is, close button, line
    local title = UI.Text(box, L["Functions you can use"], C.titleFont, A)
    title:SetPoint("TOPLEFT", HELP_PAD, -HELP_PAD)
    local close = UI.Button(box, "X", 22, 20, function() m:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    local intro = UI.Text(box, L["unit is this frame's unit. Return a text, or a format and its values."],
        C.labelFont, C.muted)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    intro:SetWidth(inner - 30)
    intro:SetJustifyH("LEFT")

    -- example in a code-like field
    local example = CreateFrame("Frame", nil, box, "BackdropTemplate")
    UI.Backdrop(example, C.fieldDark, C.border)
    example:SetHeight(26)
    local exText = example:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    exText:SetPoint("LEFT", 10, 0)
    exText:SetText([[return "%s / %s", Short(HP(unit)), Short(MaxHP(unit))]])
    exText:SetTextColor(0.85, 0.85, 0.85)

    local hint = UI.Text(box, L["Click to insert."], C.labelFont, A)

    -- the two columns of topics
    local cols = { {}, {} }
    for i, topic in ipairs(HELP) do
        local col = cols[i <= 3 and 1 or 2]
        local head = UI.Text(box, L[topic[1]], C.titleFont, C.text)
        col[#col + 1] = { head = head }
        for _, fn in ipairs(topic[2]) do
            local b = CreateFrame("Button", nil, box)
            b:SetWidth(colW)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(A[1], A[2], A[3], 0.12)
            b.call = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
            b.call:SetPoint("TOPLEFT", 8, -5)
            b.call:SetText(fn[1])
            b.call:SetTextColor(A[1], A[2], A[3])
            b.desc = UI.Text(b, L[fn[2]], C.labelFont, C.muted)
            b.desc:SetPoint("TOPLEFT", b.call, "BOTTOMLEFT", 0, -3)
            b.desc:SetWidth(colW - 16)
            b.desc:SetJustifyH("LEFT")
            b.desc:SetWordWrap(true)
            b:SetScript("OnClick", function()
                m:Hide()
                if m.onPick then m.onPick(fn[1]) end
            end)
            col[#col + 1] = { button = b }
        end
    end

    local note = UI.Text(box, L["Health and power can be hidden by the game: they can be shown, but not compared or used in math."],
        C.labelFont, C.muted)
    note:SetWidth(inner)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)

    -- places everything; text heights are only known once shown
    function m.Layout()
        local y = HELP_PAD + 16 + 6 + intro:GetStringHeight() + 12
        example:ClearAllPoints()
        example:SetPoint("TOPLEFT", HELP_PAD, -y)
        example:SetPoint("TOPRIGHT", -HELP_PAD, -y)
        y = y + 26 + 10
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", HELP_PAD, -y)
        y = y + 14 + 14
        local bottom = y
        for c, col in ipairs(cols) do
            local x, cy = HELP_PAD + (c - 1) * (colW + HELP_GAP), y
            for i, item in ipairs(col) do
                if item.head then
                    if i > 1 then cy = cy + 10 end
                    item.head:ClearAllPoints()
                    item.head:SetPoint("TOPLEFT", x, -cy)
                    cy = cy + 18
                else
                    local b = item.button
                    b:SetHeight(5 + b.call:GetStringHeight() + 3 + b.desc:GetStringHeight() + 6)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", x, -cy)
                    cy = cy + b:GetHeight() + 1
                end
            end
            bottom = math.max(bottom, cy)
        end
        bottom = bottom + 14
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", HELP_PAD, -bottom)
        box:SetHeight(bottom + note:GetStringHeight() + HELP_PAD)
    end
    return m
end

-- onPick(call): what to do with the function the user clicked
local function ShowHelp(onPick)
    helpModal = helpModal or BuildHelp()
    helpModal.onPick = onPick
    helpModal:Show()
    helpModal.Layout()
end

-- Format: indents the code again by its blocks, 4 spaces per level. Plain
-- text work: strings and comments are left out when counting blocks.
-- Blocks opened on the same line count as one level, so
-- "CallMe(function()" indents its body once, and "end)" closes both.
local INDENT = "    "
local OPENERS = { ["function"] = true, ["do"] = true, ["then"] = true, ["repeat"] = true,
    ["else"] = true, ["{"] = true, ["("] = true }
local CLOSERS = { ["end"] = true, ["until"] = true, ["else"] = true, ["elseif"] = true,
    ["}"] = true, [")"] = true }

local function Reindent(text)
    local out, open = {}, {} -- open: the line number of every block still open
    local function Level()
        local n, last = 0, nil
        for _, ln in ipairs(open) do
            if ln ~= last then n, last = n + 1, ln end
        end
        return n
    end
    local ln = 0
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        ln = ln + 1
        line = line:match("^%s*(.-)%s*$")
        -- only the code part: no escaped quotes, strings or comments
        local bare = line:gsub("\\.", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
        local level, i = nil, 1
        while i <= #bare do
            local s, e = bare:find("^[%a_][%w_]*", i)
            local tok = s and bare:sub(s, e) or bare:sub(i, i)
            i = (e or i) + 1
            if CLOSERS[tok] then table.remove(open) end
            -- closers at the start pull this line back; anything else fixes
            -- its level ("else" closes a block and opens the next one)
            if not level and (not CLOSERS[tok] or tok == "else") and not tok:find("^%s$") then
                level = Level()
            end
            if OPENERS[tok] then table.insert(open, ln) end
        end
        level = level or Level()
        out[#out + 1] = line == "" and "" or INDENT:rep(math.max(0, level)) .. line
    end
    -- the loop adds one empty line for the final newline
    if out[#out] == "" then out[#out] = nil end
    return table.concat(out, "\n")
end

-- Reindents an edit box, keeping the cursor about where it was
local function FormatBox(edit)
    local pos = edit:GetCursorPosition()
    local text = Reindent(edit:GetText())
    edit:SetText(text)
    edit:SetCursorPosition(math.min(pos, #text))
    edit:SetFocus()
end

-- Big editor: the code in a large window. Done hands the code back to
-- onDone; Cancel, Esc or leaving the tab drop the changes. A click outside
-- does nothing, so a stray click never loses work.
local bigEditor

local function BuildBigEditor()
    local A = C.accent
    local W, H, P = 860, 600, 16
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetAllPoints()
    m:SetFrameStrata("FULLSCREEN") -- under the help window (FULLSCREEN_DIALOG)
    m:EnableMouse(true)
    m:Hide()
    local dim = m:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.55)
    m:EnableKeyboard(true)
    m:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    local box = CreateFrame("Frame", nil, m, "BackdropTemplate")
    box:SetSize(W, H)
    box:SetPoint("CENTER")
    box:EnableMouse(true)
    UI.Backdrop(box, C.window, { A[1], A[2], A[3], 1 })

    local title = UI.Text(box, L["Code"], C.titleFont, A)
    title:SetPoint("TOPLEFT", P, -P - 3)
    m.name = UI.Text(box, "", C.labelFont, C.muted)
    m.name:SetPoint("LEFT", title, "RIGHT", 8, 0)

    -- tools on the left of the header gap, the closing pair on the right
    local done = UI.Button(box, L["Done"], 90, 22, function()
        local onDone = m.onDone
        m:Hide()
        if onDone then onDone(m.code.edit:GetText()) end
    end, "accent")
    done:SetPoint("TOPRIGHT", -P, -P + 2)
    local cancel = UI.Button(box, L["Cancel"], 90, 22, function() m:Hide() end)
    cancel:SetPoint("RIGHT", done, "LEFT", -6, 0)
    local format = UI.Button(box, L["Format"], 90, 22, function() FormatBox(m.code.edit) end)
    format:SetPoint("RIGHT", cancel, "LEFT", -18, 0)
    local funcs = UI.Button(box, L["Functions"], 90, 22, function()
        ShowHelp(function(call)
            m.code.edit:SetFocus()
            m.code.edit:Insert(call)
        end)
    end)
    funcs:SetPoint("RIGHT", format, "LEFT", -6, 0)

    m.code = UI.CodeBox(box, H - 2 * P - 30)
    m.code:SetPoint("TOPLEFT", P, -P - 30)
    m.code:SetWidth(W - 2 * P)
    m.code.OnWidth(W - 2 * P)
    m.code.edit:SetScript("OnTabPressed", function(self) self:Insert(INDENT) end)

    m:SetScript("OnHide", function(self)
        self.onDone = nil
        if helpModal then helpModal:Hide() end
    end)
    return m
end

local function ShowBigEditor(name, text, onDone)
    bigEditor = bigEditor or BuildBigEditor()
    bigEditor.name:SetText(name or "")
    bigEditor.onDone = onDone
    bigEditor:Show()
    bigEditor.code.edit:SetText(text or "")
    bigEditor.code.edit:SetCursorPosition(0)
    bigEditor.code.edit:SetFocus()
end

-- Its name, or else the start of its code (the same for every text)
local function TextLabel(t)
    if t.name and t.name ~= "" then return t.name end
    local first = (t.code or ""):match("[^\n]+") or ""
    first = first:gsub("^%s*return%s*", "")
    if #first > 26 then first = first:sub(1, 24) .. "…" end
    return first
end

function Tabs.texts(page, unit)
    local state = { sel = 1 }
    local function Texts() return U(unit).texts end
    local function Sel() return Texts()[state.sel] end

    -- list: a check box per row turns the text on or off; disabled ones are grey
    local function SetEnabled(t, on)
        -- nil = on (older texts have no field)
        if on then t.enabled = nil else t.enabled = false end
        ns.ApplyUnit(unit)
        Changed()
    end
    local REGIONS = { health = "Health bar", power = "Power bar", frame = "Whole frame" }
    local list = page:Add(1, UI.Card(page.content, L["Texts"], L["Click to edit · drag to reorder"]))
    list:Add(UI.List(list, {
        items = Texts,
        label = TextLabel,
        secondary = function(t) return L[REGIONS[t.region] or "Health bar"] end,
        off = function(t) return t.enabled == false end,
        checked = function(t) return t.enabled ~= false end,
        onCheck = function(t, v) SetEnabled(t, v) end,
        selected = function() return state.sel end,
        onSelect = function(i)
            state.sel = i
            if page.LoadEditor then page.LoadEditor() end
        end,
        onReorder = function(from, to)
            local t = table.remove(Texts(), from)
            table.insert(Texts(), to, t)
            state.sel = to
            ns.ApplyUnit(unit)
            if page.LoadEditor then page.LoadEditor() end
        end,
        onRemove = function(i)
            table.remove(Texts(), i)
            if state.sel > i or state.sel > #Texts() then state.sel = math.max(1, state.sel - 1) end
            ns.ApplyUnit(unit)
            Changed()
            page.LoadEditor()
        end,
        empty = L["No texts."],
        rows = 12,
    }))

    -- + in the title: pick a template, the text is added and selected
    local tplOptions = {}
    for _, t in ipairs(TEMPLATES) do tplOptions[#tplOptions + 1] = { t[1], L[t[2]] } end
    local function AddText(key)
        for _, t in ipairs(TEMPLATES) do
            if t[1] == key then
                table.insert(Texts(), {
                    region = "health", point = "CENTER", x = 0, y = 0, size = 11, justify = "CENTER",
                    code = t[3], events = ns.DeepCopy(t[4]), name = L[t[2]],
                })
                state.sel = #Texts()
            end
        end
        ns.ApplyUnit(unit)
        page.LoadEditor()
    end
    list:AddHeaderButton("plus", function(self) UI.Menu(self, tplOptions, AddText) end, { tip = L["Add text"] })

    -- editor: name, code and events are a draft; Save keeps all three at
    -- once (only when the code works), Undo goes back to the saved ones
    local draft = {}
    local function EventsText(t) return table.concat(t.events or {}, ", ") end
    local ed = page:Add(2, UI.Card(page.content, L["Edit text"]))
    ed.showIf = function() return Sel() ~= nil end
    local code, status -- built below
    local function Dirty()
        local t = Sel()
        return t and (draft.name ~= (t.name or "") or code.edit:GetText() ~= (t.code or "")
            or draft.events ~= EventsText(t))
    end
    local function ShowDirty()
        if Dirty() then
            status:SetText("|cffffc35c" .. L["Unsaved changes."] .. "|r")
            Changed()
        end
    end
    local nameRow = ed:Add(UI.Input(ed, L["Name"], function() return draft.name end,
        function(v) draft.name = v; ShowDirty() end, { saveOnBlur = true }))

    -- tools over the code
    ed:Add(UI.Buttons(ed, {
        { L["Functions"], function()
            ShowHelp(function(call)
                code.edit:SetFocus()
                code.edit:Insert(call)
            end)
        end },
        { L["Format"], function() FormatBox(code.edit) end },
        { L["Expand"], function()
            ShowBigEditor(Sel() and TextLabel(Sel()) or "", code.edit:GetText(), function(text)
                code.edit:SetText(text)
                ShowDirty()
            end)
        end },
    }))
    code = ed:Add(UI.CodeBox(ed, 200))
    code.edit:SetScript("OnTabPressed", function(self) self:Insert("    ") end)
    code.edit:HookScript("OnTextChanged", function(_, userInput) if userInput then ShowDirty() end end)
    local events = ed:Add(UI.Input(ed, L["Update on"], function() return draft.events end,
        function(v) draft.events = v; ShowDirty() end,
        { saveOnBlur = true, tip = L["Game events that refresh this text, separated by commas. It is also refreshed when the unit changes."] }))
    status = ed:Add(UI.Note(ed, ""))
    status.showIf = function() return (status.text:GetText() or "") ~= "" end

    -- Compiles the editor's code and runs it once (compiled is not enough:
    -- errors can happen at run time). Shows any error. true if it works.
    local function Validate()
        local fn, err = ns.CompileText(code.edit:GetText())
        if fn then
            local ok, runErr = ns.TryText(unit, fn)
            if ok then return true end
            err = runErr
        end
        status:SetText("|cffff6b61" .. L["Error:"] .. "|r " .. tostring(err))
        Changed()
        return false
    end
    ed:Add(UI.Buttons(ed, {
        { L["Validate"], function()
            if not Sel() or not Validate() then return end
            status:SetText("|cff6bd66b" .. L["The code works."] .. "|r"
                .. (Dirty() and ("  |cffffc35c" .. L["Not saved yet."] .. "|r") or ""))
            Changed()
        end },
        { L["Save"], function()
            local t = Sel()
            if not t then return end
            -- broken code is never saved: the text keeps its last good version
            if not Validate() then
                status:SetText(status.text:GetText() .. "\n" .. L["Not saved."])
                Changed()
                return
            end
            t.name = draft.name
            t.code = code.edit:GetText()
            t.events = {}
            for ev in draft.events:gmatch("[%w_]+") do table.insert(t.events, ev:upper()) end
            draft.events = EventsText(t)
            ns.ApplyUnit(unit)
            status:SetText("|cff6bd66b" .. L["Saved."] .. "|r")
            Changed()
        end, "accent" },
        { L["Undo changes"], function() page.LoadEditor() end },
    }))

    local place = page:Add(2, UI.Card(page.content, L["Placement"]))
    place.showIf = function() return Sel() ~= nil end
    local function TBind(key)
        return function() return Sel() and Sel()[key] end,
            function(v)
                if not Sel() then return end
                Sel()[key] = v
                ns.ApplyUnit(unit)
            end
    end
    local g, s = TBind("region")
    place:Add(UI.Segmented(place, L["Inside"], {
        { "health", L["Health bar"] }, { "power", L["Power bar"] }, { "frame", L["Whole frame"] },
    }, g, s))
    g = TBind("point")
    place:Add(UI.Dropdown(place, L["Anchor"], POINTS, g, function(v)
        local t = Sel()
        if not t then return end
        t.point = v
        t.justify = v:find("LEFT") and "LEFT" or v:find("RIGHT") and "RIGHT" or "CENTER"
        ns.ApplyUnit(unit)
    end))
    g, s = TBind("x")
    place:Add(UI.Slider(place, L["Horizontal offset"], -200, 200, 1, g, s, { format = Px }))
    g, s = TBind("y")
    place:Add(UI.Slider(place, L["Vertical offset"], -100, 100, 1, g, s, { format = Px }))
    local look = page:Add(2, UI.Card(page.content, L["Text look"]))
    look.showIf = function() return Sel() ~= nil end
    TextRows(look, Sel, function() ns.ApplyUnit(unit) end, { show = true })

    function page.LoadEditor()
        local t = Sel()
        draft.name = t and t.name or ""
        draft.events = t and EventsText(t) or ""
        code.edit:SetText(t and t.code or "")
        code.edit:SetCursorPosition(0)
        status:SetText("")
        nameRow.Refresh()
        events.Refresh()
        page:Layout()
    end
    page:HookScript("OnShow", function() page.LoadEditor() end)
    page:HookScript("OnHide", function()
        if helpModal then helpModal:Hide() end
        if bigEditor then bigEditor:Hide() end
    end)
    page.LoadEditor()
    -- the whole list was replaced (copy, undo, reset)
    function page.Reload()
        state.sel = 1
        page.LoadEditor()
    end
end

-- Auras. Left: the groups, the spell list, how the icons line up and where
-- the block goes. Right: what the selected group shows and how it looks.
local SORTS = function()
    return { { "default", L["Game order"] }, { "time", L["Time left"] }, { "name", L["Name"] } }
end

function Tabs.auras(page, unit)
    local state = { sel = 1 }
    local apply = function() ns.ApplyUnit(unit) end
    local function Groups() return ns.AuraGroups(U(unit).auras) end
    local function Sel() return Groups()[state.sel] end
    local function SelOn() return Sel() ~= nil end
    local function Harmful() return Sel() and Sel().kind == "HARMFUL" end
    local function Is(key, value) return function() return Sel() and Sel()[key] == value end end
    function page.Reload() state.sel = 1 end   -- the groups were replaced (copy, undo, reset)
    local function HasSel(card) card.showIf = function() return Sel() ~= nil end return card end

    -- get/set for a key of the selected group
    local function SB(key) return TB(Sel, key, apply) end

    -- groups
    local list = page:Add(1, UI.Card(page.content, L["Aura groups"], L["Click to edit · drag to reorder"]))
    local g, s
    list:Add(UI.List(list, {
        items = Groups,
        label = function(grp) return L[grp.name or ""] or "" end,
        secondary = function(grp) return grp.kind == "HARMFUL" and L["Debuffs"] or L["Buffs"] end,
        off = function(grp) return not grp.show end,
        checked = function(grp) return grp.show and true or false end,
        onCheck = function(grp, v)
            grp.show = v
            apply()
        end,
        selected = function() return state.sel end,
        onSelect = function(i) state.sel = i end,
        onReorder = function(from, to)
            local grp = table.remove(Groups(), from)
            table.insert(Groups(), to, grp)
            state.sel = to
            apply()
        end,
        onRemove = function(i)
            table.remove(Groups(), i)
            if state.sel > i or state.sel > #Groups() then state.sel = math.max(1, state.sel - 1) end
            apply()
            Changed()
        end,
        empty = L["No groups."],
        rows = 6,
    }))

    list:Add(UI.Input(list, L["Name"], function() return Sel() and L[Sel().name or ""] or "" end, function(v)
        if Sel() then Sel().name = v end
        apply()
        Changed()
    end, { enableIf = SelOn }))

    -- + in the title: pick a template, the group is added and selected
    local tpl = {}
    for _, t in ipairs(ns.AURA_TEMPLATES) do tpl[#tpl + 1] = { t[1], L[t[2]] } end
    local function AddGroup(key)
        for _, t in ipairs(ns.AURA_TEMPLATES) do
            if t[1] == key then
                -- the name stays in English and shows in the language in use
                local grp = t[3]()
                -- right after the last group, the way it grows, so they do not overlap
                local last = Groups()[#Groups()]
                if last then
                    ns.FillAuraGroup(last)
                    local _, bh = ns.AuraBlockSize(last)
                    grp.anchor, grp.point, grp.relPoint = last.anchor, last.point, last.relPoint
                    grp.x, grp.growX, grp.growY = last.x, last.growX, last.growY
                    grp.y = (last.y or 0) + (last.growY == "UP" and 1 or -1) * (bh + 4)
                end
                table.insert(Groups(), grp)
                state.sel = #Groups()
            end
        end
        apply()
    end
    list:AddHeaderButton("plus", function(self) UI.Menu(self, tpl, AddGroup) end, { tip = L["Add group"] })

    -- how the icons line up, and where the block goes
    local lay = HasSel(page:Add(1, UI.Card(page.content, L["Layout"])))
    g, s = SB("fill")
    lay:Add(UI.Segmented(lay, L["Fill"], { { "rows", L["Rows"] }, { "columns", L["Columns"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("perRow")
    lay:Add(UI.Slider(lay, L["Icons per line"], 1, 20, 1, g, s, { enableIf = SelOn }))
    g, s = SB("max")
    lay:Add(UI.Slider(lay, L["Maximum"], 1, 40, 1, g, s, { enableIf = SelOn }))
    g, s = SB("spacing")
    lay:Add(UI.Slider(lay, L["Space between icons"], 0, 10, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("lineSpacing")
    lay:Add(UI.Slider(lay, L["Space between lines"], 0, 10, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("growX")
    lay:Add(UI.Segmented(lay, L["Grow"], { { "RIGHT", L["Right"] }, { "LEFT", L["Left"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("growY")
    lay:Add(UI.Segmented(lay, nil, { { "DOWN", L["Down"] }, { "UP", L["Up"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("sort")
    lay:Add(UI.Dropdown(lay, L["Order"], SORTS, g, s, { enableIf = SelOn }))

    local pos = HasSel(page:Add(1, UI.Card(page.content, L["Position"])))
    PositionRows(pos, Sel, apply, { unit = unit, enableIf = SelOn, grows = true })

    -- selected group: which auras it shows
    local filt = HasSel(page:Add(2, UI.Card(page.content, L["Filters"])))
    g, s = SB("kind")
    filt:Add(UI.Segmented(filt, L["Type"], { { "HELPFUL", L["Buffs"] }, { "HARMFUL", L["Debuffs"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("caster")
    filt:Add(UI.Segmented(filt, L["Cast by"], {
        { "all", L["Anyone"] }, { "mine", L["Me"] }, { "others", L["Others"] },
    }, g, s, { enableIf = SelOn }))
    g, s = SB("boss")
    filt:Add(UI.Check(filt, L["Only boss auras"], g, s, { enableIf = SelOn }))
    g, s = SB("dispellable")
    filt:Add(UI.Check(filt, L["Only the ones I can dispel"], g, s, { enableIf = Both(SelOn, Harmful) }))
    g, s = SB("stealable")
    filt:Add(UI.Check(filt, L["Only the ones I can purge or steal"], g, s, {
        enableIf = Both(SelOn, function() return not Harmful() end),
    }))
    local kinds = {}
    for _, kind in ipairs(ns.DISPEL_KINDS) do kinds[#kinds + 1] = { kind, L[kind] } end
    filt:Add(UI.CheckGroup(filt, L["Debuff types"], kinds,
        function(kind) return Sel() and Sel().types[kind] end,
        function(kind, v)
            if Sel() then Sel().types[kind] = v end
            apply()
        end, { columns = 2, enableIf = Both(SelOn, Harmful) }))
    g, s = SB("maxDuration")
    filt:Add(UI.Slider(filt, L["Hide longer than"], 0, 600, 5, g, s, {
        enableIf = SelOn, tip = L["Hides auras that last longer than this, and permanent ones. 0: no limit."],
        format = function(v) return v == 0 and L["No limit"] or Secs(v) end,
    }))

    -- spell list
    local spells = HasSel(page:Add(2, UI.Card(page.content, L["Spell list"], L["Show only some spells, or hide some."])))
    g, s = SB("listMode")
    spells:Add(UI.Segmented(spells, nil, {
        { "off", L["All spells"] }, { "only", L["Only these"] }, { "hide", L["All except these"] },
    }, g, s, { enableIf = SelOn }))
    local where = spells:Add(UI.Note(spells, ""))
    where.Refresh = function()
        where:SetText(Harmful() and L["Works for debuffs on enemies. On friendly units the game does not allow it (the list is ignored)."]
            or L["Works for buffs on you, your group and pets. On enemies the game does not allow it (the list is ignored)."])
    end
    table.insert(UI.widgets, where)
    local function ListOn() return SelOn() and Sel().listMode ~= "off" end
    local typed = { text = "" }
    spells:Add(UI.Input(spells, L["Add spell"], function() return typed.text end, function(v)
        local grp = Sel()
        local key = ns.SpellKeyFromInput(v)
        if grp and key then
            local have = false
            for _, k in ipairs(grp.spells) do if k == key then have = true end end
            if not have then
                table.insert(grp.spells, key)
                ns.SpellIDs(ns.SpellKeyName(key))   -- starts looking up its ranks
                apply()
            end
        end
        typed.text = ""
        Changed()
    end, { enableIf = ListOn, tip = L["Spell name (every rank) or spell ID. Press Enter."] }))
    spells:Add(UI.List(spells, {
        items = function() return Sel() and Sel().spells or {} end,
        label = ns.SpellKeyName,
        lead = "icon",
        icon = ns.SpellKeyIcon,
        secondary = function(key)
            if type(key) == "number" then return "#" .. key end
            if ns.IsSpellLookupPending(ns.SpellKeyName(key)) then return L["(looking up ranks...)"] end
        end,
        spell = ns.SpellKeyID,
        onRemove = function(i)
            local grp = Sel()
            if grp then table.remove(grp.spells, i) end
            apply()
            Changed()
        end,
        empty = L["No spells."],
        rows = 6,
        rowHeight = 22,
        enableIf = ListOn,
    }))

    local when = HasSel(page:Add(2, UI.Card(page.content, L["When to show"], L["The game decides it, so it also works in combat."])))
    g, s = SB("visibility")
    when:Add(UI.Segmented(when, nil, {
        { "always", L["Always"] }, { "combat", L["In combat"] }, { "nocombat", L["Out of combat"] },
        { "custom", L["Custom"] },
    }, g, s, { enableIf = SelOn }))
    g, s = SB("visibilityCustom")
    when:Add(UI.Input(when, L["Macro conditions"], g, s, { enableIf = Both(SelOn, Is("visibility", "custom")),
        tip = L["Like in a macro, for example: [combat] show; [@target,exists] show; hide"] }))
    g, s = SB("reaction")
    when:Add(UI.Segmented(when, L["Unit"], {
        { "any", L["Any"] }, { "friendly", L["Friendly"] }, { "hostile", L["Hostile"] },
    }, g, s, { enableIf = SelOn }))

    -- selected group: how each icon looks
    local icons = HasSel(page:Add(2, UI.Card(page.content, L["Icons"])))
    g, s = SB("size")
    icons:Add(UI.Slider(icons, L["Icon size"], 10, 48, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("height")
    icons:Add(UI.Slider(icons, L["Height"], 0, 48, 1, g, s, { enableIf = SelOn,
        format = function(v) return v == 0 and L["Square"] or Px(v) end }))
    local function HasBorder() return (Sel().borderSize or 1) > 0 end
    g, s = SB("borderSize")
    icons:Add(UI.Slider(icons, L["Border size"], 0, 4, 1, g, s, { enableIf = SelOn,
        format = function(v) return v == 0 and L["None"] or Px(v) end }))
    g, s = SB("borderByType")
    icons:Add(UI.Check(icons, L["Border colored by debuff type"], g, s, { enableIf = Both(SelOn, HasBorder, Harmful) }))
    icons:Add(UI.Swatch(icons, L["Border color"], function()
        return Sel() and Sel().borderColor or { r = 0, g = 0, b = 0, a = 1 }
    end, apply, { alpha = true, enableIf = Both(SelOn, HasBorder, function()
        return not (Harmful() and Sel().borderByType ~= false)
    end) }))
    g, s = SB("alpha")
    icons:Add(UI.Slider(icons, L["Opacity"], 0.1, 1, 0.05, g, s, { format = UI.pct, enableIf = SelOn }))
    g, s = SB("spiral")
    icons:Add(UI.Check(icons, L["Duration sweep"], g, s, { enableIf = SelOn }))
    g, s = SB("pandemic")
    icons:Add(UI.Check(icons, L["Glow when it should be renewed"], g, s, { enableIf = SelOn,
        tip = L["The last part of the duration, when casting it again does not waste time. The game decides the window."] }))
    g, s = SB("tooltip")
    icons:Add(UI.Check(icons, L["Tooltip on mouseover"], g, s, { enableIf = SelOn }))

    -- the two texts on each icon: the look rows every text has, and a place on the icon
    local function IconText(card, key, enableIf)
        local function T() return Sel() and Sel()[key] end
        TextRows(card, T, apply, { auto = true, enableIf = enableIf })
        local tg, ts = TB(T, "point", apply)
        card:Add(UI.Dropdown(card, L["Anchor"], POINTS, tg, ts, { enableIf = enableIf }))
        tg, ts = TB(T, "x", apply)
        card:Add(UI.Slider(card, L["Horizontal offset"], -30, 30, 1, tg, ts, { format = Px, enableIf = enableIf }))
        tg, ts = TB(T, "y", apply)
        card:Add(UI.Slider(card, L["Vertical offset"], -30, 30, 1, tg, ts, { format = Px, enableIf = enableIf }))
    end

    local timeCard = HasSel(page:Add(2, UI.Card(page.content, L["Time text"])))
    g, s = SB("timer")
    timeCard:Add(UI.Check(timeCard, L["Show time left"], g, s, { enableIf = SelOn }))
    TimeRows(timeCard, function() return Sel() and Sel().timeFmt end, apply, { style = true, decimals = true,
        warn = true, hide = true, enableIf = Both(SelOn, Is("timer", true)) })
    IconText(timeCard, "timerText", Both(SelOn, Is("timer", true)))

    local stackCard = HasSel(page:Add(2, UI.Card(page.content, L["Stack count"])))
    IconText(stackCard, "stackText", SelOn)
end

-- Icons: every icon with its switch on the left, the chosen one's look and place on the right
function Tabs.icons(page, unit)
    local state = { sel = ns.ICON_KEYS[1] }
    local apply = function() ns.ApplyUnit(unit) end
    local function Cfg(key)
        local icons = U(unit).icons
        if not icons[key] then
            icons[key] = { show = false, point = "CENTER", relPoint = "TOP", x = 0, y = 0, size = 16, alpha = 1 }
        end
        return icons[key]
    end
    local function Sel() return Cfg(state.sel) end
    -- the frames an icon can show on (nil: any)
    local function Fits(key)
        local only = ns.ICON_ONLY[key]
        return not only or only[1][unit] or false
    end

    local list = page:Add(1, UI.Card(page.content, L["Status icons"], L["Click to edit"]))
    list:Add(UI.List(list, {
        items = function() return ns.ICON_KEYS end,
        label = function(key) return L[ns.ICON_NAMES[key]] end,
        secondary = function(key)
            local only = ns.ICON_ONLY[key]
            return only and L[only[2]] or ""
        end,
        off = function(key) return not Fits(key) end,
        checked = function(key) return Cfg(key).show and true or false end,
        onCheck = function(key, v)
            Cfg(key).show = v
            state.sel = key
            apply()
        end,
        selected = function(key) return key == state.sel end,
        onSelect = function(_, key) state.sel = key end,
        rows = #ns.ICON_KEYS,
    }))

    local function On() return Sel().show end
    local look = page:Add(2, UI.Card(page.content, L["Look"]))
    local g, s = TB(Sel, "size", apply)
    look:Add(UI.Slider(look, L["Size"], 8, 40, 1, g, s, { format = Px, enableIf = On }))
    g, s = TB(Sel, "alpha", apply)
    look:Add(UI.Slider(look, L["Opacity"], 0.1, 1, 0.05, g, s, { format = UI.pct, enableIf = On }))

    local place = page:Add(2, UI.Card(page.content, L["Position"]))
    PositionRows(place, Sel, apply, { unit = unit, enableIf = On, pieceLabel = L["Point of the icon"] })

    -- PvP: the countdown before the flag drops (only the player has one)
    local function PvP() return Cfg("pvp") end
    local function TimerOn() return PvP().show and PvP().timer end
    local timer = page:Add(2, UI.Card(page.content, L["PvP countdown"]))
    timer.showIf = function() return state.sel == "pvp" and unit == "player" end
    g, s = TB(PvP, "timer", apply)
    timer:Add(UI.Check(timer, L["Show countdown"], g, s, { enableIf = function() return PvP().show end }))
    TimeRows(timer, function() return PvP().timeFmt end, apply, { style = true, warn = true, enableIf = TimerOn })
    PositionRows(timer, function() return PvP().timerPos end, apply, { text = true, enableIf = TimerOn })
    TextRows(timer, function() return PvP().timerStyle end, apply, { auto = true, enableIf = TimerOn })
end


-- Cast bar: settings, bar look, the two texts and position
function Tabs.castbar(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local function CB() return U(unit).castbar end
    local function On() return CB().enabled end

    local card = page:Add(1, UI.Card(page.content, L["Cast bar"], L["Colors by state in the Colors page."]))
    local g, s = Bind(unit, "castbar", "enabled")
    card:Add(UI.Check(card, L["Show cast bar"], g, s))
    if unit == "player" or unit == "pet" then
        g, s = Bind(unit, "castbar", "hideBlizzard")
        card:Add(UI.Check(card, L["Hide the game's cast bar"], g, s, {
            enableIf = On,
        }))
    end
    g, s = Bind(unit, "castbar", "icon")
    card:Add(UI.Check(card, L["Spell icon"], g, s, { enableIf = On }))
    g, s = Bind(unit, "castbar", "height")
    card:Add(UI.Slider(card, L["Height"], 8, 40, 1, g, s, { format = Px, enableIf = On }))
    g, s = Bind(unit, "castbar", "width")
    card:Add(UI.Slider(card, L["Width"], 0, 500, 1, g, s, { enableIf = On,
        format = function(v) return v == 0 and L["Same as frame"] or Px(v) end }))
    g, s = Bind(unit, "castbar", "fadeTime")
    card:Add(UI.Slider(card, L["Stay after it ends"], 0, 2, 0.1, g, s, { enableIf = On,
        format = function(v) return v == 0 and L["No"] or ("%.1f s"):format(v) end,
        tip = L["Shows for a moment whether the cast was completed or interrupted."] }))
    card:Add(UI.Note(card, L["Enemy casts: if the game hides their times, the bar is shown full with the spell name."]))

    if unit == "player" then
        card = page:Add(1, UI.Card(page.content, L["Your casts"]))
        g, s = Bind(unit, "castbar", "latency")
        card:Add(UI.Check(card, L["Show latency"], g, s, { enableIf = On,
            tip = L["The end of the bar the server takes to answer: you can start the next spell there."] }))
        card:Add(UI.Swatch(card, L["Latency color"], function() return CB().latencyColor end, apply,
            { alpha = true, enableIf = function() return On() and CB().latency end }))
        g, s = Bind(unit, "castbar", "ticks")
        card:Add(UI.Check(card, L["Channel ticks"], g, s, { enableIf = On }))
        card:Add(UI.Swatch(card, L["Tick color"], function() return CB().tickColor end, apply,
            { alpha = true, enableIf = function() return On() and CB().ticks end }))
        g, s = Bind(unit, "castbar", "batch")
        card:Add(UI.Check(card, L["One bar when crafting many"], g, s, { enableIf = On }))
    end

    BarCard(page, 1, L["Bar look"], function() return CB().style end, apply, { box = true,
        autoLabel = L["By state"], enableIf = On,
    })

    -- the two texts and the position: one card, a heading for each part
    card = page:Add(2, UI.Card(page.content, L["Texts and position"]))
    card:Add(UI.Heading(card, L["Spell name"]))
    TextRows(card, function() return CB().nameText end, apply, { auto = true, enableIf = On })
    card:Add(UI.Heading(card, L["Time text"]))
    g, s = Bind(unit, "castbar", "timeFormat")
    card:Add(UI.Segmented(card, L["Time"], { { "left", "1.2" }, { "both", "1.2 / 3.0" } }, g, s, { enableIf = On }))
    TimeRows(card, function() return CB().timeFmt end, apply, { decimals = true, warn = true, enableIf = On })
    TextRows(card, function() return CB().timeText end, apply, { auto = true, enableIf = On })
    card:Add(UI.Heading(card, L["Position"]))
    PositionRows(card, CB, apply, { unit = unit, enableIf = On, pieceLabel = L["Point of the bar"] })
end

-- Extras. First what changes the frame (fading | threat border), then one
-- section per extra bar and the combat text: its settings on the left, its
-- look and text on the right, level with them. Every bar: Show, what it
-- does, Height, position | look | text.
function Tabs.extras(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local player = unit == "player"

    -- fading
    local card = page:Add(1, UI.Card(page.content, L["Fading"], L["The frame becomes transparent when any checked situation happens."]))
    local g, s
    if not player then
        g, s = Bind(unit, "fader", "range")
        card:Add(UI.Check(card, L["Out of range"], g, s, { tip = L["Out of range: farther than about 28 yards."] }))
    end
    g, s = Bind(unit, "fader", "combat")
    card:Add(UI.Check(card, L["Out of combat"], g, s))
    if not player then
        g, s = Bind(unit, "fader", "phase")
        card:Add(UI.Check(card, L["In another phase"], g, s))
        g, s = Bind(unit, "fader", "hostility")
        card:Add(UI.Segmented(card, L["By reaction"], {
            { "none", L["Never"] }, { "friendly", L["Friendly"] }, { "hostile", L["Hostile"] },
        }, g, s, { tip = L["Fades friendly or hostile units."] }))
    end
    g, s = Bind(unit, "fader", "alpha")
    card:Add(UI.Slider(card, L["Opacity when faded"], 0, 1, 0.05, g, s, { format = UI.pct }))

    -- threat: the border, and (on other units) the bar
    card = page:Add(2, UI.Card(page.content, L["Threat border"], player
        and L["Border with your highest threat on any enemy."] or L["Border with your threat on this unit."]))
    g, s = Bind(unit, "threat", "enabled")
    card:Add(UI.Check(card, L["Show threat border"], g, s))
    g, s = Bind(unit, "threat", "width")
    card:Add(UI.Slider(card, L["Thickness"], 1, 6, 1, g, s, {
        format = Px, enableIf = function() return U(unit).threat.enabled end,
    }))

    if not player then
        local function TBr() return U(unit).threatBar end
        local function TBOn() return TBr().enabled end
        page:AddSection()
        card = page:Add(1, UI.Card(page.content, L["Threat bar"], L["Your threat on this unit, from 0 to 100 %."]))
        g, s = Bind(unit, "threatBar", "enabled")
        card:Add(UI.Check(card, L["Show threat bar"], g, s))
        g, s = Bind(unit, "threatBar", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = TBOn }))
        PositionRows(card, TBr, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = TBOn })
        BarCard(page, 2, L["Threat bar look"], function() return TBr().style end, apply, { box = true,
            autoLabel = L["Threat status"], enableIf = TBOn })
        card = page:Add(2, UI.Card(page.content, L["Threat bar text"]))
        g, s = Bind(unit, "threatBar", "text")
        card:Add(UI.Check(card, L["Show percentage"], g, s, { enableIf = TBOn }))
        TextRows(card, function() return TBr().textStyle end, apply, {
            auto = true, enableIf = function() return TBOn() and TBr().text end })
    end

    if player then
        local function GC() return U(unit).gcd end
        local function GCOn() return GC().enabled end
        page:AddSection()
        card = page:Add(1, UI.Card(page.content, L["Global cooldown"]))
        g, s = Bind(unit, "gcd", "enabled")
        card:Add(UI.Check(card, L["Show global cooldown"], g, s))
        g, s = Bind(unit, "gcd", "fillUp")
        card:Add(UI.Check(card, L["Fill up"], g, s, { enableIf = GCOn,
            tip = L["The bar fills while the global cooldown runs, instead of emptying."] }))
        g, s = Bind(unit, "gcd", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = GCOn }))
        PositionRows(card, GC, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = GCOn })
        BarCard(page, 2, L["Global cooldown look"], function() return GC().style end, apply, { box = true, enableIf = GCOn })

        local function SW() return U(unit).swing end
        local function SWOn() return SW().enabled end
        page:AddSection()
        card = page:Add(1, UI.Card(page.content, L["Swing timer"], L["Time until your next melee swing or ranged shot."]))
        g, s = Bind(unit, "swing", "enabled")
        card:Add(UI.Check(card, L["Show swing timer"], g, s))
        local SWING_BARS = { { "main", L["Main hand"] }, { "off", L["Off hand"] },
            { "ranged", L["Ranged (Auto Shot, wands, thrown)"] } }
        local FILLS = { { "edge", L["From one end"] }, { "middle", L["Toward the middle"] } }
        local function BarOn(kind) return function() return SWOn() and SW()[kind].show end end
        local function MeleeOn() return SWOn() and (SW().main.show or SW().off.show) end
        for _, k in ipairs(SWING_BARS) do
            g, s = TB(function() return SW()[k[1]] end, "show", apply)
            card:Add(UI.Check(card, k[2], g, s, { enableIf = SWOn }))
        end

        card = page:Add(1, UI.Card(page.content, L["Melee swing bars"]))
        g, s = TB(function() return SW().main end, "fill", apply)
        card:Add(UI.Segmented(card, L["Main hand fill"], FILLS, g, s, { enableIf = BarOn("main") }))
        g, s = TB(function() return SW().off end, "fill", apply)
        card:Add(UI.Segmented(card, L["Off hand fill"], FILLS, g, s, { enableIf = BarOn("off") }))
        g, s = Bind(unit, "swing", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = MeleeOn }))
        g, s = Bind(unit, "swing", "gap")
        card:Add(UI.Slider(card, L["Space between bars"], 0, 10, 1, g, s, { format = Px, enableIf = MeleeOn }))
        PositionRows(card, SW, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = MeleeOn })

        local function RG() return SW().ranged end
        card = page:Add(1, UI.Card(page.content, L["Ranged swing bar"]))
        g, s = TB(RG, "fill", apply)
        card:Add(UI.Segmented(card, L["Fill"], FILLS, g, s, { enableIf = BarOn("ranged") }))
        g, s = TB(RG, "height", apply)
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = BarOn("ranged") }))
        PositionRows(card, RG, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true,
            enableIf = BarOn("ranged") })

        BarCard(page, 2, L["Swing timer look"], function() return SW().style end, apply, { box = true,
            enableIf = SWOn, colors = function(c)
                for _, k in ipairs({ { "main", L["Main hand"] }, { "off", L["Off hand"] }, { "ranged", L["Ranged"] } }) do
                    c:Add(UI.Swatch(c, k[2], function() return SW()[k[1]].color end, apply, { enableIf = BarOn(k[1]) }))
                end
            end })
        card = page:Add(2, UI.Card(page.content, L["Swing timer text"]))
        -- one text per bar: pick the bar, then its settings
        local textOf = { sel = "main" }
        local function TB_() return SW()[textOf.sel] end
        card:Add(UI.Segmented(card, L["Bar"], { { "main", L["Main hand"] }, { "off", L["Off hand"] }, { "ranged", L["Ranged"] } },
            function() return textOf.sel end, function(v) textOf.sel = v end, { enableIf = SWOn }))
        local function BarShown() return SWOn() and TB_().show end
        local function TextOn() return BarShown() and TB_().text end
        g, s = TB(TB_, "text", apply)
        card:Add(UI.Check(card, L["Show time left"], g, s, { enableIf = BarShown }))
        TimeRows(card, function() return TB_().timeFmt end, apply, { decimals = true, enableIf = TextOn })
        PositionRows(card, function() return TB_().textPos end, apply, { text = true, enableIf = TextOn })
        TextRows(card, function() return TB_().textStyle end, apply, { auto = true, enableIf = TextOn })

        local function XP() return U(unit).xp end
        local function On() return XP().enabled end
        page:AddSection()
        card = page:Add(1, UI.Card(page.content, L["Experience / reputation"]))
        g, s = Bind(unit, "xp", "enabled")
        card:Add(UI.Check(card, L["Show experience bar"], g, s))
        g, s = Bind(unit, "xp", "mode")
        card:Add(UI.Segmented(card, L["Shows"], {
            { "auto", L["Automatic"] }, { "xp", L["Experience"] }, { "rep", L["Reputation"] },
        }, g, s, { enableIf = On, tip = L["Automatic: experience until max level, then the reputation you watch."] }))
        g, s = Bind(unit, "xp", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = On }))
        PositionRows(card, XP, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = On })
        BarCard(page, 2, L["Experience bar look"], function() return XP().style end, apply, { box = true, enableIf = On })
        card = page:Add(2, UI.Card(page.content, L["Experience text"]))
        g, s = Bind(unit, "xp", "text")
        card:Add(UI.Check(card, L["Show numbers"], g, s, { enableIf = On }))
        TextRows(card, function() return XP().textStyle end, apply, {
            auto = true, enableIf = function() return On() and XP().text end })
    end

    -- combat text: a text, so one anchor and the text look
    local function CT() return U(unit).combatText end
    local function CTOn() return CT().enabled end
    page:AddSection()
    card = page:Add(1, UI.Card(page.content, L["Combat text"], L["Damage, heals and misses over the frame."]))
    g, s = Bind(unit, "combatText", "enabled")
    card:Add(UI.Check(card, L["Show combat text"], g, s))
    g, s = Bind(unit, "combatText", "duration")
    card:Add(UI.Slider(card, L["Duration"], 0.5, 4, 0.1, g, s, { enableIf = CTOn, format = function(v) return ("%.1f s"):format(v) end }))
    PositionRows(card, CT, apply, { unit = unit, text = true, enableIf = CTOn })
    card = page:Add(2, UI.Card(page.content, L["Combat text look"]))
    TextRows(card, function() return CT().textStyle end, apply, { enableIf = CTOn })
end

-- Class: what only some classes use. The tab only shows on the frames
-- where your class has something (the settings stay saved for the others).
local CLASS_TAB = {
    player = { DRUID = true, SHAMAN = true, HUNTER = true },   -- druid mana, totems, Auto Shot aiming zone
    target = { ROGUE = true, DRUID = true },    -- combo points
}
local function HasClassTab(unit)
    local _, class = UnitClass("player")
    return CLASS_TAB[unit] and CLASS_TAB[unit][class] or false
end

function Tabs.class(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local _, class = UnitClass("player")
    local g, s, card

    if unit == "target" then
        local function Combo() return U(unit).combo end
        local function On() return Combo().enabled end
        card = page:Add(1, UI.Card(page.content, L["Combo points"]))
        g, s = Bind(unit, "combo", "enabled")
        card:Add(UI.Check(card, L["Show combo points"], g, s))
        g, s = Bind(unit, "combo", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = On }))
        PositionRows(card, Combo, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = On })
        BarCard(page, 2, L["Combo points look"], function() return Combo().style end, apply, { box = true, enableIf = On })
    end

    if unit == "player" and class == "DRUID" then
        local function AM() return U(unit).altMana end
        local function AMOn() return AM().enabled end
        card = page:Add(1, UI.Card(page.content, L["Druid mana"], L["Your mana while in bear or cat form."]))
        g, s = Bind(unit, "altMana", "enabled")
        card:Add(UI.Check(card, L["Show druid mana"], g, s))
        g, s = Bind(unit, "altMana", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 24, 1, g, s, { format = Px, enableIf = AMOn }))
        PositionRows(card, AM, apply, { unit = unit, pieceLabel = L["Point of the bar"], width = true, enableIf = AMOn })
        BarCard(page, 2, L["Druid mana look"], function() return AM().style end, apply, { box = true,
            autoLabel = L["Power type"], enableIf = AMOn })
        card = page:Add(2, UI.Card(page.content, L["Druid mana text"]))
        g, s = Bind(unit, "altMana", "text")
        card:Add(UI.Check(card, L["Show numbers"], g, s, { enableIf = AMOn }))
        TextRows(card, function() return AM().textStyle end, apply, {
            auto = true, enableIf = function() return AMOn() and AM().text end })
    end

    if unit == "player" and class == "HUNTER" then
        local function SW() return U(unit).swing end
        local function AimOn() return SW().enabled and SW().ranged.show end
        card = page:Add(1, UI.Card(page.content, L["Auto Shot aiming zone"],
            L["The end of the ranged swing bar where moving or starting a cast delays the next Auto Shot."]))
        g, s = Bind(unit, "swing", "aim")
        card:Add(UI.Check(card, L["Show aiming zone"], g, s, { enableIf = AimOn }))
        g, s = Bind(unit, "swing", "aimTime")
        card:Add(UI.Slider(card, L["Aiming time (0.50 s recommended)"], 0.3, 1, 0.05, g, s, {
            format = function(v) return ("%.2f s"):format(v) end,
            enableIf = function() return AimOn() and SW().aim end,
            tip = L["Recommended: 0.50 s, the Auto Shot wind-up before haste. Haste shortens it and your latency is added. The game does not report it, so it is an estimate."] }))
        card:Add(UI.Swatch(card, L["Color"], function() return SW().aimColor end, apply,
            { alpha = true, enableIf = function() return AimOn() and SW().aim end }))
    end

    if unit == "player" and class == "SHAMAN" then
        local function TOn() return U(unit).totems.enabled end
        card = page:Add(1, UI.Card(page.content, L["Totems"], L["The game's totem bar, moved under your frame."]))
        g, s = Bind(unit, "totems", "enabled")
        card:Add(UI.Check(card, L["Move the totem bar"], g, s, { tip = L["Turning it off brings it back after /reload."] }))
        g, s = Bind(unit, "totems", "scale")
        card:Add(UI.Slider(card, L["Scale"], 0.5, 2, 0.05, g, s, { format = UI.pct, enableIf = TOn }))
        PositionRows(card, function() return U(unit).totems end, apply, { unit = unit, pieceLabel = L["Point of the totems"], enableIf = TOn })
    end
end

-------------------------------------------------------------------------------
-- Colors page: colors shared by every frame
-------------------------------------------------------------------------------
local CLASS_NAMES = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function ColorsPage(container)
    PageTitle(container, L["Colors"])
    local holder = CreateFrame("Frame", nil, container)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetPoint("BOTTOMRIGHT")
    local page = UI.Page(holder, 2)

    local function ApplyColors()
        ns.ResetGradient()
        ns.ApplyAll()
    end
    -- one swatch per key of a color group; each one can go back to its
    -- default on its own (the reset icon shows while it differs)
    local function Swatches(card, group, list, alpha)
        for _, e in ipairs(list) do
            card:Add(UI.Swatch(card, e[2], function() return ns.P.colors[group][e[1]] end, ApplyColors, {
                alpha = alpha,
                default = function() return ns.DEFAULTS.colors[group] and ns.DEFAULTS.colors[group][e[1]] end,
            }))
        end
    end

    local card = page:Add(1, UI.Card(page.content, L["Classes"]))
    local classes = {}
    for _, token in ipairs(CLASS_ORDER) do classes[#classes + 1] = { token, L[CLASS_NAMES[token]] } end
    Swatches(card, "class", classes)

    card = page:Add(1, UI.Card(page.content, L["Power"]))
    Swatches(card, "power", { { "MANA", L["Mana"] }, { "RAGE", L["Rage"] }, { "ENERGY", L["Energy"] }, { "FOCUS", L["Focus"] } })

    card = page:Add(1, UI.Card(page.content, L["Debuff types"], L["Border of the debuff icons."]))
    Swatches(card, "dispel", { { "Magic", L["Magic"] }, { "Curse", L["Curse"] }, { "Disease", L["Disease"] }, { "Poison", L["Poison"] } })

    card = page:Add(2, UI.Card(page.content, L["Reaction and state"], L["Health of units that are not players, and special states."]))
    Swatches(card, "reaction", { { "hostile", L["Hostile"] }, { "neutral", L["Neutral"] }, { "friendly", L["Friendly"] } })
    Swatches(card, "state", { { "dead", L["Dead"] }, { "offline", L["Offline"] }, { "tapped", L["Tapped by others"] } })

    card = page:Add(2, UI.Card(page.content, L["Health gradient"], L["Used by health bars set to Gradient."]))
    Swatches(card, "gradient", { { "low", L["Low health"] }, { "mid", L["Half health"] }, { "high", L["Full health"] } })

    card = page:Add(2, UI.Card(page.content, L["Incoming heals and shields"]))
    Swatches(card, "prediction", { { "heal", L["Incoming heals"] }, { "absorb", L["Shields"] } }, true)

    card = page:Add(2, UI.Card(page.content, L["Cast bar"]))
    Swatches(card, "cast", {
        { "cast", L["Casting"] }, { "channel", L["Channeling"] }, { "locked", L["Cannot be interrupted"] },
        { "interrupted", L["Interrupted"] }, { "done", L["Completed"] },
    })

    card = page:Add(2, UI.Card(page.content, L["Threat"], L["Border and threat bar."]))
    Swatches(card, "threat", { { "high", L["About to pull aggro"] }, { "insecure", L["Tanking, not secure"] }, { "tanking", L["Tanking"] } })

    card = page:Add(1, UI.Card(page.content, L["Highlight"], L["Also the glow of auras that should be renewed."]))
    Swatches(card, "highlight", { { "mouseover", L["Mouseover"] }, { "target", L["Your target"] } }, true)

    card = page:Add(1, UI.Card(page.content, L["Reset"]))
    local reset = UI.Buttons(card, {
        { L["Reset every color"], function()
            ns.P.colors = ns.DeepCopy(ns.DEFAULTS.colors)
            ApplyColors()
            Changed()
        end, "danger" },
    })
    UI.Confirm(reset.buttons[1])
    card:Add(reset)
end

-- The tabs whose settings can be copied between frames (Core: ns.COPY_SECTIONS)
local COPY_PARTS = {
    { "frame", "Frame" }, { "bars", "Bars" }, { "texts", "Texts" }, { "auras", "Auras" },
    { "icons", "Icons" }, { "castbar", "Cast bar" }, { "extras", "Extras" },
}

local TAB_LIST = {
    { "frame", "Frame" }, { "bars", "Bars" }, { "texts", "Texts" }, { "auras", "Auras" },
    { "icons", "Icons" }, { "castbar", "Cast bar" }, { "extras", "Extras" }, { "class", "Class" }, { "copy", "Copy" },
}

-------------------------------------------------------------------------------
-- Copy: the settings of another frame into this one, by tab
-------------------------------------------------------------------------------
local UNIT_ORDER = { "player", "target", "targettarget", "targettargettarget", "focus", "pet", "party" }
local undo          -- { unit, from, data, profile }: the last copy, to take it back

function Tabs.copy(page, unit)
    local state = { from = unit == "player" and "target" or "player", parts = {} }
    for _, t in ipairs(COPY_PARTS) do state.parts[t[1]] = true end
    local function CanCopy()
        for _, on in pairs(state.parts) do if on then return true end end
        return false
    end
    local function CanUndo() return undo and undo.unit == unit and undo.profile == ns.profileName end

    local card = page:Add(1, UI.Card(page.content, L["Copy from another frame"],
        L["The checked tabs replace the ones of this frame."]))
    card:Add(UI.Dropdown(card, L["Copy from"], function()
        local out = {}
        for _, u in ipairs(UNIT_ORDER) do
            if u ~= unit then out[#out + 1] = { u, L[UNIT_NAMES[u]] } end
        end
        return out
    end, function() return state.from end, function(v) state.from = v end))
    local parts = {}
    for i, t in ipairs(COPY_PARTS) do parts[i] = { t[1], L[t[2]] } end
    card:Add(UI.CheckGroup(card, L["Tabs to copy"], parts,
        function(key) return state.parts[key] end,
        function(key, v) state.parts[key] = v end, { columns = 2 }))
    card:Add(UI.Buttons(card, {
        { L["Select all"], function()
            for k in pairs(state.parts) do state.parts[k] = true end
            Changed()
        end },
        { L["Select none"], function()
            for k in pairs(state.parts) do state.parts[k] = false end
            Changed()
        end },
    }))
    card:Add(UI.Buttons(card, {
        { L["Copy"], function()
            if not CanCopy() then return end
            undo = { unit = unit, from = state.from, data = ns.DeepCopy(U(unit)), profile = ns.profileName }
            ns.CopyUnit(state.from, unit, state.parts)
            page.ReloadUnit()
        end, "accent" },
    }, { enableIf = CanCopy }))

    card = page:Add(2, UI.Card(page.content, L["Not copied"]))
    card:Add(UI.Note(card, L["The position, Enabled, the Blizzard frame and what only this frame has (combo points, experience bar, party layout...) stay as they are."]))

    card = page:Add(2, UI.Card(page.content, L["Undo"]))
    local note = card:Add(UI.Note(card, ""))
    note.Refresh = function()
        note:SetText(CanUndo()
            and L["Back to the settings this frame had before copying from"] .. " |cffffffff" .. L[UNIT_NAMES[undo.from]] .. "|r."
            or L["Nothing to undo."])
    end
    table.insert(UI.widgets, note)
    card:Add(UI.Buttons(card, {
        { L["Undo copy"], function()
            if not CanUndo() then return end
            ns.SetUnitSettings(unit, undo.data)
            undo = nil
            page.ReloadUnit()
        end },
    }, { enableIf = function() return CanUndo() and true or false end }))
end

-------------------------------------------------------------------------------
-- Unit page: title, on/off, reset and tabs
-------------------------------------------------------------------------------
local unitTabs = {}     -- unit -> its tab bar (to open a tab from outside)

local function UnitPage(container, unit)
    PageTitle(container, L[PAGE_TITLES[unit] or UNIT_NAMES[unit]])

    local tabPages = {}
    -- the unit's settings were replaced as a whole: lists start at their first item
    local function Reload()
        for _, p in pairs(tabPages) do if p.Reload then p.Reload() end end
        Changed()
    end

    local reset = UI.Button(container, L["Reset frame"], 100, 20, function()
        ns.ResetUnit(unit)
        if undo and undo.unit == unit then undo = nil end
        Reload()
    end, "danger")
    reset:SetPoint("TOPRIGHT", -12, 0)
    UI.Confirm(reset)
    UI.Tip(reset, L["Reset frame"], L["Back to the default settings of this frame."])

    local enabled = UI.Check(container, L["Enabled"], function() return U(unit).enabled end, function(v)
        U(unit).enabled = v
        ns.ApplyUnit(unit)
        ns.HideBlizzard()
    end)
    enabled:SetSize(90, 18)
    enabled.OnWidth(90)
    enabled:SetPoint("RIGHT", reset, "LEFT", -12, 0)

    local holder = CreateFrame("Frame", nil, container)
    holder:SetPoint("TOPLEFT", 0, -64)
    holder:SetPoint("BOTTOMRIGHT")

    local labels = {}
    for _, t in ipairs(TAB_LIST) do
        if t[1] ~= "class" or HasClassTab(unit) then labels[#labels + 1] = { t[1], L[t[2]] } end
    end
    local tabs = UI.Tabs(container, labels, function(key)
        for _, p in pairs(tabPages) do p:Hide() end
        local p = tabPages[key]
        if not p then
            p = UI.Page(holder, 2)
            p.ReloadUnit = Reload
            Tabs[key](p, unit)
            tabPages[key] = p
        end
        p:Show()
        UI.RefreshAll()
    end)
    tabs:SetPoint("TOPLEFT", 0, -30)
    tabs:SetPoint("TOPRIGHT", -12, -30)
    tabs:Select("frame")
    unitTabs[unit] = tabs
end

-------------------------------------------------------------------------------
-- General page
-------------------------------------------------------------------------------
local function GeneralPage(container)
    PageTitle(container, L["General"])
    local holder = CreateFrame("Frame", nil, container)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetPoint("BOTTOMRIGHT")
    local page = UI.Page(holder, 2)

    local card = page:Add(1, UI.Card(page.content, L["Appearance"], L["For every frame."]))
    local g, s = GBind("media", "texture")
    card:Add(UI.Dropdown(card, L["Bar texture"], function()
        local out = {}
        for _, o in ipairs(ns.TextureList()) do out[#out + 1] = { o[1], o[2], nil, o[1] } end
        return out
    end, g, s))
    g, s = GBind("media", "font")
    card:Add(UI.Dropdown(card, L["Font"], function()
        local out = {}
        for _, o in ipairs(ns.FontList()) do out[#out + 1] = { o[1], o[2], o[1] } end
        return out
    end, g, s))
    g, s = GBind("media", "outline")
    card:Add(UI.Segmented(card, L["Text outline"], {
        { "", L["None"] }, { "OUTLINE", L["Thin"] }, { "THICKOUTLINE", L["Thick"] },
    }, g, s))
    g, s = GBind("sounds", "target")
    card:Add(UI.Check(card, L["Target sounds"], g, s, { tip = L["The game sounds when you pick or lose a target."] }))
    g, s = GBind("smooth")
    card:Add(UI.Check(card, L["Smooth bars"], g, s, { tip = L["Health and power bars slide instead of jumping (only if the game supports it)."] }))

    card = page:Add(2, UI.Card(page.content, L["Language"]))
    card:Add(UI.Segmented(card, nil, { { "enUS", "English" }, { "esES", "Español" } },
        function() return ns.db.language or "enUS" end,
        function(v)
            ns.db.language = v
            ns.SetLanguage(v)
        end))
    card:Add(UI.Note(card, L["Type /reload to translate everything."]))

    card = page:Add(2, UI.Card(page.content, L["Tools"]))
    card:Add(UI.Buttons(card, {
        { L["Test mode"], function() ns.SetTestMode(not ns.testMode) C_Timer.After(0, Changed) end, nil,
            L["Shows every frame with sample data, so you can see how it looks."] },
        { L["Unlock frames"], function() ns.SetUnlocked(not ns.unlocked) C_Timer.After(0, Changed) end, nil,
            L["Drag the frames on screen. Lock them again when you finish."] },
    }))
    card:Add(UI.Check(card, L["Minimap button"], function()
        return not (ns.db.minimap and ns.db.minimap.hide)
    end, function(v)
        ns.db.minimap = ns.db.minimap or { angle = 200 }
        ns.db.minimap.hide = not v
        ns.UpdateMinimapButton()
    end, { tip = L["Click: options · right click: test mode · drag: move it."] }))
    card:Add(UI.Note(card, L["Commands: /sigil (this window), /sigil help."]))
end

-------------------------------------------------------------------------------
-- Profiles page
-------------------------------------------------------------------------------
local function ProfileList(excludeCurrent)
    local out = {}
    for name in pairs(ns.db.profiles) do
        if not (excludeCurrent and name == ns.profileName) then out[#out + 1] = { name, name } end
    end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

local function ProfilesPage(container)
    PageTitle(container, L["Profiles"])
    local holder = CreateFrame("Frame", nil, container)
    holder:SetPoint("TOPLEFT", 0, -34)
    holder:SetPoint("BOTTOMRIGHT")
    local page = UI.Page(holder, 2)

    local card = page:Add(1, UI.Card(page.content, L["This character"], L["Each character uses one profile. Several characters can share it."]))
    card:Add(UI.Dropdown(card, L["Profile in use"], function() return ProfileList(false) end,
        function() return ns.profileName end, function(v) ns.UseProfile(v) Changed() end))
    local newName = { text = "" }
    card:Add(UI.Input(card, L["New profile"], function() return newName.text end, function(v)
        v = strtrim(v or "")
        if v == "" then return end
        ns.UseProfile(v)
        newName.text = ""
        Changed()
    end, { tip = L["Type a name and press Enter: a new profile with the default settings."] }))

    card = page:Add(1, UI.Card(page.content, L["Copy and reset"]))
    local copy = { from = nil }
    card:Add(UI.Dropdown(card, L["Copy from"], function() return ProfileList(true) end,
        function() return copy.from end, function(v) copy.from = v end))
    card:Add(UI.Buttons(card, {
        { L["Copy into this profile"], function()
            if copy.from then ns.CopyProfile(copy.from) Changed() end
        end },
    }, { enableIf = function() return copy.from ~= nil end }))
    local reset = UI.Buttons(card, {
        { L["Reset this profile"], function() ns.ResetProfile() Changed() end, "danger" },
    })
    UI.Confirm(reset.buttons[1])
    card:Add(reset)

    local del = { name = nil }
    card:Add(UI.Dropdown(card, L["Delete profile"], function() return ProfileList(true) end,
        function() return del.name end, function(v) del.name = v end))
    local delBtn = UI.Buttons(card, {
        { L["Delete"], function()
            if del.name then ns.DeleteProfile(del.name) del.name = nil Changed() end
        end, "danger" },
    }, { enableIf = function() return del.name ~= nil end })
    UI.Confirm(delBtn.buttons[1])
    card:Add(delBtn)

    card = page:Add(2, UI.Card(page.content, L["Share"], L["Export this profile as text, or paste one to import it."]))
    local box = card:Add(UI.CodeBox(card, 200))
    local status = card:Add(UI.Note(card, ""))
    card:Add(UI.Buttons(card, {
        { L["Export"], function()
            box.edit:SetText(ns.ExportProfile())
            box.edit:SetFocus()
            box.edit:HighlightText()
            status:SetText(L["Copied to the box: press Ctrl+C."])
            page:Layout()
        end, "accent" },
        { L["Import"], function()
            UI.Dialog(L["This replaces every setting of the profile in use. Continue?"], L["Import"], function()
                local ok, err = ns.ImportProfile(box.edit:GetText())
                status:SetText(ok and ("|cff6bd66b" .. L["Profile imported."] .. "|r") or ("|cffff6b61" .. err .. "|r"))
                Changed()
            end)
        end },
    }))
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local function Build()
    win = UI.Window({ name = "SigilOptions", title = "Sigil", version = ns.version,
        logo = "Interface\\AddOns\\Sigil\\Media\\Icon" })

    win:AddHeaderButton(L["Unlock frames"], function() ns.SetUnlocked(not ns.unlocked) C_Timer.After(0, Changed) end,
        function() return ns.unlocked end, L["Drag the frames on screen. Lock them again when you finish."])
    win:AddHeaderButton(L["Test mode"], function() ns.SetTestMode(not ns.testMode) C_Timer.After(0, Changed) end,
        function() return ns.testMode end, L["Shows every frame with sample data, so you can see how it looks."])

    win:AddNav("general", L["General"], GeneralPage)
    win:AddSection(L["FRAMES"])
    for _, unit in ipairs(UNIT_ORDER) do
        win:AddNav(unit, L[UNIT_NAMES[unit]], function(container) UnitPage(container, unit) end,
            function() return ns.P and U(unit).enabled end)
    end
    win:AddSection(" ")
    win:AddNav("colors", L["Colors"], ColorsPage)
    win:AddNav("profiles", L["Profiles"], ProfilesPage)

    UI.OnRefresh = function()
        win:SetSubtitle(L["Profile:"] .. " |cffffffff" .. (ns.profileName or "") .. "|r")
        if InCombatLockdown() then
            win:SetStatus("|cffffb347" .. L["In combat: frame changes will be applied when combat ends."] .. "|r")
        else
            win:SetStatus(L["Changes are saved and applied at once."])
        end
    end
    local events = CreateFrame("Frame", nil, win)
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function() if win:IsShown() then UI.OnRefresh() end end)

    win:Select("general")
end

function ns.ToggleOptions()
    if not win then
        Build()
        UI.RefreshAll()
        return
    end
    win:Toggle()
end

-- Opens the window on a frame's page and tab (clicking a box while unlocked)
function ns.OpenOptions(unit, tab)
    if not win then Build() end
    win:Show()
    win:Select(unit)
    local tabs = unitTabs[unit]
    if tabs and tab and tabs.buttons[tab] then tabs:Select(tab) end
    UI.RefreshAll()
end

-- After dragging a frame, its position sliders show the new values
function ns.OnFrameMoved()
    if win and win:IsShown() then UI.RefreshAll() end
end
