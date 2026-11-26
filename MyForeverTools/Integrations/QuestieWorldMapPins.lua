if not (Questie and Questie.IsForever and QuestieLoader and QuestieLoader.ImportModule) then return end

local pins = QuestieLoader:ImportModule("HBDPins")
local provider = pins and pins.worldmapProvider
if not (provider and type(provider.HandlePin) == "function") then return end

local function HideDetachedWorldMapIcon(icon)
    if icon.miniMapIcon == false and icon:GetParent() == UIParent and icon:IsShown() then
        icon:Hide()
    end
end

-- Questie can show the icon before coordinate conversion. A successful placement
-- reparents it to a map pin; a failed one can leave it visible on UIParent.
hooksecurefunc(provider, "HandlePin", function(_, icon)
    HideDetachedWorldMapIcon(icon)
end)

-- Clean up any pins processed before this addon loaded.
if pins.worldmapPins then
    for icon in pairs(pins.worldmapPins) do
        HideDetachedWorldMapIcon(icon)
    end
end
