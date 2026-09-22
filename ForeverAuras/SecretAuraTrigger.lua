-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay
local Trigger = {}
local displays = {}
local loaded = {}

function Trigger.Add(data)
  displays[data.id] = nil
  for _, entry in ipairs(data.triggers) do
    if entry.trigger.type == "secretAura" then displays[data.id] = data; break end
  end
end

function Trigger.CreateFallbackState(data, triggernum, state)
  state.show = not Display.Enabled(data) or Display.Validate(data) == nil
  state.changed = true
  state.progressType = "static"
  state.value, state.total = 1, 1
  state.name, state.icon = Trigger.GetNameAndIcon(data, triggernum)
  state.unit = ForeverAuras.IsOptionsOpen() and Display.GetPreviewUnit(data) or nil
  if ForeverAuras.IsOptionsOpen() then
    state.progressType = "timed"
    state.duration, state.expirationTime = 30, GetTime() + 30
    state.stacks = 3
  end
end

function Trigger.CreateFakeStates(id, triggernum)
  local states = ForeverAuras.GetTriggerStateForTrigger(id, triggernum)
  wipe(states)
  states[""] = {}
  Trigger.CreateFallbackState(ForeverAuras.GetData(id), triggernum, states[""])
end

function Trigger.LoadDisplays(toLoad)
  for id in pairs(toLoad) do
    local data = displays[id]
    if data then
      loaded[id] = true
      if Private.regions[id] then Display.Activate(Private.regions[id].region, data) end
      for index, entry in ipairs(data.triggers) do
        if entry.trigger.type == "secretAura" then Trigger.CreateFakeStates(id, index) end
      end
      Private.UpdatedTriggerState(id)
    end
  end
end

function Trigger.UnloadDisplays(toUnload)
  for id in pairs(toUnload) do
    loaded[id] = nil
    if displays[id] and Private.regions[id] then Display.Release(Private.regions[id].region) end
  end
end

function Trigger.UnloadAll()
  Trigger.UnloadDisplays(loaded)
end

function Trigger.Delete(id)
  Trigger.UnloadDisplays({[id] = true})
  displays[id] = nil
end

function Trigger.Rename(oldid, newid)
  displays[newid], loaded[newid] = displays[oldid], loaded[oldid]
  displays[oldid], loaded[oldid] = nil, nil
end

function Trigger.FinishLoadUnload() end
function Trigger.GetName() return "Blizzard Aura" end
function Trigger.CanHaveTooltip() return false end
function Trigger.SetToolTip() return false end
function Trigger.GetOverlayInfo() return {} end
function Trigger.GetAdditionalProperties() return {} end
function Trigger.GetProgressSources(data, triggernum, values)
  table.insert(values, {trigger = triggernum, property = "value", type = "number", display = "Blizzard Aura", total = "total"})
end
function Trigger.GetTriggerConditions() return {} end

function Trigger.GetNameAndIcon(data, triggernum)
  local trigger = data.triggers[triggernum].trigger
  local id = tonumber(trigger.auraspellids and trigger.auraspellids[1])
  local info = id and C_Spell.GetSpellInfo(id)
  return info and info.name or "Secret Auras", info and info.iconID or 134400
end

function Trigger.GetTriggerDescription(data, triggernum, lines)
  local trigger = data.triggers[triggernum].trigger
  lines[#lines + 1] = {"Secret Auras", Display.units[trigger.unit] or trigger.unit}
  lines[#lines + 1] = {"Spell IDs", Display.UsesSpellIDs(trigger) and table.concat(trigger.auraspellids or {}, ", ") or "Any"}
end

ForeverAuras.RegisterTriggerSystem({"secretAura"}, Trigger)
