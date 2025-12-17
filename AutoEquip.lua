local f = CreateFrame("Frame")

-------------------------------------------------------
-- Flags
-------------------------------------------------------
local pendingScan = false
local bankOpen = false

-------------------------------------------------------
-- APIs Retail
-------------------------------------------------------
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local UseContainerItem = C_Container.UseContainerItem
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo

-------------------------------------------------------
-- Constants
-------------------------------------------------------
local WEAPON_INV_TYPES = {
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}

local INVTYPE_TO_SLOT = {
    INVTYPE_HEAD = "HeadSlot",
    INVTYPE_NECK = "NeckSlot",
    INVTYPE_SHOULDER = "ShoulderSlot",
    INVTYPE_CHEST = "ChestSlot",
    INVTYPE_ROBE = "ChestSlot",
    INVTYPE_WAIST = "WaistSlot",
    INVTYPE_LEGS = "LegsSlot",
    INVTYPE_FEET = "FeetSlot",
    INVTYPE_WRIST = "WristSlot",
    INVTYPE_HAND = "HandsSlot",
    INVTYPE_CLOAK = "BackSlot",

    INVTYPE_SHIELD = "SecondaryHandSlot",
    INVTYPE_HOLDABLE = "SecondaryHandSlot",
}

-------------------------------------------------------
-- Armor type per class
-------------------------------------------------------
local CLASS_ARMOR_TYPE = {
    WARRIOR = "Plate",
    PALADIN = "Plate",
    DEATHKNIGHT = "Plate",

    HUNTER = "Mail",
    SHAMAN = "Mail",
    EVOKER = "Mail",

    ROGUE = "Leather",
    DRUID = "Leather",
    MONK = "Leather",
    DEMONHUNTER = "Leather",

    MAGE = "Cloth",
    WARLOCK = "Cloth",
    PRIEST = "Cloth",
}

local _, playerClass = UnitClass("player")
local PLAYER_ARMOR = CLASS_ARMOR_TYPE[playerClass]

-------------------------------------------------------
-- Helpers
-------------------------------------------------------
local function GetEquippedItemInfo(invSlot)
    local link = GetInventoryItemLink("player", invSlot)
    if not link then
        return 0, nil
    end

    local ilvl = GetDetailedItemLevelInfo(link)
    return ilvl or 0, link
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

local function IsTwoHandEquipped()
    local link = GetInventoryItemLink("player", INVSLOT_MAINHAND)
    if not link then return false end

    local equipSlot = select(9, GetItemInfo(link))
    return equipSlot == "INVTYPE_2HWEAPON"
end

-------------------------------------------------------
-- Core logic
-------------------------------------------------------
local function TryEquipItem(bag, slot)
    local link = GetContainerItemLink(bag, slot)
    if not link then return end

    local name, _, _, _, _, itemType, itemSubType, _, equipSlot = GetItemInfo(link)
    if not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_NON_EQUIP_IGNORE" then
        return
    end

    local newIlvl = GetDetailedItemLevelInfo(link)
    if not newIlvl then return end

    ---------------------------------------------------
    -- SLOT DECISION 
    ---------------------------------------------------
    local targetInvSlot, equippedIlvl, replacedLink

    -- Rings
    if equipSlot == "INVTYPE_FINGER" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_FINGER1, INVSLOT_FINGER2)

    -- Trinkets
    elseif equipSlot == "INVTYPE_TRINKET" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_TRINKET1, INVSLOT_TRINKET2)

    -- Weapons
    elseif WEAPON_INV_TYPES[equipSlot] then
        local mhLink = GetInventoryItemLink("player", INVSLOT_MAINHAND)
        local mhEquip = mhLink and select(9, GetItemInfo(mhLink))

        -- Llevo 2H → solo comparo 2H
        if mhEquip == "INVTYPE_2HWEAPON" then
            if equipSlot ~= "INVTYPE_2HWEAPON" then return end
            targetInvSlot = INVSLOT_MAINHAND

        -- No llevo 2H → ignoro candidatos 2H
        elseif equipSlot == "INVTYPE_2HWEAPON" then
            return

        -- Offhand / shield
        elseif equipSlot == "INVTYPE_WEAPONOFFHAND"
            or equipSlot == "INVTYPE_SHIELD"
            or equipSlot == "INVTYPE_HOLDABLE" then
            targetInvSlot = INVSLOT_OFFHAND

        -- Main hand 1H
        else
            targetInvSlot = INVSLOT_MAINHAND
        end

        equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)

    -- Normal armor slots
    else
        local slotName = INVTYPE_TO_SLOT[equipSlot]
        if not slotName then return end

        targetInvSlot = GetInventorySlotInfo(slotName)
        equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)
    end

    if not targetInvSlot or newIlvl <= equippedIlvl then return end

    ---------------------------------------------------
    -- ARMOR TYPE CHECK
    ---------------------------------------------------
    if itemType == "Armor" then
        local requiredArmor = ({
            WARRIOR = "Plate",
            PALADIN = "Plate",
            DEATHKNIGHT = "Plate",

            HUNTER = "Mail",
            SHAMAN = "Mail",
            EVOKER = "Mail",

            ROGUE = "Leather",
            DRUID = "Leather",
            MONK = "Leather",
            DEMONHUNTER = "Leather",

            MAGE = "Cloth",
            WARLOCK = "Cloth",
            PRIEST = "Cloth",
        })[playerClass]

        -- Solo filtrar piezas reales (no joyería, capa, etc.)
        local isRealArmor =
            equipSlot == "INVTYPE_HEAD" or
            equipSlot == "INVTYPE_SHOULDER" or
            equipSlot == "INVTYPE_CHEST" or
            equipSlot == "INVTYPE_ROBE" or
            equipSlot == "INVTYPE_LEGS" or
            equipSlot == "INVTYPE_FEET" or
            equipSlot == "INVTYPE_WRIST" or
            equipSlot == "INVTYPE_HAND" or
            equipSlot == "INVTYPE_WAIST"

        if isRealArmor and requiredArmor and itemSubType ~= requiredArmor then
            return
        end
    end

    ---------------------------------------------------
    -- SOULBOUND CHECK
    ---------------------------------------------------
    local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not C_Item.IsBound(itemLoc) then
        print(string.format(
            "|cffffff00[AutoEquip]|r %s would be an upgrade but is not soulbound",
            link
        ))
        return
    end

    ---------------------------------------------------
    -- EQUIP
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
    if InCombatLockdown() or bankOpen then
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
        if pendingScan then
            ScanBags()
        end
    end
end)