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

-- These checks are declarations consumed by Blizzard, never Lua state predicates.
local durationVariables = {
  faAuraRemaining = {"RemainingDuration", "Remaining Time", 1},
  faAuraRemainingPercent = {"RemainingPercent", "Remaining Time (%)", 100},
  faAuraElapsed = {"ElapsedDuration", "Elapsed Time", 1},
  faAuraElapsedPercent = {"ElapsedPercent", "Elapsed Time (%)", 100},
  faAuraTotal = {"TotalDuration", "Total Duration", 1},
  faAuraStart = {"StartTime", "Start Time (session seconds)", 1},
  faAuraEnd = {"EndTime", "End Time (session seconds)", 1},
}
local nativeVariables = {faAuraPandemic = true, faAuraStealable = true, faAuraNotStealable = true,
  faAuraDispel = true, faAuraType = true, faAuraPresent = true, faAuraApplications = true}
for key in pairs(durationVariables) do nativeVariables[key] = true end
local indicatorProperties = {faAuraHighlightColor = true, faAuraHighlightStyle = true, faAuraHighlightSize = true, faAuraHighlightTexture = true}
function Display.IsNativeDurationCondition(check) return check and durationVariables[check.variable] ~= nil end
function Display.NativeConditionKind(data, check)
  local entry = check and data.triggers and data.triggers[check.trigger]
  local trigger = type(entry) == "table" and entry.trigger
  -- Multi-selection trigger slots can be placeholders rather than trigger entries.
  return type(trigger) == "table" and trigger.type == "secretAura" and nativeVariables[check.variable] and check.variable or nil
end
function Display.ContainsNativeCondition(data, check)
  if Display.NativeConditionKind(data, check) then return true end
  for _, child in ipairs(check and check.checks or {}) do
    if Display.ContainsNativeCondition(data, child) then return true end
  end
  return false
end
function Display.SupportsDurationColorCondition()
  return C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor
    and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step ~= nil
    and Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration ~= nil
end
local function TextProperty(data, property, kind)
  if data.regionType == "text" and Display.TextKind(data.displayText) == kind then
    if property == "color" then return "color", "color" end
    if property == "displayText" then return "color", "text" end
  end
  local index, field
  if property then index, field = property:match("^sub%.(%d+)%.(.*)$") end
  local element = index and data.subRegions and data.subRegions[tonumber(index)]
  if element and element.type == "subtext" and not Display.IsDetachedElement(data, element) and Display.TextKind(element.text_text) == kind then
    local channel = ({text_color = "color", text_visible = "visible", text_text = "text"})[field]
    if channel then return "sub." .. index .. ".text_color", channel end
  end
end
function Display.NativeConditionAllowsProperty(data, check, property)
  local kind = Display.NativeConditionKind(data, check)
  if durationVariables[kind] then
    local target, channel = TextProperty(data, property, "duration")
    return target ~= nil and channel ~= "text"
  end
  if kind == "faAuraApplications" then return TextProperty(data, property, "stack") ~= nil end
  if kind then return indicatorProperties[property] == true end
  return not indicatorProperties[property]
end
function Display.MigrateNativeConditions(data)
  local settings = data.blizzardAuraDisplay or {}
  if settings.remainingTimeColorEnabled then
    local property
    if data.regionType == "text" and Display.TextKind(data.displayText) == "duration" then property = "color" end
    for index, element in ipairs(data.subRegions or {}) do
      if not property and element.type == "subtext" and element.text_visible ~= false
          and not Display.IsDetachedElement(data, element) and Display.TextKind(element.text_text) == "duration" then
        property = "sub." .. index .. ".text_color"
      end
    end
    local triggerIndex
    for index, entry in ipairs(data.triggers or {}) do if entry.trigger.type == "secretAura" then triggerIndex = index; break end end
    if triggerIndex and property then
      data.conditions = data.conditions or {}
      table.insert(data.conditions, {check = {trigger = triggerIndex, variable = "faAuraRemaining", op = "<", value = settings.remainingTimeColorThreshold or 10},
        changes = {{property = property, value = settings.remainingTimeColor or {1, 0, 0, 1}}}})
      settings.remainingTimeColorEnabled = nil
    end
  end
end
local function Color(values, fallback)
  if type(values) ~= "table" then values = fallback end
  local result = {}
  for i = 1, 4 do
    local value = values[i]
    result[i] = type(value) == "number" and value == value and math.max(0, math.min(1, value)) or fallback[i]
  end
  return CreateColor(unpack(result))
end
local function NumericRules(data, property, stack)
  local rules = {}
  for _, condition in ipairs(data.conditions or {}) do
    local kind = Display.NativeConditionKind(data, condition.check)
    if not condition.linked and ((stack and kind == "faAuraApplications") or (not stack and durationVariables[kind])) then
      local check = condition.check
      local value = tonumber(check.value)
      if value and value == value and value >= 0 and value < math.huge then
        local supported = stack and ({['<']=true,['>=']=true,['>']=true,['<=']=true,['==']=true,['~=']=true}) or {['<']=true,['>=']=true}
        if supported[check.op] then
          for _, change in ipairs(condition.changes or {}) do
            local target, channel = TextProperty(data, change.property, stack and "stack" or "duration")
            if target == property and (stack or channel ~= "text") then
              rules[#rules + 1] = {threshold = value / (not stack and durationVariables[kind][3] or 1), op = check.op,
                value = change.value, channel = channel, kind = kind}
            end
          end
        end
      end
    end
  end
  return rules
end
local function Matches(value, rule)
  if rule.op == '<' then return value < rule.threshold
  elseif rule.op == '>=' then return value >= rule.threshold
  elseif rule.op == '>' then return value > rule.threshold
  elseif rule.op == '<=' then return value <= rule.threshold
  elseif rule.op == '==' then return value == rule.threshold
  elseif rule.op == '~=' then return value ~= rule.threshold end
end
local function BaseTextVisible(data, property)
  local index = property and property:match("^sub%.(%d+)%.text_color$")
  local original = data.nativeConditionBaseData or data
  local element = index and original.subRegions and original.subRegions[tonumber(index)]
  return not element or element.text_visible ~= false
end
function Display.DurationColorCondition(data, baseColor, property)
  if not Display.SupportsDurationColorCondition() then return end
  local rules = NumericRules(data, property)
  if #rules == 0 then return end
  local definition = durationVariables[rules[1].kind]
  local bindingProperty = Enum.DurationTextBindingProperty[definition[1]]
  if bindingProperty == nil then return end
  local points, seen = {0}, {[0] = true}
  for _, rule in ipairs(rules) do
    if rule.kind ~= rules[1].kind then return end -- One native binding samples one time property.
    if not seen[rule.threshold] then points[#points + 1] = rule.threshold; seen[rule.threshold] = true end
  end
  table.sort(points)
  local curve = C_CurveUtil.CreateColorCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  for _, value in ipairs(points) do
    local color, visible = baseColor, BaseTextVisible(data, property)
    for _, rule in ipairs(rules) do
      if Matches(value, rule) then
        if rule.channel == "color" then color = rule.value
        elseif rule.channel == "visible" then visible = rule.value ~= false end
      end
    end
    local result = Color(color, {1, 1, 1, 1})
    if not visible then local r,g,b = result:GetRGB(); result = CreateColor(r,g,b,0) end
    curve:AddPoint(value, result)
  end
  return {curve = curve, property = bindingProperty}
end
function Display.StackTextCondition(data, property)
  if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return end
  local rules = NumericRules(data, property, true)
  if #rules == 0 then return end
  local points, seen = {0, 2}, {[0]=true,[2]=true}
  for _, rule in ipairs(rules) do
    for _, value in ipairs({math.floor(rule.threshold), math.ceil(rule.threshold), math.floor(rule.threshold) + 1}) do
      if value >= 0 and not seen[value] then points[#points + 1] = value; seen[value] = true end
    end
  end
  table.sort(points)
  local breakpoints = {}
  for _, value in ipairs(points) do
    local format, visible, color = "%d", value >= 2 and BaseTextVisible(data, property), nil
    for _, rule in ipairs(rules) do
      if Matches(value, rule) then
        if rule.channel == "color" then color = rule.value
        elseif rule.channel == "visible" then visible = rule.value ~= false
        elseif rule.channel == "text" and type(rule.value) == "string" then format = rule.value:gsub("%%", "%%%%"); visible = true end
      end
    end
    if not visible then format = ""
    elseif color then
      local c = Color(color, {1,1,1,1})
      local r,g,b = c:GetRGB()
      format = ("|cff%02x%02x%02x"):format(math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(b*255+0.5)) .. format .. "|r"
    end
    breakpoints[#breakpoints + 1] = {threshold = value, format = format}
  end
  local formatter = C_StringUtil.CreateNumericRuleFormatter()
  formatter:SetBreakpoints(breakpoints)
  return formatter
end
local function OwnsDurationColor(data, property)
  local target = TextProperty(data, property, "duration")
  if target and Display.SupportsDurationColorCondition() and #NumericRules(data, target) > 0 then return true end
  target = TextProperty(data, property, "stack")
  return target and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and #NumericRules(data, target, true) > 0
end

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
  if Display.Enabled(data) then
    properties.faAuraHighlightColor = {display = "Aura Highlight Color", type = "color", default = {1, 0.82, 0, 1}}
    properties.faAuraHighlightStyle = {display = "Aura Highlight Style", type = "list", default = "border",
      values = {border = "Border", glow = "Glow", overlay = "Overlay", texture = "Custom Texture"}}
    properties.faAuraHighlightSize = {display = "Aura Highlight Size", type = "number", default = 2, min = 1, max = 64, step = 1}
    properties.faAuraHighlightTexture = {display = "Aura Highlight Texture", type = "string", default = "Interface\\Buttons\\UI-ActionButton-Border"}
  end
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
    if trigger and trigger.type == 'secretAura' then
      local native = {
        faAuraPandemic = {display = "In Pandemic Window", type = "alwaystrue"},
        faAuraStealable = {display = "Buff Is Stealable", type = "alwaystrue"},
        faAuraNotStealable = {display = "Buff Is Not Stealable", type = "alwaystrue"},
        faAuraPresent = {display = "Aura Present", type = "alwaystrue"},
        faAuraType = {display = "Aura Type", type = "select", operator_types = "native_aura_dispel", values = {HELPFUL = "Buff", HARMFUL = "Debuff"}},
        faAuraDispel = {display = "Dispel Type", type = "select", operator_types = "native_aura_dispel",
          values = {Magic = "Magic", Curse = "Curse", Disease = "Disease", Poison = "Poison", Bleed = "Bleed", Enrage = "Enrage", None = "None"}},
      }
      if Display.SupportsDurationColorCondition() then
        for key, definition in pairs(durationVariables) do
          if Enum.DurationTextBindingProperty[definition[1]] ~= nil then
            native[key] = {display = definition[2], type = "number", operator_types = "native_aura_duration"}
          end
        end
      end
      if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        native.faAuraApplications = {display = "Stack Count", type = "number"}
      end
      templates[index] = native
    else templates[index] = fields end
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
  return trigger and (trigger.type ~= 'secretAura' or Display.NativeConditionKind(data, check) ~= nil)
end

function Display.ValidateConditions(data)
  local timeProperties = {}
  for index, condition in ipairs(data.conditions or {}) do
    if Display.ContainsNativeCondition(data, condition.check) then
      local kind = Display.NativeConditionKind(data, condition.check)
      if not kind or condition.linked or (data.conditions[index + 1] and data.conditions[index + 1].linked) then
        return "Aura (Blizzard) conditions cannot use AND, OR, or Else If."
      end
      if durationVariables[kind] and condition.check.op and condition.check.op ~= "<" and condition.check.op ~= ">=" then
        return "Aura (Blizzard) time conditions support < and >=."
      end
      if (kind == "faAuraDispel" or kind == "faAuraType") and condition.check.op and condition.check.op ~= "==" then
        return "Aura (Blizzard) type conditions support equality only."
      end
      for _, change in ipairs(condition.changes or {}) do
        if durationVariables[kind] and change.property then
          local target = TextProperty(data, change.property, "duration")
          if target then
            if timeProperties[target] and timeProperties[target] ~= kind then
              return "Use one time basis per countdown text: seconds, percentage, elapsed, total, start, or end."
            end
            timeProperties[target] = kind
          end
        end
        if change.property and not Display.NativeConditionAllowsProperty(data, condition.check, change.property) then
          return "Choose a supported property for this Aura (Blizzard) condition."
        end
      end
    end
    if not ValidCheck(data, condition.check) then
      return 'Use another trigger or a global condition. Aura (Blizzard) does not expose aura state to conditions.'
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
  if result then result.nativeConditionBaseData = data end
  return result or data
end

local function SetFontSize(text, size)
  local font, _, flags = text:GetFont()
  text:SetFont(font, size, flags)
end

local function ApplyProperty(button, data, property, value, overrides)
  -- Native aura children deny addon access while aura information is secret.
  if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() or OwnsDurationColor(data, property) then return end
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

function Display.StyleNativeConditionIndicators(native, data)
  local button = native.button
  if button.ClearPandemicRegions then button:ClearPandemicRegions() end
  for _, textures in pairs(native.conditionIndicators or {}) do for _, texture in ipairs(textures) do texture:Hide() end end
  native.conditionIndicators = native.conditionIndicators or {}
  for i = #(native.conditionDispelIndices or {}), 1, -1 do button:RemoveDispelTypeTexture(native.conditionDispelIndices[i]) end
  native.conditionDispelIndices = {}
  local dispelKeys = {"None", "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage", ""}
  for index, condition in ipairs(data.conditions or {}) do
    local kind = Display.NativeConditionKind(data, condition.check)
    if kind and not durationVariables[kind] and kind ~= "faAuraApplications" and not condition.linked then
      local settings, configured = {}, false
      for _, change in ipairs(condition.changes or {}) do
        if indicatorProperties[change.property] then settings[change.property] = change.value; configured = true end
      end
      local check = condition.check
      if kind == "faAuraType" and (check.op ~= "==" or (check.value ~= "HELPFUL" and check.value ~= "HARMFUL")) then configured = false end
      if kind == "faAuraDispel" and (check.op ~= "==" or type(check.value) ~= "string") then configured = false end
      if configured then
        local textures = native.conditionIndicators[index]
        if not textures then
          textures = {}
          for i = 1, 4 do textures[i] = button:CreateTexture(nil, "OVERLAY", nil, 7) end
          native.conditionIndicators[index] = textures
        end
        local style = settings.faAuraHighlightStyle or "border"
        local color = Color(settings.faAuraHighlightColor, {1, 0.82, 0, 1})
        local r,g,b,alpha = color:GetRGBA()
        local size = tonumber(settings.faAuraHighlightSize) or 2
        size = size == size and math.max(1, math.min(64, size)) or 2
        local asset = "Interface\\Buttons\\WHITE8X8"
        if style == "glow" then asset = "Interface\\Buttons\\UI-ActionButton-Border"
        elseif style == "texture" and type(settings.faAuraHighlightTexture) == "string" and settings.faAuraHighlightTexture ~= "" then
          asset = settings.faAuraHighlightTexture
        end
        for side, texture in ipairs(textures) do
          texture:ClearAllPoints(); texture:Hide()
          if style == "border" or side == 1 then
            texture:SetTexture(asset)
            texture:SetVertexColor(r,g,b,1)
            texture:SetAlpha(alpha)
            texture:SetDesaturated(style == "glow")
            texture:SetBlendMode(style == "glow" and "ADD" or "BLEND")
            if style == "border" then
              if side <= 2 then
                local point = side == 1 and "TOP" or "BOTTOM"
                texture:SetPoint(point .. "LEFT", button, point .. "LEFT")
                texture:SetPoint(point .. "RIGHT", button, point .. "RIGHT"); texture:SetHeight(size)
              else
                local point = side == 3 and "LEFT" or "RIGHT"
                texture:SetPoint("TOP" .. point, button, "TOP" .. point)
                texture:SetPoint("BOTTOM" .. point, button, "BOTTOM" .. point); texture:SetWidth(size)
              end
            else
              local padding = style == "glow" and (size + 8) or 0
              texture:SetPoint("TOPLEFT", button, "TOPLEFT", -padding, padding)
              texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", padding, -padding)
            end
            if kind == "faAuraPandemic" and button.AddPandemicRegion then
              button:AddPandemicRegion(texture)
            elseif button.AddDispelTypeTexture then
              local options = {showWhenHelpful = true, showWhenHarmful = true, showWithoutDispelType = true,
                style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset, customDispelAssetMap = {}, customDispelColorMap = {}}
              if kind == "faAuraType" then
                options.showWhenHelpful, options.showWhenHarmful = check.value == "HELPFUL", check.value == "HARMFUL"
              elseif kind == "faAuraStealable" or kind == "faAuraNotStealable" then
                options.showWhenHarmful = false
                options.stealableFilter = Enum.CustomAuraButtonDispelTypeStealableFilter[kind == "faAuraStealable" and "Stealable" or "NotStealable"]
              end
              for _, key in ipairs(dispelKeys) do
                if kind ~= "faAuraDispel" or check.value == key then
                  options.customDispelAssetMap[key] = {asset = asset}
                  options.customDispelColorMap[key] = CreateColor(r,g,b,1)
                end
              end
              local dispelIndex = button:AddDispelTypeTexture(texture, options)
              native.conditionDispelIndices[#native.conditionDispelIndices + 1] = dispelIndex
            end
          end
        end
      end
    end
  end
end
