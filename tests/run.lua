-- Offline checks for Zuestie, with small stand-ins for WoW, Questie and Zygor.
-- Run from the repository root: lua5.1 tests/run.lua (fails with an error if any check fails).
-- These prove wiring and behavior of Zuestie's own code; the in-game look still needs a /reload.
local ROOT = ROOT or ""
local unpack = table.unpack or unpack

local failures = 0
local function check(ok, label)
    if ok then
        print("PASS " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end

-- WoW frames ---------------------------------------------------------------------------------
COMBAT = false
COMBAT_VIOLATION = nil
function InCombatLockdown() return COMBAT end

local FRAMES = {}
local Frame = {}
Frame.__index = Frame

local function Protected(self, what)
    if COMBAT and self.template == "SecureActionButtonTemplate" then
        COMBAT_VIOLATION = what
    end
end

local function NewFrame(kind, name, parent, template)
    local f = setmetatable({kind = kind, name = name, parent = parent, template = template, points = {}, shown = true,
        alpha = 1, clamped = false, scripts = {}, hooks = {}, attributes = {}}, Frame)
    if name then
        _G[name] = f
    end
    FRAMES[#FRAMES + 1] = f
    return f
end

function Frame:SetPoint(...) Protected(self, "SetPoint") self.points[#self.points + 1] = {...} end
function Frame:ClearAllPoints() Protected(self, "ClearAllPoints") self.points = {} end
function Frame:GetPoint(i) local p = self.points[i or 1] if p then return unpack(p) end end
function Frame:SetClampedToScreen(v) self.clamped = v end
function Frame:IsClampedToScreen() return self.clamped end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown end
function Frame:Show() Protected(self, "Show") self.shown = true end
function Frame:Hide()
    Protected(self, "Hide")
    local was = self.shown
    self.shown = false
    if was then
        for _, hook in ipairs(self.hooks.OnHide or {}) do hook(self) end
    end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:GetAlpha() return self.alpha end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:HookScript(event, fn) self.hooks[event] = self.hooks[event] or {} table.insert(self.hooks[event], fn) end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:GetScript(event) return self.scripts[event] end
function Frame:RegisterEvent() end
function Frame:GetParent() return self.parent end
function Frame:SetParent(p) Protected(self, "SetParent") self.parent = p end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetNormalTexture(t) self.normal = t end
function Frame:SetPushedTexture() end
function Frame:SetDisabledTexture() end
function Frame:SetHighlightTexture() end
function Frame:RegisterForClicks() end
function Frame:CreateTexture() return NewFrame("Texture") end
function Frame:CreateFontString() return NewFrame("FontString") end
function Frame:SetAllPoints() end
function Frame:SetTexture(t) self.texturePath = t end
function Frame:SetText(t) self.text = t end
function Frame:SetDesaturated(v) self.desaturated = v end
function Frame:SetCooldown() end
function Frame:SetAttribute(k, v) Protected(self, "SetAttribute") self.attributes[k] = v end
function Frame:GetAttribute(k) return self.attributes[k] end

function CreateFrame(kind, name, parent, template) return NewFrame(kind, name, parent, template) end
UIParent = NewFrame("Frame", "UIParent")
WorldMapFrame = NewFrame("Frame", "WorldMapFrame")
function WorldMapFrame:SetMapID(id) self.mapID = id end

GameTooltip = {lines = {}}
function GameTooltip:SetOwner(owner) self.owner = owner self.lines = {} end
function GameTooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
function GameTooltip:SetItemByID(id) self.item = id end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false end
function GameTooltip:GetOwner() return self.owner end

local CHAT = {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, msg) CHAT[#CHAT + 1] = msg end}
function geterrorhandler() return function(err) print("LUA ERROR " .. tostring(err)) failures = failures + 1 end end
function hooksecurefunc(t, key, fn)
    local orig = t[key]
    t[key] = function(...)
        local results = {orig(...)}
        fn(...)
        return unpack(results)
    end
end
function strlower(s) return string.lower(s) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
    local parts = {}
    for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
    return unpack(parts)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}

local timers, tickers = {}, {}
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn)
        local ticker = {fn = fn}
        function ticker:Cancel() self.cancelled = true end
        tickers[#tickers + 1] = ticker
        return ticker
    end,
}
local function RunTimers()
    for _ = 1, 50 do
        if #timers == 0 then return end
        local queue = timers
        timers = {}
        for _, fn in ipairs(queue) do fn() end
    end
end
local function Tick()
    for _, ticker in ipairs(tickers) do
        if not ticker.cancelled then ticker.fn() end
    end
    RunTimers()
end
local function Fire(event, arg)
    for _, f in ipairs(FRAMES) do
        if f.scripts.OnEvent then f.scripts.OnEvent(f, event, arg) end
    end
end

BAGS = {[1234] = 3}
C_Item = {
    GetItemInfoInstant = function(id) return id, "Quest", "Quest", "", 134400 end,
    GetItemCount = function(id) return BAGS[id] or 0 end,
}
C_Container = {GetItemCooldown = function() return 0, 0, 1 end}
OBJECTIVES = {[245] = {{"Pygmy Venom Web Spider slain: 7/15", "monster"}}}
function GetQuestObjectiveInfo(questId, i)
    local o = OBJECTIVES[questId] and OBJECTIVES[questId][i]
    if o then return o[1], o[2], false, 0, 0 end
end
OPENED_CATEGORY = nil
Settings = {OpenToCategory = function(id) OPENED_CATEGORY = id end}
LOCKPICKING = 14
C_SkillInfo = {GetSkillLineInfoByID = function(id)
    if id == 633 then return {name = "Lockpicking", rank = LOCKPICKING, maxRank = 100, skillID = 633} end
end}
PARTY = {} -- party1, party2, ...: {name, surname}
function GetNumGroupMembers() return #PARTY + 1 end
function UnitNameUnmodified(unit)
    local member = PARTY[tonumber(unit:match("%d+$"))]
    if member then return member[1], member[2] end
end

-- Libraries --------------------------------------------------------------------------------
local MESSAGES = {}
local OPTIONS
local LAST_MENU
local LIBS = {
    ["AceEvent-3.0"] = {Embed = function(_, target)
        target.RegisterMessage = function(_, message, fn) MESSAGES[message] = fn end
    end},
    ["LibUIDropDownMenuQuestie-4.0"] = {
        Create_UIDropDownMenu = function() return {} end,
        EasyMenu = function(_, list) LAST_MENU = list end,
        CloseDropDownMenus = function() end,
    },
    ["AceConfigRegistry-3.0"] = {RegisterOptionsTable = function(_, _, options) OPTIONS = options end},
    ["AceConfigDialog-3.0"] = {AddToBlizOptions = function() return {}, 77 end},
}
LibStub = setmetatable({GetLibrary = function(_, name) return LIBS[name] end}, {__call = function(_, name) return LIBS[name] end})

-- Questie ----------------------------------------------------------------------------------
local MODULES = {}
QuestieLoader = {ImportModule = function(_, name) MODULES[name] = MODULES[name] or {} return MODULES[name] end}
local function M(name) return QuestieLoader:ImportModule(name) end

local DRAWN, UPDATES, ITEM_COLUMN = {}, 0, false
local TRACKED = {245, 777}
local function Line(label)
    local line = NewFrame("Button")
    line.label = label
    line:SetScript("OnClick", "questieHandler")
    DRAWN[#DRAWN + 1] = line
    return line
end
M("LineBuilder").AddHeader = function(o) return Line("H:" .. o.text), false end
M("LineBuilder").AddTitle = function(o) return Line("T:" .. o.text) end
M("LineBuilder").AddObjective = function(o) return Line("O:" .. o.text) end
M("LineBuilder").FinishEntry = function() end
M("TrackerLayout").GetMargins = function()
    local column = ITEM_COLUMN and 25 or 16 -- Questie's item column is wider while a line has an item
    return {quest = 40 + column, objective = 53 + column, buttonSize = 16, itemButtonLeft = 38}
end
M("TrackerLayout").SetItemColumnShown = function(shown) ITEM_COLUMN = shown end
M("QuestSection").Draw = function()
    for _, id in ipairs(TRACKED) do
        M("LineBuilder").AddTitle({text = "Quest " .. id, colored = true, clickMode = "quest", target = {Id = id}})
    end
end
M("TrackerLinePool").ResetLinesForChange = function() end
M("TrackerUtils").HasQuest = function() return false end
M("TrackerQuestTooltip").Show = function() end
M("TrackerQuestTooltip").Hide = function() end
M("QuestieTracker").started = true
M("QuestieTracker").Update = function()
    if InCombatLockdown() then return end
    UPDATES = UPDATES + 1
    DRAWN = {}
    ITEM_COLUMN = false
    M("TrackerLinePool").ResetLinesForChange()
    M("QuestSection").Draw()
end

local PINS = {}
local QM = M("QuestieMap")
QM.questIdFrames = {}
local iconCount = 0
function QM:DrawManualIcon(data) PINS[#PINS + 1] = data end
function QM:ResetManualFrames() PINS = {} end
function QM:DrawWorldIcon(data)
    local frames = {}
    for _, minimap in ipairs({false, true}) do
        iconCount = iconCount + 1
        local f = {name = "QuestieIcon" .. iconCount, data = data, miniMapIcon = minimap, texture = NewFrame("Texture")}
        f.texture:SetTexture(Questie.usedIcons[data.Icon])
        _G[f.name] = f
        self.questIdFrames[data.Id] = self.questIdFrames[data.Id] or {}
        self.questIdFrames[data.Id][f.name] = f.name
        frames[#frames + 1] = f
    end
    return frames[1], frames[2]
end
function QM:GetFramesForQuest(id)
    local found = {}
    for name in pairs(self.questIdFrames[id] or {}) do found[name] = _G[name] end
    return found
end
M("QuestieLib").GetQuestIcon = function(quest) return quest.icon end
M("ZoneDB").GetAreaIdByUiMapId = function(_, map)
    if map == 999 then error("No AreaId found for UiMapId: 999") end
    return map + 10000
end
local QDATA = {}
M("QuestieDB").QueryQuestSingle = function(id, field) return QDATA[id] and QDATA[id][field] end
M("QuestiePlayer").HasRequiredRace = function() return true end
M("QuestiePlayer").HasRequiredClass = function(classes) return classes == nil end

local questCallbacks = {}
Questie = {
    db = {profile = {trackerEnabled = true}},
    ICON_TYPE_AVAILABLE = 6,
    usedIcons = {[6] = "yellow", [13] = "green"},
    icons = setmetatable({}, {__index = function(_, k) return "Questie\\" .. k end}),
    API = {isReady = true, RegisterForQuestUpdates = function(cb) questCallbacks[#questCallbacks + 1] = cb end},
}

-- Zygor ------------------------------------------------------------------------------------
local Goal = {}
Goal.__index = Goal
function Goal:GetStatus() return self.status end
function Goal:GetText() return self.text end
function Goal:IsVisible() return true end
function Goal:IsInlineTravel() return self.travel or false end
function Goal:CanBeIndentHidden() return false end
function Goal:OnClick() CLICKED = self end
function Goal:GetTooltip() end
local function G(t) return setmetatable(t, Goal) end
local Step = {}
Step.__index = Step
function Step:IsComplete() return false end
function Step:AreRequirementsMet() return not self.otherClass end
function Step:IsCurrentlySticky() return false end
function Step:CycleWaypointTo(num)
    local goal = self.goals[num]
    ZGV.Pointer.DestinationWaypoint = {m = goal.map, x = goal.x, y = goal.y}
end
local function S(goals)
    local step = setmetatable({goals = goals}, Step)
    for i, goal in ipairs(goals) do
        goal.parentStep, goal.num = step, i
    end
    return step
end
local Guide = {}
Guide.__index = Guide
function Guide:GetStatus() return self.status or "VALID" end
local function NewGuide(title, fields)
    local guide = setmetatable(fields or {}, Guide)
    guide.title = title
    guide.title_short = title:match("([^\\]+)$")
    return guide
end

local KILL = G{action = "kill", status = "incomplete", text = "Kill 15 Pygmy Venom Web Spider", questid = 245,
    target = "Pygmy Venom Web Spider", tooltip = "They roam the hills.", x = 0.3, y = 0.4, map = 1431}
local USE = G{action = "use", status = "incomplete", text = "Use the Ectoplasmic Distiller", itemid = 1234, x = 0.2, y = 0.5, map = 1431}
local STEP1 = S{
    G{action = "accept", status = "complete", text = "Accept 'The Legend of Stalvan'", questid = 66, x = 0.75, y = 0.45, map = 1431},
    KILL,
    USE,
    G{action = "goto", status = "incomplete", text = "Go to 10.2,49.7", travel = true, x = 0.102, y = 0.497, map = 1431},
    G{action = "talk", status = "incomplete", text = "Talk inside the instance", x = 0.1, y = 0.1, map = 999},
}
local LAST = S{G{action = "", status = "passive", text = "This guide is now complete."}}
local NEXT1 = NewGuide("LEVELING\\Wetlands (27-29)", {rawdata = "\nstep\naccept Fresh Meat##281 |goto Wetlands 10,50\n",
    next = "Leveling Guides\\Ashenvale (29-30)"})
local NEXT2 = NewGuide("LEVELING\\Ashenvale (29-30)", {rawdata = "\naccept The Tower of Althalaxx##1140\n"})
local CURRENT = NewGuide("LEVELING\\Duskwood & Redridge Mountains (25-27)", {steps = {STEP1, LAST},
    next = "Leveling Guides\\Wetlands (27-29)"})
local GUIDES = {CURRENT, NEXT1, NEXT2}

local master = NewFrame("Frame", "ZygorGuidesViewerFrameMaster", UIParent)
local zframe = NewFrame("Frame", "ZygorGuidesViewerFrame", master)
zframe.clamped = true
zframe:SetPoint("TOPLEFT", master)

local FOG = true
TURNED_IN = {} -- [questId] = true: what the game says is turned in
ZGV = {
    Frame = zframe,
    initialized = true,
    db = {profile = {tooltipsbelow = true, stickyon = false, enable_actionbar = true, mapicons = true, foglight = true,
        showmapbutton = true, nc_enable = true, hideincombat = false, n_popup_guides = true, enable_viewer = true,
        progress = true, progressbarmode = "steps", arrowshow = true, arrowskin = "Starlight", arrowscale = 1}},
    registeredguides = GUIDES,
    CurrentGuide = CURRENT,
    CurrentStep = STEP1,
    CurrentStepNum = 1,
    questsbyid = {[245] = {inlog = true}},
    -- Zygor asks the game about quests missing from the table (QuestTracking.lua).
    completedQuests = setmetatable({}, {__index = function(_, id) return TURNED_IN[tonumber(id) or 0] or false end}),
    GOALTYPES = {},
    ProgressBar = {CurrentProgress = 34, Text = {tooltip = "Steps Completed: 1/2"}},
    Pointer = {
        ArrowSkins = {Starlight = {name = "Starlight"}, Stealth = {name = "Stealth"}},
        ClearSet = function() end,
        ClearAntsAndLines = function() LINES_CLEARED = (LINES_CLEARED or 0) + 1 end,
        AnimateAnts = function() LINES_DRAWN = (LINES_DRAWN or 0) + 1 end,
        ClearWaypoints = function() end,
        SetWaypoint = function(_, m, x, y) return {m = m, x = x, y = y} end,
        FindTravelPath = function(self, way) self.DestinationWaypoint = way end,
        ShowMapMarkers = function() end,
        SetArrowSkin = function(_, id) ZGV.db.profile.arrowskin = id end,
        SetupArrow = function() ARROW_SETUP = (ARROW_SETUP or 0) + 1 end,
        UpdateArrowVisibility = function() end,
    },
    ActionBar = {initialised = true, ClearBar = function() ACTIONBAR = "cleared" end,
        SetActionButtons = function() ACTIONBAR = "set" end, ToggleFrame = function() end},
    Foglight = {DataProvider = {name = "fog"}, ToggleOverlay = function() FOG = not FOG end},
    IsDataProviderRegistered = function() return FOG end,
    NotificationCenter = {UpdateButton = function() end},
    Tabs = {Pool = {}, TryToActivateGuide = function() return false end,
        LoadGuideToTab = function(_, title, step) TAB_OPENED = {title, step} end},
    BugReport = {GuideRating = {}},
    Professions = {tradeskillsIdByName = {Cooking = 185, Riding = 762},
        known = {Cooking = {level = 126, max = 150, skillID = 185, name = "Cooking"}},
        placeholder = {active = false, level = 0, max = 0, placeholder = true}},
    IsForever = true,
    IsSecret = function() return false end,
    Sync = {
        OnEvent = function() SYNC_EVENTS = (SYNC_EVENTS or 0) + 1 end,
        IsPartyStatusComplete = function() return true end,
        GetStepGoalPartyStatusText = function() return "[X]", "ff00ff00" end,
    },
}
ZGV.Events_Events = {GROUP_ROSTER_UPDATE = {ZGV.Sync.OnEvent}}
-- Zygor makes its end-of-guide panel inside its window, clamped to the screen like every ZGV.UI frame.
function ZGV.BugReport.GuideRating:CreateAltFrame()
    self.NoRatingFrame = NewFrame("Frame", nil, zframe)
    self.NoRatingFrame.clamped = true
end
function ZGV.Professions:GetSkill(name) return self.known[name] or self.placeholder end
function ZGV:SetGuide(title) LOADED = title end
function ZGV:FocusStep() end
function ZGV:SkipStep(fast) SKIPPED = fast end
function ZGV:PreviousStep(fast) BACKED = fast end
function ZGV:GetStickiesAt() return {} end
function ZGV:SetVisible(_, on) self.Frame:SetShown(on) end
function ZGV:FindSuggestedGuides() return {} end
function ZGV:GetGuideByTitle(title)
    local short = title:match("([^\\]+)$")
    for _, guide in ipairs(GUIDES) do
        if guide.title_short == short then return guide end
    end
end
function ZGV:ReanchorFrame() self.Frame:ClearAllPoints() self.Frame:SetPoint("TOPLEFT", self.Frame:GetParent()) end
function ZGV:ShowWaypoints() end
function ZGV:UpdateMapButton() end
function ZGV:SanitizeGuideTitle(title) return (title:gsub("^Leveling Guides\\", "LEVELING\\")) end

-- Load Zuestie in TOC order ----------------------------------------------------------------
-- Load Zuestie in TOC order. A runner without file access can pass ZUESTIE_FILES and ZUESTIE_SOURCES.
local Z = {}
local files = ZUESTIE_FILES
if not files then
    files = {}
    for line in io.lines(ROOT .. "Zuestie.toc") do
        -- Bundled libraries (Libs\) keep their own mocks; the suite tests Zuestie's code only.
        local entry = line:match("^%s*(.-)%s*$")
        if entry:match("%.lua%s*$") and not entry:match("^Libs\\") then files[#files + 1] = entry end
    end
end
local compile = loadstring or load
for _, name in ipairs(files) do
    local chunk = ZUESTIE_SOURCES and assert(compile(ZUESTIE_SOURCES[name], "@" .. name)) or assert(loadfile(ROOT .. name))
    chunk("Zuestie", Z)
end

local function Labels()
    local labels = {}
    for _, line in ipairs(DRAWN) do labels[#labels + 1] = line.label end
    return table.concat(labels, "\n")
end
local function Find(pattern)
    for _, line in ipairs(DRAWN) do
        if line.label:find(pattern) then return line end
    end
end
local VIOLET = "Interface\\AddOns\\Zuestie\\Icons\\available_guide.png"
local function QuestIcon(id, icon)
    return (QM:DrawWorldIcon({Id = id, Icon = icon, Type = "available", QuestData = {icon = icon}}))
end

-- Questie draws some quest starters before Zuestie turns on.
local ICON66, ICON281, ICON500, ICON20 = QuestIcon(66, 6), QuestIcon(281, 6), QuestIcon(500, 6), QuestIcon(20, 13)

Fire("ADDON_LOADED", "Zuestie")
Fire("PLAYER_LOGIN")
Tick()

-- Startup ----------------------------------------------------------------------------------
check(Z.active == true, "turns on after login")
local point, relativeTo = zframe:GetPoint(1)
check(point == "TOPRIGHT" and relativeTo == UIParent and not zframe.clamped, "parks Zygor's window off-screen")
check(zframe.shown and zframe.alpha >= 0.1, "keeps Zygor's window shown so its step checker runs")
local p = ZGV.db.profile
check(p.enable_actionbar == false and p.mapicons == false and p.foglight == false and p.n_popup_guides == false,
    "switches off Zygor's own UI while on")
check(ACTIONBAR == "cleared" and FOG == false, "clears Zygor's item bar and map overlay")

-- Tracker ----------------------------------------------------------------------------------
check(DRAWN[1].label == "H:Duskwood & Redridge Mountains", "guide header first, without the level range")
check(DRAWN[2].label:find("%(25%-27%) Step 1/2") ~= nil, "step line shows levels and step count")
check(Find("WHITE8X8") ~= nil, "progress bar line")
check(Find("They roam the hills") ~= nil, "tip line")
check(not Labels():find("Go to 10.2"), "inline travel hidden like Zygor")
check(DRAWN[#DRAWN].label:find("T:.*Quest 777") ~= nil, "Questie's quest list still drawn below the guide")
check(UPDATES == 1, "one Questie layout on startup")
Tick()
check(UPDATES == 1, "no layout when nothing changed")

check(KILL.objnum == 1, "links a kill line without an objective to the quest's objective")

-- Skills Zygor misses
check(ZGV.Professions:GetSkill("Lockpicking").level == 14 and ZGV.Professions:GetSkill("Lockpicking").max == 100,
    "reads Lockpicking, which Zygor does not track")
LOCKPICKING = 15
check(ZGV.Professions:GetSkill("Lockpicking").level == 15, "Lockpicking follows skill-ups")
check(ZGV.Professions:GetSkill("Cooking").level == 126, "keeps Zygor's own skill values")

-- A quest the game takes away once another one is turned in
QDATA[1282] = {name = "They Call Him Smiling Jim", availableUntilCompleted = 1302}
QDATA[1301] = {name = "James Hyal", availableUntilCompleted = 1282}
QDATA[1440] = {name = "Return to Vahlarriel", exclusiveTo = {1393}}
check(ZGV.completedQuests[1282] == false, "a quest still on offer is not done")
TURNED_IN[1302], TURNED_IN[1393] = true, true
check(ZGV.completedQuests[1282] == true and ZGV.completedQuests[1440] == true,
    "a quest the game no longer offers counts as done for Zygor")
ZGV.questsbyid[1282] = {inlog = true}
check(ZGV.completedQuests[1282] == false and ZGV.completedQuests[1301] == false,
    "a quest in the log is not done, nor are quests it takes away")
ZGV.questsbyid[1282] = nil

-- Zygor's party sync with a member the client has not loaded yet ("Unknown", no surname)
PARTY = {{"Nyx", "Duskfang"}, {"Unknown", nil}}
for _, handler in ipairs(ZGV.Events_Events.GROUP_ROSTER_UPDATE) do handler(ZGV, "GROUP_ROSTER_UPDATE") end
check(SYNC_EVENTS == nil and ZGV.Sync:IsPartyStatusComplete() == false and ZGV.Sync:GetStepGoalPartyStatusText(1, 1) == nil,
    "Zygor's party sync waits while a party member's name is not loaded")
PARTY[2] = {"Trifling", "Fizzlebang"}
RunTimers()
check(SYNC_EVENTS == 1 and ZGV.Sync:IsPartyStatusComplete() == true, "Zygor's party sync runs once the name loads")
PARTY = {}

-- Quest list marks
local q245, q777 = Find("Quest 245"), Find("Quest 777")
check(q245 and q245.label:find(VIOLET, 1, true) ~= nil, "guide quest marked violet in the quest list")
check(q777 and not q777.label:find(VIOLET, 1, true), "other quest not marked")

-- Item button
local item = _G.ZuestieItemButton1
local useLine = Find("Use the Ectoplasmic Distiller")
check(item and item.shown and item.attributes.item1 == "item:1234", "use step gets a secure item button")
check(item and item.parent == useLine and ITEM_COLUMN == true, "item button sits in Questie's item column on its line")
check(item and item.count.text == 3 and not item.icon.desaturated, "item button shows the bag count")

-- Progress change: exactly one layout
ZGV.ProgressBar.CurrentProgress = 41
MESSAGES.ZGV_GOAL_PROGRESS("ZGV_GOAL_PROGRESS")
RunTimers()
check(UPDATES == 2, "one layout after progress changes")

-- Combat
COMBAT = true
KILL.text = "Kill 7 Pygmy Venom Web Spider (8/15)"
BAGS[1234] = 0
Fire("BAG_UPDATE_DELAYED")
Tick()
check(UPDATES == 2, "no layout during combat")
check(item.icon.desaturated == true, "item button grays out in combat when the item runs out")
check(COMBAT_VIOLATION == nil, "no protected button changes during combat")
COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
RunTimers()
check(UPDATES == 3 and Find("8/15") ~= nil, "lays out after combat ends")

-- Clicks
Find("Kill 7").scripts.OnClick(Find("Kill 7"), "LeftButton")
check(CLICKED == KILL, "clicking a line forwards to Zygor")
local killLine = Find("Kill 7")
M("QuestieTracker"):Update()
check(killLine.zuestie == nil and killLine.scripts.OnClick == "questieHandler", "pooled line handed back to Questie")

-- A step naming more than one place for the same thing (|mapmarker): each click moves the arrow on.
local DOCS = G{action = "click", status = "incomplete", text = "Click Syndicate Documents"}
ZGV.CurrentStep = S{DOCS,
    G{action = "accept", status = "incomplete", text = "Accept 'Foreboding Plans'", x = 0.4791, y = 0.8213, map = 1416},
    G{action = "mapmarker", status = "hidden", text = "", x = 0.5832, y = 0.6792, map = 1416}}
MESSAGES.ZGV_STEP_CHANGED("ZGV_STEP_CHANGED")
RunTimers()
local docs = Find("Click Syndicate Documents")
local function ArrowX() return ZGV.Pointer.DestinationWaypoint and ZGV.Pointer.DestinationWaypoint.x end
CLICKED = nil
docs.scripts.OnClick(docs, "LeftButton")
check(ArrowX() == 0.4791 and WorldMapFrame.mapID == 1416, "first click on a multi-place step points at its first place")
docs.scripts.OnClick(docs, "LeftButton")
check(ArrowX() == 0.5832, "next click points at the marker place")
docs.scripts.OnClick(docs, "LeftButton")
check(ArrowX() == 0.4791 and CLICKED == nil, "then back to the first place")
ZGV.CurrentStep, ZGV.Pointer.DestinationWaypoint = STEP1, nil
MESSAGES.ZGV_STEP_CHANGED("ZGV_STEP_CHANGED")
RunTimers()

-- Map colors
check(ICON66.texture.texturePath == VIOLET, "guide quest from an earlier step is violet")
check(ICON281.texture.texturePath == VIOLET, "next guide's quest is violet")
check(ICON500.texture.texturePath == "yellow", "quest outside the guides stays yellow")
check(ICON20.texture.texturePath == "green", "event quest keeps Questie's color")
local laterIcon = QuestIcon(1140, 6)
check(laterIcon.texture.texturePath == VIOLET, "quest drawn later gets violet as Questie draws it")
check(#PINS > 0, "step pins drawn on the map")

-- Settings page
check(OPTIONS ~= nil, "settings page registered")
SlashCmdList.ZUESTIE("config")
check(OPENED_CATEGORY == 77, "/zu config opens the settings page")
local args = OPTIONS.args
args.tracker.args.showTips.set({"showTips"}, false)
check(not Labels():find("They roam the hills"), "tips setting off hides tip lines")
args.tracker.args.showTips.set({"showTips"}, true)
args.map.args.violetQuests.set({"violetQuests"}, false)
check(ICON66.texture.texturePath == "yellow", "violet setting off restores yellow")
args.map.args.violetQuests.set({"violetQuests"}, true)
check(ICON66.texture.texturePath == VIOLET, "violet setting on again")
args.map.args.nextGuides.set({"nextGuides"}, 0)
check(ICON281.texture.texturePath == "yellow", "next guides set to 0 drops their quests")
args.map.args.nextGuides.set({"nextGuides"}, 3)
args.tracker.args.itemButtons.set({"itemButtons"}, false)
check(not item.shown, "item button setting off removes the button")
args.tracker.args.itemButtons.set({"itemButtons"}, true)
args.arrow.args.arrowskin.set(nil, "Stealth")
check(p.arrowskin == "Stealth", "arrow style changes Zygor's arrow")
args.arrow.args.arrowscale.set(nil, 1.25)
check(p.arrowscale == 1.25 and ARROW_SETUP == 1, "arrow size changes Zygor's arrow")
COMBAT = true
args.arrow.args.arrowskin.set(nil, "Starlight")
COMBAT = false
check(p.arrowskin == "Stealth", "arrow is not rebuilt during combat")
local pathLines = args.pathLines.args
pathLines.maplines_enabled.set(nil, true)
check(p.maplines_enabled == true and pathLines.maplines_enabled.get() == true and LINES_CLEARED == 1 and LINES_DRAWN == 1,
    "path lines setting turns Zygor's lines on and redraws them")
pathLines.maplines.set(nil, 1)
check(p.maplines == 1 and LINES_DRAWN == 2, "path line style changes Zygor's lines")
pathLines.maplines_enabled.set(nil, false)
check(p.maplines_enabled == false and pathLines.maplines.disabled(), "path lines off; style greys out")

-- Book button: left-click chooses a guide, right-click hides or shows the arrow
local book
for _, f in ipairs(FRAMES) do
    if f.normal == "Interface\\Icons\\INV_Misc_Book_09" then book = f end
end
LAST_MENU = nil
book.scripts.OnClick(book, "LeftButton")
check(LAST_MENU ~= nil and p.arrowshow == true, "left-clicking the book button opens the guide menu")
book.scripts.OnClick(book, "RightButton")
check(p.arrowshow == false, "right-clicking the book button hides the arrow")
COMBAT = true
book.scripts.OnClick(book, "RightButton")
COMBAT = false
check(p.arrowshow == false, "the arrow is not shown or hidden during combat")
book.scripts.OnClick(book, "RightButton")
check(p.arrowshow == true, "right-clicking again shows the arrow")

-- Step arrows: right-click jumps over finished steps, like Zygor's own arrows
local nextArrow, prevArrow
for _, f in ipairs(FRAMES) do
    if f.normal == "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" then nextArrow = f end
    if f.normal == "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" then prevArrow = f end
end
nextArrow.scripts.OnClick(nextArrow, "LeftButton")
local leftSkip = SKIPPED
nextArrow.scripts.OnClick(nextArrow, "RightButton")
prevArrow.scripts.OnClick(prevArrow, "RightButton")
check(leftSkip == false and SKIPPED == true and BACKED == true, "right-clicking the step arrows skips finished steps")

-- End of guide
ZGV.CurrentStep, ZGV.CurrentStepNum = LAST, 2
MESSAGES.ZGV_STEP_CHANGED("ZGV_STEP_CHANGED")
RunTimers()
local nextLine = Find("Next guide: Wetlands %(27%-29%)")
check(nextLine ~= nil, "last step shows a next-guide line")
check(not item.shown and item.parent == UIParent, "item button leaves with its step")
nextLine.scripts.OnClick(nextLine, "LeftButton")
check(LOADED == NEXT1.title, "clicking the next-guide line loads it")
local rating = ZGV.BugReport.GuideRating
rating:CreateAltFrame()
check(not rating.NoRatingFrame.clamped, "Zygor's end-of-guide panel stays off-screen with its window")

-- Several open guides (Zygor's tabs)
local function Tab(guide)
    local tab = {guide = guide, step = 1}
    function tab:ActivateGuide() ZGV.Tabs.ActiveTab, ZGV.CurrentGuide = self, self.guide end
    function tab:RemoveTab()
        for i, t in ipairs(ZGV.Tabs.Pool) do
            if t == self then table.remove(ZGV.Tabs.Pool, i) break end
        end
        self.guide = nil
        ZGV.Tabs.Pool[1]:ActivateGuide()
    end
    return tab
end
local tabA, tabB = Tab(CURRENT), Tab(NEXT1)
ZGV.Tabs.Pool, ZGV.Tabs.ActiveTab = {tabA, tabB}, tabA
MESSAGES.ZGV_STEP_CHANGED("ZGV_STEP_CHANGED")
RunTimers()
local tabsLine = Find("2 guides open, next: Wetlands %(27%-29%)")
check(tabsLine ~= nil, "with two guides open, a line names the next one")
tabsLine.scripts.OnClick(tabsLine, "LeftButton")
check(ZGV.CurrentGuide == NEXT1 and ZGV.Tabs.ActiveTab == tabB, "clicking it switches to the next open guide")
local function MenuEntry(list, pattern)
    for _, entry in ipairs(list) do
        if entry.text and entry.text:find(pattern) then return entry end
        local found = entry.menuList and MenuEntry(entry.menuList, pattern)
        if found then return found end
    end
end
Z.Menu.OpenGuides()
MenuEntry(LAST_MENU, "^Ashenvale %(29%-30%)$").func()
check(TAB_OPENED and TAB_OPENED[1] == NEXT2.title and #ZGV.Tabs.Pool == 2,
    "a guide picked from the menu opens in its own tab, next to the open ones")
Z.Menu.Open()
MenuEntry(LAST_MENU, "^Close this guide: Wetlands").func()
check(#ZGV.Tabs.Pool == 1 and ZGV.CurrentGuide == CURRENT, "closing a guide closes its tab and shows the other one")
MESSAGES.ZGV_STEP_CHANGED("ZGV_STEP_CHANGED")
RunTimers()
check(Find("Step 2/2") ~= nil and not Labels():find("guides open"), "no open-guides line with one guide left")
ZGV.Tabs.Pool, ZGV.Tabs.ActiveTab, ZGV.CurrentGuide = {}, nil, CURRENT

-- Catch-up
-- Duskwood (30-32) needs The Night Watch (57) from Duskwood (24-25) and Look To The Stars (177) from
-- Westfall (25-26). Zygor's chains know the first, Questie the second. Quest 159 is for another class.
local PAST = NewGuide("LEVELING\\Duskwood (24-25)", {next = "Leveling Guides\\Westfall (25-26)"})
local MID = NewGuide("LEVELING\\Westfall (25-26)", {next = "Leveling Guides\\Duskwood & Stranglethorn Vale (30-32)"})
local DEST = NewGuide("LEVELING\\Duskwood & Stranglethorn Vale (30-32)")
local function Accept(q, name)
    return G{action = "accept", status = "incomplete", text = "Accept '" .. name .. "'", questid = q}
end
PAST.steps = {S{Accept(900, "Wolves at Our Heels")}, S{Accept(57, "The Night Watch")}}
MID.steps = {S{Accept(177, "Look To The Stars")}}
DEST.steps = {S{G{action = "goto", status = "incomplete", text = "Go to Darkshire"}},
    S{Accept(58, "The Night Watch"), Accept(181, "Look To The Stars")},
    S{Accept(133, "Ghoulish Effigy"), Accept(3503, "Meeting with the Master")}}
for _, guide in ipairs({PAST, MID, DEST}) do GUIDES[#GUIDES + 1] = guide end
QDATA[181] = {preQuestSingle = {177}}
QDATA[159] = {name = "Juice Delivery", requiredClasses = 1}
QDATA[56] = {name = "The Night Watch"}
QDATA[57] = {name = "The Night Watch"}
QDATA[177] = {name = "Look To The Stars"}
QDATA[3503] = {name = "Meeting with the Master"}
ZGV.Chains = {[58] = 57, [57] = 56, [133] = 159, [3503] = 3381} -- quest 3381 is not in the game (no Questie record)
ZGV.ChainsBreadcrumbs, ZGV.RevChains = {}, {}
ZGV.completedQuests = {[56] = true}
ZGV.db.char = {}
local char = ZGV.db.char
ZGV.QuestDB = {GuideForQuest = {[57] = {PAST.title}, [177] = {MID.title}, [159] = {PAST.title}},
    Cancel = function() char.SISquests, char.SISguides, char.SISdestination, char.SISstarted = nil, nil, nil, nil end}
function ZGV:SetGuide(title, step)
    LOADED = title
    self.CurrentGuide = self:GetGuideByTitle(title)
    self.CurrentStepNum = step or 1
    self.CurrentStep = self.CurrentGuide.steps[self.CurrentStepNum]
end
ZGV:SetGuide(DEST.title, 2)
MESSAGES.ZGV_GUIDE_LOADED("ZGV_GUIDE_LOADED")
RunTimers()
local offer = Find("Earlier quests needed: 2, from 2 earlier guides")
check(offer ~= nil, "catch-up line counts the earlier quests the guide needs")
check(ZGV.Chains[181] == 177 and ZGV.RevChains[177][1] == 181, "Questie's prerequisite fills a gap in Zygor's quest chains")
M("TrackerQuestTooltip").Show(offer)
check(table.concat(GameTooltip.lines, "\n"):find("Look To The Stars | Westfall (25-26)", 1, true) ~= nil,
    "catch-up tooltip lists each quest with its guide")
check(ZGV.Chains[3503] == nil and not table.concat(GameTooltip.lines, "\n"):find("Not in Zygor's guides", 1, true),
    "a prerequisite the game does not have blocks nothing, in Zygor's chains too")
offer.scripts.OnClick(offer, "LeftButton")
RunTimers()
check(LOADED == PAST.title and ZGV.CurrentStepNum == 2, "catch-up starts at the earliest guide step with a needed quest")
check(char.SISdestination[1] == DEST.title and char.SISdestination[2] == 2, "catch-up returns to the step it started from")
check(char.SISquests[57] == PAST.title and char.SISquests[177] == MID.title and char.SISquests[159] == nil,
    "catch-up leaves out quests of another class")
check(char.SISguides[PAST.title] == true and char.SISguides[MID.title] == true and char.SISguides[DEST.title] == 2,
    "Zygor skips through the earlier guides up to the step")
check(p.beta_use_chains == true, "Zygor's quest-chain checks on while Zuestie is on")
check(Find("Catching up: 2 earlier quests left") ~= nil, "catch-up line shows what is left")
SlashCmdList.ZUESTIE("catchup")
RunTimers()
check(char.SISquests == nil and char.SISdestination == nil and not Labels():find("Catching up"), "/zu catchup stops it")
check(char.SISstarted == true, "Zygor's quest-chain checks stay on after a catch-up ends")
check(ZGV.CurrentGuide == DEST and ZGV.CurrentStepNum == 2, "stopping goes back to the step the catch-up started from")
check(Find("Earlier quests needed: 2") ~= nil, "stopping shows the same offer again, not one for the earlier guide")
SlashCmdList.ZUESTIE("catchup")
RunTimers()
check(LOADED == PAST.title and char.SISquests ~= nil, "/zu catchup starts it again")
ZGV.completedQuests[57] = true
questCallbacks[1](57, nil, 3)
RunTimers()
check(Find("Catching up: 1 earlier quest left") ~= nil, "turning in a needed quest counts down")
-- Another open guide while catching up: the catch-up neither replaces it nor shows its line there.
local catchupGuide = ZGV.CurrentGuide
ZGV.CurrentGuide = NEXT2
ZGV.completedQuests[177] = true
questCallbacks[1](177, nil, 3)
RunTimers()
check(ZGV.CurrentGuide == NEXT2 and char.SISquests ~= nil and not Labels():find("Catching up"),
    "a catch-up stays in its own tab while another guide is open")
ZGV.CurrentGuide = catchupGuide
questCallbacks[1](177, nil, 3)
RunTimers()
check(ZGV.CurrentGuide == DEST and ZGV.CurrentStepNum == 2 and char.SISquests == nil,
    "jumps back to the step once the earlier quests are done")
check(not Labels():find("Catching up") and not Labels():find("Earlier quests"), "no catch-up line once caught up")

-- Back to Zygor and logout
SlashCmdList.ZUESTIE("zygor")
check(Z.active == false, "/zu zygor turns Zuestie off")
check(p.enable_actionbar == true and p.mapicons == true and p.foglight == true and p.n_popup_guides == true,
    "restores Zygor's settings")
check(p.beta_use_chains == nil, "turns Zygor's quest-chain checks back off")
point, relativeTo = zframe:GetPoint(1)
check(point == "TOPLEFT" and relativeTo == master and zframe.clamped, "puts Zygor's window back")
check(rating.NoRatingFrame.clamped, "puts Zygor's end-of-guide panel back")
check(#PINS == 0, "removes the step pins")
check(not Labels():find("Duskwood"), "Questie's tracker back to stock")
check(ICON66.texture.texturePath == "yellow", "quest colors back to Questie's")
SlashCmdList.ZUESTIE("on")
check(p.mapicons == false, "/zu on turns it on again")
Fire("PLAYER_LOGOUT")
check(p.mapicons == true and p.enable_actionbar == true, "logout saves Zygor's own settings")

check(Z.lastError == nil, "no caught errors (" .. tostring(Z.lastError) .. ")")
if failures > 0 then
    error(failures .. " check(s) failed", 0)
end
print("All checks passed.")
