-- Modified for ForeverAuras, 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end

local L = ForeverAuras.L

--@localization(locale="enUS", format="lua_additive_table", namespace="ForeverAuras / Templates")@

-- Make missing translations available
setmetatable(ForeverAuras.L, {__index = function(self, key)
  self[key] = (key or "")
  return key
end})
