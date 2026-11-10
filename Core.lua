-------------------------------------------------------------------------------
-- Sigil - Core: saved variables, profile, secret value helpers, combat queue
-- and slash commands
-------------------------------------------------------------------------------

local ADDON, ns = ...
local L = ns.L

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
-- Profile (one per character): missing keys are filled from the defaults
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
    -- old versions kept one settings table per character in db.chars
    if db.chars then
        for char, settings in pairs(db.chars) do
            if not db.profiles[char] then db.profiles[char] = settings end
            db.profileOf[char] = db.profileOf[char] or char
        end
        db.chars = nil
    end
    local name = db.profileOf[ns.charKey] or ns.charKey
    if not db.profiles[name] then db.profiles[name] = {} end
    db.profileOf[ns.charKey] = name
    ns.profileName = name
    ns.P = db.profiles[name]
    Fill(ns.P, ns.DEFAULTS)
    ns.Migrate(ns.P)
    ns.ResetGradient()
end

-- Switches this character to another profile (created if it does not exist)
function ns.UseProfile(name)
    local db = ns.db
    if not db.profiles[name] then db.profiles[name] = {} end
    db.profileOf[ns.charKey] = name
    ns.profileName = name
    ns.P = db.profiles[name]
    Fill(ns.P, ns.DEFAULTS)
    ns.Migrate(ns.P)
    ns.ResetGradient()
    ns.ApplyAll()
end

-- Copies the settings of another profile into the current one
function ns.CopyProfile(from)
    local src = ns.db.profiles[from]
    if not src or from == ns.profileName then return end
    wipe(ns.P)
    for k, v in pairs(DeepCopy(src)) do ns.P[k] = v end
    Fill(ns.P, ns.DEFAULTS)
    ns.Migrate(ns.P)
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
    Fill(ns.P, ns.DEFAULTS)
    ns.Migrate(ns.P)
    ns.ResetGradient()
    ns.ApplyAll()
end

-- Settings of one unit back to the defaults
function ns.ResetUnit(unit)
    ns.P.units[unit] = DeepCopy(ns.DEFAULTS.units[unit])
    ns.ApplyUnit(unit)
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
    Fill(ns.P, ns.DEFAULTS)
    ns.Migrate(ns.P)
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
    print("  /sigil probe - " .. L["probe the game API and save the results"])
end

SLASH_SIGIL1 = "/sigil"
SlashCmdList.SIGIL = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd == "probe" or cmd == "sondeo" then
        ns.Probe()
    elseif cmd == "gcd" then
        if tonumber(arg) then ns.ProbeGCD(tonumber(arg)) else ns.ProbeNextGCD() end
    elseif cmd == "move" or cmd == "mover" or cmd == "unlock" then
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
