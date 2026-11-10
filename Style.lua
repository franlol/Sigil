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

-- Texture, orientation, fill direction and spark (bar.bg = background texture)
function ns.StyleBar(bar, st)
    local tex = (st.texture and st.texture ~= "") and st.texture or ns.Texture()
    bar:SetStatusBarTexture(tex)
    if bar.bg then bar.bg:SetTexture(tex) end
    local vertical = st.orientation == "VERTICAL"
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill(st.reverse and true or false)

    if st.spark then
        if not bar.spark then
            bar.spark = bar:CreateTexture(nil, "OVERLAY")
            bar.spark:SetTexture(SPARK)
            bar.spark:SetBlendMode("ADD")
        end
        local fill = bar:GetStatusBarTexture()
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
-- Position: { point, relPoint, x, y } relative to an anchor frame
-------------------------------------------------------------------------------
function ns.Place(region, anchor, pos)
    region:ClearAllPoints()
    region:SetPoint(pos.point or "CENTER", anchor, pos.relPoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
end

-------------------------------------------------------------------------------
-- Old settings -> the shared blocks (runs after the defaults are filled in)
-------------------------------------------------------------------------------
function ns.Migrate(P)
    for _, u in pairs(P.units or {}) do
        if u.powerHeight ~= nil then
            u.power.height = u.powerHeight
            u.powerHeight = nil
        end
        if u.healthColor ~= nil then
            u.health.style.color = u.healthColor == "custom" and "custom" or "auto"
            if u.customColor then u.health.style.custom = u.customColor end
            u.healthColor, u.customColor = nil, nil
        end
        if u.bgBrightness ~= nil then
            u.health.style.bgBrightness = u.bgBrightness
            u.power.style.bgBrightness = u.bgBrightness
            u.bgBrightness = nil
        end
        if u.fader and u.fader.mode ~= nil then
            u.fader.range = u.fader.mode == "range"
            u.fader.combat = u.fader.mode == "combat"
            u.fader.mode = nil
        end
        if u.combo and u.combo.color then
            u.combo.style.color = "custom"
            u.combo.style.custom = u.combo.color
            u.combo.color = nil
        end
    end
end
