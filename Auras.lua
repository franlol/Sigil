-------------------------------------------------------------------------------
-- Sigil - Auras
--
-- Forever does not let addons read auras in combat, so they are drawn by the
-- game's native aura container (CustomAuraContainerTemplate): the game picks
-- the auras and fills icon, time, stacks, border color and tooltip. Sigil
-- sets up what to show (filters) and the look.
--
-- Each frame has a list of aura groups (like "My debuffs", "Buffs"). Every
-- group is its own block of icons with its own filters, size and position.
--
-- What the game allows to filter:
--   · type (buffs / debuffs), caster (mine / others), dispel type,
--     dispellable by me, boss auras, stealable, maximum duration, order
--   · spell lists ("only these" / "all except these"): for buffs on you,
--     your group and pets, and for debuffs on enemies. Not for debuffs on
--     friendly units nor buffs on enemies (the game ignores the list there).
-------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L

local FLAT = "Interface\\Buttons\\WHITE8X8"
local DISPEL_KINDS = { "Magic", "Curse", "Disease", "Poison" }
ns.DISPEL_KINDS = DISPEL_KINDS

-- Masque (optional): skins the aura icons
local masque = LibStub and LibStub("Masque", true)
local masqueGroup = masque and masque:Group("Sigil", "Auras")

-------------------------------------------------------------------------------
-- What the game shows: filter string, extra filters and order
-------------------------------------------------------------------------------
local function Query(g)
    local harmful = g.kind == "HARMFUL"
    local filter = harmful and "HARMFUL" or "HELPFUL"
    if g.caster == "mine" then filter = filter .. "|PLAYER" end
    if harmful and g.dispellable then filter = filter .. "|RAID" end

    local cand = {}
    if g.caster == "others" then cand.isFromPlayerOrPlayerPet = false end
    if g.boss then cand.isBossAura = true end
    if not harmful and g.stealable then cand.isStealable = true end
    if g.maxDuration and g.maxDuration > 0 then cand.maxDuration = g.maxDuration end
    if harmful and g.types then
        local inc, any, all = {}, false, true
        for _, kind in ipairs(DISPEL_KINDS) do
            if g.types[kind] then inc[kind] = true any = true else all = false end
        end
        if any and not all then cand.includeDispelTypes = inc end
    end
    if g.listMode == "only" or g.listMode == "hide" then
        local set = ns.SpellSet(g.spells)
        if g.listMode == "only" then cand.includeSpellIDs = set
        elseif next(set) then cand.excludeSpellIDs = set end
    end

    local sm = AuraContainerSortMethod
    local sort
    if sm then
        if g.sort == "time" then sort = sm.Expiration
        elseif g.sort == "name" then sort = sm.Name
        elseif harmful then sort = sm.UnitFrameDebuff
        else sort = sm.Default end
    end
    return filter, next(cand) and cand or nil, sort
end
ns.AuraQuery = Query

-------------------------------------------------------------------------------
-- Aura button: icon, border, sweep, time and stacks
-------------------------------------------------------------------------------
local function BuildButton(button, g, cancel)
    local size = g.size
    button:SetSize(size, size)
    local harmful = g.kind == "HARMFUL"

    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture(FLAT)
    border:SetVertexColor(0, 0, 0, 1)
    if harmful and g.borderByType ~= false then
        -- the game colors it by debuff type, with the colors of the Colors page
        local map = { None = CreateColor(0.8, 0, 0, 1) }
        for _, kind in ipairs(DISPEL_KINDS) do
            local c = ns.Color("dispel", kind)
            map[kind] = CreateColor(c.r, c.g, c.b, 1)
        end
        button:AddDispelTypeTexture(border, {
            showAlways = true,
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            customDispelColorMap = map,
        })
    elseif harmful then
        -- nothing: plain black border
    else
        -- enemy buffs that can be stolen or purged: highlighted border
        local steal = button:CreateTexture(nil, "BORDER")
        steal:SetPoint("TOPLEFT", -1, 1)
        steal:SetPoint("BOTTOMRIGHT", 1, -1)
        steal:SetTexture(FLAT)
        button:AddDispelTypeTexture(steal, {
            showWhenHelpful = true,
            stealableFilter = Enum.CustomAuraButtonDispelTypeStealableFilter.Stealable,
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
        })
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    local cd
    if g.spiral ~= false then
        cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        cd:SetHideCountdownNumbers(true)
        button:SetDurationCooldown(cd)
    end

    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints()
    top:SetFrameLevel((cd or button):GetFrameLevel() + 2)

    -- glow when it is time to renew the aura (the game knows the window)
    if g.pandemic and button.AddPandemicRegion then
        local glow = CreateFrame("Frame", nil, button, "BackdropTemplate")
        glow:SetPoint("TOPLEFT", -2, 2)
        glow:SetPoint("BOTTOMRIGHT", 2, -2)
        glow:SetFrameLevel(top:GetFrameLevel() + 1)
        glow:SetBackdrop({ edgeFile = FLAT, edgeSize = 2 })
        local c = ns.Color("highlight", "target")
        glow:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        glow:Hide()
        pcall(button.AddPandemicRegion, button, glow)
    end

    if g.timer then
        local fs = top:CreateFontString(nil, "OVERLAY")
        ns.StyleText(fs, { size = g.timerSize or 0 }, math.max(8, math.floor(size * 0.42)))
        fs:SetPoint("CENTER", 0, 0)
        button:SetDurationText(fs, {})
    end

    local count = top:CreateFontString(nil, "OVERLAY")
    ns.StyleText(count, { size = g.stackSize or 0 }, math.max(8, math.floor(size * 0.45)))
    count:SetPoint("BOTTOMRIGHT", 2, -1)
    button:SetApplicationCount(count, {})

    button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT")
    if g.tooltip == false then button:EnableMouse(false) end
    if cancel then button:SetCancelAuraButtons("RightButtonUp") end

    if masqueGroup then
        pcall(masqueGroup.AddButton, masqueGroup, button, { Icon = icon, Cooldown = cd, Count = count, Border = border })
    end
end

local function NewContainer(f, g)
    local c = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
    c:SetPoint(g.point, f, g.relPoint, g.x, g.y)
    c:SetFlowLayoutAnchorPoint(g.point)
    c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    local fd = AnchorUtil.FlowDirection
    c:SetFlowLayoutGrowthDirection(g.growX == "LEFT" and fd.Left or fd.Right, g.growY == "UP" and fd.Up or fd.Down)
    c:SetFlowLayoutMaximumLineSize(g.perRow * (g.size + g.spacing))
    local filter, cand, sort = Query(g)
    local cancel = g.kind ~= "HARMFUL" and f.unit == "player"
    c:AddAuraGroup("auras", filter, {
        maxFrameCount = g.max,
        candidateFilters = cand,
        sortMethod = sort,
        layout = {
            elementSpacing = g.spacing, lineSpacing = g.spacing,
            elementWidth = g.size, elementHeight = g.size,
        },
        initializeFrame = function(button) BuildButton(button, g, cancel) end,
    })
    return c
end

-------------------------------------------------------------------------------
-- Sample icons (test mode, unit that does not exist)
-------------------------------------------------------------------------------
local function Samples(f, i, g)
    f.auraSamples = f.auraSamples or {}
    local s = f.auraSamples[i]
    if not s then
        s = CreateFrame("Frame", nil, f)
        s:SetSize(1, 1)
        s.icons = {}
        f.auraSamples[i] = s
    end
    s:ClearAllPoints()
    s:SetPoint(g.point, f, g.relPoint, g.x, g.y)
    local n = math.min(g.max, g.perRow, g.kind == "HARMFUL" and 3 or 5)
    local sx = g.growX == "LEFT" and -1 or 1
    local step = g.size + g.spacing
    for k = 1, math.max(n, #s.icons) do
        local t = s.icons[k]
        if k <= n then
            if not t then
                t = s:CreateTexture(nil, "ARTWORK")
                t.border = s:CreateTexture(nil, "BACKGROUND")
                t.border:SetPoint("TOPLEFT", t, -1, 1)
                t.border:SetPoint("BOTTOMRIGHT", t, 1, -1)
                s.icons[k] = t
            end
            t:SetSize(g.size, g.size)
            t:ClearAllPoints()
            t:SetPoint(g.point, s, g.point, (k - 1) * step * sx, 0)
            t:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if g.kind == "HARMFUL" then t.border:SetColorTexture(0.8, 0, 0, 1) else t.border:SetColorTexture(0, 0, 0, 1) end
            t:Show()
            t.border:Show()
        elseif t then
            t:Hide()
            t.border:Hide()
        end
    end
    s:Show()
end

local function HideSamples(f)
    for _, s in pairs(f.auraSamples or {}) do s:Hide() end
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------
local function Sig(v, out)
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = k .. "="
            Sig(v[k] == nil and v[tonumber(k)] or v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = tostring(v)
    end
    return out
end

local function Groups(f)
    local a = f.cfg.auras
    if not a or not a.enabled then return {} end
    return a.groups or {}
end

-- Out of combat (from ns.Layout): containers cannot be created in combat.
-- A group whose settings did not change keeps its container.
function ns.LayoutAuras(f)
    f.auraBlocks = f.auraBlocks or {}
    local groups = Groups(f)
    local used = {}
    for i, g in ipairs(groups) do
        if g.show then
            local filter, cand, sort = Query(g)
            local key = table.concat(Sig({ g, filter, cand or false, sort or false, ns.Font(), ns.Outline(),
                ns.P.colors.dispel, ns.P.colors.highlight.target }, {}))
            local block = f.auraBlocks[i]
            if not block or block.key ~= key then
                if block and block.container then
                    block.container:SetUnit("none")
                    block.container:Hide()
                end
                local ok, result = pcall(NewContainer, f, g)
                if ok then
                    block = { key = key, container = result }
                else
                    block = { key = key }
                    if not ns.auraWarned then
                        ns.auraWarned = true
                        ns.Print(L["Could not create the auras: %s"]:format(tostring(result)))
                    end
                end
                f.auraBlocks[i] = block
            end
            used[i] = true
        end
    end
    for i, block in pairs(f.auraBlocks) do
        if not used[i] then
            if block.container then
                block.container:SetUnit("none")
                block.container:Hide()
            end
            f.auraBlocks[i] = nil
        end
    end
end

-- The containers follow the frame's unit. They are set again on every
-- update so they read the new unit after a target change.
function ns.UpdateAuras(f)
    local groups = Groups(f)
    if ns.Fake(f.unit) then
        HideSamples(f)
        for i, g in ipairs(groups) do
            local block = f.auraBlocks and f.auraBlocks[i]
            if block and block.container then
                block.container:SetUnit("none")
                block.container:Hide()
            end
            if g.show then Samples(f, i, g) end
        end
        return
    end
    HideSamples(f)
    for _, block in pairs(f.auraBlocks or {}) do
        if block.container then
            block.container:SetUnit("none")
            block.container:SetUnit(f.unit)
            block.container:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Group templates (Add group in the options) and defaults
-------------------------------------------------------------------------------
local Group = ns.NewAuraGroup   -- Defaults.lua

ns.AURA_TEMPLATES = {
    { "buffs", "All buffs", function() return Group("Buffs", "HELPFUL") end },
    { "debuffs", "All debuffs", function() return Group("Debuffs", "HARMFUL") end },
    { "mydebuffs", "My debuffs", function() return Group("My debuffs", "HARMFUL", { caster = "mine", size = 26, pandemic = true }) end },
    { "otherdebuffs", "Debuffs from others", function() return Group("Debuffs from others", "HARMFUL", { caster = "others", size = 18 }) end },
    { "mybuffs", "My buffs", function() return Group("My buffs", "HELPFUL", { caster = "mine" }) end },
    { "dispel", "Debuffs I can dispel", function() return Group("Dispellable", "HARMFUL", { dispellable = true }) end },
    { "boss", "Boss debuffs", function() return Group("Boss debuffs", "HARMFUL", { boss = true, size = 28 }) end },
    { "steal", "Buffs I can purge or steal", function() return Group("Purgeable", "HELPFUL", { stealable = true }) end },
    { "short", "Short buffs (under 1 min)", function() return Group("Short buffs", "HELPFUL", { maxDuration = 60 }) end },
}
