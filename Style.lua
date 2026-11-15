-------------------------------------------------------------------------------
-- Sigil - Shared look: colors, bar look, text look and positions
--
-- Every bar (health, power, cast, experience, combo points) and every text
-- (unit texts, cast bar texts, experience text) is drawn through these
-- functions, so they all offer the same settings.
-------------------------------------------------------------------------------

local _, ns = ...

-------------------------------------------------------------------------------
-- Colors
-------------------------------------------------------------------------------
local function Colors() return ns.P and ns.P.colors or ns.DEFAULTS.colors end

function ns.Color(group, key)
    local g = Colors()[group]
    return g and g[key]
end

function ns.ClassRGB(token)
    local c = token and (ns.Color("class", token) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]))
    if c then return c.r, c.g, c.b end
end

function ns.PowerRGB(token)
    local c = token and (ns.Color("power", token) or (PowerBarColor and PowerBarColor[token]))
    if c then return c.r, c.g, c.b end
    return 0.3, 0.5, 1
end

-- reaction: 1-3 hostile, 4 neutral, 5-8 friendly
function ns.ReactionRGB(reaction)
    local key = (reaction or 4) <= 3 and "hostile" or reaction == 4 and "neutral" or "friendly"
    local c = ns.Color("reaction", key)
    return c.r, c.g, c.b
end

function ns.StateRGB(key)
    local c = ns.Color("state", key)
    return c.r, c.g, c.b
end

-- Health gradient: the game evaluates it with the (secret) health percentage
local curve
function ns.ResetGradient() curve = nil end

function ns.GradientCurve()
    if curve then return curve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local g = Colors().gradient
    curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(0, CreateColor(g.low.r, g.low.g, g.low.b, 1))
    curve:AddPoint(0.5, CreateColor(g.mid.r, g.mid.g, g.mid.b, 1))
    curve:AddPoint(1, CreateColor(g.high.r, g.high.g, g.high.b, 1))
    return curve
end

-------------------------------------------------------------------------------
-- Bar look
-------------------------------------------------------------------------------
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

-- The box around a bar (cast bar, GCD, threat bar...): its background and
-- the border of the bar look (st.border px, 0 = none; st.borderColor).
-- Every region given goes inside the border. Returns the border size.
function ns.StyleBox(box, st, ...)
    local edge = st.border or 1
    box:SetBackdrop({ bgFile = ns.FLAT, edgeFile = edge > 0 and ns.FLAT or nil, edgeSize = math.max(1, edge) })
    box:SetBackdropColor(0, 0, 0, 0.6)
    if edge > 0 then
        local c = st.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        box:SetBackdropBorderColor(c.r, c.g, c.b, c.a or 1)
    end
    for i = 1, select("#", ...) do
        local r = select(i, ...)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", edge, -edge)
        r:SetPoint("BOTTOMRIGHT", -edge, edge)
    end
    return edge
end

-- Texture, orientation, fill direction and spark (bar.bg = background texture)
function ns.StyleBar(bar, st)
    local tex = (st.texture and st.texture ~= "") and st.texture or ns.Texture()
    bar:SetStatusBarTexture(tex)
    -- slow bars glide instead of jumping a pixel at a time (as the game's own bars)
    local fill = bar:GetStatusBarTexture()
    fill:SetTexelSnappingBias(0)
    fill:SetSnapToPixelGrid(false)
    if bar.bg then bar.bg:SetTexture(tex) end
    local vertical = st.orientation == "VERTICAL"
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(st.reverse and true or false)

    if st.spark then
        if not bar.spark then
            bar.spark = bar:CreateTexture(nil, "OVERLAY")
            bar.spark:SetTexture(SPARK)
            bar.spark:SetBlendMode("ADD")
            -- a soft glow can sit between pixels: it glides where the fill edge ticks
            bar.spark:SetTexelSnappingBias(0)
            bar.spark:SetSnapToPixelGrid(false)
        end
        local h = vertical and bar:GetWidth() or bar:GetHeight()
        bar.spark:ClearAllPoints()
        if vertical then
            bar.spark:SetSize(math.max(8, h * 2.2), 12)
            bar.spark:SetPoint("CENTER", fill, st.reverse and "BOTTOM" or "TOP")
            bar.spark:SetRotation(math.rad(90))
        else
            bar.spark:SetSize(12, math.max(8, h * 2.2))
            bar.spark:SetPoint("CENTER", fill, st.reverse and "LEFT" or "RIGHT")
            bar.spark:SetRotation(0)
        end
        bar.spark:Show()
    elseif bar.spark then
        bar.spark:Hide()
    end
end

-- Colors of the fill and the background. r, g, b: the automatic color.
function ns.PaintBar(bar, st, r, g, b)
    if st.color == "custom" and st.custom then r, g, b = st.custom.r, st.custom.g, st.custom.b end
    bar:SetStatusBarColor(r, g, b)
    bar:GetStatusBarTexture():SetAlpha(st.alpha or 1)
    if bar.bg then
        if st.bg == "custom" and st.bgCustom then
            bar.bg:SetVertexColor(st.bgCustom.r, st.bgCustom.g, st.bgCustom.b, st.bgAlpha or 0.9)
        else
            local k = st.bgBrightness or 0.25
            bar.bg:SetVertexColor(r * k, g * k, b * k, st.bgAlpha or 0.9)
        end
    end
end

-------------------------------------------------------------------------------
-- Automatic text size (font size 0): a share of what the text sits on.
--   long: a long text on a bar (spell name, experience), of the bar height
--   short: a short number on a bar (swing, threat, alt mana), of the bar height
--   icon: a text on an icon (aura time and stacks, PvP countdown), of its size
-------------------------------------------------------------------------------
local AUTO = { long = 0.6, short = 0.8, icon = 0.45 }

function ns.AutoSize(kind, size)
    return math.max(8, math.floor(size * AUTO[kind]))
end

-------------------------------------------------------------------------------
-- Text look. autoSize: the size used when the style says 0
-------------------------------------------------------------------------------
function ns.StyleText(fs, t, autoSize)
    t = t or {}
    local size = (t.size and t.size > 0) and t.size or autoSize or 11
    local font = (t.font and t.font ~= "") and t.font or ns.Font()
    local outline = (t.outline ~= nil and t.outline ~= false) and t.outline or ns.Outline()
    if not fs:SetFont(font, size, outline) then
        fs:SetFont(STANDARD_TEXT_FONT, size, outline)
    end
    if t.shadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end
    if t.colorMode == "custom" and t.color then
        fs:SetTextColor(t.color.r, t.color.g, t.color.b)
    else
        fs:SetTextColor(1, 1, 1)
    end
end

-------------------------------------------------------------------------------
-- Time format of every countdown (auras, cast bar, swing timer, PvP flag).
-- A setting (ns.TimeFormat) becomes a list of rules: from `at` seconds on,
-- the time is written with `fmt`. The aura timer hands them to the game,
-- which counts down even secret times; the other timers run the same rules
-- here, so they all read alike.
--   style: short (3m, 45s) | compact (3m, 45) | full (3m 7s) | clock (3:07) |
--   seconds (187)
--   decimals: one decimal below this many seconds (0: never)
--   warnBelow / warnColor: the color of the last seconds (0: off)
--   hideAbove: no text until the time left drops below it (0: always shown)
-------------------------------------------------------------------------------
local EPS = 0.000001

-- every non-decimal rule of a style, from the shortest times up
local STYLES = {
    short = {
        { at = EPS, fmt = "%ds", round = "up" },
        { at = 60, fmt = "%dm", parts = { { div = 60, round = "up" } } },
        { at = 3600, fmt = "%dh", parts = { { div = 3600, round = "up" } } },
        { at = 86400, fmt = "%dd", parts = { { div = 86400, round = "up" } } },
    },
    compact = {
        { at = EPS, fmt = "%d", round = "up" },
        { at = 60, fmt = "%dm", parts = { { div = 60, round = "up" } } },
        { at = 3600, fmt = "%dh", parts = { { div = 3600, round = "up" } } },
        { at = 86400, fmt = "%dd", parts = { { div = 86400, round = "up" } } },
    },
    full = {
        { at = EPS, fmt = "%ds", round = "up" },
        { at = 60, fmt = "%dm %ds", parts = { { div = 60, round = "down" }, { mod = 60, round = "down" } } },
        { at = 3600, fmt = "%dh %dm", parts = { { div = 3600, round = "down" }, { div = 60, mod = 60, round = "down" } } },
        { at = 86400, fmt = "%dd %dh", parts = { { div = 86400, round = "down" }, { div = 3600, mod = 24, round = "down" } } },
    },
    clock = {
        { at = EPS, fmt = "%d:%02d", round = "up", parts = { { div = 60 }, { mod = 60 } } },
        { at = 3600, fmt = "%d:%02d:%02d", round = "up", parts = { { div = 3600 }, { div = 60, mod = 60 }, { mod = 60 } } },
    },
    seconds = {
        { at = EPS, fmt = "%d", round = "up" },
    },
}

local function ColorCode(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function Key(f, plain)
    local c = f.warnColor or {}
    return table.concat({ f.style or "short", f.decimals or 0, plain and 0 or f.warnBelow or 0,
        plain and 0 or f.hideAbove or 0, c.r or 1, c.g or 0, c.b or 0 }, ":")
end

local function Build(f, plain)
    local dec = f.decimals or 0
    local warn = not plain and f.warnBelow or 0
    local hide = not plain and f.hideAbove or 0
    -- the style's rules, the ones under `dec` taken over by the decimal rule
    local base = { { at = 0, fmt = "" } }
    if dec > 0 then base[2] = { at = EPS, fmt = "%.1f" } end
    local list = STYLES[f.style] or STYLES.short
    if dec >= 999 then list = {} end   -- always decimals
    for i, r in ipairs(list) do
        local at = math.max(r.at, dec)
        local nextAt = list[i + 1] and math.max(list[i + 1].at, dec)
        if not nextAt or nextAt > at then
            base[#base + 1] = { at = at, fmt = r.fmt, round = r.round, parts = r.parts }
        end
    end
    -- split at the warning and hiding times, then color or empty each piece
    local cuts = {}
    if warn > 0 then cuts[#cuts + 1] = warn end
    if hide > 0 then cuts[#cuts + 1] = hide end
    table.sort(cuts)
    local rules = {}
    for i, r in ipairs(base) do
        rules[#rules + 1] = r
        local nextAt = base[i + 1] and base[i + 1].at or math.huge
        for _, at in ipairs(cuts) do
            if at > rules[#rules].at and at < nextAt then
                rules[#rules + 1] = { at = at, fmt = r.fmt, round = r.round, parts = r.parts }
            end
        end
    end
    local code = warn > 0 and ColorCode(f.warnColor or { r = 1, g = 0.2, b = 0.2 })
    for i, r in ipairs(rules) do
        local copy = { at = r.at, fmt = r.fmt, round = r.round, parts = r.parts }
        if copy.fmt ~= "" then
            if hide > 0 and copy.at >= hide then
                copy.fmt, copy.round, copy.parts = "", nil, nil
            elseif code and copy.at < warn then
                copy.fmt = code .. copy.fmt .. "|r"
            end
        end
        rules[i] = copy
    end
    return rules
end

local ruleCache, nativeCache = {}, {}

-- The rules of a time format (plain: without the warning color and hiding).
-- Built when a timer is laid out, not on every update.
function ns.TimeRules(f, plain)
    f = f or {}
    local key = Key(f, plain)
    local rules = ruleCache[key]
    if not rules then
        rules = Build(f, plain)
        ruleCache[key] = rules
    end
    return rules
end

local function Round(v, how)
    if how == "up" then return math.ceil(v) end
    return math.floor(v)
end

-- The text for `left` seconds, as the game would write it with the same rules
function ns.FormatTime(rules, left)
    if not rules or not left or left <= 0 then return "" end
    local r
    for i = #rules, 1, -1 do
        if left >= rules[i].at then r = rules[i] break end
    end
    if not r or r.fmt == "" then return "" end
    local v = r.round and Round(left, r.round) or left
    if not r.parts then return r.fmt:format(v) end
    local a, b, c
    for i, p in ipairs(r.parts) do
        local x = v
        if p.div then x = x / p.div end
        if p.mod then x = x % p.mod end
        x = Round(x, p.round)
        if i == 1 then a = x elseif i == 2 then b = x else c = x end
    end
    return r.fmt:format(a, b, c)
end

-- The same rules as the game's formatter (nil if this client has none)
function ns.NativeTimeFormatter(f)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding) then
        return nil
    end
    f = f or {}
    local key = Key(f)
    if nativeCache[key] ~= nil then return nativeCache[key] or nil end
    local E = Enum.NumericRuleFormatRounding
    local points = {}
    for i, r in ipairs(ns.TimeRules(f)) do
        local n = { threshold = r.at, format = r.fmt }
        if r.round then n.step, n.rounding = 1, E.Up end
        if r.parts then
            n.components = {}
            for j, p in ipairs(r.parts) do
                local part = { div = p.div, mod = p.mod }
                if p.round then part.step, part.rounding = 1, p.round == "up" and E.Up or E.Down end
                n.components[j] = part
            end
        end
        points[i] = n
    end
    local ok, formatter = pcall(function()
        local fm = C_StringUtil.CreateNumericRuleFormatter()
        fm:SetBreakpoints(points)
        return fm
    end)
    nativeCache[key] = ok and formatter or false
    return ok and formatter or nil
end

-------------------------------------------------------------------------------
-- Position: { point, relPoint, x, y } relative to an anchor frame
-------------------------------------------------------------------------------
-- pos.anchor: "frame" (default, relative to the frame) or "screen" (relative to
-- the screen: the piece stays put when the frame moves)
function ns.Place(region, anchor, pos)
    if pos.anchor == "screen" then anchor = UIParent end
    region:ClearAllPoints()
    region:SetPoint(pos.point or "CENTER", anchor, pos.relPoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

-- Screen coordinates (pixels) of a point of a frame or region
local function PointPx(obj, point)
    local R = ns.R
    local l, r, t, b = R(obj:GetLeft()), R(obj:GetRight()), R(obj:GetTop()), R(obj:GetBottom())
    if not (l and r and t and b) then return nil end
    local x = point:find("LEFT") and l or point:find("RIGHT") and r or (l + r) / 2
    local y = point:find("TOP") and t or point:find("BOTTOM") and b or (t + b) / 2
    local s = obj.GetEffectiveScale and obj:GetEffectiveScale() or obj:GetParent():GetEffectiveScale()
    return x * s, y * s
end

local function Scale(region)
    return region.GetEffectiveScale and region:GetEffectiveScale() or region:GetParent():GetEffectiveScale()
end

-- Offsets that keep a piece exactly where it is now, for its point on the
-- given target's relPoint (nil while the piece is not on screen)
function ns.OffsetsFor(region, target, pos)
    local rx, ry = PointPx(region, pos.point or "CENTER")
    local tx, ty = PointPx(target, pos.relPoint or pos.point or "CENTER")
    if not rx or not tx then return nil end
    local s = Scale(region)
    return math.floor((rx - tx) / s + 0.5), math.floor((ry - ty) / s + 0.5)
end
ns.PieceScale = Scale
