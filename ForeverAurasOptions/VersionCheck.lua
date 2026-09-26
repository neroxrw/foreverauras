-- Modified for ForeverAuras, 2026-09-19.
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local L = ForeverAuras.L

local optionsVersion = "0.6.0-BETA"


if optionsVersion ~= ForeverAuras.versionString then
  local message = string.format(L["The ForeverAuras Options Addon version %s doesn't match the ForeverAuras version %s. If you updated the addon while the game was running, try restarting World of Warcraft. Otherwise try reinstalling ForeverAuras"],
                    optionsVersion, ForeverAuras.versionString)
  ---@diagnostic disable-next-line: duplicate-set-field
  ForeverAuras.IsLibsOk = function() return false end
  ---@diagnostic disable-next-line: duplicate-set-field
  ForeverAuras.ToggleOptions = function()
       ForeverAuras.prettyPrint(message)
  end

end
