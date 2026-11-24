local _, ns = ...
local equipment = C_EquipmentSet
local rules = {
    { "default", "默认" }, { "mount", "骑乘" }, { "swim", "游泳" },
    { "city", "主城" }, { "spec1", "天赋组 1" }, { "spec2", "天赋组 2" },
}
local labels = {}
for _, rule in ipairs(rules) do
    labels[rule[1]] = rule[2]
end

local config, ticker, pending
local observedRule, observedName, observedSpec, stableSince, attempted
local events = CreateFrame("Frame")

local function Say(message)
    print("|cff66cfffMyForeverTools|r " .. message)
end

local function GetTalentGroup()
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        return C_SpecializationInfo.GetActiveSpecGroup()
    end
    local getGroup = GetActiveSpecGroup or GetActiveTalentGroup
    if getGroup then return getGroup() end
end

local function GetMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function GetDesiredRule(spec)
    local sets = config.sets
    if sets.swim and IsSwimming() then return "swim", sets.swim end
    if sets.mount and IsMounted() then return "mount", sets.mount end
    if sets.city and next(config.cities) and IsResting() and config.cities[GetMapID()] then
        return "city", sets.city
    end
    if spec then
        local rule = "spec" .. spec
        if sets[rule] then return rule, sets[rule] end
    end
    return "default", sets.default
end

local function FinishSwap(success)
    local request = pending
    pending = nil
    if success then
        Say(labels[request.rule] .. " → " .. request.name)
    else
        Say("换装未完成：" .. request.name .. "。检查背包后可用 /mftgear apply 重试。")
    end
end

local function Refresh()
    local now = GetTime()
    if pending then
        if now < pending.expires then return end
        local _, _, _, equipped = equipment.GetEquipmentSetInfo(pending.id)
        FinishSwap(equipped)
    end

    if InCombatLockdown() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
        or (UnitInVehicle and UnitInVehicle("player")) then
        stableSince = nil
        return
    end

    local spec = GetTalentGroup()
    local rule, name = GetDesiredRule(spec)
    if rule ~= observedRule or name ~= observedName or spec ~= observedSpec then
        observedRule, observedName, observedSpec = rule, name, spec
        stableSince, attempted = now, false
    end
    if not name or attempted then return end
    stableSince = stableSince or now
    if now - stableSince < 0.75 or not equipment.CanUseEquipmentSets() then return end

    -- Temporary sets need an existing fallback even if a talent set is currently available.
    if rule == "swim" or rule == "mount" or rule == "city" then
        if not config.sets.default or equipment.GetEquipmentSetID(config.sets.default) == nil then
            attempted = true
            Say("默认套装已找不到。设置新的默认套装后再自动换装。")
            return
        end
    end
    local id = equipment.GetEquipmentSetID(name)
    if id == nil then
        attempted = true
        Say("找不到装备套装：" .. name .. "。")
        return
    end
    local _, _, _, equipped, _, _, _, lost = equipment.GetEquipmentSetInfo(id)
    if equipment.EquipmentSetContainsLockedItems and equipment.EquipmentSetContainsLockedItems(id) then return end
    attempted = true
    if equipped then return end
    if lost and lost > 0 then
        Say("套装缺少 " .. lost .. " 件装备：" .. name .. "。")
        return
    end

    pending = { id = id, rule = rule, name = name, expires = now + 2 }
    local ok, accepted = pcall(equipment.UseEquipmentSet, id)
    if pending and (not ok or accepted == false) then FinishSwap(false) end
end

local function ResetSelection()
    observedRule, observedName, observedSpec = nil, nil, nil
    stableSince, attempted = nil, false
end

local function UpdateTicker()
    if config.enabled and not ticker then
        events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
        ticker = C_Timer.NewTicker(0.5, Refresh)
    elseif not config.enabled and ticker then
        ticker:Cancel()
        ticker, pending = nil, nil
        events:UnregisterEvent("EQUIPMENT_SWAP_FINISHED")
    end
    ResetSelection()
end

local function ShowStatus()
    local spec = GetTalentGroup()
    local rule, name = GetDesiredRule(spec)
    Say((config.enabled and "已开启" or "已关闭") .. "。当前天赋组：" .. (spec or "?")
        .. "。匹配：" .. labels[rule] .. " → " .. (name or "未设置"))
    for _, entry in ipairs(rules) do
        Say(entry[2] .. " (" .. entry[1] .. ") → " .. (config.sets[entry[1]] or "未设置"))
    end
    for id, city in pairs(config.cities) do
        Say("已登记主城：" .. city .. " (" .. id .. ")")
    end
end

local function Help()
    Say("/mftgear sets 查看系统装备套装，/mftgear status 查看规则")
    Say("/mftgear set <规则> <套装名>，规则可用 default、mount、swim、city、spec1、spec2")
    Say("/mftgear clear <规则> 删除规则，/mftgear city add 在主城休息区登记当前位置")
    Say("/mftgear city remove <地图ID>，/mftgear on | off | apply")
end

local function IsAvailable()
    return config ~= nil and equipment and equipment.CanUseEquipmentSets and equipment.UseEquipmentSet
end

local function CanEnable()
    return config.sets.default ~= nil and equipment.GetEquipmentSetID(config.sets.default) ~= nil
end

local function SetEnabled(enabled)
    if enabled and not CanEnable() then
        Say("请先设置一套默认装备，用于离开场景时恢复。")
        return
    end
    config.enabled = enabled
    UpdateTicker()
    Say(enabled and "自动换装已开启。" or "自动换装已关闭。")
end

local function SetRule(rule, name)
    if name then
        if equipment.GetEquipmentSetID(name) == nil then
            Say("请填写已有的装备套装名称。用 /mftgear sets 查看。")
            return
        end
        config.sets[rule] = name
    else
        if rule == "default" and config.enabled then
            Say("请先暂停自动换装，再清除默认套装。")
            return
        end
        config.sets[rule] = nil
    end
    ResetSelection()
    Say(labels[rule] .. " → " .. (config.sets[rule] or "未设置"))
end

local function GetCurrentCity()
    if not IsResting() then return end
    local id = GetMapID()
    local info = id and C_Map.GetMapInfo(id)
    if info and info.name then return id, info.name end
end

local function AddCurrentCity()
    local id, name = GetCurrentCity()
    if not id then
        Say("请到主城休息区再登记地图。")
        return
    end
    config.cities[id] = name
    ResetSelection()
    Say("已登记主城：" .. name .. " (" .. id .. ")")
end

local function RemoveCity(id)
    if not id or not config.cities[id] then return end
    Say("已移除主城：" .. config.cities[id])
    config.cities[id] = nil
    ResetSelection()
end

ns.EquipmentSets = {
    rules = rules,
    IsAvailable = IsAvailable,
    CanEnable = CanEnable,
    GetSettings = function() return config end,
    SetEnabled = SetEnabled,
    SetRule = SetRule,
    GetCurrentCity = GetCurrentCity,
    AddCurrentCity = AddCurrentCity,
    RemoveCity = RemoveCity,
}

local function HandleCommand(message)
    if not config then Say("角色设置尚未加载。"); return end
    if not IsAvailable() then
        Say("当前客户端没有可用的装备套装接口。")
        return
    end
    local action, args = message:match("^%s*(%S+)%s*(.-)%s*$")
    action = action and action:lower()
    if action == "set" or action == "clear" then
        local rule, name = args:match("^(%S+)%s*(.-)%s*$")
        rule = rule and rule:lower()
        if not labels[rule] then Help(); return end
        SetRule(rule, action == "set" and name or nil)
    elseif action == "city" then
        if args == "add" then
            AddCurrentCity()
        else
            local id = tonumber(args:match("^remove%s+(%d+)$"))
            if not id or not config.cities[id] then Help(); return end
            RemoveCity(id)
        end
    elseif action == "on" or action == "off" then
        SetEnabled(action == "on")
    elseif action == "apply" then
        if not config.enabled then Say("请先用 /mftgear on 开启。"); return end
        ResetSelection()
        Refresh()
    elseif action == "status" then
        ShowStatus()
    elseif action == "sets" then
        local ids = equipment.GetEquipmentSetIDs()
        if #ids == 0 then Say("请先在角色面板的装备管理器保存套装。"); return end
        for _, id in ipairs(ids) do
            local name, _, _, equipped = equipment.GetEquipmentSetInfo(id)
            Say(name .. (equipped and "（已装备）" or ""))
        end
    else
        Help()
    end
end

SLASH_MYFOREVERTOOLSGEAR1 = "/mftgear"
SlashCmdList.MYFOREVERTOOLSGEAR = HandleCommand

events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, success, setID)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        MyForeverToolsCharacterDB = MyForeverToolsCharacterDB or {}
        config = MyForeverToolsCharacterDB.gear or { sets = {}, cities = {} }
        MyForeverToolsCharacterDB.gear = config
        if equipment and equipment.CanUseEquipmentSets and equipment.UseEquipmentSet then UpdateTicker() end
    elseif pending and setID == pending.id then
        FinishSwap(success)
    end
end)
