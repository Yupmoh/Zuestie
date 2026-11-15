-- Draws the step's waypoints as Questie world map and minimap pins.
-- Zygor stores Blizzard map IDs with 0-1 coordinates; Questie pins take
-- zone (area) IDs with 0-100 coordinates.
local _, Z = ...

local P = {}
Z.Pins = P

local PIN_TYPE = "Zuestie" -- QuestieMap.manualFrames bucket, kept apart from Questie's own notes
-- Questie's yellow "!" recolored violet: quests the loaded guide and the next guides pick up.
local GUIDE_QUEST_ICON = Z.ICON_PATH .. "available_guide.png"

local QuestieMap, QuestieLib
local guideQuests = {} -- [questId] = true
local guideKey -- title of the guide the set was built for
local chainNames = {} -- short titles of the next guides whose quests are in the set
local NEXT_GUIDES = 3 -- after Duskwood & Redridge: Wetlands, Ashenvale, Duskwood & Stranglethorn Vale

-- Step pin pictures; the accept "!" is the guide's violet one, like the tracker line and the
-- recolored Questie quest starters (a quest that unlocks later in the step has only this pin).
local ICONS = {
    accept = GUIDE_QUEST_ICON,
    turnin = Questie.icons.complete,
    talk = Questie.icons.talk,
    kill = Questie.icons.slay,
    killboss = Questie.icons.slay,
    collect = Questie.icons.loot,
    get = Questie.icons.loot,
    click = Questie.icons.interact,
    use = Questie.icons.object,
    mapmarker = Questie.icons.node,
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
            local scale = (Questie.db.profile.manualScale or 0.7) * (marker and 0.6 or 1)
            local title = pin.text and pin.text ~= "" and Z.Strip(pin.text) or "Guide waypoint"
            local data = {
                id = i,
                Name = title,
                Icon = ICONS[pin.action] or Questie.icons.fav,
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
        frame.zuestieTinted = on
    end
end

local function TintQuest(questId, on)
    for _, frame in pairs(QuestieMap:GetFramesForQuest(questId)) do
        Tint(frame, on)
    end
end

-- Next guides are not parsed until loaded, so their accepts come from the raw guide text
-- ("accept Quest Name##66 |goto ...").
local function AddRawAccepts(guide, set)
    local raw = guide.rawdata
    if type(raw) ~= "string" then
        return
    end
    for questId in raw:gmatch("\n%s*accept [^\n]-##(%d+)") do
        set[tonumber(questId)] = true
    end
end

local function NextGuide(guide)
    local title = guide.next or (guide.headerdata and guide.headerdata.next)
    return type(title) == "string" and ZGV:GetGuideByTitle(title) or nil
end

-- Every quest the loaded guide accepts at any step (skipped ones stay marked), plus the quests of
-- the next NEXT_GUIDES guides in Zygor's chain, so upcoming quests stand out from ones the guides skip.
-- Rebuilt only when the guide changes; recolors only the quests that entered or left the set.
-- force recolors the whole set, e.g. after a level-up retextured Questie's icons.
function P.UpdateGuideQuests(force)
    local guide = Z.active and ZGV.CurrentGuide
    local key = guide and guide.steps and guide.title or ""
    if key == guideKey and not force then
        return
    end
    guideKey = key

    local new = {}
    chainNames = {}
    if key ~= "" then
        for _, step in ipairs(guide.steps) do
            local goals = step.goals
            if goals then
                for _, goal in ipairs(goals) do
                    local questId = goal.action == "accept" and tonumber(goal.questid)
                    if questId then
                        new[questId] = true
                    end
                end
            end
        end
        local seen = {[guide] = true}
        local nextGuide = guide
        for _ = 1, NEXT_GUIDES do
            nextGuide = NextGuide(nextGuide)
            if not nextGuide or seen[nextGuide] then
                break
            end
            seen[nextGuide] = true
            chainNames[#chainNames + 1] = nextGuide.title_short or nextGuide.title
            AddRawAccepts(nextGuide, new)
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

-- /zu quests: which quest starters Questie has drawn, which belong to the guides, which are violet.
function P.Report()
    local total = 0
    for _ in pairs(guideQuests) do
        total = total + 1
    end
    local drawn, inGuide, violet, shown = 0, 0, 0, 0
    for questId in pairs(QuestieMap.questIdFrames) do
        local quest, tinted, available
        for _, frame in pairs(QuestieMap:GetFramesForQuest(questId)) do
            if frame.data and frame.data.Type == "available" and not frame.miniMapIcon then
                available = true
                quest = frame.data.QuestData
                tinted = tinted or frame.zuestieTinted
            end
        end
        if available then
            drawn = drawn + 1
            if guideQuests[questId] then
                inGuide = inGuide + 1
                if tinted then
                    violet = violet + 1
                end
                if shown < 8 then
                    shown = shown + 1
                    local color = tinted and "violet" or (IsYellow({QuestData = quest}) and "yellow (should be violet)" or "not yellow, kept")
                    Z.Print(("  %d %s: %s"):format(questId, quest and quest.name or "?", color))
                end
            end
        end
    end
    local guides = ZGV.CurrentGuide and ZGV.CurrentGuide.title_short or "(none)"
    if #chainNames > 0 then
        guides = guides .. " + next: " .. table.concat(chainNames, ", ")
    end
    Z.Print(("guides %s pick up %d quests. Questie shows %d quest starters; %d are in these guides, %d violet."):format(
        guides, total, drawn, inGuide, violet))
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
