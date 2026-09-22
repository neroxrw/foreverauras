-- Public trigger conditions can style native widgets without observing secret aura state.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay
local conditionActions = {chat = "chat", sound = "sound", customcode = "customcode", glowexternal = "glowexternal"}
local rootProperties = {
  icon = {color = 'color', desaturate = 'bool', zoom = 'number', inverse = 'bool', cooldownSwipe = 'bool', cooldownEdge = 'bool', cooldownTextDisabled = 'bool'},
  aurabar = {barColor = 'color', backgroundColor = 'color', icon_color = 'color', desaturate = 'bool'},
  text = {color = 'color', fontSize = 'number', displayText = 'string'},
}
local elementProperties = {
  subtext = {text_color = 'color', text_visible = 'bool', text_text = 'string', text_fontSize = 'number', text_anchorXOffset = 'number', text_anchorYOffset = 'number', text_alpha = 'number'},
  subglow = {glow = 'bool'},
}

local function PropertyType(data, property)
  if conditionActions[property] then return conditionActions[property] end
  local index, key = property:match('^sub%.(%d+)%.(.+)$')
  if index then
    local element = data.subRegions and data.subRegions[tonumber(index)]
    if Display.IsDetachedElement(data, element) then
      local definition = Private.subRegionTypes[element.type]
      local properties = definition and definition.properties
      properties = type(properties) == 'function' and properties(data, element) or properties
      local property = properties and properties[key]
      if property and not property.valueFromBoolean and not property.colorFromBoolean then return property.type end
      return
    end
    if element and key == 'text_text' and Display.TextKind(element.text_text) ~= 'literal' then return end
    return element and elementProperties[element.type] and elementProperties[element.type][key]
  end
  if property == 'displayText' and Display.TextKind(data.displayText) ~= 'literal' then return end
  return rootProperties[data.regionType] and rootProperties[data.regionType][property]
end

function Display.FilterConditionProperties(data, properties)
  return properties
end

function Display.IsNativeConditionProperty(data, property)
  return not conditionActions[property]
    and not Display.IsDetachedProperty(data, property)
    and PropertyType(data, property) ~= nil
end

function Display.FilterConditionTemplates(data, templates)
  if not Display.Enabled(data) then return templates end
  for index, fields in pairs(templates) do
    local trigger = data.triggers[index] and data.triggers[index].trigger
    -- Secret aura state cannot be used as a condition input.
    templates[index] = trigger and trigger.type ~= 'secretAura' and fields or {}
  end
  return templates
end

function Display.FilterGlobalConditions(data, templates)
  return templates
end

local function ValidCheck(data, check)
  if not check or not check.variable then return true end -- Unfinished editor row.
  if check.variable == 'AND' or check.variable == 'OR' then
    for _, child in ipairs(check.checks or {}) do
      if not ValidCheck(data, child) then return false end
    end
    return true
  end
  if check.trigger == -1 then return true end
  local trigger = data.triggers[check.trigger] and data.triggers[check.trigger].trigger
  return trigger and trigger.type ~= 'secretAura'
end

function Display.ValidateConditions(data)
  for _, condition in ipairs(data.conditions or {}) do
    if not ValidCheck(data, condition.check) then
      return 'Use another trigger or a global condition. Blizzard Aura does not expose aura state to conditions.'
    end
  end
end

-- Allocate and bind conditional elements during configuration, never from combat updates.
function Display.PrepareConditionAppearance(data)
  local result
  for _, condition in ipairs(data.conditions or {}) do
    for _, change in ipairs(condition.changes or {}) do
      local index, key = (change.property or ''):match('^sub%.(%d+)%.(.+)$')
      index = tonumber(index)
      if index and not Display.IsDetachedProperty(data, change.property) and (key == 'glow' or key == 'text_visible') and PropertyType(data, change.property) then
        if not result then
          result = {}
          for field, value in pairs(data) do result[field] = value end
          result.subRegions = {}
          for elementIndex, element in ipairs(data.subRegions) do result.subRegions[elementIndex] = element end
        end
        if result.subRegions[index] == data.subRegions[index] then result.subRegions[index] = CopyTable(data.subRegions[index]) end
        result.subRegions[index][key] = true
      end
    end
  end
  return result or data
end

local function SetFontSize(text, size)
  local font, _, flags = text:GetFont()
  text:SetFont(font, size, flags)
end

local function ApplyProperty(button, data, property, value, overrides)
  -- Native aura children deny addon access while aura information is secret.
  if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then return end
  local index, key = property:match('^sub%.(%d+)%.(.+)$')
  if index then
    index = tonumber(index)
    local entry = button.sharedElements and button.sharedElements[index]
    if not entry then return end
    if key == 'text_color' and entry.text then entry.text:SetTextColor(unpack(value))
    elseif (key == 'text_visible' or key == 'text_alpha') and entry.text then
      local prefix = 'sub.' .. index .. '.'
      local visible = overrides[prefix .. 'text_visible']
      if visible == nil then visible = data.subRegions[index].text_visible ~= false end
      local alpha = overrides[prefix .. 'text_alpha'] or data.subRegions[index].text_alpha or 1
      entry.text:SetAlpha(visible and alpha or 0)
    elseif key == 'text_text' and entry.text then entry.text:SetText((value:gsub('%%%%', '%%')))
    elseif key == 'text_fontSize' and entry.text then SetFontSize(entry.text, value)
    elseif (key == 'text_anchorXOffset' or key == 'text_anchorYOffset') and entry.text then
      local point, target, relativePoint, x, y = entry.text:GetPoint(1)
      entry.text:ClearAllPoints()
      entry.text:SetPoint(point, target, relativePoint, key == 'text_anchorXOffset' and value or x, key == 'text_anchorYOffset' and value or y)
    elseif key == 'glow' then
      local frame = entry.elementFrames and entry.elementFrames.glow
      if frame then frame:SetAlpha(value and 1 or 0) end
    end
  elseif property == 'color' then
    if data.regionType == 'text' then
      if button.mainText then button.mainText:SetTextColor(unpack(value)) end
    else button.icon:SetVertexColor(unpack(value)) end
  elseif property == 'barColor' and button.bar then button.bar:SetStatusBarColor(unpack(value))
  elseif property == 'backgroundColor' and button.barBackground then button.barBackground:SetColorTexture(unpack(value))
  elseif property == 'desaturate' then button.icon:SetDesaturated(value)
  elseif property == 'icon_color' then button.icon:SetVertexColor(unpack(value))
  elseif property == 'zoom' then
    local crop = math.min(0.45, value / 2)
    button.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
  elseif property == 'inverse' then button.cooldown:SetReverse(value)
  elseif property == 'cooldownSwipe' then button.cooldown:SetDrawSwipe(value)
  elseif property == 'cooldownEdge' then button.cooldown:SetDrawEdge(value)
  elseif property == 'cooldownTextDisabled' then button.cooldown:SetHideCountdownNumbers(value)
  elseif property == 'fontSize' and button.mainText then SetFontSize(button.mainText, value)
  elseif property == 'displayText' and button.mainText then button.mainText:SetText((value:gsub('%%%%', '%%'))) end
end

function Display.ApplyConditionAppearance(button, region, data)
  local overrides = region.secretAuraConditionValues or {}
  for index, element in ipairs(data.subRegions or {}) do
    if not Display.IsDetachedElement(data, element) then
      if element.type == 'subglow' then ApplyProperty(button, data, 'sub.' .. index .. '.glow', element.glow == true, overrides)
      elseif element.type == 'subtext' then ApplyProperty(button, data, 'sub.' .. index .. '.text_visible', element.text_visible ~= false, overrides) end
    end
  end
  for property, value in pairs(region.secretAuraConditionValues or {}) do
    ApplyProperty(button, data, property, value, overrides)
  end
end

function Display.SetConditionProperty(region, property, ...)
  local native = region.blizzardAuraDisplay
  if not native or not native.active then return end
  local kind = PropertyType(native.data, property)
  if not kind then return end
  local value = kind == 'color' and {...} or ...
  region.secretAuraConditionValues = region.secretAuraConditionValues or {}
  region.secretAuraConditionValues[property] = value
  for _, instance in ipairs(native.instances) do
    for _, button in ipairs(instance.buttons) do ApplyProperty(button, native.data, property, value, region.secretAuraConditionValues) end
  end
end

-- Condition evaluation continues while access is denied; restore only its latest result.
function Display.RefreshConditionAppearance(region)
  local native = region.blizzardAuraDisplay
  if not native or not native.active or not region.secretAuraConditionValues then return end
  for _, instance in ipairs(native.instances) do
    for _, button in ipairs(instance.buttons) do
      Display.ApplyConditionAppearance(button, region, native.data)
    end
  end
end
