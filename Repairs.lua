-- Fixes for Zygor bugs on WoW Forever. Each one wraps a Zygor function from outside; Zygor's files stay as
-- they are. Installed once Zygor has started (Core.lua), whether Zuestie is on or off: the bugs hit Zygor's
-- own window too.
local _, Z = ...

local R = {}
Z.Repairs = R

-- Skills --------------------------------------------------------------------------------------
-- Zygor for Forever reads skill levels only from GetProfessions, which leaves out skill lines such as
-- Lockpicking and Riding: their goals stay at 0 ("Reach Level 75 in Lockpicking (0/75)") and never complete.
-- For a skill Zygor does not know, Zuestie reads the skill line from C_SkillInfo instead.
local SKILL_LINE_IDS = {Lockpicking = 633} -- skill lines missing from Zygor's own list
local skillLines = {} -- [name] = skill table handed to Zygor, refreshed on every read

local function TitleCase(first, rest)
    return first:upper() .. rest:lower()
end

local function SkillLine(name)
    name = name:gsub("_", " "):gsub("(%a)([%w]*)", TitleCase) -- as Zygor's GetSkill names skills
    local id = SKILL_LINE_IDS[name] or ZGV.Professions.tradeskillsIdByName[name]
    if not id then
        return nil
    end
    local ok, info = pcall(C_SkillInfo.GetSkillLineInfoByID, id)
    if not (ok and type(info) == "table" and type(info.rank) == "number" and info.rank > 0) then
        return nil
    end
    local skill = skillLines[name]
    if not skill then
        skill = {active = true, skillID = id, name = name}
        skillLines[name] = skill
    end
    skill.level, skill.max = info.rank, info.maxRank or info.rank
    return skill
end

local function RepairSkills()
    local professions = ZGV.Professions
    if not (C_SkillInfo and type(C_SkillInfo.GetSkillLineInfoByID) == "function" and type(professions) == "table"
        and type(professions.GetSkill) == "function" and type(professions.tradeskillsIdByName) == "table") then
        return
    end
    local getSkill = professions.GetSkill
    professions.GetSkill = function(self, name)
        local skill = getSkill(self, name)
        -- Zygor answers a skill it does not know with its shared placeholder (level 0).
        if type(skill) == "table" and skill.placeholder and type(name) == "string" then
            return SkillLine(name) or skill
        end
        return skill
    end
end

-- Party sync ----------------------------------------------------------------------------------
-- Zygor's group sync names party members name .. " " .. surname (UnitNameUnmodified, in Sync.lua's
-- getunitname). A member the client has not loaded yet is "Unknown" with no surname, and Zygor errors
-- ("attempt to concatenate local 'surname'") on party changes. Zygor's sync code now runs only once every
-- party name is loaded; a party change that comes too early is retried each second.
local PARTY_EVENTS = {"GROUP_ROSTER_UPDATE", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE", "PLAYER_ENTERING_WORLD"}
local PARTY_RETRY_SECONDS = 1
local PARTY_RETRIES = 30

local function PartyNamesLoaded()
    for i = 1, GetNumGroupMembers() - 1 do
        local name, surname = UnitNameUnmodified("party" .. i)
        if surname == nil and not ZGV.IsSecret(name) then
            return false
        end
    end
    return true
end

local function RepairPartySync()
    local sync = ZGV.Sync
    if not (ZGV.IsForever and type(UnitNameUnmodified) == "function" and type(ZGV.IsSecret) == "function"
        and type(sync) == "table" and type(sync.OnEvent) == "function" and type(ZGV.Events_Events) == "table") then
        return
    end

    local onEvent = sync.OnEvent
    local retries, waiting = 0, false
    local function Run(addon, event, ...)
        if PartyNamesLoaded() then
            return onEvent(addon, event, ...)
        end
        if waiting or retries >= PARTY_RETRIES then
            return
        end
        waiting, retries = true, retries + 1
        C_Timer.After(PARTY_RETRY_SECONDS, function()
            waiting = false
            Run(addon, "GROUP_ROSTER_UPDATE") -- Zygor handles all four party events the same way
        end)
    end
    local function OnEvent(addon, event, ...)
        retries = 0
        return Run(addon, event, ...)
    end
    -- Zygor keeps its event handlers in lists (ZGV:AddEventHandler); swap Sync's in place.
    for _, event in ipairs(PARTY_EVENTS) do
        local handlers = rawget(ZGV.Events_Events, event)
        for i, handler in ipairs(handlers or {}) do
            if handler == onEvent then
                handlers[i] = OnEvent
            end
        end
    end
    sync.OnEvent = OnEvent

    -- The same name lookup in Zygor's party status checks and its step window's party marks.
    local isComplete = sync.IsPartyStatusComplete
    if type(isComplete) == "function" then
        sync.IsPartyStatusComplete = function(...)
            return PartyNamesLoaded() and isComplete(...)
        end
    end
    local statusText = sync.GetStepGoalPartyStatusText
    if type(statusText) == "function" then
        sync.GetStepGoalPartyStatusText = function(...)
            if PartyNamesLoaded() then
                return statusText(...)
            end
        end
    end
end

-- Quests the game no longer offers -----------------------------------------------------------
-- Some quests disappear once another one is turned in: They Call Him Smiling Jim (1282) is gone after
-- James Hyal (1302), the other way into the same chain. Zygor does not know this, so its guide waits at
-- Guard Byron for a quest he no longer has. Questie does (availableUntilCompleted, exclusiveTo). Every
-- Zygor check of "is this quest done" goes through ZGV.completedQuests, so a quest Questie says can no
-- longer be taken now counts as done there too: its accept and turn-in steps move on.
local blockers = {} -- [questId] = quests whose turn-in takes this one away (false: none)

local function Blockers(q)
    local known = blockers[q]
    if known ~= nil then
        return known
    end
    if not Z.Catchup.QuestieReady() then
        return false -- asked again once Questie has loaded
    end
    local field = Z.Catchup.QuestieField
    local list = {}
    local untilDone = field(q, "availableUntilCompleted")
    if type(untilDone) == "number" and untilDone > 0 then
        list[#list + 1] = untilDone
    end
    local exclusive = field(q, "exclusiveTo")
    if type(exclusive) == "table" then
        for _, other in ipairs(exclusive) do
            list[#list + 1] = other
        end
    end
    known = #list > 0 and list or false
    blockers[q] = known
    return known
end

local function RepairUnavailableQuests()
    local quests = ZGV.completedQuests
    local meta = type(quests) == "table" and getmetatable(quests)
    local turnedIn = meta and meta.__index
    if type(turnedIn) ~= "function" then
        return
    end
    meta.__index = function(t, id)
        if turnedIn(t, id) then
            return true
        end
        local q = tonumber(id)
        local list = q and Blockers(q)
        if not list then
            return false
        end
        local quest = ZGV.questsbyid and ZGV.questsbyid[q]
        if quest and quest.inlog then
            return false
        end
        for _, other in ipairs(list) do
            if rawget(t, other) or turnedIn(t, other) then
                return true
            end
        end
        return false
    end
end

function R.Install()
    Z.Try(RepairSkills)
    Z.Try(RepairPartySync)
    Z.Try(RepairUnavailableQuests)
end
