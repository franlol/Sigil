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
    player = "Player", target = "Target", targettarget = "Target of target", focus = "Focus", pet = "Pet",
    party = "Party",
}

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

-- Class-specific pieces: enabled only for the classes that use them (a profile
-- can be shared by characters of several classes, so they stay visible)
local function ClassIs(...)
    local classes = {}
    for _, c in ipairs({ ... }) do classes[c] = true end
    return function()
        local _, class = UnitClass("player")
        return classes[class] or false
    end
end

-- Note shown when your class does not use a card
-- (the class does not change while playing, so the card never changes size)
local function ClassNote(card, check)
    if check() then return end
    card:Add(UI.Note(card, "|cffffb347" .. L["Your class does not use this. It stays saved for characters that do."] .. "|r"))
end

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
-- autoTip, enableIf, showIf, subtitle, column
local function BarCard(page, column, title, getStyle, apply, opts)
    opts = opts or {}
    local card = page:Add(column, UI.Card(page.content, title, opts.subtitle))
    card.showIf = opts.showIf
    local on = opts.enableIf
    local function Is(key, value) return function() return getStyle()[key] == value end end
    local function IsNot(key, value) return function() return getStyle()[key] ~= value end end

    local g, s = TB(getStyle, "texture", apply)
    card:Add(UI.Dropdown(card, L["Texture"], function() return TextureOptions(true) end, g, s, { enableIf = on }))
    local colors = { { "auto", opts.autoLabel or L["Automatic"] } }
    if opts.gradient then colors[#colors + 1] = { "gradient", L["Gradient"] } end
    colors[#colors + 1] = { "custom", L["Custom"] }
    g, s = TB(getStyle, "color", apply)
    card:Add(UI.Segmented(card, L["Color"], colors, g, s, { enableIf = on, tip = opts.autoTip }))
    card:Add(UI.Swatch(card, L["Custom color"], function() return getStyle().custom end, apply,
        { enableIf = Both(on, Is("color", "custom")) }))
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

-- Position rows (anchored to, attach point, corner, offsets, optional width),
-- added to a card. opts.unit: the frame the piece belongs to
local function PositionRows(card, getPos, apply, opts)
    opts = opts or {}
    local on = opts.enableIf
    if opts.unit then AnchorRow(card, opts.unit, getPos, on) end
    local g, s = TB(getPos, "relPoint", apply)
    card:Add(UI.Dropdown(card, L["Point of the frame or screen"], POINTS, g, s, { enableIf = on }))
    g, s = TB(getPos, "point", apply)
    card:Add(UI.Dropdown(card, opts.cornerLabel or L["Corner"], POINTS, g, s, { enableIf = on }))
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
    card:Add(UI.Check(card, L["Hide the game's frame"], g, s, {
        tip = L["Hides the Blizzard frame this one replaces. Turning it off brings it back after /reload."],
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
    PositionRows(card, H, apply, { unit = unit, width = true, enableIf = HDet })
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
    PositionRows(card, PW, apply, { unit = unit, width = true, enableIf = PDet })
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
    } },
    { "Power", {
        { "Power(unit)", "Current" },
        { "MaxPower(unit)", "Maximum" },
    } },
    { "Combat", {
        { "Threat(unit)", "Threat percentage, or nothing" },
    } },
    { "Format", {
        { "Short(number)", "Short number: 12.3K, 1.2M" },
        { "Colorize(text, r, g, b)", "Text in a color (0-1)" },
        { "ClassColor(unit)", "Class color: r, g, b" },
        { "DifficultyColor(unit)", "Level color by difficulty: r, g, b" },
    } },
}

-- One topic as text: its title, then a call (accent) and what it gives per line
local function HelpText(topic)
    local A = C.accent
    local hex = ("|cff%02x%02x%02x"):format(A[1] * 255, A[2] * 255, A[3] * 255)
    local lines = { "|cffffffff" .. L[topic[1]] .. "|r" }
    for _, fn in ipairs(topic[2]) do
        lines[#lines + 1] = hex .. fn[1] .. "|r  " .. L[fn[2]]
    end
    return table.concat(lines, "\n")
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

    -- list
    local list = page:Add(1, UI.Card(page.content, L["Texts"], L["Click to edit · drag to reorder"]))
    list:Add(SelectList(list, Texts, TextLabel, function() return state.sel end, function(i)
        state.sel = i
        if page.LoadEditor then page.LoadEditor() end
    end, nil, 20, function(from, to)
        local t = table.remove(Texts(), from)
        table.insert(Texts(), to, t)
        state.sel = to
        ns.ApplyUnit(unit)
        if page.LoadEditor then page.LoadEditor() end
    end))

    local add = { tpl = "name" }
    local tplOptions = {}
    for _, t in ipairs(TEMPLATES) do tplOptions[#tplOptions + 1] = { t[1], L[t[2]] } end
    list:Add(UI.Dropdown(list, L["Template"], tplOptions, function() return add.tpl end, function(v) add.tpl = v end))
    list:Add(UI.Buttons(list, {
        { L["Add text"], function()
            for _, t in ipairs(TEMPLATES) do
                if t[1] == add.tpl then
                    table.insert(Texts(), {
                        region = "health", point = "CENTER", x = 0, y = 0, size = 11, justify = "CENTER",
                        code = t[3], events = ns.DeepCopy(t[4]), name = L[t[2]],
                    })
                    state.sel = #Texts()
                end
            end
            ns.ApplyUnit(unit)
            Changed()
            page.LoadEditor()
        end, "accent" },
    }))
    local delete = UI.Buttons(list, {
        { L["Delete selected"], function()
            if not Sel() then return end
            table.remove(Texts(), state.sel)
            state.sel = math.max(1, math.min(state.sel, #Texts()))
            ns.ApplyUnit(unit)
            Changed()
            page.LoadEditor()
        end, "danger" },
    }, { enableIf = function() return Sel() ~= nil end })
    UI.Confirm(delete.buttons[1])
    list:Add(delete)

    -- reference
    local ref = page:Add(1, UI.Card(page.content, L["Functions you can use"],
        L["unit is this frame's unit. Return a text, or a format and its values."]))
    ref:Add(UI.Note(ref, "|cffd0d0d0return \"%s / %s\", HP(unit), MaxHP(unit)|r"))
    for _, topic in ipairs(HELP) do ref:Add(UI.Note(ref, HelpText(topic))) end
    ref:Add(UI.Note(ref, L["Health and power can be hidden by the game: they can be shown, but not compared or used in math."]))

    -- editor
    local ed = page:Add(2, UI.Card(page.content, L["Edit text"]))
    ed.showIf = function() return Sel() ~= nil end
    local nameRow = ed:Add(UI.Input(ed, L["Name"], function() return Sel() and Sel().name or "" end,
        function(v)
            if Sel() then Sel().name = v end
            Changed()
        end))
    local code = ed:Add(UI.CodeBox(ed, 150))
    local status = ed:Add(UI.Note(ed, ""))
    ed:Add(UI.Buttons(ed, {
        { L["Apply code"], function()
            local t = Sel()
            if not t then return end
            local text = code.edit:GetText()
            local fn, err = ns.CompileText(text)
            if not fn then
                status:SetText("|cffff6b61" .. L["Error:"] .. "|r " .. tostring(err))
                Changed()
                return
            end
            t.code = text
            status:SetText("|cff6bd66b" .. L["Applied."] .. "|r")
            ns.ApplyUnit(unit)
            Changed()
        end, "accent" },
        { L["Undo changes"], function() page.LoadEditor() end },
    }))
    local events = ed:Add(UI.Input(ed, L["Update on"], function()
        return Sel() and table.concat(Sel().events or {}, ", ") or ""
    end, function(v)
        local t = Sel()
        if not t then return end
        t.events = {}
        for ev in v:gmatch("[%w_]+") do table.insert(t.events, ev:upper()) end
        ns.ApplyUnit(unit)
    end, { tip = L["Game events that refresh this text, separated by commas. It is also refreshed when the unit changes."] }))

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
        code.edit:SetText(t and t.code or "")
        code.edit:SetCursorPosition(0)
        status:SetText(L["Edit the code and press Apply. Errors are shown here."])
        nameRow.Refresh()
        events.Refresh()
        page:Layout()
    end
    page:HookScript("OnShow", function() page.LoadEditor() end)
    page.LoadEditor()
end

-- Auras: list of groups on the left, the selected group's settings on the right
local SORTS = function()
    return { { "default", L["Game order"] }, { "time", L["Time left"] }, { "name", L["Name"] } }
end

function Tabs.auras(page, unit)
    local state = { sel = 1 }
    local function Groups() return U(unit).auras.groups end
    local function Sel() return Groups()[state.sel] end
    local function On() return U(unit).auras.enabled end
    local function SelOn() return On() and Sel() ~= nil end
    local function Harmful() return Sel() and Sel().kind == "HARMFUL" end

    -- get/set for a key of the selected group
    local function SB(key)
        return function() local g = Sel() return g and g[key] end,
            function(v)
                local g = Sel()
                if not g then return end
                g[key] = v
                ns.ApplyUnit(unit)
            end
    end

    -- groups
    local list = page:Add(1, UI.Card(page.content, L["Aura groups"],
        L["Each group is a block of icons with its own filters, size and place."]))
    local g, s = Bind(unit, "auras", "enabled")
    list:Add(UI.Check(list, L["Show auras"], g, s))
    list:Add(SelectList(list, Groups, function(grp)
        local kind = grp.kind == "HARMFUL" and L["Debuffs"] or L["Buffs"]
        local name = L[grp.name or ""] or ""
        local off = grp.show and "" or ("  |cff777777(" .. L["hidden"] .. ")|r")
        return name .. "  |cff8f8fa0" .. kind .. "|r" .. off
    end, function() return state.sel end, function(i) state.sel = i end, nil, 20, function(from, to)
        local grp = table.remove(Groups(), from)
        table.insert(Groups(), to, grp)
        state.sel = to
        ns.ApplyUnit(unit)
    end))
    list:Add(UI.Note(list, L["Drag a group to change its order."]))

    local add = { tpl = "debuffs" }
    local tpl = {}
    for _, t in ipairs(ns.AURA_TEMPLATES) do tpl[#tpl + 1] = { t[1], L[t[2]] } end
    list:Add(UI.Dropdown(list, L["Template"], tpl, function() return add.tpl end, function(v) add.tpl = v end))
    list:Add(UI.Buttons(list, {
        { L["Add group"], function()
            for _, t in ipairs(ns.AURA_TEMPLATES) do
                if t[1] == add.tpl then
                    local grp = t[3]()
                    grp.name = L[grp.name]
                    -- below the last group, so they do not overlap
                    local last = Groups()[#Groups()]
                    if last then grp.y = (last.y or 0) - (last.size + last.spacing) * math.ceil(last.max / last.perRow) - 4 end
                    table.insert(Groups(), grp)
                    state.sel = #Groups()
                end
            end
            ns.ApplyUnit(unit)
            Changed()
        end, "accent" },
    }, { enableIf = On }))
    local del = UI.Buttons(list, {
        { L["Delete selected"], function()
            if not Sel() then return end
            table.remove(Groups(), state.sel)
            state.sel = math.max(1, math.min(state.sel, #Groups()))
            ns.ApplyUnit(unit)
            Changed()
        end, "danger" },
    }, { enableIf = SelOn })
    UI.Confirm(del.buttons[1])
    list:Add(del)

    -- spell list
    local spells = page:Add(1, UI.Card(page.content, L["Spell list"], L["Show only some spells, or hide some."]))
    spells.showIf = function() return Sel() ~= nil end
    g, s = SB("listMode")
    spells:Add(UI.Segmented(spells, nil, {
        { "off", L["Off"] }, { "only", L["Only these"] }, { "hide", L["All except these"] },
    }, g, s, { enableIf = SelOn }))
    local where = spells:Add(UI.Note(spells, ""))
    where.Refresh = function()
        where:SetText(Harmful() and L["Works for debuffs on enemies. On friendly units the game does not allow it (the list is ignored)."]
            or L["Works for buffs on you, your group and pets. On enemies the game does not allow it (the list is ignored)."])
    end
    table.insert(UI.widgets, where)
    local typed = { text = "" }
    spells:Add(UI.Input(spells, L["Add spell"], function() return typed.text end, function(v)
        local grp = Sel()
        local key = ns.SpellKeyFromInput(v)
        if grp and key then
            grp.spells = grp.spells or {}
            table.insert(grp.spells, key)
            ns.SpellIDs(ns.SpellKeyName(key))   -- starts looking up its ranks
            ns.ApplyUnit(unit)
        end
        typed.text = ""
        Changed()
    end, { enableIf = function() return SelOn() and Sel().listMode ~= "off" end,
        tip = L["Spell name (every rank) or spell ID. Press Enter."] }))
    spells:Add(SelectList(spells, function() return Sel() and Sel().spells or {} end,
        function(key)
            local name = ns.SpellKeyName(key)
            if type(key) == "number" then name = name .. "  |cff8f8fa0#" .. key .. "|r"
            elseif ns.IsSpellLookupPending(name) then name = name .. "  |cff8f8fa0" .. L["(looking up ranks...)"] .. "|r" end
            return "      " .. name
        end, nil, nil, function(row, key, i)
            if not row.icon then
                row.icon = row:CreateTexture(nil, "OVERLAY")
                row.icon:SetSize(16, 16)
                row.icon:SetPoint("LEFT", 8, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.remove = UI.Button(row, "x", 16, 16)
                row.remove:SetPoint("RIGHT", -3, 0)
                row.remove.text:SetTextColor(unpack(C.danger))
                row.text:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
            end
            row.icon:SetTexture(ns.SpellKeyIcon(key))
            row.remove:SetScript("OnClick", function()
                local grp = Sel()
                if grp then table.remove(grp.spells, i) end
                ns.ApplyUnit(unit)
                Changed()
            end)
        end, 22))

    -- selected group: what to show
    local what = page:Add(2, UI.Card(page.content, L["What to show"]))
    what.showIf = function() return Sel() ~= nil end
    what:Add(UI.Input(what, L["Name"], function() return Sel() and L[Sel().name or ""] or "" end, function(v)
        if Sel() then Sel().name = v end
        Changed()
    end, { enableIf = SelOn }))
    g, s = SB("show")
    what:Add(UI.Check(what, L["Show this group"], g, s, { enableIf = SelOn }))
    g, s = SB("kind")
    what:Add(UI.Segmented(what, L["Type"], { { "HELPFUL", L["Buffs"] }, { "HARMFUL", L["Debuffs"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("caster")
    what:Add(UI.Segmented(what, L["Cast by"], {
        { "all", L["Anyone"] }, { "mine", L["Me"] }, { "others", L["Others"] },
    }, g, s, { enableIf = SelOn }))

    local filt = page:Add(2, UI.Card(page.content, L["Filters"]))
    filt.showIf = function() return Sel() ~= nil end
    g, s = SB("dispellable")
    filt:Add(UI.Check(filt, L["Only the ones I can dispel"], g, s, { enableIf = Both(SelOn, Harmful) }))
    g, s = SB("boss")
    filt:Add(UI.Check(filt, L["Only boss auras"], g, s, { enableIf = SelOn }))
    g, s = SB("stealable")
    filt:Add(UI.Check(filt, L["Only the ones I can purge or steal"], g, s, {
        enableIf = Both(SelOn, function() return not Harmful() end),
    }))
    for _, kind in ipairs(ns.DISPEL_KINDS) do
        filt:Add(UI.Check(filt, L[kind], function() return Sel() and Sel().types[kind] end, function(v)
            if Sel() then Sel().types[kind] = v end
            ns.ApplyUnit(unit)
        end, { enableIf = Both(SelOn, Harmful) }))
    end
    g, s = SB("maxDuration")
    filt:Add(UI.Slider(filt, L["Hide longer than"], 0, 600, 5, g, s, {
        enableIf = SelOn, tip = L["Hides auras that last longer than this, and permanent ones. 0: no limit."],
        format = function(v) if v == 0 then return L["No limit"] end
            return v >= 60 and ("%d min %02d s"):format(v / 60, v % 60) or ("%d s"):format(v) end,
    }))
    g, s = SB("sort")
    filt:Add(UI.Dropdown(filt, L["Order"], SORTS, g, s, { enableIf = SelOn }))

    local look = page:Add(2, UI.Card(page.content, L["Look"]))
    look.showIf = function() return Sel() ~= nil end
    g, s = SB("size")
    look:Add(UI.Slider(look, L["Icon size"], 10, 48, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("spacing")
    look:Add(UI.Slider(look, L["Spacing"], 0, 10, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("perRow")
    look:Add(UI.Slider(look, L["Icons per row"], 1, 20, 1, g, s, { enableIf = SelOn }))
    g, s = SB("max")
    look:Add(UI.Slider(look, L["Maximum"], 1, 40, 1, g, s, { enableIf = SelOn }))
    g, s = SB("timer")
    look:Add(UI.Check(look, L["Show time left"], g, s, { enableIf = SelOn }))
    g, s = SB("timerSize")
    look:Add(UI.Slider(look, L["Time text size"], 0, 24, 1, g, s, { enableIf = function() return SelOn() and Sel().timer end,
        format = function(v) return v == 0 and L["Automatic"] or Px(v) end }))
    g, s = SB("stackSize")
    look:Add(UI.Slider(look, L["Stack text size"], 0, 24, 1, g, s, { enableIf = SelOn,
        format = function(v) return v == 0 and L["Automatic"] or Px(v) end }))
    g, s = SB("spiral")
    look:Add(UI.Check(look, L["Duration sweep"], g, s, { enableIf = SelOn }))
    g, s = SB("borderByType")
    look:Add(UI.Check(look, L["Border colored by debuff type"], g, s, { enableIf = Both(SelOn, Harmful) }))
    g, s = SB("tooltip")
    look:Add(UI.Check(look, L["Tooltip on mouseover"], g, s, { enableIf = SelOn }))
    g, s = SB("pandemic")
    look:Add(UI.Check(look, L["Glow when it should be renewed"], g, s, { enableIf = SelOn,
        tip = L["The last part of the duration, when casting it again does not waste time. The game decides the window."] }))

    local pos = page:Add(1, UI.Card(page.content, L["Position"]))
    pos.showIf = function() return Sel() ~= nil end
    AnchorRow(pos, unit, Sel, SelOn)
    g, s = SB("relPoint")
    pos:Add(UI.Dropdown(pos, L["Point of the frame or screen"], POINTS, g, s, { enableIf = SelOn }))
    g, s = SB("point")
    pos:Add(UI.Dropdown(pos, L["Corner of the block"], POINTS, g, s, { enableIf = SelOn }))
    g, s = SB("growX")
    pos:Add(UI.Segmented(pos, L["Grow"], { { "RIGHT", L["Right"] }, { "LEFT", L["Left"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("growY")
    pos:Add(UI.Segmented(pos, nil, { { "DOWN", L["Down"] }, { "UP", L["Up"] } }, g, s, { enableIf = SelOn }))
    g, s = SB("x")
    pos:Add(UI.Slider(pos, L["Horizontal offset"], -300, 300, 1, g, s, { format = Px, enableIf = SelOn }))
    g, s = SB("y")
    pos:Add(UI.Slider(pos, L["Vertical offset"], -300, 300, 1, g, s, { format = Px, enableIf = SelOn }))
end

-- Icons: every icon with its switch on the left, the chosen one's place on the right
local ICON_NAMES = {
    combat = "In combat", resting = "Resting", leader = "Group leader", assistant = "Raid assistant",
    masterLooter = "Master looter", role = "Role", raidTarget = "Raid target", pvp = "PvP",
    readyCheck = "Ready check", resurrect = "Being resurrected", summon = "Summon", phase = "Other phase",
    questBoss = "Quest boss",
}

function Tabs.icons(page, unit)
    local state = { sel = ns.ICON_KEYS[1] }
    local function Cfg(key)
        local icons = U(unit).icons
        if not icons[key] then icons[key] = { show = false, point = "TOP", x = 0, y = 0, size = 16 } end
        return icons[key]
    end

    local list = page:Add(1, UI.Card(page.content, L["Status icons"], L["Turn them on, and click Edit to place one."]))
    for _, key in ipairs(ns.ICON_KEYS) do
        local row = UI.Check(list, L[ICON_NAMES[key]], function() return Cfg(key).show end, function(v)
            Cfg(key).show = v
            state.sel = key
            ns.ApplyUnit(unit)
            Changed()
        end)
        -- "Edit" at the end of the row: chooses the icon to place
        local edit = UI.Button(row, L["Edit"], 44, 16, function()
            state.sel = key
            Changed()
        end)
        edit:SetPoint("RIGHT")
        edit:SetFrameLevel(row.box:GetFrameLevel() + 3)
        row.label:SetPoint("RIGHT", edit, "LEFT", -6, 0)
        local base = row.Refresh
        row.Refresh = function(...)
            base(...)
            edit.text:SetTextColor(unpack(state.sel == key and C.accent or C.muted))
        end
        list:Add(row)
    end

    local place = page:Add(2, UI.Card(page.content, L["Place"]))
    local title = place:Add(UI.Note(place, ""))
    title.Refresh = function() title:SetText(L["Editing:"] .. " |cffffffff" .. L[ICON_NAMES[state.sel]] .. "|r") end
    table.insert(UI.widgets, title)
    local function IB(k)
        return function() return Cfg(state.sel)[k] end,
            function(v)
                Cfg(state.sel)[k] = v
                ns.ApplyUnit(unit)
            end
    end
    local function On() return Cfg(state.sel).show end
    local g, s = IB("point")
    place:Add(UI.Dropdown(place, L["Position"], POINTS, g, s, { enableIf = On }))
    g, s = IB("size")
    place:Add(UI.Slider(place, L["Size"], 8, 40, 1, g, s, { format = Px, enableIf = On }))
    g, s = IB("x")
    place:Add(UI.Slider(place, L["Horizontal offset"], -60, 60, 1, g, s, { format = Px, enableIf = On }))
    g, s = IB("y")
    place:Add(UI.Slider(place, L["Vertical offset"], -60, 60, 1, g, s, { format = Px, enableIf = On }))
    place:Add(UI.Note(place, L["Tip: turn on Test mode to see every icon on the frame."]))
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
            enableIf = On, tip = L["Turning it off brings it back after /reload."],
        }))
    end
    g, s = Bind(unit, "castbar", "icon")
    card:Add(UI.Check(card, L["Spell icon"], g, s, { enableIf = On }))
    if unit == "player" then
        g, s = Bind(unit, "castbar", "latency")
        card:Add(UI.Check(card, L["Show latency"], g, s, { enableIf = On,
            tip = L["The end of the bar the server takes to answer: you can start the next spell there."] }))
    end
    g, s = Bind(unit, "castbar", "height")
    card:Add(UI.Slider(card, L["Height"], 8, 40, 1, g, s, { format = Px, enableIf = On }))
    g, s = Bind(unit, "castbar", "timeFormat")
    card:Add(UI.Segmented(card, L["Time"], { { "left", "1.2" }, { "both", "1.2 / 3.0" } }, g, s, { enableIf = On }))
    g, s = Bind(unit, "castbar", "fadeTime")
    card:Add(UI.Slider(card, L["Stay after it ends"], 0, 2, 0.1, g, s, { enableIf = On,
        format = function(v) return v == 0 and L["No"] or ("%.1f s"):format(v) end,
        tip = L["Shows for a moment whether the cast was completed or interrupted."] }))
    card:Add(UI.Note(card, L["Enemy casts: if the game hides their times, the bar is shown full with the spell name."]))

    BarCard(page, 1, L["Bar look"], function() return CB().style end, apply, {
        autoLabel = L["By state"], enableIf = On,
    })

    card = page:Add(2, UI.Card(page.content, L["Spell name"]))
    TextRows(card, function() return CB().nameText end, apply, { auto = true, enableIf = On })
    card = page:Add(2, UI.Card(page.content, L["Time text"]))
    TextRows(card, function() return CB().timeText end, apply, { auto = true, enableIf = On })
    card = page:Add(2, UI.Card(page.content, L["Position"]))
    PositionRows(card, CB, apply, { unit = unit, width = true, enableIf = On, cornerLabel = L["Corner of the bar"] })
end

-- Extras: fading, threat, combo points, experience, totems
function Tabs.extras(page, unit)
    local apply = function() ns.ApplyUnit(unit) end
    local card = page:Add(1, UI.Card(page.content, L["Fading"], L["The frame becomes transparent when any checked situation happens."]))
    local g, s
    if unit ~= "player" then
        g, s = Bind(unit, "fader", "range")
        card:Add(UI.Check(card, L["Out of range"], g, s, { tip = L["Out of range: farther than about 28 yards."] }))
    end
    g, s = Bind(unit, "fader", "combat")
    card:Add(UI.Check(card, L["Out of combat"], g, s))
    if unit ~= "player" then
        g, s = Bind(unit, "fader", "phase")
        card:Add(UI.Check(card, L["In another phase"], g, s))
        g, s = Bind(unit, "fader", "hostility")
        card:Add(UI.Segmented(card, L["By reaction"], {
            { "none", L["Never"] }, { "friendly", L["Friendly"] }, { "hostile", L["Hostile"] },
        }, g, s, { tip = L["Fades friendly or hostile units."] }))
    end
    g, s = Bind(unit, "fader", "alpha")
    card:Add(UI.Slider(card, L["Opacity when faded"], 0, 1, 0.05, g, s, { format = UI.pct }))

    -- combat text
    local function CT() return U(unit).combatText end
    local function CTOn() return CT().enabled end
    card = page:Add(2, UI.Card(page.content, L["Combat text"], L["Damage, heals and misses over the frame."]))
    g, s = Bind(unit, "combatText", "enabled")
    card:Add(UI.Check(card, L["Show combat text"], g, s))
    g, s = Bind(unit, "combatText", "duration")
    card:Add(UI.Slider(card, L["Duration"], 0.5, 4, 0.1, g, s, { enableIf = CTOn, format = function(v) return ("%.1f s"):format(v) end }))
    PositionRows(card, CT, apply, { unit = unit, enableIf = CTOn })
    TextRows(card, function() return CT().textStyle end, apply, { enableIf = CTOn })

    -- threat bar
    if unit ~= "player" then
        local function TBr() return U(unit).threatBar end
        local function TBOn() return TBr().enabled end
        card = page:Add(2, UI.Card(page.content, L["Threat bar"], L["Your threat on this unit, from 0 to 100 %."]))
        g, s = Bind(unit, "threatBar", "enabled")
        card:Add(UI.Check(card, L["Show threat bar"], g, s))
        g, s = Bind(unit, "threatBar", "height")
        card:Add(UI.Slider(card, L["Height"], 3, 24, 1, g, s, { format = Px, enableIf = TBOn }))
        g, s = Bind(unit, "threatBar", "text")
        card:Add(UI.Check(card, L["Show percentage"], g, s, { enableIf = TBOn }))
        PositionRows(card, TBr, apply, { unit = unit, width = true, enableIf = TBOn })
        BarCard(page, 2, L["Threat bar look"], function() return TBr().style end, apply, {
            autoLabel = L["Threat status"], enableIf = TBOn })
    end

    card = page:Add(2, UI.Card(page.content, L["Threat"], unit == "player"
        and L["Border with your highest threat on any enemy."] or L["Border with your threat on this unit."]))
    g, s = Bind(unit, "threat", "enabled")
    card:Add(UI.Check(card, L["Show threat border"], g, s))
    g, s = Bind(unit, "threat", "width")
    card:Add(UI.Slider(card, L["Thickness"], 1, 6, 1, g, s, {
        format = Px, enableIf = function() return U(unit).threat.enabled end,
    }))

    if unit == "target" then
        local function Combo() return U(unit).combo end
        local ComboClass = ClassIs("ROGUE", "DRUID")
        local function On() return ComboClass() and Combo().enabled end
        card = page:Add(1, UI.Card(page.content, L["Combo points"], L["Rogues and druids only."]))
        ClassNote(card, ComboClass)
        g, s = Bind(unit, "combo", "enabled")
        card:Add(UI.Check(card, L["Show combo points"], g, s, { enableIf = ComboClass }))
        g, s = Bind(unit, "combo", "height")
        card:Add(UI.Slider(card, L["Height"], 3, 20, 1, g, s, { format = Px, enableIf = On }))
        PositionRows(card, Combo, apply, { unit = unit, width = true, enableIf = On })
        BarCard(page, 1, L["Combo points look"], function() return Combo().style end, apply, { enableIf = On })
    end

    if unit == "player" then
        local function AM() return U(unit).altMana end
        local DruidClass = ClassIs("DRUID")
        local function AMOn() return DruidClass() and AM().enabled end
        card = page:Add(1, UI.Card(page.content, L["Druid mana"], L["Your mana while in bear or cat form."]))
        ClassNote(card, DruidClass)
        g, s = Bind(unit, "altMana", "enabled")
        card:Add(UI.Check(card, L["Show druid mana"], g, s, { enableIf = DruidClass }))
        g, s = Bind(unit, "altMana", "height")
        card:Add(UI.Slider(card, L["Height"], 3, 24, 1, g, s, { format = Px, enableIf = AMOn }))
        g, s = Bind(unit, "altMana", "text")
        card:Add(UI.Check(card, L["Show numbers"], g, s, { enableIf = AMOn }))
        PositionRows(card, AM, apply, { unit = unit, width = true, enableIf = AMOn })
        BarCard(page, 1, L["Druid mana look"], function() return AM().style end, apply, {
            autoLabel = L["Power type"], enableIf = AMOn })

        local function GC() return U(unit).gcd end
        local function GCOn() return GC().enabled end
        card = page:Add(2, UI.Card(page.content, L["Global cooldown"], L["A thin bar that empties while the global cooldown runs."]))
        g, s = Bind(unit, "gcd", "enabled")
        card:Add(UI.Check(card, L["Show global cooldown"], g, s))
        g, s = Bind(unit, "gcd", "height")
        card:Add(UI.Slider(card, L["Height"], 2, 16, 1, g, s, { format = Px, enableIf = GCOn }))
        PositionRows(card, GC, apply, { unit = unit, width = true, enableIf = GCOn })
        BarCard(page, 2, L["Global cooldown look"], function() return GC().style end, apply, { enableIf = GCOn })

        local function XP() return U(unit).xp end
        local function On() return XP().enabled end
        card = page:Add(1, UI.Card(page.content, L["Experience / reputation"], L["A thin bar under your frame."]))
        g, s = Bind(unit, "xp", "enabled")
        card:Add(UI.Check(card, L["Show the bar"], g, s))
        g, s = Bind(unit, "xp", "mode")
        card:Add(UI.Segmented(card, L["Shows"], {
            { "auto", L["Automatic"] }, { "xp", L["Experience"] }, { "rep", L["Reputation"] },
        }, g, s, { enableIf = On, tip = L["Automatic: experience until max level, then the reputation you watch."] }))
        g, s = Bind(unit, "xp", "height")
        card:Add(UI.Slider(card, L["Height"], 4, 24, 1, g, s, { format = Px, enableIf = On }))
        PositionRows(card, XP, apply, { unit = unit, width = true, enableIf = On })
        BarCard(page, 1, L["Experience bar look"], function() return XP().style end, apply, { enableIf = On })
        card = page:Add(2, UI.Card(page.content, L["Experience text"]))
        g, s = Bind(unit, "xp", "text")
        card:Add(UI.Check(card, L["Show numbers"], g, s, { enableIf = On }))
        TextRows(card, function() return XP().textStyle end, apply, {
            auto = true, enableIf = function() return On() and XP().text end })

        local ShamanClass = ClassIs("SHAMAN")
        local function TOn() return ShamanClass() and U(unit).totems.enabled end
        card = page:Add(2, UI.Card(page.content, L["Totems"], L["The game's totem bar, moved under your frame (shamans)."]))
        ClassNote(card, ShamanClass)
        g, s = Bind(unit, "totems", "enabled")
        card:Add(UI.Check(card, L["Move the totem bar"], g, s, { enableIf = ShamanClass, tip = L["Turning it off brings it back after /reload."] }))
        g, s = Bind(unit, "totems", "scale")
        card:Add(UI.Slider(card, L["Scale"], 0.5, 2, 0.05, g, s, { format = UI.pct, enableIf = TOn }))
        PositionRows(card, function() return U(unit).totems end, apply, { unit = unit, enableIf = TOn })
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
    -- one swatch per key of a color group
    local function Swatches(card, group, list, alpha)
        for _, e in ipairs(list) do
            card:Add(UI.Swatch(card, e[2], function() return ns.P.colors[group][e[1]] end, ApplyColors, { alpha = alpha }))
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
        { "interrupted", L["Interrupted"] }, { "done", L["Completed"] }, { "latency", L["Latency"] },
    })

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

local TAB_LIST = {
    { "frame", "Frame" }, { "bars", "Bars" }, { "texts", "Texts" }, { "auras", "Auras" },
    { "icons", "Icons" }, { "castbar", "Cast bar" }, { "extras", "Extras" },
}


-------------------------------------------------------------------------------
-- Unit page: title, on/off, reset and tabs
-------------------------------------------------------------------------------
local function UnitPage(container, unit)
    PageTitle(container, L[UNIT_NAMES[unit]])

    local reset = UI.Button(container, L["Reset frame"], 100, 20, function()
        ns.ResetUnit(unit)
        Changed()
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
    local tabPages = {}

    local labels = {}
    for i, t in ipairs(TAB_LIST) do labels[i] = { t[1], L[t[2]] } end
    local tabs = UI.Tabs(container, labels, function(key)
        for _, p in pairs(tabPages) do p:Hide() end
        local p = tabPages[key]
        if not p then
            p = UI.Page(holder, 2)
            Tabs[key](p, unit)
            tabPages[key] = p
        end
        p:Show()
        UI.RefreshAll()
    end)
    tabs:SetPoint("TOPLEFT", 0, -30)
    tabs:SetPoint("TOPRIGHT", -12, -30)
    tabs:Select("frame")
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
    local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Sigil", "Version")
    win = UI.Window({ name = "SigilOptions", title = "Sigil", version = version })

    win:AddHeaderButton(L["Unlock frames"], function() ns.SetUnlocked(not ns.unlocked) C_Timer.After(0, Changed) end,
        function() return ns.unlocked end, L["Drag the frames on screen. Lock them again when you finish."])
    win:AddHeaderButton(L["Test mode"], function() ns.SetTestMode(not ns.testMode) C_Timer.After(0, Changed) end,
        function() return ns.testMode end, L["Shows every frame with sample data, so you can see how it looks."])

    win:AddNav("general", L["General"], GeneralPage)
    win:AddSection(L["FRAMES"])
    for _, unit in ipairs({ "player", "target", "targettarget", "focus", "pet", "party" }) do
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

-- After dragging a frame, its position sliders show the new values
function ns.OnFrameMoved()
    if win and win:IsShown() then UI.RefreshAll() end
end
