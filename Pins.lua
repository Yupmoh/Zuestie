-- Draws the step's waypoints as Questie world map and minimap pins.
-- Zygor stores Blizzard map IDs with 0-1 coordinates; Questie pins take
-- zone (area) IDs with 0-100 coordinates.
local _, Z = ...

local P = {}
Z.Pins = P

local PIN_TYPE = "Zuestie" -- QuestieMap.manualFrames bucket, kept apart from Questie's own notes
-- Questie's yellow "!" recolored violet: quests the current guide picks up from here on.
local GUIDE_QUEST_ICON = Z.ICON_PATH .. "available_guide.png"

local QuestieMap, QuestieLib
local guideQuests = {} -- [questId] = true
local guideKey -- guide title and step the set was built for

local ICONS = {
    accept = "available",
    turnin = "complete",
    talk = "talk",
    kill = "slay",
    killboss = "slay",
    collect = "loot",
    get = "loot",
    click = "interact",
    use = "object",
}

local drawn = false

function P.Clear()
    if not drawn then
        return
    end
    drawn = false
    Z.Try(QuestieMap.ResetManualFrames, QuestieMap, PIN_TYPE)
end

-- Returns true when the pins are drawn, false to retry on the next refresh.
function P.Draw(pins)
    if not Questie.API.isReady then
        return false
    end
    local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    P.Clear()

    local step = ZGV.CurrentStepNum or 0
    for i, pin in ipairs(pins) do
        -- GetAreaIdByUiMapId raises an error for maps Questie does not know (instances, some floors).
        local ok, areaId = pcall(ZoneDB.GetAreaIdByUiMapId, ZoneDB, pin.map)
        if ok and areaId then
            local marker = pin.action == "mapmarker"
            local iconKey = marker and "node" or ICONS[pin.action] or "fav"
            local scale = (Questie.db.profile.manualScale or 0.7) * (marker and 0.6 or 1)
            local title = pin.text and pin.text ~= "" and Z.Strip(pin.text) or "Guide waypoint"
            local data = {
                id = i,
                Name = title,
                Icon = Questie.icons[iconKey],
                Type = "manual",
                IsObjectiveNote = false,
                GetIconScale = function() return scale end,
                ManualTooltipData = {
                    Title = title,
                    Body = {{"Zuestie: ", "step " .. step}},
                    disableShiftToRemove = true,
                },
            }
            data.IconScale = scale
            Z.Try(QuestieMap.DrawManualIcon, QuestieMap, data, areaId, pin.x * 100, pin.y * 100, PIN_TYPE)
            drawn = true
        end
    end
    return true
end

-- Only normal (yellow) starters change; gray, event, PvP and repeatable keep Questie's colors.
local function IsYellow(data)
    if data.QuestData then
        local ok, icon = pcall(QuestieLib.GetQuestIcon, data.QuestData)
        if ok then
            return icon == Questie.ICON_TYPE_AVAILABLE
        end
    end
    return data.Icon == Questie.ICON_TYPE_AVAILABLE
end

local function Tint(frame, on)
    local data = frame and frame.data
    if data and data.Type == "available" and frame.texture and IsYellow(data) then
        frame.texture:SetTexture(on and GUIDE_QUEST_ICON or Questie.usedIcons[Questie.ICON_TYPE_AVAILABLE])
    end
end

local function TintQuest(questId, on)
    for _, frame in pairs(QuestieMap:GetFramesForQuest(questId)) do
        Tint(frame, on)
    end
end

-- Rebuilds the guide quest set when the guide or step changed, and recolors only the quests that
-- entered or left it. force recolors the whole set, e.g. after a level-up retextured Questie's icons.
function P.UpdateGuideQuests(force)
    local guide = Z.active and ZGV.CurrentGuide
    local stepNum = ZGV.CurrentStepNum or 1
    local key = guide and guide.steps and (guide.title .. "#" .. stepNum) or ""
    if key == guideKey and not force then
        return
    end
    guideKey = key

    local new = {}
    if key ~= "" then
        for i = stepNum, #guide.steps do
            local goals = guide.steps[i].goals
            if goals then
                for _, goal in ipairs(goals) do
                    local questId = goal.action == "accept" and tonumber(goal.questid)
                    if questId then
                        new[questId] = true
                    end
                end
            end
        end
    end
    for questId in pairs(guideQuests) do
        if not new[questId] then
            TintQuest(questId, false)
        end
    end
    for questId in pairs(new) do
        if force or not guideQuests[questId] then
            TintQuest(questId, true)
        end
    end
    guideQuests = new
end

function P.Install()
    QuestieMap = QuestieLoader:ImportModule("QuestieMap")
    QuestieLib = QuestieLoader:ImportModule("QuestieLib")
    -- Questie draws every quest starter here; guide quests get the violet "!" as they are drawn.
    local drawWorldIcon = QuestieMap.DrawWorldIcon
    QuestieMap.DrawWorldIcon = function(self, data, ...)
        local iconMap, iconMinimap = drawWorldIcon(self, data, ...)
        if iconMap and data and guideQuests[data.Id] then
            Tint(iconMap, true)
            Tint(iconMinimap, true)
        end
        return iconMap, iconMinimap
    end
end
