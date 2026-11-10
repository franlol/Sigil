-------------------------------------------------------------------------------
-- Sigil - API probe (phase 0)
--
-- /sigil probe checks which functions, events and templates exist in this
-- client, calls the unit functions on player/target/focus/pet and records
-- which values come back secret. Results go to SigilDB.probe[context], one
-- entry per context (world, dungeon, raid... and in combat or not).
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local UNITS = { "player", "target", "targettarget", "focus", "pet" }

-- Functions that only need to exist (not called)
local FUNCTIONS = {
    "loadstring", "load", "setfenv", "getfenv",
    "SetPortraitTexture", "SetPortraitTextureFromCreatureDisplayID",
    "RegisterUnitWatch", "RegisterStateDriver", "SecureHandlerWrapScript",
    "UnitHealthPercent", "UnitPowerPercent", "UnitCastingDuration", "UnitChannelDuration",
    "UnitGetDetailedHealPrediction", "CreateUnitHealPredictionCalculator",
    "C_CurveUtil.CreateCurve", "C_CurveUtil.CreateColorCurve", "C_DurationUtil.CreateDuration",
    "C_UnitAuras.GetAuraDataByIndex", "C_UnitAuras.GetAuraDataByAuraInstanceID",
    "C_UnitAuras.GetUnitAuras", "C_UnitAuras.GetAuraSlots", "C_UnitAuras.GetAuraDuration",
    "AuraUtil.ForEachAura", "C_Spell.GetSpellInfo", "C_Spell.GetSpellTexture",
    "C_Reputation.GetWatchedFactionData", "GetWatchedFactionInfo",
    "GetPetHappiness", "GetTotemInfo", "GetComboPoints", "GetShapeshiftForm",
    "C_EventUtils.IsEventValid", "C_XMLUtil.GetTemplateInfo",
    "C_Timer.After", "C_Timer.NewTicker",
}

local EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT",
    "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
    "UNIT_FACTION", "UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED",
    "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE", "UNIT_COMBAT",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_PET", "UNIT_HAPPINESS", "PET_UI_UPDATE", "UNIT_TARGET", "UNIT_PHASE",
    "UNIT_CONNECTION", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED", "UNIT_ENTERED_VEHICLE",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION",
    "UPDATE_FACTION", "RAID_TARGET_UPDATE", "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE",
    "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED",
    "INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED", "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_TOTEM_UPDATE", "COMBAT_LOG_EVENT_UNFILTERED",
}

local TEMPLATES = {
    "SecureUnitButtonTemplate", "SecureActionButtonTemplate", "SecureHandlerStateTemplate",
    "SecureHandlerAttributeTemplate", "PingableUnitFrameTemplate", "BackdropTemplate",
    "CooldownFrameTemplate", "CastingBarFrameTemplate", "SmallCastingBarFrameTemplate",
    "CustomAuraContainerTemplate",
}

local BLIZZARD_FRAMES = {
    "PlayerFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT", "PetFrame",
    "PlayerCastingBarFrame", "CastingBarFrame", "TargetFrameSpellBar", "FocusFrameSpellBar",
    "PetCastingBarFrame", "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
    "ComboFrame", "ComboPointPlayerFrame", "TotemFrame", "PlayerFrameAlternateManaBar",
}

-- "@" is replaced by the unit
local UNIT_CALLS = {
    { "UnitExists", "@" }, { "UnitGUID", "@" }, { "UnitName", "@" }, { "UnitLevel", "@" },
    { "UnitEffectiveLevel", "@" }, { "UnitClass", "@" }, { "UnitRace", "@" },
    { "UnitClassification", "@" }, { "UnitCreatureType", "@" }, { "UnitIsPlayer", "@" },
    { "UnitIsFriend", "player", "@" }, { "UnitCanAttack", "player", "@" },
    { "UnitReaction", "@", "player" }, { "UnitIsTapDenied", "@" },
    { "UnitHealth", "@" }, { "UnitHealthMax", "@" }, { "UnitHealthPercent", "@" },
    { "UnitPower", "@" }, { "UnitPowerMax", "@" }, { "UnitPowerType", "@" },
    { "UnitGetIncomingHeals", "@" }, { "UnitGetTotalAbsorbs", "@" }, { "UnitGetTotalHealAbsorbs", "@" },
    { "UnitIsDeadOrGhost", "@" }, { "UnitIsConnected", "@" }, { "UnitIsAFK", "@" },
    { "UnitAffectingCombat", "@" }, { "UnitIsPVP", "@" }, { "UnitFactionGroup", "@" },
    { "UnitIsGroupLeader", "@" }, { "GetRaidTargetIndex", "@" }, { "UnitPhaseReason", "@" },
    { "UnitHasIncomingResurrection", "@" }, { "C_IncomingSummon.HasIncomingSummon", "@" },
    { "GetReadyCheckStatus", "@" }, { "UnitIsQuestBoss", "@" },
    { "UnitThreatSituation", "player", "@" }, { "UnitDetailedThreatSituation", "player", "@" },
    { "CheckInteractDistance", "@", 4 }, { "UnitIsVisible", "@" }, { "UnitInRange", "@" },
    { "UnitCastingInfo", "@" }, { "UnitChannelInfo", "@" }, { "GetComboPoints", "player", "@" },
}

local GLOBAL_CALLS = {
    { "IsInInstance" }, { "GetInstanceInfo" }, { "IsResting" },
    { "UnitXP", "player" }, { "UnitXPMax", "player" }, { "GetXPExhaustion" },
    { "GetWatchedFactionInfo" }, { "GetPetHappiness" }, { "GetTotemInfo", 1 },
    { "GetShapeshiftForm" }, { "UnitPower", "player", 4 }, { "UnitPowerMax", "player", 4 },
}

local AURA_FIELDS = {
    "name", "icon", "applications", "duration", "expirationTime", "spellId",
    "dispelName", "sourceUnit", "isStealable", "auraInstanceID", "isHelpful", "isHarmful",
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local stats

local function Pack(...) return { n = select("#", ...), ... } end

-- Finds a global by dotted path ("C_UnitAuras.GetAuraDataByIndex")
local function Find(path)
    local t = _G
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function Describe(v)
    if ns.S(v) then
        stats.secret = stats.secret + 1
        local ok, tv = pcall(type, v)
        return "SECRET " .. (ok and tv or "?")
    end
    local tv = type(v)
    if tv == "nil" or tv == "table" or tv == "function" or tv == "userdata" then return tv end
    return tv .. " " .. tostring(v)
end

local function Call(path, ...)
    local f = Find(path)
    if type(f) ~= "function" then
        stats.missing = stats.missing + 1
        return "MISSING"
    end
    local res = Pack(pcall(f, ...))
    if not res[1] then
        stats.errors = stats.errors + 1
        return "ERROR " .. tostring(res[2])
    end
    local out = {}
    for i = 2, math.min(res.n, 13) do out[#out + 1] = Describe(res[i]) end
    return table.concat(out, " | ")
end

-- Runs func and records "ok <value>" or "ERROR <message>"
local function Try(func)
    local res = Pack(pcall(func))
    if not res[1] then
        stats.errors = stats.errors + 1
        return "ERROR " .. tostring(res[2])
    end
    return "ok " .. Describe(res[2])
end

local function Args(list, unit)
    local args = {}
    for i = 2, #list do
        local a = list[i]
        if a == "@" then a = unit end
        args[i - 1] = a
    end
    return args
end

-------------------------------------------------------------------------------
-- Probe sections
-------------------------------------------------------------------------------
local function ProbeAuras(unit)
    local out = {}
    local get = Find("C_UnitAuras.GetAuraDataByIndex")
    if type(get) ~= "function" then return "MISSING" end
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local ok, aura = pcall(get, unit, 1, filter)
        if not ok then
            stats.errors = stats.errors + 1
            out[filter] = "ERROR " .. tostring(aura)
        elseif ns.S(aura) then
            stats.secret = stats.secret + 1
            out[filter] = "SECRET"
        elseif type(aura) ~= "table" then
            out[filter] = "none"
        else
            local fields = {}
            for _, k in ipairs(AURA_FIELDS) do fields[k] = Describe(aura[k]) end
            out[filter] = fields
        end
    end
    return out
end

-- What we can do with a secret value: texts and bars need these
local function ProbeSecretUse(unit)
    local h = UnitHealth(unit)
    local m = UnitHealthMax(unit)
    local fs = ns.probeFS
    local bar = ns.probeBar
    return {
        healthIsSecret = ns.S(h),
        concat = Try(function() return h .. "" end),
        format = Try(function() return string.format("%d", h) end),
        tostring = Try(function() return tostring(h) end),
        divide = Try(function() return h / m end),
        compare = Try(function() return h < m end),
        setText = Try(function() fs:SetText(h) return fs:GetText() end),
        setFormattedText = Try(function() fs:SetFormattedText("%d / %d", h, m) return fs:GetText() end),
        barMinMax = Try(function() bar:SetMinMaxValues(0, m) return true end),
        barValue = Try(function() bar:SetValue(h) return bar:GetValue() end),
    }
end

local function ProbeLuaTexts()
    return {
        loadstring = Try(function()
            local chunk = assert(loadstring("return UnitName('player')"))
            setfenv(chunk, { UnitName = UnitName })
            return chunk()
        end),
    }
end

local function ProbePortraits()
    return {
        texture2D = Try(function()
            ns.probeTex = ns.probeTex or ns.probeFrame:CreateTexture()
            SetPortraitTexture(ns.probeTex, "player")
            return ns.probeTex:GetTexture()
        end),
        model3D = Try(function()
            ns.probeModel = ns.probeModel or CreateFrame("PlayerModel", nil, ns.probeFrame)
            ns.probeModel:SetUnit("player")
            return ns.probeModel:GetModelFileID()
        end),
    }
end

local function Context()
    local inInstance, kind = IsInInstance()
    local key = inInstance and kind or "world"
    if InCombatLockdown() then key = key .. "+combat" end
    return key
end

-------------------------------------------------------------------------------
-- Entry point
-------------------------------------------------------------------------------
function ns.Probe()
    stats = { missing = 0, secret = 0, errors = 0 }
    if not ns.probeFrame then
        ns.probeFrame = CreateFrame("Frame", nil, UIParent)
        ns.probeFrame:Hide()
        ns.probeFS = ns.probeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ns.probeBar = CreateFrame("StatusBar", nil, ns.probeFrame)
    end

    local r = {
        time = date("%Y-%m-%d %H:%M:%S"),
        build = select(4, GetBuildInfo()),
        functions = {}, events = {}, templates = {}, blizzard = {}, global = {}, units = {},
    }

    for _, f in ipairs(FUNCTIONS) do
        local exists = type(Find(f)) == "function"
        if not exists then stats.missing = stats.missing + 1 end
        r.functions[f] = exists
    end

    local isValid = Find("C_EventUtils.IsEventValid")
    for _, e in ipairs(EVENTS) do
        r.events[e] = type(isValid) == "function" and isValid(e) or "unknown"
    end

    local templateInfo = Find("C_XMLUtil.GetTemplateInfo")
    for _, t in ipairs(TEMPLATES) do
        r.templates[t] = type(templateInfo) == "function" and templateInfo(t) ~= nil or "unknown"
    end

    for _, name in ipairs(BLIZZARD_FRAMES) do
        r.blizzard[name] = _G[name] ~= nil
    end

    for _, c in ipairs(GLOBAL_CALLS) do
        local key = c[1] .. "(" .. table.concat(Args(c), ",") .. ")"
        r.global[key] = Call(c[1], unpack(Args(c)))
    end

    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) then
            local u = { calls = {} }
            for _, c in ipairs(UNIT_CALLS) do
                u.calls[c[1]] = Call(c[1], unpack(Args(c, unit)))
            end
            u.auras = ProbeAuras(unit)
            u.secretUse = ProbeSecretUse(unit)
            r.units[unit] = u
        else
            r.units[unit] = "does not exist"
        end
    end

    r.luaTexts = ProbeLuaTexts()
    r.portraits = ProbePortraits()

    local context = Context()
    ns.db.probe = ns.db.probe or {}
    ns.db.probe[context] = r

    ns.Print(L["Probe saved for context %s: %d missing, %d secret, %d errors."]:format(
        context, stats.missing, stats.secret, stats.errors))
    ns.Print(L["Type /reload to write it to disk."])
    ns.Print(L["Tip: run it with a target, a focus and your pet, in the open world, in a dungeon and in combat."])
end

-------------------------------------------------------------------------------
-- /sigil gcd: what the game gives for the global cooldown. Run it right after
-- casting a spell (within a second).
-------------------------------------------------------------------------------
local GCD_SPELL = 61304

-- Every line goes to the chat and to SigilDB.gcdProbe (read after /reload)
local function Out(line)
    print(line)
    ns.db.gcdProbe = ns.db.gcdProbe or {}
    table.insert(ns.db.gcdProbe, line)
end

local function Show(label, v)
    if ns.S(v) then
        Out("  " .. label .. ": SECRET " .. type(v))
    else
        Out("  " .. label .. ": " .. tostring(v))
    end
end

function ns.ProbeGCD(spellID)
    spellID = spellID or GCD_SPELL
    Out("GCD " .. spellID .. " (" .. tostring((ns.GetSpellName(spellID))) .. ")")
    if not (C_Spell and C_Spell.GetSpellCooldown) then
        Out("  C_Spell.GetSpellCooldown: MISSING")
        return
    end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok then
        Out("  GetSpellCooldown: ERROR " .. tostring(info))
    elseif not info then
        Out("  GetSpellCooldown: nil")
    else
        Show("startTime", info.startTime)
        Show("duration", info.duration)
        Show("isEnabled", info.isEnabled)
        Show("modRate", info.modRate)
    end
    if C_Spell.GetSpellCooldownDuration then
        local ok2, d = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        Out("  GetSpellCooldownDuration: " .. (ok2 and (d and (ns.S(d) and "SECRET object" or "object") or "nil") or ("ERROR " .. tostring(d))))
        if ok2 and d then
            local bar = ns.probeBar or CreateFrame("StatusBar")
            local ok3, err = pcall(bar.SetTimerDuration, bar, d)
            Out("  StatusBar:SetTimerDuration: " .. (ok3 and "ok" or ("ERROR " .. tostring(err))))
        end
    else
        Out("  C_Spell.GetSpellCooldownDuration: MISSING")
    end
end

-- /sigil gcd with no spell: waits for your next cast and probes as it starts
-- (the global cooldown starts with the cast: a spell with a cast time ends
-- after it), a moment later so the game has updated the cooldowns
function ns.ProbeNextGCD()
    ns.Print(L["Cast any spell: the global cooldown is probed right after it."])
    ns.db.gcdProbe = {}
    local w = ns.gcdProbeWatcher or CreateFrame("Frame")
    ns.gcdProbeWatcher = w
    w:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    w:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    w:SetScript("OnEvent", function(self, _, _, _, castID)
        self:UnregisterAllEvents()
        C_Timer.After(0.1, function()
            ns.ProbeGCD()
            -- the spell cast: its cooldown is the global one when it has none of its own
            if castID then ns.ProbeGCD(castID) end
            -- the old API, if the client has it
            if GetSpellCooldown then
                local ok, st, dur = pcall(GetSpellCooldown, GCD_SPELL)
                Out("  GetSpellCooldown(61304) old API: " .. (ok and (tostring(st) .. " / " .. tostring(dur)) or "ERROR"))
                if castID then
                    ok, st, dur = pcall(GetSpellCooldown, castID)
                    Out("  GetSpellCooldown(cast) old API: " .. (ok and (tostring(st) .. " / " .. tostring(dur)) or "ERROR"))
                end
            end
            ns.Print(L["Type /reload to write it to disk."])
        end)
    end)
end
