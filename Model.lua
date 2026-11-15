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
        tinsert(m.lines, line)
        local pin = m.pins[#m.pins]
        if pin and pin.goal == goal then
            pin.text = text
        end
    end
    if HasText(goal.tooltip) and (text == "?" or profile.tooltipsbelow) then
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
    if ZGV.db.profile.progress == false or type(bar) ~= "table" or type(bar.CurrentProgress) ~= "number" then
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
    return m
end

function Z.Signature(m)
    local parts = {m.guideName, m.title}
    for _, line in ipairs(m.lines) do
        parts[#parts + 1] = line.kind .. ":" .. (line.status or "") .. ":" .. line.text
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
