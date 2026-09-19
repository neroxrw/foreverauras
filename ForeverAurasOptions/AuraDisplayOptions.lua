-- Native aura layout and events; appearance is configured by the shared Display editor.
if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...

local pendingRefresh

function OptionsPrivate.QueueOptionsRefresh(id)
  if not pendingRefresh then
    pendingRefresh = {}
    -- AceConfig still owns the clicked widget until its setter returns.
    C_Timer.After(0, function()
      local requests = pendingRefresh
      pendingRefresh = nil
      for auraId in pairs(requests) do
        ForeverAuras.ClearAndUpdateOptions(auraId)
      end
      -- Registering new options does not redraw the panel after AceConfig's
      -- click handler has finished. Refill once, keeping the selected tab.
      ForeverAuras.FillOptions()
    end)
  end
  pendingRefresh[id] = true
end

function OptionsPrivate.GetSecretAuraSettings(data)
  local Display = OptionsPrivate.Private.BlizzardAuraDisplay
  local function Settings() return data.blizzardAuraDisplay or {} end
  local function Save(key, value)
    data.blizzardAuraDisplay = data.blizzardAuraDisplay or {}
    data.blizzardAuraDisplay[key] = value
    ForeverAuras.Add(data)
    OptionsPrivate.QueueOptionsRefresh(data.id)
  end
  local function Disabled() return not Display.Enabled(data) end
  local args = {__title = "Secret Aura Settings", __order = 8, __collapsed = true}
  args.sortMethod = {
    type = "select", name = "Sort by", disabled = Disabled, values = Display.sortMethods,
    sorting = {"Default", "ExpirationOnly", "Expiration", "NameOnly", "Name", "ImportantOnly", "BigDefensive", "UnitFrameDebuff", "AuraInstanceIDOnly"},
    desc = "Sort each unit's auras. Remaining time puts the soonest-expiring aura first, with permanent auras last. Blizzard priority applies caster and priority rules before time or name. Unit-frame debuffs also enables debuff classification, which can hide auras.",
    get = function() local trigger = Display.GetTrigger(data); return trigger and trigger.sortMethod or "Default" end,
    set = function(_, value)
      local trigger = Display.GetTrigger(data)
      if not trigger then return end
      if value == "UnitFrameDebuff" and trigger.processedAuraType ~= "Debuff" and trigger.processedAuraType ~= "Dispel" then
        trigger.processedAuraType = "Debuff"
      end
      trigger.sortMethod = value
      ForeverAuras.Add(data)
      OptionsPrivate.QueueOptionsRefresh(data.id)
    end,
  }
  args.sortReverse = {
    type = "toggle", name = "Reverse Sort", disabled = Disabled,
    desc = "Reverse the selected order. For Remaining time, later expirations and permanent auras come first.",
    get = function() local trigger = Display.GetTrigger(data); return trigger and trigger.sortReverse or false end,
    set = function(_, value)
      local trigger = Display.GetTrigger(data)
      if not trigger then return end
      trigger.sortReverse = value
      ForeverAuras.Add(data)
      OptionsPrivate.QueueOptionsRefresh(data.id)
    end,
  }
  for _, axis in ipairs({"X", "Y"}) do
    local key = "nameplate" .. axis
    args[key] = {
      type = "range", name = axis == "X" and "Nameplate X offset" or "Nameplate Y offset", min = -200, max = 200, step = 1, disabled = Disabled,
      hidden = function() return data.anchorFrameType == "UNITFRAME" or not Display.UsesNameplates(data) end,
      get = function() return Settings()[key] or (axis == "X" and 0 or 8) end,
      set = function(_, value) Save(key, value) end,
    }
  end
  args.growth = {
    type = "select", name = "Icon growth direction", order = 3.1, disabled = Disabled,
    values = {RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down"},
    get = function() return Settings().growth or "RIGHT" end,
    set = function(_, value) Save("growth", value) end,
  }
  args.spacing = {
    type = "range", name = "Icon spacing", order = 3.2, min = 0, max = 40, step = 1, disabled = Disabled,
    get = function() return Settings().spacing or 6 end,
    set = function(_, value) Save("spacing", value) end,
  }
  args.maxIcons = {
    type = "range", name = "Maximum icons", order = 3.3, min = 1, softMax = 40, step = 1, disabled = Disabled,
    desc = "Maximum auras per unit. Drag up to 40, or type a larger number.",
    get = function() return Settings().maxIcons or 10 end,
    set = function(_, value) Save("maxIcons", value) end,
  }

  args.growth.name = "Aura growth direction"
  args.spacing.name = "Aura spacing"
  args.maxIcons.name = "Maximum auras"
  args.textHeight = {type = "range", name = "Text Area Height", min = 4, softMax = 300, step = 1,
    hidden = function() return data.regionType ~= "text" end,
    desc = "Space reserved for each aura's text. Set its width in Font Flags.",
    get = function() return Settings().textHeight or (data.fontSize or 18) * 1.2 end,
    set = function(_, value) Save("textHeight", value) end}
  args.swipeColor = {type = "color", name = "Swipe Color", hasAlpha = true, hidden = function() return data.regionType ~= "icon" end,
    get = function() return unpack(Settings().swipeColor or {0, 0, 0, 0.8}) end,
    set = function(_, red, green, blue, alpha) Save("swipeColor", {red, green, blue, alpha}) end}
  args.status = {type = "description", width = "full", name = function() return Display.Validate(data) or "" end,
    hidden = function() return Display.Validate(data) == nil end}
  local order = {"status", "growth", "spacing", "maxIcons", "sortMethod", "sortReverse", "nameplateX", "nameplateY", "textHeight", "swipeColor"}
  for index, key in ipairs(order) do
    args[key].order = index
    args[key].width = args[key].width or ForeverAuras.normalWidth
  end
  return args
end

-- Keep the standard editor and its getters/setters; restrict only unsupported native features.
function OptionsPrivate.PrepareSecretDisplayOptions(data, groups)
  local Display = OptionsPrivate.Private.BlizzardAuraDisplay
  if not Display.HasTrigger(data) then return end
  groups.secretAura = OptionsPrivate.GetSecretAuraSettings(data)
  groups.progressOptions = nil
  local unsupported = {
    useTooltip = true, toolTipArea = true, useCooldownModRate = true, iconInset = true, keepAspectRatio = true,
    texXOffset = true, texYOffset = true, useMasque = true, smoothProgress = true, enableGradient = true, gradientOrientation = true, barColor2 = true,
    spark = true, sparkTexture = true, sparkChooseTexture = true, sparkDesaturate = true, sparkColor = true, sparkBlendMode = true,
    sparkWidth = true, sparkHeight = true, sparkOffsetX = true, sparkOffsetY = true, sparkRotationMode = true, sparkRotation = true,
    sparkMirror = true, sparkHidden = true, customTextUpdate = true, text_customTextUpdate = true, text_customTextUpdateThrottle = true,
    text_smoothScaling = true, smoothScaling = true, rotateText = true, glowStartAnim = true, glowLines = true, glowFrequency = true,
    glowLength = true, glowThickness = true, glowBorder = true,
  }
  local timeFields = {p_format = true, p_time_format = true, p_time_precision = true, p_time_dynamic_threshold = true, p_time_legacy_floor = true}
  for groupKey, group in pairs(groups) do
    local index = tonumber(groupKey:match("^sub%.(%d+)%."))
    local detached = index and Display.IsDetachedElement(data, data.subRegions and data.subRegions[index])
    if detached then
      group.__title = "Detached " .. group.__title
      if group.text_text then group.text_text.desc = "Hardcoded text. Use Conditions from other triggers to show, hide or change this message." end
      if group.text_text_pChoose then group.text_text_pChoose.disabled = true end
    end
    if groupKey:match("%.subborder$") then group.__duplicate = nil end
    if not detached and groupKey ~= "secretAura" and groupKey ~= "position" then
      for key, option in pairs(group) do
        if type(option) == "table" and option.type then
          if groupKey:match("%.subborder$") and key == "border_ppscale" then
            option.disabled = true
            option.desc = "Secret aura borders use the size set in Display; pixel-perfect scaling is unavailable."
          elseif unsupported[key] then
            option.disabled = true
            option.desc = "Not supported by Blizzard's native aura display."
          elseif key == "iconSource" then
            option.values = {[-1] = "Automatic", [0] = "Manual"}
          elseif key == "automaticWidth" then
            option.values = {Fixed = "Fixed"}
            option.desc = "Native aura layout uses a fixed text area."
          elseif key == "glowType" then
            option.values = {Proc = "Proc Glow", buttonOverlay = "Pulse Glow"}
          elseif key == "anchor_area" then
            option.values = data.regionType == "aurabar" and {ALL = "Whole Area", bar = "Bar", icon = "Icon"} or {ALL = "Whole Area"}
          elseif key == "anchor_point" and type(option.values) == "table" then
            local points = {}
            for point, title in pairs(option.values) do
              if not point:find("%.") and (point:match("^[A-Z_]+$")) then points[point] = title end
            end
            option.values = points
          elseif key == "text_text" or key == "displayText" then
            option.desc = "Use %p for duration, %s for stacks or %n for the aura name. Each code needs its own text element. Literal text is also supported."
          end
          local formatKey = key:match("^text_text_format_(.+)$") or key:match("^displayText_format_(.+)$")
          if formatKey and not timeFields[formatKey] and not formatKey:match("^footer") then
            if option.type ~= "execute" and option.type ~= "description" then option.disabled = true; option.desc = "Not supported by native aura text." end
          elseif formatKey == "p_format" then
            option.values = {timed = "Time Format"}
          elseif formatKey == "p_time_format" then
            option.values = {[-1] = "Blizzard Default", [0] = "Minutes and seconds", [-2] = "Seconds"}
          end
        end
      end
    end
  end
end

function OptionsPrivate.PrepareSecretActionOptions(data, action)
  local Display = OptionsPrivate.Private.BlizzardAuraDisplay
  if not Display.HasTrigger(data) then return end
  local supported = {header = true, do_sound = true, sound = true, sound_channel = true, sound_path = true, hide_all_glows = true}
  for key, option in pairs(action.args) do
    local when, field = key:match("^(%a+)_(.+)$")
    if (when == "start" or when == "finish") and option.type ~= "header" then
      if not supported[field] then
        -- Leave active toggles usable so imported settings can be switched off.
        option.disabled = function() return option.type ~= "toggle" or not (data.actions[when] or {})[field] end
        option.desc = "Not available for secret aura On Show/On Hide. Sound files are supported; live TTS and custom callbacks are not."
      elseif field == "sound" then
        local values = {}
        for value, title in pairs(OptionsPrivate.Private.sound_types) do
          if value ~= " KitID" then values[value] = title end
        end
        values[" Fojji"] = "FojjiCore recorded voice"
        option.values = values
        option.sorting = OptionsPrivate.Private.SortOrderForValues(values)
      end
    end
  end
  for _, when in ipairs({"start", "finish"}) do
    local title = when == "start" and "added" or "removed"
    action.args[when .. "_do_sound"].desc = "Play when one of the trigger's exact spell IDs is " .. title .. ". Works even if Blizzard cannot display the aura. Uses the selected unit and exact spell IDs, excluding ignored IDs; other display filters do not affect sounds."
    local soundOrder = action.args[when .. "_sound"].order
    action.args[when .. "_sound_fojji"] = {
      type = "input", name = "Recorded phrase", width = "full", order = soundOrder + 0.01,
      hidden = function() return data.actions[when].sound ~= " Fojji" end,
      disabled = function() return not data.actions[when].do_sound end,
      desc = "Exact phrase in your selected FojjiCore recorded voice pack. Live TTS is not supported."
    }
  end
  -- Reuse the native unit-glow settings, never the Lua On Show glow action.
  local settings = data.blizzardAuraDisplay
  local function SaveGlow(key, value)
    settings[key] = value
    ForeverAuras.Add(data)
    OptionsPrivate.QueueOptionsRefresh(data.id)
  end
  for key, option in pairs(action.args) do
    if key:match("^start_glow_") or key == "start_choose_glow_frame" or key == "start_use_glow_color" then
      option.hidden = true
    end
  end
  local showGlow = action.args.start_do_glow
  showGlow.name = "Glow Anchored Unit Frame"
  showGlow.desc = "Use Unit Frames anchoring in Display. The frame glows while any aura matches your filters and stops automatically. Exact Spell IDs are not required."
  showGlow.disabled = function() return data.anchorFrameType ~= "UNITFRAME" and not data.actions.start.do_glow end
  showGlow.get = function() return settings.unitGlow or data.actions.start.do_glow or false end
  showGlow.set = function(_, value)
    data.actions.start.do_glow = nil
    SaveGlow("unitGlow", value)
  end
  local fields = {
    glow_type = {"unitGlowType", "proc"}, use_glow_color = {"unitUseGlowColor", true},
    glow_color = {"unitGlowColor", {1, 0.82, 0, 1}}, glow_duration = {"unitGlowDuration", 1},
    glow_XOffset = {"unitGlowX", 0}, glow_YOffset = {"unitGlowY", 0},
  }
  for field, mapping in pairs(fields) do
    local option = action.args["start_" .. field]
    local key, default = mapping[1], mapping[2]
    option.hidden = function() return data.anchorFrameType ~= "UNITFRAME" or not settings.unitGlow end
    option.disabled = function() return not settings.unitGlow or (field == "glow_color" and settings.unitUseGlowColor == false) end
    option.desc = "Style the glow on the anchored unit frame."
    option.get = function()
      local value = settings[key]
      if value == nil then value = default end
      if field == "glow_color" then return unpack(value) end
      if field == "glow_type" then return value == "pulse" and "buttonOverlay" or "Proc" end
      return value
    end
    option.set = function(_, value, green, blue, alpha)
      if field == "glow_color" then value = {value, green, blue, alpha}
      elseif field == "glow_type" then value = value == "buttonOverlay" and "pulse" or "proc" end
      SaveGlow(key, value)
    end
  end
  action.args.start_glow_type.values = {Proc = "Proc Glow", buttonOverlay = "Pulse Glow"}
  action.args.start_glow_duration.name = "Animation Duration"
  action.args.start_glow_padding = {
    type = "range", control = "ForeverAurasSpinBox", name = "Padding", order = 10.865,
    min = 0, max = 40, step = 1, width = ForeverAuras.normalWidth,
    desc = "Extra space around the unit frame. Zero follows its edges.",
    hidden = function() return data.anchorFrameType ~= "UNITFRAME" or not settings.unitGlow end,
    disabled = function() return not settings.unitGlow end,
    get = function() return settings.unitGlowPadding or 0 end,
    set = function(_, value) SaveGlow("unitGlowPadding", value) end,
  }
  action.args.secretSoundNotice = {type = "description", order = 0, width = "full",
    name = "|cffff2020Secret Aura Trigger Detected: Limited options.|r"}
end
