-- Player swing timing supplied by Blizzard; no combat-log reconstruction.
if not ForeverAuras.IsLibsOK() then return end
local swings, timers = {}, {}
local frame
local eventName = 'FA_SWING_TIMER_UPDATE'
local slots = {[0] = 16, [1] = 17, [2] = 18}
local names = {[0] = 'Main Hand', [1] = 'Off Hand', [2] = 'Ranged'}

function ForeverAuras.GetSwingTimerInfo(swingType)
  local swing = swings[swingType]
  return swing and swing.duration or 0, swing and swing.expirationTime or 0,
    names[swingType], GetInventoryItemTexture('player', slots[swingType]) or 132324
end

function ForeverAuras.WatchSwingTimer()
  if frame or not Enum.PlayerSwingType then return end
  frame = CreateFrame('Frame')
  frame:RegisterEvent('PLAYER_SWING')
  frame:RegisterEvent('PLAYER_ENTERING_WORLD')
  frame:RegisterEvent('WEAPON_SLOT_CHANGED')
  frame:SetScript('OnEvent', function(_, event, duration, swingType)
    if event == 'PLAYER_SWING' then
      if issecretvalue(duration) or issecretvalue(swingType) then return end
      if not slots[swingType] or type(duration) ~= 'number' or duration <= 0 or duration == math.huge or duration ~= duration then return end
      if timers[swingType] then timers[swingType]:Cancel() end
      swings[swingType] = {duration = duration, expirationTime = GetTime() + duration}
      timers[swingType] = C_Timer.NewTimer(duration, function()
        swings[swingType], timers[swingType] = nil, nil
        ForeverAuras.ScanEvents(eventName)
      end)
    else
      for _, timer in pairs(timers) do timer:Cancel() end
      wipe(timers)
      wipe(swings)
    end
    ForeverAuras.ScanEvents(eventName)
  end)
end
