local f = CreateFrame("Frame")

-- Flags
local pendingScan = false

-- APIs Retail
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local UseContainerItem = C_Container.UseContainerItem
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo

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

    INVTYPE_BODY = "ShirtSlot",
}

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

-- Para anillos y trinkets: devuelve el PEOR de los dos
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
    local link = GetContainerItemLink(bag, slot)
    if not link then return end

    local equipSlot = select(9, GetItemInfo(link))
    if not equipSlot then return end

    -- Ignorar objetos no equipables
    if equipSlot == "INVTYPE_NON_EQUIP_IGNORE" then return end


    local newIlvl = GetDetailedItemLevelInfo(link)
    if not newIlvl then return end

    local targetInvSlot
    local equippedIlvl
    local replacedLink

    -- Anillos
    if equipSlot == "INVTYPE_FINGER" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_FINGER1, INVSLOT_FINGER2)

    -- Trinkets
    elseif equipSlot == "INVTYPE_TRINKET" then
        targetInvSlot, equippedIlvl, replacedLink =
            GetWorstOfTwo(INVSLOT_TRINKET1, INVSLOT_TRINKET2)

    -- Armas
    elseif WEAPON_INV_TYPES[equipSlot] then
        targetInvSlot = INVSLOT_MAINHAND
        equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)

    -- Slots normales (HEAD, CHEST, etc.)
    else
        local slotName = INVTYPE_TO_SLOT[equipSlot]
        if not slotName then return end

        targetInvSlot = GetInventorySlotInfo(slotName)
        if not targetInvSlot then return end

        equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)
    end

    if not targetInvSlot then return end

    if newIlvl > equippedIlvl then
        UseContainerItem(bag, slot)

        local newName = link
        local oldName = replacedLink or "nothing"

        print(string.format(
            "|cff00ff00[AutoEquip]|r Equipped %s |cffff0000(replaces %s)|r",
            newName,
            oldName
        ))
    end
end

-------------------------------------------------------
-- Bag scan
-------------------------------------------------------

local function ScanBags()
    if InCombatLockdown() then
        pendingScan = true
        return
    end

    pendingScan = false

    for bag = 0, NUM_BAG_SLOTS do
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            TryEquipItem(bag, slot)
        end
    end
end

-------------------------------------------------------
-- Events
-------------------------------------------------------

f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

f:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then
        ScanBags()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingScan then
            ScanBags()
        end
    end
end)