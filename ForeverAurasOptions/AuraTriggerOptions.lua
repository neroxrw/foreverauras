if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local Editor = {}
OptionsPrivate.AuraEditor = Editor

local auraTypes = {
  HELPFUL = "Buff", HARMFUL = "Debuff", BOTH = "Buff or Debuff",
  Buff = "Blizzard: Buff", Debuff = "Blizzard: Debuff", Dispel = "Blizzard: Dispellable",
}
local classificationFilters = {Buff = "HELPFUL", Debuff = "HARMFUL", Dispel = "HARMFUL"}

function Editor.Mode(trigger)
  if trigger.auraTracking == "native" or trigger.auraTracking == "readable" then return trigger.auraTracking end
  return trigger.type == "secretAura" and "native" or "readable"
end

function Editor.Resolve(data, triggernum)
  local trigger = data.triggers[triggernum].trigger
  if trigger.type ~= "aura2" and trigger.type ~= "secretAura" then return end
  local mode = Editor.Mode(trigger)
  local native = mode == "native"
  local wanted = native and "secretAura" or "aura2"
  if wanted == trigger.type then return end
  if native then
    trigger.auraReadableSettings = {
      onlyMaw = trigger.onlyMaw, automaticWidth = data.automaticWidth, debuffType = trigger.debuffType,
    }
    if trigger.debuffType == "BOTH" then trigger.debuffType = "HELPFUL" end
    trigger.secretUseSpellIDs = trigger.useExactSpellId or false
    trigger.type = wanted
    OptionsPrivate.Private.BlizzardAuraDisplay.Migrate(data)
  else
    local previous = trigger.auraReadableSettings
    trigger.useExactSpellId = OptionsPrivate.Private.BlizzardAuraDisplay.UsesSpellIDs(trigger)
    if previous then
      trigger.onlyMaw = previous.onlyMaw
      data.automaticWidth = previous.automaticWidth
      if previous.debuffType == "BOTH" then trigger.debuffType = "BOTH" end
    end
    trigger.type = wanted
    trigger.auraReadableSettings = nil
  end
  OptionsPrivate.QueueOptionsRefresh(data.id)
end

function OptionsPrivate.SaveAuraTrigger(data, triggernum)
  Editor.Resolve(data, triggernum)
  ForeverAuras.Add(data)
end

function Editor.AddOptions(options, data, triggernum)
  local trigger = data.triggers[triggernum].trigger
  local native = trigger.type == "secretAura"
  local function Save() OptionsPrivate.SaveAuraTrigger(data, triggernum); OptionsPrivate.QueueOptionsRefresh(data.id) end
  if native then
    options.help.fontSize = "small"
  else
    options.auraCapabilities = {
      type = "description", order = 1.3, width = "full", fontSize = "small",
      name = "Legacy Auras rarely function in combat as most are Blizzard-controlled.",
    }
  end
  local auraType = options.debuffType
  auraType.values = native and {HELPFUL = "Buff", HARMFUL = "Debuff"} or {HELPFUL = "Buff", HARMFUL = "Debuff", BOTH = "Buff or Debuff"}
  auraType.sorting = native and {"HELPFUL", "HARMFUL"} or {"HELPFUL", "HARMFUL", "BOTH"}
  auraType.get = function() return trigger.debuffType end
  auraType.set = function(_, value)
    if not auraType.values[value] then return end
    trigger.processedAuraType = "any"
    trigger.debuffType = value
    if trigger.sortMethod == "UnitFrameDebuff" then trigger.sortMethod = "Default" end
    Save()
  end
  if native then
    options.show_settings_header = {type = "header", name = "Show and Clone Settings", order = 69.91}
    options.matchesShowOn = {type = "select", name = "Show On", order = 71, width = ForeverAuras.normalWidth,
      values = {native = "Controlled by Blizzard"}, get = function() return "native" end, disabled = true}
    options.showClones = {type = "toggle", name = "Auto-Clone (Show All Matches)", order = 72, width = "full",
      get = function() return trigger.showClones or false end, disabled = true}
    options.combineMode = {type = "select", name = "Preferred Match", order = 72.6, width = ForeverAuras.normalWidth,
      values = OptionsPrivate.Private.bufftrigger_2_preferred_match_types, get = function() return trigger.combineMode or "showLowest" end, disabled = true}
    options.nativeShowNotice = {type = "description", order = 73, width = "full", fontSize = "small",
      name = "You cannot control clones with an Aura (Blizzard). Use the Aura (Blizzard) Settings under Display."}
  end
end
