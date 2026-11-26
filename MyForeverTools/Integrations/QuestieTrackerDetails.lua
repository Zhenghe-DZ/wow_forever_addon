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

    -- A post-hook lets Questie open its map or popup before the integrated log opens.
    -- Choose the destination before either UI path runs.
    local showQuestLog = tracker.ShowQuestLog
    tracker.ShowQuestLog = function(self, quest, ...)
        local questID = quest and quest.Id
        if type(questID) ~= "number" or questID <= 0 then return end

        local details = QuestMapFrame and QuestMapFrame.DetailsFrame
        if not CanOpenDetails() or type(QuestMapFrame_OpenToQuestDetails) ~= "function"
            or not details or not C_QuestLog.GetLogIndexForQuestID(questID) then
            return showQuestLog(self, quest, ...)
        end

        if details:IsVisible() and details.questID == questID then return end
        return QuestMapFrame_OpenToQuestDetails(questID)
    end
end)
