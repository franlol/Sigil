-------------------------------------------------------------------------------
-- LibFlatyUI-1.0
--
-- Flat, dark controls for addon settings windows, built only from plain
-- frames, textures and font strings (no Blizzard UI templates other than
-- BackdropTemplate), so the look does not change between game versions.
--
-- Usage
--   local UI = LibStub("LibFlatyUI-1.0"):New({ accent = { 0.7, 0.55, 1 } })
--   local win = UI.Window({ name = "MyAddonOptions", title = "MyAddon" })
--   win:AddNav("general", "General", function(container)
--       local page = UI.Page(container, 2)
--       local card = page:Add(1, UI.Card(page.content, "Look"))
--       card:Add(UI.Check(card, "Enable", getter, setter))
--   end)
--   win:Select("general")
--
-- Instances
--   :New(theme) returns an independent instance with its own colors and its
--   own list of controls. Every constructor of an instance is a plain
--   function (UI.Button(...), not UI:Button(...)).
--
-- Controls
--   Every control is a "row": a frame that takes the width its card gives
--   it. Rows accept an options table:
--     showIf()   -> the row is hidden when it returns false (the card closes
--                   the gap)
--     enableIf() -> the row is greyed out and ignores clicks when false
--     tip        -> help text shown in a tooltip when hovering the row
--   get/set pairs read and write the value the control shows. After a user
--   change the instance calls UI.OnChange(), if defined (usually to call
--   UI.RefreshAll()).
-------------------------------------------------------------------------------

local MAJOR, MINOR = "LibFlatyUI-1.0", 5
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local FLAT = "Interface\\Buttons\\WHITE8X8"

-------------------------------------------------------------------------------
-- Theme
-------------------------------------------------------------------------------
lib.defaultTheme = {
    accent = { 0.27, 0.75, 0.45 },          -- brand color: marks, thumbs, focus
    window = { 0.06, 0.06, 0.08, 0.97 },
    windowBorder = { 0.2, 0.2, 0.25, 1 },
    header = { 0.08, 0.1, 0.15, 1 },
    nav = { 0.1, 0.1, 0.12, 1 },
    navSelected = nil,                      -- (nil: a dark shade of the accent)
    button = { 0.15, 0.15, 0.18, 1 },
    border = { 0.25, 0.25, 0.3, 1 },
    field = { 0.05, 0.05, 0.06, 1 },
    fieldDark = { 0.03, 0.03, 0.04, 1 },
    card = { 0.095, 0.095, 0.118, 1 },
    cardBorder = { 0.19, 0.19, 0.235, 1 },
    text = { 1, 1, 1 },
    muted = { 0.65, 0.65, 0.65 },
    danger = { 1, 0.45, 0.35 },
    success = { 0.42, 0.84, 0.42 },
    labelFont = "GameFontHighlightSmall",
    titleFont = "GameFontNormal",
    rowHeight = 18,        -- height of a one-line control
    gap = 10,              -- space between rows of a card
    pad = 10,              -- inner margin of a card
}

local function Merge(base, over)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

-- Only one dropdown list can be open at a time, for every instance
lib.openMenu = lib.openMenu
lib.closer = lib.closer or CreateFrame("Frame")
pcall(lib.closer.RegisterEvent, lib.closer, "GLOBAL_MOUSE_DOWN")
lib.closer:SetScript("OnEvent", function()
    local m = lib.openMenu
    if not m then return end
    if m:IsMouseOver() or (m.owner and m.owner:IsMouseOver()) then return end
    m:Hide()
    lib.openMenu = nil
end)

-------------------------------------------------------------------------------
-- New instance
-------------------------------------------------------------------------------
function lib:New(theme)
    local T = Merge(lib.defaultTheme, theme)
    local A = T.accent
    T.navSelected = T.navSelected or { A[1] * 0.3, A[2] * 0.3, A[3] * 0.3, 1 }
    local UI = { theme = T, widgets = {}, pages = {}, inputs = {} }

    local function Register(w)
        table.insert(UI.widgets, w)
        return w
    end

    local function Changed()
        if UI.OnChange then UI.OnChange() end
    end

    ---------------------------------------------------------------------------
    -- Basics
    ---------------------------------------------------------------------------
    function UI.Backdrop(f, bg, border)
        f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
        f:SetBackdropColor(unpack(bg or T.field))
        f:SetBackdropBorderColor(unpack(border or T.border))
    end

    -- Font string. fontObject: a font object name (theme label font by default)
    function UI.Text(parent, text, fontObject, color)
        local fs = parent:CreateFontString(nil, "OVERLAY", fontObject or T.labelFont)
        fs:SetJustifyH("LEFT")
        fs:SetText(text or "")
        if color then fs:SetTextColor(unpack(color)) end
        return fs
    end

    -- Tooltip with a title and an optional wrapped description
    function UI.Tip(f, title, text)
        if not title and not text then return end
        f:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(title or "", 1, 1, 1)
            if text then GameTooltip:AddLine(text, T.muted[1], T.muted[2], T.muted[3], true) end
            GameTooltip:Show()
        end)
        f:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function Hover(f, on)
        if on then f:SetBackdropBorderColor(A[1], A[2], A[3], 1)
        else f:SetBackdropBorderColor(unpack(f.borderColor or T.border)) end
    end

    -- Base frame of every control
    local function Row(parent, height, opts)
        local r = CreateFrame("Frame", nil, parent)
        r:SetSize(200, height)
        opts = opts or {}
        r.showIf, r.enableIf = opts.showIf, opts.enableIf
        if opts.tip then
            r:EnableMouse(true)
            if r.SetMouseClickEnabled then r:SetMouseClickEnabled(false) end
            UI.Tip(r, opts.label, opts.tip)
        end
        return r
    end
    UI.Row = Row

    -- Grey and unclickable, without changing the layout
    function UI.SetEnabled(w, on)
        w:SetAlpha(on and 1 or 0.35)
        if not w.blocker then
            if on then return end
            w.blocker = CreateFrame("Frame", nil, w)
            w.blocker:SetAllPoints()
            w.blocker:EnableMouse(true)
        end
        w.blocker:SetFrameLevel(w:GetFrameLevel() + 30)
        w.blocker:SetShown(not on)
    end

    ---------------------------------------------------------------------------
    -- Buttons
    ---------------------------------------------------------------------------
    -- style: nil, "accent" (filled with the brand color) or "danger"
    function UI.Button(parent, text, w, h, onClick, style)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(w or 100, h or 20)
        if style == "accent" then
            b.borderColor = { A[1], A[2], A[3], 1 }
            UI.Backdrop(b, { A[1] * 0.4, A[2] * 0.4, A[3] * 0.4, 1 }, b.borderColor)
        else
            b.borderColor = T.border
            UI.Backdrop(b, T.button)
        end
        b.text = UI.Text(b, text, T.labelFont, style == "danger" and T.danger or nil)
        b.text:SetPoint("CENTER")
        b.text:SetJustifyH("CENTER")
        b:SetScript("OnEnter", function(self) Hover(self, true) end)
        b:SetScript("OnLeave", function(self) Hover(self, false) end)
        b:SetScript("OnClick", onClick)
        return b
    end

    -- Turns a button into a two-step one: the first click asks to confirm,
    -- the second one (within 3 seconds) runs the action
    function UI.Confirm(b, armedText)
        local action = b:GetScript("OnClick")
        local saved, r, g, bl
        local token = 0
        local function Disarm()
            if not b.armed then return end
            b.armed = nil
            b.text:SetText(saved)
            b.text:SetTextColor(r, g, bl)
        end
        b:SetScript("OnClick", function(self, ...)
            if self.armed then
                Disarm()
                if action then action(self, ...) end
                return
            end
            saved = self.text:GetText()
            r, g, bl = self.text:GetTextColor()
            self.armed = true
            self.text:SetText(armedText or UI.strings.confirm)
            self.text:SetTextColor(1, 0.8, 0.3)
            token = token + 1
            local mine = token
            C_Timer.After(3, function() if token == mine then Disarm() end end)
        end)
        b:HookScript("OnHide", Disarm)
        return b
    end

    -- Row of buttons sharing the width. list = { { text, onClick, style, tip }, ... }
    function UI.Buttons(parent, list, opts)
        local r = Row(parent, 20, opts)
        r.buttons = {}
        for i, def in ipairs(list) do
            local b = UI.Button(r, def[1], 80, 20, def[2], def[3])
            if def[4] then UI.Tip(b, def[1], def[4]) end
            r.buttons[i] = b
        end
        r.OnWidth = function(w)
            local n = #r.buttons
            local bw = (w - (n - 1) * 6) / n
            for i, b in ipairs(r.buttons) do
                b:ClearAllPoints()
                b:SetPoint("LEFT", (i - 1) * (bw + 6), 0)
                b:SetWidth(bw)
            end
        end
        return r
    end

    ---------------------------------------------------------------------------
    -- Check box (small square with a brand-color mark; the mark fades in/out)
    ---------------------------------------------------------------------------
    local function FadeTo(region, target, duration)
        region.fadeTarget = target
        local holder = region.fadeHolder
        if not holder:IsVisible() then region:SetAlpha(target) return end
        holder:SetScript("OnUpdate", function(self, elapsed)
            local a = region:GetAlpha()
            local step = elapsed / duration
            a = a < target and math.min(target, a + step) or math.max(target, a - step)
            region:SetAlpha(a)
            if a == target then self:SetScript("OnUpdate", nil) end
        end)
    end

    function UI.Check(parent, label, get, set, opts)
        opts = opts or {}
        opts.label = label
        local r = Row(parent, T.rowHeight, opts)
        local c = CreateFrame("Button", nil, r, "BackdropTemplate")
        c:SetSize(14, 14)
        c:SetPoint("LEFT")
        c.borderColor = T.border
        UI.Backdrop(c, T.field)
        c.mark = c:CreateTexture(nil, "OVERLAY")
        c.mark:SetPoint("TOPLEFT", 3, -3)
        c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
        c.mark:SetColorTexture(A[1], A[2], A[3], 1)
        c.mark.fadeHolder = c
        r.label = UI.Text(r, label)
        r.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
        r.label:SetPoint("RIGHT")
        r.label:SetWordWrap(false)
        r.box = c
        r.OnWidth = function(w) c:SetHitRectInsets(0, -(w - 14), -2, -2) end
        r.Refresh = function(_, animate)
            local target = get() and 1 or 0
            if animate then FadeTo(c.mark, target, 0.12)
            elseif c.mark.fadeTarget ~= target or not c:GetScript("OnUpdate") then
                c:SetScript("OnUpdate", nil)
                c.mark.fadeTarget = target
                c.mark:SetAlpha(target)
            end
        end
        c:SetScript("OnClick", function()
            set(not get())
            r.Refresh(r, true)
            Changed()
        end)
        c:SetScript("OnEnter", function(self) Hover(self, true) end)
        c:SetScript("OnLeave", function(self) Hover(self, false) end)
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Switch (on / off) with a sliding knob
    ---------------------------------------------------------------------------
    function UI.Switch(parent, label, get, set, opts)
        opts = opts or {}
        opts.label = label
        local r = Row(parent, T.rowHeight + 2, opts)
        r.label = UI.Text(r, label)
        r.label:SetPoint("LEFT")
        r.label:SetPoint("RIGHT", -40, 0)
        r.label:SetWordWrap(false)

        local W, H, K = 28, 14, 10
        local sw = CreateFrame("Button", nil, r, "BackdropTemplate")
        sw:SetSize(W, H)
        sw:SetPoint("RIGHT")
        sw.borderColor = T.border
        UI.Backdrop(sw)
        sw.knob = sw:CreateTexture(nil, "OVERLAY")
        sw.knob:SetSize(K, K)
        r.switch = sw
        r.OnWidth = function(w) sw:SetHitRectInsets(-(w - W), 0, -3, -3) end

        local travel = W - 4 - K
        local function Mix(a, b, t) return a + (b - a) * t end
        local function Paint(p)
            local t = p * p * (3 - 2 * p)
            sw.knob:ClearAllPoints()
            sw.knob:SetPoint("LEFT", 2 + travel * t, 0)
            sw.knob:SetColorTexture(Mix(T.muted[1], 1, t), Mix(T.muted[2], 1, t), Mix(T.muted[3], 1, t), 1)
            sw:SetBackdropColor(Mix(T.field[1], A[1] * 0.7, t), Mix(T.field[2], A[2] * 0.7, t), Mix(T.field[3], A[3] * 0.7, t), 1)
        end
        local function Animate(self, elapsed)
            local step = elapsed / 0.15
            self.pos = self.pos < self.target and math.min(self.target, self.pos + step) or math.max(self.target, self.pos - step)
            Paint(self.pos)
            if self.pos == self.target then self:SetScript("OnUpdate", nil) end
        end
        r.Refresh = function(_, animate)
            local target = get() and 1 or 0
            if sw.target == target and sw:GetScript("OnUpdate") then return end
            sw.target = target
            if animate and sw.pos and sw:IsVisible() then
                sw:SetScript("OnUpdate", Animate)
            else
                sw:SetScript("OnUpdate", nil)
                sw.pos = target
                Paint(target)
            end
        end
        sw:SetScript("OnClick", function()
            set(not get())
            r.Refresh(r, true)
            Changed()
        end)
        sw:SetScript("OnEnter", function(self) Hover(self, true) end)
        sw:SetScript("OnLeave", function(self) Hover(self, false) end)
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Group of check boxes in columns (several on/off values at once)
    -- options = { { value, label }, ... }; get(value) -> bool; set(value, bool)
    ---------------------------------------------------------------------------
    function UI.CheckGroup(parent, label, options, get, set, opts)
        opts = opts or {}
        opts.label = label
        local columns = opts.columns or 2
        local top = label and 16 or 0
        local rows = math.ceil(#options / columns)
        local r = Row(parent, top + rows * (T.rowHeight + 2), opts)
        if label then
            r.label = UI.Text(r, label)
            r.label:SetPoint("TOPLEFT")
        end
        r.items = {}
        for i, o in ipairs(options) do
            local value = o[1]
            local item = UI.Check(r, o[2], function() return get(value) end, function(v) set(value, v) end)
            r.items[i] = item
        end
        r.OnWidth = function(w)
            local cw = math.floor(w / columns)
            for i, item in ipairs(r.items) do
                local col = (i - 1) % columns
                local row = math.floor((i - 1) / columns)
                item:ClearAllPoints()
                item:SetPoint("TOPLEFT", col * cw, -top - row * (T.rowHeight + 2))
                item:SetWidth(cw - 6)
                item.OnWidth(cw - 6)
            end
        end
        return r
    end

    ---------------------------------------------------------------------------
    -- Slider: label and value on top, track below. The mouse wheel and the
    -- < > buttons move it one step; clicking the value lets you type it.
    -- opts.format(value) -> text shown as the value
    ---------------------------------------------------------------------------
    function UI.Slider(parent, label, minV, maxV, step, get, set, opts)
        opts = opts or {}
        opts.label = label
        local fmt = opts.format
        local r = Row(parent, 34, opts)
        r.label = UI.Text(r, label)
        r.label:SetPoint("TOPLEFT")

        local value = CreateFrame("EditBox", nil, r)
        value:SetSize(70, 14)
        value:SetPoint("TOPRIGHT", 0, 1)
        value:SetFontObject(T.labelFont)
        value:SetJustifyH("RIGHT")
        value:SetAutoFocus(false)

        local s = CreateFrame("Slider", nil, r, "BackdropTemplate")
        s:SetOrientation("HORIZONTAL")
        s:SetPoint("TOPLEFT", 18, -17)
        s:SetPoint("TOPRIGHT", -18, -17)
        s:SetHeight(10)
        UI.Backdrop(s)
        local thumb = s:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(A[1], A[2], A[3], 1)
        thumb:SetSize(8, 12)
        s:SetThumbTexture(thumb)
        s:SetMinMaxValues(minV, maxV)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)

        local function Round(v)
            v = math.floor(v / step + 0.5) * step
            if step < 1 then v = tonumber(("%.2f"):format(v)) end
            return math.min(maxV, math.max(minV, v))
        end
        local function Show(v) value:SetText(fmt and fmt(v) or tostring(v)) end
        local function Commit(v)
            v = Round(v)
            if v ~= get() then
                set(v)
                Changed()
            end
            s:SetValue(v)
            Show(v)
        end

        s:SetScript("OnValueChanged", function(_, v, user)
            v = Round(v)
            Show(v)
            if user and v ~= get() then set(v) end
        end)
        s:SetScript("OnMouseUp", Changed)
        -- no mouse wheel: it would catch the wheel meant to scroll the page
        -- (use the < > buttons, drag, or type the value)

        value:SetScript("OnEditFocusGained", function(self) self:SetText(tostring(get())) self:HighlightText() end)
        value:SetScript("OnEnterPressed", function(self)
            local n = tonumber(self:GetText())
            self:ClearFocus()
            if n then Commit(n) else Show(get()) end
        end)
        value:SetScript("OnEscapePressed", function(self) self:ClearFocus() Show(get()) end)
        value:SetScript("OnEditFocusLost", function() Show(Round(get() or minV)) end)

        local minus = UI.Button(r, "<", 14, 14, function() Commit((get() or minV) - step) end)
        minus:SetPoint("RIGHT", s, "LEFT", -3, 0)
        local plus = UI.Button(r, ">", 14, 14, function() Commit((get() or minV) + step) end)
        plus:SetPoint("LEFT", s, "RIGHT", 3, 0)

        r.Refresh = function()
            local v = get() or minV
            s:SetValue(v)
            Show(Round(v))
        end
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Segmented control: a few exclusive options side by side
    -- options = { { value, label }, ... }
    ---------------------------------------------------------------------------
    function UI.Segmented(parent, label, options, get, set, opts)
        opts = opts or {}
        opts.label = label
        local top = label and -16 or 0
        local r = Row(parent, (label and 16 or 0) + 20, opts)
        if label then
            r.label = UI.Text(r, label)
            r.label:SetPoint("TOPLEFT")
        end
        r.buttons = {}
        for i, o in ipairs(options) do
            local b = UI.Button(r, o[2], 50, 20, function()
                set(o[1])
                r.Refresh()
                Changed()
            end)
            b.value = o[1]
            r.buttons[i] = b
        end
        r.OnWidth = function(w)
            local n = #r.buttons
            local bw = (w - (n - 1) * 2) / n
            for i, b in ipairs(r.buttons) do
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (i - 1) * (bw + 2), top)
                b:SetWidth(bw)
            end
        end
        r.Refresh = function()
            local cur = get()
            for _, b in ipairs(r.buttons) do
                if b.value == cur then
                    b.borderColor = { A[1], A[2], A[3], 1 }
                    b:SetBackdropColor(A[1] * 0.3, A[2] * 0.3, A[3] * 0.3, 1)
                    b.text:SetTextColor(1, 1, 1)
                else
                    b.borderColor = T.border
                    b:SetBackdropColor(unpack(T.button))
                    b.text:SetTextColor(unpack(T.muted))
                end
                b:SetBackdropBorderColor(unpack(b.borderColor))
            end
        end
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Scroll bar: draggable, with a brand-color thumb.
    -- onScroll(position) is called when the user moves it.
    -- bar:SetRange(max, visibleFraction), bar:SetPos(position)
    ---------------------------------------------------------------------------
    -- Built by hand (not a Slider widget): the thumb follows the cursor and
    -- the top of the bar is always the top of the content, in every client.
    function UI.ScrollBar(parent, onScroll)
        local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        bar:SetWidth(8)
        UI.Backdrop(bar, T.fieldDark, { 0.2, 0.2, 0.25, 1 })
        bar:EnableMouse(true)
        local thumb = CreateFrame("Frame", nil, bar)
        thumb:SetSize(6, 16)
        thumb:EnableMouse(true)
        thumb.tex = thumb:CreateTexture(nil, "OVERLAY")
        thumb.tex:SetAllPoints()
        thumb.tex:SetColorTexture(A[1], A[2], A[3], 0.9)
        bar.thumb = thumb
        bar.max, bar.cur = 0, 0

        local function Travel() return math.max(1, bar:GetHeight() - 2 - thumb:GetHeight()) end
        local function PlaceThumb()
            local f = bar.max > 0 and bar.cur / bar.max or 0
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", bar, "TOP", 0, -1 - f * Travel())
        end
        local function CursorY()
            local _, y = GetCursorPosition()
            return y / bar:GetEffectiveScale()
        end
        -- position from the cursor; grab = cursor distance from the thumb top
        local function MoveTo(y, grab)
            local offset = (bar:GetTop() - 1) - y - grab
            local v = math.floor(math.max(0, math.min(1, offset / Travel())) * bar.max + 0.5)
            if v ~= bar.cur then
                bar.cur = v
                PlaceThumb()
                onScroll(v)
            end
        end
        local function StartDrag(grab)
            thumb:SetScript("OnUpdate", function()
                if not IsMouseButtonDown("LeftButton") then
                    thumb:SetScript("OnUpdate", nil)
                    return
                end
                MoveTo(CursorY(), grab)
            end)
        end
        thumb:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            StartDrag(thumb:GetTop() - CursorY())
        end)
        thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)
        -- click on the track: the thumb jumps there (centered) and can be dragged
        bar:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            local grab = thumb:GetHeight() / 2
            MoveTo(CursorY(), grab)
            StartDrag(grab)
        end)
        bar:SetScript("OnSizeChanged", PlaceThumb)

        function bar:SetRange(max, frac)
            self.max = math.max(0, math.floor((max or 0) + 0.5))
            thumb:SetHeight(math.max(16, (self:GetHeight() - 2) * math.min(1, frac or 1)))
            if self.cur > self.max then self.cur = self.max end
            PlaceThumb()
            self:SetShown(self.max > 0)
        end
        function bar:SetPos(v)
            self.cur = math.max(0, math.min(self.max, math.floor((v or 0) + 0.5)))
            PlaceThumb()
        end
        return bar
    end

    ---------------------------------------------------------------------------
    -- Dropdown: label above, button below; the list scrolls when long.
    -- options = { { value, label, font, texture }, ... } or a function that
    -- returns it. With font, the option is drawn in that font; with texture,
    -- a sample of it is shown behind the option.
    ---------------------------------------------------------------------------
    local MAX_ITEMS = 14

    function UI.CloseMenu()
        if lib.openMenu then
            lib.openMenu:Hide()
            lib.openMenu = nil
        end
    end

    local function ApplyFont(fs, font)
        if font then
            if not fs:SetFont(font, 12, "") then fs:SetFontObject(T.labelFont) end
        else
            fs:SetFontObject(T.labelFont)
        end
    end

    local function ApplyTexture(frame, tex)
        if not frame.preview then
            if not tex then return end
            frame.preview = frame:CreateTexture(nil, "BORDER")
            frame.preview:SetPoint("TOPLEFT", 1, -1)
            frame.preview:SetPoint("BOTTOMRIGHT", -1, 1)
            frame.preview:SetVertexColor(A[1] * 0.6, A[2] * 0.6, A[3] * 0.6, 1)
        end
        if tex then frame.preview:SetTexture(tex) end
        frame.preview:SetShown(tex ~= nil)
    end

    function UI.Dropdown(parent, label, options, get, set, opts)
        opts = opts or {}
        opts.label = label
        local yOff = label and -14 or 0
        local r = Row(parent, (label and 14 or 0) + 20, opts)
        if label then
            r.label = UI.Text(r, label)
            r.label:SetPoint("TOPLEFT")
        end
        local b = UI.Button(r, "", 150, 20)
        b:SetPoint("TOPLEFT", 0, yOff)
        b:SetPoint("TOPRIGHT", 0, yOff)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -16, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        -- the arrow: a thick chevron in the brand color
        b.arrow = CreateFrame("Frame", nil, b)
        b.arrow:SetSize(8, 5)
        b.arrow:SetPoint("RIGHT", -6, 0)
        for i, x in ipairs({ 0, 8 }) do
            local line = b.arrow:CreateLine(nil, "OVERLAY")
            line:SetThickness(2)
            line:SetColorTexture(A[1], A[2], A[3], 1)
            line:SetStartPoint("TOPLEFT", b.arrow, x, 0)
            line:SetEndPoint("BOTTOMLEFT", b.arrow, 4, 0)
            b.arrow[i] = line
        end
        r.button = b

        local function Opts() return type(options) == "function" and options() or options end

        r.Refresh = function()
            local cur = get()
            for _, o in ipairs(Opts()) do
                if o[1] == cur then
                    ApplyFont(b.text, o[3])
                    ApplyTexture(b, o[4])
                    b.text:SetText(o[2])
                    return
                end
            end
            ApplyFont(b.text, nil)
            ApplyTexture(b, nil)
            b.text:SetText(cur ~= nil and tostring(cur):match("([^\\]+)$") or "")
        end

        b:SetScript("OnClick", function()
            if lib.openMenu then
                local owner = lib.openMenu.owner
                UI.CloseMenu()
                if owner == b then return end
            end
            local list = Opts()
            local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            UI.Backdrop(menu, { 0.06, 0.06, 0.08, 1 }, { A[1], A[2], A[3], 1 })
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetClampedToScreen(true)
            menu.owner = b
            local shown = math.min(#list, MAX_ITEMS)
            menu:SetSize(math.max(b:GetWidth(), 150), shown * 18 + 4)
            menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
            menu:EnableMouse(true)
            local offset, maxOffset = 0, math.max(0, #list - MAX_ITEMS)
            local items, bar = {}, nil
            local function Fill()
                for i = 1, shown do
                    local o = list[i + offset]
                    local it = items[i]
                    it.value = o and o[1]
                    ApplyFont(it.t, o and o[3])
                    ApplyTexture(it, o and o[4])
                    it.t:SetText(o and o[2] or "")
                    it.sel:SetShown(o ~= nil and o[1] == get())
                end
            end
            local function ScrollTo(v)
                offset = math.max(0, math.min(maxOffset, math.floor(v + 0.5)))
                Fill()
                if bar then bar:SetPos(offset) end
            end
            local itemW = menu:GetWidth() - 4 - (maxOffset > 0 and 12 or 0)
            for i = 1, shown do
                local it = CreateFrame("Button", nil, menu)
                it:SetSize(itemW, 18)
                it:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
                local hl = it:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.1)
                it.sel = it:CreateTexture(nil, "ARTWORK")
                it.sel:SetAllPoints()
                it.sel:SetColorTexture(A[1], A[2], A[3], 0.2)
                it.t = UI.Text(it, "")
                it.t:SetPoint("LEFT", 4, 0)
                it.t:SetPoint("RIGHT", -4, 0)
                it.t:SetWordWrap(false)
                it:SetScript("OnClick", function(self)
                    set(self.value)
                    r.Refresh()
                    UI.CloseMenu()
                    Changed()
                end)
                items[i] = it
            end
            if maxOffset > 0 then
                bar = UI.ScrollBar(menu, ScrollTo)
                bar:SetPoint("TOPRIGHT", -3, -3)
                bar:SetPoint("BOTTOMRIGHT", -3, 3)
                bar:SetRange(maxOffset, shown / #list)
                menu:EnableMouseWheel(true)
                menu:SetScript("OnMouseWheel", function(_, d) ScrollTo(offset - d) end)
                local cur = get()
                for k, o in ipairs(list) do
                    if o[1] == cur then ScrollTo(k - math.ceil(shown / 2)) break end
                end
            end
            Fill()
            lib.openMenu = menu
        end)
        r:SetScript("OnHide", function()
            if lib.openMenu and lib.openMenu.owner == b then UI.CloseMenu() end
        end)
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Color swatch: color box on the left, label on the right.
    -- getColor() returns a { r, g, b, a } table that the picker edits.
    -- opts.alpha: the picker also edits the opacity
    ---------------------------------------------------------------------------
    local function OpenColorPicker(c, hasAlpha, onChange)
        local prev = { r = c.r, g = c.g, b = c.b, a = c.a }
        local function Apply()
            c.r, c.g, c.b = ColorPickerFrame:GetColorRGB()
            if hasAlpha then
                c.a = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha())
                    or (OpacitySliderFrame and 1 - OpacitySliderFrame:GetValue()) or 1
            end
            onChange()
        end
        local function Cancel()
            c.r, c.g, c.b, c.a = prev.r, prev.g, prev.b, prev.a
            onChange()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b, opacity = c.a or 1, hasOpacity = hasAlpha,
                swatchFunc = Apply, opacityFunc = Apply, cancelFunc = Cancel,
            })
        else
            ColorPickerFrame.func = Apply
            ColorPickerFrame.opacityFunc = Apply
            ColorPickerFrame.cancelFunc = Cancel
            ColorPickerFrame.hasOpacity = hasAlpha
            ColorPickerFrame.opacity = 1 - (c.a or 1)
            ColorPickerFrame:SetColorRGB(c.r, c.g, c.b)
            ColorPickerFrame:Hide()
            ColorPickerFrame:Show()
        end
    end

    function UI.Swatch(parent, label, getColor, onChange, opts)
        opts = opts or {}
        opts.label = label
        local r = Row(parent, T.rowHeight, opts)
        local s = CreateFrame("Button", nil, r, "BackdropTemplate")
        s:SetSize(28, 14)
        s:SetPoint("LEFT")
        s.borderColor = { 0.6, 0.6, 0.6, 1 }
        UI.Backdrop(s, { 1, 1, 1, 1 }, s.borderColor)
        r.label = UI.Text(r, label)
        r.label:SetPoint("LEFT", s, "RIGHT", 6, 0)
        s:SetScript("OnEnter", function(self) Hover(self, true) end)
        s:SetScript("OnLeave", function(self) Hover(self, false) end)
        r.Refresh = function()
            local c = getColor()
            s:SetBackdropColor(c.r, c.g, c.b, 1)
        end
        s:SetScript("OnClick", function()
            OpenColorPicker(getColor(), opts.alpha, function()
                r.Refresh()
                if onChange then onChange() end
            end)
        end)
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Text input
    ---------------------------------------------------------------------------
    -- Plain one-line edit box with the theme look. Tab moves to the next
    -- visible input of the instance, Shift+Tab to the previous one.
    function UI.EditBox(parent, w, h)
        local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        e:SetSize(w or 120, h or 20)
        e.borderColor = T.border
        UI.Backdrop(e, T.fieldDark)
        e:SetFontObject(ChatFontNormal)
        e:SetTextInsets(5, 5, 0, 0)
        e:SetAutoFocus(false)
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:HookScript("OnEditFocusGained", function(self) Hover(self, true) end)
        e:HookScript("OnEditFocusLost", function(self) Hover(self, false) end)
        e:SetScript("OnTabPressed", function(self)
            local list = UI.inputs
            local dir = IsShiftKeyDown() and -1 or 1
            local at
            for i, other in ipairs(list) do if other == self then at = i break end end
            if not at then return end
            for k = 1, #list do
                local other = list[((at - 1 + k * dir) % #list) + 1]
                if other:IsVisible() then
                    other:SetFocus()
                    return
                end
            end
        end)
        table.insert(UI.inputs, e)
        return e
    end

    -- Labelled input: the value is saved on Enter (or when focus leaves, if
    -- opts.saveOnBlur)
    function UI.Input(parent, label, get, set, opts)
        opts = opts or {}
        opts.label = label
        local top = label and -14 or 0
        local r = Row(parent, (label and 14 or 0) + 20, opts)
        if label then
            r.label = UI.Text(r, label)
            r.label:SetPoint("TOPLEFT")
        end
        local e = UI.EditBox(r, 150)
        e:SetPoint("TOPLEFT", 0, top)
        e:SetPoint("TOPRIGHT", 0, top)
        local function Save()
            set(e:GetText())
            Changed()
        end
        e:SetScript("OnEnterPressed", function(self)
            Save()
            self:ClearFocus()
        end)
        e:HookScript("OnEditFocusLost", function(self)
            if opts.saveOnBlur then Save() else self:SetText(get() or "") end
        end)
        r.Refresh = function() if not e:HasFocus() then e:SetText(get() or "") end end
        r.edit = e
        return Register(r)
    end

    -- Search box: grey hint while empty, a clear button, and onChange(text)
    -- called on every keystroke
    function UI.SearchBox(parent, hint, onChange, opts)
        local r = Row(parent, 20, opts)
        local e = UI.EditBox(r, 150)
        e:SetAllPoints()
        e:SetTextInsets(5, 20, 0, 0)
        local placeholder = UI.Text(e, hint or UI.strings.search, T.labelFont, T.muted)
        placeholder:SetPoint("LEFT", 6, 0)
        local clear = UI.Button(e, "x", 16, 16, function()
            e:SetText("")
            e:ClearFocus()
        end)
        clear:SetPoint("RIGHT", -2, 0)
        clear:Hide()
        e:SetScript("OnTextChanged", function(self)
            local text = self:GetText()
            placeholder:SetShown(text == "")
            clear:SetShown(text ~= "")
            if onChange then onChange(text) end
        end)
        e:SetScript("OnEnterPressed", e.ClearFocus)
        r.edit = e
        return r
    end

    -- Multi-line text box with its own scroll (code, long text).
    -- height = visible height; the edit box is row.edit
    function UI.CodeBox(parent, height, opts)
        local r = Row(parent, height, opts)
        local box = CreateFrame("Frame", nil, r, "BackdropTemplate")
        box:SetAllPoints()
        box.borderColor = T.border
        UI.Backdrop(box, T.fieldDark)
        local sf = CreateFrame("ScrollFrame", nil, box)
        sf:SetPoint("TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", -14, 6)
        local e = CreateFrame("EditBox", nil, sf)
        e:SetMultiLine(true)
        e:SetAutoFocus(false)
        e:SetFontObject(ChatFontNormal)
        e:SetWidth(200)
        sf:SetScrollChild(e)
        local bar = UI.ScrollBar(box, function(v) sf:SetVerticalScroll(v) end)
        bar:SetPoint("TOPRIGHT", -3, -3)
        bar:SetPoint("BOTTOMRIGHT", -3, 3)
        local function Update()
            local max = math.max(0, e:GetHeight() - sf:GetHeight())
            bar:SetRange(max, sf:GetHeight() / math.max(1, e:GetHeight()))
            bar:SetPos(sf:GetVerticalScroll())
        end
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, e:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - d * 30)))
            Update()
        end)
        e:SetScript("OnCursorChanged", function(_, _, y, _, lineHeight)
            local top, view = sf:GetVerticalScroll(), sf:GetHeight()
            y = -y
            if y < top then sf:SetVerticalScroll(y)
            elseif y + lineHeight > top + view then sf:SetVerticalScroll(y + lineHeight - view) end
            Update()
        end)
        e:SetScript("OnTextChanged", Update)
        e:SetScript("OnEscapePressed", e.ClearFocus)
        e:HookScript("OnEditFocusGained", function() Hover(box, true) end)
        e:HookScript("OnEditFocusLost", function() Hover(box, false) end)
        box:EnableMouse(true)
        box:SetScript("OnMouseDown", function() e:SetFocus() end)
        r.OnWidth = function(w) e:SetWidth(w - 20) end
        r.edit = e
        return r
    end

    ---------------------------------------------------------------------------
    -- Help text: grey, wraps to the row width. row:SetText(text) changes it.
    ---------------------------------------------------------------------------
    function UI.Note(parent, text, opts)
        local r = Row(parent, 14, opts)
        r.text = UI.Text(r, text, T.labelFont, T.muted)
        r.text:SetPoint("TOPLEFT")
        r.text:SetWordWrap(true)
        r.OnWidth = function(w)
            r.text:SetWidth(w)
            r:SetHeight(math.max(12, r.text:GetStringHeight() + 2))
        end
        r.SetText = function(_, t)
            r.text:SetText(t)
            r.OnWidth(r:GetWidth())
        end
        return r
    end

    ---------------------------------------------------------------------------
    -- Selectable list
    --   opts.items()              -> the list to show
    --   opts.label(item, index)   -> text of a row
    --   opts.selected()           -> index of the selected row (or nil)
    --   opts.onSelect(index)
    --   opts.decorate(row, item, index)  optional extra pieces per row
    --   opts.onReorder(from, to)  optional: rows can be dragged to reorder
    --   opts.rowHeight            default 20
    ---------------------------------------------------------------------------
    function UI.List(parent, opts)
        local h = opts.rowHeight or 20
        local r = Row(parent, 10, opts)
        local rows = {}
        local dragFrom
        local marker = r:CreateTexture(nil, "OVERLAY")
        marker:SetHeight(2)
        marker:SetColorTexture(A[1], A[2], A[3], 1)
        marker:Hide()

        local function IndexAtCursor()
            local _, cy = GetCursorPosition()
            cy = cy / r:GetEffectiveScale()
            local top = r:GetTop()
            if not top then return 1 end
            local n = #opts.items()
            return math.max(1, math.min(n, math.floor((top - cy) / (h + 2)) + 1))
        end

        r.Refresh = function()
            local list = opts.items()
            local sel = opts.selected and opts.selected()
            for i, item in ipairs(list) do
                local row = rows[i]
                if not row then
                    row = CreateFrame("Button", nil, r)
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                    local hl = row:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(1, 1, 1, 0.07)
                    row.bar = row:CreateTexture(nil, "ARTWORK")
                    row.bar:SetPoint("TOPLEFT")
                    row.bar:SetPoint("BOTTOMLEFT")
                    row.bar:SetWidth(2)
                    row.bar:SetColorTexture(A[1], A[2], A[3], 1)
                    row.text = UI.Text(row, "")
                    row.text:SetPoint("LEFT", 8, 0)
                    row.text:SetPoint("RIGHT", -6, 0)
                    row.text:SetWordWrap(false)
                    if opts.onReorder then
                        row:RegisterForDrag("LeftButton")
                        row:SetScript("OnDragStart", function(self)
                            dragFrom = self.index
                            r:SetScript("OnUpdate", function()
                                local to = IndexAtCursor()
                                marker:ClearAllPoints()
                                marker:SetPoint("TOPLEFT", 0, -(to - 1) * (h + 2) + 1)
                                marker:SetPoint("TOPRIGHT", 0, -(to - 1) * (h + 2) + 1)
                                marker:Show()
                            end)
                        end)
                        row:SetScript("OnDragStop", function()
                            r:SetScript("OnUpdate", nil)
                            marker:Hide()
                            local to = IndexAtCursor()
                            if dragFrom and to ~= dragFrom then opts.onReorder(dragFrom, to) end
                            dragFrom = nil
                            Changed()
                        end)
                    end
                    rows[i] = row
                end
                row.index = i
                row:SetScript("OnClick", function(self)
                    if opts.onSelect then opts.onSelect(self.index) end
                    Changed()
                end)
                local on = sel == i
                row.bg:SetColorTexture(A[1], A[2], A[3], on and 0.22 or 0)
                row.bar:SetShown(on)
                row.text:SetText(opts.label(item, i))
                row.text:SetTextColor(unpack(on and T.text or T.muted))
                if opts.decorate then opts.decorate(row, item, i) end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(i - 1) * (h + 2))
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * (h + 2))
                row:SetHeight(h)
                row:Show()
            end
            for i = #list + 1, #rows do rows[i]:Hide() end
            r:SetHeight(math.max(1, #list * (h + 2) - 2))
        end
        return Register(r)
    end

    ---------------------------------------------------------------------------
    -- Card: box with a brand-color title and a line under it; its rows are
    -- stacked top to bottom. card:Add(row), card:Layout(width)
    ---------------------------------------------------------------------------
    function UI.Card(parent, title, subtitle)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        UI.Backdrop(card, T.card, T.cardBorder)
        card.rows = {}
        local P = T.pad
        card.title = UI.Text(card, title, T.titleFont, A)
        card.title:SetPoint("TOPLEFT", P, -P)
        card.line = card:CreateTexture(nil, "ARTWORK")
        card.line:SetHeight(1)
        card.line:SetColorTexture(A[1], A[2], A[3], 0.3)
        if subtitle then
            card.subtitle = UI.Text(card, subtitle, T.labelFont, T.muted)
            card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
            card.subtitle:SetWordWrap(true)
        end

        function card:Add(w)
            w:SetParent(self)
            table.insert(self.rows, w)
            return w
        end

        function card:Layout(width)
            self:SetWidth(width)
            local inner = width - 2 * P
            local top = P + 16
            if self.subtitle then
                self.subtitle:SetWidth(inner)
                top = top + self.subtitle:GetStringHeight() + 4
            end
            self.line:ClearAllPoints()
            self.line:SetPoint("TOPLEFT", P, -(top + 2))
            self.line:SetPoint("TOPRIGHT", -P, -(top + 2))
            local y = -(top + 10)
            for _, w in ipairs(self.rows) do
                local visible = not w.showIf or w.showIf()
                w:SetShown(visible)
                if visible then
                    if w.enableIf then UI.SetEnabled(w, w.enableIf() and true or false) end
                    w:SetWidth(inner)
                    if w.OnWidth then w.OnWidth(inner) end
                    w:ClearAllPoints()
                    w:SetPoint("TOPLEFT", P, y)
                    y = y - w:GetHeight() - T.gap
                end
            end
            self:SetHeight(-y - T.gap + P)
        end
        return card
    end

    ---------------------------------------------------------------------------
    -- Page: vertical scroll area with columns of cards.
    -- page:Add(column, card), page:Layout(). A card with card.showIf hides.
    ---------------------------------------------------------------------------
    function UI.Page(parent, columns)
        local page = CreateFrame("Frame", nil, parent)
        page:SetAllPoints()
        local sf = CreateFrame("ScrollFrame", nil, page)
        sf:SetPoint("TOPLEFT")
        sf:SetPoint("BOTTOMRIGHT", -12, 0)
        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(10, 10)
        sf:SetScrollChild(content)
        page.content = content
        page.cols = {}
        for i = 1, columns or 2 do page.cols[i] = {} end

        local bar = UI.ScrollBar(page, function(v) sf:SetVerticalScroll(v) end)
        bar:SetPoint("TOPRIGHT", -1, 0)
        bar:SetPoint("BOTTOMRIGHT", -1, 0)
        local function UpdateBar()
            local h, view = content:GetHeight(), sf:GetHeight()
            local max = math.max(0, h - view)
            if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
            bar:SetRange(max, h > 0 and view / h or 1)
            bar:SetPos(sf:GetVerticalScroll())
        end
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, content:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - d * 40)))
            bar:SetPos(self:GetVerticalScroll())
        end)

        function page:Add(col, card)
            card:SetParent(self.content)
            table.insert(self.cols[col], card)
            return card
        end

        function page:Layout()
            local w = sf:GetWidth()
            if w <= 0 then return end
            content:SetWidth(w)
            local gap = T.gap
            local n = #self.cols
            local cw = math.floor((w - (n - 1) * gap) / n)
            local low = 0
            for i, col in ipairs(self.cols) do
                local y = 0
                for _, card in ipairs(col) do
                    local visible = not card.showIf or card.showIf()
                    card:SetShown(visible)
                    if visible then
                        card:Layout(cw)
                        card:ClearAllPoints()
                        card:SetPoint("TOPLEFT", (i - 1) * (cw + gap), y)
                        y = y - card:GetHeight() - gap
                    end
                end
                low = math.min(low, y)
            end
            content:SetHeight(-low + 4)
            UpdateBar()
        end
        sf:SetScript("OnSizeChanged", function() page:Layout() end)
        table.insert(UI.pages, page)
        return page
    end

    ---------------------------------------------------------------------------
    -- Tabs: a row of text tabs with a brand-color underline.
    -- list = { { key, label }, ... }; onSelect(key). tabs:Select(key)
    ---------------------------------------------------------------------------
    function UI.Tabs(parent, list, onSelect)
        local bar = CreateFrame("Frame", nil, parent)
        bar:SetHeight(26)
        bar.buttons = {}
        local x = 0
        for _, t in ipairs(list) do
            local key = t[1]
            local b = CreateFrame("Button", nil, bar)
            b.text = UI.Text(b, t[2], T.titleFont, T.muted)
            b.text:SetPoint("CENTER")
            local w = b.text:GetStringWidth() + 22
            b:SetSize(w, 26)
            b:SetPoint("TOPLEFT", x, 0)
            x = x + w
            b.line = b:CreateTexture(nil, "OVERLAY")
            b.line:SetPoint("BOTTOMLEFT", 5, 0)
            b.line:SetPoint("BOTTOMRIGHT", -5, 0)
            b.line:SetHeight(2)
            b.line:SetColorTexture(A[1], A[2], A[3], 1)
            b:SetScript("OnEnter", function(self) if bar.current ~= key then self.text:SetTextColor(unpack(T.text)) end end)
            b:SetScript("OnLeave", function(self) if bar.current ~= key then self.text:SetTextColor(unpack(T.muted)) end end)
            b:SetScript("OnClick", function() bar:Select(key) end)
            bar.buttons[key] = b
        end
        local sep = bar:CreateTexture(nil, "ARTWORK")
        sep:SetPoint("BOTTOMLEFT")
        sep:SetPoint("BOTTOMRIGHT")
        sep:SetHeight(1)
        sep:SetColorTexture(1, 1, 1, 0.07)
        function bar:Select(key)
            self.current = key
            for k, b in pairs(self.buttons) do
                b.line:SetShown(k == key)
                b.text:SetTextColor(unpack(k == key and T.text or T.muted))
            end
            if onSelect then onSelect(key) end
        end
        return bar
    end

    ---------------------------------------------------------------------------
    -- Confirmation dialog over the screen (darkens what is behind)
    ---------------------------------------------------------------------------
    function UI.Dialog(text, acceptText, onAccept, cancelText)
        local d = UI.dialog
        if not d then
            d = CreateFrame("Frame", nil, UIParent)
            d:SetAllPoints()
            d:SetFrameStrata("FULLSCREEN_DIALOG")
            d:EnableMouse(true)
            local dim = d:CreateTexture(nil, "BACKGROUND")
            dim:SetAllPoints()
            dim:SetColorTexture(0, 0, 0, 0.55)
            d.box = CreateFrame("Frame", nil, d, "BackdropTemplate")
            d.box:SetSize(340, 120)
            d.box:SetPoint("CENTER")
            UI.Backdrop(d.box, T.window, { A[1], A[2], A[3], 1 })
            d.text = UI.Text(d.box, "", T.labelFont)
            d.text:SetPoint("TOPLEFT", 16, -16)
            d.text:SetPoint("TOPRIGHT", -16, -16)
            d.text:SetJustifyH("CENTER")
            d.text:SetWordWrap(true)
            d.accept = UI.Button(d.box, "", 120, 22, nil, "accent")
            d.accept:SetPoint("BOTTOMRIGHT", d.box, "BOTTOM", -4, 14)
            d.cancel = UI.Button(d.box, "", 120, 22, function() d:Hide() end)
            d.cancel:SetPoint("BOTTOMLEFT", d.box, "BOTTOM", 4, 14)
            d:EnableKeyboard(true)
            d:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then
                    self:SetPropagateKeyboardInput(false)
                    self:Hide()
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end)
            UI.dialog = d
        end
        d.text:SetText(text)
        d.box:SetHeight(math.max(110, d.text:GetStringHeight() + 70))
        d.accept.text:SetText(acceptText or UI.strings.accept)
        d.cancel.text:SetText(cancelText or UI.strings.cancel)
        d.accept:SetScript("OnClick", function()
            d:Hide()
            if onAccept then onAccept() end
        end)
        d:Show()
        return d
    end

    ---------------------------------------------------------------------------
    -- Window: header (logo, title, version, subtitle, buttons on the right),
    -- navigation buttons on the left, page area and an optional status line.
    --   opts = { name, title, version, width, height, logo (texture path) }
    --   win:AddNav(key, label, build, dot)  build(container) runs on first open;
    --                                       dot() -> true/false shows a dot
    --   win:AddSection(label)               small caption in the navigation
    --   win:AddHeaderButton(label, onClick, isOn, tip)  isOn() lights it up
    --   win:Select(key), win:SetSubtitle(text), win:SetStatus(text)
    ---------------------------------------------------------------------------
    function UI.Window(opts)
        local W, H = opts.width or 760, opts.height or 606
        local NAV_W = opts.navWidth or 130
        local win = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
        win:SetSize(W, H)
        win:SetPoint("CENTER")
        win:SetFrameStrata("DIALOG")
        win:SetToplevel(true)
        UI.Backdrop(win, T.window, T.windowBorder)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:SetClampedToScreen(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        if opts.name then table.insert(UISpecialFrames, opts.name) end
        win:SetScript("OnHide", function() UI.CloseMenu() end)

        -- header: band with a soft brand-color glow from the left
        local header = CreateFrame("Frame", nil, win)
        header:SetPoint("TOPLEFT", 1, -1)
        header:SetPoint("TOPRIGHT", -1, -1)
        header:SetHeight(40)
        local hbg = header:CreateTexture(nil, "BACKGROUND")
        hbg:SetAllPoints()
        hbg:SetColorTexture(unpack(T.header))
        local glow = header:CreateTexture(nil, "BORDER")
        glow:SetAllPoints()
        glow:SetColorTexture(1, 1, 1, 1)
        if not (CreateColor and pcall(glow.SetGradient, glow, "HORIZONTAL",
            CreateColor(A[1], A[2], A[3], 0.08), CreateColor(A[1], A[2], A[3], 0))) then
            glow:SetColorTexture(A[1], A[2], A[3], 0.03)
        end
        local hline = header:CreateTexture(nil, "ARTWORK")
        hline:SetPoint("BOTTOMLEFT")
        hline:SetPoint("BOTTOMRIGHT")
        hline:SetHeight(1)
        hline:SetColorTexture(A[1], A[2], A[3], 0.35)

        -- logo: the given texture, or a brand-color diamond
        local logo = header:CreateTexture(nil, "ARTWORK")
        if opts.logo then
            logo:SetSize(24, 24)
            logo:SetTexture(opts.logo)
        else
            logo:SetSize(12, 12)
            logo:SetColorTexture(A[1], A[2], A[3], 1)
            logo:SetRotation(math.rad(45))
        end
        logo:SetPoint("CENTER", header, "LEFT", 22, 0)
        local title = header:CreateFontString(nil, "OVERLAY")
        title:SetFont(STANDARD_TEXT_FONT, 14, "")
        title:SetTextColor(1, 1, 1)
        title:SetText(opts.title or "")
        title:SetPoint("TOPLEFT", header, "TOPLEFT", 42, -6)
        local version = UI.Text(header, opts.version and ("v" .. opts.version) or "", "GameFontDisableSmall")
        version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
        local subtitle = UI.Text(header, "", T.labelFont, { 0.6, 0.64, 0.71 })
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        function win:SetSubtitle(text) subtitle:SetText(text or "") end

        local close = UI.Button(header, "X", 22, 20, function() win:Hide() end)
        close:SetPoint("RIGHT", -10, 0)
        local lastButton = close
        function win:AddHeaderButton(label, onClick, isOn, tip)
            local b = UI.Button(header, label, 110, 20, onClick)
            b:SetPoint("RIGHT", lastButton, "LEFT", -6, 0)
            lastButton = b
            if tip then UI.Tip(b, label, tip) end
            if isOn then
                b.Refresh = function()
                    if isOn() then
                        b.borderColor = { A[1], A[2], A[3], 1 }
                        b:SetBackdropColor(A[1] * 0.3, A[2] * 0.3, A[3] * 0.3, 1)
                    else
                        b.borderColor = T.border
                        b:SetBackdropColor(unpack(T.button))
                    end
                    b:SetBackdropBorderColor(unpack(b.borderColor))
                end
                Register(b)
            end
            return b
        end

        -- navigation and pages
        local navY = -50
        local navs, pages, builders, order = {}, {}, {}, {}
        local area = CreateFrame("Frame", nil, win)
        area:SetPoint("TOPLEFT", NAV_W + 18, -50)
        area:SetPoint("BOTTOMRIGHT", -8, opts.status ~= false and 26 or 8)

        function win:AddSection(label)
            local t = UI.Text(win, label, "GameFontDisableSmall")
            t:SetPoint("TOPLEFT", 14, navY - 6)
            navY = navY - 22
        end

        local function PaintNav()
            for key, nb in pairs(navs) do
                local on = key == win.current
                nb:SetBackdropColor(unpack(on and T.navSelected or T.nav))
                nb.text:SetTextColor(unpack(on and T.text or { 0.85, 0.85, 0.88 }))
                if nb.dot then
                    local lit = nb.dotFn()
                    nb.dot:SetColorTexture(lit and A[1] or 0.3, lit and A[2] or 0.3, lit and A[3] or 0.35, 1)
                end
            end
        end

        function win:AddNav(key, label, build, dot)
            local nb = UI.Button(win, label, NAV_W, 26, function() win:Select(key) end)
            nb:SetPoint("TOPLEFT", 10, navY)
            nb.text:ClearAllPoints()
            nb.text:SetPoint("LEFT", 10, 0)
            if dot then
                nb.dot = nb:CreateTexture(nil, "OVERLAY")
                nb.dot:SetSize(6, 6)
                nb.dot:SetPoint("RIGHT", -9, 0)
                nb.dotFn = dot
            end
            navY = navY - 30
            navs[key] = nb
            builders[key] = build
            table.insert(order, key)
            return nb
        end

        function win:Select(key)
            UI.CloseMenu()
            self.current = key
            for k, p in pairs(pages) do p:SetShown(k == key) end
            if not pages[key] and builders[key] then
                local container = CreateFrame("Frame", nil, area)
                container:SetAllPoints()
                pages[key] = container
                builders[key](container)
            end
            if pages[key] then pages[key]:Show() end
            PaintNav()
            UI.RefreshAll()
        end

        -- status line at the bottom
        if opts.status ~= false then
            local status = UI.Text(win, "", T.labelFont, T.muted)
            status:SetPoint("BOTTOMLEFT", NAV_W + 18, 9)
            function win:SetStatus(text) status:SetText(text or "") end
        else
            function win:SetStatus() end
        end

        function win:Toggle()
            self:SetShown(not self:IsShown())
            if self:IsShown() then UI.RefreshAll() end
        end

        win.header = header
        win.area = area
        win.PaintNav = PaintNav
        UI.window = win
        return win
    end

    ---------------------------------------------------------------------------
    -- Refresh every control (values, enabled state) and the visible pages
    ---------------------------------------------------------------------------
    function UI.RefreshAll()
        for _, w in ipairs(UI.widgets) do
            if w.Refresh then w.Refresh(w) end
        end
        for _, p in ipairs(UI.pages) do
            if p:IsVisible() then p:Layout() end
        end
        if UI.window and UI.window.PaintNav then UI.window.PaintNav() end
        if UI.OnRefresh then UI.OnRefresh() end
    end

    -- Value formatters
    UI.pct = function(v) return ("%d%%"):format(v * 100 + 0.5) end
    UI.px = function(v) return ("%d px"):format(v) end

    -- Texts the library shows on its own; replace them to translate
    UI.strings = {
        confirm = "Click again to confirm",
        search = "Search...",
        accept = "Accept",
        cancel = "Cancel",
    }

    return UI
end
