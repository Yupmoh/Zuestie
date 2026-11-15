-- Zuestie: Zygor's guide engine runs with its window parked off-screen,
-- and the current step is drawn in Questie's tracker and on Questie's map.
-- Work happens only when something changed: Zygor, Questie and game events queue one refresh,
-- and a slow fallback poll catches step conditions nothing announces.
local _, Z = ...
_G.Zuestie = Z

local POLL_SECONDS = 2
local REFRESH_DELAY = 0.1 -- coalesces event bursts into one refresh

Z.ICON_PATH = "Interface\\AddOns\\Zuestie\\Icons\\"
Z.active = false
Z.stepChanges = 0

function Z.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33CCFFZuestie|r: " .. msg)
end

function Z.Try(f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
        Z.lastError = err
    end
    return ok, err
end

-- Removes color codes; keeps textures.
function Z.Strip(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Account-wide settings (ZuestieDB.settings), shown on the Options.lua settings page.
Z.DEFAULTS = {
    showProgress = true, -- progress bar under the step line
    showTips = true, -- Zygor's tips as gray lines (always in the line tooltip)
    showButtons = true, -- book, back and skip buttons on the step line
    itemButtons = true, -- clickable item on "use" steps
    questListMarks = true, -- violet mark on guide quests in Questie's quest list
    mapPins = true, -- the step's waypoints on the map and minimap
    violetQuests = true, -- violet "!" for quests the guides pick up
    nextGuides = 3, -- next guides in Zygor's order whose quests count as guide quests
    catchUp = true, -- offer to catch up on earlier quests the guide needs
}

function Z.Setting(key)
    local value = ZuestieDB and ZuestieDB.settings and ZuestieDB.settings[key]
    if value == nil then
        return Z.DEFAULTS[key]
    end
    return value
end

function Z.SetSetting(key, value)
    ZuestieDB.settings[key] = value
    if not Z.active then
        return
    end
    Z.lastSig, Z.lastPinSig = nil, nil
    Z.Pins.UpdateGuideQuests(true)
    Z.Refresh() -- the cleared signature makes Questie lay out again, also for button and quest-list settings
end

local function Need(missing, ok, name)
    if not ok then
        missing[#missing + 1] = name
    end
end

-- Everything Zuestie calls on Questie. Checked at load: Questie loads first (Dependencies).
local function MissingQuestie()
    local missing = {}
    local QL = _G.QuestieLoader
    Need(missing, type(QL) == "table" and type(QL.ImportModule) == "function", "QuestieLoader")
    if #missing > 0 then
        return missing
    end
    local function fn(module, name)
        local m = QL:ImportModule(module)
        Need(missing, type(m[name]) == "function", module .. "." .. name)
    end
    fn("QuestSection", "Draw")
    fn("LineBuilder", "AddHeader")
    fn("LineBuilder", "AddTitle")
    fn("LineBuilder", "AddObjective")
    fn("LineBuilder", "FinishEntry")
    fn("TrackerLayout", "GetMargins")
    fn("TrackerLinePool", "ResetLinesForChange")
    fn("TrackerUtils", "HasQuest")
    fn("TrackerQuestTooltip", "Show")
    fn("TrackerQuestTooltip", "Hide")
    fn("QuestieTracker", "Update")
    fn("QuestieMap", "DrawManualIcon")
    fn("QuestieMap", "ResetManualFrames")
    fn("QuestieMap", "DrawWorldIcon")
    fn("QuestieMap", "GetFramesForQuest")
    fn("QuestieLib", "GetQuestIcon")
    fn("ZoneDB", "GetAreaIdByUiMapId")
    Need(missing, type(_G.Questie) == "table" and type(_G.Questie.API) == "table"
        and type(_G.Questie.API.RegisterForQuestUpdates) == "function", "Questie.API")
    return missing
end

-- Everything Zuestie calls on Zygor. Checked once Zygor has built its window.
local function MissingZygor()
    local missing = {}
    local ZGV = _G.ZGV
    Need(missing, type(ZGV) == "table", "ZGV")
    if #missing > 0 then
        return missing
    end
    for _, name in ipairs({"SetGuide", "FocusStep", "SkipStep", "PreviousStep", "GetStickiesAt", "SetVisible",
        "FindSuggestedGuides", "GetGuideByTitle", "ReanchorFrame", "ShowWaypoints", "UpdateMapButton"}) do
        Need(missing, type(ZGV[name]) == "function", "ZGV:" .. name)
    end
    Need(missing, type(ZGV.Frame) == "table", "ZGV.Frame")
    Need(missing, type(ZGV.db) == "table" and type(ZGV.db.profile) == "table", "ZGV.db.profile")
    Need(missing, type(ZGV.registeredguides) == "table", "ZGV.registeredguides")
    Need(missing, type(ZGV.Pointer) == "table" and type(ZGV.Pointer.ClearSet) == "function"
        and type(ZGV.Pointer.ShowMapMarkers) == "function", "ZGV.Pointer")
    return missing
end

local function ReportMissing(missing)
    Z.missing = missing
    Z.Print("turned off: " .. table.concat(missing, ", ") .. " not found (an addon update changed it). Zygor keeps its own window.")
end

function Z.Activate()
    if Z.active or Z.missing then
        return
    end
    if InCombatLockdown() then
        Z.pending = "on"
        return
    end
    Z.active = true
    Z.Headless.Enable()
    Z.lastSig, Z.lastPinSig = nil, nil
    Z.Refresh()
end

function Z.Deactivate()
    if not Z.active then
        return
    end
    if InCombatLockdown() then
        Z.pending = "off"
        Z.Print("switching back to Zygor's window after combat.")
        return
    end
    Z.active = false
    Z.Headless.Disable()
    Z.Pins.Clear()
    Z.Pins.UpdateGuideQuests() -- back to Questie's yellow "!"
    Z.lastSig, Z.lastPinSig = nil, nil
    Z.Tracker.Request() -- redraws Questie's tracker without the guide section
end

function Z.SetEnabled(on)
    ZuestieDB.enabled = on
    if on then
        Z.Activate()
        Z.Print("on. Guide steps show in Questie's tracker.")
    else
        Z.Deactivate()
        Z.Print("off. Zygor's window is back. Type /zu on to switch again.")
    end
end

-- Compares the step model with what Questie's tracker and map show, and redraws only what is stale.
function Z.Refresh()
    Z.refreshQueued = false
    if not Z.active then
        return
    end
    Z.Headless.KeepAlive()
    -- A finished catch-up loads the guide it came from; build the model after that.
    Z.Try(Z.Catchup.Update)
    -- First: Questie's quest titles read the guide quest set while the tracker lays out.
    Z.Pins.UpdateGuideQuests()
    local ok, m = Z.Try(Z.BuildModel)
    if not ok then
        return
    end
    if Z.Signature(m) ~= Z.lastSig then
        Z.Tracker.Request()
    end
    local pinSig = Z.PinSignature(m)
    if pinSig ~= Z.lastPinSig and Z.Pins.Draw(m.pins) then
        Z.lastPinSig = pinSig
    end
end

function Z.RefreshSoon()
    if Z.refreshQueued or not Z.active then
        return
    end
    Z.refreshQueued = true
    C_Timer.After(REFRESH_DELAY, Z.Refresh)
end

function Z.PrevStep()
    if Z.active and ZGV.CurrentGuide then
        ZGV:PreviousStep(false, true)
    end
end

function Z.SkipStep()
    if Z.active and ZGV.CurrentGuide then
        ZGV:SkipStep(false, false, true)
    end
end

-- Same order as clicking Zygor's own progress bar; the mode is Zygor's setting.
local PROGRESS_MODES = {"quests", "steps", "exp"}

function Z.CycleProgressMode()
    local profile = ZGV.db.profile
    local current = profile.progressbarmode or "steps"
    local nextMode = PROGRESS_MODES[1]
    for i, mode in ipairs(PROGRESS_MODES) do
        if mode == current then
            nextMode = PROGRESS_MODES[i % #PROGRESS_MODES + 1]
        end
    end
    profile.progressbarmode = nextMode
    local bar = ZGV.ProgressBar
    if bar and bar.Update then
        Z.Try(bar.Update, bar)
    end
    Z.RefreshSoon()
end

local function YesNo(v)
    return v and "yes" or "no"
end

function Z.PrintStatus()
    if Z.missing then
        Z.Print("turned off, missing: " .. table.concat(Z.missing, ", "))
        return
    end
    Z.Print((Z.active and "on" or "off") .. (ZuestieDB.enabled and "" or " (you switched it off)"))
    local ZGV = _G.ZGV
    if ZGV and ZGV.Frame then
        local f = ZGV.Frame
        Z.Print(("Zygor engine: started %s, window shown %s, visible %s, alpha %.2f, parked %s"):format(
            YesNo(ZGV.initialized), YesNo(f:IsShown()), YesNo(f:IsVisible()), f:GetAlpha(), YesNo(Z.Headless.IsParked())))
    end
    if ZGV and ZGV.CurrentGuide and ZGV.CurrentGuide.steps then
        Z.Print(("Guide: %s, step %d/%d"):format(ZGV.CurrentGuide.title, ZGV.CurrentStepNum or 0, #ZGV.CurrentGuide.steps))
    else
        Z.Print("Guide: none loaded")
    end
    Z.Print(("Step changes since login while on: %d"):format(Z.stepChanges))
    Z.Print(Z.Catchup.Status())
    if Z.lastError then
        Z.Print("Last error: " .. tostring(Z.lastError))
    end
end

-- Prints the guide section's lines with their escape codes visible, for layout bugs.
function Z.PrintLines()
    local ok, m = Z.Try(Z.BuildModel)
    if not ok then
        Z.Print("could not read the step: " .. tostring(m))
        return
    end
    Z.Print(("%s | %s | %d lines, %d pins"):format(m.guideName, m.title, #m.lines, #m.pins))
    for i, line in ipairs(m.lines) do
        Z.Print(("%d %s %s [%s]"):format(i, line.kind, line.status or "-", line.text:gsub("|", "||")))
    end
end

-- Zygor fires these through AceEvent-3.0 messages.
local ZYGOR_MESSAGES = {"ZGV_STEP_CHANGED", "ZGV_GUIDE_LOADED", "ZGV_GOAL_COMPLETED", "ZGV_GOAL_UNCOMPLETED",
    "ZGV_GOAL_PROGRESS", "ZGV_INITIAL_GUIDE_LOADED"}

-- CallbackHandler calls function handlers as handler(message, ...).
local function OnZygorMessage(message)
    if not Z.active then
        return
    end
    if message == "ZGV_STEP_CHANGED" then
        Z.stepChanges = Z.stepChanges + 1
    elseif message == "ZGV_INITIAL_GUIDE_LOADED" then
        -- Zygor's startup can rebuild its map button and overlays; set them again.
        Z.Headless.ApplySideEffects()
    end
    if message ~= "ZGV_GOAL_PROGRESS" then
        Z.Catchup.Invalidate() -- Zygor's quest log view may have changed
    end
    Z.RefreshSoon()
end

-- Zygor builds its window during login; wait for it before going headless.
local function WaitForZygor()
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(0.2, function()
        tries = tries + 1
        local ZGV = _G.ZGV
        local ready = type(ZGV) == "table" and type(ZGV.Frame) == "table" and type(ZGV.db) == "table"
        if not ready and tries < 300 then
            return
        end
        ticker:Cancel()
        local missing = MissingZygor()
        if #missing > 0 then
            ReportMissing(missing)
            return
        end
        local AceEvent = LibStub("AceEvent-3.0")
        AceEvent:Embed(Z)
        Z.Try(Z.RepairSkills)
        for _, message in ipairs(ZYGOR_MESSAGES) do
            Z:RegisterMessage(message, OnZygorMessage)
        end
        -- Quest progress also moves Zygor's sticky steps, which send no messages of their own.
        -- Accepted, turned-in and abandoned quests change which earlier quests the guide still needs.
        Questie.API.RegisterForQuestUpdates(function(_, _, reason)
            local reasons = Questie.API.Enums and Questie.API.Enums.QuestUpdateTriggerReason
            if not reasons or reason ~= reasons.QUEST_UPDATED then
                Z.Catchup.Invalidate()
            end
            Z.RefreshSoon()
        end)
        C_Timer.NewTicker(POLL_SECONDS, Z.Refresh)
        if ZuestieDB.enabled then
            Z.Activate()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Item counts, level and zone feed Zygor's collect goals and step conditions.
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
-- Zygor recomputes its XP progress on this; the guide's progress line follows.
events:RegisterEvent("PLAYER_XP_UPDATE")
-- Cooldown swirl on the guide's item buttons.
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
-- Skill-ups move skill goals such as "Reach Level 75 in Lockpicking".
events:RegisterEvent("SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Zuestie" then
        ZuestieDB = ZuestieDB or {}
        if ZuestieDB.enabled == nil then
            ZuestieDB.enabled = true
        end
        ZuestieDB.settings = ZuestieDB.settings or {}
        local missing = MissingQuestie()
        if #missing > 0 then
            Z.missing = missing
        else
            Z.Tracker.Install()
            Z.Pins.Install()
        end
    elseif event == "PLAYER_LOGIN" then
        Z.Options.Register()
        if Z.missing then
            ReportMissing(Z.missing)
        else
            WaitForZygor()
        end
    elseif event == "PLAYER_LOGOUT" then
        Z.Headless.RestoreProfile()
    elseif event == "PLAYER_REGEN_ENABLED" then
        local pending = Z.pending
        Z.pending = nil
        if pending == "on" then
            Z.Activate()
        elseif pending == "off" then
            Z.Deactivate()
        else
            Z.RefreshSoon() -- Questie skips tracker layouts in combat
        end
    elseif event == "PLAYER_LEVEL_UP" then
        Z.RefreshSoon()
        -- Questie retextures quest starters on level-up; recolor the guide's after it is done.
        C_Timer.After(2, function()
            if Z.active then
                Z.Pins.UpdateGuideQuests(true)
            end
        end)
    elseif event == "BAG_UPDATE_COOLDOWN" then
        Z.Tracker.UpdateItemButtons()
    elseif event == "BAG_UPDATE_DELAYED" then
        Z.Tracker.UpdateItemButtons()
        Z.RefreshSoon()
    elseif event ~= "ADDON_LOADED" then
        Z.RefreshSoon()
    end
end)

SLASH_ZUESTIE1 = "/zu"
SLASH_ZUESTIE2 = "/zuestie"
SlashCmdList.ZUESTIE = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "zygor" or msg == "off" then
        Z.SetEnabled(false)
    elseif msg == "on" then
        Z.SetEnabled(true)
    elseif msg == "next" or msg == "skip" then
        Z.SkipStep()
    elseif msg == "prev" or msg == "back" then
        Z.PrevStep()
    elseif msg == "status" then
        Z.PrintStatus()
    elseif msg == "lines" then
        Z.PrintLines()
    elseif msg == "quests" then
        Z.Pins.Report()
    elseif msg == "catchup" then
        Z.Catchup.Toggle()
    elseif msg == "config" or msg == "settings" or msg == "options" then
        Z.Options.Open()
    elseif Z.active then
        Z.Menu.Open()
    else
        Z.Print("off. Commands: /zu on, /zu status, /zu config")
    end
end
