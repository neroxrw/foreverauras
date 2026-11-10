-- Modified for ForeverAuras, 2026-10-07.
-- Modifications Copyright (C) 2026 ForeverAuras. Licensed under the GNU GPL v2 (see LICENSE).
if not WeakAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

-- Frames and hooks from this file are timed by the profiler (see Private.TimedAPI).
local CreateFrame, hooksecurefunc, TimedHookScript = Private.TimedAPI("SubSubText")
local SharedMedia = LibStub("LibSharedMedia-3.0");
local L = WeakAuras.L;
local FontStringScaleAnimationMode = Enum and Enum.FontStringScaleAnimationMode

local screenWidth, screenHeight = math.ceil(GetScreenWidth() / 20) * 20, math.ceil(GetScreenHeight() / 20) * 20

local defaultFont = WeakAuras.defaultFont
local defaultFontSize = WeakAuras.defaultFontSize

local default = function(parentType)
  if parentType == "icon" then
    -- No Shadow, but Outline
    local d = {
      text_text = "%p",
      text_color = {1, 1, 1, 1},
      text_font = defaultFont,
      text_fontSize = 16,
      text_fontType = "OUTLINE",
      text_visible = true,
      text_justify = "CENTER",

      text_selfPoint = "AUTO",
      anchor_point = "CENTER",
      anchorXOffset = 0,
      anchorYOffset = 0,

      text_shadowColor = { 0, 0, 0, 1},
      text_shadowXOffset = 0,
      text_shadowYOffset = 0,
      rotateText = "NONE",

      text_automaticWidth = "Auto",
      text_fixedWidth = 64,
      text_wordWrap = "WordWrap",
    }
    Private.subRegionPrototype.AddAlphaToDefault(d, "text")
    return d
  else
    -- With Shadow, without Outline
    local d = {
      text_text = "%n",
      text_color = {1, 1, 1, 1},
      text_font = defaultFont,
      text_fontSize = defaultFontSize,
      text_fontType = "None",
      text_visible = true,
      text_justify = "CENTER",

      text_selfPoint = "AUTO",
      anchor_point = parentType == "aurabar" and "INNER_RIGHT" or "BOTTOMLEFT",
      anchorXOffset = 0,
      anchorYOffset = 0,

      text_shadowColor = { 0, 0, 0, 1},
      text_shadowXOffset = 1,
      text_shadowYOffset = -1,
      rotateText = "NONE",

      text_automaticWidth = "Auto",
      text_fixedWidth = 64,
      text_wordWrap = "WordWrap",
    }
    Private.subRegionPrototype.AddAlphaToDefault(d, "text")
    return d
  end
end

local properties = {
  text_visible = {
    display = L["Visibility"],
    setter = "SetVisible",
    type = "bool",
    defaultProperty = true
  },
  text_text = {
    display = L["Text"],
    setter = "ChangeText",
    type = "string",
    control = "WeakAurasInputWithIndentation"
  },
  text_color = {
    display = L["Color"],
    setter = "Color",
    type = "color",
  },
  text_fontSize = {
    display = L["Font Size"],
    setter = "SetTextHeight",
    type = "number",
    min = 6,
    softMax = 72,
    step = 1,
    default = 12
  },
  text_anchorXOffset = {
    display = L["X-Offset"],
    setter = "SetXOffset",
    type = "number",
    softMin = (-1 * screenWidth),
    softMax = screenWidth,
    bigStep = 10,
  },
  text_anchorYOffset = {
    display = L["Y-Offset"],
    setter = "SetYOffset",
    type = "number",
    softMin = (-1 * screenHeight),
    softMax = screenHeight,
    bigStep = 10,
  },
}

Private.subRegionPrototype.AddAlphaProperties(properties, "text")
Private.subRegionPrototype.AddColorFromBooleanProperty(properties, "text", "text_color")

-- Rotate object around its origin
local function animRotate(object, degrees, anchor)
  if (not anchor) then
    anchor = "CENTER";
  end
  -- Something to rotate
  if object.animationGroup or degrees ~= 0 then
    -- Create AnimationGroup and rotation animation
    object.animationGroup = object.animationGroup or object:CreateAnimationGroup();
    local group = object.animationGroup;
    group.rotate = group.rotate or group:CreateAnimation("rotation");
    local rotate = group.rotate;

    if rotate:GetDegrees() == degrees and rotate:GetOrigin() == anchor then
      return
    end

    rotate:SetOrigin(anchor, 0, 0);
    rotate:SetDegrees(degrees);
    rotate:SetDuration(0);
    rotate:SetEndDelay(2147483647);
    group:Play();
    rotate:SetSmoothProgress(1);
    group:Pause();
  end
end

-- Calculate offset after rotation
local function getRotateOffset(object, degrees, point)
  -- Any rotation at all?
  if degrees ~= 0 then
    -- Basic offset
    local originoffset = object:GetStringHeight() / 2;
    local xo = -1 * originoffset * sin(degrees);
    local yo = originoffset * (cos(degrees) - 1);

    -- Alignment dependant offset
    if point:find("BOTTOM", 1, true) then
      yo = yo + (1 - cos(degrees)) * (object:GetStringWidth() / 2 - originoffset);
    elseif point:find("TOP", 1, true) then
      yo = yo - (1 - cos(degrees)) * (object:GetStringWidth() / 2 - originoffset);
    end
    if point:find("RIGHT", 1, true) then
      xo = xo + (1 - cos(degrees)) * (object:GetStringWidth() / 2 - originoffset);
    elseif point:find("LEFT", 1, true) then
      xo = xo - (1 - cos(degrees)) * (object:GetStringWidth() / 2 - originoffset);
    end

    -- Done
    return xo, yo;

  -- No rotation
  else
    return 0, 0;
  end
end
local fontObjectCounter = 0

-- ForeverAuras (1.3.6-dev.2, Dan's stray count): every text element ever
-- made, for the /fa textcheck diagnostic (Private.TextCheck), which lists
-- texts still shown without a live owner. Weak keys; nothing else reads it.
Private.subTextFrames = Private.subTextFrames or setmetatable({}, {__mode = "k"})

local function create()
  local region = CreateFrame("Frame", nil, UIParent);
  Private.subTextFrames[region] = true

  local text = region:CreateFontString(nil, "OVERLAY");
  region.text = text;

  -- WOW's layout system works best if frames and all their parents are anchored
  -- In this case, it appears that a text doesn't get the right size on the initial
  -- load with a custom font. (Though it works if the font is non-custom or after
  -- a ReloadUI). Just moving the normal AnchorSubRegion to the start of modify was not enough
  -- But anchoring the text to UIParent before re-anchoring it correctly does seem to fix
  -- the issue. Also see #1778
  text:SetPoint("CENTER", UIParent, "CENTER")

  text:SetWordWrap(true)
  text:SetNonSpaceWrap(true)

  local fontObject = CreateFont("ForeverAuras-SubText-Font" .. fontObjectCounter)
  fontObjectCounter =  fontObjectCounter + 1
  -- Defer attachment until modify has configured the font and its shadow.
  region.fontObject = fontObject

  return region;
end

local function onAcquire(subRegion)
  subRegion.faState = "live"   -- ForeverAuras (1.3.6-dev.4): lifecycle for /fa textcheck
  subRegion:Show()
end

local function onRelease(subRegion)
  -- A pooled subtext must not resume the previous aura's native timer slot.
  Private.CDMAuraProgress.HideText(subRegion)
  Private.BlizzardAuraDisplay.HideLinkedText(subRegion)
  -- ForeverAuras (1.3.6-dev.4): lifecycle for /fa textcheck; "pooled" only once the hide went through
  subRegion.faState = "release attempted"
  subRegion:Hide()
  subRegion.faState = "pooled"
end

local function modify(parent, region, parentData, data, first)
  region:SetParent(parent)
  -- ForeverAuras (1.3.6-dev.2): the display this element was last given to, for /fa textcheck
  region.faOwnerId, region.faOwnerClone = parent.id, parent.cloneId
  local text = region.text;
  local fontObject = region.fontObject

  local fontPath = SharedMedia:Fetch("font", data.text_font);
  local fontType = data.text_fontType == "None" and "" or data.text_fontType
  local slugFont = data.text_fontType == "SLUG" or data.text_fontType == "OUTLINE|SLUG" or data.text_fontType == "THICKOUTLINE|SLUG"
  if text.SetScaleAnimationMode and FontStringScaleAnimationMode then
    text:SetScaleAnimationMode(slugFont and FontStringScaleAnimationMode.Vertex or FontStringScaleAnimationMode.FontSize)
  end
  if text.SetSmoothScaling then
    text:SetSmoothScaling(data.text_smoothScaling or false) -- doesn't accept nil
  end
  -- Normal and CDM subtext share the same inherited shadow setup.
  fontObject:SetJustifyH(data.text_justify or "CENTER")
  Private.ApplyTextFont(text, fontObject, fontPath, data.text_fontSize, fontType,
    data.text_shadowColor, data.text_shadowXOffset, data.text_shadowYOffset)
  if text:GetFont() then
    text:SetText("") -- SetJustifyH is broken unless the text changes
    text:SetText(WeakAuras.ReplaceRaidMarkerSymbols(data.text_text));
  end

  text:SetTextHeight(data.text_fontSize);

  if (data.text_automaticWidth == "Fixed") then
    if (data.text_wordWrap == "WordWrap") then
      text:SetWordWrap(true);
      text:SetNonSpaceWrap(true);
    else
      text:SetWordWrap(false);
      text:SetNonSpaceWrap(false);
    end

    text:SetWidth(data.text_fixedWidth);
    region:SetWidth(data.text_fixedWidth);
    region.width = data.text_fixedWidth;
  else
    text:SetWidth(0);
    text:SetWordWrap(true);
    text:SetNonSpaceWrap(true);
  end

  if first then
    local containsCustomText = false
    for index, subRegion in ipairs(parentData.subRegions) do
      if subRegion.type == "subtext" and Private.ContainsCustomPlaceHolder(subRegion.text_text) then
        containsCustomText = true
        break
      end
    end
    if not containsCustomText then
      if type(parentData.conditions) == "table" then
        for _, condition in ipairs(parentData.conditions) do
          if type(condition.changes) == "table" then
            for _, change in ipairs(condition.changes) do
              if type(change.property) == "string"
                and change.property:match("sub%.%d+%.text_text")
              then
                containsCustomText = true
                break
              end
            end
          end
        end
      end
    end
    if containsCustomText and parentData.customText and parentData.customText ~= "" then
      parent.customTextFunc = WeakAuras.LoadFunction("return "..parentData.customText, parentData.id)
      parent.values.customTextUpdateThrottle = parentData.customTextUpdateThrottle or 0
    else
      parent.customTextFunc = nil
      parent.values.customTextUpdateThrottle = 0
    end
    parent.values.custom = nil
    parent.values.lastCustomTextUpdate = nil
    parent.values.customTextUpdated = false
  end

  local texts = {}
  local textStr = data.text_text or ""
  if textStr ~= "" then
    tinsert(texts, textStr)
  end

  local subRegionIndex = 1
  for index, subRegion in ipairs(parentData.subRegions) do
    if subRegion == data then
      subRegionIndex = index
      break;
    end
  end
  if type(parentData.conditions) == "table" then
    local conditionName = "sub."..subRegionIndex..".text_text"
    for _, condition in ipairs(parentData.conditions) do
      if type(condition.changes) == "table" then
        for _, change in ipairs(condition.changes) do
          if type(change.property) == "string" and change.property == conditionName then
            if type(change.value ) == "string" and change.value ~= "" then
              tinsert(texts, change.value)
            end
          end
        end
      end
    end
  end

  local tint = Private.DurationTextStyle(parentData, data, subRegionIndex)
  local getter = function(key, default)
    if key:find("_time_tint$") then return tint end
    local fullKey = "text_text_format_" .. key
    if (data[fullKey] == nil) then
      data[fullKey] = default
    end
    return data[fullKey]
  end

  region.subTextFormatters, region.everyFrameFormatters = Private.CreateFormatters(texts, getter, false, parentData)

  function region:ConfigureTextUpdate()
    Private.CDMAuraProgress.HideText(region)
    local nativeKind, nativeTrigger = Private.ParseCDMText(region.text_text)
    -- The placeholder's own Time Format settings, for countdowns Blizzard
    -- formats from a duration object (CopyCDMCountdownText).
    local token = type(region.text_text) == "string" and (region.text_text:match("^%%{(.-)}$") or region.text_text:match("^%%(.+)$"))
    local timeFormat = (nativeKind == "bp" or nativeKind == "p") and Private.CDMTextFormat and Private.CDMTextFormat(data, token) or nil
    if nativeKind == "bp" or nativeKind == "bs" then
      region.Update = function()
        if not text:GetFont() then return end
        local state = nativeTrigger and parent.states and parent.states[nativeTrigger] or not nativeTrigger and parent.state
        if Private.CDMAuraProgress.UpdateText(parent, region, data, nativeKind, nativeTrigger) then return end
        Private.CopyCDMCountdownText(text, state, nativeKind, timeFormat)
      end
      region.FrameTick = region.Update
      return
    end
    local UpdateText
    -- A text that is only a %p or %t timer hides itself, like the native
    -- countdown, while its timer is a GCD-length or wand Shoot lockout.
    local timerOnly = type(region.text_text) == "string" and region.text_text:match("^%s*%%[pt]%s*$") ~= nil
    text:SetAlpha(1)
    if region.text_text and Private.ContainsAnyPlaceHolders(region.text_text) then
      UpdateText = function()
        if Private.CDMAuraProgress.UpdateText(parent, region, data, nativeKind, nativeTrigger) then return end
        if nativeKind then
          local state = nativeTrigger and parent.states and parent.states[nativeTrigger] or not nativeTrigger and parent.state
          -- The options window's sample (cdmTextPreview) is formatted like
          -- any %p below, so the Time Format settings show in the preview.
          if state and state.cdmBuff and not state.cdmTextPreview then
            if text:GetFont() then Private.CopyCDMCountdownText(text, state, nativeKind, timeFormat) end
            return
          end
        end
        local textStr = region.text_text or ""
        textStr = Private.ReplacePlaceHolders(textStr, parent, nil, false, self.subTextFormatters)

        -- Set only when the string differs from what is shown: a cooldown
        -- icon's texts are updated on every global cooldown, and a timer text
        -- every tick, and the client lays the text out again on each set.
        -- Compared with the string itself (other code writes these texts
        -- too); a secret string cannot be compared and is set.
        if text:GetFont() then
          local rendered = WeakAuras.ReplaceRaidMarkerSymbols(textStr)
          local current = text:GetText()
          if issecretvalue(rendered) or issecretvalue(current) or current ~= rendered then
            text:SetText(rendered)
          end
        end
        if timerOnly then
          local state = parent.state
          -- ForeverAuras (dev.103, Dan's dev.102 focus run): the GCD alpha is the client's evaluation of
          -- the duration object (the costly call of a secret countdown's tick); a tick re-reads it a
          -- quarter second after the last read at most, a state update at once (region.alphaNow, set by
          -- Update). Nothing is cached across those reads: it is read less often.
          local now = GetTime()
          if region.alphaNow or not region.alphaRead or now - region.alphaRead >= 0.25 then
            region.alphaNow, region.alphaRead = nil, now
            local alpha = state and state.cdmHideGCDText and not state.cdmTextPreview
              and state.cdmTextDurationObject and Private.GCDTextAlpha(state.cdmTextDurationObject)
            text:SetAlpha(alpha or 1)
          end
        end
        region:UpdateAnchorOnTextChange()
      end
    end

    local Update
    if parent.customTextFunc and UpdateText then
      Update = function()
        if not parent.values.customTextUpdated then
          parent.values.custom = Private.RunCustomTextFunc(parent, parent.customTextFunc)
          parent.values.lastCustomTextUpdate = GetTime()
          parent.values.customTextUpdated = true
        end
        region.alphaNow = true   -- (dev.103) a state update reads the GCD alpha at once
        UpdateText()
      end
    elseif UpdateText then
      Update = function()
        region.alphaNow = true   -- (dev.103) a state update reads the GCD alpha at once
        UpdateText()
      end
    end

    local FrameTick
    if (nativeKind and Private.IsCDMBuffText(region.text_text, parentData))
       or Private.ContainsPlaceHolders(region.text_text, "p")
       or Private.AnyEveryFrameFormatters(region.text_text, region.everyFrameFormatters)
    then
      FrameTick = UpdateText
    end

    if parent.customTextFunc and parentData.customTextUpdate == "update" then
      if Private.ContainsCustomPlaceHolder(region.text_text) then
        FrameTick = function()
          if not parent.values.lastCustomTextUpdate
          or parent.values.lastCustomTextUpdate + parent.values.customTextUpdateThrottle < GetTime()
          then
            parent.values.custom = Private.RunCustomTextFunc(parent, parent.customTextFunc)
            parent.values.lastCustomTextUpdate = GetTime()
            parent.values.customTextUpdated = true
          end
          UpdateText()
        end
      end
    end

    local linkedKind, linkedTrigger = Private.BlizzardAuraDisplay.LinkedTextKind(region.text_text, parentData)
    if linkedKind and Update then
      local standard, standardTick = Update, FrameTick
      Private.BlizzardAuraDisplay.ResetLinkedText(region)
      Update = function()
        if Private.BlizzardAuraDisplay.UpdateLinkedText(region, data, parentData, linkedKind, linkedTrigger) then return end
        standard()
      end
      FrameTick = standardTick and function()
        if region.linkedTextActive then return end
        standardTick()
      end
    else
      Private.BlizzardAuraDisplay.HideLinkedText(region)
    end

    -- ForeverAuras (dev.98, corrected in dev.100 after Astra's review): a text
    -- that is only a %p timer in the "timed" format shows a string that can
    -- change only at known points of the remaining time: whole seconds, the
    -- decimal steps (and half steps, for rounding) below the dynamic
    -- threshold, the threshold itself, and zero. The tick formats at the
    -- first tick past the next such point and rests in between; if the shown
    -- string did not change there (another rounding than expected), it keeps
    -- formatting every tick until it does. The ordinary %p token is the case
    -- (Private.ParseCDMText names it "p" too); the native countdown route
    -- (a cdmBuff state), secret or paused timers, mod-rated or tinted ones,
    -- Blizzard's modern format and anything but a timed progress keep
    -- formatting every tick, as before. A state update formats at once and
    -- forgets the resting point.
    if FrameTick == UpdateText and timerOnly and region.text_text:match("%%p") then
      local formatKind = data["text_text_format_p_format"] or "timed"
      local timeFormat = tonumber(data["text_text_format_p_time_format"]) or 0
      local tinted = data["text_text_format_p_time_tint"]
      if formatKind == "timed" and timeFormat ~= 2 and not tinted then
        local threshold = tonumber(data["text_text_format_p_time_dynamic_threshold"]) or 60
        local precision = tonumber(data["text_text_format_p_time_precision"]) or 1
        local scale = 10 ^ precision
        local margin = 1e-5
        local restUntil, restFrom, restExpiration, restDuration, expectChange
        local tick = FrameTick
        -- the nearest point below the remaining time where the string can change
        -- (nil when the remaining time sits ON such a point: a string may change just below it, so the
        -- next tick formats as well)
        local function NextPoint(remaining)
          if math.abs(remaining - math.floor(remaining + 0.5)) < margin then return nil end
          if threshold > 0 and math.abs(remaining - threshold) < margin then return nil end
          local point = 0
          local whole = math.floor(remaining - margin)
          if whole > point then point = whole end
          if threshold > 0 and remaining < threshold + margin then
            -- decimals are printf-rounded: the string changes around the half steps (k + 0.5) / scale
            local steps = remaining * scale - 0.5
            if math.abs(steps - math.floor(steps + 0.5)) < margin * scale then return nil end
            local half = (math.floor((remaining - margin) * scale - 0.5) + 0.5) / scale
            if half > point then point = half end
          elseif threshold > 0 and threshold > point then
            point = threshold
          end
          if point < 0 then point = 0 end
          return point
        end
        FrameTick = function()
          local state = parent.state
          local expiration = state and state.expirationTime
          local duration = state and state.duration
          if not state or state.progressType ~= "timed" or state.paused or state.cdmBuff
            or type(expiration) ~= "number" or type(duration) ~= "number"
            or issecretvalue(expiration) or issecretvalue(duration)
            or (state.modRate ~= nil and (issecretvalue(state.modRate) or state.modRate ~= 1)) then
            restUntil = nil
            return tick()
          end
          local now = GetTime()
          if restUntil and expiration == restExpiration and duration == restDuration and now < restUntil then return end
          local before = text:GetText()
          tick()
          local after = text:GetText()
          local expected = expectChange and expiration == restExpiration and duration == restDuration
          restExpiration, restDuration = expiration, duration
          if expected and not issecretvalue(after) and not issecretvalue(before) and after == before and now - restFrom < 0.25 then
            -- the change expected at this point has not shown yet: look again next tick
            return
          end
          expectChange = false
          local remaining = expiration - now
          if remaining <= 0 then
            restUntil, restFrom = math.huge, now   -- expired: formatted (empty) once, a new timer wakes it
            return
          end
          local point = NextPoint(remaining)
          if point then
            restUntil, restFrom, expectChange = expiration - point, expiration - point, true
          else
            restUntil, restFrom = now, now   -- on a point: the next tick formats too (no change expected of it)
          end
          -- (dev.101, Dan's focus profile) a text hidden during GCD-length lockouts re-reads its alpha
          -- from the client's duration object at every format (Private.GCDTextAlpha, a costly client
          -- call): resting keeps that to four reads a second at most instead of thirty
          if state.cdmHideGCDText and restUntil > now + 0.25 then
            restUntil, restFrom, expectChange = now + 0.25, now + 0.25, false
          end
        end
        local standard = Update
        Update = function()
          restUntil = nil
          return standard()
        end
      end
    end

    region.Update = Update
    region.FrameTick = FrameTick and Private.ThrottledTextTick(FrameTick)

    if not UpdateText then
      if text:GetFont() then
        local textStr = region.text_text
        textStr = textStr:gsub("\\n", "\n");
        text:SetText(WeakAuras.ReplaceRaidMarkerSymbols(textStr))
      end
    end
  end

  function region:ConfigureSubscribers()
    local visible = self:IsShown()
    -- ForeverAuras 1.2.1 (Astra's performance review 1): a text hidden by its
    -- own visibility setting leaves its subscriptions; before, only a text
    -- without the callbacks was removed, so a hidden text kept updating and
    -- kept an otherwise idle display on the frame tick. Shown again, it
    -- refreshes at once (below) as before.
    if visible and self.Update then
      parent.subRegionEvents:AddSubscriber("Update", region)
    else
      parent.subRegionEvents:RemoveSubscriber("Update", region)
    end
    if visible and self.FrameTick then
      parent.subRegionEvents:AddSubscriber("FrameTick", region)
    else
      parent.subRegionEvents:RemoveSubscriber("FrameTick", region)
    end
    -- ForeverAuras 1.2.1 (performance review 2): a text's tick function can
    -- change while it stays subscribed (ChangeText); the display sorts
    -- itself onto the text or the frame queue again (RegionPrototype.lua).
    if parent.UpdateTick then parent:UpdateTick() end
    if self.Update and parent.state and visible then
      self:Update()
    end
  end

  function region:ChangeText(msg)
    region.text_text = msg
    region:ConfigureTextUpdate()
    region:ConfigureSubscribers()
  end

  region.text_text = data.text_text
  region:ConfigureTextUpdate()

  function region:SetTextHeight(size)
    local fontPath = SharedMedia:Fetch("font", data.text_font);
    if not text:GetFont() then -- Font invalid, set the font but keep the setting
      text:SetFont(STANDARD_TEXT_FONT, size, fontType);
    else
      region.text:SetFont(fontPath, size, fontType);
    end
    region.text:SetTextHeight(size)
    region:UpdateAnchorOnTextChange();
    -- Keep the native CDM fallback in sync with font-size conditions.
    Private.CDMAuraProgress.StyleText(region)
  end

  function region:SetVisible(visible)
    if visible then
      self:Show()
    else
      self:Hide()
    end
    region:ConfigureSubscribers()
  end

  function region:Color(r, g, b, a)
    region.color_r = r;
    region.color_g = g;
    region.color_b = b;
    region.color_a = a;
    if (r or g or b) then
      a = a or 1;
    end
    text:SetTextColor(region.color_anim_r or r, region.color_anim_g or g,
                      region.color_anim_b or b, region.color_anim_a or a)
    -- The bound countdown has its own font, but shares this subtext's colour.
    Private.CDMAuraProgress.StyleText(region)
  end

  local selfPoint = data.text_selfPoint
  if selfPoint == "AUTO" then
    if parentData.regionType == "icon" then
      local anchorPoint = data.anchor_point or "CENTER"
      if anchorPoint:sub(1, 6) == "INNER_" then
        selfPoint = anchorPoint:sub(7)
      elseif anchorPoint:sub(1, 6) == "OUTER_" then
        anchorPoint = anchorPoint:sub(7)
        selfPoint = Private.inverse_point_types[anchorPoint] or "CENTER"
      else
        selfPoint = "CENTER"
      end
    elseif parentData.regionType == "aurabar" then
      selfPoint = data.anchor_point or "CENTER"
      if selfPoint:sub(1, 5) == "ICON_" then
        selfPoint = selfPoint:sub(6)
      elseif selfPoint:sub(1, 6) == "INNER_" then
        selfPoint = selfPoint:sub(7)
      end
      selfPoint = Private.point_types[selfPoint] and selfPoint or "CENTER"
    else
      selfPoint = Private.inverse_point_types[data.anchor_point or "CENTER"] or "CENTER"
    end
  end

  region.text_anchorXOffset = data.text_anchorXOffset
  region.text_anchorYOffset = data.text_anchorYOffset

  local textDegrees = data.rotateText == "LEFT" and 90 or data.rotateText == "RIGHT" and -90 or 0;

  -- The native countdown sits where this text sits. In a Modern Aura Group
  -- the text itself is parked off screen with its display and the stand-in's
  -- copy of it is what shows, so the countdown follows that copy (or, when
  -- the copy refuses a dependent, its own container, which already does).
  region.AnchorNativeText = function(self, nativeText)
    nativeText:ClearAllPoints()
    local target = Private.CDMAuraProgress.NativeTextAnchor(self)
    nativeText.faAnchorTarget = target
    if target ~= text and not pcall(nativeText.SetPoint, nativeText, selfPoint, target, selfPoint) then
      nativeText:ClearAllPoints()
      local container = self.cdmAuraTimer and self.cdmAuraTimer.container
      if container then nativeText:SetPoint(selfPoint, container, selfPoint)
      else nativeText:SetPoint(selfPoint, text, selfPoint) end
    elseif target == text then
      nativeText:SetPoint(selfPoint, text, selfPoint)
    end
  end

  region.Anchor = function(self)
    local xo, yo = getRotateOffset(text, Private.IsCDMBuffText(region.text_text, parentData) and 0 or textDegrees, selfPoint)
    parent:AnchorSubRegion(text, "point", data.anchor_point, selfPoint,
                           (self.text_anchorXOffset or 0) + xo, (self.text_anchorYOffset or 0) + yo)
    -- Native countdowns use the same public anchor/offset configuration.
    Private.CDMAuraProgress.StyleText(region)
  end

  if textDegrees == 0 then
    region.UpdateAnchorOnTextChange = function() end
  else
    region.UpdateAnchorOnTextChange = region.Anchor
  end

  region.SetXOffset = function(self, xOffset)
    if self.text_anchorXOffset == xOffset then
      return
    end
    self.text_anchorXOffset = xOffset
    self:Anchor()
  end

  region.SetYOffset = function(self, yOffset)
    if self.text_anchorYOffset == yOffset then
      return
    end
    self.text_anchorYOffset = yOffset
    self:Anchor()
  end

  region:SetAlpha(1)
  region:Color(data.text_color[1], data.text_color[2], data.text_color[3], data.text_color[4]);
  region:SetVisible(data.text_visible)
  animRotate(text, textDegrees, selfPoint)
  region:Anchor()
  Private.CDMAuraProgress.ModifyText(parent, region, parentData, data)
end

local function addDefaultsForNewAura(data)
  if data.regionType == "aurabar" then
    local d1 = {
      ["type"] = "subtext",
      text_text = "%p",
      text_color = {1, 1, 1, 1},
      text_font = defaultFont,
      text_fontSize = defaultFontSize,
      text_fontType = "None",
      text_justify = "CENTER",
      text_visible = true,

      text_selfPoint = "AUTO",
      anchor_point = "INNER_LEFT",
      anchorXOffset = 0,
      anchorYOffset = 0,

      text_shadowColor = { 0, 0, 0, 1},
      text_shadowXOffset = 1,
      text_shadowYOffset = -1,

      rotateText = "NONE",
    }
    Private.subRegionPrototype.AddAlphaToDefault(d1, "text")

    tinsert(data.subRegions, d1);

    local d2 = {
      ["type"] = "subtext",
      text_text = "%n",
      text_color = {1, 1, 1, 1},
      text_font = defaultFont,
      text_fontSize = defaultFontSize,
      text_fontType = "None",
      text_justify = "CENTER",
      text_visible = true,

      text_selfPoint = "AUTO",
      anchor_point = "INNER_RIGHT",
      anchorXOffset = 0,
      anchorYOffset = 0,

      text_shadowColor = { 0, 0, 0, 1},
      text_shadowXOffset = 1,
      text_shadowYOffset = -1,

      rotateText = "NONE",
    }
    Private.subRegionPrototype.AddAlphaToDefault(d2, "text")

    tinsert(data.subRegions, d2);
  elseif data.regionType == "icon" then
    local d1 = {
      ["type"] = "subtext",
      text_text = "%p",
      text_color = {1, 1, 1, 1},
      text_font = defaultFont,
      text_fontSize = 16,
      text_fontType = "OUTLINE",
      text_justify = "CENTER",
      text_visible = true,

      text_selfPoint = "AUTO",
      anchor_point = "CENTER",
      anchorXOffset = 0,
      anchorYOffset = 0,

      text_shadowColor = { 0, 0, 0, 1},
      text_shadowXOffset = 0,
      text_shadowYOffset = 0,

      rotateText = "NONE",
    }
    Private.subRegionPrototype.AddAlphaToDefault(d1, "text")

    tinsert(data.subRegions, d1);
  end
end

local function supports(regionType)
  return regionType == "texture"
         or regionType == "progresstexture"
         or regionType == "icon"
         or regionType == "aurabar"
         or regionType == "empty"
end

WeakAuras.RegisterSubRegionType("subtext", L["Text"], supports, create, modify, onAcquire, onRelease,
                                default, addDefaultsForNewAura, properties)

-- ForeverAuras (1.3.6-dev.4, Dan's stray count; Astra's textcheck reviews):
-- "/fa textcheck" is a READ-ONLY report of the addon's text elements (the
-- SubText wrappers made since the reload; native countdowns, linked copies,
-- Text displays and custom-code strings are NOT covered, so a clean report
-- does not rule those out, and a stale record is evidence, not proof that it
-- paints a given glyph). For every element whose wrapper or FontString has
-- its visible flag set (IsVisible: an ancestry check, not pixels on screen),
-- or whose visibility cannot be read, it classifies the element:
--   live      listed by the display it is parented to, and that display is the
--             one it was last given to, by aura id AND clone key
--   stale     parented to a display that does not list it, or last given to a
--             different display or clone, or its FontString left its wrapper
--   pooled    released to the pool (release completed) yet visible
--   detached  a detached element of a Modern display (parent is not the display by design)
--   unknown   a read failed or returned a secret value somewhere on the way
-- and prints the records that are not plainly live (and live ones whose text
-- is secret or unreadable, as information). Every lookup and call is
-- guarded and classified before use; one unreadable object marks its own
-- record unknown and the rest of the report still prints. There is no hide.
local function Call(object, method, ...)
  if object == nil then return false, "nil object" end
  local okF, fn = pcall(function() return object[method] end)
  if not okF then return false, fn end
  if type(fn) ~= "function" then return false, "no " .. tostring(method) end
  local results = {pcall(fn, object, ...)}
  if not results[1] then return false, results[2] end
  for i = 2, #results do if issecretvalue(results[i]) then return false, "secret" end end
  return true, unpack(results, 2)
end
local function Field(object, key)
  if object == nil then return false, "nil object" end
  local ok, value = pcall(function() return object[key] end)
  if not ok then return false, value end
  if issecretvalue(value) then return false, "secret" end
  return true, value
end
local function SameClone(a, b)
  if a == nil or a == "" then a = nil end
  if b == nil or b == "" then b = nil end
  return a == b
end
local function Describe(frame)
  if frame == nil then return "nil" end
  if frame == UIParent then return "UIParent" end
  local okI, id = Field(frame, "id")
  if okI and id ~= nil then
    local okC, clone = Field(frame, "cloneId")
    return ("display %s (clone %s)"):format(tostring(id), okC and tostring(clone) or "unreadable")
  end
  local okN, name = Call(frame, "GetName")
  if okN and name then return tostring(name) end
  local okT, kind = Call(frame, "GetObjectType")
  return okT and ("a %s"):format(tostring(kind)) or "unreadable"
end
-- true / false / nil (unknown: the list could not be read)
local function Lists(region, frame)
  if region == nil then return false end
  local ok, subs = Field(region, "subRegions")
  if not ok then return nil end
  if type(subs) ~= "table" then return false end
  local okI, found = pcall(function() for _, sub in ipairs(subs) do if sub == frame then return true end end return false end)
  if not okI then return nil end
  return found
end

function Private.TextCheck()
  local counted, failed, counts, records = 0, 0, {}, 0
  for frame in pairs(Private.subTextFrames or {}) do
    local okW, wrapperVisible = Call(frame, "IsVisible")
    local okX, text = Field(frame, "text")
    local okTV, textVisible = Call(okX and text or nil, "IsVisible")
    local anyVisible = (okW and wrapperVisible == true) or (okTV and textVisible == true)
    local readable = okW and okTV
    if not readable then failed = failed + 1 end
    if anyVisible or not readable then
      counted = counted + 1
      local okP, parent = Call(frame, "GetParent")
      local okTP, textParent = Call(okX and text or nil, "GetParent")
      local okPI, parentId = Field(okP and parent or nil, "id")
      local okPC, parentClone = Field(okP and parent or nil, "cloneId")
      local okPR, parentRegionType = Field(okP and parent or nil, "regionType")
      local parentIsDisplay = okP and okPR and type(parentRegionType) == "string"
      local okPS, parentShown = Call(okP and parent or nil, "IsShown")
      local ownerId, ownerClone = frame.faOwnerId, frame.faOwnerClone
      local ownerRegion = ownerId and WeakAuras.GetRegion(ownerId, (ownerClone ~= nil and ownerClone ~= "") and ownerClone or nil) or nil
      local listedByParent = false
      if parentIsDisplay then listedByParent = Lists(parent, frame) end
      local listedByOwner = Lists(ownerRegion, frame)
      local okT, value = Call(okX and text or nil, "GetText")
      local state
      if not (readable and okP and okTP and okX) or (parentIsDisplay and not (okPI and okPC and okPS)) or listedByParent == nil or listedByOwner == nil then state = "unknown"
      elseif frame.secretAuraDetached then state = "detached"
      elseif frame.faState == "pooled" then state = "pooled"
      elseif textParent ~= frame then state = "stale"
      elseif parentIsDisplay and listedByParent == true and (ownerId == nil or (parentId == ownerId and SameClone(parentClone, ownerClone))) then state = "live"
      else state = "stale" end
      counts[state] = (counts[state] or 0) + 1
      -- A live element whose text cannot be read (secret) is printed too, as information, not as a fault.
      if state ~= "live" or not okT then
        records = records + 1
        local okA, _, anchor = Call(okX and text or nil, "GetPoint", 1)
        WeakAuras.prettyPrint(("Text check %d: %s; wrapper under %s%s; text under %s; last given to %s (clone %s); listed by parent: %s, by owner: %s; lifecycle %s; text %s; anchored to %s"):format(
          records, state, okP and Describe(parent) or "unreadable",
          parentIsDisplay and (okPS and (parentShown and ", shown" or ", hidden") or ", visibility unreadable") or "",
          okTP and (textParent == frame and "its wrapper" or Describe(textParent)) or "unreadable",
          tostring(ownerId), tostring(ownerClone),
          listedByParent == nil and "unknown" or tostring(listedByParent), listedByOwner == nil and "unknown" or tostring(listedByOwner),
          tostring(frame.faState),
          okT and ("%q"):format(tostring(value)) or ("unreadable (%s)"):format(tostring(value)),
          okA and Describe(anchor) or "unreadable"))
      end
    end
  end
  WeakAuras.prettyPrint(("Text check: %d elements with a visible flag or an unreadable one: %d live, %d stale, %d pooled, %d detached, %d unknown (%d with a failed read). Visible flag is an ancestry check, not pixels on screen. Covers the addon's text elements only, not native countdowns, linked copies, Text displays or custom strings; a stale record is evidence, not proof."):format(
    counted, counts.live or 0, counts.stale or 0, counts.pooled or 0, counts.detached or 0, counts.unknown or 0, failed))
end

-- ForeverAuras (1.3.6-dev.5, Dan's stray count): "/fa textcheck native" sweeps
-- every aura container frame the client knows (EnumerateFrames; forbidden
-- frames skipped) and reports the ones that have a visible string the addon
-- cannot read (a countdown or stack count the client draws from secret
-- data), with the container's state and the frames above it, up to the
-- display or named frame that owns it. Read-only; every lookup and call is
-- guarded, one unreadable object marks its own record. It covers strings
-- inside aura containers only; a string drawn elsewhere is not listed.
local function Chain(frame)
  local parts, cursor, depth, ownedByDisplay = {}, frame, 0, false
  while cursor and depth < 8 do
    local okP, parent = Call(cursor, "GetParent")
    if not okP then parts[#parts + 1] = "unreadable parent"; break end
    if parent == nil then break end
    parts[#parts + 1] = Describe(parent)
    local okI, id = Field(parent, "id")
    if okI and id ~= nil then ownedByDisplay = true; break end
    if parent == UIParent then break end
    cursor = parent
    depth = depth + 1
  end
  return table.concat(parts, " < "), ownedByDisplay
end
local coverage = {regionsFailed = 0, childrenFailed = 0, depthBound = 0, forbiddenSkipped = 0, forbiddenUnknown = 0}
local function Strings(frame, found, depth)
  if depth > 6 then coverage.depthBound = coverage.depthBound + 1; return end
  local okR, regions = pcall(function() return {frame:GetRegions()} end)
  if not okR then coverage.regionsFailed = coverage.regionsFailed + 1 end
  if okR then
    for _, region in ipairs(regions) do
      local okK, kind = Call(region, "GetObjectType")
      if okK and kind == "FontString" then
        local okV, visible = Call(region, "IsVisible")
        if not okV or visible == true then
          local okT, value = Call(region, "GetText")
          found[#found + 1] = {ok = okT, text = value}
        end
      end
    end
  end
  local okC, children = pcall(function() return {frame:GetChildren()} end)
  if not okC then coverage.childrenFailed = coverage.childrenFailed + 1 end
  if okC then for _, child in ipairs(children) do Strings(child, found, depth + 1) end end
end
function Private.TextCheckNative()
  local containers, reported, kinds = 0, 0, {}
  for k in pairs(coverage) do coverage[k] = 0 end
  local frame = EnumerateFrames()
  while frame do
    local okF, forbidden = Call(frame, "IsForbidden")
    if not okF then coverage.forbiddenUnknown = coverage.forbiddenUnknown + 1
    elseif forbidden then coverage.forbiddenSkipped = coverage.forbiddenSkipped + 1 end
    if okF and not forbidden then
      -- An aura container is known by its API, not by its object type name
      -- (the client does not report "AuraContainer" for it).
      local okM, addSlot = Field(frame, "AddAuraSlot")
      local okK, kind = Call(frame, "GetObjectType")
      if okM and type(addSlot) == "function" then
        containers = containers + 1
        kinds[tostring(okK and kind or "?")] = (kinds[tostring(okK and kind or "?")] or 0) + 1
        local okV, visible = Call(frame, "IsVisible")
        if not okV or visible == true then
          local found = {}
          Strings(frame, found, 0)
          local texts, blanks, unreadable = {}, 0, 0
          for _, entry in ipairs(found) do
            if not entry.ok then unreadable = unreadable + 1
            elseif entry.text == nil or entry.text == "" then blanks = blanks + 1
            else texts[#texts + 1] = ("%q"):format(tostring(entry.text)) end
          end
          local chain, ownedByDisplay = Chain(frame)
          -- Reported: a string the addon cannot read, or real text in a
          -- container that no ForeverAuras display owns (custom code's own
          -- native slots, such as the Consumes backend's roots under UIParent).
          if unreadable > 0 or (not ownedByDisplay and #texts > 0) then
            reported = reported + 1
            local okE, enabled = Call(frame, "IsEnabled")
            local okS, shown = Call(frame, "IsShown")
            local before = coverage.regionsFailed + coverage.childrenFailed + coverage.depthBound
            WeakAuras.prettyPrint(("Native check %d: %s container, %s, %s; above it: %s; text: %s; %d blank, %d unreadable%s"):format(reported,
              ownedByDisplay and "display-owned" or "NOT display-owned",
              okS and (shown and "shown" or "hidden") or "shown unreadable",
              okE and (enabled and "enabled" or "disabled") or "enabled unreadable",
              chain, #texts > 0 and table.concat(texts, ", ") or "none readable", blanks, unreadable,
              (coverage.regionsFailed + coverage.childrenFailed + coverage.depthBound) > before and "; part of this container could not be walked" or ""))
          end
        end
      end
    end
    frame = EnumerateFrames(frame)
  end
  local kindList = {}
  for kind, n in pairs(kinds) do kindList[#kindList + 1] = ("%s x%d"):format(kind, n) end
  WeakAuras.prettyPrint(("Native check: %d aura containers (object types: %s), %d reported (an unreadable string, or readable text in a container no display owns). Coverage: %d forbidden frames skipped, %d frames whose forbidden state could not be read, %d region lists and %d child lists unreadable, %d subtrees cut at the depth bound. Strings outside aura containers are not covered; an uninspectable subtree is unknown, not empty."):format(
    containers, table.concat(kindList, ", "), reported, coverage.forbiddenSkipped, coverage.forbiddenUnknown, coverage.regionsFailed, coverage.childrenFailed, coverage.depthBound))
end

-- ForeverAuras (1.3.6-dev.8, Astra's native review): "/fa textcheck consumes"
-- maps the Clickable Consumes backend's own native layer by its actual
-- records (aura_env.natives and aura_env.nativePool of "FCR: Consumes
-- (Backend)"): per category and cache signature, the root's state, the
-- display the native was last drawn for versus the category's current
-- display, every chain's count text and what that count is anchored to, and
-- pooled (not current) natives whose frames are still shown. Read-only; all
-- reads guarded; failures are reported as unknown.
function Private.TextCheckConsumes()
  local accessor = Private.memoryRootAccessors and Private.memoryRootAccessors["aura environments"]
  local envs = accessor and accessor()
  local env = envs and envs["FCR: Consumes (Backend)"]
  if not env then WeakAuras.prettyPrint("Consumes check: the backend's environment is not loaded (aura not loaded or renamed)."); return end
  local click = env.CLICK or "FCR: Consumes Bar"
  local function FrameState(f)
    if f == nil then return "none" end
    local okS, shown = Call(f, "IsShown"); local okV, visible = Call(f, "IsVisible")
    local okE, enabled = Call(f, "IsEnabled")
    return (okS and (shown and "shown" or "hidden") or "shown?") .. "/" .. (okV and (visible and "visible" or "not visible") or "visible?")
      .. (okE and (enabled and "/enabled" or "/disabled") or "")
  end
  -- ForeverAuras (1.3.6-dev.11): strata/level of the frame that draws an element (a font string's parent)
  -- and where it sits on screen, each read guarded; a font string reports its own position.
  local function Layer(element)
    if element == nil then return "none" end
    local frame = element
    local okO, objectType = Call(element, "GetObjectType")
    if okO and (objectType == "FontString" or objectType == "Texture") then
      local okP, parent = Call(element, "GetParent")
      frame = okP and parent or nil
    end
    local okS, strata = Call(frame, "GetFrameStrata"); local okL, level = Call(frame, "GetFrameLevel")
    local okX, left = Call(element, "GetLeft"); local okY, top = Call(element, "GetTop")
    local okW, width = Call(element, "GetWidth")
    return ("%s/%s at %s,%s w%s"):format(okS and tostring(strata) or "strata?", okL and tostring(level) or "level?",
      okX and left and ("%.0f"):format(left) or "?", okY and top and ("%.0f"):format(top) or "?",
      okW and width and ("%.0f"):format(width) or "?")
  end
  local function CountInfo(chain, currentRegion)
    local count = chain.count
    if not count then return "no count" end
    local okT, text = Call(count, "GetText")
    local okV, visible = Call(count, "IsVisible")
    local okA, _, anchor = Call(count, "GetPoint", 1)
    local where = "anchor unreadable"
    if okA then
      local okP, anchorParent = Call(anchor, "GetParent")
      if anchor == nil then where = "no anchor"
      elseif anchor == currentRegion or (okP and anchorParent == currentRegion) then where = "anchored on the CURRENT display"
      elseif okP and anchorParent ~= nil and Field(anchorParent, "id") then where = "anchored on " .. Describe(anchorParent) .. " (NOT the current display)"
      else where = "anchored on " .. Describe(anchor) end
    end
    return ("text %s, %s, %s"):format(okT and ("%q"):format(tostring(text)) or ("unreadable (%s)"):format(tostring(text)),
      okV and (visible and "visible" or "not visible") or "visibility unreadable", where)
  end
  local function Report(key, native, current)
    local okR, regions = pcall(function() return WeakAuras.GetRegion(click, key) end)
    local region = okR and regions or nil
    local visualRegion = native.visual and native.visual.region
    WeakAuras.prettyPrint(("Consumes check: %s native for %s, signature %s: root %s, %s; drawn for %s, current display %s%s"):format(
      current and "CURRENT" or "POOLED", tostring(key), tostring(native.signature), FrameState(native.root),
      native.disabled and "disabled" or "enabled",
      Describe(visualRegion), Describe(region), visualRegion == region and "" or " (DIFFERENT)"))
    for index, chain in ipairs(native.chains or {}) do
      local level = chain.levels and chain.levels[1]
      local container = level and level.container
      if chain.count or (container and select(2, Call(container, "IsVisible")) == true) then
        WeakAuras.prettyPrint(("  chain %d (%d of %d requirements%s): container %s, button %s; %s"):format(index, #(chain.members or {}), native.n or 0,
          chain.full and ", full" or "", FrameState(container), level and level.button and "built" or "not built", CountInfo(chain, region)))
        -- ForeverAuras (1.3.6-dev.11, Consumes doubled digit): the draw order the chains actually have, so a
        -- lower chain's count showing through a fuller chain's picture can be told from a wrong number.
        local last = chain.levels and chain.levels[#(chain.members or {})]
        WeakAuras.prettyPrint(("    layers: first container %s, last skin %s, count %s"):format(
          Layer(container), Layer(last and last.skin), Layer(chain.count)))
      end
    end
    local subText = region and region.subRegions
    local textLine = "no sub-text"
    if type(subText) == "table" then
      for _, sub in ipairs(subText) do
        if type(sub) == "table" and sub.text then textLine = "sub-text " .. Layer(sub.text); break end
      end
    end
    WeakAuras.prettyPrint(("    display layers: region %s, native root %s, %s"):format(Layer(region), Layer(native.root), textLine))
  end
  local seen = 0
  for key, native in pairs(env.natives or {}) do seen = seen + 1; Report(key, native, true) end
  local pooledShown = 0
  for key, pool in pairs(env.nativePool or {}) do
    for signature, native in pairs(pool) do
      if native ~= (env.natives or {})[key] then
        local okV, visible = Call(native.root, "IsVisible")
        local anyChain = false
        for _, chain in ipairs(native.chains or {}) do
          local level = chain.levels and chain.levels[1]
          if level and level.container and select(2, Call(level.container, "IsVisible")) == true then anyChain = true end
        end
        if (okV and visible) or anyChain or not okV then pooledShown = pooledShown + 1; Report(key, native, false) end
      end
    end
  end
  WeakAuras.prettyPrint(("Consumes check: %d current natives, %d pooled natives still visible or unreadable. A count anchored on a display other than its category's current one, or a pooled native still visible, is the lead; anything unreadable is unknown."):format(seen, pooledShown))
end
