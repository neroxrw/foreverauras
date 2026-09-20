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

function Private.ExecEnv.GetTemporaryWeaponEnchants()
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
