-- Modified for ForeverAuras, 2026-10-07.
-- Modifications Copyright (C) 2026 ForeverAuras. Licensed under the GNU GPL v2 (see LICENSE).
if not WeakAuras.IsLibsOK() then return end
local _, Private = ...

local gcdStates = {}
local gcdStateSince = {}

-- isOnGCD is authoritative only while handling SPELL_UPDATE_COOLDOWN.
function Private.UpdateSpellCooldownGCD(spellID)
  local info = C_Spell.GetSpellCooldown(spellID)
  local wasOnGCD = gcdStates[spellID] == true
  gcdStates[spellID] = nil
  -- Only cache an explicit public flag; an unavailable/secret value is unknown.
  if info and not issecretvalue(info.isOnGCD) and type(info.isOnGCD) == "boolean" then
    gcdStates[spellID] = info.isOnGCD
  end
  if gcdStates[spellID] ~= true then
    gcdStateSince[spellID] = nil
  elseif not wasOnGCD then
    gcdStateSince[spellID] = GetTime()
  end
end

function Private.GetSpellCooldownGCDFlag(spellID)
  return gcdStates[spellID], gcdStateSince[spellID]
end

-- Prefer the fresh filtered timer; the event-scoped flag may be stale.
function Private.IsSpellCooldownGCD(spellID)
  local duration = C_Spell.GetSpellCooldownDuration(spellID, true)
  if duration then
    local zero = duration:IsZero()
    if not issecretvalue(zero) then return zero end
    return nil
  end
  return gcdStates[spellID]
end

function Private.ClearSpellCooldownGCD()
  wipe(gcdStates)
  wipe(gcdStateSince)
end

-- Clear known GCD-only displays with an owned zero duration; otherwise use Blizzard's timer.
local emptyCooldownDuration
function Private.GetSpellCooldownDurationWithoutGCD(spellID, onGCD)
  if onGCD == true then
    if not emptyCooldownDuration then
      emptyCooldownDuration = C_DurationUtil.CreateDuration()
    end
    return emptyCooldownDuration
  end
  return C_Spell.GetSpellCooldownDuration(spellID, true)
end

function Private.GetSpellCooldownData(spellID, track, showGCD, showLossOfControl, into)
  local info = C_Spell.GetSpellCooldown(spellID)
  local charges = C_Spell.GetSpellCharges(spellID)
  if not info and not charges then return end

  -- Keep the fresh filtered timer even if a cached GCD flag disagrees.
  local cooldown = C_Spell.GetSpellCooldownDuration(spellID, true)
  local zero
  if cooldown then
    local result = cooldown:IsZero()
    if not issecretvalue(result) then zero = result end
  end
  local onCooldown
  if info then
    if not info.isEnabled then
      onCooldown = true
    elseif not info.isActive then
      onCooldown = false
    elseif zero ~= nil then
      onCooldown = not zero
    end
  end

  -- Logical checks use public flags; desaturation follows the fresh timer.
  local conditionOnCooldown = onCooldown
  if onCooldown == nil and info and info.isActive and gcdStates[spellID] ~= nil then
    onCooldown = not gcdStates[spellID]
  end
  local result = into and wipe(into) or {}
  result.cooldown = cooldown
  result.conditionOnCooldown = conditionOnCooldown
  result.conditionDuration = cooldown
  result.gcdOnly = info and info.isActive and info.isEnabled and zero == true or false
  result.onCooldown = onCooldown
  result.paused = info and not info.isEnabled or false
  result.count = C_Spell.GetSpellCastCount(spellID)
  if onCooldown ~= nil then result.ready = not onCooldown end
  if charges then
    result.charges = charges.currentCharges
    result.maxCharges = charges.maxCharges
    result.recharging = charges.isActive
    result.chargeDuration = C_Spell.GetSpellChargeDuration(spellID)
  end

  -- Share the copied timer with desaturation without changing logical cooldown state.
  local held
  result.textDuration, held = Private.GetWandCooldownDuration(spellID, cooldown)
  result.wandAppearanceDuration = held and not result.paused and result.textDuration or nil
  local useCharges = track == "charges"
  if track ~= "cooldown" and track ~= "charges" and charges then
    local shortCooldown = info and not issecretvalue(info.duration) and info.duration <= 1.5
    -- An idle charge timer must not replace a requested GCD with an empty swipe.
    -- When timing is restricted, the public recharge flag can still select it.
    useCharges = charges.isActive == true and (conditionOnCooldown ~= true or shortCooldown or not info)
  end
  if useCharges then
    result.duration = result.chargeDuration
    result.conditionDuration = result.chargeDuration
    result.textDuration = result.chargeDuration
    result.wandAppearanceDuration = nil -- Recharge appearance keeps its own timer.
    result.gcdOnly = false
    result.onCooldown = charges and charges.isActive or false
    result.conditionOnCooldown = result.onCooldown
    result.paused = false
  else
    result.duration = showGCD and C_Spell.GetSpellCooldownDuration(spellID) or cooldown
  end
  if showLossOfControl then
    local lossOfControl = C_Spell.GetSpellLossOfControlCooldownInfo(spellID)
    if lossOfControl and lossOfControl.shouldReplaceNormalCooldown then
      result.duration = C_Spell.GetSpellLossOfControlCooldownDuration(spellID)
      result.conditionDuration = result.duration
      result.textDuration = result.duration
      result.wandAppearanceDuration = nil -- Loss of control takes precedence.
      result.gcdOnly = false
      result.onCooldown = lossOfControl.isActive
      result.conditionOnCooldown = result.onCooldown
      result.paused = false
    end
  end
  return result
end

Private.ExecEnv.GetSpellCooldownData = Private.GetSpellCooldownData

local customStateScratch = {}
function WeakAuras.SetSpellCooldownState(state, spellID, showGCD, showGCDText)
  local cooldown = Private.GetSpellCooldownData(spellID, nil, showGCD, nil, customStateScratch)
  local hideGCDText = not showGCDText
  state.changed = true
  state.progressType = "durationObject"
  state.expirationTime, state.duration, state.modRate = nil, nil, nil
  state.paused, state.remaining, state.value, state.total = nil, nil, nil, nil
  state.durationObject = cooldown and cooldown.duration
  state.onCooldown = cooldown and cooldown.onCooldown
  state.spellCooldownConditionDuration = cooldown and cooldown.conditionDuration
  state.spellCooldownConditionOnCooldown = cooldown and cooldown.conditionOnCooldown
  state.wandAppearanceDuration = cooldown and not cooldown.paused and cooldown.wandAppearanceDuration or nil
  state.cdmTextPreview = false
  state.cdmHideGCDText = hideGCDText
  state.cdmGCDOnly = cooldown and cooldown.gcdOnly or false
  state.cdmTextDurationRequired = hideGCDText
  state.cdmTextDurationObject = hideGCDText and cooldown and cooldown.textDuration or nil
  state.cdmNativePaused = cooldown and cooldown.paused or false
end

-- Copied durations keep their total span after expiry. Evaluate remaining time
-- directly into desaturation; nested condition endpoints may also be secret.
local wandAppearanceCurve
local function SelectWandDesaturation(state, needle, valueIfTrue, valueIfFalse)
  local duration = state.wandAppearanceDuration
  if not duration then return end
  if not wandAppearanceCurve then wandAppearanceCurve = C_CurveUtil.CreateCurve() end
  wandAppearanceCurve:SetToDefaults()
  local expired, active = valueIfFalse, valueIfTrue
  if needle ~= 1 then expired, active = valueIfTrue, valueIfFalse end
  wandAppearanceCurve:AddPoint(0, expired)
  wandAppearanceCurve:AddPoint(0.001, active)
  return duration:EvaluateRemainingDuration(wandAppearanceCurve), true
end

-- Use CDM's public condition result when no copied Shoot timer applies.
function Private.ExecEnv.SelectCDMCooldownDesaturation(state, needle, valueIfTrue, valueIfFalse, publicResult)
  if not state or not state.show then return valueIfFalse end
  local value, applied = SelectWandDesaturation(state, needle, valueIfTrue, valueIfFalse)
  if applied then return value end
  if publicResult then return valueIfTrue end
  return valueIfFalse
end

function Private.ExecEnv.SelectSpellCooldownDesaturation(state, needle, valueIfTrue, valueIfFalse, publicResult)
  if not state or not state.show then return valueIfFalse end
  local value, applied = SelectWandDesaturation(state, needle, valueIfTrue, valueIfFalse)
  if applied then return value end
  if state.progressType ~= "durationObject" then
    if publicResult then return valueIfTrue end
    return valueIfFalse
  end
  local duration = state.spellCooldownConditionDuration
  -- Use fresh timer metadata for appearance and public flags for logical checks.
  local onCooldown = state.spellCooldownConditionOnCooldown
  if onCooldown == nil and not duration then onCooldown = state.onCooldown end
  if onCooldown ~= nil then
    if onCooldown == (needle == 1) then return valueIfTrue end
    return valueIfFalse
  end
  if duration and duration.IsZero and C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
    if needle == 1 then
      return C_CurveUtil.EvaluateColorValueFromBoolean(duration:IsZero(), valueIfFalse, valueIfTrue)
    end
    return C_CurveUtil.EvaluateColorValueFromBoolean(duration:IsZero(), valueIfTrue, valueIfFalse)
  end
  return valueIfFalse
end

function Private.ValidateSpellCooldownSupport(data)
  local triggers = {}
  local comparisons, chargeIndex, progressTexture
  for index, entry in ipairs(data.triggers or {}) do
    local trigger = entry.trigger
    if trigger.type == "spell" and trigger.event == "Cooldown Progress (Spell)" then
      triggers[index] = true
      comparisons = comparisons or trigger.use_remaining or trigger.use_charges or trigger.use_spellCount
      chargeIndex = chargeIndex or trigger.use_trackcharge
      progressTexture = progressTexture or data.regionType == "progresstexture"
    end
  end
  local function CheckCondition(check)
    if not check then return end
    if triggers[check.trigger] and check.value ~= nil then
      local variable = check.variable
      comparisons = comparisons or variable == "expirationTime" or variable == "duration"
        or variable == "charges" or variable == "spellCount" or variable == "stacks"
        or variable == "readyTime" or variable == "chargeGainTime" or variable == "chargeLostTime"
    end
    for _, child in ipairs(check.checks or {}) do CheckCondition(child) end
  end
  for _, condition in ipairs(data.conditions or {}) do
    if not Private.TimerConditionHandled(data, condition) then CheckCondition(condition.check) end
  end

  local messages = {}
  if comparisons then
    table.insert(messages, "Cooldown time and charge-count comparisons cannot be evaluated while the client restricts their values. Timers can still be displayed, and On Cooldown uses the public cooldown status.")
  end
  if chargeIndex then
    table.insert(messages, "Tracking a specific numbered charge requires readable charge counts and is unavailable while cooldown values are restricted. Tracking the current recharge is supported.")
  end
  if progressTexture then
    table.insert(messages, "Progress textures cannot render restricted duration objects. Use an icon cooldown or progress bar for this trigger.")
  end
  if #messages > 0 then
    Private.AuraWarnings.UpdateWarning(data.uid, "restricted_cooldown_options", "warning", table.concat(messages, "\n"))
  else
    Private.AuraWarnings.UpdateWarning(data.uid, "restricted_cooldown_options")
  end
end
