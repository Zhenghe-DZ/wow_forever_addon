local locale = GetLocale()
if locale == "zhCN" or locale == "zhTW" then return end

-- Subset of LXGW WenKai Regular v1.530, distributed under SIL OFL 1.1.
local fontPath = "Interface\\AddOns\\MyForeverTools\\Media\\HandbookCJK.ttf"
local normalizedFontPath = fontPath:lower()

local function FixFont(region)
    if region.IsForbidden and region:IsForbidden() then return end
    if not region:IsObjectType("FontString") or not region:IsVisible() then return end

    local text = region:GetText()
    if issecretvalue and issecretvalue(text) then return end
    -- UTF-8 leading bytes for Han ideographs, including Extension A and supplementary blocks.
    if type(text) ~= "string" or not (text:find("[\228-\233][\128-\191]")
        or text:find("\227[\144-\191]")
        or text:find("\239[\164-\171]")
        or text:find("\240[\160-\175]")) then return end

    local file, size, flags = region:GetFont()
    if file and file:lower() == normalizedFontPath then return end
    -- Replace the explicit font assigned by the handbook, preserving its size and outline.
    region:SetFont(fontPath, size and size > 0 and size or 14, flags or "")
end

local function FixVisibleFonts(frame)
    if (frame.IsForbidden and frame:IsForbidden()) or not frame:IsVisible() or frame:IsObjectType("GameTooltip") then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        FixFont(region)
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        FixVisibleFonts(child)
    end
end

local function AttachToWindow(frame)
    local ticker
    local function Refresh()
        if not InCombatLockdown() then
            FixVisibleFonts(frame)
        end
    end
    local function OnShow()
        Refresh()
        -- Page switches, scrolling and pooled rows can introduce labels after OnShow.
        if not ticker then ticker = C_Timer.NewTicker(0.5, Refresh) end
    end
    local function OnHide()
        if not ticker then return end
        ticker:Cancel()
        ticker = nil
    end
    frame:HookScript("OnShow", OnShow)
    frame:HookScript("OnHide", OnHide)
    if frame:IsVisible() then OnShow() end
end

local window = DungeonsForever_MainFrame
if window then
    AttachToWindow(window)
else
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("ADDON_LOADED")
    listener:SetScript("OnEvent", function(self, _, addonName)
        if addonName ~= "DungeonsForever" then return end
        self:UnregisterEvent("ADDON_LOADED")
        if DungeonsForever_MainFrame then AttachToWindow(DungeonsForever_MainFrame) end
    end)
end
