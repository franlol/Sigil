-------------------------------------------------------------------------------
-- Sigil - Spell names and IDs for the aura lists
--
-- A list entry is a spell ID (number) or a name ("n:Name"). A name stands
-- for every rank of the spell: its IDs are asked to the client once, by
-- walking its spells in the background (a few thousand per frame), and kept
-- until the client version changes.
-------------------------------------------------------------------------------

local _, ns = ...

ns.GetSpellName = (C_Spell and C_Spell.GetSpellName) or function(id)
    return (GetSpellInfo and GetSpellInfo(id)) or nil
end

ns.GetSpellIcon = (C_Spell and C_Spell.GetSpellTexture) or function(id)
    return GetSpellTexture and GetSpellTexture(id)
end

local SCAN_MAX, SCAN_STEP = 1500000, 5000
local pending = {}   -- [lowercase name] = { left = IDs still to check, ids = {} }
local scanID = 1
local scanner = CreateFrame("Frame")
scanner:Hide()

local function ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

local function Index()
    local idx = ns.db.spellIndex
    if type(idx) ~= "table" or idx.build ~= ClientBuild() then
        idx = { build = ClientBuild(), names = {} }
        ns.db.spellIndex = idx
    end
    return idx
end

scanner:SetScript("OnUpdate", function(self)
    local last = math.min(SCAN_MAX, scanID + SCAN_STEP - 1)
    for id = scanID, last do
        local name = ns.GetSpellName(id)
        if name then
            local p = pending[name:lower()]
            if p then p.ids[#p.ids + 1] = id end
        end
    end
    local step = last - scanID + 1
    scanID = last + 1
    if scanID > SCAN_MAX then scanID = 1 end

    local names, finished = Index().names, false
    for lower, p in pairs(pending) do
        p.left = p.left - step
        if p.left <= 0 then
            table.sort(p.ids)
            names[lower] = (#p.ids > 0) and p.ids or false
            pending[lower] = nil
            finished = true
        end
    end
    if finished then
        -- the auras that use those names are built again
        if ns.ApplyAll then ns.ApplyAll() end
        if ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
    end
    if not next(pending) then self:Hide() end
end)

-- Every ID of a name, or nil while they are being looked up
function ns.SpellIDs(name)
    if not name or name == "" or not ns.db then return nil end
    local lower = name:lower()
    local v = Index().names[lower]
    if v == nil then
        if not pending[lower] then
            pending[lower] = { left = SCAN_MAX, ids = {} }
            scanner:Show()
        end
        return nil
    end
    return v or nil
end

function ns.IsSpellLookupPending(name)
    return name and pending[name:lower()] ~= nil
end

-- Text typed by the user -> list entry (number or "n:Name"), or nil
function ns.SpellKeyFromInput(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local id = tonumber(text)
    if id then return ns.GetSpellName(id) and id or nil end
    -- the client's name (right capitals) when it knows it
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(text)
    if info and info.name then return "n:" .. info.name end
    return "n:" .. text
end

function ns.SpellKeyName(key)
    if type(key) == "number" then return ns.GetSpellName(key) or tostring(key) end
    return (type(key) == "string" and key:match("^n:(.+)$")) or tostring(key)
end

function ns.SpellKeyIcon(key)
    local id = type(key) == "number" and key
    if not id then
        local name = ns.SpellKeyName(key)
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(name)
        id = info and info.spellID
        if not id then
            local ids = ns.SpellIDs(name)
            id = ids and ids[1]
        end
    end
    return id and ns.GetSpellIcon(id) or 134400
end

-- { [id] = true } for every entry of a list
function ns.SpellSet(list)
    local set = {}
    for _, key in ipairs(list or {}) do
        if type(key) == "number" then
            set[key] = true
        else
            for _, id in ipairs(ns.SpellIDs(ns.SpellKeyName(key)) or {}) do set[id] = true end
        end
    end
    return set
end
