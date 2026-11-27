local _, addon = ...
local swim = addon.SwimGear
if not (swim and Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end

local translations = {
    enUS = {
        title = "Swimming gear", enabled = "Auto-swap while swimming",
        instructions = "Choose a slot, then choose an item from your bags. Each slot can have one rule.",
        choose = "Choose a bag item", empty = "No matching ready-to-equip items in your bags",
        remove = "Remove rule", rules = "Saved rules", none = "No rules yet",
        slots = { "Head", "Neck", "Shoulders", "Chest", "Waist", "Legs", "Feet", "Wrists", "Hands",
            "Upper ring", "Lower ring", "Upper trinket", "Lower trinket", "Back" },
    },
    deDE = {
        title = "Schwimmausrüstung", enabled = "Ausrüstung beim Schwimmen automatisch wechseln",
        instructions = "Wähle einen Ausrüstungsplatz und einen Gegenstand aus deinen Taschen. Pro Platz gilt eine Regel.",
        choose = "Gegenstand aus den Taschen wählen", empty = "Keine passenden, anlegbaren Gegenstände in den Taschen",
        remove = "Regel entfernen", rules = "Gespeicherte Regeln", none = "Noch keine Regeln",
        slots = { "Kopf", "Hals", "Schultern", "Brust", "Taille", "Beine", "Füße", "Handgelenke", "Hände",
            "Oberer Ring", "Unterer Ring", "Oberes Schmuckstück", "Unteres Schmuckstück", "Rücken" },
    },
    zhCN = {
        title = "游泳换装", enabled = "游泳时自动换装",
        instructions = "先选装备槽位，再选背包中的装备。每个槽位可以设置一条规则。",
        choose = "选择背包装备", empty = "背包里没有符合条件且可装备的物品",
        remove = "删除规则", rules = "已保存的规则", none = "还没有规则",
        slots = { "头部", "颈部", "肩部", "胸部", "腰部", "腿部", "脚部", "手腕", "手部",
            "上方戒指", "下方戒指", "上方饰品", "下方饰品", "背部" },
    },
}
local L = translations[GetLocale()] or translations.enUS

local panel = CreateFrame("Frame")
local slotMenu = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
local itemMenu = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
local enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
local remove = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
local selected = 12 -- Upper trinket

local function Label(font, x, y, text)
    local label = panel:CreateFontString(nil, "ARTWORK", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, y)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

Label("GameFontNormalLarge", 24, -24, L.title)
Label("GameFontHighlight", 24, -62, L.instructions)
enabled:SetPoint("TOPLEFT", 22, -98)
enabled.Text:SetText(L.enabled)
slotMenu:SetPoint("TOPLEFT", 24, -139)
slotMenu:SetWidth(240)
itemMenu:SetPoint("TOPLEFT", 24, -174)
itemMenu:SetWidth(300)
remove:SetPoint("LEFT", itemMenu, "RIGHT", 8, 0)
remove:SetSize(132, 24)
remove:SetText(L.remove)
Label("GameFontNormal", 24, -219, L.rules)
local ruleList = Label("GameFontHighlight", 24, -243)

local function ItemName(item)
    return item.link:match("|h%[(.-)%]|h") or tostring(item.id)
end

local function RefreshPanel()
    local db = swim.db
    if not db then return end
    local rule = db.rules[swim.slots[selected][1]]
    enabled:SetChecked(db.enabled)
    slotMenu:SetDefaultText(L.slots[selected])
    itemMenu:SetDefaultText(rule and ItemName(rule) or L.choose)
    slotMenu:GenerateMenu()
    itemMenu:GenerateMenu()
    remove:SetEnabled(rule ~= nil)

    local lines = {}
    for i, slot in ipairs(swim.slots) do
        local saved = db.rules[slot[1]]
        if saved then lines[#lines + 1] = L.slots[i] .. "  " .. saved.link end
    end
    if #lines == 0 then lines[1] = L.none end
    ruleList:SetText(table.concat(lines, "\n"))
end

slotMenu:SetupMenu(function(_, menu)
    for i, title in ipairs(L.slots) do
        menu:CreateButton(title, function(index)
            selected = index
            RefreshPanel()
        end, i)
    end
end)

itemMenu:SetupMenu(function(_, menu)
    if not swim.db then return end
    local slot = swim.slots[selected]
    local choices = swim.GetChoices(slot)
    if #choices == 0 then
        menu:CreateTitle(L.empty)
        return
    end
    menu:SetScrollMode(245)
    for _, item in ipairs(choices) do
        menu:CreateButton(ItemName(item), function(choice)
            swim.db.rules[slot[1]] = choice
            swim.Refresh()
            RefreshPanel()
        end, item)
    end
end)

enabled:SetScript("OnClick", function(self)
    if not swim.db then return end
    swim.db.enabled = self:GetChecked() and true or false
    swim.Refresh()
    RefreshPanel()
end)

remove:SetScript("OnClick", function()
    if not swim.db then return end
    swim.db.rules[swim.slots[selected][1]] = nil
    swim.Refresh()
    RefreshPanel()
end)

panel:SetScript("OnShow", RefreshPanel)
Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "MyForeverTools"))
