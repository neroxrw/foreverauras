-- Modified for ForeverAuras, 2026-09-19.
if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...

local function GetOptions(data, triggernum)
  local trigger = data.triggers[triggernum].trigger
  local display = OptionsPrivate.Private.BlizzardAuraDisplay
  local width = ForeverAuras.normalWidth
  local function Save(key, value)
    trigger[key] = value
    OptionsPrivate.SaveAuraTrigger(data, triggernum)
    OptionsPrivate.QueueOptionsRefresh(data.id)
  end
  local auraTypes = {
    HELPFUL = "Buff", HARMFUL = "Debuff",
    Buff = "Blizzard: Buff", Debuff = "Blizzard: Debuff",
    Dispel = "Blizzard: Dispellable",
  }
  local classificationFilters = {Buff = "HELPFUL", Debuff = "HARMFUL", Dispel = "HARMFUL"}
  local function SelectedAuraType()
    local classification = trigger.processedAuraType
    if not classification or classification == "any" then return trigger.debuffType end
    if classificationFilters[classification] ~= trigger.debuffType then
      return classification .. ":" .. trigger.debuffType
    end
    return classification
  end
  local function AuraTypeValues()
    local values = {}
    for key, title in pairs(auraTypes) do values[key] = title end
    -- Preserve older independently selected filter/classification combinations.
    local selected = SelectedAuraType()
    if not values[selected] then
      values[selected] = (auraTypes[trigger.processedAuraType] or trigger.processedAuraType) .. " (" .. (auraTypes[trigger.debuffType] or trigger.debuffType) .. " filter)"
    end
    return values
  end
  local options = {
    help = {type = "description", order = 2, width = "full", fontSize = "small",
      name = "Trigger Always Active. Blizzard Controls Display."},
    unitLabel = {
      type = "toggle", name = "Unit", order = 3, width = width,
      disabled = true, get = function() return true end,
    },
    unit = {
      type = "select", name = "Unit", order = 3.01, width = width, values = display.units,
      get = function() return trigger.unit end, set = function(_, value) Save("unit", value) end,
    },
    auraTypeLabel = {
      type = "toggle", name = "Aura Type", order = 4, width = width,
      disabled = true, get = function() return true end,
    },
    debuffType = {
      type = "select", name = "Aura Type", order = 4.01, width = width, values = AuraTypeValues,
      sorting = function()
        local order = {"HELPFUL", "HARMFUL", "Buff", "Debuff", "Dispel"}
        local selected = SelectedAuraType()
        if not auraTypes[selected] then order[#order + 1] = selected end
        return order
      end,
      desc = "Buff and Debuff use your filters. Blizzard Classification also applies Blizzard's unit-frame visibility and dispel rules, so some auras may be hidden.",
      get = SelectedAuraType,
      set = function(_, value)
        if not auraTypes[value] then return end
        local classification = classificationFilters[value] and value or "any"
        trigger.debuffType = classificationFilters[value] or value
        if trigger.sortMethod == "UnitFrameDebuff" and classification ~= "Debuff" and classification ~= "Dispel" then
          trigger.sortMethod = "Default"
        end
        Save("processedAuraType", classification)
      end,
    },
    useUnitNames = {
      type = "toggle", name = "Player Name(s)", order = 4.1, width = width,
      desc = "Only track these group members. This also limits which units can play configured aura sounds.",
      hidden = function() return trigger.unit ~= "group" and trigger.unit ~= "party" and trigger.unit ~= "raid" end,
      get = function() return trigger.useUnitNames or false end,
      set = function(_, value) Save("useUnitNames", value) end,
    },
    unitNames = {
      type = "input", name = "Player Names", order = 4.2, width = "full",
      desc = "Enter character names separated by commas. Include both the first name and surname, keeping the space between them. Capitalization does not matter. Only group members whose names are available to addons can match.",
      hidden = function() return not trigger.useUnitNames or (trigger.unit ~= "group" and trigger.unit ~= "party" and trigger.unit ~= "raid") end,
      get = function() return table.concat(trigger.unitNames or {}, ", ") end,
      set = function(_, value)
        local names = {}
        for name in value:gmatch("[^,]+") do
          name = strtrim(name)
          if name ~= "" then names[#names + 1] = name end
        end
        Save("unitNames", names)
      end,
    },
    useUnitRoles = {
      type = "toggle", name = "Group Role", order = 4.3, width = width,
      desc = "Only track members with the selected assigned group roles. This also limits configured aura sounds. Player-name and role filters must both match when enabled.",
      hidden = function() return trigger.unit ~= "group" and trigger.unit ~= "party" and trigger.unit ~= "raid" end,
      get = function() return trigger.useUnitRoles or false end,
      set = function(_, value) Save("useUnitRoles", value) end,
    },
    unitRoles = {
      type = "multiselect", name = "Group Roles", order = 4.4, width = "full",
      values = {TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage", NONE = "Unassigned"},
      desc = "Uses Blizzard's assigned group role. Members without a role assigned match Unassigned.",
      hidden = function() return not trigger.useUnitRoles or (trigger.unit ~= "group" and trigger.unit ~= "party" and trigger.unit ~= "raid") end,
      get = function(_, role) return (trigger.unitRoles or {})[role] or false end,
      set = function(_, role, value)
        trigger.unitRoles = trigger.unitRoles or {}
        trigger.unitRoles[role] = value or nil
        Save("unitRoles", trigger.unitRoles)
      end,
    },
    filtersHeader = {type = "header", name = "Aura Filters", order = 10},
    durationEnabled = {
      type = "toggle", name = "Limit total duration", order = 22, width = width,
      desc = "Filters total duration, not remaining time. Permanent auras are excluded when enabled.",
      get = function() return trigger.maxDuration ~= nil end,
      set = function(_, value) Save("maxDuration", value and 60 or nil) end,
    },
    maxDuration = {
      type = "range", name = "Maximum total duration (seconds)", order = 23, width = width,
      control = "ForeverAurasSpinBox", min = 0.1, softMax = 3600, step = 0.1,
      disabled = function() return trigger.maxDuration == nil end,
      get = function() return trigger.maxDuration or 60 end, set = function(_, value) Save("maxDuration", value) end,
    },
    includeNameplateOnly = {
      type = "toggle", name = "Include nameplate-only auras", order = 21, width = "full",
      desc = "Also allows auras normally returned only for nameplate displays. Other filters still apply.",
      get = function() return trigger.includeNameplateOnly or false end, set = function(_, value) Save("includeNameplateOnly", value) end,
      hidden = function() return trigger.unit ~= "nameplate" end,
    },

  }
  options.spellSelectionHeader = {type = "header", name = "Spell Selection Filters", order = 4.5}
  options.debuffSpellIDWarning = {
    type = "description", order = 4.9, width = "full", fontSize = "small",
    name = "|cffff0000Filtering Debuffs by spell ID will cause the Aura not display. Sounds can still be added in Actions.|r",
    hidden = function()
      return trigger.debuffType ~= "HARMFUL"
        or not (display.UsesSpellIDs(trigger) or display.UsesExcludedSpellIDs(trigger))
    end,
  }
  local function SpellIDs(toggleKey, prefix, storageKey, title, inputName, order, Enabled, flag)
    options[toggleKey] = {
      type = "toggle", name = title, order = order, width = width - 0.2,
      get = function() return Enabled(trigger) end,
      set = function(_, value) Save(flag, value) end,
    }
    options[prefix .. "DisabledSpace"] = {
      type = "description", name = "", order = order + 0.001, width = width + 0.2,
      hidden = function() return Enabled(trigger) end,
    }
    local size = #(trigger[storageKey] or {}) + 1
    OptionsPrivate.CreateAuraSpellOptions(options, data, triggernum, size,
      true, false, prefix, order, flag, storageKey, inputName,
      nil,
      false, function() return Enabled(trigger) end)
    -- Unlike Legacy, these values are also sent to Blizzard's native filters.
    for i = 1, size do
      options[prefix .. i].validate = function(_, value)
        if value == "" then return true end
        local id = tonumber(value)
        if not id or id <= 0 or id >= 2147483647 or id ~= math.floor(id) then
          return "Enter a positive whole-number Spell ID."
        end
        return true
      end
    end
  end
  SpellIDs("useSpellIDs", "spellid", "auraspellids", "Exact Spell ID(s)", "Spell ID", 5,
    display.UsesSpellIDs, "secretUseSpellIDs")
  SpellIDs("useExcludedSpellIDs", "ignorespellid", "excludedAuraSpellIDs", "Ignored Exact Spell ID(s)", "Ignored Spell ID", 7,
    display.UsesExcludedSpellIDs, "secretUseExcludedSpellIDs")
  local function TriState(key, title, order, description, GetValue, SetValue)
    options[key] = {
      type = "toggle", width = "full", order = order,
      name = function()
        local value = GetValue()
        if value == nil then return title end
        return value and "|cFF00FF00" .. title .. "|r" or "|cFFFF0000Not " .. title .. "|r"
      end,
      desc = description,
      get = function()
        local value = GetValue()
        if value == nil then return false end
        return value and "true" or "false"
      end,
      set = function(_, checked)
        if checked then SetValue(true)
        elseif GetValue() == false then SetValue(nil)
        else SetValue(false) end
      end,
    }
  end
  for index, field in ipairs(display.booleanFilters) do
    local key = field[1]
    local title = field[2]
    TriState(key, title, 10 + index,
      field[3],
      function() return trigger[key] end, function(value) Save(key, value) end)
    if key == "nameplateShowAll" or key == "nameplateShowPersonal" then
      options[key].hidden = function() return trigger.unit ~= "nameplate" end
      options[key].desc = (key == "nameplateShowAll"
        and "Only match auras Blizzard marks for display on all nameplates."
        or "Only match auras marked for Blizzard's personal-debuff display on nameplates. This does not refer to your personal resource bar.")
        .. " This checks Blizzard's nameplate flag. It does not change where the icon appears or who cast the aura."
    end
  end
  for index, key in ipairs({"includeDispelTypes", "excludeDispelTypes"}) do
    options[key] = {
      type = "multiselect", name = index == 1 and "Include dispel types" or "Exclude dispel types", order = 23 + index, width = "full",
      values = display.dispelTypes,
      desc = "Select nothing to disable this filter. Include requires one of the selected types; exclude removes those types. Exclusions take precedence. This checks the category, not your dispel abilities.",
      get = function(_, name) return trigger[key] and trigger[key][name] or false end,
      set = function(_, name, value)
        local values = {}
        for k, v in pairs(trigger[key] or {}) do values[k] = v end
        values[name] = value and true or nil
        Save(key, next(values) and values or nil)
      end,
    }
  end
  for index, field in ipairs(display.processingOptions) do
    local key = field[1]
    options[key] = {
      type = "toggle", name = field[2], order = 25 + index, width = width,
      disabled = function() return not trigger.processedAuraType or trigger.processedAuraType == "any" end,
      desc = key == "displayOnlyDispellableDebuffs"
        and "Changes Blizzard's unit-frame classification paths; priority and boss exceptions may still apply. To show only dispellable auras, use the dispel filters under Aura Filters."
        or "Controls Blizzard's classification pass. Ignoring the selected classification can hide all matching auras.",
      get = function() return trigger[key] or false end, set = function(_, value) Save(key, value) end,
    }
  end
  for index, field in ipairs(display.nativeFilters) do
    local key = field[1]
    TriState("native" .. key, field[2], 20 + index / 20, field[3],
      function() return (trigger.nativeFilters or {})[key] end,
      function(value)
        local filters = {}
        for k, v in pairs(trigger.nativeFilters or {}) do filters[k] = v end
        filters[key] = value
        Save("nativeFilters", next(filters) and filters or nil)
      end)
  end
  options.isFromPlayerOrPlayerPet.width = width
  options.nativePLAYER.width = width
  options.nativePLAYER.order = options.isFromPlayerOrPlayerPet.order + 0.01
  for _, field in ipairs(display.processingOptions) do options[field[1]] = nil end
  for _, fields in ipairs({display.nativeFilters, display.booleanFilters}) do
    for _, field in ipairs(fields) do
      local key = field[1]
      local option = options[fields == display.nativeFilters and "native" .. key or key]
      if option then
        local hidden = option.hidden
        option.hidden = function()
          return not display.FilterApplies(key, trigger) or (type(hidden) == "function" and hidden()) or hidden == true
        end
      end
    end
  end
  OptionsPrivate.commonOptions.AddCommonTriggerOptions(options, data, triggernum, true)
  OptionsPrivate.AuraEditor.AddOptions(options, data, triggernum)
  OptionsPrivate.AddTriggerMetaFunctions(options, data, triggernum)
  return {["trigger." .. triggernum .. ".secretAura"] = options}
end

ForeverAuras.RegisterTriggerSystemOptions({"secretAura"}, GetOptions)
