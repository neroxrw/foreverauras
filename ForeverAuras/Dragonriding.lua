-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

local LibAdvFlight = LibStub("LibAdvFlight-1.1")
local Events = LibAdvFlight.Events;

local function HandleEvent(self, event, arg1)
  Private.callbacks:Fire("WA_DRAGONRIDING_UPDATE")
  if event == "PLAYER_ENTERING_WORLD" and arg1 == true then
    C_Timer.After(2, HandleEvent)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", HandleEvent)

LibAdvFlight.RegisterCallback(Events.ADV_FLYING_ENABLED, HandleEvent);
LibAdvFlight.RegisterCallback(Events.ADV_FLYING_DISABLED, HandleEvent);

Private.IsDragonriding = function ()
  return LibAdvFlight.IsAdvFlyEnabled()
end

