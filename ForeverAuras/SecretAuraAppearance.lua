-- Shared Display settings rendered by Blizzard's native aura widgets.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay
local Media = LibStub("LibSharedMedia-3.0")

Display.supportedElements = {subbackground = true, subforeground = true, subtext = true, subborder = true, subglow = true, subtexture = true}

function Display.IsDetachedElement(data, element)
  return Display.HasTrigger(data) and element and element.secretAuraDetached == true
    and (element.type == "subtext" or element.type == "subtexture")
end

function Display.IsDetachedProperty(data, property)
  local index = property:match("^sub%.(%d+)%.")
  return index and Display.IsDetachedElement(data, data.subRegions and data.subRegions[tonumber(index)]) or false
end

function Display.CanAddElement(data, kind)
  if kind == "subcdmdispel" then return Private.CDMAuraProgress.IsConfigured(data) end
  if not Display.HasTrigger(data) then return true end
  if not Display.supportedElements[kind] then return false end
  if kind == "subborder" then
    for _, element in ipairs(data.subRegions or {}) do
      if element.type == "subborder" then return false end
    end
  end
  return true
end

local function TextDefault(regionType)
  local definition = Private.subRegionTypes.subtext.default
  local result = type(definition) == "function" and definition(regionType) or CopyTable(definition)
  result.type = "subtext"
  return result
end

function Display.MigrateAppearance(data, legacy)
  local settings = data.blizzardAuraDisplay
  if data.regionType == "text" then data.automaticWidth = "Fixed" end
  if settings.sharedDisplay then return end
  if legacy then
    local elements = {{type = "subbackground"}}
    for _, key in ipairs(Display.Elements(legacy)) do
      local element
      if key == "duration" or key == "stack" or key == "label" or key:match("^text%d+$") then
        element = TextDefault(data.regionType)
        element.text_text = key == "duration" and "%p" or key == "stack" and "%s" or legacy[key] or ""
        if key ~= "duration" and key ~= "stack" then element.text_text = element.text_text:gsub("%%", "%%%%") end
        element.text_visible = (key ~= "duration" or legacy.duration ~= false) and (key ~= "stack" or legacy.stacks ~= false) and legacy[key .. "Visible"] ~= false
        local fields = {Font = "text_font", Size = "text_fontSize", Color = "text_color", Outline = "text_fontType", Justify = "text_justify",
          ShadowColor = "text_shadowColor", ShadowX = "text_shadowXOffset", ShadowY = "text_shadowYOffset", SelfPoint = "text_selfPoint",
          Anchor = "anchor_point", X = "anchorXOffset", Y = "anchorYOffset"}
        for suffix, field in pairs(fields) do
          local value = legacy[key .. suffix]
          if value ~= nil then element[field] = type(value) == "table" and CopyTable(value) or value end
        end
        local anchor = key == "stack" and "BOTTOMRIGHT" or key == "label" and "BOTTOM" or "CENTER"
        element.anchor_point = legacy[key .. "Anchor"] or anchor
        element.text_selfPoint = legacy[key .. "SelfPoint"] or anchor
        element.anchorXOffset = legacy[key .. "X"] or (key == "stack" and -3 or 0)
        element.anchorYOffset = legacy[key .. "Y"] or ((key == "stack" or key == "label") and 3 or 0)
        element.text_fontSize = legacy[key .. "Size"] or (key == "stack" and 14 or legacy.fontSize or 18)
        element.text_shadowColor = CopyTable(legacy[key .. "ShadowColor"] or {0, 0, 0, 0})
        if key == "duration" then
          element.text_text_format_p_format = "timed"
          element.text_text_format_p_time_format = legacy.durationFormat == "clock" and 0 or legacy.durationFormat == "seconds" and -2 or -1
          element.text_text_format_p_time_precision = legacy.durationPrecision or 1
          element.text_text_format_p_time_dynamic_threshold = legacy.durationDecimalThreshold or 3
          element.text_text_format_p_time_legacy_floor = legacy.durationRoundUp == false
        end
      elseif key == "glow" then
        element = {type = "subglow", glow = legacy.glow == true, glowType = legacy.glowType == "pulse" and "buttonOverlay" or "Proc",
          glowColor = CopyTable(legacy.glowColor or {1, 0.82, 0, 1}), useGlowColor = legacy.useGlowColor ~= false,
          glowScale = legacy.glowScale or 1, glowDuration = legacy.glowDuration or 1, glowXOffset = legacy.glowX or 0, glowYOffset = legacy.glowY or 0}
      elseif key == "background" then
        element = {type = "subtexture", textureVisible = true, textureTexture = "Interface\\Buttons\\WHITE8X8",
          textureColor = CopyTable(legacy.backgroundColor or {0, 0, 0, 0.5}), textureBlendMode = "BLEND", anchor_mode = "area", anchor_area = "ALL"}
      end
      if element then elements[#elements + 1] = element end
    end
    data.subRegions = elements
    data.inverse = legacy.reverse ~= false
  elseif data.regionType == "icon" then
    data.inverse = true
  end
  settings.sharedDisplay = true
end

function Display.Dimensions(data)
  if data.regionType == "text" then
    return math.max(4, data.fixedWidth or 200), math.max(4, data.blizzardAuraDisplay.textHeight or (data.fontSize or 18) * 1.2)
  end
  return math.max(4, data.width or 64), math.max(4, data.height or 64)
end

-- Native bindings each own one text field. Never inspect their resulting text.
function Display.TextKind(value)
  if value == "%p" then return "duration" end
  if value == "%s" then return "stack" end
  if value == "%n" then return "name" end
  if not (value or ""):gsub("%%%%", ""):find("%%") then return "literal" end
end

function Display.ValidateAppearance(data)
  local used = {}
  local function CheckText(value, visible)
    if visible == false then return end
    local kind = Display.TextKind(value)
    if not kind then return "You can only use %p, %s, %n or hardcoded text. Put each code in its own text element. Custom text (%c) is not supported." end
    if kind ~= "literal" and used[kind] then return "Secret auras support one text element for each of %p, %s and %n. Remove the duplicate or turn off Show Text." end
    used[kind] = true
  end
  if data.regionType == "text" then
    local problem = CheckText(data.displayText)
    if problem then return problem end
  end
  for _, element in ipairs(data.subRegions or {}) do
    if element.type ~= "subborder" and not Display.supportedElements[element.type] then return "This sub element is not supported by Secret Auras. Use Text, Texture or Glow." end
    if Display.IsDetachedElement(data, element) then
      if element.type == "subtext" and Display.TextKind(element.text_text) ~= "literal" then
        return "Detached Text uses hardcoded text. Use other triggers and Conditions to control when it appears."
      end
    elseif element.type == "subtext" then
      local problem = CheckText(element.text_text, element.text_visible)
      if problem then return problem end
    elseif element.type == "subglow" and element.glow and element.glowType ~= "Proc" and element.glowType ~= "buttonOverlay" then
      return "Secret auras support Proc Glow and Action Button Glow. Choose one in Display."
    end
  end
end

local function TextSettings(element)
  return {textFont = element.text_font, textSize = element.text_fontSize, textColor = element.text_color, textOutline = element.text_fontType,
    textJustify = element.text_justify, textShadowColor = element.text_shadowColor, textShadowX = element.text_shadowXOffset,
    textShadowY = element.text_shadowYOffset, textSelfPoint = element.text_selfPoint, textAnchor = element.anchor_point,
    textX = element.text_anchorXOffset or element.anchorXOffset, textY = element.text_anchorYOffset or element.anchorYOffset}
end

local function BindText(button, text, value, config, prefix)
  local kind = Display.TextKind(value)
  if kind == "duration" then
    local format = config[prefix .. "p_time_format"]
    local options
    if format ~= nil and format ~= -1 then
      options = {textFormatter = Private.GetDurationTextFormatter(config[prefix .. "p_time_legacy_floor"] and 0 or 99,
        config[prefix .. "p_time_dynamic_threshold"] or 3, config[prefix .. "p_time_precision"] or 1, format == -2)}
    end
    button:SetDurationText(text, options)
  elseif kind == "stack" then button:SetApplicationCount(text)
  elseif kind == "name" then button:SetSpellName(text)
  else text:SetText((value or ""):gsub("%%%%", "%%")) end
end

local function TextLayout(text, mode, width, wrap)
  text:SetWidth(mode == "Fixed" and (width or 200) or 0)
  text:SetWordWrap(wrap ~= "Elide")
  text:SetNonSpaceWrap(wrap ~= "Elide")
end

local function Area(native, data, name)
  if data.regionType == "aurabar" and name == "bar" then return native.bar, native.barWidth, native.barHeight end
  if data.regionType == "aurabar" and data.icon and name == "icon" then return native.icon, native.iconSize, native.iconSize end
  local width, height = Display.Dimensions(data)
  return native.button, width, height
end

-- BackdropTemplate installs resize scripts and reads frame geometry. Native aura
-- children instead use fixed texture slices sized from the public Display settings.
local function StyleBorder(entry, parent, target, width, height, element)
  if not entry.border then
    entry.border = CreateFrame("Frame", nil, parent)
    entry.borderPieces = {}
    for _, name in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "LEFT", "RIGHT", "TOP", "BOTTOM"}) do
      entry.borderPieces[name] = entry.border:CreateTexture(nil, "ARTWORK")
    end
  end
  local frame, pieces = entry.border, entry.borderPieces
  local offset = element.border_offset or 0
  width, height = math.max(1, width + offset * 2), math.max(1, height + offset * 2)
  local size = math.min(math.max(0.1, element.border_size or 2), width / 2, height / 2)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", target, "CENTER")
  frame:SetSize(width, height)
  local file = Media:Fetch("border", element.border_edge or "Square Full White")
  for _, texture in pairs(pieces) do
    texture:ClearAllPoints()
    texture:SetTexture(file, "REPEAT", "REPEAT")
    texture:SetVertexColor(unpack(element.border_color or {1, 1, 1, 1}))
  end
  for index, point in ipairs({"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}) do
    local texture = pieces[point]
    texture:SetPoint(point, frame, point)
    texture:SetSize(size, size)
    local left = 0.5078125 + (index - 1) * 0.125
    texture:SetTexCoord(left, left + 0.109375, 0.0625, 0.9375)
  end
  local repeatX = math.max(0, width / size - 2 - 0.0625)
  local repeatY = math.max(0, height / size - 2 - 0.0625)
  for _, side in ipairs({"LEFT", "RIGHT"}) do
    local texture = pieces[side]
    texture:SetWidth(size)
    texture:SetPoint("TOP" .. side, pieces["TOP" .. side], "BOTTOM" .. side)
    texture:SetPoint("BOTTOM" .. side, pieces["BOTTOM" .. side], "TOP" .. side)
    local left = side == "LEFT" and 0.0078125 or 0.1328125
    texture:SetTexCoord(left, left + 0.109375, 0.0625, repeatY)
  end
  for _, side in ipairs({"TOP", "BOTTOM"}) do
    local texture = pieces[side]
    texture:SetHeight(size)
    texture:SetPoint(side .. "LEFT", pieces[side .. "LEFT"], side .. "RIGHT")
    texture:SetPoint(side .. "RIGHT", pieces[side .. "RIGHT"], side .. "LEFT")
    local left = side == "TOP" and 0.2578125 or 0.3828125
    texture:SetTexCoord(left, repeatX, left + 0.109375, repeatX, left, 0.0625, left + 0.109375, 0.0625)
  end
  frame:SetAlpha(element.border_alpha or 1)
  frame:Show()
end

function Display.StyleAppearance(native, data, ElementFrame, StyleText, StyleGlow)
  local button = native.button
  local width, height = Display.Dimensions(data)
  button:SetSize(width, height)
  native.inner:SetSize(width * 0.8, height * 0.8)
  native.outer:SetSize(width * 1.1, height * 1.1)
  button:ClearDurationText()
  button:ClearApplicationCount()
  button:ClearSpellName()
  button:ClearDurationBar()
  button:ClearDurationCooldown()
  button:ClearIcon()
  for _, frame in pairs(native.elementFrames or {}) do frame:Hide() end
  native.border:Hide()
  native.icon:Hide(); native.cooldown:Hide()
  if native.bar then native.bar:Hide() end
  if native.mainText then native.mainText:Hide() end
  for _, entry in pairs(native.sharedElements or {}) do
    if entry.glow then StyleGlow(entry, {blizzardAuraDisplay = {glow = false}}) end
  end
  native.sharedElements = native.sharedElements or {}
  local base = ElementFrame(native, "sharedBase")
  base:SetFrameLevel(button:GetFrameLevel() + 1); base:Show()
  native.icon:ClearAllPoints(); native.icon:SetAllPoints(button)
  native.icon:SetDesaturated(data.desaturate == true)
  local crop = math.min(0.45, math.max(0, (data.zoom or 0) / 2))
  native.icon:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
  native.icon:SetVertexColor(unpack(data.regionType == "aurabar" and data.icon_color or data.color or {1, 1, 1, 1}))
  if data.regionType == "icon" or (data.regionType == "aurabar" and data.icon) then
    if data.iconSource == 0 and data.displayIcon then native.icon:SetTexture(data.displayIcon) else button:SetIcon(native.icon) end
    native.icon:Show()
  end
  if data.regionType == "icon" and data.cooldown ~= false then
    native.cooldown:SetFrameLevel(base:GetFrameLevel() + 1)
    native.cooldown:SetDrawSwipe(data.cooldownSwipe ~= false)
    native.cooldown:SetDrawEdge(data.cooldownEdge == true)
    native.cooldown:SetReverse(data.inverse == true)
    native.cooldown:SetHideCountdownNumbers(data.cooldownTextDisabled ~= false)
    native.cooldown:SetSwipeColor(unpack(data.blizzardAuraDisplay.swipeColor or {0, 0, 0, 0.8}))
    button:SetDurationCooldown(native.cooldown)
  elseif data.regionType == "aurabar" then
    if not native.bar then native.bar = CreateFrame("StatusBar", nil, base) end
    local bar = native.bar
    bar:ClearAllPoints(); bar:SetAllPoints(button)
    bar:SetStatusBarTexture(data.textureSource == "LSM" and Media:Fetch("statusbar", data.texture or "Blizzard") or data.textureInput or "Interface\\Buttons\\WHITE8X8")
    bar:SetStatusBarColor(unpack(data.barColor or {1, 0, 0, 1}))
    local vertical = (data.orientation or "HORIZONTAL"):find("VERTICAL", 1, true) ~= nil
    native.barWidth = math.max(4, width - (data.icon and not vertical and height or 0))
    native.barHeight = math.max(4, height - (data.icon and vertical and width or 0))
    native.iconSize = vertical and width or height
    bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    bar:SetReverseFill((data.orientation or ""):find("INVERSE", 1, true) ~= nil)
    if not native.barBackground then native.barBackground = base:CreateTexture(nil, "BACKGROUND") end
    native.barBackground:SetAllPoints(bar)
    native.barBackground:SetColorTexture(unpack(data.backgroundColor or {0, 0, 0, 0.5}))
    native.barBackground:Show()
    if data.icon then
      local first = data.icon_side == "LEFT"
      local side = vertical and (first and "BOTTOM" or "TOP") or (first and "LEFT" or "RIGHT")
      local size = vertical and width or height
      native.icon:ClearAllPoints(); native.icon:SetSize(size, size); native.icon:SetPoint(side, button, side)
      bar:ClearAllPoints(); bar:SetPoint("TOPLEFT", button, "TOPLEFT", side == "LEFT" and size or 0, side == "TOP" and -size or 0)
      bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", side == "RIGHT" and -size or 0, side == "BOTTOM" and size or 0)
    end
    button:SetDurationBar(bar, {direction = data.inverse and Enum.StatusBarTimerDirection.ElapsedTime or Enum.StatusBarTimerDirection.RemainingTime})
    bar:Show()
  end
  if data.regionType ~= "aurabar" and native.barBackground then native.barBackground:Hide() end
  if data.regionType == "text" then
    native.mainText = native.mainText or base:CreateFontString(nil, "OVERLAY")
    StyleText(native.mainText, native, {textFont = data.font, textSize = data.fontSize, textColor = data.color, textOutline = data.outline,
      textJustify = data.justify, textShadowColor = data.shadowColor, textShadowX = data.shadowXOffset, textShadowY = data.shadowYOffset}, "text", 18, "CENTER", 0, 0)
    native.mainText:Show()
    TextLayout(native.mainText, data.automaticWidth, data.fixedWidth, data.wordWrap)
    BindText(button, native.mainText, data.displayText, data, "displayText_format_")
  end
  local borderSeen
  for index, element in ipairs(data.subRegions or {}) do
    if not Display.IsDetachedElement(data, element) then
      local frame = ElementFrame(native, "shared" .. index)
      frame:SetFrameLevel(button:GetFrameLevel() + index * 3 + 3); frame:SetAlpha(1); frame:Show()
      local entry = native.sharedElements[index]
      if not entry then entry = {button = button, elementFrames = {glow = frame}}; native.sharedElements[index] = entry end
      if entry.text then entry.text:Hide() end
      if entry.border then entry.border:Hide() end
      if entry.texture then entry.texture:Hide() end
      if element.type == "subbackground" then
        base:SetFrameLevel(frame:GetFrameLevel())
        if native.bar then native.bar:SetFrameLevel(base:GetFrameLevel() + 1) end
        native.cooldown:SetFrameLevel(base:GetFrameLevel() + 1)
      elseif element.type == "subforeground" and native.bar then
        native.bar:SetFrameLevel(frame:GetFrameLevel())
      elseif element.type == "subtext" and element.text_visible ~= false then
        entry.text = entry.text or frame:CreateFontString(nil, "OVERLAY")
        StyleText(entry.text, native, TextSettings(element), "text", 18, "CENTER", 0, 0)
        entry.text:SetAlpha(element.text_alpha or 1)
        TextLayout(entry.text, element.text_automaticWidth, element.text_fixedWidth, element.text_wordWrap)
        entry.text:Show()
        BindText(button, entry.text, element.text_text, element, "text_text_format_")
      elseif element.type == "subborder" then
        if not borderSeen and element.border_visible ~= false then
          local target, borderWidth, borderHeight = Area(native, data, element.anchor_area)
          StyleBorder(entry, frame, target, borderWidth, borderHeight, element)
        end
        borderSeen = true
      elseif element.type == "subglow" then
        entry.glowAnchor, entry.glowWidth, entry.glowHeight = Area(native, data, element.anchor_area)
        StyleGlow(entry, {width = width, height = height, blizzardAuraDisplay = {glow = element.glow, glowType = element.glowType == "buttonOverlay" and "pulse" or "proc",
          useGlowColor = element.useGlowColor, glowColor = element.glowColor, glowScale = element.glowScale, glowDuration = element.glowDuration,
          glowX = element.glowXOffset, glowY = element.glowYOffset}})
      elseif element.type == "subtexture" and element.textureVisible ~= false then
        entry.texture = entry.texture or frame:CreateTexture(nil, "ARTWORK")
        local texture = entry.texture
        texture:ClearAllPoints()
        if element.anchor_mode == "point" then
          local point = element.anchor_point or "CENTER"
          local target = button
          if point:sub(1, 6) == "INNER_" then target = native.inner; point = point:sub(7)
          elseif point:sub(1, 6) == "OUTER_" then target = native.outer; point = point:sub(7) end
          texture:SetSize(element.width or 32, element.height or 32)
          texture:SetPoint(element.self_point or "CENTER", target, point, element.xOffset or 0, element.yOffset or 0)
        else
          local target = Area(native, data, element.anchor_area)
          texture:SetPoint("TOPLEFT", target, "TOPLEFT", -(element.xOffset or 0) / 2, (element.yOffset or 0) / 2)
          texture:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", (element.xOffset or 0) / 2, -(element.yOffset or 0) / 2)
        end
        texture:SetTexture(element.textureTexture)
        texture:SetVertexColor(unpack(element.textureColor or {1, 1, 1, 1}))
        texture:SetDesaturated(element.textureDesaturate == true)
        texture:SetBlendMode(element.textureBlendMode or "BLEND")
        texture:SetTexCoord(element.textureMirror and 1 or 0, element.textureMirror and 0 or 1, 0, 1)
        texture:SetRotation(math.rad(element.textureRotation or 0))
        texture:SetAlpha(element.texture_alpha or 1)
        texture:Show()
      end
    end
  end
end
