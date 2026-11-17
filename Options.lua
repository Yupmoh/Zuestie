-- Settings page in the game's options (Esc, Options, AddOns, Zuestie), built with AceConfig.
-- AceConfig ships with Questie, so Zuestie needs no libraries of its own. /zu config opens it.
local _, Z = ...

local O = {}
Z.Options = O

local function Get(info)
    return Z.Setting(info[#info])
end

local function Set(info, value)
    Z.SetSetting(info[#info], value)
end

local function Toggle(order, name, desc)
    return {order = order, type = "toggle", width = "full", name = name, desc = desc, get = Get, set = Set}
end

-- The arrow is Zygor's: these read and write Zygor's own arrow settings. Its arrow contains secure
-- buttons, so it can only be rebuilt out of combat.
local function ZygorReady()
    return type(ZGV) == "table" and type(ZGV.db) == "table" and type(ZGV.Pointer) == "table"
end

local function ArrowSet(apply)
    return function(_, value)
        if not ZygorReady() then
            return
        end
        if InCombatLockdown() then
            Z.Print("the arrow can change after combat.")
            return
        end
        Z.Try(apply, value)
    end
end

local function ArrowSkins()
    local skins = {}
    if ZygorReady() and ZGV.Pointer.ArrowSkins then
        for id, skin in pairs(ZGV.Pointer.ArrowSkins) do
            skins[id] = skin.name or id
        end
    end
    return skins
end

local setArrowShown = ArrowSet(function(value)
    ZGV.db.profile.arrowshow = value
    ZGV.Pointer:UpdateArrowVisibility()
end)

-- Zygor's path lines ("ant trails"): the travel route to the next place on the world map and minimap.
-- These write Zygor's own settings and redraw the lines, as Zygor's options page does.
local function PathLinesSet(key)
    return function(_, value)
        if not ZygorReady() then
            return
        end
        ZGV.db.profile[key] = value
        Z.Try(function()
            ZGV.Pointer:ClearAntsAndLines()
            ZGV.Pointer:AnimateAnts()
        end)
    end
end

-- Right-click on the tracker's book button.
function O.ToggleArrow()
    if not ZygorReady() then
        return
    end
    local show = not ZGV.db.profile.arrowshow
    setArrowShown(nil, show)
    if ZGV.db.profile.arrowshow == show then
        Z.Print(show and "arrow shown." or "arrow hidden. Right-click the book button to show it again.")
    end
end

local options = {
    type = "group",
    name = "Zuestie",
    args = {
        intro = {
            order = 0,
            type = "description",
            name = "Zygor's guides inside Questie's tracker. Changes apply right away.\n",
        },
        tracker = {
            order = 10,
            type = "group",
            inline = true,
            name = "Tracker",
            args = {
                showProgress = Toggle(1, "Progress bar", "Guide progress under the step line. Click it in the tracker to switch between quests, steps and XP."),
                showTips = Toggle(2, "Tips", "Zygor's tips as gray lines under a step. They also show when you hover the line."),
                showButtons = Toggle(3, "Guide buttons", "Book (choose a guide), back and skip buttons in front of the step line."),
                itemButtons = Toggle(4, "Item buttons", "A clickable item on steps that say to use an item. They update after combat ends."),
                questListMarks = Toggle(5, "Mark guide quests in the quest list", "A violet \"!\" in front of quests your guides use."),
                catchUp = Toggle(6, "Catch-up line", "When quests ahead in the guide need earlier quests you skipped, a violet line offers to do just those. Click it: Zygor loads the earlier guide, skips everything else, and brings you back to your step."),
            },
        },
        map = {
            order = 20,
            type = "group",
            inline = true,
            name = "Map",
            args = {
                mapPins = Toggle(1, "Step pins", "The current step's places on the world map and minimap."),
                violetQuests = Toggle(2, "Violet \"!\" for guide quests", "Quests your guide picks up show a violet \"!\". Yellow ones are quests the guides skip."),
                nextGuides = {
                    order = 3,
                    type = "range",
                    width = "double",
                    name = "Next guides to include",
                    desc = "Quests of this many guides after the current one, in Zygor's order, also show violet.",
                    min = 0,
                    max = 5,
                    step = 1,
                    get = Get,
                    set = Set,
                    disabled = function() return not Z.Setting("violetQuests") end,
                },
            },
        },
        pathLines = {
            order = 25,
            type = "group",
            inline = true,
            name = "Path lines (Zygor's settings)",
            disabled = function() return not ZygorReady() end,
            args = {
                maplines_enabled = {
                    order = 1,
                    type = "toggle",
                    width = "full",
                    name = "Show path lines",
                    desc = "Zygor's travel route to the next place, on the world map and minimap.",
                    get = function() return ZygorReady() and ZGV.db.profile.maplines_enabled end,
                    set = PathLinesSet("maplines_enabled"),
                },
                maplines = {
                    order = 2,
                    type = "select",
                    name = "Style",
                    values = {[1] = "Moving dots", [2] = "Solid line"},
                    get = function() return ZygorReady() and ZGV.db.profile.maplines end,
                    set = PathLinesSet("maplines"),
                    disabled = function() return not (ZygorReady() and ZGV.db.profile.maplines_enabled) end,
                },
            },
        },
        arrow = {
            order = 30,
            type = "group",
            inline = true,
            name = "Arrow (Zygor's settings)",
            disabled = function() return not ZygorReady() end,
            args = {
                arrowshow = {
                    order = 1,
                    type = "toggle",
                    width = "full",
                    name = "Show the arrow",
                    desc = "Right-clicking the book button in the tracker also hides or shows it.",
                    get = function() return ZygorReady() and ZGV.db.profile.arrowshow end,
                    set = setArrowShown,
                },
                arrowskin = {
                    order = 2,
                    type = "select",
                    name = "Style",
                    values = ArrowSkins,
                    get = function() return ZygorReady() and ZGV.db.profile.arrowskin end,
                    set = ArrowSet(function(value)
                        ZGV.Pointer:SetArrowSkin(value)
                    end),
                },
                arrowscale = {
                    order = 3,
                    type = "range",
                    name = "Size",
                    min = 0.6,
                    max = 1.8,
                    step = 0.05,
                    isPercent = true,
                    get = function() return ZygorReady() and ZGV.db.profile.arrowscale or 1 end,
                    set = ArrowSet(function(value)
                        ZGV.db.profile.arrowscale = value
                        ZGV.Pointer:SetupArrow()
                    end),
                },
            },
        },
        zygor = {
            order = 40,
            type = "execute",
            name = "Use Zygor's window instead",
            desc = "Turns Zuestie off and brings Zygor's own window back. /zu on switches again.",
            func = function() Z.SetEnabled(false) end,
        },
    },
}

function O.Register()
    local registry = LibStub("AceConfigRegistry-3.0", true)
    local dialog = LibStub("AceConfigDialog-3.0", true)
    if not (registry and dialog) or O.categoryId then
        return
    end
    registry:RegisterOptionsTable("Zuestie", options)
    local ok, _, categoryId = pcall(dialog.AddToBlizOptions, dialog, "Zuestie", "Zuestie")
    if ok then
        O.categoryId = categoryId
    end
end

function O.Open()
    if O.categoryId and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(O.categoryId)
    else
        Z.Print("the settings page is not available (AceConfig from Questie did not load).")
    end
end
