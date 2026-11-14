-- Modified for ForeverAuras, 2026-10-23.
-- Modifications Copyright (C) 2026 ForeverAuras. Licensed under the GNU GPL v2 (see LICENSE).
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local L = WeakAuras.L

-- ForeverAuras (1.4.0): read from the toc, so a build that bumps the
-- version cannot leave this behind (every dev build since 1.3.10-dev.1 did,
-- and the options refused to open with "doesn't match").
local optionsVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "1.4.0"


if optionsVersion ~= WeakAuras.versionString then
  local message = string.format(L["The ForeverAuras Options Addon version %s doesn't match the ForeverAuras version %s. If you updated the addon while the game was running, try restarting World of Warcraft. Otherwise try reinstalling ForeverAuras"],
                    optionsVersion, WeakAuras.versionString)
  ---@diagnostic disable-next-line: duplicate-set-field
  WeakAuras.IsLibsOk = function() return false end
  ---@diagnostic disable-next-line: duplicate-set-field
  WeakAuras.ToggleOptions = function()
       WeakAuras.prettyPrint(message)
  end

end
