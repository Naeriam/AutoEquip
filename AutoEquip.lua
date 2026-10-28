local f = CreateFrame("Frame")

-------------------------------------------------------
-- State
-------------------------------------------------------
local pendingScan = false
local bankOpen = false
local bankCooldownUntil = 0
local scanReadyAt = 0      -- no scans before this time (login grace period)
local scanTimer = nil      -- debounce timer for scan requests
local scanBag, scanSlot = nil, nil -- progress of the scan in course

-------------------------------------------------------
-- Tuning
-------------------------------------------------------
local LOGIN_DELAY     = 5   -- seconds to wait after login / reload
local SCAN_DEBOUNCE   = 0.5 -- seconds to group consecutive bag updates
local SLOTS_PER_FRAME = 8   -- bag slots checked per frame

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
        C_Item.GetItemInfoInstant(itemID)

    if not equipLoc or equipLoc == "" then return end

    ---------------------------------------------------
    -- NEVER equip weapons
    ---------------------------------------------------
    if classID == ITEM_CLASS_WEAPON then return end
    ---------------------------------------------------
    -- NEVER equip trinkets or rings
    -- (rings excluded: unique-equipped duplicates with the same name but
    -- different itemIDs made the addon swap them back and forth forever)
    ---------------------------------------------------
    if equipLoc == "INVTYPE_TRINKET" or equipLoc == "INVTYPE_FINGER" then return end

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
    local slotName = INVTYPE_TO_SLOT[equipLoc]
    if not slotName then return end

    local targetInvSlot = GetInventorySlotInfo(slotName)
    local equippedIlvl, replacedLink = GetEquippedItemInfo(targetInvSlot)

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
-- Bag scan (spread over several frames to avoid hitches)
-------------------------------------------------------
local function CanScan()
    return not InCombatLockdown() and not bankOpen
        and GetTime() >= bankCooldownUntil
end

local function StopScan()
    scanBag, scanSlot = nil, nil
    f:SetScript("OnUpdate", nil)
end

local function ScanStep()
    if not CanScan() then
        pendingScan = true
        StopScan()
        return
    end

    local budget = SLOTS_PER_FRAME
    while budget > 0 do
        if scanSlot > GetContainerNumSlots(scanBag) then
            scanBag, scanSlot = scanBag + 1, 1
            if scanBag > NUM_BAG_SLOTS then
                StopScan()
                return
            end
        else
            TryEquipItem(scanBag, scanSlot)
            scanSlot = scanSlot + 1
            budget = budget - 1
        end
    end
end

local function ScanBags()
    if not CanScan() then
        pendingScan = true
        return
    end

    pendingScan = false

    -- (Re)start from the first bag; a scan in course is restarted
    scanBag, scanSlot = 0, 1
    f:SetScript("OnUpdate", ScanStep)
end

-- Groups bursts of events into a single scan and honours the login delay
local function RequestScan()
    if scanTimer then scanTimer:Cancel() end
    local delay = math.max(SCAN_DEBOUNCE, scanReadyAt - GetTime())
    scanTimer = C_Timer.NewTimer(delay, function()
        scanTimer = nil
        ScanBags()
    end)
end

-------------------------------------------------------
-- Events
-------------------------------------------------------
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")

f:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if event == "PLAYER_ENTERING_WORLD" then
        if isInitialLogin or isReloadingUi then
            scanReadyAt = GetTime() + LOGIN_DELAY
            RequestScan()
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        RequestScan()

    elseif event == "PLAYER_REGEN_ENABLED" and pendingScan then
        RequestScan()

    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true

    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
        bankCooldownUntil = GetTime() + 1.2
        pendingScan = true
    end
end)