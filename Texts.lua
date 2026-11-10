-------------------------------------------------------------------------------
-- Sigil - Lua texts
--
-- Each text is compiled once with loadstring and runs with its own
-- environment: the helpers below first, then the game's globals.
-- Forever hides some values (health, power...) as secret: they can be
-- shown (SetText, format, ..) but not compared or used in math. The helpers
-- return them as they come, so the user code only has to show them.
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local S, R = ns.S, ns.R

-------------------------------------------------------------------------------
-- Test data (test mode). Player, target, target of target and pet are at
-- 80 % health and power, so the empty part (bar background) can be seen and tuned.
-------------------------------------------------------------------------------
local FAKE = {
    player = {
        level = 20, classification = "normal", player = true,
        hp = 800, maxhp = 1000, power = 800, maxpower = 1000, powerToken = "MANA", reaction = 5,
    },
    target = {
        name = "Test target", level = 21, classification = "elite", class = "Humanoid",
        hp = 3600, maxhp = 4500, power = 1200, maxpower = 1500, powerToken = "MANA", reaction = 2,
    },
    targettarget = {
        name = "Test unit", level = 20, classification = "normal", class = "Warrior", classToken = "WARRIOR",
        hp = 800, maxhp = 1000, power = 80, maxpower = 100, powerToken = "RAGE", reaction = 5, player = true,
    },
    focus = {
        name = "Test focus", level = 22, classification = "rare", class = "Undead",
        hp = 2600, maxhp = 3800, power = 900, maxpower = 900, powerToken = "MANA", reaction = 2,
    },
    pet = {
        name = "Test pet", level = 20, classification = "normal", class = "Beast",
        hp = 560, maxhp = 700, power = 80, maxpower = 100, powerToken = "FOCUS", reaction = 5,
    },
    party1 = {
        name = "Party member", level = 20, classification = "normal", class = "Priest", classToken = "PRIEST",
        hp = 540, maxhp = 600, power = 700, maxpower = 900, powerToken = "MANA", reaction = 5, player = true,
    },
    party2 = {
        name = "Party member", level = 21, classification = "normal", class = "Warrior", classToken = "WARRIOR",
        hp = 950, maxhp = 1300, power = 30, maxpower = 100, powerToken = "RAGE", reaction = 5, player = true,
    },
    party3 = {
        name = "Party member", level = 19, classification = "normal", class = "Rogue", classToken = "ROGUE",
        hp = 300, maxhp = 700, power = 80, maxpower = 100, powerToken = "ENERGY", reaction = 5, player = true,
    },
    party4 = {
        name = "Party member", level = 20, classification = "normal", class = "Mage", classToken = "MAGE",
        hp = 520, maxhp = 560, power = 400, maxpower = 1000, powerToken = "MANA", reaction = 5, player = true,
    },
}

-- Test data of a frame in test mode (every frame, even when the unit exists)
function ns.Fake(unit)
    if not ns.testMode then return nil end
    local f = FAKE[unit]
    -- your own name, class and level on your frame
    if unit == "player" and f and not f.name then
        f.name = UnitName("player")
        f.class = (UnitClass("player"))
        f.classToken = select(2, UnitClass("player"))
        f.level = UnitLevel("player")
    end
    return f
end

-------------------------------------------------------------------------------
-- Helpers available to the texts
-------------------------------------------------------------------------------
local H = {}
ns.textHelpers = H

local CLASSIFICATION = { elite = "+", rare = "R", rareelite = "R+", worldboss = "B" }

function H.Name(u)
    local f = ns.Fake(u)
    if f then return L[f.name] end
    return (UnitName(u))
end

-- Name with surname (Forever characters have one)
function H.FullName(u)
    local f = ns.Fake(u)
    if f then return L[f.name] end
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local ok, n = pcall(NameUtil.FormatUnitNameForDisplay, u)
        if ok and n then return n end
    end
    return (UnitName(u))
end

function H.Level(u)
    local f = ns.Fake(u)
    local l = f and f.level or UnitEffectiveLevel(u)
    if S(l) then return l end
    if not l or l <= 0 then return "??" end
    return l
end

function H.Classification(u)
    local f = ns.Fake(u)
    local c = f and f.classification or R(UnitClassification(u))
    return c and CLASSIFICATION[c] or ""
end

-- Class for players, creature type for the rest
function H.Class(u)
    local f = ns.Fake(u)
    if f then return L[f.class] end
    if R(UnitIsPlayer(u)) then return (UnitClass(u)) or "" end
    return UnitCreatureType(u) or ""
end

function H.ClassColor(u)
    local f = ns.Fake(u)
    local token = f and f.classToken or R(select(2, UnitClass(u)))
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Color of the level by difficulty compared with the player
function H.DifficultyColor(u)
    local f = ns.Fake(u)
    local l = f and f.level or UnitEffectiveLevel(u)
    if S(l) or not l or l <= 0 then return 1, 0.1, 0.1 end
    local fn = GetCreatureDifficultyColor or GetQuestDifficultyColor
    if fn then
        local c = fn(l)
        if c then return c.r, c.g, c.b end
    end
    return 1, 0.82, 0
end

function H.HP(u)
    local f = ns.Fake(u)
    if f then return f.hp end
    return UnitHealth(u)
end

function H.MaxHP(u)
    local f = ns.Fake(u)
    if f then return f.maxhp end
    return UnitHealthMax(u)
end

-- Missing health
function H.Missing(u)
    local f = ns.Fake(u)
    if f then return f.maxhp - f.hp end
    if UnitHealthMissing then return UnitHealthMissing(u) end
    return 0
end

-- Health percentage 0-100 (computed by the game, works with secret values)
function H.HPPercent(u)
    local f = ns.Fake(u)
    if f then return math.floor(f.hp / f.maxhp * 100) end
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        return UnitHealthPercent(u, false, CurveConstants.ScaleTo100)
    end
    return 0
end

function H.Power(u)
    local f = ns.Fake(u)
    if f then return f.power end
    return UnitPower(u)
end

function H.MaxPower(u)
    local f = ns.Fake(u)
    if f then return f.maxpower end
    return UnitPowerMax(u)
end

-- Short number: 12.3K, 1.2M (works with secret values)
function H.Short(n)
    if AbbreviateNumbers then return AbbreviateNumbers(n) end
    return tostring(n)
end

-- Dead, Ghost, Offline, AFK or nil
function H.Status(u)
    if ns.Fake(u) then return nil end
    if R(UnitIsConnected(u)) == false then return L["Offline"] end
    if R(UnitIsGhost(u)) then return L["Ghost"] end
    if R(UnitIsDead(u)) then return L["Dead"] end
    if R(UnitIsAFK(u)) then return L["AFK"] end
    return nil
end

-- A part of a frame by name: the bars, the portrait or any placed piece
-- (castbar, combo, xp, gcd, altMana, threatBar, totems, combatText, aura1...)
local PARTS = { health = "health", power = "power", portrait = "portrait" }
local function Part(f, part)
    if PARTS[part] then return f[PARTS[part]] end
    local e = f.pieces and f.pieces[part]
    return e and e.region
end

local Over = ns.MouseOver

-- Mouse over this frame (Hover()) or over one of its parts (Hover("power")).
-- Texts that use it are refreshed whenever the mouse moves between parts.
local current -- the frame whose text is running now (set by ns.RunText)
function H.Hover(part)
    local f = current
    if not f then return false end
    if part == nil or part == "frame" then return f.hover and true or false end
    return Over(Part(f, part))
end

-- Which parts the mouse is over now, as one string (changes = refresh)
function ns.HoverState(f)
    local s = f.hover and "f" or ""
    for key in pairs(PARTS) do
        if Over(Part(f, key)) then s = s .. "|" .. key end
    end
    for key, e in pairs(f.pieces or {}) do
        if Over(e.region) then s = s .. "|" .. key end
    end
    return s
end

-- Text in a color: Colorize("hello", 1, 0, 0)
function H.Colorize(text, r, g, b)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) .. text .. "|r"
end

-------------------------------------------------------------------------------
-- Compile and run
-------------------------------------------------------------------------------
local HELPERS_ENV = setmetatable({}, {
    __index = function(_, k)
        local v = H[k]
        if v ~= nil then return v end
        return _G[k]
    end,
})

-- Returns the function to run, or nil and the error
function ns.CompileText(code)
    local chunk, err = loadstring(code or "", "Sigil text")
    if not chunk then return nil, err end
    -- own environment: variables of one text do not leak to the others
    setfenv(chunk, setmetatable({}, { __index = HELPERS_ENV }))
    return chunk
end

local function Show(fs, first, ...)
    if select("#", ...) > 0 then
        fs:SetFormattedText(first, ...)
    else
        fs:SetText(first or "")
    end
end

local function Run(t)
    Show(t.fs, t.fn())
end

-- Runs a compiled text once for the first frame of a settings key, to find
-- errors that only show when it runs (a missing unit, a nil value...).
-- Returns true, or false and the error.
function ns.TryText(key, fn)
    local f = ns.frames[ns.UnitsOf(key)[1] or key]
    if not f then return true end
    getfenv(fn).unit = f.unit
    current = f
    local ok, err = pcall(fn)
    return ok, err
end

-- t: { fs, fn, cfg, err }
function ns.RunText(f, t)
    if not t.fn then return end
    getfenv(t.fn).unit = f.unit
    current = f
    local ok, err = pcall(Run, t)
    if not ok then
        t.fs:SetText("|cffff3333" .. L["error"] .. "|r")
        if t.err ~= err then
            t.err = err
            ns.Print(L["Error in a text of %s: %s"]:format(f.unit, tostring(err)))
        end
    end
end
