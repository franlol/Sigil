-------------------------------------------------------------------------------
-- Sigil - Cast bar
--
-- The bar is filled in the best way the game allows for that unit:
--   1. Plain times (usually your own casts): Sigil moves the bar and shows
--      the remaining time.
--   2. Secret times: the game moves the bar with its duration object
--      (StatusBar:SetTimerDuration), if it lets addons do it.
--   3. If neither works: the bar is shown full with the spell name and icon.
-- The name and icon are shown even when they are secret.
--
-- Colors (Colors page): cast, channel, cannot be interrupted, interrupted,
-- completed. When a cast ends the bar stays `fadeTime` seconds and fades.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

local FLAT = "Interface\\Buttons\\WHITE8X8"

local function CastRGB(key)
    local c = ns.Color("cast", key)
    return c.r, c.g, c.b
end

-- Fading after the cast ends
local function FadeOut(cb, duration)
    cb.fadeLeft, cb.fadeTotal = duration, duration
    cb.mode = "fade"
end

local function OnUpdate(self, elapsed)
    if self.mode == "fade" then
        self.fadeLeft = self.fadeLeft - elapsed
        if self.fadeLeft <= 0 then
            self.mode = nil
            self:Hide()
            self:SetAlpha(1)
        else
            self:SetAlpha(math.min(1, self.fadeLeft / self.fadeTotal * 1.5))
        end
        return
    end
    if self.mode ~= "manual" then return end
    local now = GetTime()
    if now >= self.finish then
        self.bar:SetValue(self.channel and 0 or self.finish - self.start)
        return
    end
    local v = self.channel and (self.finish - now) or (now - self.start)
    self.bar:SetValue(v)
    if self.timeFormat == "both" then
        self.time:SetFormattedText("%.1f / %.1f", self.finish - now, self.finish - self.start)
    else
        self.time:SetFormattedText("%.1f", self.finish - now)
    end
end

local function Build(f)
    local cb = CreateFrame("Frame", nil, f, "BackdropTemplate")

    cb.icon = cb:CreateTexture(nil, "ARTWORK")
    cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cb.bar = CreateFrame("StatusBar", nil, cb)
    cb.bar:SetMinMaxValues(0, 1)
    cb.bar.bg = cb.bar:CreateTexture(nil, "BACKGROUND")
    cb.bar.bg:SetAllPoints()
    -- your latency: the end of the bar the server takes to answer
    cb.lag = cb.bar:CreateTexture(nil, "OVERLAY")
    cb.lag:SetTexture(FLAT)
    cb.lag:Hide()

    cb.text = cb.bar:CreateFontString(nil, "OVERLAY")
    cb.text:SetWordWrap(false)
    cb.text:SetJustifyH("LEFT")
    cb.time = cb.bar:CreateFontString(nil, "OVERLAY")
    cb.time:SetJustifyH("RIGHT")

    cb:Hide()
    cb:SetScript("OnUpdate", OnUpdate)
    return cb
end

function ns.LayoutCastbar(f)
    local c = f.cfg.castbar
    if not c or not c.enabled then
        if f.castbar then f.castbar:Hide() end
        return
    end
    local cb = f.castbar or Build(f)
    f.castbar = cb
    local h = c.height
    ns.PlacePiece(f, "castbar", L["Cast bar"], cb, c)
    cb:SetSize(c.width and c.width > 0 and c.width or f.cfg.width, h)

    local e = ns.StyleBox(cb, c.style)
    local inner = h - 2 * e
    cb.icon:ClearAllPoints()
    cb.bar:ClearAllPoints()
    if c.icon then
        cb.icon:SetSize(inner, inner)
        cb.icon:SetPoint("TOPLEFT", e, -e)
        cb.icon:Show()
        cb.bar:SetPoint("TOPLEFT", inner + e + 1, -e)
    else
        cb.icon:Hide()
        cb.bar:SetPoint("TOPLEFT", e, -e)
    end
    cb.bar:SetPoint("BOTTOMRIGHT", -e, e)
    ns.StyleBar(cb.bar, c.style)

    local auto = math.max(8, math.floor(h * 0.6))
    ns.StyleText(cb.text, c.nameText, auto)
    ns.StyleText(cb.time, c.timeText, auto)
    cb.time:ClearAllPoints()
    cb.time:SetPoint("RIGHT", -4, 0)
    cb.text:ClearAllPoints()
    cb.text:SetPoint("LEFT", 4, 0)
    cb.text:SetPoint("RIGHT", cb.time, "LEFT", -4, 0)
    cb.timeFormat = c.timeFormat
end

local function Paint(f, key)
    local cb = f.castbar
    ns.PaintBar(cb.bar, f.cfg.castbar.style, CastRGB(key))
end

local function StateKey(cb, notInterruptible)
    if R(notInterruptible) then return "locked" end
    return cb.channel and "channel" or "cast"
end

-- reason: "done" (completed) or "interrupted"; nil hides at once
local function Stop(f, reason)
    local cb = f.castbar
    if not cb or not cb:IsShown() or cb.mode == "fade" then return end
    local fade = f.cfg.castbar.fadeTime or 0
    if not reason or fade <= 0 then
        cb.mode = nil
        cb:Hide()
        return
    end
    Paint(f, reason)
    if reason == "interrupted" then
        cb.text:SetText(L["Interrupted"])
    else
        cb.bar:SetMinMaxValues(0, 1)
        cb.bar:SetValue(1)
    end
    cb.time:SetText("")
    FadeOut(cb, fade)
end

-- The game moves the bar itself (secret times)
local function TryTimer(cb, unit, channel)
    local getDuration = channel and UnitChannelDuration or UnitCastingDuration
    if not getDuration or not cb.bar.SetTimerDuration or not Enum.StatusBarTimerDirection then return false end
    local ok = pcall(function()
        local d = getDuration(unit)
        local dir = channel and Enum.StatusBarTimerDirection.RemainingTime or Enum.StatusBarTimerDirection.ElapsedTime
        cb.bar:SetTimerDuration(d, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0, dir)
    end)
    return ok
end

-- Has a value (secret values cannot be tested with "if")
local function Has(v)
    return S(v) or v ~= nil
end

-- fresh: a new cast (not a delay or update): measures the latency
local function Start(f, channel, fresh)
    local cb = f.castbar
    if not cb or not f.cfg.castbar.enabled then return end
    local u = f.unit
    local name, text, texture, startMs, endMs, notInterruptible, _
    if channel then
        name, text, texture, startMs, endMs, _, notInterruptible = UnitChannelInfo(u)
    else
        name, text, texture, startMs, endMs, _, _, notInterruptible = UnitCastingInfo(u)
    end
    if not Has(name) then return Stop(f) end

    cb.channel = channel
    cb:SetAlpha(1)
    Paint(f, StateKey(cb, notInterruptible))
    if Has(text) then cb.text:SetText(text) else cb.text:SetText(name) end
    if cb.icon:IsShown() then pcall(cb.icon.SetTexture, cb.icon, texture) end

    if fresh then cb.lag:Hide() end
    if not S(startMs) and not S(endMs) and startMs and endMs then
        cb.mode = "manual"
        cb.start, cb.finish = startMs / 1000, endMs / 1000
        cb.bar:SetMinMaxValues(0, cb.finish - cb.start)
        -- latency, only for your own casts
        local total = cb.finish - cb.start
        if fresh and u == "player" and f.cfg.castbar.latency and ns.castSentAt and total > 0 then
            local lag = math.min(total, math.max(0, GetTime() - ns.castSentAt))
            local c = ns.Color("cast", "latency")
            cb.lag:SetVertexColor(c.r, c.g, c.b, c.a or 0.6)
            cb.lag:ClearAllPoints()
            local side = channel and "LEFT" or "RIGHT"
            cb.lag:SetPoint("TOP" .. side)
            cb.lag:SetPoint("BOTTOM" .. side)
            cb.lag:SetWidth(math.max(1, cb.bar:GetWidth() * lag / total))
            cb.lag:Show()
        end
    elseif TryTimer(cb, u, channel) then
        cb.mode = "timer"
        cb.time:SetText("")
    else
        cb.mode = "static"
        cb.bar:SetMinMaxValues(0, 1)
        cb.bar:SetValue(1)
        cb.time:SetText("")
    end
    cb:Show()
end

-- Is the unit casting right now? (unit change, show, test mode)
function ns.UpdateCastbar(f)
    local cb = f.castbar
    if not cb or not f.cfg.castbar or not f.cfg.castbar.enabled then return end
    local casting = UnitCastingInfo(f.unit)
    local channeling = UnitChannelInfo(f.unit)
    if ns.Fake(f.unit) or (ns.testMode and not Has(casting) and not Has(channeling)) then
        cb.mode = nil
        cb.channel = false
        cb:SetAlpha(1)
        Paint(f, "cast")
        cb.bar:SetMinMaxValues(0, 1)
        cb.bar:SetValue(0.6)
        cb.text:SetText(L["Test cast"])
        cb.time:SetText(f.cfg.castbar.timeFormat == "both" and "1.2 / 3.0" or "1.2")
        if cb.icon:IsShown() then cb.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
        -- sample latency at the end of your bar
        cb.lag:Hide()
        if f.unit == "player" and f.cfg.castbar.latency then
            local c = ns.Color("cast", "latency")
            cb.lag:SetVertexColor(c.r, c.g, c.b, c.a or 0.6)
            cb.lag:ClearAllPoints()
            cb.lag:SetPoint("TOPRIGHT")
            cb.lag:SetPoint("BOTTOMRIGHT")
            cb.lag:SetWidth(math.max(1, cb.bar:GetWidth() * 0.12))
            cb.lag:Show()
        end
        cb:Show()
        return
    end
    if Has(casting) then return Start(f, false) end
    if Has(channeling) then return Start(f, true) end
    if cb.mode ~= "fade" then Stop(f) end
end

-- when you press a spell: the start of the latency
ns.On("UNIT_SPELLCAST_SENT", function() ns.castSentAt = GetTime() end)
ns.On("UNIT_SPELLCAST_START", function(f) Start(f, false, true) end)
ns.On("UNIT_SPELLCAST_DELAYED", function(f) Start(f, false) end)
ns.On("UNIT_SPELLCAST_CHANNEL_START", function(f) Start(f, true, true) end)
ns.On("UNIT_SPELLCAST_CHANNEL_UPDATE", function(f) Start(f, true) end)
ns.On("UNIT_SPELLCAST_STOP", function(f) if f.castbar and not f.castbar.channel then Stop(f, "done") end end)
ns.On("UNIT_SPELLCAST_FAILED", function(f) if f.castbar and not f.castbar.channel then Stop(f, "interrupted") end end)
ns.On("UNIT_SPELLCAST_INTERRUPTED", function(f) Stop(f, "interrupted") end)
ns.On("UNIT_SPELLCAST_CHANNEL_STOP", function(f) Stop(f, "done") end)
ns.On("UNIT_SPELLCAST_INTERRUPTIBLE", function(f) if f.castbar and f.castbar.mode ~= "fade" then Paint(f, f.castbar.channel and "channel" or "cast") end end)
ns.On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", function(f) if f.castbar and f.castbar.mode ~= "fade" then Paint(f, "locked") end end)
