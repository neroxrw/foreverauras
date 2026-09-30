-- Modified for ForeverAuras, 2026-09-30.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay
local Trigger = {}
local displays = {}
local loaded = {}

function Trigger.Add(data)
  Display.MigrateNativeConditions(data)
  displays[data.id] = nil
  for _, entry in ipairs(data.triggers) do
    if entry.trigger.type == "secretAura" then displays[data.id] = data; break end
  end
end

-- Units that may not exist. As with Aura (Legacy), the trigger is inactive
-- while such a unit does not exist, unless Show If Unit Does Not Exist
-- (trigger.unitExists, the Legacy field) is ticked. Whether a unit exists is
-- public; whether it has the aura is not, so this is the only case in which
-- the trigger goes inactive. Mouseover has no event when it clears, so it
-- stays active, as before.
local optionalUnits = {target = true, focus = true, pet = true, targettarget = true, focustarget = true}
local function UnitMissing(trigger)
  if type(trigger) ~= "table" or not optionalUnits[trigger.unit] or trigger.unitExists then return false end
  return not Display.SingleUnitExists(trigger)
end

-- Whether this Aura (Modern) trigger is active. The editor always shows its
-- samples, so there the unit does not matter.
local function IsActive(data, triggernum)
  if not (not Display.Enabled(data) or Display.Validate(data) == nil) then return false end
  local entry = data.triggers[triggernum]
  return ForeverAuras.IsOptionsOpen() or not UnitMissing(entry and entry.trigger)
end

-- Also the framework's fallback state when this trigger supplies a shown
-- display's information; that one is always shown.
function Trigger.CreateFallbackState(data, triggernum, state)
  state.show = not Display.Enabled(data) or Display.Validate(data) == nil
  state.changed = true
  state.progressType = "static"
  state.value, state.total = 1, 1
  state.name, state.icon = Trigger.GetNameAndIcon(data, triggernum)
  state.unit = ForeverAuras.IsOptionsOpen() and Display.GetPreviewUnit(data) or nil
  if ForeverAuras.IsOptionsOpen() then
    state.progressType = "timed"
    -- Standard sample duration, independent of active aura timers.
    state.duration, state.expirationTime = 6, GetTime() + 6
    state.stacks = 3
  end
end

function Trigger.CreateFakeStates(id, triggernum)
  local states = ForeverAuras.GetTriggerStateForTrigger(id, triggernum)
  wipe(states)
  states[""] = {}
  local data = ForeverAuras.GetData(id)
  Trigger.CreateFallbackState(data, triggernum, states[""])
  -- The trigger's own state follows its unit (IsActive).
  states[""].show = IsActive(data, triggernum)
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

-- Unit changes that can make a unit appear or disappear, and the units they
-- affect (UNIT_TARGET and UNIT_PET are keyed by the unit that changed).
local unitChangeEvents = {
  PLAYER_TARGET_CHANGED = {target = true, targettarget = true},
  PLAYER_FOCUS_CHANGED = {focus = true, focustarget = true},
  UNIT_TARGET = {target = {targettarget = true}, focus = {focustarget = true}},
  UNIT_PET = {player = {pet = true}},
  PLAYER_ENTERING_WORLD = {target = true, focus = true, pet = true, targettarget = true, focustarget = true},
}
local unitFrame = CreateFrame("Frame")
for event in pairs(unitChangeEvents) do unitFrame:RegisterEvent(event) end
unitFrame:SetScript("OnEvent", function(_, event, unit)
  -- The editor keeps its sample states until it closes.
  if ForeverAuras.IsOptionsOpen() then return end
  local affected = unitChangeEvents[event]
  if event == "UNIT_TARGET" or event == "UNIT_PET" then affected = unit and affected[unit] end
  if not affected then return end
  for id in pairs(loaded) do
    local data = displays[id]
    local changed = false
    for index, entry in ipairs(data and data.triggers or {}) do
      if entry.trigger.type == "secretAura" and affected[entry.trigger.unit] then
        local state = ForeverAuras.GetTriggerStateForTrigger(id, index)[""]
        local show = IsActive(data, index)
        if state and state.show ~= show then
          state.show, state.changed = show, true
          changed = true
        end
      end
    end
    if changed then Private.UpdatedTriggerState(id) end
  end
end)

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
function Trigger.GetName() return "Aura (Modern)" end
function Trigger.CanHaveTooltip() return false end
function Trigger.SetToolTip() return false end
function Trigger.GetOverlayInfo() return {} end
function Trigger.GetAdditionalProperties() return {} end
function Trigger.GetProgressSources(data, triggernum, values)
  table.insert(values, {trigger = triggernum, property = "value", type = "number", display = "Aura (Modern)", total = "total"})
end
function Trigger.GetTriggerConditions() return {} end

function Trigger.GetNameAndIcon(data, triggernum)
  local trigger = data.triggers[triggernum].trigger
  -- Preview metadata follows the configured selections, without expanding ranks.
  local id = Display.GetSpellIDs(trigger, false)[1]
  local info = id and C_Spell.GetSpellInfo(id)
  return info and info.name or "Secret Auras", info and info.iconID or 134400
end

-- The hover summary uses unwrapped double-column rows. Bound each ID list here
-- so large selections cannot stretch it off-screen; the editor retains the full list.
local function SpellIDSummary(ids, enabled)
  if not enabled or not ids or #ids == 0 then return "None" end
  local shown = {}
  for index = 1, math.min(#ids, 3) do
    shown[#shown + 1] = tostring(ids[index])
  end
  local summary = table.concat(shown, ", ")
  if #ids > #shown then
    summary = summary .. " (+" .. (#ids - #shown) .. " more)"
  end
  return summary
end

function Trigger.GetTriggerDescription(data, triggernum, lines)
  local trigger = data.triggers[triggernum].trigger
  lines[#lines + 1] = {"Secret Auras", Display.units[trigger.unit] or trigger.unit}
  -- What makes the display appear.
  local showOn = Display.showOnValues[Display.ShowOn(trigger)]
  local op, seconds = Display.RemainingWindow(trigger)
  if op then showOn = showOn .. ", remaining " .. op .. " " .. seconds .. " s" end
  lines[#lines + 1] = {"Show On", showOn}
  -- Describe both modes without relabelling existing exact selections.
  lines[#lines + 1] = {"Spell IDs (All Ranks)", SpellIDSummary(trigger.auraRankSpellIDs, Display.UsesRankSpellIDs(trigger))}
  lines[#lines + 1] = {"Exact Spell IDs", SpellIDSummary(trigger.auraspellids, Display.UsesSpellIDs(trigger))}
end

ForeverAuras.RegisterTriggerSystem({"secretAura"}, Trigger)
