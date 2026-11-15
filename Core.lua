-------------------------------------------------------------------------------
-- Sigil - Core: saved variables, profile, secret value helpers, combat queue
-- and slash commands
-------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

-- From the TOC; "dev" when running from the repository (not packaged)
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or ""
if ns.version:find("^@") then ns.version = "dev" end

-------------------------------------------------------------------------------
-- Secret values (Forever hides some unit values)
-------------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue or function() return false end

function ns.S(v) return issecretvalue(v) end

function ns.R(v)
    if issecretvalue(v) then return nil end
    return v
end

-- Rectangle of a shown frame or region on screen (pixels): left, bottom,
-- right, top. nil if hidden or if its place is secret.
function ns.ScreenRect(region)
    if not (region and region:IsVisible()) then return nil end
    local l, b, w, h = region:GetRect()
    l, b, w, h = ns.R(l), ns.R(b), ns.R(w), ns.R(h)
    if not (l and b and w and h) then return nil end
    local s = region:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

-- Distance from the cursor to a frame or region (pixels): 0 inside it,
-- nil if it has no rectangle. One rule for everything (IsMouseOver can be
-- secret on bars showing secret values).
function ns.CursorDistance(region)
    local l, b, r, t = ns.ScreenRect(region)
    if not l then return nil end
    local x, y = GetCursorPosition()
    local dx = x < l and l - x or x > r and x - r or 0
    local dy = y < b and b - y or y > t and y - t or 0
    return math.sqrt(dx * dx + dy * dy)
end

function ns.MouseOver(region)
    return ns.CursorDistance(region) == 0
end

-- A region lies inside another one (both shown, places not secret)
function ns.RectInside(region, outer)
    local l, b, r, t = ns.ScreenRect(region)
    local L, B, R, T = ns.ScreenRect(outer)
    if not (l and L) then return false end
    return l >= L - 0.5 and b >= B - 0.5 and r <= R + 0.5 and t <= T + 0.5
end

-------------------------------------------------------------------------------
-- Unit states as the player understands them
--
-- Some game functions answer a nearby but different question than the one an
-- indicator shows. Icons, texts, colors and faders use these helpers, never the
-- raw functions, so every part of the addon agrees:
--   InCombatLockdown   protected-code lockdown, still false inside the
--                      PLAYER_REGEN_DISABLED handlers (only for RunOOC & co.)
--   UnitIsDead(OrGhost) also true for a hunter feigning death
-------------------------------------------------------------------------------
local R = ns.R

-- The player is in combat (also right as PLAYER_REGEN_DISABLED fires)
function ns.InCombat()
    return R(UnitAffectingCombat("player")) and true or InCombatLockdown()
end

local function FeigningDeath(u)
    return UnitIsFeignDeath and R(UnitIsFeignDeath(u)) and true or false
end

function ns.IsDead(u)
    return R(UnitIsDead(u)) and not FeigningDeath(u) or false
end

function ns.IsGhost(u)
    return R(UnitIsGhost(u)) and true or false
end

function ns.IsDeadOrGhost(u)
    return ns.IsDead(u) or ns.IsGhost(u)
end

-- PvP flag: flagged right now, whatever flagged them (their own toggle, the
-- zone, the realm, attacking a flagged player)
function ns.IsPvPFreeForAll(u)
    return UnitIsPVPFreeForAll and R(UnitIsPVPFreeForAll(u)) and true or false
end

function ns.IsPvP(u)
    return ns.IsPvPFreeForAll(u) or (R(UnitIsPVP(u)) and true or false)
end

-- Seconds left before the player's PvP flag drops (nil: it is not counting down)
function ns.PvPTimeLeft()
    if not (IsPVPTimerRunning and GetPVPTimer) or not R(IsPVPTimerRunning()) then return nil end
    local ms = R(GetPVPTimer())
    if type(ms) ~= "number" or ms <= 0 then return nil end
    return ms / 1000
end

-------------------------------------------------------------------------------
-- Chat
-------------------------------------------------------------------------------
function ns.Print(msg)
    print("|cffb48cffSigil|r: " .. msg)
end

-------------------------------------------------------------------------------
-- Things that cannot be done in combat wait until it ends
-------------------------------------------------------------------------------
local pending, order = {}, {}

function ns.RunOOC(key, func)
    if InCombatLockdown() then
        if not pending[key] then order[#order + 1] = key end
        pending[key] = func
    else
        func()
    end
end

local function FlushPending()
    local keys = order
    order = {}
    for _, key in ipairs(keys) do
        local func = pending[key]
        pending[key] = nil
        if func then func() end
    end
end

-------------------------------------------------------------------------------
-- Settings: missing keys are filled from the defaults
-------------------------------------------------------------------------------
-- Lists the user edits (add, remove, reorder): never filled item by item
local LISTS = { texts = true, point = true, groups = true, spells = true, events = true }

local function Fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                Fill(dst[k], v)
            else
                dst[k] = v
            end
        elseif type(v) == "table" and type(dst[k]) == "table" and not LISTS[k] then
            Fill(dst[k], v)
        end
    end
end

-- Older settings in today's shape, before the defaults fill the gaps
local function Migrate(p)
    for _, u in pairs(type(p.units) == "table" and p.units or {}) do
        for _, ic in pairs(type(u) == "table" and type(u.icons) == "table" and u.icons or {}) do
            -- icons: `point` was the point of the frame the icon centers on
            if type(ic) == "table" and ic.relPoint == nil and ic.point then
                ic.relPoint, ic.point = ic.point, "CENTER"
            end
        end
        -- combat text is a text: one anchor, the same point on both sides
        local ct = type(u) == "table" and u.combatText
        if type(ct) == "table" and ct.relPoint and ct.point ~= ct.relPoint then ct.point = ct.relPoint end
        -- swing timer: melee/ranged switches, fill and colors became per bar
        local sw = type(u) == "table" and u.swing
        if type(sw) == "table" and type(sw.ranged) ~= "table" then
            local colors = type(sw.colors) == "table" and sw.colors or {}
            local fill = type(sw.fill) == "string" and sw.fill or nil
            local melee = sw.melee
            sw.main = { show = melee, fill = fill, color = colors.main }
            sw.off = { show = melee, fill = fill, color = colors.off }
            sw.ranged = { show = sw.ranged, fill = fill, color = colors.ranged }
            sw.melee, sw.colors, sw.fill = nil, nil, nil
        end
        -- swing timer: the time-left text became per bar (its look starts fresh)
        if type(sw) == "table" and sw.text ~= nil then
            for _, k in ipairs({ "main", "off", "ranged" }) do
                if type(sw[k]) == "table" then sw[k].text, sw[k].decimals = sw.text, sw.decimals end
            end
            sw.text, sw.decimals, sw.textStyle, sw.textPos = nil, nil, nil, nil
        end
        -- time texts: their format became a time format (see ns.TimeFormat)
        for _, k in ipairs({ "main", "off", "ranged" }) do
            local bar = type(sw) == "table" and sw[k]
            if type(bar) == "table" and bar.decimals ~= nil then
                if bar.timeFmt == nil then bar.timeFmt = { decimals = bar.decimals == 0 and 0 or 999 } end
                bar.decimals = nil
            end
        end
        local pvp = type(u) == "table" and type(u.icons) == "table" and u.icons.pvp
        if type(pvp) == "table" and pvp.timerFormat ~= nil then
            if pvp.timeFmt == nil then pvp.timeFmt = { style = pvp.timerFormat == "seconds" and "seconds" or "clock" } end
            pvp.timerFormat = nil
        end
    end
end

-- The profile in use, ready: migrated and filled from the defaults
local function Prepare()
    Migrate(ns.P)
    Fill(ns.P, ns.DEFAULTS)
end

local function CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-------------------------------------------------------------------------------
-- Named profiles: SigilDB.profiles[name] = settings,
-- SigilDB.profileOf[character] = name of the profile it uses
-------------------------------------------------------------------------------
local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = DeepCopy(v) end
    return c
end
ns.DeepCopy = DeepCopy

local function LoadProfile()
    local db = ns.db
    db.profiles = db.profiles or {}
    db.profileOf = db.profileOf or {}
    ns.charKey = CharKey()
    local name = db.profileOf[ns.charKey] or ns.charKey
    if not db.profiles[name] then db.profiles[name] = {} end
    db.profileOf[ns.charKey] = name
    ns.profileName = name
    ns.P = db.profiles[name]
    Prepare()
    ns.ResetGradient()
end

-- Switches this character to another profile (created if it does not exist)
function ns.UseProfile(name)
    local db = ns.db
    if not db.profiles[name] then db.profiles[name] = {} end
    db.profileOf[ns.charKey] = name
    ns.profileName = name
    ns.P = db.profiles[name]
    Prepare()
    ns.ResetGradient()
    ns.ApplyAll()
end

-- Copies the settings of another profile into the current one
function ns.CopyProfile(from)
    local src = ns.db.profiles[from]
    if not src or from == ns.profileName then return end
    wipe(ns.P)
    for k, v in pairs(DeepCopy(src)) do ns.P[k] = v end
    Prepare()
    ns.ResetGradient()
    ns.ApplyAll()
end

function ns.DeleteProfile(name)
    if name == ns.profileName then return end
    ns.db.profiles[name] = nil
    for char, p in pairs(ns.db.profileOf) do
        if p == name then ns.db.profileOf[char] = nil end
    end
end

function ns.ResetProfile()
    wipe(ns.P)
    Prepare()
    ns.ResetGradient()
    ns.ApplyAll()
end

-- Settings of one unit back to the defaults
function ns.ResetUnit(unit)
    ns.P.units[unit] = DeepCopy(ns.DEFAULTS.units[unit])
    ns.ApplyUnit(unit)
end

-- Replaces every setting of one unit (undo of a copy)
function ns.SetUnitSettings(unit, data)
    ns.P.units[unit] = data
    Prepare()
    ns.ApplyUnit(unit)
end

-------------------------------------------------------------------------------
-- Copy settings from one frame to another, by section (the option tabs).
-- Only what every frame has: never its position, Enabled, the Blizzard frame
-- or the parts of one frame only (combo points, experience, party layout...).
-------------------------------------------------------------------------------
ns.COPY_SECTIONS = {
    { "frame", { "width", "height", "scale", "background", "border", "borderSize", "alpha",
        "portrait", "portraitStyle", "portraitWidth", "visibility", "visibilityCustom", "highlight" } },
    { "bars", { "health", "power" } },
    { "texts", { "texts" } },
    { "auras", { "auras" } },
    { "icons", { "icons" } },
    { "castbar", { "castbar" } },
    { "extras", { "fader", "threat", "threatBar", "combatText" } },
}

-- Settings a frame does not show in its options: never copied from or into it
local HIDDEN = {
    player = { fader = { range = true, phase = true, hostility = true }, threatBar = true },
    target = { highlight = { target = true } },
}

local PLACE = { anchor = true, point = true, relPoint = true, x = true, y = true }

local function Union(a, b)
    if a == true or b == true then return true end
    if not a then return b end
    if not b then return a end
    local u = {}
    for k, v in pairs(a) do u[k] = v end
    for k, v in pairs(b) do u[k] = Union(u[k], v) end
    return u
end

-- A copied piece placed on the screen would sit on top of the original:
-- it goes back to the frame
local function Unscreen(t)
    if type(t) ~= "table" then return t end
    if t.anchor == "screen" then t.anchor, t.x, t.y = nil, 0, 0 end
    for _, v in pairs(t) do Unscreen(v) end
    return t
end

-- src into dst, key by key. Lists are replaced whole; keys dst does not have
-- (parts of the other frame only) are skipped; a piece placed on the screen
-- (in either frame) keeps the place dst had.
local function Merge(dst, src, skip)
    local keepPlace = dst.anchor == "screen" or src.anchor == "screen"
    for k, v in pairs(src) do
        local s = skip and skip[k]
        if s == true or dst[k] == nil or (keepPlace and PLACE[k]) then
            -- left as it is
        elseif type(v) == "table" and type(dst[k]) == "table" and not LISTS[k] then
            Merge(dst[k], v, type(s) == "table" and s or nil)
        else
            dst[k] = Unscreen(DeepCopy(v))
        end
    end
end

-- sections: { frame = true, texts = true, ... }
function ns.CopyUnit(from, to, sections)
    local src, dst = ns.P.units[from], ns.P.units[to]
    if not src or not dst or from == to then return end
    local skip = Union(HIDDEN[from], HIDDEN[to]) or {}
    local pick, picked = {}, {}
    for _, sec in ipairs(ns.COPY_SECTIONS) do
        if sections[sec[1]] then
            for _, key in ipairs(sec[2]) do
                pick[key], picked[key] = src[key], dst[key]
            end
        end
    end
    Merge(picked, pick, skip)
    for k, v in pairs(picked) do dst[k] = v end
    Prepare()
    ns.ApplyUnit(to)
end

-------------------------------------------------------------------------------
-- Export / import: the profile as Lua text, read back without any access
-- to the game (empty environment)
-------------------------------------------------------------------------------
local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            out[#out + 1] = "["
            Serialize(k, out)
            out[#out + 1] = "]="
            Serialize(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = ("%q"):format(v):gsub("\n", "n")
    elseif t == "number" or t == "boolean" then
        out[#out + 1] = tostring(v)
    else
        out[#out + 1] = "nil"
    end
    return out
end

function ns.ExportProfile()
    return "SIGIL1:" .. table.concat(Serialize(ns.P, {}))
end

-- Returns true, or false and the reason
function ns.ImportProfile(text)
    local body = text and text:match("^%s*SIGIL1:(.+)$")
    if not body then return false, L["This is not a Sigil profile."] end
    local chunk = loadstring("return " .. body)
    if not chunk then return false, L["The text is damaged."] end
    setfenv(chunk, {})
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= "table" then return false, L["The text is damaged."] end
    wipe(ns.P)
    for k, v in pairs(data) do ns.P[k] = v end
    Prepare()
    ns.ResetGradient()
    ns.ApplyAll()
    return true
end

-------------------------------------------------------------------------------
-- Loading
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        SigilDB = SigilDB or {}
        ns.db = SigilDB
        ns.SetLanguage(ns.db.language or "enUS")
    elseif event == "PLAYER_LOGIN" then
        LoadProfile()
        ns.CreateFrames()
        ns.HideBlizzard()
    elseif event == "PLAYER_REGEN_ENABLED" then
        FlushPending()
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function Help()
    ns.Print(L["Commands:"])
    print("  /sigil - " .. L["open the options"])
    print("  /sigil move - " .. L["unlock the frames to move them (and show test data)"])
    print("  /sigil lock - " .. L["lock the frames"])
    print("  /sigil test - " .. L["show or hide the test frames"])
    print("  /sigil reset - " .. L["back to the default settings of this character"])
    print("  /sigil lang en|es - " .. L["language: en or es"])
end

SLASH_SIGIL1 = "/sigil"
SlashCmdList.SIGIL = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "move" or cmd == "mover" or cmd == "unlock" then
        ns.SetUnlocked(true)
    elseif cmd == "lock" or cmd == "bloquear" then
        ns.SetUnlocked(false)
    elseif cmd == "test" or cmd == "prueba" then
        ns.SetTestMode(not ns.testMode)
    elseif cmd == "reset" then
        ns.ResetProfile()
        ns.Print(L["Settings reset."])
    elseif cmd == "lang" or cmd == "idioma" then
        ns.db.language = (arg == "es") and "esES" or "enUS"
        ns.SetLanguage(ns.db.language)
        ns.Print(L["Language: English"] .. " " .. L["Type /reload to translate everything."])
    elseif cmd == "help" or cmd == "ayuda" then
        Help()
    else
        ns.ToggleOptions()
    end
end
