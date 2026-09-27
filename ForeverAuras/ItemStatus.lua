if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

function Private.ExecEnv.GetEquipmentDurability(selectedSlot)
  local lowest, currentTotal, maximumTotal, broken, count = 100, 0, 0, 0, 0
  selectedSlot = tonumber(selectedSlot) or 0
  if selectedSlot < 0 or selectedSlot > 19 or selectedSlot ~= math.floor(selectedSlot) then return end
  local firstSlot, lastSlot = 1, 19
  if selectedSlot > 0 then firstSlot, lastSlot = selectedSlot, selectedSlot end
  for slot = firstSlot, lastSlot do
    local current, maximum = GetInventoryItemDurability(slot)
    if hasanysecretvalues(current, maximum) then return end
    if current and maximum and maximum > 0 then
      lowest = math.min(lowest, current / maximum * 100)
      currentTotal = currentTotal + current
      maximumTotal = maximumTotal + maximum
      count = count + 1
      if current == 0 then broken = broken + 1 end
    end
  end
  if count == 0 then return end
  return lowest, currentTotal / maximumTotal * 100, broken, count
end

function Private.ExecEnv.GetBagSpace(includeSpecialty)
  local free, total = 0, 0
  local lastBag = includeSpecialty and (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) or NUM_BAG_SLOTS
  for bag = 0, lastBag do
    local slots = C_Container.GetContainerNumSlots(bag)
    local available, family = C_Container.GetContainerNumFreeSlots(bag)
    if hasanysecretvalues(slots, available, family) then return end
    if slots and slots > 0 and (includeSpecialty or family == 0) then
      if available == nil then return end
      total = total + slots
      free = free + available
    end
  end
  if total == 0 then return end
  return free, total, total-free, free / total * 100
end

-- Ignore permanent enchants. If both are supplied, prefer an imbue over an oil
-- for the legacy one-enchant-per-hand trigger. Secret fields remain unavailable.
local function ReadModernWeaponEnchant(slot)
  local list = C_Item.GetWeaponEnchantInfo(slot)
  if issecretvalue(list) then return nil, false end
  local chosen
  local types = Enum and Enum.ItemEnchantType
  if not types then return nil, false end
  for _, entry in ipairs(list or {}) do
    if issecretvalue(entry) or hasanysecretvalues(entry.hasEnchant, entry.enchantType, entry.timeLeft, entry.charges, entry.enchantID, entry.enchantIconID) then return nil, false end
    if entry.hasEnchant and (entry.enchantType == types.Temporary or entry.enchantType == types.Imbue) then
      if not chosen or entry.enchantType == types.Imbue then chosen = entry end
    end
  end
  return chosen, true
end

-- Extra return values are internal metadata; the first twelve retain the old API.
function Private.ExecEnv.GetTemporaryWeaponEnchants()
  if C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.ItemEnchantType and Enum.WeaponSlot then
    local main, mainReadable = ReadModernWeaponEnchant(Enum.WeaponSlot.MainHand)
    local off, offReadable = ReadModernWeaponEnchant(Enum.WeaponSlot.OffHand)
    if not mainReadable or not offReadable then
      return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false
    end
    return main ~= nil, main and main.timeLeft, main and main.charges, main and main.enchantID,
      off ~= nil, off and off.timeLeft, off and off.charges, off and off.enchantID,
      nil, nil, nil, nil, true, main and main.enchantIconID, off and off.enchantIconID
  end
  if C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo then
    local main = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_MAINHAND)
    local off = C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT_OFFHAND)
    return main ~= nil, main and main.remainingTimeMs, main and main.chargesRemaining, main and main.enchantID,
      off ~= nil, off and off.remainingTimeMs, off and off.chargesRemaining, off and off.enchantID
  end
  return GetWeaponEnchantInfo()
end

local function TrackingInfo(index)
  if C_Minimap and C_Minimap.GetTrackingInfo then return C_Minimap.GetTrackingInfo(index) end
  local name, texture, active = GetTrackingInfo(index)
  if name then return {name = name, texture = texture, active = active == true or active == 1} end
end

local function TrackingCount()
  if C_Minimap and C_Minimap.GetNumTrackingTypes then return C_Minimap.GetNumTrackingTypes() end
  return GetNumTrackingTypes()
end

local function TrackingKey(info)
  return info.spellID and tostring(info.spellID) or info.name
end

function Private.ExecEnv.GetTrackingChoices(selected)
  local values = {}
  for index = 1, TrackingCount() do
    local info = TrackingInfo(index)
    if info then values[TrackingKey(info)] = info.name end
  end
  if selected and selected ~= "" and not values[selected] then values[selected] = selected .. " (unavailable)" end
  return values
end

function Private.ExecEnv.GetTrackingState(selected)
  for index = 1, TrackingCount() do
    local info = TrackingInfo(index)
    if info and TrackingKey(info) == selected then return info.active, info.name, info.texture end
  end
end
