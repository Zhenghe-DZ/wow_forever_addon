local api = Questie and Questie.API
if not (api and api.RegisterOnReady and QuestieLoader and QuestieLoader.ImportModule) then return end

local function Install()
    local db = QuestieLoader:ImportModule("QuestieDB")
    local lib = QuestieLoader:ImportModule("QuestieLib")
    local zones = QuestieLoader:ImportModule("ZoneDB")
    local questModule = QuestieLoader:ImportModule("QuestieQuest")
    local layout = QuestieLoader:ImportModule("TooltipLayout")
    if not (db and db.GetQuest and db.QueryNPCSingle and db.QueryObjectSingle
        and lib and lib.GetColoredQuestName and zones and zones.GetLocalizedDungeonName
        and layout and layout.Render and C_Map and C_Map.GetAreaInfo) then return end

    local resolvers = questModule and questModule.private and questModule.private.objectiveSpawnListCallTable

    local function AreaName(id)
        if type(id) ~= "number" or id <= 0 then return end
        local name = zones:GetLocalizedDungeonName(id) or C_Map.GetAreaInfo(id)
        if name and name ~= "" then return name end
    end

    local function AddAreas(set, points)
        for area, coordinates in pairs(points or {}) do
            if type(coordinates) == "table" and next(coordinates) then
                local name = AreaName(area)
                if name then set[name] = true end
            end
        end
    end

    local function AddSpawnList(set, spawnList)
        for _, source in pairs(spawnList or {}) do
            AddAreas(set, source.Spawns)
            AddAreas(set, source.Waypoints)
        end
    end

    local function FormatList(set, preferred)
        local names = {}
        for name in pairs(set) do
            if name ~= preferred then names[#names + 1] = name end
        end
        table.sort(names)
        if preferred then table.insert(names, 1, preferred) end
        if #names > 2 then return table.concat(names, " / ", 1, 2) .. " 等" end
        if #names > 0 then return table.concat(names, " / ") end
    end

    local function ObjectiveAreas(quest)
        local places = {}
        for _, objective in pairs(quest.Objectives or {}) do
            AddSpawnList(places, objective.spawnList)
        end
        for _, objective in pairs(quest.SpecialObjectives or {}) do
            AddSpawnList(places, objective.spawnList)
        end

        -- Available quests do not yet have the spawn lists generated from the player's quest log.
        if not next(places) and resolvers then
            for _, objective in ipairs(quest.ObjectiveData or {}) do
                local resolve = resolvers[objective.Type]
                if resolve and (objective.Id or objective.Type == "event" or objective.Type == "killcredit")
                    and (objective.Type ~= "spell" or objective.ItemSourceId) then
                    local context = { Description = objective.Text, Coordinates = objective.Coordinates, Icon = objective.Icon }
                    local ok, sources = pcall(resolve, objective.Id, context, objective)
                    if ok then AddSpawnList(places, sources) end
                end
            end
        end

        local zone = AreaName(quest.zoneOrSort)
        return FormatList(places, zone and places[zone] and zone or nil) or zone
    end

    local function TurnInPlaces(quest)
        local destinations = {}
        local finisher = quest.Finisher or {}
        for _, entry in ipairs({ { finisher.NPC, db.QueryNPCSingle }, { finisher.GameObject, db.QueryObjectSingle } }) do
            local query = entry[2]
            for _, id in ipairs(entry[1] or {}) do
                local name = query(id, "name")
                local places = {}
                AddAreas(places, query(id, "spawns"))
                AddAreas(places, query(id, "waypoints"))
                if next(places) then
                    for place in pairs(places) do
                        destinations[name and (place .. " · " .. name) or place] = true
                    end
                elseif name and name ~= "" then
                    destinations[name] = true
                end
            end
        end
        return FormatList(destinations)
    end

    local function Suffix(id)
        local quest = db.GetQuest(id)
        if not quest then return end
        local objective = ObjectiveAreas(quest) or "地点未知"
        local turnIn = TurnInPlaces(quest) or "地点未知"
        return " |cffb8d4eb（做：" .. objective .. "；交：" .. turnIn .. "）|r"
    end

    local function Titles(tooltip)
        local ids = {}
        local function Add(title, id)
            if not title or not id then return end
            if ids[title] == nil or ids[title] == id then
                ids[title] = id
            else
                ids[title] = false -- Do not attach another quest's places to an ambiguous title.
            end
        end
        for id in pairs(tooltip.questOrder or {}) do
            Add(lib:GetColoredQuestName(id, Questie.db.profile.enableTooltipsQuestLevel, true), id)
        end
        for _, giver in pairs(tooltip.npcAndObjectOrder or {}) do
            for _, entry in pairs(giver) do Add(entry.title, entry.questId) end
        end
        return ids
    end

    -- Preserve Questie's description wrapping by measuring the decorated rows with its own renderer.
    local render = layout.Render
    hooksecurefunc(layout, "Render", function(self, tooltip, rows)
        if tooltip ~= GameTooltip or not IsShiftKeyDown() or not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
        local pin = tooltip._owner
        if not pin or pin.miniMapIcon or not pin.data or pin.data ~= tooltip._showData
            or tooltip._showOwner or tooltip:GetOwner() ~= pin then return end

        local titles, suffixes = Titles(tooltip), {}
        local decorated
        for index, row in ipairs(rows) do
            local field = row.kind == "doubleLine" and "leftText" or row.kind == "line" and "text"
            local title = field and row[field]
            local id = title and titles[title]
            if id then
                if suffixes[id] == nil then suffixes[id] = Suffix(id) or false end
                if suffixes[id] then
                    if not decorated then decorated = { unpack(rows) } end
                    local copy = {}
                    for key, value in pairs(row) do copy[key] = value end
                    copy[field] = title .. suffixes[id]
                    decorated[index] = copy
                end
            end
        end
        if decorated then
            tooltip:ClearLines()
            render(self, tooltip, decorated)
        end
    end)
end

api.RegisterOnReady(Install)
