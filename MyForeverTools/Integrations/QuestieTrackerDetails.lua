local api = Questie and Questie.API
if not (api and api.RegisterOnReady and QuestieLoader and QuestieLoader.ImportModule) then return end

local function CanOpenDetails()
    return not InCombatLockdown()
        and not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled())
end

api.RegisterOnReady(function()
    if not Questie.IsForever then return end
    local tracker = QuestieLoader:ImportModule("TrackerUtils")
    if not (tracker and tracker.ShowQuestLog and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return end

    local request = 0
    hooksecurefunc(tracker, "ShowQuestLog", function(_, quest)
        request = request + 1
        if not CanOpenDetails() then return end
        local questID = quest and quest.Id
        if type(questID) ~= "number" or questID <= 0 then return end

        -- Let Questie's native map navigation run before opening the details pane.
        local current = request
        C_Timer.After(0, function()
            if current ~= request or not CanOpenDetails() or not C_QuestLog.GetLogIndexForQuestID(questID) then return end
            if type(QuestMapFrame_OpenToQuestDetails) ~= "function" or not QuestMapFrame then return end

            local details = QuestMapFrame.DetailsFrame
            if not details then return end
            if not details:IsVisible() or details.questID ~= questID then
                -- Same entry point as the standalone quest window's Show Map button.
                QuestMapFrame_OpenToQuestDetails(questID)
            end

            -- Questie can leave a standalone window open for a quest without a known map.
            local popup = QuestLogPopupDetailFrame
            if details:IsVisible() and details.questID == questID
                and popup and popup:IsShown() and popup.questID == questID then
                HideUIPanel(popup)
            end
        end)
    end)
end)
