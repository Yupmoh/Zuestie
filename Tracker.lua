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
local GUIDE_COLOR = "|cFFB98CFF" -- the violet of the guide's "!"

-- Goal lines start with an icon column, like the icons in front of Questie's quest titles.
-- Same pictures as Questie's map icons; the accept "!" is the guide's violet one.
local function Icon(path)
    return "|T" .. path .. ":0|t "
end
local GUIDE_ICON = Icon(Z.ICON_PATH .. "available_guide.png")
local BLANK = Icon(Z.ICON_PATH .. "blank.png") -- keeps text aligned on lines without an icon
local CHECK = Icon("Interface\\RaidFrame\\ReadyCheck-Ready")
local CROSS = Icon("Interface\\RaidFrame\\ReadyCheck-NotReady")
local ACTION_ICONS = {
    accept = GUIDE_ICON,
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
    elseif line.kind == "nextguide" or line.kind == "catchup" then
        return GUIDE_ICON .. GUIDE_COLOR .. line.text .. "|r"
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

-- Steps with |mapmarker lines name more than one place for the same thing ("Multiple locations").
-- Zygor's arrow only points at the step's goal places, so on such a step a left click on any of
-- its lines moves the arrow to the next place: goal places in step order, then the marker places,
-- then around again. Other steps keep Zygor's own goal click.
local function IsPlace(place, map, x, y)
    return place.map == map and math.abs(place.x - x) < 0.0005 and math.abs(place.y - y) < 0.0005
end

local function StepPlaces(step)
    local places, markers = {}, false
    for _, goal in ipairs(step.goals or {}) do
        local place
        if goal.x and goal.y and goal.map then
            if goal.action == "mapmarker" then
                if not goal.condition_visible or goal.condition_visible() then
                    place, markers = {map = goal.map, x = goal.x, y = goal.y}, true
                end
            elseif not goal.force_noway and goal:IsVisible() and goal:GetStatus() ~= "complete" then
                place = {map = goal.map, x = goal.x, y = goal.y, goal = goal}
            end
        end
        for _, other in ipairs(place and places or {}) do
            if IsPlace(other, place.map, place.x, place.y) then
                place = nil
                break
            end
        end
        places[#places + 1] = place
    end
    return markers and #places > 1 and places or nil
end

-- The place after the arrow's current one; when the arrow points elsewhere, the clicked goal's own.
local function NextPlace(places, clicked)
    local dest = ZGV.Pointer.DestinationWaypoint
    if dest and dest.x and dest.y then
        for i, place in ipairs(places) do
            if IsPlace(place, dest.m, dest.x, dest.y) then
                return places[i % #places + 1]
            end
        end
    end
    for _, place in ipairs(places) do
        if place.goal == clicked then
            return place
        end
    end
    return places[1]
end

local function PointAt(step, place)
    local pointer = ZGV.Pointer
    pointer:ClearWaypoints("manual")
    if WorldMapFrame:IsShown() then
        WorldMapFrame:SetMapID(place.map)
    end
    if place.goal and not step:IsCurrentlySticky() then
        -- What Zygor's own goal click does: the arrow belongs to the goal and moves on once it is done.
        step:CycleWaypointTo(place.goal.num)
        ZGV:ShowWaypoints()
    else
        -- What Zygor does for a map marker click.
        pointer:FindTravelPath(pointer:SetWaypoint(place.map, place.x, place.y, {}, false))
    end
end

local function ClickGoal(goal, button)
    local step = goal.parentStep
    local kind = ZGV.GOALTYPES[goal.action]
    local places = step and button == "LeftButton" and not goal.next
        and not (kind and (kind.click_to_complete or kind.onclick)) and StepPlaces(step)
    if places then
        PointAt(step, NextPlace(places, goal))
    else
        goal:OnClick(button)
    end
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
    if data.kind == "nextguide" and button ~= "RightButton" then
        Z.Menu.LoadGuide(data.guide)
        return
    end
    if data.kind == "catchup" and button ~= "RightButton" then
        if data.active then
            Z.Catchup.Stop()
        else
            Z.Catchup.Start()
        end
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
    Z.Try(ClickGoal, data.goal, button)
    Z.RefreshSoon()
end

local function Tag(line, data)
    if tagged[line] == nil then
        tagged[line] = line:GetScript("OnClick") or false
    end
    line.zuestie = data
    line:SetScript("OnClick", OnLineClick)
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(self.tip, 1, 0.82, 0)
    if self.hint then
        GameTooltip:AddLine(self.hint(), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function HideTooltip()
    GameTooltip:Hide()
end

-- Back, choose-guide and next buttons in the empty space left of the step line, where Questie
-- puts the buttons in front of quest titles. Three frames made once, moved onto each layout's step line.
local SLOT_GAP = 2
local BUTTONS = {
    {key = "guides", tip = "Choose a guide", texture = "Interface\\Icons\\INV_Misc_Book_09",
        click = function(_, mouse)
            if mouse == "RightButton" then
                Z.Options.ToggleArrow()
            else
                Z.Menu.OpenGuides()
            end
        end,
        hint = function()
            return ZGV.db.profile.arrowshow and "Right-click: hide the arrow" or "Right-click: show the arrow"
        end},
    {key = "prev", tip = "Previous step", texture = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage", paged = true, click = function() Z.PrevStep() end},
    {key = "next", tip = "Next step (skip)", texture = "Interface\\Buttons\\UI-SpellbookIcon-NextPage", paged = true, click = function() Z.SkipStep() end},
}
local SHOW_ORDER = {"guides", "next", "prev"} -- which buttons stay when the space is narrow
local buttons = {}

local function GetButton(spec)
    local button = buttons[spec.key]
    if not button then
        button = CreateFrame("Button")
        button.tip = spec.tip
        button.hint = spec.hint
        if spec.hint then
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
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

-- Item buttons for "use" steps, in Questie's quest-item column. They are secure action buttons:
-- made, attached and hidden only during Questie's layouts, which never run in combat. Clicking works
-- in combat; count, cooldown and gray-out update from bag events.
local MAX_ITEM_BUTTONS = 4
local itemButtons = {}
local usedItemButtons = 0

local function ItemTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetItemByID(self.itemid)
    GameTooltip:Show()
end

local function ItemCount(itemid)
    local getCount = C_Item and C_Item.GetItemCount or GetItemCount
    return getCount(itemid, false, true) or 0
end

local function UpdateItemButton(button)
    local count = ItemCount(button.itemid)
    button.count:SetText(count > 1 and count or "")
    button.icon:SetDesaturated(count == 0)
    local getCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    local start, duration, enable = getCooldown(button.itemid)
    if start and duration and duration > 0 and enable ~= 0 and enable ~= false then
        button.cooldown:SetCooldown(start, duration)
        button.cooldown:Show()
    else
        button.cooldown:Hide()
    end
end

local function GetItemButton(i)
    local button = itemButtons[i]
    if not button then
        button = CreateFrame("Button", "ZuestieItemButton" .. i, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("AnyUp", "AnyDown")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        button.count:SetPoint("BOTTOMRIGHT", -1, 1)
        button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cooldown:SetAllPoints()
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnEnter", ItemTooltip)
        button:SetScript("OnLeave", HideTooltip)
        button:Hide()
        itemButtons[i] = button
    end
    return button
end

local function PlaceItemButton(line, itemid)
    if usedItemButtons >= MAX_ITEM_BUTTONS or InCombatLockdown() then
        return
    end
    usedItemButtons = usedItemButtons + 1
    local button = GetItemButton(usedItemButtons)
    button.itemid = itemid
    button:SetAttribute("type1", "item")
    button:SetAttribute("item1", "item:" .. itemid)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemid)
    button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    UpdateItemButton(button)

    local margins = TrackerLayout.GetMargins()
    local size = margins.quest - SLOT_GAP - margins.itemButtonLeft
    button:SetSize(size, size)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", line, "TOPLEFT", margins.itemButtonLeft, 1)
    button:SetParent(line)
    button:Show()
end

local function HideItemButtons()
    for i = 1, usedItemButtons do
        local button = itemButtons[i]
        button:Hide()
        button:ClearAllPoints()
        button:SetParent(UIParent)
        button:SetAttribute("item1", nil)
    end
    usedItemButtons = 0
end

function T.UpdateItemButtons()
    for i = 1, usedItemButtons do
        Z.Try(UpdateItemButton, itemButtons[i])
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

    -- Item buttons need Questie's wide quest-item column, as when a tracked quest has an item.
    for _, data in ipairs(m.lines) do
        if data.itemid then
            if TrackerLayout.SetItemColumnShown then
                TrackerLayout.SetItemColumnShown(true)
            end
            break
        end
    end

    -- One shared target: hovering any line highlights the whole guide section.
    local target = {zuestie = true}
    local line = LineBuilder.AddTitle({text = "|cFFFFD100" .. m.title .. "|r", colored = true, clickMode = "recipe", target = target})
    if not line then
        return
    end
    Tag(line, {kind = "title", text = m.title})
    if Z.Setting("showButtons") then
        Z.Try(PlaceButtons, line, m.guide ~= nil)
    end

    local last = line
    for _, data in ipairs(m.lines) do
        line = LineBuilder.AddObjective({text = Format(data), clickMode = "recipe", target = target})
        if not line then
            break
        end
        Tag(line, data)
        if data.itemid then
            Z.Try(PlaceItemButton, line, data.itemid)
        end
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
    elseif data.kind == "nextguide" then
        tip:AddLine(data.guide.title_short or data.guide.title, 1, 0.82, 0)
        tip:AddLine("Click: load this guide", 0.6, 0.6, 0.6)
    elseif data.kind == "catchup" then
        Z.Catchup.Tooltip(tip, data)
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

    -- Quest titles in Questie's list get the violet "!" when the guide uses the quest.
    -- QuestSection builds a fresh options table per title, so prefixing its text is safe.
    local addTitle = LineBuilder.AddTitle
    LineBuilder.AddTitle = function(options, ...)
        if Z.active and options and options.clickMode == "quest" and options.target
            and Z.Setting("questListMarks") and Z.Pins.IsGuideQuest(options.target.Id) then
            options.text = GUIDE_ICON .. options.text
        end
        return addTitle(options, ...)
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
        HideItemButtons()
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
