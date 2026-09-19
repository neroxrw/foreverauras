-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local knownEvents = {
  PLAYER_ENTERING_WORLD = true,
  ADDON_RESTRICTION_STATE_CHANGED = true,
  PLAYER_IN_COMBAT_CHANGED = true,
  ENCOUNTER_STATE_CHANGED = true,
  CHALLENGE_MODE_START = true,
  PVP_MATCH_ACTIVE = true,
  PVP_MATCH_COMPLETE = true,
  PVP_MATCH_INACTIVE = true,
  PVP_MATCH_STATE_CHANGED = true,
}

local secretState = nil
local function HandleEvent(_, event, ...)
  local newSecretState = Private.ClientAPI.RestrictionsActive()
  if secretState ~= newSecretState then
    secretState = newSecretState
    Private.callbacks:Fire("WA_SECRET_STATE_UPDATE") -- for load
    Private.ScanEvents("WA_SECRET_STATE_UPDATE") -- for triggers
  end
  if event == "ADDON_RESTRICTION_STATE_CHANGED" then
    local restrictionType, state = ...
    if state == Enum.AddOnRestrictionState.Activating then
      -- in case we missed an event we can ensure if applied
      -- type affects us by rechecking on next frame
      C_Timer.After(0, HandleEvent)
    end
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", HandleEvent)
for event in pairs(knownEvents) do
  frame:RegisterEvent(event)
end


function ForeverAuras.IsSecretStateActive()
  return secretState
end
