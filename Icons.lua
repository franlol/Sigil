-------------------------------------------------------------------------------
-- Sigil - Status icons
--   combat, resting, leader, assistant, master looter, role, raid target,
--   PvP, ready check, incoming resurrection, summon, phase, quest boss,
--   pet happiness
--
-- Each icon is centered on a point of the frame (its corner, edge...) plus
-- an offset. Test mode shows all the enabled ones. Textures are the game's
-- own UI textures.
-------------------------------------------------------------------------------

local _, ns = ...
local R = ns.R
local L = ns.L

local STATE = "Interface\\CharacterFrame\\UI-StateIcon"

-- A texture file or an atlas name (the game's globals can be either,
-- depending on the client: READY_CHECK_*_TEXTURE are atlases in the modern UI)
local function IsAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetTex(tex, path, l, r, t, b)
    if IsAtlas(path) then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(path)
        return
    end
    tex:SetTexture(path)
    if l then tex:SetTexCoord(l, r, t, b) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- Pet happiness: 1 unhappy, 2 content, 3 happy (nil = no data).
-- C_PetInfo.GetPetHappiness (Forever) or GetPetHappiness, else the happiness power (only if the
-- client names one: power type 4 is combo points in the modern UI).
local HAPPINESS_POWER = Enum and Enum.PowerType and Enum.PowerType.Happiness
local function PetHappiness(u)
    if u ~= "pet" or not R(UnitExists(u)) then return nil end
    local get = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
    if get then
        local h = R(get())
        if type(h) == "number" and h >= 1 and h <= 3 then return h end
    end
    if not HAPPINESS_POWER then return nil end
    local cur, max = R(UnitPower(u, HAPPINESS_POWER)), R(UnitPowerMax(u, HAPPINESS_POWER))
    if not (cur and max and max > 0) then return nil end
    local pct = cur / max
    return pct < 1 / 3 and 1 or pct < 2 / 3 and 2 or 3
end

-- Ready check: it stays a few seconds after it ends
local readyUntil = 0

-- key -> active(unit) and apply(tex, unit, test)
local ICONS = {
    combat = {
        active = function(u)
            if u == "player" then return ns.InCombat() end
            return R(UnitAffectingCombat(u)) and true or false
        end,
        apply = function(tex) SetTex(tex, STATE, 0.5, 1, 0, 0.49) end,
    },
    resting = {
        active = function(u) return u == "player" and IsResting() or false end,
        apply = function(tex) SetTex(tex, STATE, 0, 0.5, 0, 0.421875) end,
    },
    leader = {
        active = function(u) return R(UnitIsGroupLeader(u)) and true or false end,
        apply = function(tex) SetTex(tex, "Interface\\GroupFrame\\UI-Group-LeaderIcon") end,
    },
    assistant = {
        active = function(u)
            return IsInRaid() and R(UnitIsGroupAssistant(u)) and not R(UnitIsGroupLeader(u)) and true or false
        end,
        apply = function(tex) SetTex(tex, "Interface\\GroupFrame\\UI-Group-AssistantIcon") end,
    },
    masterLooter = {
        active = function(u)
            if not GetLootMethod then return false end
            local method, partyIndex, raidIndex = GetLootMethod()
            if method ~= "master" then return false end
            local who
            if raidIndex then who = "raid" .. raidIndex
            elseif partyIndex == 0 then who = "player"
            elseif partyIndex then who = "party" .. partyIndex end
            return who ~= nil and R(UnitIsUnit(u, who)) and true or false
        end,
        apply = function(tex) SetTex(tex, "Interface\\GroupFrame\\UI-Group-MasterLooter") end,
    },
    role = {
        active = function(u)
            if not UnitGroupRolesAssigned then return false end
            local role = R(UnitGroupRolesAssigned(u))
            return role == "TANK" or role == "HEALER" or role == "DAMAGER"
        end,
        apply = function(tex, u, test)
            local role = test and "HEALER" or R(UnitGroupRolesAssigned(u))
            if GetTexCoordsForRoleSmallCircle and role then
                SetTex(tex, "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", GetTexCoordsForRoleSmallCircle(role))
            end
        end,
    },
    raidTarget = {
        active = function(u) return R(GetRaidTargetIndex(u)) ~= nil end,
        apply = function(tex, u, test)
            local index = test and 8 or R(GetRaidTargetIndex(u))
            tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            if index and SetRaidTargetIconTexture then SetRaidTargetIconTexture(tex, index) end
        end,
    },
    pvp = {
        active = function(u) return ns.IsPvP(u) end,
        apply = function(tex, u, test)
            local faction = test and UnitFactionGroup("player") or R(UnitFactionGroup(u))
            if (not test and ns.IsPvPFreeForAll(u)) or (faction ~= "Horde" and faction ~= "Alliance") then faction = "FFA" end
            SetTex(tex, "Interface\\TargetingFrame\\UI-PVP-" .. faction, 0, 0.65, 0, 0.65)
        end,
    },
    readyCheck = {
        active = function(u)
            if GetTime() > readyUntil then return false end
            return R(GetReadyCheckStatus(u)) ~= nil
        end,
        apply = function(tex, u, test)
            local status = test and "ready" or R(GetReadyCheckStatus(u))
            if status == "ready" then SetTex(tex, READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready")
            elseif status == "notready" then SetTex(tex, READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady")
            else SetTex(tex, READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting") end
        end,
    },
    resurrect = {
        active = function(u) return R(UnitHasIncomingResurrection(u)) and true or false end,
        apply = function(tex) SetTex(tex, "Interface\\RaidFrame\\Raid-Icon-Rez") end,
    },
    summon = {
        active = function(u)
            if not (C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus) then return false end
            local s = R(C_IncomingSummon.IncomingSummonStatus(u))
            return s ~= nil and s ~= 0
        end,
        apply = function(tex, u, test)
            local s = test and 1 or R(C_IncomingSummon.IncomingSummonStatus(u))
            local atlas = s == 2 and "Raid-Icon-SummonAccepted" or s == 3 and "Raid-Icon-SummonDeclined"
                or "Raid-Icon-SummonPending"
            SetTex(tex, atlas)
        end,
    },
    phase = {
        active = function(u) return UnitPhaseReason and R(UnitPhaseReason(u)) ~= nil or false end,
        apply = function(tex) SetTex(tex, "Interface\\TargetingFrame\\UI-PhasingIcon", 0.15625, 0.84375, 0.15625, 0.84375) end,
    },
    questBoss = {
        active = function(u) return R(UnitIsQuestBoss(u)) and true or false end,
        apply = function(tex) SetTex(tex, "Interface\\TargetingFrame\\PortraitQuestBadge") end,
    },
    happiness = {
        active = function(u) return PetHappiness(u) ~= nil end,
        apply = function(tex, u, test)
            local h = test and 3 or PetHappiness(u) or 3
            -- happy, content, unhappy faces side by side
            local l = (3 - h) * 0.1875
            SetTex(tex, "Interface\\PetPaperDollFrame\\UI-PetHappiness", l, l + 0.1875, 0, 0.359375)
        end,
        -- Same lines as Blizzard's pet frame: mood, damage and loyalty
        tooltip = function(u)
            local get = (C_PetInfo and C_PetInfo.GetPetHappiness) or GetPetHappiness
            local _, damage, loyalty
            if get then _, damage, loyalty = get() end
            damage, loyalty = R(damage), R(loyalty)
            local h = PetHappiness(u) or 3
            GameTooltip:SetText(_G["PET_HAPPINESS" .. h] or "")
            if type(damage) == "number" and PET_DAMAGE_PERCENTAGE then
                GameTooltip:AddLine(format(PET_DAMAGE_PERCENTAGE, damage), 1, 1, 1)
            end
            if type(loyalty) == "number" then
                if loyalty < 0 and LOSING_LOYALTY then GameTooltip:AddLine(LOSING_LOYALTY, 1, 0.1, 0.1)
                elseif loyalty > 0 and GAINING_LOYALTY then GameTooltip:AddLine(GAINING_LOYALTY, 0.1, 1, 0.1) end
            end
        end,
    },
}

-- Hover area for the icons that have a tooltip (clicks go through to the frame)
local function TooltipHit(f, key, tex)
    local hit = CreateFrame("Frame", nil, f.overlay)
    hit:SetAllPoints(tex)
    hit:SetFrameLevel(f.overlay:GetFrameLevel() + 5)
    hit:EnableMouse(true)
    if hit.SetMouseClickEnabled then hit:SetMouseClickEnabled(false) end
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(ICONS[key].tooltip, f.unit)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hit:Hide()
    return hit
end

ns.ICON_KEYS = {
    "combat", "resting", "leader", "assistant", "masterLooter", "role", "raidTarget",
    "pvp", "readyCheck", "resurrect", "summon", "phase", "questBoss", "happiness",
}

ns.ICON_NAMES = {
    combat = "In combat", resting = "Resting", leader = "Group leader", assistant = "Raid assistant",
    masterLooter = "Master looter", role = "Role", raidTarget = "Raid target", pvp = "PvP",
    readyCheck = "Ready check", resurrect = "Being resurrected", summon = "Summon", phase = "Other phase",
    questBoss = "Quest boss", happiness = "Pet happiness",
}

-- Icons that only some frames can show: key -> { frames, label }.
-- The rest can show on any frame.
ns.ICON_ONLY = {
    resting = { { player = true }, "Player" },
    happiness = { { pet = true }, "Pet" },
    questBoss = { { target = true, targettarget = true, targettargettarget = true, focus = true }, "NPCs" },
}

-------------------------------------------------------------------------------
-- PvP countdown: on the PvP icon of the player frame, while the flag wears off
-- (as Blizzard's player frame: the time read on each update, counted down here)
-------------------------------------------------------------------------------
local TEST_TIME_LEFT = 272

local function PaintTimer(fs)
    local left = fs.endsAt and fs.endsAt - GetTime()
    if not left or left <= 0 then
        fs:SetText("")
        fs.ticker:Hide()
        return
    end
    fs:SetText(ns.FormatTime(fs.rules, left))
end

local function LayoutPvPTimer(f, tex, cfg)
    local fs = tex.timer
    if not fs then
        fs = f.overlay:CreateFontString(nil, "OVERLAY")
        fs:SetDrawLayer("OVERLAY", 3)
        local ticker = CreateFrame("Frame", nil, f.overlay)
        ticker:Hide()
        local wait = 0
        ticker:SetScript("OnUpdate", function(_, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = 0.1
            PaintTimer(fs)
        end)
        fs.ticker = ticker
        tex.timer = fs
    end
    fs:Hide()
    fs.ticker:Hide()
    fs.on = (f.unit == "player" and cfg and cfg.show and cfg.timer) and true or false
    if not cfg then return end
    fs.rules = ns.TimeRules(cfg.timeFmt)
    ns.StyleText(fs, cfg.timerStyle, math.max(8, math.floor((cfg.size or 26) * 0.4)))
    local tp = cfg.timerPos or {}
    fs:ClearAllPoints()
    fs:SetPoint(tp.point or "CENTER", tex, tp.relPoint or tp.point or "CENTER", tp.x or 0, tp.y or 0)
end

local function UpdatePvPTimer(tex)
    local fs = tex and tex.timer
    if not fs then return end
    local left
    if fs.on and tex:IsShown() then
        left = ns.testMode and TEST_TIME_LEFT or ns.PvPTimeLeft()
    end
    if left then
        fs.endsAt = GetTime() + left
        fs:Show()
        PaintTimer(fs)
        fs.ticker:SetShown(not ns.testMode)
    else
        fs.endsAt = nil
        fs:Hide()
        fs.ticker:Hide()
    end
end

function ns.LayoutIcons(f)
    f.icons = f.icons or {}
    for _, key in ipairs(ns.ICON_KEYS) do
        local cfg = f.cfg.icons and f.cfg.icons[key]
        local tex = f.icons[key]
        if not tex then
            tex = f.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
            f.icons[key] = tex
            if ICONS[key].tooltip then tex.hit = TooltipHit(f, key, tex) end
        end
        tex:Hide()
        if tex.hit then tex.hit:Hide() end
        if cfg and cfg.show then
            -- a piece like any other: it can be dragged while unlocked
            ns.PlacePiece(f, "icon:" .. key, L[ns.ICON_NAMES[key]], tex, cfg)
            tex:SetSize(cfg.size, cfg.size)
            tex:SetAlpha(cfg.alpha or 1)
        end
        if key == "pvp" then LayoutPvPTimer(f, tex, cfg) end
    end
end

function ns.UpdateIcons(f)
    if not f.icons then return end
    local u = f.unit
    local test = ns.testMode and true or false
    for _, key in ipairs(ns.ICON_KEYS) do
        local cfg = f.cfg.icons and f.cfg.icons[key]
        local tex = f.icons[key]
        if cfg and cfg.show then
            local def = ICONS[key]
            local ok, on = pcall(def.active, u)
            on = test or (ok and on)
            if on then pcall(def.apply, tex, u, test) end
            tex:SetShown(on and true or false)
        else
            tex:Hide()
        end
        if tex.hit then tex.hit:SetShown(tex:IsShown()) end
    end
    UpdatePvPTimer(f.icons.pvp)
end

-- Events (registered by every frame through ns.On)
for _, ev in ipairs({
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
    "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PARTY_LOOT_METHOD_CHANGED",
    "PLAYER_ROLES_ASSIGNED", "READY_CHECK_CONFIRM", "INCOMING_RESURRECT_CHANGED",
    "INCOMING_SUMMON_CHANGED", "UNIT_PHASE", "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_FLAGS", "UNIT_FACTION", "UNIT_HAPPINESS", "PET_UI_UPDATE", "PLAYER_FLAGS_CHANGED",
}) do
    ns.On(ev, function(f) ns.UpdateIcons(f) end)
end

ns.On("READY_CHECK", function(f)
    readyUntil = math.huge
    ns.UpdateIcons(f)
end)
ns.On("READY_CHECK_FINISHED", function(f)
    readyUntil = GetTime() + 6
    ns.UpdateIcons(f)
    C_Timer.After(6.1, function() ns.UpdateIcons(f) end)
end)

-- Happiness can also come as a power update: only the pet frame cares
ns.On("UNIT_POWER_UPDATE", function(f, _, powerType)
    if f.unit == "pet" and (powerType == nil or powerType == "HAPPINESS") then ns.UpdateIcons(f) end
end)
