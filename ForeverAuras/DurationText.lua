-- Modified for ForeverAuras, 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...

local formatters = {}

-- CDM can show a GCD swipe while its text uses only the spell/recharge timer.
-- Keep this choice independent of whether IsZero() is readable in combat.
function Private.GetTextDuration(state)
  return state.cdmTextDurationObject or state.durationObject
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
