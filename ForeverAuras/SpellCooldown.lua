-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

local gcdStates = {}

-- isOnGCD is authoritative only while handling SPELL_UPDATE_COOLDOWN.
function Private.UpdateSpellCooldownGCD(spellID)
  local info = C_Spell.GetSpellCooldown(spellID)
  gcdStates[spellID] = nil
  if info then
    gcdStates[spellID] = info.isOnGCD == true
  end
end

function Private.ClearSpellCooldownGCD()
  wipe(gcdStates)
end

function Private.GetSpellCooldownData(spellID, track, showGCD, showLossOfControl)
  local info = C_Spell.GetSpellCooldown(spellID)
  local charges = C_Spell.GetSpellCharges(spellID)
  if not info and not charges then return end

  local cooldown = C_Spell.GetSpellCooldownDuration(spellID, true)
  local onCooldown
  if info then
    if not info.isEnabled then
      onCooldown = true
    elseif not info.isActive then
      onCooldown = false
    elseif cooldown then
      local zero = cooldown:IsZero()
      if not issecretvalue(zero) then
        onCooldown = not zero
      elseif gcdStates[spellID] ~= nil then
        onCooldown = not gcdStates[spellID]
      end
    end
  end

  local result = {
    cooldown = cooldown,
    onCooldown = onCooldown,
    paused = info and not info.isEnabled or false,
    count = C_Spell.GetSpellCastCount(spellID),
  }
  if onCooldown ~= nil then result.ready = not onCooldown end
  if charges then
    result.charges = charges.currentCharges
    result.maxCharges = charges.maxCharges
    result.recharging = charges.isActive
    result.chargeDuration = C_Spell.GetSpellChargeDuration(spellID)
  end

  local useCharges = track == "charges"
  if track ~= "cooldown" and track ~= "charges" and charges then
    local shortCooldown = info and not issecretvalue(info.duration) and info.duration <= 1.5
    useCharges = onCooldown == false or shortCooldown or not info
  end
  if useCharges then
    result.duration = result.chargeDuration
    result.onCooldown = charges and charges.isActive or false
    result.paused = false
  else
    result.duration = showGCD and C_Spell.GetSpellCooldownDuration(spellID) or cooldown
  end
  if showLossOfControl then
    local lossOfControl = C_Spell.GetSpellLossOfControlCooldownInfo(spellID)
    if lossOfControl and lossOfControl.shouldReplaceNormalCooldown then
      result.duration = C_Spell.GetSpellLossOfControlCooldownDuration(spellID)
      result.onCooldown = lossOfControl.isActive
      result.paused = false
    end
  end
  return result
end

Private.ExecEnv.GetSpellCooldownData = Private.GetSpellCooldownData

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
  for _, condition in ipairs(data.conditions or {}) do CheckCondition(condition.check) end

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
