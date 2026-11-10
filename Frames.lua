-------------------------------------------------------------------------------
-- Sigil - Unit frames (player, target, target of target)
--
-- Each frame is a secure unit button: left click targets, right click opens
-- the unit menu. Health and power are drawn with the values as the game
-- gives them (secret or not): a StatusBar accepts secret values.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

local FLAT = "Interface\\Buttons\\WHITE8X8"
local SMOOTH = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

ns.UNITS = { "player", "target", "targettarget", "focus", "pet", "party1", "party2", "party3", "party4" }
ns.frames = {}

-- Settings key of each unit: the four party frames share "party"
local CFG_KEY = { party1 = "party", party2 = "party", party3 = "party", party4 = "party" }
function ns.CfgKey(unit) return CFG_KEY[unit] or unit end

-- Frames that use a settings key ("party" -> party1..4)
function ns.UnitsOf(key)
    local out = {}
    for _, unit in ipairs(ns.UNITS) do
        if ns.CfgKey(unit) == key then out[#out + 1] = unit end
    end
    return out
end

-- Units whose events do not fire: they are refreshed every POLL seconds
local POLLED = { targettarget = true }
local POLL = 0.2

local UNIT_LABEL = {
    player = "Player", target = "Target", targettarget = "Target of target", focus = "Focus", pet = "Pet",
}

local function Label(unit)
    local n = unit:match("^party(%d)$")
    if n then return L["Party"] .. " " .. n end
    return L[UNIT_LABEL[unit]]
end

-- Events that mean "this frame shows another unit now"
local UNIT_CHANGED = {
    PLAYER_ENTERING_WORLD = true, PLAYER_TARGET_CHANGED = true, UNIT_TARGET = true,
    PLAYER_FOCUS_CHANGED = true, UNIT_PET = true, GROUP_ROSTER_UPDATE = true,
}

local function Num(v)
    if S(v) then return v end
    return v or 0
end

local function SetBar(bar, v, smooth)
    if smooth and SMOOTH then bar:SetValue(v, SMOOTH) else bar:SetValue(v) end
end

-------------------------------------------------------------------------------
-- Colors
-------------------------------------------------------------------------------
-- State of the unit that overrides any color: dead, offline, tapped (or nil)
local function StateKey(u)
    if ns.Fake(u) then return nil end
    if R(UnitIsConnected(u)) == false then return "offline" end
    if R(UnitIsDeadOrGhost(u)) then return "dead" end
    if not R(UnitIsPlayer(u)) and R(UnitIsTapDenied(u)) then return "tapped" end
end

-- Automatic health color: class for players, reaction for the rest
local function HealthColor(u)
    local fake = ns.Fake(u)
    if fake then
        if fake.player then return ns.ClassRGB(fake.classToken) end
        return ns.ReactionRGB(fake.reaction)
    end
    if R(UnitIsPlayer(u)) then
        local r, g, b = ns.ClassRGB(R(select(2, UnitClass(u))))
        if r then return r, g, b end
    end
    return ns.ReactionRGB(R(UnitReaction(u, "player")))
end

-------------------------------------------------------------------------------
-- Updates
-------------------------------------------------------------------------------
-- Health color: automatic, gradient by health, or custom. Dead, offline and
-- tapped units use their state color.
function ns.UpdateColor(f)
    local st = f.cfg.health.style
    local state = StateKey(f.unit)
    if state then
        local r, g, b = ns.StateRGB(state)
        ns.PaintBar(f.health, { bg = st.bg, bgCustom = st.bgCustom, bgBrightness = st.bgBrightness, bgAlpha = st.bgAlpha }, r, g, b)
        return
    end
    if st.color == "gradient" then
        local fake = ns.Fake(f.unit)
        local curve = ns.GradientCurve()
        if curve then
            local ok = pcall(function()
                local color
                if fake then color = curve:Evaluate(fake.hp / fake.maxhp)
                else color = UnitHealthPercent(f.unit, false, curve) end
                f.health:GetStatusBarTexture():SetVertexColor(color:GetRGB())
            end)
            if ok then
                -- the background cannot be darkened from a hidden color: neutral dark
                local k = st.bgBrightness or 0.25
                if st.bg == "custom" then
                    f.health.bg:SetVertexColor(st.bgCustom.r, st.bgCustom.g, st.bgCustom.b, st.bgAlpha or 0.9)
                else
                    f.health.bg:SetVertexColor(k * 0.6, k * 0.6, k * 0.6, st.bgAlpha or 0.9)
                end
                return
            end
        end
    end
    f.health:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    ns.PaintBar(f.health, st, HealthColor(f.unit))
end

-- Incoming heals and shields: bars that continue where the health ends
function ns.UpdatePrediction(f)
    local h = f.cfg.health
    local u = f.unit
    local fake = ns.Fake(u)
    local max = fake and fake.maxhp or Num(UnitHealthMax(u))
    if h.healPrediction and (fake or UnitGetIncomingHeals) then
        f.pred:SetMinMaxValues(0, max)
        f.pred:SetValue(fake and fake.maxhp * 0.05 or Num(UnitGetIncomingHeals(u)))
        f.pred:Show()
    else
        f.pred:Hide()
    end
    if h.absorbs and (fake or UnitGetTotalAbsorbs) then
        f.absorb:SetMinMaxValues(0, max)
        f.absorb:SetValue(fake and fake.maxhp * 0.04 or Num(UnitGetTotalAbsorbs(u)))
        f.absorb:Show()
    else
        f.absorb:Hide()
    end
end

function ns.UpdateHealth(f, jump)
    local u = f.unit
    local fake = ns.Fake(u)
    if fake then
        f.health:SetMinMaxValues(0, fake.maxhp)
        f.health:SetValue(fake.hp)
        return
    end
    f.health:SetMinMaxValues(0, Num(UnitHealthMax(u)))
    SetBar(f.health, Num(UnitHealth(u)), ns.P.smooth and not jump)
    -- the gradient follows the health
    if f.cfg.health.style.color == "gradient" then ns.UpdateColor(f) end
end

function ns.UpdatePowerValue(f, jump)
    if not f.power:IsShown() then return end
    local u = f.unit
    local fake = ns.Fake(u)
    if fake then
        f.power:SetMinMaxValues(0, fake.maxpower)
        f.power:SetValue(fake.power)
        return
    end
    f.power:SetMinMaxValues(0, Num(UnitPowerMax(u)))
    SetBar(f.power, Num(UnitPower(u)), ns.P.smooth and not jump)
end

function ns.UpdatePower(f, jump)
    if not f.power:IsShown() then return end
    local fake = ns.Fake(f.unit)
    local token = fake and fake.powerToken or R(select(2, UnitPowerType(f.unit)))
    ns.PaintBar(f.power, f.cfg.power.style, ns.PowerRGB(token))
    ns.UpdatePowerValue(f, jump)
end

function ns.UpdatePortrait(f)
    local c = f.cfg
    if c.portrait == "none" then return end
    local u = f.unit
    local p = f.portrait
    -- sample picture only for units that do not exist (your own stays real)
    if ns.Fake(u) and not UnitExists(u) then
        p.model:Hide()
        p.tex:Show()
        p.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return
    end
    if c.portraitStyle == "3d" then
        p.tex:Hide()
        p.model:Show()
        if R(UnitIsVisible(u)) then
            p.model:SetUnit(u)
            p.model:SetPortraitZoom(1)
            p.model:SetCamDistanceScale(1)
        else
            p.model:ClearModel()
        end
        return
    end
    p.model:Hide()
    p.tex:Show()
    local token = c.portraitStyle == "class" and R(UnitIsPlayer(u)) and R(select(2, UnitClass(u)))
    local coords = token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords then
        p.tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        p.tex:SetTexCoord(unpack(coords))
    else
        SetPortraitTexture(p.tex, u)
        p.tex:SetTexCoord(0.15, 0.85, 0.15, 0.85)
    end
end

function ns.UpdateTexts(f)
    for _, t in ipairs(f.texts) do ns.RunText(f, t) end
end

-- Texts shown only on mouseover or out of combat
function ns.UpdateTextVisibility(f)
    local combat = InCombatLockdown()
    for _, t in ipairs(f.texts) do
        local show = t.cfg.show or "always"
        local on = show == "always" or (show == "mouseover" and f.hover) or (show == "ooc" and not combat)
            or ns.testMode
        t.fs:SetAlpha(on and 1 or 0)
    end
end

-- Border when the mouse is over the frame, or when its unit is your target
function ns.UpdateHighlight(f)
    local hl = f.cfg.highlight or {}
    local color
    if hl.mouseover and f.hover then
        color = ns.Color("highlight", "mouseover")
    elseif hl.target and f.unit ~= "target" and not ns.Fake(f.unit) and R(UnitIsUnit(f.unit, "target")) then
        color = ns.Color("highlight", "target")
    end
    if color then
        f.hl:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
        f.hl:Show()
    else
        f.hl:Hide()
    end
end

-- Everything (unit change, show, test mode...)
function ns.UpdateAll(f)
    if not f:IsShown() then return end
    if not ns.Fake(f.unit) and not UnitExists(f.unit) then return end
    ns.UpdateColor(f)
    ns.UpdateHealth(f, true)
    ns.UpdatePrediction(f)
    ns.UpdatePower(f, true)
    ns.UpdateHighlight(f)
    ns.UpdateTextVisibility(f)
    ns.UpdatePortrait(f)
    ns.UpdateTexts(f)
    ns.UpdateAuras(f)
    ns.UpdateIcons(f)
    ns.UpdateFader(f)
    ns.UpdateCastbar(f)
    ns.UpdateThreat(f)
    ns.UpdateCombo(f)
    ns.UpdateExperience(f)
    ns.UpdateAltMana(f)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
-- Event -> functions(frame). Other files add theirs with ns.On.
-- Events that do not start with UNIT_ are registered for the whole game.
local HANDLERS = {}

function ns.On(event, func)
    HANDLERS[event] = HANDLERS[event] or {}
    table.insert(HANDLERS[event], func)
end

ns.On("UNIT_HEALTH", function(f) ns.UpdateHealth(f) ns.UpdateColor(f) end)
ns.On("UNIT_MAXHEALTH", function(f) ns.UpdateHealth(f) end)
ns.On("UNIT_POWER_FREQUENT", function(f) ns.UpdatePowerValue(f) end)
ns.On("UNIT_MAXPOWER", function(f) ns.UpdatePowerValue(f) end)
ns.On("UNIT_DISPLAYPOWER", function(f) ns.UpdatePower(f, true) end)
ns.On("UNIT_PORTRAIT_UPDATE", function(f) ns.UpdatePortrait(f) end)
ns.On("UNIT_MODEL_CHANGED", function(f) ns.UpdatePortrait(f) end)
ns.On("UNIT_FACTION", function(f) ns.UpdateColor(f) end)
ns.On("UNIT_CONNECTION", function(f) ns.UpdateColor(f) ns.UpdateHealth(f, true) end)
ns.On("UNIT_FLAGS", function(f) ns.UpdateColor(f) end)
ns.On("UNIT_HEAL_PREDICTION", function(f) ns.UpdatePrediction(f) end)
ns.On("UNIT_ABSORB_AMOUNT_CHANGED", function(f) ns.UpdatePrediction(f) end)
ns.On("UNIT_MAXHEALTH", function(f) ns.UpdatePrediction(f) end)
ns.On("PLAYER_REGEN_DISABLED", function(f) ns.UpdateTextVisibility(f) end)
ns.On("PLAYER_REGEN_ENABLED", function(f) ns.UpdateTextVisibility(f) end)

-- Units whose frame shows someone else when the target changes
local FOLLOWS_TARGET = { target = true, targettarget = true }

local function OnEvent(f, event, ...)
    if event == "PLAYER_TARGET_CHANGED" and not FOLLOWS_TARGET[f.unit] then
        ns.UpdateHighlight(f)
        return
    end
    if UNIT_CHANGED[event] then
        ns.UpdateAll(f)
        return
    end
    if not f:IsShown() or ns.Fake(f.unit) then return end
    local h = HANDLERS[event]
    if h then
        for _, func in ipairs(h) do func(f, ...) end
    end
    local list = f.textEvents[event]
    if list then
        for _, t in ipairs(list) do ns.RunText(f, t) end
    end
end

local function RegisterEvents(f)
    f:UnregisterAllEvents()
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    if FOLLOWS_TARGET[f.unit] or (f.cfg.highlight and f.cfg.highlight.target) then
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
    if f.unit == "targettarget" then f:RegisterUnitEvent("UNIT_TARGET", "target") end
    if f.unit == "focus" then f:RegisterEvent("PLAYER_FOCUS_CHANGED") end
    if f.unit == "pet" then f:RegisterUnitEvent("UNIT_PET", "player") end
    if CFG_KEY[f.unit] == "party" then f:RegisterEvent("GROUP_ROSTER_UPDATE") end
    if POLLED[f.unit] then return end
    local seen = {}
    local function Add(ev)
        if seen[ev] then return end
        seen[ev] = true
        if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(ev) then return end
        if ev:find("^UNIT_") then
            f:RegisterUnitEvent(ev, f.unit)
        else
            f:RegisterEvent(ev)
        end
    end
    for ev in pairs(HANDLERS) do Add(ev) end
    for ev in pairs(f.textEvents) do Add(ev) end
end

-------------------------------------------------------------------------------
-- Building and layout
-------------------------------------------------------------------------------
local function NewBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(FLAT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(FLAT)
    return bar
end

local function Build(unit)
    local f = CreateFrame("Button", "SigilFrame_" .. unit, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
    f.unit = unit
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:RegisterForClicks("AnyUp")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Clique (click-casting) and similar addons read this table
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true

    f.health = NewBar(f)
    f.power = NewBar(f)
    -- incoming heals and shields continue where the health fill ends
    if f.health.SetClipsChildren then f.health:SetClipsChildren(true) end
    f.pred = CreateFrame("StatusBar", nil, f.health)
    f.absorb = CreateFrame("StatusBar", nil, f.health)
    for _, b in ipairs({ f.pred, f.absorb }) do
        b:SetStatusBarTexture(FLAT)
        b:SetMinMaxValues(0, 1)
        b:SetValue(0)
    end

    -- highlight border (mouseover / your target)
    f.hl = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.hl:SetPoint("TOPLEFT", -1, 1)
    f.hl:SetPoint("BOTTOMRIGHT", 1, -1)
    f.hl:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    f.hl:Hide()

    f.portrait = CreateFrame("Frame", nil, f)
    f.portrait.tex = f.portrait:CreateTexture(nil, "ARTWORK")
    f.portrait.tex:SetAllPoints()
    f.portrait.model = CreateFrame("PlayerModel", nil, f.portrait)
    f.portrait.model:SetAllPoints()
    f.portrait.model:Hide()

    f.overlay = CreateFrame("Frame", nil, f)
    f.overlay:SetAllPoints()
    f.overlay:SetFrameLevel(f.health:GetFrameLevel() + 5)

    f.texts, f.textEvents, f.fontStrings = {}, {}, {}

    f:SetScript("OnEvent", OnEvent)
    f:HookScript("OnShow", ns.UpdateAll)
    f:HookScript("OnEnter", function(self)
        self.hover = true
        ns.UpdateHighlight(self)
        ns.UpdateTextVisibility(self)
        if not UnitExists(self.unit) then return end
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    f:HookScript("OnLeave", function(self)
        self.hover = false
        ns.UpdateHighlight(self)
        ns.UpdateTextVisibility(self)
        GameTooltip:Hide()
    end)

    -- Every POLL seconds: range, and everything for the units without events
    local elapsed = 0
    f:HookScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < POLL then return end
        elapsed = 0
        if ns.Fake(self.unit) then return end
        if POLLED[self.unit] then
            ns.UpdateColor(self)
            ns.UpdateHealth(self, true)
            ns.UpdatePowerValue(self, true)
            ns.UpdateTexts(self)
            ns.UpdateIcons(self)
            ns.UpdateCastbar(self)
        end
        ns.UpdateFader(self)
        ns.UpdateThreat(self)
    end)

    return f
end

-- Texts: fontstrings, compiled code and the events that refresh each one
function ns.BuildTexts(f)
    wipe(f.texts)
    wipe(f.textEvents)
    for _, fs in ipairs(f.fontStrings) do fs:Hide() end
    for i, cfg in ipairs(f.cfg.texts) do
        local fs = f.fontStrings[i]
        if not fs then
            fs = f.overlay:CreateFontString(nil, "OVERLAY")
            fs:SetWordWrap(false)
            f.fontStrings[i] = fs
        end
        -- a damaged size (not a number) goes back to the default; texts from
        -- older versions get the look settings every text has
        if type(cfg.size) ~= "number" then cfg.size = 11 end
        if cfg.font == nil then cfg.font = false end
        if cfg.outline == nil then cfg.outline = false end
        if cfg.shadow == nil then cfg.shadow = false end
        if cfg.colorMode == nil then cfg.colorMode = "code" end
        if cfg.show == nil then cfg.show = "always" end
        ns.StyleText(fs, cfg, 11)
        fs:SetJustifyH(cfg.justify or "LEFT")
        fs:ClearAllPoints()
        local region = cfg.region == "power" and f.power:IsShown() and f.power
            or cfg.region == "frame" and f or f.health
        fs:SetPoint(cfg.point or "LEFT", region, cfg.point or "LEFT", cfg.x or 0, cfg.y or 0)
        fs:SetText("")
        fs:Show()
        local fn, err = ns.CompileText(cfg.code)
        if not fn then ns.Print(L["Error in a text of %s: %s"]:format(f.unit, tostring(err))) end
        local t = { fs = fs, fn = fn, cfg = cfg }
        f.texts[#f.texts + 1] = t
        for _, ev in ipairs(cfg.events or {}) do
            f.textEvents[ev] = f.textEvents[ev] or {}
            table.insert(f.textEvents[ev], t)
        end
    end
end

-- Size, position, portrait and bars. Secure frame: only out of combat.
function ns.Layout(f)
    local c = f.cfg
    f:SetSize(c.width, c.height)
    f:ClearAllPoints()
    local n = tonumber(f.unit:match("^party(%d)$"))
    if n and n > 1 then
        -- party 2-4 go after the previous one
        local prev = ns.frames["party" .. (n - 1)]
        local gap = c.spacing or 8
        local grow = c.grow or "DOWN"
        if grow == "UP" then f:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, gap)
        elseif grow == "RIGHT" then f:SetPoint("TOPLEFT", prev, "TOPRIGHT", gap, 0)
        elseif grow == "LEFT" then f:SetPoint("TOPRIGHT", prev, "TOPLEFT", -gap, 0)
        else f:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap) end
    else
        local p = c.point
        f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    end

    f:SetScale(c.scale or 1)

    -- background and border
    local edge = c.borderSize or 1
    f:SetBackdrop({ bgFile = FLAT, edgeFile = edge > 0 and FLAT or nil, edgeSize = math.max(1, edge) })
    local bg, bd = c.background, c.border
    f:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    if edge > 0 then f:SetBackdropBorderColor(bd.r, bd.g, bd.b, bd.a or 1) end
    local inset = math.max(0, edge)

    -- portrait (square, or the chosen width)
    local inner = c.height - 2 * inset
    local left, right = inset, inset
    local portrait = f.portrait
    portrait:ClearAllPoints()
    if c.portrait == "left" or c.portrait == "right" then
        local pw = (c.portraitWidth and c.portraitWidth > 0) and c.portraitWidth or inner
        portrait:SetSize(pw, inner)
        if c.portrait == "left" then
            portrait:SetPoint("TOPLEFT", inset, -inset)
            left = inset + pw + 1
        else
            portrait:SetPoint("TOPRIGHT", -inset, -inset)
            right = inset + pw + 1
        end
        portrait:Show()
    else
        portrait:Hide()
    end

    -- health and power
    local ph = c.power.height or 0
    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", left, -inset)
    f.health:SetPoint("TOPRIGHT", -right, -inset)
    if ph > 0 then
        f.health:SetHeight(inner - ph - 1)
        f.power:ClearAllPoints()
        f.power:SetPoint("BOTTOMLEFT", left, inset)
        f.power:SetPoint("BOTTOMRIGHT", -right, inset)
        f.power:SetHeight(ph)
        f.power:Show()
    else
        f.health:SetHeight(inner)
        f.power:Hide()
    end
    ns.StyleBar(f.health, c.health.style)
    ns.StyleBar(f.power, c.power.style)

    -- incoming heals and shields after the end of the health fill
    local fill = f.health:GetStatusBarTexture()
    local vertical = c.health.style.orientation == "VERTICAL"
    local reverse = c.health.style.reverse
    local function Follow(bar, after, color)
        bar:SetStatusBarTexture(ns.Texture())
        bar:SetStatusBarColor(color.r, color.g, color.b, color.a or 0.5)
        bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
        bar:SetReverseFill(reverse and true or false)
        bar:ClearAllPoints()
        if vertical then
            local from, to = reverse and "TOP" or "BOTTOM", reverse and "BOTTOM" or "TOP"
            bar:SetPoint(from .. "LEFT", after, to .. "LEFT")
            bar:SetPoint(from .. "RIGHT", after, to .. "RIGHT")
            bar:SetHeight(f.health:GetHeight())
        else
            local from, to = reverse and "RIGHT" or "LEFT", reverse and "LEFT" or "RIGHT"
            bar:SetPoint("TOP" .. from, after, "TOP" .. to)
            bar:SetPoint("BOTTOM" .. from, after, "BOTTOM" .. to)
            bar:SetWidth(f.health:GetWidth() > 0 and f.health:GetWidth() or (c.width - left - right))
        end
    end
    Follow(f.pred, fill, ns.Color("prediction", "heal"))
    Follow(f.absorb, f.pred:GetStatusBarTexture(), ns.Color("prediction", "absorb"))

    -- highlight border color and thickness follow the frame border
    f.hl:SetFrameLevel(f.overlay:GetFrameLevel() + 3)

    ns.BuildTexts(f)
    ns.LayoutAuras(f)
    ns.LayoutIcons(f)
    ns.LayoutCastbar(f)
    ns.LayoutThreat(f)
    ns.LayoutCombo(f)
    ns.LayoutExperience(f)
    ns.LayoutTotems(f)
    ns.LayoutAltMana(f)
    ns.LayoutCombatText(f)
    ns.LayoutGCD(f)
    RegisterEvents(f)
end

-------------------------------------------------------------------------------
-- Visibility: shown while the unit exists (or always in test mode)
-------------------------------------------------------------------------------
-- Party frames hide in raids when asked: a secure state driver decides
local function Stop(f)
    UnregisterUnitWatch(f)
    if UnregisterStateDriver then UnregisterStateDriver(f, "visibility") end
end

-- Macro conditions that decide when the frame is shown. The game evaluates
-- them itself, so they also work in combat.
local function VisibilityRule(f)
    local c = f.cfg
    local parts = {}
    if CFG_KEY[f.unit] == "party" and c.hideInRaid then parts[#parts + 1] = "[group:raid] hide" end
    parts[#parts + 1] = ("[@%s,noexists] hide"):format(f.unit)
    local mode = c.visibility or "always"
    if mode == "combat" then
        parts[#parts + 1] = "[combat] show; hide"
    elseif mode == "combatTarget" then
        parts[#parts + 1] = "[combat] show; [@target,exists] show; hide"
    elseif mode == "custom" and c.visibilityCustom and c.visibilityCustom ~= "" then
        parts[#parts + 1] = c.visibilityCustom
    else
        parts[#parts + 1] = "show"
    end
    return table.concat(parts, "; ")
end
ns.VisibilityRule = VisibilityRule

local function ApplyVisibility(f)
    Stop(f)
    if not f.cfg.enabled then
        f:Hide()
    elseif ns.testMode then
        f:Show()
    elseif RegisterStateDriver then
        RegisterStateDriver(f, "visibility", VisibilityRule(f))
    else
        RegisterUnitWatch(f)
    end
end

function ns.CreateFrames()
    for _, unit in ipairs(ns.UNITS) do
        local f = Build(unit)
        f.cfg = ns.P.units[ns.CfgKey(unit)]
        ns.frames[unit] = f
    end
    -- in order: party 2-4 are anchored to the previous one
    for _, unit in ipairs(ns.UNITS) do
        local f = ns.frames[unit]
        ns.Layout(f)
        ApplyVisibility(f)
        ns.UpdateAll(f)
    end
end

-- Applies the settings of a frame again (options window, profile change).
-- key: a unit or a settings key ("party" = the four party frames).
-- Secure frames: waits for the end of combat if needed.
function ns.ApplyUnit(key)
    local units = ns.UnitsOf(ns.CfgKey(key))
    ns.RunOOC("apply:" .. ns.CfgKey(key), function()
        for _, unit in ipairs(units) do
            local f = ns.frames[unit]
            if f then
                f.cfg = ns.P.units[ns.CfgKey(unit)]
                ns.Layout(f)
                ApplyVisibility(f)
                ns.UpdateAll(f)
            end
        end
    end)
end

function ns.ApplyAll()
    local done = {}
    for _, unit in ipairs(ns.UNITS) do
        local key = ns.CfgKey(unit)
        if not done[key] then
            done[key] = true
            ns.ApplyUnit(key)
        end
    end
    ns.HideBlizzard()
end

-------------------------------------------------------------------------------
-- Test mode and moving
-------------------------------------------------------------------------------
function ns.SetTestMode(on)
    ns.RunOOC("test", function()
        ns.testMode = on
        for _, f in pairs(ns.frames) do
            ApplyVisibility(f)
            ns.UpdateAll(f)
        end
        ns.Print(on and L["Test mode on."] or L["Test mode off."])
    end)
end

local function Mover(f)
    local m = CreateFrame("Frame", nil, f, "BackdropTemplate")
    m:SetAllPoints()
    m:SetFrameLevel(f.overlay:GetFrameLevel() + 10)
    m:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    m:SetBackdropColor(0.45, 0.3, 0.75, 0.35)
    m:SetBackdropBorderColor(0.7, 0.55, 1, 1)
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    m.label:SetPoint("CENTER")
    m.label:SetText(Label(f.unit))
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    -- party 2-4 follow party 1: dragging any of them moves party 1
    local n = tonumber(f.unit:match("^party(%d)$"))
    local lead = (n and n > 1) and ns.frames.party1 or f
    m:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        lead:StartMoving()
    end)
    m:SetScript("OnDragStop", function()
        lead:StopMovingOrSizing()
        local p, _, rp, x, y = lead:GetPoint(1)
        lead.cfg.point = { p, "UIParent", rp, math.floor(x + 0.5), math.floor(y + 0.5) }
        if ns.OnFrameMoved then ns.OnFrameMoved(lead.unit) end
    end)
    m:Hide()
    return m
end

function ns.SetUnlocked(on)
    ns.RunOOC("unlock", function()
        ns.unlocked = on
        for _, f in pairs(ns.frames) do
            f.mover = f.mover or Mover(f)
            f.mover:SetShown(on)
        end
        if on ~= ns.testMode then ns.SetTestMode(on) end
        ns.Print(on and L["Frames unlocked: drag them. /sigil lock to finish."] or L["Frames locked."])
    end)
end
