if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = {}
Private.CDMAuraProgress = Display
local Media = LibStub("LibSharedMedia-3.0")
local regions = setmetatable({}, {__mode = "k"})

local function Restricted()
  return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret())
end

local function Key(ids)
  local sorted, seen = {}, {}
  for _, id in ipairs(ids or {}) do
    if type(id) == "number" and not seen[id] then sorted[#sorted + 1] = id; seen[id] = true end
  end
  table.sort(sorted)
  return table.concat(sorted, ","), seen
end

function Display.IsConfigured(data)
  local source = data.progressSource and data.progressSource[1] or -1
  if source == 0 then return false end
  if source < 0 then source = data.triggers.activeTriggerMode or -1 end
  if source < 0 and #data.triggers == 1 then source = 1 end
  local entry = data.triggers[source]
  return entry and entry.trigger.type == "cdm" and entry.trigger.event == "Blizzard CDM Buff" or false
end

local function ApplyStyle(native, region)
  local cooldown = native.cooldown
  -- Native aura descendants become forbidden while aura data is restricted.
  -- Configure before registration, then defer appearance edits until accessible.
  if Restricted() or (cooldown.IsForbidden and cooldown:IsForbidden()) then return end
  local swipe, edge = region.cooldownSwipe == true, region.cooldownEdge == true
  local reverse, hideNumbers = region.inverseDirection == true, region.cdmConfiguredHideNumbers == true
  if native.swipe ~= swipe then cooldown:SetDrawSwipe(swipe); native.swipe = swipe end
  if native.edge ~= edge then cooldown:SetDrawEdge(edge); native.edge = edge end
  if native.reverse ~= reverse then cooldown:SetReverse(reverse); native.reverse = reverse end
  if native.hideNumbers ~= hideNumbers then cooldown:SetHideCountdownNumbers(hideNumbers); native.hideNumbers = hideNumbers end
end

function Display.Style(region)
  local native = region.cdmNativeProgress
  if not native then return end
  if native.kind == "icon" then ApplyStyle(native, region)
  elseif not Restricted() then Display.StyleProgress(native, region) end
end

local function Accessible(object)
  return not Restricted() and not (object.IsForbidden and object:IsForbidden())
end

-- Native containers add structural children, not additional sub-element layers.
-- Keep their entire rendering subtree on the layer assigned to its owner.
local function SyncNativeLevel(native, level, force)
  if Restricted() or (not force and native.frameLevel == level) then return end
  for _, frame in ipairs({native.container, native.button, native.bar or native.cooldown}) do
    if not Accessible(frame) then return end
  end
  native.container:SetFrameLevel(level)
  native.button:SetFrameLevel(level)
  if native.bar then native.bar:SetFrameLevel(level) end
  if native.cooldown then native.cooldown:SetFrameLevel(level) end
  native.frameLevel = level
end

function Display.SyncFrameLevels(region, force)
  if Restricted() then return end
  local level = region.regionType == "aurabar" and region.bar:GetFrameLevel() or region:GetFrameLevel()
  for _, native in pairs(region.cdmAuraSlots or {}) do SyncNativeLevel(native, level, force) end
  for _, sub in ipairs(region.subRegions or {}) do
    if sub.cdmIndicatorSlots then
      for _, native in pairs(sub.cdmIndicatorSlots) do SyncNativeLevel(native, sub:GetFrameLevel(), force) end
    end
    if sub.cdmTextSlots then
      local textLevel = sub:GetFrameLevel()
      for _, native in pairs(sub.cdmTextSlots) do SyncNativeLevel(native, textLevel, force) end
    end
  end
end

local function Circular(data)
  return data.regionType == "progresstexture" and (data.orientation == "CLOCKWISE" or data.orientation == "ANTICLOCKWISE")
end

function Display.StyleProgress(native, region)
  local data = region.cdmProgressData
  local widget = native.bar or native.cooldown
  if not data or not widget or not Accessible(widget) then return end
  local color
  if not hasanysecretvalues(region.color_r, region.color_g, region.color_b, region.color_a) then
    color = {region.color_r or 1, region.color_g or 1, region.color_b or 1, region.color_a or 1}
  end
  if native.bar then
    local vertical = (region.orientation or data.orientation or ""):find("VERTICAL", 1, true) ~= nil
    local reverse = (region.orientation or data.orientation or ""):find("INVERSE", 1, true) ~= nil
    native.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    native.bar:SetReverseFill(reverse)
    if color then native.bar:SetStatusBarColor(unpack(color)) end
    local texture = data.regionType == "aurabar" and
      (data.textureSource == "LSM" and Media:Fetch("statusbar", region.texture or data.texture or "Blizzard") or region.textureInput or data.textureInput)
      or data.foregroundTexture
    native.bar:SetStatusBarTexture(texture or "Interface\\Buttons\\WHITE8X8")
    local direction = region.inverseDirection and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime
    if data.cdmProgressMode == "stacks" then
      native.button:SetApplicationBar(native.bar, {minApplications = 0, maxApplications = data.cdmMaxStacks or 5})
    elseif native.direction ~= direction then
      native.button:SetDurationBar(native.bar, {direction = direction})
      native.direction = direction
    end
  else
    native.cooldown:SetDrawSwipe(true)
    native.cooldown:SetDrawEdge(false)
    native.cooldown:SetHideCountdownNumbers(true)
    native.cooldown:SetSwipeTexture(data.foregroundTexture)
    if color then native.cooldown:SetSwipeColor(unpack(color)) end
    native.cooldown:SetReverse(region.inverseDirection == true)
  end
end

local function CreateSlot(parent, filters, initialize)
  local native = {}
  local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  native.container = container
  native.unit, native.filter = "player", "HELPFUL"
  container:SetEnabled(false)
  container:SetAllPoints(parent)
  container:SetFrameLevel(parent:GetFrameLevel() + 1)
  container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
  container:AddAuraSlot("Progress", "HELPFUL", {
    candidateFilters = {includeSpellIDs = filters},
    initializeFrame = function(button)
      native.button = button
      button:SetAllPoints(container)
      button:EnableMouse(false)
      initialize(native, button)
    end,
  })
  container:SetUnit("player")
  container:Hide()
  return native
end

local function Create(region, filters)
  local data = region.cdmProgressData
  return CreateSlot(region, filters, function(native, button)
    native.kind = data.regionType
    if data.regionType == "icon" or Circular(data) then
      native.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
      native.cooldown:SetAllPoints(button)
      native.cooldown:SetDrawBling(false)
      native.cooldown:SetHideCountdownNumbers(true)
      if data.regionType == "icon" then ApplyStyle(native, region) else Display.StyleProgress(native, region) end
      button:SetDurationCooldown(native.cooldown)
    else
      native.bar = CreateFrame("StatusBar", nil, button)
      native.bar:SetAllPoints(data.regionType == "aurabar" and region.bar or button)
      Display.StyleProgress(native, region)
    end
  end)
end

local function ProgressKey(region, key)
  local data = region.cdmProgressData
  return key .. ":" .. (data.regionType or "icon") .. ":" .. (Circular(data) and "circle" or "linear") .. ":" .. (data.cdmProgressMode or "duration") .. ":" .. tostring(data.cdmMaxStacks or 5)
end

local function SuppressProgress(region, active)
  if region.regionType == "aurabar" then
    region.bar.fg:SetAlpha(active and 0 or 1)
    region.bar.spark:SetAlpha(active and 0 or 1)
    if active then
      for _, texture in pairs(region.bar.extraTextures or {}) do texture:Hide() end
      for _, bar in pairs(region.bar.additionalBars or {}) do if type(bar) == "table" and bar.Hide then bar:Hide() end end
    end
  elseif region.regionType == "progresstexture" then
    if active then region.foreground:Hide(); region.foregroundSpinner:Hide()
    elseif region.circular then region.foregroundSpinner:Show()
    else region.foreground:Show() end
  elseif active and region.cooldown then region.cooldown:Hide() end
  if active and region.FrameTick then
    region.FrameTick = nil
    region.subRegionEvents:RemoveSubscriber("FrameTick", region)
  end
end

local function HookAppearance(region)
  region.cdmAppearanceHooks = region.cdmAppearanceHooks or {}
  for _, method in ipairs({"Color", "ColorAnim", "SetInverse", "SetOrientation", "UpdateForegroundColor", "UpdateStatusBarTexture"}) do
    if type(region[method]) == "function" and region.cdmAppearanceHooks[method] ~= region[method] then
      hooksecurefunc(region, method, function(self) Display.Style(self) end)
      region.cdmAppearanceHooks[method] = region[method]
    end
  end
end

function Display.Modify(region, data)
  SuppressProgress(region, false)
  region.cdmProgressData = data
  HookAppearance(region)
  region.cdmNativeProgress = nil
  for _, native in pairs(region.cdmAuraSlots or {}) do
    native.container:SetEnabled(false)
    native.container:Hide()
  end
  regions[region] = nil
  local needed = false
  for _, entry in ipairs(data.triggers or {}) do
    if entry.trigger.type == "cdm" and entry.trigger.event == "Blizzard CDM Buff" then needed = true end
  end
  if not needed or (data.regionType == "icon" and not data.cooldown) then return end
  regions[region] = true
  if Restricted() then return end
  if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    if not C_AddOns.LoadAddOn("Blizzard_AuraContainer") then return end
  end
  region.cdmAuraSlots = region.cdmAuraSlots or {}
  local wanted = {}
  for _, entry in ipairs(data.triggers) do
    local trigger = entry.trigger
    if trigger.type == "cdm" and trigger.event == "Blizzard CDM Buff" then
      for _, ids in ipairs(Private.CDMNativeSelections(trigger)) do
        local key, filters = Key(ids)
        if key ~= "" then
          key = ProgressKey(region, key)
          wanted[key] = true
          if not region.cdmAuraSlots[key] then region.cdmAuraSlots[key] = Create(region, filters) end
        end
      end
    end
  end
  for key, native in pairs(region.cdmAuraSlots) do
    if not wanted[key] then
      native.container:SetEnabled(false)
      native.container:Hide()
      -- Keep the native frame available for later edits without reusing stale filters.
    end
  end
end

function Display.Update(region)
  local source = region.progressSource and region.progressSource[1] or -1
  local state
  if source == -1 then state = region.state
  elseif source > 0 then state = region.states and region.states[source] end
  local native
  if region.cdmProgressData and (region.cdmProgressData.regionType ~= "icon" or region.cdmProgressData.cooldown) and state and state.cdmBuff and not state.cdmAuraTotem and not (state.cdmTextPreview and state.auraActive ~= true) then
    local key = ProgressKey(region, Key(state.cdmAuraSpellIDs))
    native = region.cdmAuraSlots and region.cdmAuraSlots[key]
  end
  if native then
    local unit, filter = state.cdmAuraUnit or "player", state.cdmAuraFilter or "HELPFUL"
    if native.unit ~= unit or native.filter ~= filter then
      native.container:SetEnabled(false)
      native.container:SetAuraSlotFilterString("Progress", filter)
      native.container:SetUnit(unit)
      native.unit, native.filter = unit, filter
      native.container:SetEnabled(true)
    end
  end
  local previous = region.cdmNativeProgress
  if previous ~= native then
    if previous then previous.container:SetEnabled(false); previous.textEnabled = false; previous.container:Hide() end
    region.cdmNativeProgress = native
    SuppressProgress(region, native ~= nil)
    if native then
      if region.cooldown then region.cooldown:Hide() end
      native.container:SetEnabled(true)
      native.container:Show()
    end
  end
  if native then
    SuppressProgress(region, true)
    Display.SyncFrameLevels(region)
    Display.Style(region)
  end
  return native ~= nil
end

-- Each text element gets its own native slot, so duplicate countdowns can use
-- different formats. The native FontString is displayed directly, never read back.
local texts = setmetatable({}, {__mode = "k"})
local function TextKind(config, kind)
  if config.cdmTextSource and config.cdmTextSource ~= "auto" then return config.cdmTextSource end
  if kind == "caster" or kind == "dispel" then return kind end
  if kind == "p" or kind == "bp" then return "duration" end
  if kind == "s" or kind == "bs" then return "stacks" end
end

local function BindText(native, sub, config, kind)
  if not Accessible(native.text) then return end
  local text = native.text
  native.appearance = nil
  local font, size, flags = sub.text:GetFont()
  text:SetFont(font or STANDARD_TEXT_FONT, size or config.text_fontSize or 16, flags or "")
  text:SetTextColor(unpack(config.text_color or {1, 1, 1, 1}))
  text:SetShadowColor(unpack(config.text_shadowColor or {0, 0, 0, 0}))
  text:SetShadowOffset(config.text_shadowXOffset or 0, config.text_shadowYOffset or 0)
  text:SetJustifyH(config.text_justify or "CENTER")
  text:SetWidth(config.text_automaticWidth == "Fixed" and (config.text_fixedWidth or 64) or 0)
  text:SetWordWrap(config.text_wordWrap ~= "Elide")
  text:SetNonSpaceWrap(config.text_wordWrap ~= "Elide")
  text:ClearAllPoints()
  -- Follow the ordinary text's public anchor, not its potentially secret extent.
  for i = 1, sub.text:GetNumPoints() do text:SetPoint(sub.text:GetPoint(i)) end
  native.button:ClearDurationText()
  native.button:ClearApplicationCount()
  native.button:ClearCasterName()
  native.button:ClearDispelTypeText()
  if kind == "duration" then
    local options = {}
    if config.cdmTimeFormat and config.cdmTimeFormat ~= "blizzard" then
      options.textFormatter = Private.GetDurationTextFormatter(config.cdmRoundUp == false and 0 or 99,
        config.cdmDecimalThreshold or 3, config.cdmPrecision or 1, config.cdmTimeFormat == "seconds")
    end
    if config.cdmDurationColor then
      local curve = C_CurveUtil.CreateColorCurve()
      curve:SetType(Enum.LuaCurveType.Step)
      curve:AddPoint(0, CreateColor(unpack(config.cdmExpiringColor or {1, 0.2, 0.2, 1})))
      curve:AddPoint(config.cdmColorThreshold or 3, CreateColor(unpack(config.text_color or {1, 1, 1, 1})))
      options.textColor = {curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration}
    end
    native.button:SetDurationText(text, options)
  elseif kind == "stacks" then
    local options
    if config.cdmShowOneStack or (config.cdmStackFormat and config.cdmStackFormat ~= "number") then
      local formatter = C_StringUtil.CreateNumericRuleFormatter()
      local format = config.cdmStackFormat == "prefix" and "×%d" or config.cdmStackFormat == "suffix" and "%d×"
        or config.cdmStackFormat == "padded" and "%0" .. (config.cdmStackDigits or 2) .. "d" or "%d"
      formatter:SetBreakpoints({{threshold = 0, format = ""}, {threshold = config.cdmShowOneStack and 1 or 2, format = format}})
      options = {formatter = formatter}
    end
    native.button:SetApplicationCount(text, options)
  elseif kind == "caster" then
    native.button:SetCasterName(text, {showRealmName = config.cdmCasterRealm == true, useClassColors = config.cdmCasterClassColor == true})
  elseif kind == "dispel" then
    native.button:SetDispelTypeText(text, {showWhenHelpful = true, showWhenHarmful = true})
  end
end

function Display.ModifyText(parent, sub, parentData, config)
  texts[sub] = {parent = parent, data = parentData, config = config}
  sub.cdmNativeText = nil
  for _, native in pairs(sub.cdmTextSlots or {}) do native.container:SetEnabled(false); native.textEnabled = false; native.container:Hide() end
  local kind = TextKind(config, Private.ParseCDMText(config.text_text))
  local needed
  for _, entry in ipairs(parentData.triggers or {}) do
    if entry.trigger.type == "cdm" and entry.trigger.event == "Blizzard CDM Buff" then needed = true end
  end
  if not needed or not kind or Restricted() then return end
  if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    if not C_AddOns.LoadAddOn("Blizzard_AuraContainer") then return end
  end
  sub.cdmTextSlots = sub.cdmTextSlots or {}
  for _, entry in ipairs(parentData.triggers or {}) do
    local trigger = entry.trigger
    if trigger.type == "cdm" and trigger.event == "Blizzard CDM Buff" then
      for _, ids in ipairs(Private.CDMNativeSelections(trigger)) do
        local key, filters = Key(ids)
        if key ~= "" then
          local kinds = (kind == "duration" or kind == "stacks") and {"duration", "stacks"} or {kind}
          for _, bindingKind in ipairs(kinds) do
            local slotKey = key .. ":" .. bindingKind
            local native = sub.cdmTextSlots[slotKey]
            if not native then
              native = CreateSlot(sub, filters, function(created, button)
                created.text = button:CreateFontString(nil, "OVERLAY")
                BindText(created, sub, config, bindingKind)
              end)
              sub.cdmTextSlots[slotKey] = native
            else BindText(native, sub, config, bindingKind) end
          end
      end
      end
    end
  end
end

function Display.HideText(sub)
  if sub.cdmNativeText then
    sub.cdmNativeText.container:SetEnabled(false)
    sub.cdmNativeText.container:Hide()
    sub.cdmNativeText.textEnabled = false
    sub.cdmNativeText = nil
  end
end

function Display.UpdateText(parent, sub, config, kind, explicitTrigger)
  local source = parent.progressSource and parent.progressSource[1] or -1
  local state = explicitTrigger and parent.states and parent.states[explicitTrigger]
  if not explicitTrigger then
    state = source > 0 and parent.states and parent.states[source] or source == -1 and parent.state
  end
  local native
  kind = TextKind(config, kind)
  if kind and state and state.cdmBuff and not state.cdmAuraTotem then
    native = sub.cdmTextSlots and sub.cdmTextSlots[Key(state.cdmAuraSpellIDs) .. ":" .. kind]
  end
  local previous = sub.cdmNativeText
  if previous ~= native then
    if previous then previous.container:SetEnabled(false); previous.textEnabled = false; previous.container:Hide() end
    sub.cdmNativeText = native
  end
  if not native then return false end
  local preview = state.cdmTextPreview and state.auraActive ~= true
  if preview then
    native.container:SetEnabled(false);native.textEnabled = false;native.container:Hide()
    local sample = kind == "duration" and (config.cdmTimeFormat == "seconds" and "1740" or config.cdmTimeFormat == "clock" and "29:00" or "29m")
      or kind == "stacks" and "3" or kind == "caster" and "Player" or "Magic"
    sub.text:SetText(sample)
    return true
  end
  local unit, filter = state.cdmAuraUnit or "player", state.cdmAuraFilter or "HELPFUL"
  if native.unit ~= unit or native.filter ~= filter then
    native.container:SetEnabled(false)
    native.textEnabled = false
    native.container:SetAuraSlotFilterString("Progress", filter)
    native.container:SetUnit(unit)
    native.unit, native.filter = unit, filter
  end
  SyncNativeLevel(native, sub:GetFrameLevel())
  if Accessible(native.text) then
    local font, size, flags = sub.text:GetFont()
    local r, g, b, a = sub.color_r, sub.color_g, sub.color_b, sub.color_a
    if not hasanysecretvalues(r, g, b, a) then
      local signature = tostring(font) .. ":" .. tostring(size) .. ":" .. tostring(flags) .. ":" .. tostring(r) .. ":" .. tostring(g) .. ":" .. tostring(b) .. ":" .. tostring(a)
        .. ":" .. tostring(sub.text_anchorXOffset) .. ":" .. tostring(sub.text_anchorYOffset)
      if native.appearance ~= signature then
        native.text:SetFont(font or STANDARD_TEXT_FONT, size or 16, flags or "")
        if not config.cdmDurationColor and not config.cdmCasterClassColor and r then native.text:SetTextColor(r, g, b, a) end
        native.text:ClearAllPoints()
        for i = 1, sub.text:GetNumPoints() do native.text:SetPoint(sub.text:GetPoint(i)) end
        native.appearance = signature
      end
    end
  end
  sub.text:SetText("")
  if not native.textEnabled then native.container:SetEnabled(true); native.textEnabled = true end
  native.container:Show()
  return true
end

local indicators = setmetatable({}, {__mode = "k"})
function Display.ModifyIndicator(parent, sub, parentData, config)
  indicators[sub] = {parent = parent, data = parentData, config = config}
  Display.ReleaseIndicator(sub)
  if Restricted() then return end
  if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    if not C_AddOns.LoadAddOn("Blizzard_AuraContainer") then return end
  end
  sub.cdmIndicatorSlots = sub.cdmIndicatorSlots or {}
  for _, entry in ipairs(parentData.triggers or {}) do
    local trigger = entry.trigger
    if trigger.type == "cdm" and trigger.event == "Blizzard CDM Buff" then
      for _, ids in ipairs(Private.CDMNativeSelections(trigger)) do
        local key, filters = Key(ids)
        if key ~= "" then
          key = key .. ":" .. (config.dispelStyle or "Icon")
          if not sub.cdmIndicatorSlots[key] then
            sub.cdmIndicatorSlots[key] = CreateSlot(sub, filters, function(native, button)
              native.indicator = button:CreateTexture(nil, "OVERLAY")
              native.indicator:SetAllPoints(button)
              button:AddDispelTypeTexture(native.indicator, {
                showWhenHelpful = true, showWhenHarmful = true,
                style = Enum.CustomAuraButtonDispelTypeTextureStyle[config.dispelStyle or "Icon"],
              })
            end)
          end
      end
      end
    end
  end
end

function Display.ReleaseIndicator(sub, forget)
  if forget then indicators[sub] = nil end
  for _, native in pairs(sub.cdmIndicatorSlots or {}) do native.container:SetEnabled(false); native.container:Hide() end
  sub.cdmNativeIndicator = nil
  if sub.preview then sub.preview:Hide() end
end

function Display.UpdateIndicator(parent, sub, config)
  local source = parent.progressSource and parent.progressSource[1] or -1
  local state = source > 0 and parent.states and parent.states[source] or source == -1 and parent.state
  local native
  if sub.visible and state and state.cdmBuff then
    local key = Key(state.cdmAuraSpellIDs) .. ":" .. (config.dispelStyle or "Icon")
    native = sub.cdmIndicatorSlots and sub.cdmIndicatorSlots[key]
  end
  if sub.cdmNativeIndicator ~= native then
    Display.ReleaseIndicator(sub)
    sub.cdmNativeIndicator = native
  end
  if not native then return end
  if state.cdmTextPreview and state.auraActive ~= true then
    native.container:SetEnabled(false);native.container:Hide()
    if config.dispelStyle == "Border" or config.dispelStyle == "BorderWithIcon" then
      AuraUtil.SetAuraBorderAtlas(sub.preview, "Magic", config.dispelStyle == "BorderWithIcon")
    else AuraUtil.SetAuraDispelTypeIcon(sub.preview, "Magic") end
    sub.preview:Show()
    return
  end
  sub.preview:Hide()
  local unit, filter = state.cdmAuraUnit or "player", state.cdmAuraFilter or "HELPFUL"
  if native.unit ~= unit or native.filter ~= filter then
    native.container:SetEnabled(false)
    native.container:SetAuraSlotFilterString("Progress", filter)
    native.container:SetUnit(unit)
    native.unit, native.filter = unit, filter
  end
  SyncNativeLevel(native, sub:GetFrameLevel())
  native.container:SetEnabled(true)
  native.container:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
local function RefreshBindings()
  if Restricted() then return end
  for sub, record in pairs(indicators) do
    Display.ModifyIndicator(record.parent, sub, record.data, record.config)
    Display.UpdateIndicator(record.parent, sub, record.config)
  end
  for sub, record in pairs(texts) do
    Display.ModifyText(record.parent, sub, record.data, record.config)
  end
  for region in pairs(regions) do
    Display.Modify(region, region.cdmProgressData)
    Display.Update(region)
  end
end
events:SetScript("OnEvent", RefreshBindings)
if EventRegistry then
  EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
    C_Timer.After(0, RefreshBindings)
  end, events)
end
