-- Runs Zygor without its window.
-- Zygor's step checker quits while its window is hidden or faded below 10%
-- (ZGV:TryToCompleteStep, ZygorGuidesViewer.lua), so the window stays shown
-- at full alpha and is parked off-screen instead.
local _, Z = ...

local H = {}
Z.Headless = H

-- Zygor profile values while Zuestie is on. The originals come back on /zu zygor and at logout,
-- so Zygor's saved settings never keep Zuestie's values.
local OVERRIDES = {
    enable_actionbar = false, -- Zygor's item bar
    mapicons = false, -- Zygor's waypoint icons; Questie pins replace them
    foglight = false, -- Zygor's world map overlay
    showmapbutton = false, -- Zygor's minimap button
    nc_enable = false, -- Zygor's notification center
    n_popup_guides = false, -- Zygor's "next guide" popup; the tracker's next-guide line replaces it
    -- Zygor's quest-chain checks (QuestDB:IsQuestPossible), registered only on Classic clients. Catchup.lua
    -- keeps them running: accept steps whose earlier quests are not done get skipped.
    beta_use_chains = true,
    -- Read at combat start to fade the window, which would pause the step checker.
    -- Zuestie never calls the option's setter: it registers secure state drivers on the arrow
    -- and item bar, which errors before Zygor builds them. The arrow keeps its own combat setting.
    hideincombat = false,
}

local snapshot -- [key] = {raw = original raw profile value}
local parking = false
local hooked = false

local function Parked()
    local f = ZGV.Frame
    local point, relativeTo = f:GetPoint(1)
    return point == "TOPRIGHT" and relativeTo == UIParent and not f:IsClampedToScreen()
end

function H.IsParked()
    return Z.active and Parked()
end

local function Park()
    local f = ZGV.Frame
    parking = true
    f:SetClampedToScreen(false)
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -200, -200)
    parking = false
end

local function EnsureShown()
    if Z.active and not ZGV.Frame:IsShown() then
        ZGV:SetVisible(nil, true)
        Park()
    end
end

-- Zygor's end-of-guide rating panels sit inside its window but are clamped to the screen
-- (ZGV.UI:Create("Frame"), UiWidgets/Frame.lua), so the parked window would leave them in the
-- bottom-left corner as an empty box. They are made on demand by these GuideRating methods.
local RATING_CREATORS = {"CreateFrame", "CreateAltFrame", "CreateCancelledFrame", "Popup"}

local function SetRatingClamped(clamped)
    local rating = ZGV.BugReport and ZGV.BugReport.GuideRating
    if not rating then
        return
    end
    local cancelled = rating.CancelledRatingFrame
    for _, frame in pairs({rating.GuideRatingViewer, rating.NoRatingFrame, rating.ZygorPopupOn, cancelled,
        cancelled and cancelled.centeranchor}) do
        frame:SetClampedToScreen(clamped)
    end
end

local function InstallHooks()
    if hooked then
        return
    end
    hooked = true
    -- Zygor re-anchors its window to its master frame (ZGV:ReanchorFrame); send it back off-screen.
    hooksecurefunc(ZGV.Frame, "SetPoint", function()
        if Z.active and not parking then
            Park()
        end
    end)
    -- Hiding the window would stop the step checker.
    ZGV.Frame:HookScript("OnHide", function()
        if Z.active then
            C_Timer.After(0, EnsureShown)
        end
    end)
    -- Zygor's own map dots for the step; Questie pins show them instead.
    hooksecurefunc(ZGV.Pointer, "ShowMapMarkers", function(pointer)
        if Z.active then
            pointer:ClearSet("stepmarkers")
        end
    end)
    local rating = ZGV.BugReport and ZGV.BugReport.GuideRating
    if rating then
        for _, name in ipairs(RATING_CREATORS) do
            if rating[name] then
                hooksecurefunc(rating, name, function()
                    if Z.active then
                        SetRatingClamped(false)
                    end
                end)
            end
        end
    end
end

-- Makes Zygor's visible pieces match its current profile values.
function H.ApplySideEffects()
    local p = ZGV.db.profile
    local bar = ZGV.ActionBar
    if bar and bar.initialised then
        Z.Try(function()
            if p.enable_actionbar then
                bar:SetActionButtons()
            else
                bar:ClearBar()
            end
            bar:ToggleFrame()
        end)
    end
    local fog = ZGV.Foglight
    if fog and fog.DataProvider and ZGV.IsDataProviderRegistered then
        Z.Try(function()
            -- ToggleOverlay flips the overlay, it does not read the setting.
            local shown = ZGV.IsDataProviderRegistered(WorldMapFrame, fog.DataProvider.name) and true or false
            if shown ~= (p.foglight and true or false) then
                fog:ToggleOverlay()
            end
        end)
    end
    Z.Try(ZGV.UpdateMapButton, ZGV)
    local nc = ZGV.NotificationCenter
    if nc and nc.UpdateButton then
        Z.Try(nc.UpdateButton, nc)
    end
    local pointer = ZGV.Pointer
    Z.Try(ZGV.ShowWaypoints, ZGV)
    if Z.active then
        Z.Try(pointer.ClearSet, pointer, "stepmarkers")
    else
        Z.Try(pointer.ShowMapMarkers, pointer)
    end
end

-- Puts Zygor's own profile values back without touching its frames.
function H.RestoreProfile()
    if not snapshot then
        return
    end
    local p = ZGV.db.profile
    for key, saved in pairs(snapshot) do
        rawset(p, key, saved.raw)
    end
    snapshot = nil
end

function H.Enable()
    local p = ZGV.db.profile
    if not snapshot then
        snapshot = {enable_viewer = {raw = rawget(p, "enable_viewer")}}
        for key, value in pairs(OVERRIDES) do
            snapshot[key] = {raw = rawget(p, key)}
            p[key] = value
        end
    end
    InstallHooks()
    Park()
    SetRatingClamped(false)
    EnsureShown()
    if ZGV.Frame:GetAlpha() < 0.1 then
        ZGV.Frame:SetAlpha(1)
    end
    H.ApplySideEffects()
end

-- Called every refresh tick while on.
function H.KeepAlive()
    local f = ZGV.Frame
    if not f:IsShown() then
        EnsureShown()
    elseif not Parked() then
        Park()
    end
    if f:GetAlpha() < 0.1 then
        f:SetAlpha(1)
    end
end

function H.Disable()
    H.RestoreProfile()
    local f = ZGV.Frame
    f:SetClampedToScreen(true)
    SetRatingClamped(true)
    if not Z.Try(ZGV.ReanchorFrame, ZGV) then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", f:GetParent())
    end
    -- The user asked for Zygor's window, so show it even if it was hidden before.
    ZGV:SetVisible(nil, true)
    H.ApplySideEffects()
end
