-- Guide menu: step navigation and guide picker, built with Questie's bundled dropdown library.
local _, Z = ...

local M = {}
Z.Menu = M

local CHUNK = 25 -- longest list before it is split into submenus
local LibDropDown = LibStub:GetLibrary("LibUIDropDownMenuQuestie-4.0")
local menuFrame

local function Close()
    LibDropDown:CloseDropDownMenus()
end

local function ShortTitle(title)
    return title:match("([^\\]+)$") or title
end

local function IsListed(guide)
    if type(guide.condition_visible) == "function" then
        local ok, visible = pcall(guide.condition_visible)
        if not ok or visible ~= true then
            return false
        end
    end
    local ok, status = pcall(guide.GetStatus, guide)
    return ok and status ~= "INVALID"
end

local function LoadGuide(guide)
    -- A guide already open in a Zygor tab resumes at its saved step.
    if ZGV.Tabs and ZGV.Tabs.TryToActivateGuide and ZGV.Tabs:TryToActivateGuide(guide) then
        return
    end
    ZGV:SetGuide(guide.title, 1)
end
M.LoadGuide = LoadGuide

local function GuideEntry(guide, text)
    return {
        text = text or ShortTitle(guide.title),
        checked = guide == ZGV.CurrentGuide,
        func = function()
            Close()
            LoadGuide(guide)
        end,
    }
end

local function Submenu(text, list)
    return {text = text, hasArrow = true, notCheckable = true, menuList = list}
end

local function Chunk(list)
    if #list <= CHUNK then
        return list
    end
    local out = {}
    for first = 1, #list, CHUNK do
        local part = {}
        for i = first, math.min(first + CHUNK - 1, #list) do
            part[#part + 1] = list[i]
        end
        out[#out + 1] = Submenu(part[1].text .. "  ...  " .. part[#part].text, part)
    end
    return out
end

-- Guide titles are paths like "LEVELING\Ashenvale & Stonetalon Mountains (21-24)".
local function AllGuidesMenu()
    local function Folder(name)
        return {name = name, folders = {}, items = {}}
    end
    local root = Folder("")
    for _, guide in ipairs(ZGV.registeredguides) do
        if guide.title and IsListed(guide) then
            local node = root
            local parts = {strsplit("\\", guide.title)}
            for i = 1, #parts - 1 do
                local child = node.folders[parts[i]]
                if not child then
                    child = Folder(parts[i])
                    node.folders[parts[i]] = child
                    node.items[#node.items + 1] = child
                end
                node = child
            end
            node.items[#node.items + 1] = guide
        end
    end

    local function ToList(node, depth)
        local list = {}
        for _, item in ipairs(node.items) do
            if item.folders then
                local name = item.name
                if depth == 0 and ZGV.GuideTitles and ZGV.GuideTitles[name] then
                    name = ZGV.GuideTitles[name]
                end
                list[#list + 1] = Submenu(name, ToList(item, depth + 1))
            else
                list[#list + 1] = GuideEntry(item)
            end
        end
        return Chunk(list)
    end
    return ToList(root, 0)
end

local function SuggestedMenu()
    local list = {}
    local ok, suggested = pcall(ZGV.FindSuggestedGuides, ZGV)
    if ok and suggested then
        for _, guides in pairs(suggested) do
            for _, guide in ipairs(guides) do
                list[#list + 1] = GuideEntry(guide)
            end
        end
    end
    return list
end

local function OpenTabsMenu()
    local list = {}
    local pool = ZGV.Tabs and ZGV.Tabs.Pool
    if type(pool) ~= "table" then
        return list
    end
    for _, tab in pairs(pool) do
        local guide = tab.guide
        if type(guide) == "table" and guide.title and tab.ActivateGuide then
            list[#list + 1] = {
                text = ("%s (step %s)"):format(ShortTitle(guide.title), tostring(tab.step or "?")),
                checked = guide == ZGV.CurrentGuide,
                func = function()
                    Close()
                    tab:ActivateGuide("zuestie")
                end,
            }
        end
    end
    return list
end

function M.Open()
    menuFrame = menuFrame or LibDropDown:Create_UIDropDownMenu("ZuestieMenuFrame", UIParent)
    local guide = ZGV.CurrentGuide
    local list = {{text = guide and ShortTitle(guide.title) or "Zuestie", isTitle = true, notCheckable = true}}

    if guide then
        list[#list + 1] = {text = "Previous step", notCheckable = true, func = function() Close() Z.PrevStep() end}
        list[#list + 1] = {text = "Skip step", notCheckable = true, func = function() Close() Z.SkipStep() end}
        local nextGuide = guide.next and ZGV:GetGuideByTitle(guide.next)
        if nextGuide then
            local entry = GuideEntry(nextGuide, "Load next guide: " .. ShortTitle(nextGuide.title))
            entry.checked, entry.notCheckable = nil, true
            list[#list + 1] = entry
        end
    end

    local suggested = SuggestedMenu()
    if #suggested > 0 then
        list[#list + 1] = Submenu("Suggested guides", Chunk(suggested))
    end
    local tabs = OpenTabsMenu()
    if #tabs > 0 then
        list[#list + 1] = Submenu("Open guides", Chunk(tabs))
    end
    list[#list + 1] = Submenu("All guides", AllGuidesMenu())

    if ZGV.GuideMenu and ZGV.GuideMenu.Show then
        list[#list + 1] = {text = "Search guides (Zygor browser)", notCheckable = true, func = function() Close() ZGV.GuideMenu:Show() end}
    end
    list[#list + 1] = {text = "Use Zygor's window instead", notCheckable = true, func = function() Close() Z.SetEnabled(false) end}
    list[#list + 1] = {text = "Settings", notCheckable = true, func = function() Close() Z.Options.Open() end}
    list[#list + 1] = {text = "Close", notCheckable = true, func = Close}

    LibDropDown:EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end

-- Guide picker only: suggested guides first, then every category one click away.
function M.OpenGuides()
    menuFrame = menuFrame or LibDropDown:Create_UIDropDownMenu("ZuestieMenuFrame", UIParent)
    local list = {{text = "Choose a guide", isTitle = true, notCheckable = true}}
    local suggested = SuggestedMenu()
    if #suggested > 0 then
        list[#list + 1] = {text = "Suggested for you", isTitle = true, notCheckable = true}
        for _, entry in ipairs(Chunk(suggested)) do
            list[#list + 1] = entry
        end
        list[#list + 1] = {text = "All guides", isTitle = true, notCheckable = true}
    end
    for _, entry in ipairs(AllGuidesMenu()) do
        list[#list + 1] = entry
    end
    local tabs = OpenTabsMenu()
    if #tabs > 0 then
        list[#list + 1] = Submenu("Open guides", Chunk(tabs))
    end
    if ZGV.GuideMenu and ZGV.GuideMenu.Show then
        list[#list + 1] = {text = "Search guides (Zygor browser)", notCheckable = true, func = function() Close() ZGV.GuideMenu:Show() end}
    end
    list[#list + 1] = {text = "Close", notCheckable = true, func = Close}
    LibDropDown:EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end
