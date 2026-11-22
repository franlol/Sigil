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
-- Your own casts also show the latency, channel ticks and one bar for a
-- crafting batch (their colors are cast bar settings).
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

local FLAT = "Interface\\Buttons\\WHITE8X8"

local function CastRGB(key)
    local c = ns.Color("cast", key)
    return c.r, c.g, c.b
end

local PASSED_ALPHA = 0.35   -- a channel tick that already happened

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
    -- base: time of the crafts already made in a batch; span: the whole bar
    local now = GetTime()
    local times = self.tickTimes
    if times then
        local i = self.nextTick
        while times[i] and now >= times[i] do
            self.marks[i]:SetAlpha(PASSED_ALPHA)
            i = i + 1
        end
        self.nextTick = i
    end
    if now >= self.finish then
        self.bar:SetValue(self.channel and 0 or self.base + self.finish - self.start)
        return
    end
    local v = self.channel and (self.finish - now) or (self.base + now - self.start)
    self.bar:SetValue(v)
    local left = ns.FormatTime(self.timeRules, self.span - self.base - (now - self.start))
    if self.timeFormat == "both" then
        self.time:SetText(left .. " / " .. ns.FormatTime(self.totalRules, self.span))
    else
        self.time:SetText(left)
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
    cb.marks = {}   -- channel tick lines, made when first needed

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
    cb:SetSize(c.width and c.width > 0 and c.width or ns.FrameWidth(f), h)

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

    local auto = ns.AutoSize("long", h)
    ns.StyleText(cb.text, c.nameText, auto)
    ns.StyleText(cb.time, c.timeText, auto)
    cb.time:ClearAllPoints()
    cb.time:SetPoint("RIGHT", -4, 0)
    cb.text:ClearAllPoints()
    cb.text:SetPoint("LEFT", 4, 0)
    cb.text:SetPoint("RIGHT", cb.time, "LEFT", -4, 0)
    cb.timeFormat = c.timeFormat
    cb.timeRules = ns.TimeRules(c.timeFmt)
    cb.totalRules = ns.TimeRules(c.timeFmt, true)   -- the total: no warning color
end

local function Paint(f, key)
    local cb = f.castbar
    ns.PaintBar(cb.bar, f.cfg.castbar.style, CastRGB(key))
end

local function StateKey(cb, notInterruptible)
    if R(notInterruptible) then return "locked" end
    return cb.channel and "channel" or "cast"
end

-- Crafting many at once ("Create all"): one bar for the whole batch.
-- The game says how many crafts are left when the first one starts; Sigil
-- counts the ones that follow. nil when no batch is being made.
local batch   -- { spell, index (the craft being made), total }

-- fresh: a new cast; returns the batch this cast belongs to, or nil
local function Batch(fresh, spellID)
    if not fresh then return batch end
    if batch and spellID and batch.spell == spellID then
        batch.index = batch.index + 1
        batch.total = math.max(batch.total, batch.index)
        return batch
    end
    local get = C_TradeSkillUI and C_TradeSkillUI.GetRemainingRecasts
    local left = get and R(get())
    if type(left) == "number" and left > 0 and spellID then
        batch = { spell = spellID, index = 1, total = left + 1 }
    else
        batch = nil
    end
    return batch
end

-------------------------------------------------------------------------------
-- Channel ticks (your own channels): a line where each tick lands. The count
-- comes from ns.CHANNEL_TICKS; the ticks are spread evenly over the channel
-- the game started (haste included) and keep their times when a pushback
-- ends it sooner. Passed ticks are dimmed (OnUpdate).
-------------------------------------------------------------------------------
local function HideTicks(cb)
    for _, m in ipairs(cb.marks) do m:Hide() end
    cb.tickTimes, cb.tickSpell, cb.nextTick = nil, nil, nil
end

-- fracs[i]: where line i goes, as a share of the bar from where it fills
local function DrawMarks(cb, fracs, color)
    local bar = cb.bar
    local vertical = bar:GetOrientation() == "VERTICAL"
    local reverse = bar:GetReverseFill()
    local side = vertical and (reverse and "TOP" or "BOTTOM") or (reverse and "RIGHT" or "LEFT")
    local length = vertical and bar:GetHeight() or bar:GetWidth()
    local sign = reverse and -1 or 1
    local thick = PixelUtil and PixelUtil.GetNearestPixelSize(1, bar:GetEffectiveScale(), 1) or 1
    for i, frac in ipairs(fracs) do
        local m = cb.marks[i]
        if not m then
            m = bar:CreateTexture(nil, "ARTWORK", nil, 7)   -- over the fill, under the texts
            m:SetTexture(FLAT)
            cb.marks[i] = m
        end
        m:ClearAllPoints()
        if frac > 0 and frac < 1 then
            if vertical then
                m:SetSize(bar:GetWidth(), thick)
                m:SetPoint("CENTER", bar, side, 0, sign * frac * length)
            else
                m:SetSize(thick, bar:GetHeight())
                m:SetPoint("CENTER", bar, side, sign * frac * length, 0)
            end
            m:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            m:SetAlpha(1)
            m:Show()
        else
            m:Hide()
        end
    end
    for i = #fracs + 1, #cb.marks do cb.marks[i]:Hide() end
end

-- Your channel (plain times): where its ticks land. fresh: a new channel
local function ChannelTicks(f, spellID, fresh)
    local cb, c = f.castbar, f.cfg.castbar
    local n = f.unit == "player" and c.ticks and spellID and ns.CHANNEL_TICKS[spellID]
    if not n then return HideTicks(cb) end
    if fresh or cb.tickSpell ~= spellID or not cb.tickTimes then
        local step = (cb.finish - cb.start) / n
        cb.tickTimes, cb.tickSpell = {}, spellID
        for k = 1, n - 1 do cb.tickTimes[k] = cb.start + k * step end
    end
    -- the bar shows the time left: a tick sits where that time is left
    local span = cb.finish - cb.start
    local fracs = {}
    for i, t in ipairs(cb.tickTimes) do fracs[i] = (cb.finish - t) / span end
    DrawMarks(cb, fracs, c.tickColor)
    cb.nextTick = 1
    local now = GetTime()
    while cb.tickTimes[cb.nextTick] and now >= cb.tickTimes[cb.nextTick] do
        cb.marks[cb.nextTick]:SetAlpha(PASSED_ALPHA)
        cb.nextTick = cb.nextTick + 1
    end
end

-- Does a stop event belong to the cast on the bar? A cast that ended can
-- send its stop after the next cast started. Unknown ids always match;
-- channels are not checked (like the game's own cast bar).
local function SameCast(cb, guid)
    if cb.channel then return true end
    guid = R(guid)
    return not guid or not cb.castGUID or guid == cb.castGUID
end

-- reason: "done" (completed) or "interrupted"; nil hides at once
-- guid: the cast the stop event is about
local function Stop(f, reason, guid)
    local cb = f.castbar
    if not cb or not cb:IsShown() or cb.mode == "fade" then return end
    if not SameCast(cb, guid) then return end
    cb.hidden = nil
    if cb.craft then cb.craft, batch = nil, nil end
    HideTicks(cb)
    local fade = f.cfg.castbar.fadeTime or 0
    cb.mode = nil
    if not reason or fade <= 0 then
        cb:Hide()
        return
    end
    Paint(f, reason)
    if reason == "interrupted" then cb.text:SetText(L["Interrupted"]) end
    -- full bar for both ends (also takes the bar back from the game's timer)
    cb.bar:SetMinMaxValues(0, 1)
    cb.bar:SetValue(1)
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
-- guid: the cast id from the event (nil when called outside an event)
local function Start(f, channel, fresh, guid)
    local cb = f.castbar
    if not cb or not f.cfg.castbar.enabled then return end
    local u = f.unit
    local name, text, texture, startMs, endMs, notInterruptible, castID, spellID, _
    if channel then
        name, text, texture, startMs, endMs, _, notInterruptible, spellID = UnitChannelInfo(u)
    else
        name, text, texture, startMs, endMs, _, castID, notInterruptible, spellID = UnitCastingInfo(u)
    end
    if not Has(name) then return Stop(f) end

    cb.hidden = nil   -- a real cast takes the bar
    cb.channel = channel
    cb.castGUID = R(guid) or R(castID)
    cb.craft = not channel and u == "player" and f.cfg.castbar.batch and Batch(fresh, R(spellID)) or nil
    cb:SetAlpha(1)
    Paint(f, StateKey(cb, notInterruptible))
    if not Has(text) then text = name end
    if cb.craft then
        -- one number: how many are left, this one included
        cb.text:SetText(text .. " (" .. (cb.craft.total - cb.craft.index + 1) .. ")")
    else
        cb.text:SetText(text)
    end
    if cb.icon:IsShown() then pcall(cb.icon.SetTexture, cb.icon, texture) end

    if fresh then cb.lag:Hide() end
    if not S(startMs) and not S(endMs) and startMs and endMs then
        cb.mode = "manual"
        cb.start, cb.finish = startMs / 1000, endMs / 1000
        local total = cb.finish - cb.start
        local craft = cb.craft
        cb.base = craft and (craft.index - 1) * total or 0
        cb.span = craft and craft.total * total or total
        cb.bar:SetMinMaxValues(0, cb.span)
        -- latency, only for your own casts: from the key press of this same
        -- cast, used once (not on a batch)
        local sent = ns.castSent
        if fresh and u == "player" then ns.castSent = nil end
        if fresh and u == "player" and f.cfg.castbar.latency and sent and total > 0 and not craft
            and cb.castGUID and sent.guid == cb.castGUID then
            local lag = math.min(total, math.max(0, GetTime() - sent.at))
            local c = f.cfg.castbar.latencyColor
            cb.lag:SetVertexColor(c.r, c.g, c.b, c.a or 0.6)
            cb.lag:ClearAllPoints()
            local side = channel and "LEFT" or "RIGHT"
            cb.lag:SetPoint("TOP" .. side)
            cb.lag:SetPoint("BOTTOM" .. side)
            cb.lag:SetWidth(math.max(1, cb.bar:GetWidth() * lag / total))
            cb.lag:Show()
        end
        if channel then ChannelTicks(f, R(spellID), fresh) else HideTicks(cb) end
    elseif TryTimer(cb, u, channel) then
        HideTicks(cb)
        cb.mode = "timer"
        cb.time:SetText("")
    else
        cb.mode = "static"
        HideTicks(cb)
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
        local left = ns.FormatTime(cb.timeRules, 1.2)
        cb.time:SetText(f.cfg.castbar.timeFormat == "both" and left .. " / " .. ns.FormatTime(cb.totalRules, 3) or left)
        if cb.icon:IsShown() then cb.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
        -- sample ticks and latency on your bar, to see their colors
        HideTicks(cb)
        if f.unit == "player" and f.cfg.castbar.ticks then
            DrawMarks(cb, { 0.2, 0.4, 0.6, 0.8 }, f.cfg.castbar.tickColor)
        end
        cb.lag:Hide()
        if f.unit == "player" and f.cfg.castbar.latency then
            local c = f.cfg.castbar.latencyColor
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
    -- a hidden cast (Multi-Shot) is not one the game reports: it ends on its events
    if cb.hidden and cb.mode == "manual" then return end
    if cb.mode ~= "fade" and cb.mode ~= "wait" then Stop(f) end
end

-- One craft of a batch ended and more follow: the bar holds until the next
local function CraftDone(f, guid)
    local cb = f.castbar
    local craft = cb.craft
    if not craft or craft.index >= craft.total or cb.mode ~= "manual" or not SameCast(cb, guid) then
        return false
    end
    cb.mode = "wait"
    cb.bar:SetValue(cb.base + cb.finish - cb.start)
    return true
end

-------------------------------------------------------------------------------
-- Multi-Shot (hunters, your bar): the game sends no cast for its short cast,
-- only the key press (SENT) and the shot (SUCCEEDED), or FAILED /
-- INTERRUPTED. The bar runs from the press over the aiming time (the same
-- short cast as Auto Shot's, a swing timer setting) and ends when the game
-- says the shot is done.
-------------------------------------------------------------------------------
local MULTI_SHOT = { [2643] = true, [14288] = true, [14289] = true, [14290] = true, [25294] = true }

local function HiddenStart(f, guid, spellID)
    local cb, c = f.castbar, f.cfg.castbar
    if f.unit ~= "player" or not cb or not c.enabled or not c.multiShot then return end
    spellID = R(spellID)
    if not (spellID and MULTI_SHOT[spellID]) then return end
    -- a press while it is already on the bar (or during a real cast) is not a new shot
    if cb:IsShown() and (cb.mode == "manual" or cb.mode == "timer" or cb.mode == "static") then return end
    local now = GetTime()
    local total = f.cfg.swing and f.cfg.swing.aimTime or 0.5
    cb.hidden, cb.channel, cb.craft = true, false, nil
    cb.castGUID = R(guid)
    cb:SetAlpha(1)
    Paint(f, "cast")
    cb.text:SetText(C_Spell.GetSpellName(spellID) or "")
    if cb.icon:IsShown() then cb.icon:SetTexture(C_Spell.GetSpellTexture(spellID)) end
    HideTicks(cb)
    cb.lag:Hide()
    cb.mode = "manual"
    cb.start, cb.finish, cb.base, cb.span = now, now + total, 0, total
    cb.bar:SetMinMaxValues(0, total)
    cb.bar:SetValue(0)
    cb:Show()
end

-- when you press a spell: the start of the latency (and of Multi-Shot)
ns.On("UNIT_SPELLCAST_SENT", function(f, _, _, guid, spellID)
    ns.castSent = { guid = R(guid), at = GetTime() }
    HiddenStart(f, guid, spellID)
end)
-- the shot of a hidden cast (real casts end on STOP)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(f, _, guid)
    if f.castbar and f.castbar.hidden then Stop(f, "done", guid) end
end)
ns.On("UNIT_SPELLCAST_START", function(f, _, guid) Start(f, false, true, guid) end)
ns.On("UNIT_SPELLCAST_DELAYED", function(f, _, guid) Start(f, false, false, guid) end)
ns.On("UNIT_SPELLCAST_CHANNEL_START", function(f, _, guid) Start(f, true, true, guid) end)
ns.On("UNIT_SPELLCAST_CHANNEL_UPDATE", function(f, _, guid) Start(f, true, false, guid) end)
ns.On("UNIT_SPELLCAST_STOP", function(f, _, guid)
    if not f.castbar or f.castbar.channel or CraftDone(f, guid) then return end
    Stop(f, "done", guid)
end)
-- the game stopped making the batch (finished, cancelled or out of materials)
ns.On("UPDATE_TRADESKILL_CAST_STOPPED", function(f)
    if f.castbar and f.castbar.mode == "wait" then Stop(f, "done") end
    batch = nil
end)
ns.On("UNIT_SPELLCAST_FAILED", function(f, _, guid) if f.castbar and not f.castbar.channel then Stop(f, "interrupted", guid) end end)
ns.On("UNIT_SPELLCAST_INTERRUPTED", function(f, _, guid) Stop(f, "interrupted", guid) end)
-- a channel cut short says who interrupted it
ns.On("UNIT_SPELLCAST_CHANNEL_STOP", function(f, _, guid, _, by) Stop(f, Has(by) and "interrupted" or "done", guid) end)
ns.On("UNIT_SPELLCAST_INTERRUPTIBLE", function(f) if f.castbar and f.castbar.mode ~= "fade" then Paint(f, f.castbar.channel and "channel" or "cast") end end)
ns.On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", function(f) if f.castbar and f.castbar.mode ~= "fade" then Paint(f, "locked") end end)
