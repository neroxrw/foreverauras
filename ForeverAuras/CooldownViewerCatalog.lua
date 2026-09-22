if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local identities = {}

function Private.CDMResetIdentities()
  identities = {}
end

local labels = {
  Essential = "Essential", Utility = "Utility", TrackedBuff = "Tracked Buffs", TrackedBar = "Tracked Bars",
  GroupBuff = "Group Buffs", SpecAgnosticEssential = "Shared Cooldowns", SpecAgnosticTracked = "Shared Buffs",
  EquipSlotEssential = "Item Cooldowns", EquipSlotTracked = "Item Buffs",
}
local viewerNames = {"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer"}

local function Number(value)
  if not (issecretvalue and issecretvalue(value)) and type(value) == "number" then return value end
end

local function Readable(value)
  return not (issecretvalue and issecretvalue(value))
end

function Private.CDMCategoryName(category)
  for name, value in pairs(Enum.CooldownViewerCategory) do
    if value == category then return labels[name] or name end
  end
  return "Other"
end

function Private.CDMIsBuff(category)
  local c = Enum.CooldownViewerCategory
  return category == c.TrackedBuff or category == c.TrackedBar or category == c.GroupBuff or category == c.SpecAgnosticTracked or category == c.EquipSlotTracked
end

local observed = setmetatable({}, {__mode = "k"})
local observedViewers = setmetatable({}, {__mode = "k"})
local nativeRefreshQueued = false
local function NativeRefresh()
  if nativeRefreshQueued then return end
  nativeRefreshQueued = true
  C_Timer.After(0, function()
    nativeRefreshQueued = false
    if Private.ScanEvents then Private.ScanEvents("FA_CDM_REFRESH") end
  end)
end
local function Observe(frame)
  if observed[frame] or not hooksecurefunc then return end
  local record = {}
  observed[frame] = record
  local function Clear()
    record.duration, record.raw = nil, nil
    NativeRefresh()
  end
  for _, method in ipairs({"ClearAuraInstanceInfo", "OnAuraInstanceInfoCleared", "OnCooldownIDSet", "OnCooldownIDCleared"}) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, Clear) end
  end
  if type(frame.OnAuraInstanceInfoSet) == "function" then hooksecurefunc(frame, "OnAuraInstanceInfoSet", Clear) end
  if type(frame.SetAuraInstanceInfo) == "function" then hooksecurefunc(frame, "SetAuraInstanceInfo", NativeRefresh) end
  for _, method in ipairs({"OnUnitAuraRemovedEvent", "OnUnitAuraUpdatedEvent", "OnNewTarget", "OnActiveStateChanged"}) do
    if type(frame[method]) == "function" then hooksecurefunc(frame, method, NativeRefresh) end
  end
  if frame.HookScript then frame:HookScript("OnShow", NativeRefresh); frame:HookScript("OnHide", NativeRefresh) end
  local cooldown = frame.Cooldown or frame.cooldown
  if cooldown then
    if cooldown.SetCooldownFromDurationObject then
      hooksecurefunc(cooldown, "SetCooldownFromDurationObject", function(_, duration)
        record.duration, record.raw = duration, nil
        NativeRefresh()
      end)
    end
    if cooldown.SetCooldown then
      hooksecurefunc(cooldown, "SetCooldown", function(_, start, duration, modRate)
        record.duration, record.raw = nil, {start = start, duration = duration, modRate = modRate}
        NativeRefresh()
      end)
    end
    if cooldown.Clear then hooksecurefunc(cooldown, "Clear", Clear) end
  end
end

function Private.CDMFrames()
  local frames = {}
  for _, name in ipairs(viewerNames) do
    local viewer = _G[name]

    if viewer and hooksecurefunc and not observedViewers[viewer] then
      observedViewers[viewer] = true
      for _, method in ipairs({"OnUnitAura", "OnPlayerTargetChanged", "RefreshActiveFramesForTargetChange"}) do
        if type(viewer[method]) == "function" then hooksecurefunc(viewer, method, NativeRefresh) end
      end
    end
    local pool = viewer and viewer.itemFramePool
    if pool and pool.EnumerateActive then
      for frame in pool:EnumerateActive() do
        local id = Number(frame.cooldownID)
        if id then Observe(frame); frames[id] = frame end
      end
    end
  end
  return frames
end

function Private.CDMCatalog()
  local catalog = {}
  local settings = _G.CooldownViewerSettings
  local provider = settings and settings.GetDataProvider and settings:GetDataProvider()
  provider = provider or _G.CooldownViewerDataProvider
  local layout

  if provider and provider.GetDisplayData and (not provider.IsDirty or not provider:IsDirty()) then
    local data = provider:GetDisplayData()
    layout = data and data.cooldownInfoByID
  end
  local categories = {}
  local frames = Private.CDMFrames()
  for _, category in pairs(Enum.CooldownViewerCategory) do
    if type(category) == "number" and category >= 0 then categories[category] = true end
  end
  for category in pairs(categories) do
    for _, id in ipairs(C_CooldownViewer.GetCooldownViewerCategorySet(category, true) or {}) do
      if Number(id) then
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
        if info then
          local arranged = layout and layout[id]
          local placement = arranged and Number(arranged.category)
          local displayed
          if placement ~= nil then
            local c = Enum.CooldownViewerCategory
            displayed = placement == c.Essential or placement == c.Utility or placement == c.TrackedBuff or placement == c.TrackedBar
          elseif frames[id] then

            displayed = true
            local viewer = frames[id].viewerFrame
            placement = viewer and Number(viewer.cooldownViewerCategory)
          end
          catalog[id] = {
            category = placement and placement >= 0 and placement or category,
            sourceCategory = category,
            displayed = displayed,
            known = Readable(info.isKnown) and info.isKnown ~= false,
          }
        end
      end
    end
  end
  return catalog
end

function Private.CDMIdentity(id, entry, info, frame)
  local spellID = frame and frame.GetSpellID and Number(frame:GetSpellID())
  spellID = spellID or Number(info.linkedSpellID) or Number(info.overrideTooltipSpellID) or Number(info.overrideSpellID)
  if not spellID and Private.CDMIsBuff(entry.category) then
    for _, linked in ipairs(info.linkedSpellIDs or {}) do
      local candidate = Number(linked)
      if candidate and candidate > 0 then spellID = candidate; break end
    end
  end
  spellID = spellID or Number(info.spellID)
  local slot = Number(info.equipSlot)
  local itemID = slot and Number(GetInventoryItemID("player", slot))
  if not itemID and frame and frame.cooldownInfo then itemID = Number(frame.cooldownInfo.lastItemIDForCategory) end
  local categoryID = Number(info.spellCategoryID)
  if not spellID and categoryID and C_Spell.GetLastCategoryCooldownSource then
    local sourceSpell, sourceItem = C_Spell.GetLastCategoryCooldownSource(categoryID)
    spellID, itemID = Number(sourceSpell), Number(sourceItem)
  end
  local spell = spellID and spellID > 0 and C_Spell.GetSpellInfo(spellID)
  local name, icon = spell and spell.name, spell and spell.iconID
  if itemID and C_Item then
    name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
    icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or icon
  end
  local previous = identities[id] or {}
  local identity = {spellID = spellID or previous.spellID, itemID = itemID or previous.itemID, slot = slot, name = name or previous.name or (slot and ("Equipment slot " .. slot)) or ("CDM entry " .. id), icon = icon or previous.icon or 134400}
  identities[id] = identity
  return identity
end

local function SetTimes(state, startTime, duration, modRate)
  startTime, duration, modRate = Number(startTime), Number(duration), Number(modRate)
  if not startTime or not duration then return false end
  state.progressType = "timed"
  state.duration = duration
  state.expirationTime = startTime + duration
  state.modRate = modRate or 1
  state.value, state.total = nil, nil
  return true
end

function Private.CDMApplyItem(state, identity)
  local startTime, duration, enabled
  if identity.slot then
    startTime, duration, enabled = GetInventoryItemCooldown("player", identity.slot)
  elseif identity.itemID and C_Item and C_Item.GetItemCooldown then
    startTime, duration, enabled = C_Item.GetItemCooldown(identity.itemID)
  end
  if SetTimes(state, startTime, duration) then
    state.onCooldown = state.duration > 0 and state.expirationTime > GetTime()
    state.isReady = not state.onCooldown
    if Number(enabled) == 0 then state.isReady = false end
  end
end

local function ApplyAuraSource(state, unit, aura)
  state.cdmAuraFilter = "HELPFUL"
  if Readable(unit) and (unit == "player" or unit == "target") then state.cdmAuraUnit = unit end
  local harmful = aura and aura.isHarmful
  if Readable(harmful) and type(harmful) == "boolean" then
    state.cdmAuraFilter = harmful and "HARMFUL" or "HELPFUL"
  elseif state.cdmAuraUnit == "target" then
    local friend = UnitIsFriend and UnitIsFriend("player", "target")
    state.cdmAuraFilter = Readable(friend) and friend == true and "HELPFUL" or "HARMFUL"
  end
  if state.cdmAuraUnit == "target" then
    state.cdmAuraFilter = state.cdmAuraFilter == "HELPFUL" and "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" or "HARMFUL|PLAYER"
  end
end

local function ApplyCachedAura(state, identity, info, frame, exactID, buffSpellIDs)
  local aura, unit
  state.cdmAuraUnit, state.cdmAuraFilter, state.cdmAuraTotem = "player", "HELPFUL", false
  if frame then aura, unit = frame.auraDataCached, frame.auraDataUnit end
  ApplyAuraSource(state, unit, aura)
  local nativeMatches = frame and not exactID
  if frame and exactID then
    local spellID = Number(frame.auraSpellID) or (aura and Number(aura.spellId))
    nativeMatches = spellID == exactID
  end
  if nativeMatches then
    local instance = frame.auraInstanceID
    if Readable(instance) then
      if instance ~= nil then state.auraActive = true
      elseif not aura then state.auraActive = false end
    end
  end
  if exactID and aura and not nativeMatches then aura, unit = nil, nil end

  local nativeAbsent = frame and Readable(frame.auraInstanceID) and frame.auraInstanceID == nil
    and not frame.auraDataCached
  if not aura then
    if nativeAbsent then state.auraActive = false end
    local totem = frame and frame.totemData
    if totem then
      state.cdmAuraTotem = true
      local duration, expiration = Number(totem.duration), Number(totem.expirationTime)
      if duration and expiration then
        SetTimes(state, expiration - duration, duration, totem.modRate)
        state.auraActive = expiration > GetTime()
      end
    end
    return
  end
  state.auraActive = true
  if Readable(aura.dispelName) and type(aura.dispelName) == "string" then state.cdmDispelName = aura.dispelName end
  ApplyAuraSource(state, unit, aura)
  if nativeMatches then
    local cooldown = frame.Cooldown or frame.cooldown
    if cooldown and cooldown.GetCountdownFontString then state.cdmCountdownSource = cooldown:GetCountdownFontString() end
    if not state.cdmCountdownSource and frame.Bar then state.cdmCountdownSource = frame.Bar.Duration end
    local applications = frame.Applications
    local stacks = applications and (applications.Applications or applications)
    if not stacks or not stacks.GetText then stacks = frame.Icon and frame.Icon.Applications end
    if stacks and stacks.GetText then state.cdmStackSource = stacks end
    state.cdmTextRecord = observed[frame]
  end
  if nativeMatches and observed[frame] then
    local record = observed[frame]
    if record.duration then
      state.progressType, state.durationObject = "durationObject", record.duration
      state.value, state.total = nil, nil
    elseif record.raw then
      SetTimes(state, record.raw.start, record.raw.duration, record.raw.modRate)
    end
  end
  state.stacks = Number(aura.applications)
  if not state.durationObject then
    local duration, expiration = Number(aura.duration), Number(aura.expirationTime)
    if duration and expiration then
      SetTimes(state, expiration - duration, duration, aura.timeMod)
      state.auraActive = duration == 0 or expiration > GetTime()
    end
  end
end

function Private.CDMApplyAura(state, identity, info, frame, exactID, buffSpellIDs)
  ApplyCachedAura(state, identity, info, frame, exactID, buffSpellIDs)

  if frame then
    local active = frame.isActive
    if not Readable(active) then
      state.auraActive = nil

    elseif type(active) == "boolean" then

      state.auraActive = active
      if active and exactID then
        local spellID = Number(frame.auraSpellID)
          or (frame.auraDataCached and Number(frame.auraDataCached.spellId))

        if spellID then state.auraActive = spellID == exactID
        else state.auraActive = nil end
      end
    end
  end
  if state.auraActive == false then
    state.progressType, state.value, state.total = "static", 1, 1
    state.durationObject, state.duration, state.expirationTime, state.modRate = nil, nil, nil, nil
    state.cdmCountdownSource, state.cdmStackSource, state.cdmTextRecord = nil, nil, nil
    state.stacks, state.cdmDispelName = nil, nil
  end
end

function Private.ParseCDMText(value)
  if type(value) ~= "string" then return end
  local token = value:match("^%%{(.-)}$") or value:match("^%%(.+)$")
  if not token then return end
  if token == "bp" or token == "bs" or token == "p" or token == "s" or token == "caster" or token == "dispel" then return token end
  local trigger, kind = token:match("^(%d+)%.(b?[ps])$")
  if not trigger then
    local index, field = token:match("^(%d+)%.(%a+)$")
    if field == "caster" or field == "dispel" then return field, tonumber(index) end
  end
  if trigger then return kind, tonumber(trigger) end
end

function Private.IsCDMBuffText(value, data)
  local kind, index = Private.ParseCDMText(value)
  if not kind then return false end
  if kind == "bp" or kind == "bs" then return true end
  local triggers = data and data.triggers
  if not triggers then return false end
  if not index and data.progressSource and data.progressSource[1] then
    local source = data.progressSource[1]
    if source == 0 then return false elseif source > 0 then index = source end
  end
  index = index or (triggers.activeTriggerMode and triggers.activeTriggerMode > 0 and triggers.activeTriggerMode) or (#triggers == 1 and 1)
  local entry = index and triggers[index]
  local trigger = type(entry) == "table" and entry.trigger
  return trigger and trigger.type == "cdm" and trigger.event == "Blizzard CDM Buff" or false
end

function Private.CopyCDMCountdownText(destination, state, kind)
  if kind == "caster" then destination:SetText(""); return end
  if kind == "dispel" then destination:SetText(state and state.show and state.cdmDispelName or ""); return end
  if kind == "s" then kind = "bs" end
  local source = state and state.show and (kind == "bs" and state.cdmStackSource or kind ~= "bs" and state.cdmCountdownSource)
  if source and source.IsForbidden and source:IsForbidden() then source = nil end
  if source and kind == "bs" and source.IsShown then
    local shown = source:IsShown()
    if Readable(shown) and not shown then destination:SetText(""); return end
  end
  if source then destination:SetText(source:GetText()) elseif state and state.show and state.cdmTextPreview then destination:SetText(kind == "bs" and "3" or "29m") else destination:SetText("") end
end
