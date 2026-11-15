-- Draws the guide as a section at the top of Questie's tracker; Questie's quest list stays below, unchanged.
-- Questie has no section API: sections are drawn in a fixed order inside QuestieTracker:Update,
-- so Zuestie draws its lines right before QuestSection.Draw, with Questie's own LineBuilder.
-- Performance: Zuestie asks Questie for a layout only when the guide text changed, and the
-- section's header collapses like a zone header to hide the guide.
local _, Z = ...

local T = {}
Z.Tracker = T

local HEADER_KEY = "Zuestie" -- Questie.db.char.collapsedZones key

local QuestieTracker, LineBuilder, TrackerLayout
local tagged = {} -- [line] = OnClick script the pooled line had before Zuestie used it
local tooltipOwner
local lastShownError

local Strip = Z.Strip

-- Zygor's quest-name pink becomes Questie's quest-title gold; other name colors stay.
local ZYGOR_QUEST_COLOR = "|c[fF][fF][eE][eE][bB][bB][fF][fF]"
local QUEST_COLOR = "|cFFFFD100"

-- Goal lines start with an icon column, like the icons in front of Questie's quest titles.
-- Same pictures as Questie's map icons; the accept "!" is the guide's violet one.
local function Icon(path)
    return "|T" .. path .. ":0|t "
end
local BLANK = Icon(Z.ICON_PATH .. "blank.png") -- keeps text aligned on lines without an icon
local CHECK = Icon("Interface\\RaidFrame\\ReadyCheck-Ready")
local CROSS = Icon("Interface\\RaidFrame\\ReadyCheck-NotReady")
local ACTION_ICONS = {
    accept = Icon(Z.ICON_PATH .. "available_guide.png"),
    turnin = Icon(Questie.icons.complete),
    talk = Icon(Questie.icons.talk),
    kill = Icon(Questie.icons.slay),
    killboss = Icon(Questie.icons.slay),
    collect = Icon(Questie.icons.loot),
    get = Icon(Questie.icons.loot),
    buy = Icon(Questie.icons.loot),
    click = Icon(Questie.icons.interact),
    use = Icon(Questie.icons.object),
    ["goto"] = Icon(Questie.icons.route),
    home = Icon("Interface\\Icons\\INV_Misc_Rune_01"), -- hearthstone
    fpath = Icon("Interface\\Minimap\\Tracking\\FlightMaster"),
}

-- The progress bar is two flat textures inside the line's text: no extra frames to manage.
local BAR_WIDTH, BAR_HEIGHT = 120, 8
local BAR_EMPTY = 55 -- gray level of the unfilled part
local MODE_LABEL = {steps = "steps", quests = "quests", exp = "XP"}

local function BarPart(width, r, g, b)
    if width <= 0 then
        return ""
    end
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(BAR_HEIGHT, width, r, g, b)
end

local function ProgressText(line)
    local fill = math.floor(BAR_WIDTH * line.percent / 100 + 0.5)
    return BarPart(fill, line.r, line.g, line.b) .. BarPart(BAR_WIDTH - fill, BAR_EMPTY, BAR_EMPTY, BAR_EMPTY)
        .. ("  |cFFFFFFFF%d%%|r |cFF9D9D9D%s|r"):format(line.percent, MODE_LABEL[line.mode] or line.mode)
end

local function Format(line)
    local indent = ("  "):rep(line.indent or 0)
    if line.kind == "also" then
        return "|cFFC0C0C0" .. line.text .. ":|r"
    elseif line.kind == "progress" then
        return ProgressText(line)
    elseif line.kind == "tip" then
        -- Several |tip lines arrive joined by line breaks; one line keeps the section short.
        local tip = Strip(line.text):gsub("|n", "  "):gsub("\n", "  ")
        return ("  "):rep(math.max(0, (line.indent or 1) - 1)) .. BLANK .. "|cFF9D9D9D" .. tip .. "|r"
    end
    local status = line.status
    if status == "complete" then
        return indent .. CHECK .. "|cFF5FBF5F" .. Strip(line.text) .. "|r"
    elseif status == "impossible" or status == "obsolete" then
        return indent .. CROSS .. "|cFF808080" .. Strip(line.text) .. "|r"
    end
    indent = indent .. (ACTION_ICONS[line.goal and line.goal.action] or BLANK)
    if status == "warning" then
        return indent .. "|cFFFF9933" .. Strip(line.text) .. "|r"
    elseif status == "passive" then
        return indent .. "|cFFD8D8D8" .. line.text:gsub(ZYGOR_QUEST_COLOR, QUEST_COLOR) .. "|r"
    end
    return indent .. "|cFFFFFFFF" .. line.text:gsub(ZYGOR_QUEST_COLOR, QUEST_COLOR) .. "|r"
end

local function OnLineClick(self, button)
    local data = self.zuestie
    if not data then
        return
    end
    if data.kind == "progress" and button ~= "RightButton" then
        Z.CycleProgressMode()
        return
    end
    if data.kind == "title" and not ZGV.CurrentGuide then
        Z.Menu.OpenGuides()
        return
    end
    if button == "RightButton" or not data.goal then
        Z.Menu.Open()
        return
    end
    Z.Try(data.goal.OnClick, data.goal, button)
    Z.RefreshSoon()
end

local function Tag(line, data)
    if tagged[line] == nil then
        tagged[line] = line:GetScript("OnClick") or false
    end
    line.zuestie = data
    line:SetScript("OnClick", OnLineClick)
end

-- Back, choose-guide and next buttons in the empty space left of the step line, where Questie
-- puts the buttons in front of quest titles. Three frames made once, moved onto each layout's step line.
local SLOT_GAP = 2
local BUTTONS = {
    {key = "guides", tip = "Choose a guide", texture = "Interface\\Icons\\INV_Misc_Book_09", click = function() Z.Menu.OpenGuides() end},
    {key = "prev", tip = "Previous step", texture = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", paged = true, click = function() Z.PrevStep() end},
    {key = "next", tip = "Next step (skip)", texture = "Interface\\Buttons\\UI-SpellbookIcon-NextPage", paged = true, click = function() Z.SkipStep() end},
}
local SHOW_ORDER = {"guides", "next", "prev"} -- which buttons stay when the space is narrow
local buttons = {}

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.tip, 1, 0.82, 0)
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

local function GetButton(spec)
    local button = buttons[spec.key]
    if not button then
        button = CreateFrame("Button")
        button.tip = spec.tip
        if spec.paged then
            button:SetNormalTexture(spec.texture .. "-Up")
            button:SetPushedTexture(spec.texture .. "-Down")
            button:SetDisabledTexture(spec.texture .. "-Disabled")
        else
            button:SetNormalTexture(spec.texture)
        end
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", spec.click)
        button:SetScript("OnEnter", ButtonTooltip)
        button:SetScript("OnLeave", HideTooltip)
        buttons[spec.key] = button
    end
    return button
end

local function HideButtons()
    for _, button in pairs(buttons) do
        button:Hide()
    end
end

local function PlaceButtons(line, hasGuide)
    local margins = TrackerLayout.GetMargins()
    local size = margins.buttonSize
    local fits = math.floor((margins.quest - SLOT_GAP) / (size + SLOT_GAP))
    local shown = {}
    for _, key in ipairs(SHOW_ORDER) do
        if #shown < fits and (hasGuide or key == "guides") then
            shown[key] = true
            shown[#shown + 1] = key
        end
    end
    -- Right-aligned against the step text, in BUTTONS order.
    local right = margins.quest - SLOT_GAP
    for i = #BUTTONS, 1, -1 do
        local spec = BUTTONS[i]
        if shown[spec.key] then
            local button = GetButton(spec)
            button:SetParent(line)
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint("TOPRIGHT", line, "TOPLEFT", right, 1)
            button:Show()
            right = right - size - SLOT_GAP
        end
    end
end

local function DrawGuide()
    local m = Z.BuildModel()
    -- What the tracker shows now; Z.Refresh asks for a new layout only when this goes stale.
    Z.lastSig = Z.Signature(m)

    local header, collapsed = LineBuilder.AddHeader({key = HEADER_KEY, text = m.guideName})
    if not header or collapsed then
        return
    end

    -- One shared target: hovering any line highlights the whole guide section.
    local target = {zuestie = true}
    local line = LineBuilder.AddTitle({text = "|cFFFFD100" .. m.title .. "|r", colored = true, clickMode = "recipe", target = target})
    if not line then
        return
    end
    Tag(line, {kind = "title", text = m.title})
    Z.Try(PlaceButtons, line, m.guide ~= nil)

    local last = line
    for _, data in ipairs(m.lines) do
        line = LineBuilder.AddObjective({text = Format(data), clickMode = "recipe", target = target})
        if not line then
            break
        end
        Tag(line, data)
        last = line
    end
    LineBuilder.FinishEntry(last)
end

local function ShowTooltip(line)
    local data = line.zuestie
    local tip = GameTooltip
    tip:SetOwner(line, "ANCHOR_LEFT")
    if data.kind == "title" then
        tip:AddLine(ZGV.CurrentGuide and ZGV.CurrentGuide.title_short or "Zuestie", 1, 0.82, 0)
        tip:AddLine(data.text, 1, 1, 1)
        tip:AddLine(ZGV.CurrentGuide and "Click: guide menu" or "Click: choose a guide", 0.6, 0.6, 0.6)
    elseif data.kind == "progress" then
        tip:AddLine("Guide progress", 1, 0.82, 0)
        if data.tooltip then
            tip:AddLine(data.tooltip, 1, 1, 1)
        end
        tip:AddLine("Click: switch between quests, steps and XP", 0.6, 0.6, 0.6)
    elseif data.goal then
        local goal = data.goal
        tip:AddLine(Strip(data.text), 1, 1, 1, true)
        if data.kind == "goal" and goal.tooltip then
            tip:AddLine(goal.tooltip, 0.85, 0.85, 0.7, true)
        end
        local ok, extra = pcall(goal.GetTooltip, goal)
        if ok and type(extra) == "string" then
            tip:AddLine(extra, 0.85, 0.85, 0.7, true)
        end
        local goalType = ZGV.GOALTYPES and ZGV.GOALTYPES[goal.action]
        if goalType and goalType.click_to_complete then
            tip:AddLine("Click: confirm", 0.6, 0.6, 0.6)
        elseif goal.x then
            tip:AddLine("Click: point the arrow here", 0.6, 0.6, 0.6)
        end
        tip:AddLine("Right-click: guide menu", 0.6, 0.6, 0.6)
    else
        tip:AddLine("Right-click: guide menu", 0.6, 0.6, 0.6)
    end
    tip:Show()
    tooltipOwner = line
end

function T.Install()
    local QL = QuestieLoader
    QuestieTracker = QL:ImportModule("QuestieTracker")
    LineBuilder = QL:ImportModule("LineBuilder")
    TrackerLayout = QL:ImportModule("TrackerLayout")
    local QuestSection = QL:ImportModule("QuestSection")
    local TrackerUtils = QL:ImportModule("TrackerUtils")
    local TrackerLinePool = QL:ImportModule("TrackerLinePool")
    local TrackerQuestTooltip = QL:ImportModule("TrackerQuestTooltip")

    local drawQuests = QuestSection.Draw
    QuestSection.Draw = function(...)
        if Z.active then
            local ok, err = pcall(DrawGuide)
            if not ok then
                Z.lastError = err
                if err ~= lastShownError then
                    lastShownError = err
                    geterrorhandler()(err)
                end
            end
        end
        return drawQuests(...)
    end

    -- Questie hides its tracker when no quest is tracked; the guide section keeps it up.
    local hasQuest = TrackerUtils.HasQuest
    TrackerUtils.HasQuest = function(...)
        if Z.active then
            return true
        end
        return hasQuest(...)
    end

    -- Lines are pooled. Questie resets them before each layout; drop Zuestie's marks with them.
    hooksecurefunc(TrackerLinePool, "ResetLinesForChange", function()
        if InCombatLockdown() or not Questie.db.profile.trackerEnabled then
            return -- Questie skipped the reset too
        end
        for line, onClick in pairs(tagged) do
            line.zuestie = nil
            line:SetScript("OnClick", onClick or nil)
        end
        wipe(tagged)
        HideButtons()
    end)

    -- Questie's quest tooltip ignores lines without a quest; show the guide tooltip on those.
    hooksecurefunc(TrackerQuestTooltip, "Show", function(line)
        if line and line.zuestie and line:IsVisible() then
            Z.Try(ShowTooltip, line)
        end
    end)
    hooksecurefunc(TrackerQuestTooltip, "Hide", function(line)
        if tooltipOwner and (line == nil or line == tooltipOwner) then
            if GameTooltip:GetOwner() == tooltipOwner then
                GameTooltip:Hide()
            end
            tooltipOwner = nil
        end
    end)
end

-- Asks Questie for a new layout. Questie skips it in combat or before its tracker starts;
-- Z.lastSig then stays stale, so the next refresh asks again.
function T.Request()
    if QuestieTracker and QuestieTracker.started and not InCombatLockdown() then
        QuestieTracker:Update()
    end
end
