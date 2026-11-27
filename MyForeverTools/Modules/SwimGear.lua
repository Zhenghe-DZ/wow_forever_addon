local _, addon = ...
local bags = C_Container
if not (IsSwimming and bags and bags.GetContainerItemInfo and bags.GetContainerNumSlots
    and bags.GetContainerNumFreeSlots and bags.PickupContainerItem and C_Item and C_Item.GetItemInfoInstant
    and PickupInventoryItem and GetInventoryItemID and GetInventoryItemLink and IsInventoryItemLocked
    and GetCursorInfo and CursorHasItem and ClearCursor and C_Timer and C_Timer.NewTicker) then return end

local swim = {}
addon.SwimGear = swim

-- Weapon slots can also displace equipment in another slot (e.g. a two-hander).
local slots = {
    { 1, "INVTYPE_HEAD" }, { 2, "INVTYPE_NECK" },
    { 3, "INVTYPE_SHOULDER" }, { 5, "INVTYPE_CHEST", "INVTYPE_ROBE" },
    { 6, "INVTYPE_WAIST" }, { 7, "INVTYPE_LEGS" },
    { 8, "INVTYPE_FEET" }, { 9, "INVTYPE_WRIST" },
    { 10, "INVTYPE_HAND" }, { 11, "INVTYPE_FINGER" },
    { 12, "INVTYPE_FINGER" }, { 13, "INVTYPE_TRINKET" },
    { 14, "INVTYPE_TRINKET" }, { 15, "INVTYPE_CLOAK" },
}
swim.slots = slots

local db, ticker, readyAt, transitionAt
local wet = false
local retryAt = {}
local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local function ItemGUID(bag, slot)
    if not (C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot
        and ItemLocation.CreateFromEquipmentSlot) then return end
    local location = bag and ItemLocation:CreateFromBagAndSlot(bag, slot) or ItemLocation:CreateFromEquipmentSlot(slot)
    local ok, guid = pcall(C_Item.GetItemGUID, location)
    if ok then return guid end
end

local function Identity(id, link, bag, slot)
    return { id = id, link = link, guid = ItemGUID(bag, slot) }
end

local function Equipped(slot)
    local id = GetInventoryItemID("player", slot)
    if not id then return false end
    return Identity(id, GetInventoryItemLink("player", slot), nil, slot)
end

local function SameItem(a, b)
    if not a or not b then return a == b end
    if a.id ~= b.id then return false end
    if b.guid then return a.guid == b.guid end
    return a.link ~= nil and a.link == b.link
end

local function Unresolved(item, expected)
    return item and expected and item.id == expected.id
        and ((expected.guid and not item.guid) or (not expected.guid and not item.link))
end

-- An automatic replacement should never trigger a bind-on-equip confirmation.
local function CanEquipFromBag(info)
    if info.isBound then return true end
    if not (info.hyperlink and C_Item.GetItemInfo) then return false end
    local bindType = select(14, C_Item.GetItemInfo(info.hyperlink))
    local bindOnEquip = Enum and Enum.ItemBind and Enum.ItemBind.OnEquip or 2
    return bindType ~= nil and bindType ~= bindOnEquip
end

function swim.GetChoices(slot)
    local items = {}
    for bag = 0, lastBag do
        for index = 1, bags.GetContainerNumSlots(bag) do
            local info = bags.GetContainerItemInfo(bag, index)
            if info and info.itemID and info.hyperlink then
                local _, _, _, equipType = C_Item.GetItemInfoInstant(info.itemID)
                if equipType and (equipType == slot[2] or equipType == slot[3]) and CanEquipFromBag(info) then
                    items[#items + 1] = Identity(info.itemID, info.hyperlink, bag, index)
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.link < b.link end)
    return items
end

local function FindInBags(item, forEquip)
    local foundBag, foundSlot
    for bag = 0, lastBag do
        for index = 1, bags.GetContainerNumSlots(bag) do
            local info = bags.GetContainerItemInfo(bag, index)
            if info and info.itemID == item.id then
                local guid = ItemGUID(bag, index)
                local exact = item.guid and guid and guid == item.guid
                if exact or (not item.guid and item.link and info.hyperlink == item.link) then
                    if foundBag then return end -- No GUID and multiple identical links.
                    if info.isLocked or (forEquip and not CanEquipFromBag(info)) then return end
                    if exact then return bag, index end
                    foundBag, foundSlot = bag, index
                end
            end
        end
    end
    return foundBag, foundSlot
end

local function EmptyBagSlot()
    for bag = 0, lastBag do
        local free, family = bags.GetContainerNumFreeSlots(bag)
        if free and free > 0 and family == 0 then
            for index = 1, bags.GetContainerNumSlots(bag) do
                if not bags.GetContainerItemInfo(bag, index) then return bag, index end
            end
        end
    end
end

local function CanMove()
    return not InCombatLockdown() and not UnitAffectingCombat("player") and not UnitIsDeadOrGhost("player")
        and not UnitCastingInfo("player") and not UnitChannelInfo("player")
        and not GetCursorInfo() and not SpellIsTargeting()
end

local function Move(slot, bag, index, unequip)
    if unequip then
        pcall(PickupInventoryItem, slot)
        if CursorHasItem() then pcall(bags.PickupContainerItem, bag, index) end
    else
        pcall(bags.PickupContainerItem, bag, index)
        if CursorHasItem() then pcall(PickupInventoryItem, slot) end
    end
    if CursorHasItem() then ClearCursor() end
end

local function StopWhenIdle()
    if (not db.enabled or not next(db.rules)) and not next(db.swapped) and ticker then
        ticker:Cancel()
        ticker = nil
        wet, transitionAt = false, nil
        wipe(db.skipped)
    end
end

local function Tick()
    local now = GetTime()
    local swimming = IsSwimming() and true or false
    if swimming == wet then
        transitionAt = nil
    else
        transitionAt = transitionAt or now
        if now - transitionAt >= (swimming and 0.5 or 1.25) then
            wet, transitionAt = swimming, nil
        end
    end
    if not wet and not swimming and next(db.skipped) then wipe(db.skipped) end

    -- The client applies inventory changes asynchronously. Observe the result
    -- before treating a different item as a manual change or moving another slot.
    if readyAt and now < readyAt then return end
    local want = db.enabled and wet
    for slot, entry in pairs(db.swapped) do
        local current = Equipped(slot)
        if SameItem(current, entry.target) then
            entry.equipping = nil
        elseif not IsInventoryItemLocked(slot) and not Unresolved(current, entry.target) then
            db.swapped[slot] = nil
            if want and not (entry.restoring and SameItem(current, entry.original)) then
                db.skipped[slot] = true
            end
        end
    end
    StopWhenIdle()
    if not ticker or (db.enabled and transitionAt) or not CanMove() then return end

    for _, definition in ipairs(slots) do
        local slot = definition[1]
        local rule = db.rules[slot]
        local entry = db.swapped[slot]
        if not IsInventoryItemLocked(slot) and now >= (retryAt[slot] or 0) then
            if entry and not entry.equipping and (not want or not SameItem(rule, entry.target)) then
                retryAt[slot] = now + 2
                local current = Equipped(slot)
                if SameItem(current, entry.target) then
                    local bag, index
                    if entry.original then
                        bag, index = FindInBags(entry.original)
                    else
                        bag, index = EmptyBagSlot()
                    end
                    if bag then
                        entry.restoring = true
                        readyAt = now + 1
                        Move(slot, bag, index, not entry.original)
                        return
                    end
                end
            elseif want and rule and not entry and not db.skipped[slot] then
                retryAt[slot] = now + 2
                local original = Equipped(slot)
                if not SameItem(original, rule) and not Unresolved(original, rule)
                    and (not original or original.guid or original.link) then
                    local bag, index = FindInBags(rule, true)
                    if bag then
                        db.swapped[slot] = { original = original, target = rule, equipping = true }
                        readyAt = now + 1
                        Move(slot, bag, index)
                        return
                    end
                end
            end
        end
    end
end

function swim.Refresh()
    if not db then return end
    if not ticker and ((db.enabled and next(db.rules)) or next(db.swapped)) then
        ticker = C_Timer.NewTicker(0.35, Tick)
    end
    if ticker then Tick() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    MyForeverToolsSwimDB = MyForeverToolsSwimDB or {}
    db = MyForeverToolsSwimDB
    db.rules = db.rules or {}
    db.swapped = db.swapped or {}
    db.skipped = db.skipped or {}
    swim.db = db
    swim.Refresh()
end)
