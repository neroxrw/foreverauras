if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

local catalog
local gcdStates = {}
local refreshEvents = {
  PLAYER_ENTERING_WORLD = true,
  PLAYER_SPECIALIZATION_CHANGED = true,
  SPELLS_CHANGED = true,
  PLAYER_EQUIPMENT_CHANGED = true,
  GET_ITEM_INFO_RECEIVED = true,
  FA_CDM_LAYOUT_CHANGED = true,
  COOLDOWN_VIEWER_DATA_LOADED = true,
  COOLDOWN_VIEWER_TABLE_HOTFIXED = true,
  COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = true,
}

local function IsReadable(value)
  return not (issecretvalue and issecretvalue(value))
end

local function IsAvailable()
  return C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet and C_CooldownViewer.GetCooldownViewerCooldownInfo and Enum and Enum.CooldownViewerCategory and C_Spell and C_Spell.GetSpellCooldownDuration
end

local function GetCatalog(refresh)
  if catalog and not refresh then return catalog end
  catalog = IsAvailable() and Private.CDMCatalog() or {}
  return catalog
end

local function SpellRank(id)
  if not IsReadable(id) or type(id) ~= "number" then return end
  local text = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id)
  return IsReadable(text) and type(text) == "string" and tonumber(text:match("%d+")) or nil
end

local function ExactMatch(info, id)
  if IsReadable(info.spellID) and info.spellID == id then return 2 end
  local baseRank, rank = SpellRank(info.spellID), SpellRank(id)
  if baseRank and rank and baseRank ~= rank then return 0 end
  for _, field in ipairs({"linkedSpellID", "overrideSpellID"}) do
    if IsReadable(info[field]) and info[field] == id then return 1 end
  end
  for _, linked in ipairs(info.linkedSpellIDs or {}) do
    if IsReadable(linked) and linked == id then return 1 end
  end
  return 0
end

local resolved = {}
function Private.ResolveCDMSpell(trigger, event)
  if trigger.type == "cdm" then trigger.cdmSource = trigger.event == "Blizzard CDM Buff" and "buff" or "cooldown" end
  if refreshEvents[event] then Private.CDMResetIdentities() end
  local entries = GetCatalog(refreshEvents[event] or event == "OPTIONS")
  local query = tostring(trigger.cdmSpell or ""):match("^%s*(.-)%s*$")
  local key = query .. ":" .. tostring(trigger.cdmExact) .. ":" .. (trigger.cdmSource or "cooldown")
  if resolved.entries ~= entries then resolved = {entries = entries} end
  if resolved[key] then return resolved[key] end
  local id = tonumber(query)
  if trigger.cdmExact and not id then return {} end
  local spell = id and C_Spell.GetSpellInfo(id)
  local name = (spell and spell.name or query):lower()
  local exact = trigger.cdmExact or id ~= nil
  local anyBuffRank = not exact and trigger.cdmSource == "buff"
  local buffSpellIDs, seen = {}, {}
  local function AddBuffID(spellID)
    if not IsReadable(spellID) or type(spellID) ~= "number" or seen[spellID] then return end
    local spell = C_Spell.GetSpellInfo(spellID)
    if spell and spell.name:lower() == name then seen[spellID] = true; buffSpellIDs[#buffSpellIDs + 1] = spellID end
  end
  local best, bestRank, bestScore
  for entryID, entry in pairs(entries) do
    if (entry.known or exact or anyBuffRank) and Private.CDMIsBuff(entry.category) == (trigger.cdmSource == "buff") then
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(entryID)
      if info then
        local identity = Private.CDMIdentity(entryID, entry, info)
        local score = exact and ExactMatch(info, id) or 1
        local matches = exact and score > 0 or not exact and identity.name:lower() == name
        if matches and anyBuffRank then
          AddBuffID(info.spellID)
          AddBuffID(identity.spellID)
          for _, linked in ipairs(info.linkedSpellIDs or {}) do AddBuffID(linked) end
          score = entry.known and 1 or 0
        end
        if matches and identity.spellID then
          local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(identity.spellID)
          local rank = IsReadable(subtext) and type(subtext) == "string" and tonumber(subtext:match("%d+")) or 0
          if not best or score > bestScore or (score == bestScore and (rank > bestRank or (rank == bestRank and entryID < best))) then best, bestRank, bestScore = entryID, rank, score end
        end
      end
    end
  end
  resolved[key] = best and {best} or {}
  if anyBuffRank then resolved[key].buffSpellIDs = buffSpellIDs end
  return resolved[key]
end

function Private.DebugCDMSpell(trigger, auraID, triggernum)
  local query = tostring(trigger.cdmSpell or "")
  local id = tonumber(query)
  local spell = id and C_Spell.GetSpellInfo(id)
  local name = (spell and spell.name or query):lower()
  local function Text(value)
    if not IsReadable(value) then return "SECRET" end
    return tostring(value)
  end
  local count = 0
  local frames = Private.CDMFrames()
  for entryID, entry in pairs(GetCatalog(true)) do
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(entryID)
    if info then
      local identity = Private.CDMIdentity(entryID, entry, info, frames[entryID])
      if identity.name:lower() == name or (id and ExactMatch(info, id) > 0) then
        local links = {}
        for _, linked in ipairs(info.linkedSpellIDs or {}) do links[#links + 1] = Text(linked) end
        local state = {}
        if Private.CDMIsBuff(entry.category) then Private.CDMApplyAura(state, identity, info, frames[entryID]) end
        print("[CDM] " .. identity.name .. " | " .. Private.CDMCategoryName(entry.category) .. " | known=" .. Text(entry.known) .. " | base=" .. Text(info.spellID) .. " | resolved=" .. Text(identity.spellID) .. " | linked=" .. Text(info.linkedSpellID) .. " [" .. table.concat(links, ",") .. "] | override=" .. Text(info.overrideSpellID) .. " | base rank=" .. Text(SpellRank(info.spellID)) .. " | active=" .. Text(state.auraActive))
        count = count + 1
      end
    end
  end
  print("[CDM] " .. count .. " matching entries for " .. query)
  local selected = Private.ResolveCDMSpell(trigger, "OPTIONS")
  local mode = trigger.cdmSource == "buff" and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always")
  print("[CDM State] type=" .. Text(trigger.type) .. " event=" .. Text(trigger.event) .. " source=" .. Text(trigger.cdmSource) .. " input=" .. query .. " show=" .. mode .. " selected=" .. #selected)
  local calculated = {}
  Private.UpdateCooldownViewerStates(calculated, selected, "FA_CDM_REFRESH", trigger.use_cdmShowGCD, trigger.cdmTrack or "auto", trigger.cdmHideGCDText ~= false, mode, tonumber(query))
  for _, state in pairs(calculated) do
    print("[CDM Calculated] spell=" .. Text(state.spellId) .. " show=" .. Text(state.show) .. " active=" .. Text(state.auraActive) .. " progress=" .. Text(state.progressType))
  end
  if auraID and triggernum then
    local states = ForeverAuras.GetTriggerStateForTrigger(auraID, triggernum)
    local count = 0
    for _, state in pairs(states or {}) do
      count = count + 1
      print("[CDM Live] spell=" .. Text(state.spellId) .. " show=" .. Text(state.show) .. " active=" .. Text(state.auraActive) .. " progress=" .. Text(state.progressType))
    end
    if count == 0 then print("[CDM Live] No trigger states") end
  end
end

function Private.CDMEntryMatches(trigger, entry, info)
  if entry.displayed ~= true then return false end
  local c = Enum.CooldownViewerCategory
  local item = info.equipSlot ~= nil or info.spellCategoryID ~= nil
    or entry.sourceCategory == c.EquipSlotEssential or entry.sourceCategory == c.EquipSlotTracked
  if trigger.event == "Blizzard CDM Item" then return item and not Private.CDMIsBuff(entry.category) end
  if trigger.event == "Blizzard CDM Buff" then return Private.CDMIsBuff(entry.category) end
  if item then return false end
  if trigger.event == "Blizzard CDM Utility" then return entry.category == c.Utility end
  return entry.category == c.Essential
end

function Private.CDMAuraSpellIDs(info)
  local ids, seen = {}, {}
  local function Add(id)
    if IsReadable(id) and type(id) == "number" and id > 0 and not seen[id] then
      seen[id] = true; ids[#ids + 1] = id
    end
  end
  Add(info.spellID); Add(info.overrideSpellID); Add(info.overrideTooltipSpellID); Add(info.linkedSpellID)
  for _, id in ipairs(info.linkedSpellIDs or {}) do Add(id) end
  table.sort(ids)
  return ids
end

function Private.GetCDMPickerSelections(trigger, event)
  local selected = {buffSpellIDsByEntry = {}}
  local entries = GetCatalog(refreshEvents[event] or event == "OPTIONS")
  for key, enabled in pairs(trigger.cdmSpells and trigger.cdmSpells.multi or {}) do
    local id = tonumber(key)
    local entry = id and entries[id]
    local info = entry and C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if enabled and info and Private.CDMEntryMatches(trigger, entry, info) then
      selected[#selected + 1] = id
      selected.buffSpellIDsByEntry[id] = Private.CDMAuraSpellIDs(info)
    end
  end
  table.sort(selected)
  return selected
end

function Private.CDMNativeSelections(trigger)
  if trigger.cdmSpell ~= nil then
    local selected = Private.ResolveCDMSpell(trigger)
    local id = tonumber(trigger.cdmSpell)
    return {id and selected[1] and {id} or selected.buffSpellIDs}
  end
  local selected = Private.GetCDMPickerSelections(trigger, "OPTIONS")
  local bindings = {}
  for _, id in ipairs(selected) do bindings[#bindings + 1] = selected.buffSpellIDsByEntry[id] end
  return bindings
end

local function GetSelections(trigger)
  if trigger.cdmSpell ~= nil then return Private.ResolveCDMSpell(trigger) end
  return Private.GetCDMPickerSelections(trigger)
end

local function GetValues(trigger)
  local values = {}
  local frames = Private.CDMFrames()
  for id, entry in pairs(GetCatalog(true)) do
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if info then
      local identity = Private.CDMIdentity(id, entry, info, frames[id])
      local placement = entry.displayed == true and "Displayed" or entry.displayed == false and "Not displayed" or "Layout unavailable"
      local learned = entry.known and "" or " — Not learned"
      values[id] = placement .. " — " .. Private.CDMCategoryName(entry.category) .. " — " .. identity.name .. " [" .. (identity.spellID or identity.itemID or "Unknown") .. "]" .. learned
    end
  end
  for _, id in ipairs(GetSelections(trigger)) do
    if type(id) == "number" and not values[id] then values[id] = "Unavailable in this specialization" end
  end
  return values
end

local function ReadBoolean(value)
  if IsReadable(value) and type(value) == "boolean" then return value end
end

local refreshQueued = false
local function QueueRefresh()
  if refreshQueued then return end
  refreshQueued = true
  C_Timer.After(0, function()
    refreshQueued = false
    if Private.ScanEvents then Private.ScanEvents("FA_CDM_REFRESH") end
  end)
end

function Private.UpdateCooldownViewerStates(allstates, selected, event, showGCD, track, hideGCDText, showMode, exactID, requireTarget)
  if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then Private.CDMResetIdentities() end
  if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" then wipe(gcdStates) end
  local available = GetCatalog(refreshEvents[event] or event == "OPTIONS")
  local frames = Private.CDMFrames()
  for _, state in pairs(allstates) do
    state.show = false
    state.changed = true
  end
  if not IsAvailable() then return true end
  if requireTarget and event ~= "OPTIONS" then
    local exists = UnitExists("target")
    local attackable = UnitCanAttack("player", "target")
    if not IsReadable(exists) or not IsReadable(attackable) then return true end
    if not exists or not attackable then return true end
  end

  for index, cooldownID in ipairs(selected) do
    local entry = available[cooldownID]
    if entry and (entry.known or exactID or selected.buffSpellIDs or selected.buffSpellIDsByEntry) then
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
      if info then
        local identity = Private.CDMIdentity(cooldownID, entry, info, frames[cooldownID])
        if exactID then
          local spell = C_Spell.GetSpellInfo(exactID)
          identity = {spellID = exactID, name = spell and spell.name or identity.name, icon = spell and spell.iconID or identity.icon}
        end
        local cloneID = tostring(cooldownID)
        if not allstates[cloneID] then
          allstates[cloneID] = {
            show = true,
            changed = true,
          }
        end
        local state = allstates[cloneID]
        state.show, state.changed, state.autoHide = true, true, false
        state.index, state.name, state.icon = index, identity.name, identity.icon
        state.spellId, state.itemId, state.cooldownID = identity.spellID, identity.itemID, type(cooldownID) == "number" and cooldownID or nil
        state.cdmDisplayed, state.cdmCategory = entry.displayed, Private.CDMCategoryName(entry.category)
        state.progressType, state.value, state.total = "static", 1, 1
        state.durationObject, state.duration, state.expirationTime, state.modRate = nil, nil, nil, nil
        state.cdmBuff = Private.CDMIsBuff(entry.category)
        local bindingIDs = selected.buffSpellIDsByEntry and selected.buffSpellIDsByEntry[cooldownID]
        state.cdmAuraSpellIDs = state.cdmBuff and (bindingIDs or (exactID and {exactID}) or selected.buffSpellIDs or {identity.spellID}) or nil
        state.cdmTextPreview = event == "OPTIONS"
        state.cdmCountdownSource, state.cdmStackSource, state.cdmTextRecord = nil, nil, nil
        state.onCooldown, state.isReady, state.recharging, state.stacks, state.auraActive = nil, nil, nil, nil, nil
        state.cdmGCDOnly, state.cdmHideGCDText = false, hideGCDText == true

        if Private.CDMIsBuff(entry.category) then
          Private.CDMApplyAura(state, identity, info, frames[cooldownID], exactID, bindingIDs or selected.buffSpellIDs)
        elseif identity.slot or identity.itemID then
          Private.CDMApplyItem(state, identity)
        elseif identity.spellID then
          local spellID = identity.spellID
          local cooldown = C_Spell.GetSpellCooldown(spellID)
          if event == "SPELL_UPDATE_COOLDOWN" then gcdStates[spellID] = cooldown and ReadBoolean(cooldown.isOnGCD) end
          local realDuration = C_Spell.GetSpellCooldownDuration(spellID, true)
          local zero = realDuration and ReadBoolean(realDuration:IsZero())
          if zero ~= nil then
            state.onCooldown, state.isReady = not zero, zero
          elseif cooldown and ReadBoolean(cooldown.isActive) == false then
            state.onCooldown, state.isReady = false, true
          elseif cooldown and ReadBoolean(cooldown.isActive) == true and gcdStates[spellID] ~= nil then
            state.onCooldown, state.isReady = not gcdStates[spellID], gcdStates[spellID]
          end
          state.cdmGCDOnly = gcdStates[spellID] == true and state.onCooldown == false
          local duration = showGCD and C_Spell.GetSpellCooldownDuration(spellID) or realDuration
          local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
          if charges then
            state.recharging = ReadBoolean(charges.isActive)
            if IsReadable(charges.currentCharges) and type(charges.currentCharges) == "number" then
              state.stacks = charges.currentCharges
              state.isReady = charges.currentCharges > 0
            end
          end
          if (track == "charges" or (track ~= "cooldown" and (ReadBoolean(info.charges) == true or charges))) and C_Spell.GetSpellChargeDuration then duration = C_Spell.GetSpellChargeDuration(spellID) or duration end
          if duration then
            state.progressType, state.durationObject = "durationObject", duration
            state.value, state.total = nil, nil
          end
          if cooldown and ReadBoolean(cooldown.isEnabled) == false then state.isReady, state.onCooldown = false, true end
        end
        if event ~= "OPTIONS" then
          if showMode == "cooldown" then state.show = state.onCooldown == true elseif showMode == "ready" then state.show = state.onCooldown == false elseif showMode == "active" then state.show = state.auraActive == true elseif showMode == "missing" then state.show = state.auraActive == false end
        end
        state.hasTimer = state.durationObject ~= nil or state.progressType == "timed"
      end
    end
  end
  if event ~= "FA_CDM_REFRESH" and event ~= "OPTIONS" and #selected > 0 then QueueRefresh() end
  return true
end

Private.ExecEnv.UpdateCooldownViewerStates = Private.UpdateCooldownViewerStates
Private.ExecEnv.UpdateCDMSpell = function(allstates, config, event)
  local selected = Private.ResolveCDMSpell(config, event)
  return Private.UpdateCooldownViewerStates(allstates, selected, event, config.showGCD, config.track, config.hideGCDText, config.showMode, tonumber(config.cdmSpell), config.requireTarget)
end


local function BooleanCondition(field)
  return function(state, needle)
    return state and state.show and state[field] ~= nil and state[field] == (needle == 1)
  end
end

Private.CooldownViewerPrototype = {
  type = "cdm",
  name = "Cooldown",
  statesParameter = "full",
  progressType = "timed",
  cooldownViewerProgress = true,
  automaticrequired = true,
  force_events = "PLAYER_ENTERING_WORLD",
  internal_events = {"FA_CDM_REFRESH", "FA_CDM_LAYOUT_CHANGED"},
  GetNameAndIcon = function(trigger)
    local entries, frames = GetCatalog(), Private.CDMFrames()
    for _, id in ipairs(GetSelections(trigger)) do
      local info = entries[id] and C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
      if info then
        local identity = Private.CDMIdentity(id, entries[id], info, frames[id])
        return identity.name, identity.icon
      end
    end
    return "Cooldown Manager", 134400
  end,
  events = function()
    local events = {"PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_ICON", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "GET_ITEM_INFO_RECEIVED", "PLAYER_TARGET_CHANGED", "PLAYER_TOTEM_UPDATE"}
    if IsAvailable() then
      events[#events + 1] = "COOLDOWN_VIEWER_DATA_LOADED"
      events[#events + 1] = "COOLDOWN_VIEWER_TABLE_HOTFIXED"
      events[#events + 1] = "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
    end
    return {events = events, unit_events = {player = {"UNIT_AURA"}, target = {"UNIT_AURA", "UNIT_FACTION", "UNIT_FLAGS"}}}
  end,
  triggerFunction = function(trigger)
    if trigger.type == "cdm" then trigger.cdmSource = trigger.event == "Blizzard CDM Buff" and "buff" or "cooldown" end
    if trigger.cdmSpell ~= nil then
      return ("local config = {cdmSpell=%q, cdmExact=%s, cdmSource=%q, showGCD=%s, track=%q, hideGCDText=%s, showMode=%q, requireTarget=%s}\nreturn function(allstates,event) return Private.ExecEnv.UpdateCDMSpell(allstates,config,event) end"):format(trigger.cdmSpell, tostring(trigger.cdmExact == true), trigger.cdmSource or "cooldown", tostring(trigger.use_cdmShowGCD == true), trigger.cdmTrack or "auto", tostring(trigger.cdmHideGCDText ~= false), trigger.cdmSource == "buff" and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always"), tostring(trigger.cdmSource == "buff" and trigger.cdmRequireTarget == true))
    end
    local selected = {}
    for key, enabled in pairs(trigger.cdmSpells and trigger.cdmSpells.multi or {}) do
      local id = tonumber(key)
      if enabled and id then selected[#selected + 1] = ("[%d]=true"):format(id) end
    end
    return ("local config={type='cdm',event=%q,cdmSpells={multi={%s}}}\nreturn function(allstates,event) local selected=Private.ExecEnv.GetCDMPickerSelections(config,event); return Private.ExecEnv.UpdateCooldownViewerStates(allstates,selected,event,%s,%q,%s,%q,nil,%s) end"):format(trigger.event or "Blizzard Cooldown Manager", table.concat(selected, ","), tostring(trigger.use_cdmShowGCD == true), trigger.cdmTrack or "auto", tostring(trigger.cdmHideGCDText ~= false), trigger.event == "Blizzard CDM Buff" and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always"), tostring(trigger.event == "Blizzard CDM Buff" and trigger.cdmRequireTarget == true))
  end,
  args = {
    {
      name = "cdmSpells",
      display = "Cooldown Manager entries",
      type = "multiselect",
      required = true,
      multiNoSingle = true,
      sorted = true,
      values = GetValues,
    },
    {
      name = "cdmShowGCD",
      display = "Include global cooldown",
      type = "toggle",
    },
    {
      name = "spellId",
      display = "Spell ID",
      hidden = true,
      conditionType = "number",
      operator_types = "only_equal",
    },
    {
      name = "name",
      display = "Spell Name",
      hidden = true,
      conditionType = "string",
    },
    {
      name = "onCooldown",
      display = "On Cooldown",
      hidden = true,
      conditionType = "bool",
      conditionTest = BooleanCondition("onCooldown"),
    },
    {
      name = "isReady",
      display = "Ready",
      hidden = true,
      conditionType = "bool",
      conditionTest = BooleanCondition("isReady"),
    },
    {
      name = "recharging",
      display = "Recharging",
      hidden = true,
      conditionType = "bool",
      conditionTest = BooleanCondition("recharging"),
    },
  },
}

for _, field in ipairs({{"itemId", "Item ID", "number"}, {"cdmCategory", "CDM Category", "string"}, {"cdmDisplayed", "Displayed in CDM", "bool"}, {"auraActive", "Aura Active (when readable)", "bool"}, {"hasTimer", "Timer Available", "bool"}}) do
  local arg = {name = field[1], display = field[2], conditionType = field[3], hidden = true}
  if field[3] == "bool" then arg.conditionTest = BooleanCondition(field[1]) end
  if field[3] == "number" then arg.operator_types = "only_equal" end
  table.insert(Private.CooldownViewerPrototype.args, arg)
end

if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
    catalog = nil
    C_Timer.After(0, function()
      if Private.ScanEvents then Private.ScanEvents("FA_CDM_LAYOUT_CHANGED") end
    end)
  end, Private.CooldownViewerPrototype)
end

Private.CooldownViewerBuffPrototype = {}
for key, value in pairs(Private.CooldownViewerPrototype) do Private.CooldownViewerBuffPrototype[key] = value end
Private.CooldownViewerBuffPrototype.name = "Aura"

-- Conditions must describe the selected CDM subtype, not fields it never supplies.
local buffArgs, cooldownArgs = {}, {}
for _, arg in ipairs(Private.CooldownViewerPrototype.args) do
  if arg.name ~= "hasTimer" then
    if arg.name ~= "onCooldown" and arg.name ~= "isReady" and arg.name ~= "recharging" and arg.name ~= "cdmShowGCD" then
      buffArgs[#buffArgs + 1] = arg
    end
    if arg.name ~= "auraActive" then cooldownArgs[#cooldownArgs + 1] = arg end
  end
end
Private.CooldownViewerBuffPrototype.args = buffArgs
Private.CooldownViewerPrototype.args = cooldownArgs

Private.ExecEnv.GetCDMPickerSelections = Private.GetCDMPickerSelections
Private.CooldownViewerUtilityPrototype = {}
Private.CooldownViewerItemPrototype = {}
for key, value in pairs(Private.CooldownViewerPrototype) do
  Private.CooldownViewerUtilityPrototype[key] = value
  Private.CooldownViewerItemPrototype[key] = value
end
Private.CooldownViewerUtilityPrototype.name = "Utility"
Private.CooldownViewerItemPrototype.name = "Item"
