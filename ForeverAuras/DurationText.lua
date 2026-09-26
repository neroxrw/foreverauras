-- Modified for ForeverAuras, 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

local formatters = {}

-- The public GCD-only state is a text policy, not a duration to format. In
-- particular, a temporarily missing filtered timer must never expose the swipe
-- through GetTextDuration's fallback. Charge selection clears cdmGCDOnly.
function Private.ShouldHideDurationText(state)
  return state and state.cdmHideGCDText == true and not state.cdmTextPreview
    and (state.cdmGCDOnly == true
      or (state.cdmTextDurationRequired and not state.cdmTextDurationObject))
end

-- CDM can show a GCD swipe while its text uses only the spell/recharge timer.
-- Keep this choice independent of whether IsZero() is readable in combat.
function Private.GetTextDuration(state)
  return state.cdmTextDurationObject or state.durationObject
end

-- A regular spell can retain readable timed progress while rendering text from
-- a separate GCD-free duration. Preview text continues to use its sample state.
function Private.UsesDurationText(state)
  if not state then return false end
  if state.cdmHideGCDText and not state.cdmTextPreview then
    return ForeverAuras.IsDurationObject(state.cdmTextDurationObject)
  end
  return state.progressType == "durationObject" and ForeverAuras.IsDurationObject(state.durationObject)
end

function Private.GetDurationTextFormatter(format, threshold, precision, secondsOnly)
  local key = format .. ":" .. threshold .. ":" .. precision .. ":" .. tostring(secondsOnly == true)
  local formatter = formatters[key]
  if not formatter then
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    local rounding = Enum.NumericRuleFormatRounding
    local rules = {
      {threshold = 0, format = ""},
      {threshold = 0.000001, format = "%d", step = 1, rounding = format == 99 and rounding.Up or rounding.Down},
    }
    if threshold > 0 then
      rules[2] = {threshold = 0.000001, format = "%." .. precision .. "f"}
      rules[#rules + 1] = {threshold = threshold, format = "%d", step = 1, rounding = format == 99 and rounding.Up or rounding.Down}
    end
    if not secondsOnly then
      local minuteThreshold = math.max(60, threshold)
      if threshold == minuteThreshold then table.remove(rules) end
      rules[#rules + 1] = {
        threshold = minuteThreshold, format = "%d:%02d", step = 1,
        rounding = format == 99 and rounding.Up or rounding.Down,
        components = {{div = 60}, {mod = 60}},
      }
    end
    formatter:SetBreakpoints(rules)
    formatters[key] = formatter
  end
  return formatter
end

function Private.FormatDurationText(duration, total, format, threshold, precision, modRate)
  local formatter = Private.GetDurationTextFormatter(format, threshold, precision)
  local modifier = modRate == false and Enum.DurationTimeModifier.BaseTime or Enum.DurationTimeModifier.RealTime
  if total then return duration:FormatTotalDuration(formatter, modifier) end
  return duration:FormatRemainingDuration(formatter, modifier)
end
