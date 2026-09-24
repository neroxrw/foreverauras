if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

local catalog
local refreshEvents = {
  PLAYER_ENTERING_WORLD = true,
  PLAYER_SPECIALIZATION_CHANGED = true,
  SPELLS_CHANGED = true,
  PLAYER_EQUIPMENT_CHANGED = true,
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
  local batch = Private.cdmScanBatch
  if batch and batch.catalog then return batch.catalog end
  if catalog and not refresh then
    if batch then batch.catalog = catalog end
    return catalog
  end
  catalog = IsAvailable() and Private.CDMCatalog() or {}
  if batch then batch.catalog = catalog end
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

-- nil uses the entry picker; an empty filter selects nothing.
function Private.CDMSpellQueries(trigger)
  if not (trigger.cdmUseNames or trigger.cdmUseExactIDs or (trigger.event == "Blizzard CDM Item" and trigger.cdmUseItemIDs)) then return end
  local queries, seen = {}, {}
  local function Add(values, exact, itemExact)
    for _, value in ipairs(values or {}) do
      local query = tostring(value):match("^%s*(.-)%s*$")
      local key = (itemExact and "item:" or exact and "id:" or "name:") .. query
      if query ~= "" and not seen[key] then
        seen[key] = true
        local buff = trigger.event == "Blizzard CDM Buff"
        queries[#queries + 1] = {type = "cdm", event = trigger.event, cdmSource = buff and "buff" or "cooldown",
          cdmSelection = "spell", cdmSpell = query, cdmExact = exact, cdmItemExact = itemExact == true, use_ignoreSpellKnown = trigger.use_ignoreSpellKnown,
          showGCD = trigger.use_cdmShowGCD == true, track = trigger.cdmTrack or "auto", hideGCDText = trigger.cdmHideGCDText ~= false,
          showMode = buff and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always"),
          requireTarget = buff and trigger.cdmRequireTarget == true}
      end
    end
  end
  if trigger.cdmUseNames then Add(trigger.cdmNames, false) end
  if trigger.cdmUseExactIDs then Add(trigger.cdmExactIDs, true) end
  if trigger.event == "Blizzard CDM Item" and trigger.cdmUseItemIDs then Add(trigger.cdmItemIDs, false, true) end
  return queries
end

local resolved = {}
function Private.ResolveCDMSpell(trigger, event)
  if trigger.type == "cdm" then trigger.cdmSource = trigger.event == "Blizzard CDM Buff" and "buff" or "cooldown" end
  if refreshEvents[event] then Private.CDMResetIdentities() end
  local entries = GetCatalog(refreshEvents[event] or event == "OPTIONS")
  local query = tostring(trigger.cdmSpell or ""):match("^%s*(.-)%s*$")
  if trigger.event == "Blizzard CDM Item" then
    -- Equipment and category-source identities can change without a catalog change.
    local selected = {buffSpellIDsByEntry = {}}
    local id = tonumber(query)
    local spell = id and not trigger.cdmItemExact and C_Spell.GetSpellInfo(id)
    local name = (spell and spell.name or query):lower()
    local frames = Private.CDMFrames()
    for entryID, entry in pairs(entries) do
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(entryID)
      if info and Private.CDMEntryMatches(trigger, entry, info) then
        local identity = Private.CDMIdentity(entryID, entry, info, frames[entryID])
        local useSpell
        if identity.itemID and C_Item and C_Item.GetItemSpell then
          local _, spellID = C_Item.GetItemSpell(identity.itemID)
          useSpell = spellID
        end
        local spellInfo = (useSpell or identity.spellID) and C_Spell.GetSpellInfo(useSpell or identity.spellID)
        local matches
        if trigger.cdmItemExact then
          matches = id and identity.itemID == id
        elseif trigger.cdmExact then
          matches = id and (ExactMatch(info, id) > 0 or identity.spellID == id or useSpell == id)
        else
          matches = query ~= "" and (identity.name:lower() == name or spellInfo and spellInfo.name:lower() == name)
        end
        if matches then selected[#selected + 1] = entryID end
      end
    end
    table.sort(selected)
    return selected
  end
  local key = tostring(trigger.cdmSelection) .. ":" .. tostring(trigger.event) .. ":" .. query .. ":" .. tostring(trigger.cdmExact) .. ":" .. (trigger.cdmSource or "cooldown") .. ":" .. tostring(trigger.use_ignoreSpellKnown)
  if resolved.entries ~= entries then resolved = {entries = entries} end
  if resolved[key] then return resolved[key] end
  local id = tonumber(query)
  if trigger.cdmExact and not id then return {} end
  local spell = id and C_Spell.GetSpellInfo(id)
  local name = (spell and spell.name or query):lower()
  local exact = trigger.cdmExact == true
  if trigger.event == "Blizzard CDM Buff" and not exact then
    local frames = Private.CDMFrames()
    local bestEntry, bestSpell, bestRank, bestDirect
    for entryID, entry in pairs(entries) do
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(entryID)
      if info and Private.CDMIsBuff(entry.category) then
        local displayed = Private.CDMEntryMatches(trigger, entry, info)
        local ids = Private.CDMAuraSpellIDs(info)
        local frame = frames[entryID]
        local frameSpell = frame and frame.GetSpellID and frame:GetSpellID()
        if IsReadable(frameSpell) and type(frameSpell) == "number" then ids[#ids + 1] = frameSpell end
        for _, spellID in ipairs(ids) do
          local candidate = C_Spell.GetSpellInfo(spellID)
          if candidate and candidate.name:lower() == name and ForeverAuras.IsSpellKnownIncludingPet(spellID) then
            local rank = SpellRank(spellID) or 0
            local direct = IsReadable(info.spellID) and info.spellID == spellID and 1 or 0
            if not bestSpell or rank > bestRank or (rank == bestRank and displayed and (not bestEntry or direct > bestDirect or (direct == bestDirect and entryID < bestEntry))) then
              bestEntry, bestSpell, bestRank, bestDirect = displayed and entryID or nil, spellID, rank, direct
            end
          end
        end
      end
    end
    -- Names follow one learned rank and one CDM entry, never a union of rank states.
    local selected = bestEntry and {bestEntry} or {}
    selected.singleClone, selected.buffName = true, name
    selected.buffResolvedSpellID = bestSpell
    selected.buffSpellIDs = bestSpell and {bestSpell} or {}
    resolved[key] = selected
    return selected
  end
  local anyBuffRank = not exact and trigger.cdmSource == "buff"
  local buffSpellIDs, seen, buffEntryIDs = {}, {}, {}
  local function AddBuffID(spellID)
    if not IsReadable(spellID) or type(spellID) ~= "number" or seen[spellID] then return end
    local spell = C_Spell.GetSpellInfo(spellID)
    if spell and spell.name:lower() == name then seen[spellID] = true; buffSpellIDs[#buffSpellIDs + 1] = spellID end
  end
  local best, bestRank, bestScore
  for entryID, entry in pairs(entries) do
    if (entry.known or exact or anyBuffRank or trigger.use_ignoreSpellKnown) and Private.CDMIsBuff(entry.category) == (trigger.cdmSource == "buff") then
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(entryID)
      if info and (trigger.cdmSelection ~= "spell" or Private.CDMEntryMatches(trigger, entry, info)) then
        local identity = Private.CDMIdentity(entryID, entry, info)
        local score = exact and ExactMatch(info, id) or 1
        local matches = exact and score > 0 or not exact and identity.name:lower() == name
        local auraSpellIDs = anyBuffRank and Private.CDMAuraSpellIDs(info)
        -- A CDM entry can display a linked effect with a different name from its base aura.
        if anyBuffRank and not matches then
          for _, spellID in ipairs(auraSpellIDs) do
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name:lower() == name then matches = true; break end
          end
        end
        if matches and anyBuffRank then
          buffEntryIDs[#buffEntryIDs + 1] = entryID
          AddBuffID(identity.spellID)
          for _, spellID in ipairs(auraSpellIDs) do AddBuffID(spellID) end
          score = entry.known and 1 or 0
        end
        if matches and identity.spellID then
          local subtext = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(trigger.cdmSelection == "spell" and info.spellID or identity.spellID)
          local rank = IsReadable(subtext) and type(subtext) == "string" and tonumber(subtext:match("%d+")) or 0
          if not best or score > bestScore or (score == bestScore and (rank > bestRank or (rank == bestRank and entryID < best))) then best, bestRank, bestScore = entryID, rank, score end
        end
      end
    end
  end
  resolved[key] = best and {best} or {}
  if anyBuffRank then
    table.sort(buffSpellIDs)
    table.sort(buffEntryIDs)
    resolved[key].buffSpellIDs = buffSpellIDs
    if trigger.cdmSelection == "spell" then resolved[key].buffEntryIDs = buffEntryIDs end
  end
  if trigger.cdmSelection == "spell" then resolved[key].singleClone = true end
  return resolved[key]
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
  local queries = Private.CDMSpellQueries(trigger)
  if queries then
    local bindings = {}
    for _, query in ipairs(queries) do
      for _, ids in ipairs(Private.CDMNativeSelections(query)) do bindings[#bindings + 1] = ids end
    end
    return bindings
  end
  if trigger.cdmSpell ~= nil and tostring(trigger.cdmSpell):find("%S") and trigger.event ~= "Blizzard CDM Item" then
    local selected = Private.ResolveCDMSpell(trigger)
    local id = trigger.cdmExact and tonumber(trigger.cdmSpell)
    return {id and selected[1] and {id} or selected.buffSpellIDs}
  end
  local selected = Private.GetCDMPickerSelections(trigger, "OPTIONS")
  local bindings = {}
  for _, id in ipairs(selected) do bindings[#bindings + 1] = selected.buffSpellIDsByEntry[id] end
  return bindings
end

local function GetSelections(trigger)
  local queries = Private.CDMSpellQueries(trigger)
  if queries then
    local selected, seen = {}, {}
    for _, query in ipairs(queries) do
      for _, id in ipairs(Private.ResolveCDMSpell(query)) do
        if not seen[id] then selected[#selected + 1] = id; seen[id] = true end
      end
    end
    return selected
  end
  if trigger.cdmSpell ~= nil and tostring(trigger.cdmSpell):find("%S") and trigger.event ~= "Blizzard CDM Item" then return Private.ResolveCDMSpell(trigger) end
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
      local learned = entry.known and "" or " â€” Not learned"
      values[id] = placement .. " â€” " .. Private.CDMCategoryName(entry.category) .. " â€” " .. identity.name .. " [" .. (identity.spellID or identity.itemID or "Unknown") .. "]" .. learned
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

local spellCooldowns = {}
local function GetSpellCooldownState(spellID, event)
  local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
  local active = info and ReadBoolean(info.isActive)
  if active == nil then return end
  local status = spellCooldowns[spellID]
  if not status then status = {}; spellCooldowns[spellID] = status end
  if not active then
    status.onCooldown, status.onGCD, status.gcdReadyAt, status.gcdStart = false, false, nil, nil
  end
  -- Blizzard only guarantees isOnGCD during SPELL_UPDATE_COOLDOWN.
  if active and event == "SPELL_UPDATE_COOLDOWN" and IsReadable(info.isOnGCD) then
    local onGCD = info.isOnGCD == true
    local start = IsReadable(info.startTime) and type(info.startTime) == "number" and info.startTime or nil
    if onGCD then
      if status.onGCD ~= true or (start and status.gcdStart and start ~= status.gcdStart) then
        local readyAt = GetTime() + 0.20
        status.gcdReadyAt = readyAt
        C_Timer.After(0.20, function()
          if status.gcdReadyAt == readyAt then Private.QueueCDMRefresh() end
        end)
      end
      status.gcdStart = start
    else
      status.gcdReadyAt, status.gcdStart = nil, nil
    end
    status.onCooldown, status.onGCD = not onGCD, onGCD
  end
  return status.onCooldown, true, status.onGCD, status.gcdReadyAt
end

local function QueueRefresh()
  Private.QueueCDMRefresh()
end

local function BuildCooldownViewerStates(allstates, selected, event, showGCD, track, hideGCDText, showMode, exactID, requireTarget, ignoreSpellKnown)
  if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then Private.CDMResetIdentities() end
  local available = GetCatalog(refreshEvents[event] or event == "OPTIONS")
  local frames = Private.CDMFrames()
  for _, state in pairs(allstates) do
    state.show = false
    state.changed = true
  end

  if event ~= "FA_CDM_REFRESH" and event ~= "OPTIONS"
      and event ~= "GET_ITEM_INFO_RECEIVED" and event ~= "ITEM_DATA_LOAD_RESULT"
      and #selected > 0 then QueueRefresh() end
  if not IsAvailable() then return true end
  if requireTarget and event ~= "OPTIONS" then
    local exists = UnitExists("target")
    local attackable = UnitCanAttack("player", "target")
    if not IsReadable(exists) or not IsReadable(attackable) then return true end
    if not exists or not attackable then return true end
  end

  for index, cooldownID in ipairs(selected) do
    local entry = available[cooldownID]
    if entry and (entry.known or exactID or selected.buffSpellIDs or selected.buffSpellIDsByEntry or ignoreSpellKnown) then
      local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
      if info then
        local identity = Private.CDMIdentity(cooldownID, entry, info, frames[cooldownID])
        local displaySpellID = exactID or selected.buffResolvedSpellID
        if displaySpellID then
          local spell = C_Spell.GetSpellInfo(displaySpellID)
          identity = {spellID = displaySpellID, name = spell and spell.name or identity.name, icon = spell and spell.iconID or identity.icon}
        end
        local cloneID = selected.singleClone and "spell" or tostring(cooldownID)
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
        state.cdmTextDurationObject = nil
        state.cdmSuppressGCD = false
        state.cdmNativePaused = false
        state.cdmBuff = Private.CDMIsBuff(entry.category)
        local bindingIDs = selected.buffSpellIDsByEntry and selected.buffSpellIDsByEntry[cooldownID]
        state.cdmAuraSpellIDs = state.cdmBuff and (bindingIDs or (exactID and {exactID}) or selected.buffSpellIDs or {identity.spellID}) or nil
        state.cdmTextPreview = event == "OPTIONS"
        state.cdmCountdownSource, state.cdmStackSource, state.cdmTextRecord, state.cdmDispelName = nil, nil, nil, nil
        state.onCooldown, state.isReady, state.recharging, state.stacks, state.auraActive = nil, nil, nil, nil, nil
        state.cdmGCDOnly, state.cdmHideGCDText = false, hideGCDText == true

        if Private.CDMIsBuff(entry.category) then
          if selected.buffEntryIDs then
            local bestAura, bestScore
            for _, auraID in ipairs(selected.buffEntryIDs) do
              local auraInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(auraID)
              if auraInfo and available[auraID] then
                local candidate = {}
                local auraIdentity = Private.CDMIdentity(auraID, available[auraID], auraInfo, frames[auraID])
                Private.CDMApplyAura(candidate, auraIdentity, auraInfo, frames[auraID], nil, selected.buffSpellIDs)
                local score = candidate.auraActive == true and 2 or candidate.auraActive == nil and 1 or 0
                if not bestAura or score > bestScore then bestAura, bestScore = candidate, score end
              end
            end
            for key, value in pairs(bestAura or {}) do state[key] = value end
            if state.progressType ~= "static" then state.value, state.total = nil, nil end
          else
          Private.CDMApplyAura(state, identity, info, frames[cooldownID], exactID, bindingIDs or selected.buffSpellIDs)
          end
        elseif identity.slot or identity.itemID then
          Private.CDMApplyItem(state, identity)
        elseif identity.spellID then
          local spellID = identity.spellID
          if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
            local override = C_SpellBook.FindSpellOverrideByID(spellID)
            if IsReadable(override) and type(override) == "number" and override > 0 then spellID = override end
          end
          local realDuration = C_Spell.GetSpellCooldownDuration(spellID, true)
          local onCooldown, hasCooldownFlags, onGCD, gcdReadyAt = GetSpellCooldownState(spellID, event)
          local native = Private.CDMGetNativeCooldown(frames[cooldownID], identity.spellID)
          state.cdmNativeRevision = native and native.revision
          local duration = native and native.duration or nil
          state.cdmNativePaused = native and native.paused == true or false
          if native then
            state.inRange = native.inRange
            state.stacks = native.charges
            if native.charges ~= nil then state.isReady = native.charges > 0 end
            if native.onGCD ~= nil then state.cdmGCDOnly = native.onGCD end
            if native.onCooldown ~= nil then
              state.onCooldown = native.onCooldown
              if state.stacks == nil then state.isReady = not native.onCooldown end
            end
            if native.recharging ~= nil then state.recharging = native.recharging end
          end
          -- Native frame flags can be secret even when these API flags are public.
          if onCooldown ~= nil then
            state.onCooldown, state.isReady = onCooldown, not onCooldown
            if onCooldown then
              duration = realDuration
              state.cdmGCDOnly, state.cdmNativePaused = false, false
            elseif onGCD then
              duration = showGCD and C_Spell.GetSpellCooldownDuration(spellID) or nil
              state.cdmGCDOnly, state.cdmNativePaused = true, false
            else
              duration = realDuration
              state.cdmGCDOnly, state.cdmNativePaused = false, false
            end
          elseif hasCooldownFlags and not state.cdmGCDOnly then
            duration = realDuration
            state.cdmNativePaused = false
          end
          local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
          if charges then
            local count = charges.currentCharges
            local recharging = ReadBoolean(charges.isActive)
            if recharging ~= nil then state.recharging = recharging end
            if IsReadable(count) and type(count) == "number" then
              state.stacks = count
              state.isReady, state.onCooldown = count > 0, count == 0
            elseif native and native.recharging == true then
              state.isReady, state.onCooldown = true, false
            end
          end
          if C_Spell.GetSpellChargeDuration and (track == "charges" or (track == "auto" and state.recharging == true)) then
            local chargeDuration = C_Spell.GetSpellChargeDuration(spellID)
            if chargeDuration then
              duration = chargeDuration
              state.cdmGCDOnly, state.cdmNativePaused = false, false
            end
          end
          local holdUntil = onGCD and gcdReadyAt or (native and native.gcdReadyAt)
          if state.cdmGCDOnly and (not showGCD or (holdUntil and GetTime() < holdUntil)) then
            duration = nil
          end
          state.cdmSuppressGCD = not duration
          if duration then
            state.progressType, state.durationObject = "durationObject", duration
            state.value, state.total = nil, nil
          else
            -- Zero duration keeps %p empty and progress bars unfilled.
            state.progressType, state.duration, state.expirationTime = "timed", 0, 0
            state.value, state.total = nil, nil
          end
          if hideGCDText then
            -- Hide GCD text without hiding a real cooldown or recharge timer.
            state.cdmTextDurationObject = state.cdmGCDOnly and realDuration or duration
          end
        end
        if event ~= "OPTIONS" then
          if not ignoreSpellKnown and not state.cdmBuff and not Private.CDMEntryMatches({event = "Blizzard CDM Item"}, entry, info) then
            local known = false
            for _, id in pairs({identity.spellID, info.spellID, info.overrideSpellID, info.linkedSpellID}) do
              if IsReadable(id) and type(id) == "number" and id > 0 and id < 2147483647
                  and ForeverAuras.IsSpellKnownIncludingPet(id) then known = true; break end
            end
            if not known then state.show = false end
          end
          if state.show and showMode == "cooldown" then state.show = state.onCooldown == true elseif state.show and showMode == "ready" then state.show = state.onCooldown == false elseif state.show and showMode == "active" then state.show = state.auraActive == true elseif state.show and showMode == "missing" then state.show = state.auraActive == false end
        end
        state.hasTimer = state.durationObject ~= nil or state.progressType == "timed"
      end
    end
  end
  return true
end

-- Compare snapshots because the trigger engine modifies live states.
-- Secret values and mutable aura bindings still require an update.
local previousOutputs = setmetatable({}, {__mode = "k"})
local function GetOutputs(selected, event, showGCD, track, hideGCDText, showMode, exactID, requireTarget, ignoreSpellKnown)
  local batch = Private.cdmScanBatch
  local cache, key
  if batch then
    batch.outputs = batch.outputs or {}
    cache = batch.outputs[selected]
    if not cache then cache = {}; batch.outputs[selected] = cache end
    key = table.concat({event or "", tostring(showGCD), tostring(track), tostring(hideGCDText),
      tostring(showMode), tostring(exactID), tostring(requireTarget), tostring(ignoreSpellKnown)}, ":")
    if cache[key] then return cache[key] end
  end
  local outputs = {}
  BuildCooldownViewerStates(outputs, selected, event, showGCD, track, hideGCDText, showMode, exactID, requireTarget, ignoreSpellKnown)
  if cache then cache[key] = outputs end
  return outputs
end
local function SameOutput(previous, current)
  if not previous or current.cdmBuff then return false end
  -- Combat timers can change in place while their values remain unreadable.
  if InCombatLockdown and InCombatLockdown() then return false end
  for key, value in pairs(current) do
    if key ~= "changed" then
      local old = previous[key]
      if not IsReadable(value) or not IsReadable(old) or value ~= old then return false end
    end
  end
  for key in pairs(previous) do
    if key ~= "changed" and current[key] == nil then return false end
  end
  return true
end

local function CommitStates(allstates, outputs)
  local previous = previousOutputs[allstates] or {}
  local changed = false
  for key, output in pairs(outputs) do
    local state = allstates[key]
    if not state or not SameOutput(previous[key], output) or state.show ~= output.show then
      if not state then state = {}; allstates[key] = state end
      for field in pairs(previous[key] or {}) do
        if field ~= "changed" then state[field] = nil end
      end
      for field, value in pairs(output) do state[field] = value end
      state.changed = true
      changed = true
    end
  end
  for key, state in pairs(allstates) do
    if not outputs[key] and state.show then
      for field in pairs(previous[key] or {}) do
        if field ~= "changed" then state[field] = nil end
      end
      state.show, state.changed = false, true
      changed = true
    end
  end
  previousOutputs[allstates] = outputs
  return changed
end

function Private.UpdateCooldownViewerStates(allstates, ...)
  return CommitStates(allstates, GetOutputs(...))
end

Private.ExecEnv.UpdateCooldownViewerStates = Private.UpdateCooldownViewerStates
Private.ExecEnv.UpdateCDMSpell = function(allstates, config, event, ...)
  local selected = Private.ResolveCDMSpell(config, event)
  return Private.UpdateCooldownViewerStates(allstates, selected, event, config.showGCD, config.track, config.hideGCDText, config.showMode, config.cdmExact and tonumber(config.cdmSpell) or nil, config.requireTarget, config.use_ignoreSpellKnown)
end

function Private.ExecEnv.UpdateCDMSelectionList(allstates, queries, event)
  local outputs = {}
  for queryIndex, query in ipairs(queries) do
    local selected = Private.ResolveCDMSpell(query, event)
    local temporary = GetOutputs(selected, event, query.showGCD, query.track, query.hideGCDText,
      query.showMode, query.event ~= "Blizzard CDM Item" and query.cdmExact and tonumber(query.cdmSpell) or nil, query.requireTarget, query.use_ignoreSpellKnown)
    for _, state in pairs(temporary) do
      -- Cooldown and item aliases share a clone; buff filters each own their clone.
      local key = tostring(state.cooldownID) .. ":" .. tostring(state.spellId)
      if query.event == "Blizzard CDM Buff" then
        key = query.cdmExact and ("id:" .. tostring(tonumber(query.cdmSpell))) or ("name:" .. selected.buffName)
        local clone = {}
        for field, value in pairs(state) do clone[field] = value end
        clone.index = queryIndex
        state = clone
      end
      if not outputs[key] or not outputs[key].show or state.show then outputs[key] = state end
    end
  end
  return CommitStates(allstates, outputs)
end

local function BooleanCondition(field)
  return function(state, needle)
    return state and state.show and state[field] ~= nil and state[field] == (needle == 1)
  end
end

Private.CooldownViewerPrototype = {
  type = "cdm",
  name = "Essential Cooldowns",
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
    local events = {"PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_ICON", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED", "PLAYER_TOTEM_UPDATE"}
    if IsAvailable() then
      events[#events + 1] = "COOLDOWN_VIEWER_DATA_LOADED"
      events[#events + 1] = "COOLDOWN_VIEWER_TABLE_HOTFIXED"
      events[#events + 1] = "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED"
    end
    return {events = events, unit_events = {player = {"UNIT_AURA"}, target = {"UNIT_AURA", "UNIT_FACTION", "UNIT_FLAGS"}}}
  end,
  triggerFunction = function(trigger)
    if trigger.event == "Blizzard CDM Buff" and (trigger.cdmUseRemaining or trigger.cdmUseStacks or trigger.cdmUseTotal or trigger.cdmUseElapsed) then
      local base = {}
      for key, value in pairs(trigger) do base[key] = value end
      base.cdmUseRemaining, base.cdmUseStacks, base.cdmUseTotal, base.cdmUseElapsed = nil, nil, nil, nil
      local source = Private.CooldownViewerPrototype.triggerFunction(base)
      return ("local update=(function() %s end)()\nlocal rawStates={}\nreturn function(allstates,event) update(rawStates,event); return Private.ExecEnv.UpdateCDMBuffFilters(allstates,rawStates,event,%q,%q,%q,%q,%q,%q,%q,%q) end"):format(source, trigger.cdmUseRemaining and tostring(trigger.cdmRemainingTime or 10) or "", trigger.cdmRemainingOperator or "<", trigger.cdmUseStacks and tostring(trigger.cdmStackCount or 1) or "", trigger.cdmStackOperator or ">=", trigger.cdmUseTotal and tostring(trigger.cdmTotalTime or 10) or "", trigger.cdmTotalOperator or "<", trigger.cdmUseElapsed and tostring(trigger.cdmElapsedTime or 10) or "", trigger.cdmElapsedOperator or ">=")
    end
    local queries = Private.CDMSpellQueries(trigger)
    if queries then
      local serialized = {}
      for _, query in ipairs(queries) do
        serialized[#serialized + 1] = ("{type='cdm',event=%q,cdmSelection='spell',cdmSpell=%q,cdmExact=%s,cdmItemExact=%s,use_ignoreSpellKnown=%s,showGCD=%s,track=%q,hideGCDText=%s,showMode=%q,requireTarget=%s}"):format(
          query.event, query.cdmSpell, tostring(query.cdmExact), tostring(query.cdmItemExact), tostring(query.use_ignoreSpellKnown == true),
          tostring(query.showGCD), query.track, tostring(query.hideGCDText), query.showMode, tostring(query.requireTarget))
      end
      return ("local queries={%s}\nreturn function(allstates,event) return Private.ExecEnv.UpdateCDMSelectionList(allstates,queries,event) end"):format(table.concat(serialized, ","))
    end
    if trigger.type == "cdm" then trigger.cdmSource = trigger.event == "Blizzard CDM Buff" and "buff" or "cooldown" end
    if trigger.cdmSpell ~= nil and tostring(trigger.cdmSpell):find("%S") and trigger.event ~= "Blizzard CDM Item" then
      return ("local config = {type=%q,event=%q,cdmSelection=%q,cdmSpell=%q, cdmExact=%s, cdmSource=%q, showGCD=%s, track=%q, hideGCDText=%s, showMode=%q, requireTarget=%s, use_ignoreSpellKnown=%s}\nreturn function(allstates,event,...) return Private.ExecEnv.UpdateCDMSpell(allstates,config,event,...) end"):format(trigger.type or "", trigger.event or "", trigger.cdmSelection or "", trigger.cdmSpell, tostring(trigger.cdmExact == true), trigger.cdmSource or "cooldown", tostring(trigger.use_cdmShowGCD == true), trigger.cdmTrack or "auto", tostring(trigger.cdmHideGCDText ~= false), trigger.cdmSource == "buff" and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always"), tostring(trigger.cdmSource == "buff" and trigger.cdmRequireTarget == true), tostring(trigger.use_ignoreSpellKnown == true))
    end
    local selected = {}
    for key, enabled in pairs(trigger.cdmSpells and trigger.cdmSpells.multi or {}) do
      local id = tonumber(key)
      if enabled and id then selected[#selected + 1] = ("[%d]=true"):format(id) end
    end
    return ("local config={type='cdm',event=%q,cdmSpells={multi={%s}}}\nreturn function(allstates,event,...) local selected=Private.ExecEnv.GetCDMPickerSelections(config,event); return Private.ExecEnv.UpdateCooldownViewerStates(allstates,selected,event,%s,%q,%s,%q,nil,%s,%s) end"):format(trigger.event or "Blizzard Cooldown Manager", table.concat(selected, ","), tostring(trigger.use_cdmShowGCD == true), trigger.cdmTrack or "auto", tostring(trigger.cdmHideGCDText ~= false), trigger.event == "Blizzard CDM Buff" and (trigger.cdmBuffShow or "active") or (trigger.cdmShow or "always"), tostring(trigger.event == "Blizzard CDM Buff" and trigger.cdmRequireTarget == true), tostring(trigger.use_ignoreSpellKnown == true))
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
Private.CooldownViewerBuffPrototype.name = "Buff/Debuff"

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
local function BuffRemainingTime(state)
  if not state or not state.show or not state.cdmBuff or state.auraActive ~= true then return end
  local remaining, timeScale = nil, 1
  if state.durationObject then
    local total = state.durationObject:GetTotalDuration()
    if not IsReadable(total) or type(total) ~= "number" or total <= 0 then return end
    remaining = state.durationObject:GetRemainingDuration()
  else
    local duration, expiration, rate = state.duration, state.expirationTime, state.modRate
    if not IsReadable(duration) or not IsReadable(expiration) or not IsReadable(rate) then return end
    if type(duration) ~= "number" or duration <= 0 or type(expiration) ~= "number" then return end
    rate = rate or 1
    if type(rate) ~= "number" or rate <= 0 then return end
    remaining = (expiration - GetTime()) / rate
    timeScale = rate
  end
  if IsReadable(remaining) and type(remaining) == "number" and remaining == remaining and remaining < math.huge then
    return math.max(0, remaining), timeScale
  end
end
local remainingCondition = {
  name = "cdmRemaining",
  display = "Remaining Time (when readable)",
  hidden = true,
  conditionType = "number",
  noProgressSource = true,
  conditionTest = function(state, value, op)
    local remaining = BuffRemainingTime(state)
    value = tonumber(value)
    if remaining == nil or not value then return false end
    if op == "<" then return remaining < value
    elseif op == "<=" then return remaining <= value
    elseif op == ">" then return remaining > value
    elseif op == ">=" then return remaining >= value
    elseif op == "==" then return math.abs(remaining - value) < 0.05
    elseif op == "~=" then return math.abs(remaining - value) >= 0.05 end
    return false
  end,
  conditionRecheckTime = function(state, value)
    local remaining, timeScale = BuffRemainingTime(state)
    value = tonumber(value)
    if not remaining or remaining <= 0 or not value then return end
    local delay = remaining * timeScale
    for _, boundary in ipairs({value + 0.05, value, value - 0.05}) do
      if boundary >= 0 and remaining >= boundary then
        delay = math.min(delay, (remaining - boundary) * timeScale + 0.001)
      end
    end
    return GetTime() + math.max(0.001, delay)
  end,
}
buffArgs[#buffArgs + 1] = remainingCondition
local remainingWakeups = setmetatable({}, {__mode = "k"})
local function BuffStacksMatch(state, value, op)
  local stacks = state.stacks
  if state.auraActive ~= true or not IsReadable(stacks) or type(stacks) ~= "number" then return false end
  if op == "<" then return stacks < value
  elseif op == "<=" then return stacks <= value
  elseif op == ">" then return stacks > value
  elseif op == ">=" then return stacks >= value
  elseif op == "==" then return stacks == value
  elseif op == "~=" then return stacks ~= value end
  return false
end
local function BuffTimeValue(state, elapsed)
  if not state.show or not state.cdmBuff or state.auraActive ~= true then return end
  local total, value, timeScale = nil, nil, 1
  if state.durationObject then
    total = state.durationObject:GetTotalDuration()
    if not IsReadable(total) or type(total) ~= "number" or total <= 0 or total >= math.huge then return end
    if elapsed then value = state.durationObject:GetElapsedDuration()
    else value = total end
  else
    total, timeScale = state.duration, state.modRate
    if not IsReadable(total) or not IsReadable(timeScale) then return end
    timeScale = timeScale or 1
    if type(total) ~= "number" or total <= 0 or total >= math.huge then return end
    if type(timeScale) ~= "number" or timeScale <= 0 or timeScale >= math.huge then return end
    value = total / timeScale
    if elapsed then
      local expiration = state.expirationTime
      if not IsReadable(expiration) or type(expiration) ~= "number" then return end
      value = (GetTime() - (expiration - total)) / timeScale
    end
  end
  if IsReadable(value) and type(value) == "number" and value == value and value < math.huge then
    return math.max(0, value), timeScale
  end
end
local function BuffTimeMatches(value, threshold, op)
  if value == nil then return false end
  if op == "<" then return value < threshold
  elseif op == "<=" then return value <= threshold
  elseif op == ">" then return value > threshold
  elseif op == ">=" then return value >= threshold end
  return false
end
function Private.ExecEnv.UpdateCDMBuffFilters(allstates, rawStates, event, value, op, stackValue, stackOp, totalValue, totalOp, elapsedValue, elapsedOp)
  value, stackValue = tonumber(value), tonumber(stackValue)
  totalValue, elapsedValue = tonumber(totalValue), tonumber(elapsedValue)
  local outputs, nextCheck = {}, nil
  for key, state in pairs(rawStates) do
    local output = {}
    for field, entry in pairs(state) do output[field] = entry end
    if event ~= "OPTIONS" then
      if value then
        output.show = state.show and remainingCondition.conditionTest(state, value, op) or false
        local nextTime = remainingCondition.conditionRecheckTime(state, value)
        if nextTime and (not nextCheck or nextTime < nextCheck) then nextCheck = nextTime end
      end
      if stackValue then output.show = output.show and BuffStacksMatch(state, stackValue, stackOp) or false end
      if totalValue then output.show = output.show and BuffTimeMatches(BuffTimeValue(state), totalValue, totalOp) or false end
      if elapsedValue then
        local elapsed, timeScale = BuffTimeValue(state, true)
        output.show = output.show and BuffTimeMatches(elapsed, elapsedValue, elapsedOp) or false
        local remaining = BuffRemainingTime(state)
        if elapsed and remaining and remaining > 0 and elapsed <= elapsedValue then
          local delay = math.min((elapsedValue - elapsed) * timeScale + 0.001, remaining * timeScale)
          local nextTime = GetTime() + math.max(0.001, delay)
          if not nextCheck or nextTime < nextCheck then nextCheck = nextTime end
        end
      end
    end
    outputs[key] = output
  end
  local pending = remainingWakeups[rawStates]
  if not pending or pending.at ~= nextCheck then
    if pending and pending.timer and pending.timer.Cancel then pending.timer:Cancel() end
    remainingWakeups[rawStates] = nil
    if nextCheck then
      local wakeup = {at = nextCheck}
      remainingWakeups[rawStates] = wakeup
      local function Refresh()
        if remainingWakeups[rawStates] == wakeup then
          remainingWakeups[rawStates] = nil
          Private.QueueCDMRefresh()
        end
      end
      local delay = math.max(0.001, nextCheck - GetTime())
      if C_Timer.NewTimer then wakeup.timer = C_Timer.NewTimer(delay, Refresh)
      else C_Timer.After(delay, Refresh) end
    end
  end
  return CommitStates(allstates, outputs)
end
Private.CooldownViewerPrototype.args = cooldownArgs

Private.ExecEnv.GetCDMPickerSelections = Private.GetCDMPickerSelections
Private.CooldownViewerUtilityPrototype = {}
Private.CooldownViewerItemPrototype = {}
for key, value in pairs(Private.CooldownViewerPrototype) do
  Private.CooldownViewerUtilityPrototype[key] = value
  Private.CooldownViewerItemPrototype[key] = value
end
Private.CooldownViewerUtilityPrototype.name = "Utility Cooldowns"
Private.CooldownViewerItemPrototype.name = "Item"
local spellArgs = {}
for i, arg in ipairs(Private.CooldownViewerPrototype.args) do spellArgs[i] = arg end
spellArgs[#spellArgs + 1] = {name = "inRange", display = "Spell In Range", hidden = true,
  conditionType = "bool", conditionTest = BooleanCondition("inRange")}
Private.CooldownViewerPrototype.args = spellArgs
Private.CooldownViewerUtilityPrototype.args = spellArgs
-- Item metadata events only update item triggers; they do not change the catalog.
Private.CooldownViewerItemPrototype.events = function()
  local result = Private.CooldownViewerPrototype.events()
  result.events[#result.events + 1] = "GET_ITEM_INFO_RECEIVED"
  result.events[#result.events + 1] = "ITEM_DATA_LOAD_RESULT"
  return result
end
