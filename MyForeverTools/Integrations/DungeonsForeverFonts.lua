local locale = GetLocale()
if locale == "zhCN" or locale == "zhTW" then return end

local fontFamilies = {}
local fontFamilyCount = 0
local updatedFonts = setmetatable({}, { __mode = "k" })
local fontMembers = {
    { alphabet = "roman", file = "Fonts\\FRIZQT__.TTF", offset = 0 },
    { alphabet = "simplifiedchinese", file = "Fonts\\ARKai_T.ttf", offset = 3 },
    { alphabet = "traditionalchinese", file = "Fonts\\blei00d.TTF", offset = 3 },
    { alphabet = "korean", file = "Fonts\\2002.TTF", offset = 0 },
    { alphabet = "russian", file = "Fonts\\FRIZQT___CYR.TTF", offset = 0 },
}

local function GetFontFamily(size, flags)
    flags = flags or ""
    local key = size .. "|" .. flags
    if fontFamilies[key] ~= nil then return fontFamilies[key] end

    local family
    if type(CreateFontFamily) == "function" then
        local members = {}
        for i, font in ipairs(fontMembers) do
            members[i] = {
                alphabet = font.alphabet,
                file = font.file,
                height = size + font.offset,
                flags = flags,
            }
        end
        fontFamilyCount = fontFamilyCount + 1
        local name = "MyForeverToolsDungeonFont" .. fontFamilyCount
        local ok, result = pcall(CreateFontFamily, name, members)
        if ok then family = result end
    end

    if not family then
        if size <= 10 then
            family = GameFontHighlightSmall
        elseif size >= 16 then
            family = GameFontHighlightLarge
        elseif size >= 13 then
            family = GameFontHighlightMedium
        end
        family = family or GameFontHighlight
    end
    fontFamilies[key] = family or false
    return fontFamilies[key]
end

local function FixFont(region)
    if not region:IsObjectType("FontString") or not region:IsVisible() then return end

    local text = region:GetText()
    if issecretvalue and issecretvalue(text) then return end
    -- UTF-8 leading bytes for Han ideographs, including Extension A and supplementary blocks.
    if not text or not (text:find("[\228-\233][\128-\191]")
        or text:find("\227[\144-\191]")
        or text:find("\239[\164-\171]")
        or text:find("\240[\160-\175]")) then return end

    local file, size, flags = region:GetFont()
    if not size or size <= 0 then return end
    local current = updatedFonts[region]
    if current and current.family == region:GetFontObject()
        and current.file == file and current.size == size and current.flags == flags then
        return
    end

    local family = GetFontFamily(size, flags)
    if not family then return end
    region:SetFontObject(family)
    file, size, flags = region:GetFont()
    updatedFonts[region] = { family = region:GetFontObject(), file = file, size = size, flags = flags }
end

local function FixVisibleFonts(frame)
    if not frame:IsVisible() or frame:IsProtected() or frame:IsObjectType("GameTooltip") then return end
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
