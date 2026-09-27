-- Preserve spell countdowns and desaturation during Shoot's shared cooldown.
-- Duration objects remain opaque; logical cooldown state and swipes stay live.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local expiryTimer, refreshQueued
local snapshots, castAfterShot = {}, {}
local shotAt, lastShotUpdate = -math.huge, -math.huge
local window = 3

local function PublicSpell(id)
  return not issecretvalue(id) and type(id) == "number"
end

-- Refresh text through dedicated internal events, not synthetic Blizzard events.
local function Refresh()
  if refreshQueued then return end
  refreshQueued = true
  C_Timer.After(0, function()
    refreshQueued = nil
    Private.ScanEvents("FA_WAND_TEXT_REFRESH")
    Private.ScanEvents("FA_CDM_REFRESH")
  end)
end

local function Clear()
  wipe(snapshots)
  wipe(castAfterShot)
  shotAt, lastShotUpdate = -math.huge, -math.huge
  if expiryTimer then expiryTimer:Cancel(); expiryTimer = nil end
end

local function NoteShot()
  local now = GetTime()
  -- SUCCEEDED and COOLDOWN can report the same shot in either order. Do not
  -- erase a subsequent cast when a duplicate update arrives in that frame.
  if now - lastShotUpdate > 0.05 then
    shotAt = now
    wipe(castAfterShot)
  end
  lastShotUpdate = now
  if expiryTimer then expiryTimer:Cancel() end
  expiryTimer = C_Timer.NewTimer(window, function()
    expiryTimer = nil
    Refresh()
  end)
  Refresh()
end

local function OnEvent(_, event, unit, baseSpellID, spellID)
  if event == "PLAYER_ENTERING_WORLD" then
    Clear()
    Refresh()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" then
    if not PublicSpell(spellID) then
      -- An unidentified cast cannot safely be attributed to a tracked spell.
      Clear()
    elseif spellID == 5019 then
      NoteShot()
    else
      castAfterShot[spellID] = true
    end
    Refresh()
  elseif event == "SPELL_UPDATE_COOLDOWN" and ((PublicSpell(unit) and unit == 5019) or (PublicSpell(baseSpellID) and baseSpellID == 5019)) then
    -- The expiration update is not another shot. Unknown flags leave cast events
    -- in charge instead of extending the window from an unreadable value.
    local info = C_Spell.GetSpellCooldown(5019)
    if info and not issecretvalue(info.isActive) and info.isActive == true then NoteShot() end
  end
end

-- Call before choosing a recharge/loss-of-control timer. A copied timer expires
-- naturally in Blizzard's renderer even if no readable expiration is available.
function Private.GetWandCooldownDuration(spellID, duration, source)
  if not PublicSpell(spellID) or spellID == 5019 then return duration end
  -- CDM and ordinary Spell triggers must not overwrite one another's samples.
  local key = (source or "spell") .. ":" .. spellID
  local holding = GetTime() - shotAt < window and not castAfterShot[spellID]
  if holding then
    -- Keep the live timer until a sample is available.
    -- The second return describes our own selection, never the timer's contents.
    return snapshots[key] or duration, snapshots[key] ~= nil
  end
  if duration and duration.Copy then snapshots[key] = duration:Copy()
  else snapshots[key] = nil end
  return duration
end

-- Track public cast events from login; no session toggle is required.
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnEvent)
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
