-- Reads Zygor's current step into a plain model: tracker lines and map pins.
-- The goal filtering mirrors Zygor's own step display (Skins/Default/ViewerFrame.lua).
local _, Z = ...

local tinsert, concat = table.insert, table.concat

-- True when the text shows something besides color codes and spaces.
local function HasText(text)
    return text ~= nil and text ~= "?" and Z.Strip(text):match("%S") ~= nil
end

-- A few Zygor guide lines name the quest but not its objective ("|q 245" instead of "|q 245/1"),
-- so Zygor shows no count ("Kill 15 ..." forever) and cannot complete the goal from quest progress.
-- Once the quest is in the log, fill in the objective whose text names the goal's target, or the
-- quest's only objective of that kind. Zygor then counts and completes the goal itself.
local OBJECTIVE_TYPE = {kill = "monster", get = "item", goal = false}

-- Goal actions that use an item; their lines get a clickable item button.
local USE_ACTIONS = {use = true, useany = true}

local function BindObjective(goal)
    local wanted = OBJECTIVE_TYPE[goal.action]
    if goal.objnum or not goal.questid or wanted == nil or goal.zuestieBound then
        return
    end
    local quest = ZGV.questsbyid and ZGV.questsbyid[goal.questid]
    if not (quest and quest.inlog) then
        return -- try again once the quest is accepted
    end
    local target = type(goal.target) == "string" and goal.target ~= "" and goal.target:lower()
    local byName, byType, typeCount, total = nil, nil, 0, 0
    for i = 1, 20 do
        local text, objectiveType = GetQuestObjectiveInfo(goal.questid, i, false)
        if not text then
            break
        end
        total = total + 1
        if target and not byName and text:lower():find(target, 1, true) then
            byName = i
        end
        if wanted and objectiveType == wanted then
            typeCount = typeCount + 1
            byType = i
        end
    end
    if total == 0 then
        return -- objectives not loaded yet
    end
    goal.zuestieBound = true
    goal.objnum = byName or (typeCount == 1 and byType) or nil
end

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

function Z.RepairSkills()
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

local function AddGoal(m, step, goal, ctx)
    local profile = ZGV.db.profile
    BindObjective(goal)
    local status = goal:GetStatus()

    if goal.action == "mapmarker" then
        -- Hidden marker dots, e.g. where the mobs of a kill step are.
        if goal.x and goal.y and goal.map and (not goal.condition_visible or goal.condition_visible()) then
            tinsert(m.pins, {map = goal.map, x = goal.x, y = goal.y, action = "mapmarker", text = goal.waytitle or goal.text})
        end
        return
    end
    if status == "hidden" then
        return
    end

    if goal.x and goal.y and goal.map and status ~= "complete" then
        tinsert(m.pins, {map = goal.map, x = goal.x, y = goal.y, action = goal.action, text = nil, goal = goal})
    end

    if ctx.canHideTravel and goal:IsInlineTravel() then
        return
    end
    if profile.collapsecompleted and goal:CanBeIndentHidden() and not step:IsComplete() then
        return
    end

    local text = goal:GetText(true)
    local indent = goal.indent or 0
    if HasText(text) then
        if ctx.sticky and not ctx.shownAlso then
            ctx.shownAlso = true
            tinsert(m.lines, {kind = "also", text = "Also"})
        end
        local line = {kind = "goal", goal = goal, status = status, text = text, indent = indent}
        if USE_ACTIONS[goal.action] and status ~= "complete" and Z.Setting("itemButtons") then
            line.itemid = tonumber(goal.itemid or goal.defaultitem)
        end
        tinsert(m.lines, line)
        local pin = m.pins[#m.pins]
        if pin and pin.goal == goal then
            pin.text = text
        end
    end
    if HasText(goal.tooltip) and (text == "?" or profile.tooltipsbelow) and Z.Setting("showTips") then
        tinsert(m.lines, {kind = "tip", goal = goal, text = goal.tooltip, indent = indent + 1})
    end
end

local function AddStep(m, step, sticky)
    local profile = ZGV.db.profile
    local goals = step.goals or {}
    local ctx = {sticky = sticky, canHideTravel = false}
    if not profile.showinlinetravel or sticky then
        for _, goal in ipairs(goals) do
            if not goal:IsInlineTravel() then
                ctx.canHideTravel = true
                break
            end
        end
    end
    for _, goal in ipairs(goals) do
        -- One broken goal must not hide the rest of the step.
        Z.Try(AddGoal, m, step, goal, ctx)
    end
end

-- Zygor's own progress bar already computes guide progress (steps, quests or XP) when the step or
-- XP changes; its window is parked, not gone. Zuestie reads the stored values instead of recounting.
local function AddProgress(m)
    local bar = ZGV.ProgressBar
    if not Z.Setting("showProgress") or ZGV.db.profile.progress == false
        or type(bar) ~= "table" or type(bar.CurrentProgress) ~= "number" then
        return
    end
    local percent = math.max(0, math.min(100, math.floor(bar.CurrentProgress + 0.5)))
    local r, g, b = 0, 0.8, 0
    if bar.Texture and bar.Texture.GetVertexColor then
        r, g, b = bar.Texture:GetVertexColor()
    end
    r, g, b = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
    local mode = ZGV.db.profile.progressbarmode or "steps"
    tinsert(m.lines, {
        kind = "progress",
        text = ("%d %s %d,%d,%d"):format(percent, mode, r, g, b), -- what the signature compares
        percent = percent,
        mode = mode,
        r = r, g = g, b = b,
        tooltip = bar.Text and bar.Text.tooltip,
    })
end

-- Replaces Zygor's next-guide popups: a line that loads the next guide in Zygor's order. Shown on
-- the guide's last step, or earlier once Zygor suggests the next guide (the player outleveled this one).
local function AddNextGuide(m, guide)
    local title = guide.next or (guide.headerdata and guide.headerdata.next)
    local nextGuide = type(title) == "string" and ZGV:GetGuideByTitle(title)
    if not nextGuide then
        return
    end
    local onLastStep = (ZGV.CurrentStepNum or 0) >= #guide.steps
    local suggested = false
    if not onLastStep then
        local ok, status = pcall(nextGuide.GetStatus, nextGuide)
        suggested = ok and status == "SUGGESTED"
    end
    if onLastStep or suggested then
        tinsert(m.lines, {
            kind = "nextguide",
            text = (onLastStep and "Next guide: " or "Ready for: ") .. (nextGuide.title_short or nextGuide.title),
            guide = nextGuide,
        })
    end
end

function Z.BuildModel()
    local guide, step = ZGV.CurrentGuide, ZGV.CurrentStep
    local m = {lines = {}, pins = {}}
    if not (guide and step and guide.steps) then
        m.guideName = "Guide"
        m.title = "No guide loaded, click to choose one"
        return m
    end

    m.guide = guide
    -- "Duskwood & Redridge Mountains (25-27)": the name heads the section like a zone name, and the
    -- levels lead the step line like Questie's "(22) Quest Name" titles.
    local name = guide.title_short or guide.title
    local short, levels = name:match("^(.-)%s*%((%d+%-%d+)%)$")
    m.guideName = short or name
    m.title = (levels and "(" .. levels .. ") " or "") .. ("Step %d/%d"):format(ZGV.CurrentStepNum or step.num or 0, #guide.steps)
    AddProgress(m)
    local ok, catchup = Z.Try(Z.Catchup.Line)
    if ok and catchup then
        tinsert(m.lines, catchup)
    end
    AddStep(m, step, false)

    local profile = ZGV.db.profile
    if profile.stickyon and (profile.stickydisplay == 3 or profile.stickydisplay == 4) then
        local ok, stickies = Z.Try(ZGV.GetStickiesAt, ZGV)
        if ok and stickies then
            -- Zygor reuses this table on its next call, so copy it first.
            local copy = {}
            for i, sticky in ipairs(stickies) do
                copy[i] = sticky
            end
            for _, sticky in ipairs(copy) do
                AddStep(m, sticky, true)
            end
        end
    end
    Z.Try(AddNextGuide, m, guide)
    return m
end

function Z.Signature(m)
    local parts = {m.guideName, m.title}
    for _, line in ipairs(m.lines) do
        parts[#parts + 1] = line.kind .. ":" .. (line.status or "") .. ":" .. (line.itemid or "") .. ":" .. line.text
    end
    return concat(parts, "\001")
end

function Z.PinSignature(m)
    local parts = {}
    for _, pin in ipairs(m.pins) do
        parts[#parts + 1] = ("%s:%s:%.4f:%.4f:%s"):format(pin.action or "", pin.map, pin.x, pin.y, pin.text or "")
    end
    return concat(parts, "\001")
end
