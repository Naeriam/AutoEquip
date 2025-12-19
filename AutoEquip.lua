local f = CreateFrame("Frame")

-------------------------------------------------------
-- State
-------------------------------------------------------
local pendingScan = false
local bankOpen = false
local bankCooldownUntil = 0

-------------------------------------------------------
-- Stable item class IDs
-------------------------------------------------------
local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR  = 4

-------------------------------------------------------
-- APIs
-------------------------------------------------------
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local UseContainerItem    = C_Container.UseContainerItem

-------------------------------------------------------
-- Armor type per class
-------------------------------------------------------
local CLASS_ARMOR_ID = {
    WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
    HUNTER = 3, SHAMAN = 3, EVOKER = 3,
    ROGUE = 2, DRUID = 2, MONK = 2, DEMONHUNTER = 2,
    MAGE = 1, WARLOCK = 1, PRIEST = 1,
}

-------------------------------------------------------
-- Equip location → inventory slot
-------------------------------------------------------
local INVTYPE_TO_SLOT = {
    INVTYPE_HEAD     = "HeadSlot",
    INVTYPE_SHOULDER = "ShoulderSlot",
    INVTYPE_CHEST    = "ChestSlot",
    INVTYPE_ROBE     = "ChestSlot",
    INVTYPE_WAIST    = "WaistSlot",
    INVTYPE_LEGS     = "LegsSlot",
    INVTYPE_FEET     = "FeetSlot",
    INVTYPE_WRIST    = "WristSlot",
    INVTYPE_HAND     = "HandsSlot",
    INVTYPE_CLOAK    = "BackSlot",
    INVTYPE_NECK     = "NeckSlot",
}

local _, playerClass = UnitClass("player")
local REQUIRED_ARMOR = CLASS_ARMOR_ID[playerClass]

-------------------------------------------------------
-- Helpers
-------------------------------------------------------
local function GetEquippedItemInfo(invSlot)
    local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
    if not loc or not C_Item.DoesItemExist(loc) then
        return 0, nil
    end
    return C_Item.GetCurrentItemLevel(loc) or 0,
           GetInventoryItemLink("player", invSlot)
end

local function GetWorstOfTwo(slot1, slot2)
    local ilvl1, link1 = GetEquippedItemInfo(slot1)
    local ilvl2, link2 = GetEquippedItemInfo(slot2)

    if ilvl1 <= ilvl2 then
        return slot1, ilvl1, link1
    else
        return slot2, ilvl2, link2
    end
end

-------------------------------------------------------
-- Core logic
-------------------------------------------------------
local function TryEquipItem(bag, slot)
    if bankOpen or GetTime() < bankCooldownUntil then
        pendingScan = true
        return
    end

    local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not itemLoc or not C_Item.DoesItemExist(itemLoc) then return end

    local itemID = C_Item.GetItemID(itemLoc)
    if not itemID then pendingScan = true return end

    local link = GetContainerItemLink(bag, slot)
    if not link then return end

    local _, _, _, equipLoc, _, classID, subClassID =
        GetItemInfoInstant(itemID)

    if not equipLoc or equipLoc == "" then return end

    ---------------------------------------------------
    -- NEVER equip weapons
    ---------------------------------------------------
    if classID == ITEM_CLASS_WEAPON then return end

    ---------------------------------------------------
    -- Armor type enforcement (ONLY real armor slots)
    ---------------------------------------------------
    local isRealArmorSlot =
        equipLoc == "INVTYPE_HEAD" or
        equipLoc == "INVTYPE_SHOULDER" or
        equipLoc == "INVTYPE_CHEST" or
        equipLoc == "INVTYPE_ROBE" or
        equipLoc == "INVTYPE_WAIST" or
        equipLoc == "INVTYPE_LEGS" or
        equipLoc == "INVTYPE_FEET" or
        equipLoc == "INVTYPE_WRIST" or
        equipLoc == "INVTYPE_HAND"

    if isRealArmorSlot and classID == ITEM_CLASS_ARMOR then
        if subClassID ~= REQUIRED_ARMOR then return end
    end

    ---------------------------------------------------
    -- Item level
    ---------------------------------------------------
    local newIlvl = C_Item.GetCurrentItemLevel(itemLoc)
    if not newIlvl then pendingScan = true return end

    ---------------------------------------------------
    -- Target slot resolution
    ---------------------------------------------------
    local targetInvSlot, equippedIlvl, replacedLink

    if equipLoc == "INVTYPE_FINGER" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_FINGER1, INVSLOT_FINGER2)

    elseif equipLoc == "INVTYPE_TRINKET" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_TRINKET1, INVSLOT_TRINKET2)

    else
        local slotName = INVTYPE_TO_SLOT[equipLoc]
        if not slotName then return end

        targetInvSlot = GetInventorySlotInfo(slotName)
        equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)
    end

    if not targetInvSlot or newIlvl <= equippedIlvl then return end

    ---------------------------------------------------
    -- Bind check
    ---------------------------------------------------
    if not C_Item.IsBound(itemLoc) then
        print(string.format(
            "|cffffff00[AutoEquip]|r %s would be an upgrade but is not soulbound",
            link
        ))
        return
    end

    ---------------------------------------------------
    -- Equip
    ---------------------------------------------------
    UseContainerItem(bag, slot)

    print(string.format(
        "|cff00ff00[AutoEquip]|r Equipped %s |cffff0000(replaces %s)|r",
        link,
        replacedLink or "nothing"
    ))
end

-------------------------------------------------------
-- Bag scan
-------------------------------------------------------
local function ScanBags()
    if InCombatLockdown() or bankOpen or GetTime() < bankCooldownUntil then
        pendingScan = true
        return
    end

    pendingScan = false

    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            TryEquipItem(bag, slot)
        end
    end
end

-------------------------------------------------------
-- Events
-------------------------------------------------------
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")

f:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        ScanBags()

    elseif event == "PLAYER_REGEN_ENABLED" and pendingScan then
        ScanBags()

    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true

    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        bankCooldownUntil = GetTime() + 1.2
        pendingScan = true
    end
end)