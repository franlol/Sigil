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
-- GetPetHappiness if the client has it, else the happiness power (type 4).
local HAPPINESS_POWER = Enum and Enum.PowerType and Enum.PowerType.Happiness or 4
local function PetHappiness(u)
    if u ~= "pet" or not R(UnitExists(u)) then return nil end
    if GetPetHappiness then
        local h = R(GetPetHappiness())
        if h then return h end
    end
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
            if u == "player" then return InCombatLockdown() end
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
        active = function(u) return R(UnitIsPVP(u)) and true or false end,
        apply = function(tex, u, test)
            local faction = test and UnitFactionGroup("player") or R(UnitFactionGroup(u))
            if faction ~= "Horde" and faction ~= "Alliance" then faction = "FFA" end
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
    },
}

ns.ICON_KEYS = {
    "combat", "resting", "leader", "assistant", "masterLooter", "role", "raidTarget",
    "pvp", "readyCheck", "resurrect", "summon", "phase", "questBoss", "happiness",
}

function ns.LayoutIcons(f)
    f.icons = f.icons or {}
    for _, key in ipairs(ns.ICON_KEYS) do
        local cfg = f.cfg.icons and f.cfg.icons[key]
        local tex = f.icons[key]
        if not tex then
            tex = f.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
            f.icons[key] = tex
        end
        tex:Hide()
        if cfg and cfg.show then
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", f, cfg.point, cfg.x or 0, cfg.y or 0)
            tex:SetSize(cfg.size, cfg.size)
        end
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
    end
end

-- Events (registered by every frame through ns.On)
for _, ev in ipairs({
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
    "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "RAID_TARGET_UPDATE", "PARTY_LOOT_METHOD_CHANGED",
    "PLAYER_ROLES_ASSIGNED", "READY_CHECK_CONFIRM", "INCOMING_RESURRECT_CHANGED",
    "INCOMING_SUMMON_CHANGED", "UNIT_PHASE", "UNIT_CLASSIFICATION_CHANGED",
    "UNIT_FLAGS", "UNIT_FACTION", "UNIT_HAPPINESS", "PET_UI_UPDATE",
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
