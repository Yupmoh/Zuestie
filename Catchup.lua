-- Catch-up: when quests ahead in the guide need earlier quests that were skipped, do only those, then come back.
-- Zygor's "Smart Injection System" already skips every step that is not about a list of quests
-- (QuestDB:MaybeSkipThisGoal reads ZGV.db.char.SISquests, SISguides and SISdestination), but its switch,
-- profile.beta_use_chains, is only registered on Classic clients, and its planner (FindStartingPoint) counts
-- every quest of the whole guide, other classes' included. Zuestie plans the list itself: the earlier quests
-- the guide needs from the current step on, with Questie's prerequisites where Zygor's quest chains have
-- none. Zygor's skipping engine walks the earlier guides; once the list is done, Zuestie jumps back.
-- Outside a catch-up, Zygor's quest-chain checks stay on too (char.SISstarted): accept steps whose earlier
-- quests are not done get skipped, so the guide stops sending the player to quest givers with nothing to give.
local _, Z = ...

local C = {}
Z.Catchup = C

local MAX_DEPTH = 40
local MAX_TOOLTIP_QUESTS = 12

local asked = {} -- [questId] = true once Questie was asked for its prerequisites
local forPlayer = {} -- [questId] = whether Questie's race and class requirements allow the player
local pastGuides = {} -- [guide title] = {list = titles oldest first, ending with the guide, index = {[title] = i}}
local revision = 0
local cacheKey, cacheResult

local function ShortTitle(title)
    return (title:match("([^\\]+)$") or title)
end
C.ShortTitle = ShortTitle

local function QuestieReady()
    return type(Questie) == "table" and type(Questie.API) == "table" and Questie.API.isReady
end

local function QuestieField(q, field)
    if not QuestieReady() then
        return nil
    end
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    if type(QuestieDB.QueryQuestSingle) ~= "function" then
        return nil
    end
    local ok, value = pcall(QuestieDB.QueryQuestSingle, q, field)
    if ok then
        return value
    end
end

local function Done(q)
    if ZGV.completedQuests[q] then
        return true
    end
    return C_QuestLog ~= nil and C_QuestLog.IsQuestFlaggedCompleted ~= nil and C_QuestLog.IsQuestFlaggedCompleted(q) or false
end

local function InLog(q)
    local quest = ZGV.questsbyid[q]
    return quest ~= nil and quest.inlog or false
end

local function Satisfied(q)
    return ZGV.ChainsBreadcrumbs[q] or Done(q)
end

local function GuidesFor(q)
    return ZGV.QuestDB.GuideForQuest[q]
end

local function QuestName(q)
    local name = QuestieField(q, "name")
    return type(name) == "string" and name or ("Quest " .. q)
end

-- Quests of another race or class never count. Questie knows the requirements; Zygor's quest lists do not.
local function ForPlayer(q)
    local known = forPlayer[q]
    if known ~= nil then
        return known
    end
    if not QuestieReady() then
        return true
    end
    local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
    if type(QuestiePlayer.HasRequiredRace) ~= "function" or type(QuestiePlayer.HasRequiredClass) ~= "function" then
        return true
    end
    known = QuestiePlayer.HasRequiredRace(QuestieField(q, "requiredRaces"))
        and QuestiePlayer.HasRequiredClass(QuestieField(q, "requiredClasses")) and true or false
    forPlayer[q] = known
    return known
end

local function AddReverse(pre, post)
    local rev = ZGV.RevChains[pre]
    if type(rev) == "number" then
        rev = {rev}
        ZGV.RevChains[pre] = rev
    elseif type(rev) ~= "table" then
        rev = {}
        ZGV.RevChains[pre] = rev
    end
    table.insert(rev, post)
end

-- Questie's prerequisites in Zygor's chain format: a quest id, or {"AND"|"OR", id, ...}.
-- preQuestGroup needs all of them, preQuestSingle any of them. A group member counts as done when one of
-- its exclusive alternatives is done (Questie's rule); a negative member skips that check.
local function FromQuestie(q)
    local group, single = QuestieField(q, "preQuestGroup"), QuestieField(q, "preQuestSingle")
    local mode, list
    if type(group) == "table" and #group > 0 then
        mode, list = "AND", group
    elseif type(single) == "table" and #single > 0 then
        mode, list = "OR", single
    else
        return nil
    end
    local pre = {mode}
    for _, id in ipairs(list) do
        local fulfilled = false
        if id < 0 then
            id = -id
        elseif mode == "AND" and not Done(id) then
            local exclusive = QuestieField(id, "exclusiveTo")
            if type(exclusive) == "table" then
                for _, other in ipairs(exclusive) do
                    if Done(other) then
                        fulfilled = true
                        break
                    end
                end
            end
        end
        if not fulfilled and id ~= q then
            pre[#pre + 1] = id
        end
    end
    if #pre == 1 then
        return nil
    elseif #pre == 2 then
        return pre[2]
    end
    return pre
end

-- Zygor's prerequisites for a quest. Where Zygor has none, Questie's are added to Zygor's chain tables,
-- so Zygor's own quest checks use them too.
local function Prereqs(q)
    local pre = ZGV.Chains[q]
    if pre ~= nil or asked[q] or not QuestieReady() then
        return pre
    end
    asked[q] = true
    pre = FromQuestie(q)
    if pre == nil then
        return nil
    end
    ZGV.Chains[q] = pre
    if type(pre) == "number" then
        AddReverse(pre, q)
    else
        for i = 2, #pre do
            AddReverse(pre[i], q)
        end
    end
    return pre
end

local function Available(q)
    local pre = Prereqs(q)
    if type(pre) == "number" then
        return Satisfied(pre)
    elseif type(pre) ~= "table" then
        return true
    end
    local any = pre[1] == "OR"
    for _, p in ipairs(pre) do
        if type(p) == "number" then
            local ok = Satisfied(p)
            if any and ok then
                return true
            elseif not any and not ok then
                return false
            end
        end
    end
    return not any
end

-- Every unfinished quest on the way to q, q included: out[q] = true, or false for quests of another race
-- or class. A quest in the log ends the walk: only its turn-in is left. Of "any of" prerequisites, the one
-- in the log is followed, else the first one a guide picks up.
local function Collect(q, out, depth)
    if depth > MAX_DEPTH or out[q] ~= nil or Satisfied(q) then
        return
    end
    if not ForPlayer(q) then
        out[q] = false
        return
    end
    out[q] = true
    if InLog(q) then
        return
    end
    local pre = Prereqs(q)
    if type(pre) == "number" then
        Collect(pre, out, depth + 1)
    elseif type(pre) == "table" then
        if pre[1] == "OR" then
            local pick
            for _, p in ipairs(pre) do
                if type(p) == "number" then
                    if Satisfied(p) then
                        return
                    end
                    if InLog(p) then
                        pick = p
                    elseif not pick and GuidesFor(p) and ForPlayer(p) then
                        pick = p
                    end
                end
            end
            pick = pick or pre[2]
            if type(pick) == "number" then
                Collect(pick, out, depth + 1)
            end
        else
            for _, p in ipairs(pre) do
                if type(p) == "number" then
                    Collect(p, out, depth + 1)
                end
            end
        end
    end
end

local function Parsed(guide)
    if not guide.steps and type(guide.Parse) == "function" then
        pcall(guide.Parse, guide, true)
    end
    return guide.steps
end

local function RequirementsMet(step)
    local ok, met = pcall(step.AreRequirementsMet, step)
    return not ok or met
end

-- The guides before this one in Zygor's order (each guide's "next"), like Zygor's own catch-up walks them.
local function PastGuides(guide)
    local known = pastGuides[guide.title]
    if known then
        return known
    end
    local prev = {}
    for _, g in ipairs(ZGV.registeredguides) do
        local nextTitle = g.next or (g.headerdata and g.headerdata.next)
        nextTitle = type(nextTitle) == "string" and ZGV:SanitizeGuideTitle(nextTitle)
        local eligible = not g.condition_suggested_exclusive
        if not eligible and type(g.condition_suggested_race) == "function" then
            local ok, yes = pcall(g.condition_suggested_race)
            eligible = ok and yes
        end
        if nextTitle and eligible and not prev[nextTitle] then
            prev[nextTitle] = g.title
        end
    end
    local list, index = {guide.title}, {[guide.title] = true}
    local title = prev[guide.title]
    while title and not index[title] and #list < 50 do
        table.insert(list, 1, title)
        index[title] = true
        title = prev[title]
    end
    for i, t in ipairs(list) do
        index[t] = i
    end
    known = {list = list, index = index}
    pastGuides[guide.title] = known
    return known
end

-- Where the catch-up picks q up: the earliest guide before this one that accepts it, else any guide.
local function HomeGuide(q, past)
    local where = GuidesFor(q)
    if not where then
        return nil
    end
    local best, bestIndex
    for _, title in ipairs(where) do
        local i = past.index[title]
        if i and (not bestIndex or i < bestIndex) then
            best, bestIndex = title, i
        end
    end
    return best or where[1]
end

function C.Ready()
    return ZGV ~= nil and ZGV.initialized and type(ZGV.db) == "table" and type(ZGV.db.char) == "table"
        and type(ZGV.Chains) == "table" and type(ZGV.ChainsBreadcrumbs) == "table" and type(ZGV.RevChains) == "table"
        and type(ZGV.completedQuests) == "table" and type(ZGV.questsbyid) == "table"
        and type(ZGV.registeredguides) == "table" and type(ZGV.SanitizeGuideTitle) == "function"
        and type(ZGV.QuestDB) == "table" and type(ZGV.QuestDB.GuideForQuest) == "table"
        and type(ZGV.QuestDB.Cancel) == "function"
end

function C.Active()
    local char = ZGV.db.char
    return type(char.SISdestination) == "table" and char.SISquests ~= nil
end

-- Quest log changes; the next Needed call counts again.
function C.Invalidate()
    revision = revision + 1
end

-- The earlier quests the guide needs from step fromStep on:
-- {count, quests = sorted ids, home = {[id] = guide title}, guides = {[title] = true}, unguided = sorted ids}.
-- unguided: needed, but no Zygor guide picks them up. nil when the guide cannot be read (Zygor's parser
-- failed): unknown, which must not end a catch-up. Cached per guide, step and quest log change.
function C.Needed(guide, fromStep)
    local key = guide.title .. "#" .. fromStep .. "#" .. revision
    if key == cacheKey then
        return cacheResult
    end
    local steps = Parsed(guide)
    if not steps then
        return nil
    end
    local result = {count = 0, quests = {}, home = {}, guides = {}, unguided = {}}
    -- What the guide takes care of from here: quests it accepts, and quests in the log it works on.
    local own, accepts = {}, {}
    for i = fromStep, #steps do
        local step = steps[i]
        if RequirementsMet(step) then
            for _, goal in ipairs(step.goals or {}) do
                local q = tonumber(goal.questid)
                if q and goal.action == "accept" then
                    own[q] = true
                    accepts[#accepts + 1] = q
                elseif q and InLog(q) then
                    own[q] = true
                end
            end
        end
    end
    local chain = {}
    for _, q in ipairs(accepts) do
        if not Done(q) and not InLog(q) and not Available(q) then
            Collect(q, chain, 0)
        end
    end
    local past = PastGuides(guide)
    for q, counted in pairs(chain) do
        if counted and not own[q] then
            local home = HomeGuide(q, past)
            if home or InLog(q) then
                result.count = result.count + 1
                result.quests[#result.quests + 1] = q
                if home then
                    result.home[q] = home
                    result.guides[home] = true
                end
            else
                result.unguided[#result.unguided + 1] = q
            end
        end
    end
    table.sort(result.quests)
    table.sort(result.unguided)
    cacheKey, cacheResult = key, result
    return result
end

-- One guide name, or "N earlier guides".
local function Describe(need)
    local names = {}
    for title in pairs(need.guides) do
        names[#names + 1] = ShortTitle(title)
    end
    if #names == 1 then
        return names[1]
    elseif #names == 0 then
        return "your quest log"
    end
    return #names .. " earlier guides"
end

local function Names(quests)
    local names = {}
    for i, q in ipairs(quests) do
        names[i] = QuestName(q)
    end
    return table.concat(names, ", ")
end

local function Plural(n, word)
    return n .. " " .. word .. (n == 1 and "" or "s")
end

local function Destination()
    local dest = ZGV.db.char.SISdestination
    local guide = type(dest[1]) == "string" and ZGV:GetGuideByTitle(dest[1])
    return guide, tonumber(dest[2]) or 1
end

-- The tracker line: an offer while not catching up, progress while catching up. nil when there is nothing to say.
function C.Line()
    if not C.Ready() then
        return nil
    end
    if C.Active() then
        local guide, step = Destination()
        local need = guide and C.Needed(guide, step)
        local dest = ShortTitle(ZGV.db.char.SISdestination[1])
        return {
            kind = "catchup",
            active = true,
            text = need and ("Catching up: %s left, then back to %s"):format(Plural(need.count, "earlier quest"), dest)
                or ("Catching up, then back to %s"):format(dest),
            need = need,
            step = step,
        }
    end
    local guide, step = ZGV.CurrentGuide, ZGV.CurrentStepNum
    if not Z.Setting("catchUp") or not (guide and guide.steps and step) then
        return nil
    end
    local need = C.Needed(guide, step)
    local text
    if not need then
        return nil
    elseif need.count > 0 then
        text = ("Earlier quests needed: %d, from %s"):format(need.count, Describe(need))
    elseif #need.unguided > 0 then
        text = ("Blocked by %s outside Zygor's guides"):format(Plural(#need.unguided, "earlier quest"))
    else
        return nil
    end
    return {kind = "catchup", text = text, need = need, step = step}
end

function C.Tooltip(tip, data)
    local need = data.need
    if data.active then
        tip:AddLine("Catching up", 1, 0.82, 0)
        tip:AddLine(("Zygor skips every step that does not lead to these quests. Once they are done, you go back to %s, step %d.")
            :format(ShortTitle(ZGV.db.char.SISdestination[1]), data.step), 1, 1, 1, true)
    else
        tip:AddLine("Earlier quests needed", 1, 0.82, 0)
        tip:AddLine("Quests ahead in this guide need these first. Catching up loads the earlier guide, skips everything else, and brings you back to this step.", 1, 1, 1, true)
    end
    if need then
        for i, q in ipairs(need.quests) do
            if i > MAX_TOOLTIP_QUESTS then
                tip:AddLine(("and %d more"):format(#need.quests - MAX_TOOLTIP_QUESTS), 0.6, 0.6, 0.6)
                break
            end
            local where = InLog(q) and "in your quest log" or ShortTitle(need.home[q] or "")
            tip:AddDoubleLine(QuestName(q), where, 1, 1, 1, 0.6, 0.6, 0.6)
        end
        if #need.unguided > 0 then
            tip:AddLine("Not in Zygor's guides; Questie shows where they start:", 1, 0.82, 0, true)
            for i, q in ipairs(need.unguided) do
                if i > MAX_TOOLTIP_QUESTS then
                    break
                end
                tip:AddLine(QuestName(q), 1, 1, 1)
            end
        end
    end
    if data.active then
        tip:AddLine(("Click: stop and go back to %s, step %d"):format(ShortTitle(ZGV.db.char.SISdestination[1]), data.step),
            0.6, 0.6, 0.6, true)
    elseif need and need.count > 0 then
        tip:AddLine("Click: catch up", 0.6, 0.6, 0.6)
    end
end

-- First step of the guide that works on one of the quests, before step limit when given.
local function FirstStep(guide, quests, limit)
    local steps = Parsed(guide)
    if not steps then
        return nil
    end
    for i, step in ipairs(steps) do
        if limit and i >= limit then
            return nil
        end
        if RequirementsMet(step) then
            for _, goal in ipairs(step.goals or {}) do
                local q = tonumber(goal.questid)
                if q and quests[q] then
                    return i
                end
            end
        end
    end
end

local function Cancel()
    Z.Try(ZGV.QuestDB.Cancel, ZGV.QuestDB)
    C.Invalidate()
end

function C.Start()
    if not (Z.active and C.Ready()) then
        Z.Print("catch-up needs Zygor's quest data; it is still loading.")
        return
    end
    if C.Active() then
        Z.Print("already catching up. /zu catchup stops it.")
        return
    end
    local guide, stepNum = ZGV.CurrentGuide, ZGV.CurrentStepNum
    if not (guide and guide.steps and stepNum) then
        Z.Print("load a guide first.")
        return
    end
    local need = C.Needed(guide, stepNum)
    if not need then
        Z.Print("could not read " .. ShortTitle(guide.title) .. ".")
        return
    elseif need.count == 0 then
        if #need.unguided > 0 then
            Z.Print("Zygor's guides do not pick up " .. Names(need.unguided) .. ". Questie shows where they start.")
        else
            Z.Print("this guide needs no earlier quests from here on.")
        end
        return
    end

    -- Zygor's catch-up state: the quests, the guides it skips through, and where it ends.
    local past = PastGuides(guide)
    local quests, used = {}, {}
    for _, q in ipairs(need.quests) do
        local home = need.home[q]
        quests[q] = home or true
        if home then
            used[home] = true
        end
    end
    local guides = {}
    for i = 1, #past.list - 1 do
        guides[past.list[i]] = used[past.list[i]] or -1 -- guides in between are skipped through
    end
    for title in pairs(used) do
        guides[title] = guides[title] or true
    end
    guides[guide.title] = stepNum -- this guide only up to this step

    -- Start in the earliest guide that picks up a needed quest: Zygor's order first, then any other.
    local order, others = {}, {}
    for _, title in ipairs(past.list) do
        if used[title] then
            order[#order + 1] = title
        end
    end
    for title in pairs(used) do
        if not past.index[title] then
            others[#others + 1] = title
        end
    end
    table.sort(others)
    for _, title in ipairs(others) do
        order[#order + 1] = title
    end
    local startGuide, startStep
    for _, title in ipairs(order) do
        local g = ZGV:GetGuideByTitle(title)
        startStep = g and FirstStep(g, quests, g == guide and stepNum or nil)
        if startStep then
            startGuide = g
            break
        end
    end
    if not startGuide then
        Z.Print("no guide step picks up " .. Names(need.quests) .. ". Questie shows where they start.")
        return
    end

    local char = ZGV.db.char
    char.SISquests, char.SISguides, char.SISdestination, char.SISstarted = quests, guides, {guide.title, stepNum}, true
    C.Invalidate()
    ZGV:SetGuide(startGuide.title, startStep)
    if ZGV.CurrentGuide ~= startGuide then
        Cancel()
        Z.Print("Zygor did not load " .. ShortTitle(startGuide.title) .. "; catch-up stopped.")
        return
    end
    Z.Print(("catching up on %s: %s. Zygor skips everything else, then you are back on %s, step %d.")
        :format(Plural(need.count, "earlier quest"), Names(need.quests), ShortTitle(guide.title), stepNum))
    Z.RefreshSoon()
end

function C.Stop()
    if C.Ready() and C.Active() then
        local target, step = Destination()
        Cancel()
        if target then
            ZGV:SetGuide(target.title, step)
            Z.Print(("catch-up stopped. Back on %s, step %d."):format(ShortTitle(target.title), step))
        else
            Z.Print("catch-up stopped.")
        end
        Z.RefreshSoon()
    end
end

function C.Toggle()
    if C.Ready() and C.Active() then
        C.Stop()
    else
        C.Start()
    end
end

-- Called on every refresh. Ends the catch-up at its step, and jumps back once the earlier quests are done.
function C.Update()
    if not C.Ready() then
        return
    end
    local char = ZGV.db.char
    if not char.SISstarted then
        char.SISstarted = true -- QuestDB:IsQuestPossible checks chains only while this or SISdestination is set
    end
    if not C.Active() then
        return
    end
    local dest = char.SISdestination
    local guide = ZGV.CurrentGuide
    if guide and guide.title == dest[1] and (ZGV.CurrentStepNum or 0) >= (tonumber(dest[2]) or 1) then
        Cancel()
        Z.Print(("caught up. Back on %s, step %d."):format(ShortTitle(dest[1]), ZGV.CurrentStepNum or 0))
        return
    end
    local target, step = Destination()
    if not target then
        Cancel()
        return
    end
    local need = C.Needed(target, step)
    if need and need.count == 0 then
        Cancel()
        Z.Print(("caught up. Back to %s, step %d."):format(ShortTitle(target.title), step))
        ZGV:SetGuide(target.title, step)
    end
end

function C.Status()
    if not C.Ready() then
        return "Catch-up: waiting for Zygor's quest data"
    end
    local line = C.Line()
    return "Catch-up: " .. (line and line.text or (C.Active() and "on" or "nothing needed"))
end
