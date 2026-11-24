local _, ns = ...
local gear = ns.EquipmentSets

local function AddScenarioChoices(menu, settings, setID, setName)
    menu:CreateTitle(setName)
    for _, rule in ipairs(gear.rules) do
        local key, label = rule[1], rule[2]
        local function IsAssigned()
            return settings.sets[key] == setName
        end
        local choice = menu:CreateCheckbox(label, IsAssigned, function()
            -- A set may be edited or removed while the menu is open.
            if C_EquipmentSet.GetEquipmentSetInfo(setID) ~= setName then return end
            if IsAssigned() then
                gear.SetRule(key, nil)
            else
                gear.SetRule(key, setName)
            end
        end)
        choice:SetTooltip(function(tooltip)
            local assigned = settings.sets[key]
            if assigned then
                tooltip:SetText("当前使用：" .. assigned)
                if assigned ~= setName then
                    tooltip:AddLine("勾选后会改用此套装。", 1, 1, 1, true)
                elseif key == "default" and settings.enabled then
                    tooltip:AddLine("请先暂停自动换装，再取消默认套装。", 1, 1, 1, true)
                end
            else
                tooltip:SetText("勾选后在此场景使用该套装。")
            end
            tooltip:Show()
        end)
    end
end

local function AddCityChoices(menu, settings)
    local cities = menu:CreateButton("主城地图")
    local id, name = gear.GetCurrentCity()
    local add = cities:CreateButton(name and ("登记：" .. name) or "在主城休息区登记当前位置", gear.AddCurrentCity)
    add:SetEnabled(id ~= nil and not settings.cities[id])

    local registered = {}
    for cityID in pairs(settings.cities) do
        registered[#registered + 1] = cityID
    end
    table.sort(registered)
    for _, cityID in ipairs(registered) do
        cities:CreateButton("移除：" .. settings.cities[cityID], gear.RemoveCity, cityID)
    end
end

local function OpenScenarios(button, pane)
    if not gear.IsAvailable() then return end

    local settings = gear.GetSettings()
    local setID = pane.selectedSetID
    local setName = setID ~= nil and C_EquipmentSet.GetEquipmentSetInfo(setID)
    MenuUtil.CreateContextMenu(button, function(_, menu)
        if setName then
            AddScenarioChoices(menu, settings, setID, setName)
        else
            menu:CreateTitle("请先选中一个装备套装")
        end

        menu:CreateDivider()
        menu:CreateCheckbox("启用自动换装", function() return settings.enabled == true end, function()
            gear.SetEnabled(not settings.enabled)
        end):SetTooltip(function(tooltip)
            if not settings.enabled and not gear.CanEnable() then
                tooltip:SetText("请先将一个装备套装设为默认。")
                tooltip:Show()
            end
        end)
        AddCityChoices(menu, settings)
    end)
end

local function AddScenarioButton()
    local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
    if not pane or not pane.NewSet or not MenuUtil or not MenuUtil.CreateContextMenu then return end

    local button = CreateFrame("Button", nil, pane, "SharedButtonSmallTemplate")
    button:SetSize(180, 18)
    button:SetPoint("BOTTOM", pane.NewSet, "TOP", 0, 1)
    button:SetText("适用场景")
    button:SetScript("OnClick", function(self) OpenScenarios(self, pane) end)
    return true
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_UIPanels_Game" and addonName ~= "Blizzard_Menu" then return end
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
    elseif AddScenarioButton() then
        self:UnregisterAllEvents()
    end
end)
