-- Modified for ForeverAuras, 2026-10-07.
if not WeakAuras.IsLibsOK() then return end
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
    return WeakAuras.IsDurationObject(state.cdmTextDurationObject)
  end
  return state.progressType == "durationObject" and WeakAuras.IsDurationObject(state.durationObject)
end

-- Below the threshold (or a minute): seconds, with decimals below the threshold.
local function SecondRules(threshold, precision, rounding, suffix)
  local rules = {{threshold = 0, format = ""}, {threshold = 0.000001, format = "%d" .. suffix, step = 1, rounding = rounding}}
  if threshold > 0 then
    rules[2] = {threshold = 0.000001, format = "%." .. precision .. "f"}
    if threshold < 60 then rules[3] = {threshold = threshold, format = "%d" .. suffix, step = 1, rounding = rounding} end
  end
  return rules
end

local function Part(div, mod, rounding)
  return {div = div, mod = mod, step = 1, rounding = rounding}
end

-- Old Blizzard: 2h | 3m | 10s.
local function ShortRules(threshold, precision, rounding)
  local rules = SecondRules(threshold, precision, rounding, "s")
  rules[#rules + 1] = {threshold = math.max(60, threshold), format = "%dm", components = {Part(60, nil, rounding)}}
  rules[#rules + 1] = {threshold = 3600, format = "%dh", components = {Part(3600, nil, rounding)}}
  rules[#rules + 1] = {threshold = 86400, format = "%dd", components = {Part(86400, nil, rounding)}}
  return rules
end

-- Modern Blizzard: 1h 3m | 3m 7s | 10s.
local function ModernRules(threshold, precision, rounding)
  local down = Enum.NumericRuleFormatRounding.Down
  local rules = SecondRules(threshold, precision, rounding, "s")
  rules[#rules + 1] = {threshold = math.max(60, threshold), format = "%dm %ds", components = {Part(60, nil, down), Part(nil, 60, down)}}
  rules[#rules + 1] = {threshold = 3600, format = "%dh %dm", components = {Part(3600, nil, down), Part(60, 60, down)}}
  rules[#rules + 1] = {threshold = 86400, format = "%dd %dh", components = {Part(86400, nil, down), Part(3600, 24, down)}}
  return rules
end

local styledRules = {[-3] = ShortRules, [-4] = ModernRules}

function Private.GetDurationTextFormatter(format, threshold, precision, secondsOnly, style)
  local Rules = styledRules[style]
  local key = format .. ":" .. threshold .. ":" .. precision .. ":" .. tostring(secondsOnly == true) .. ":" .. tostring(Rules and style)
  local formatter = formatters[key]
  if not formatter and Rules then
    formatter = C_StringUtil.CreateNumericRuleFormatter()
    local rounding = Enum.NumericRuleFormatRounding
    formatter:SetBreakpoints(Rules(threshold, precision, format == 99 and rounding.Up or rounding.Down))
    formatters[key] = formatter
  end
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
