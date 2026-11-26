local api = Questie and Questie.API
if not (api and api.RegisterOnReady and QuestieLoader and QuestieLoader.ImportModule) then return end

local function CanOpenDetails()
    return not InCombatLockdown()
        and not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled())
end

api.RegisterOnReady(function()
    if not Questie.IsForever then return end
    local tracker = QuestieLoader:ImportModule("TrackerUtils")
    local compat = QuestieLoader:ImportModule("QuestieCompat")
    if not (tracker and tracker.ShowQuestLog and compat and compat.GetQuestUiMapID
        and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and QuestUtil and QuestUtil.OpenQuestDetails) then return end

    local request = 0
    hooksecurefunc(tracker, "ShowQuestLog", function(_, quest)
        request = request + 1
        if not CanOpenDetails() then return end
        local questID = quest and quest.Id
        if type(questID) ~= "number" or questID <= 0 then return end

        -- Questie already opens the popup itself for quests without a map.
        local mapID = compat.GetQuestUiMapID(questID)
        if not mapID or mapID == 0 then return end

        local current = request
        C_Timer.After(0, function()
            if current ~= request or not CanOpenDetails() or not C_QuestLog.GetLogIndexForQuestID(questID) then return end

            local embedded = QuestMapFrame and QuestMapFrame.DetailsFrame
            local popup = QuestLogPopupDetailFrame
            if embedded and embedded:IsVisible() and embedded.questID == questID then return end
            if popup and popup:IsShown() and popup.questID == questID then return end

            -- Use the same standalone details UI as Questie's fallback to keep map state changes native.
            QuestUtil.OpenQuestDetails(questID)
        end)
    end)
end)
