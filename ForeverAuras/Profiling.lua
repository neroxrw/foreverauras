-- Modified for ForeverAuras, 2026-09-18.
-- Modifications Copyright (C) 2026 ForeverAuras. Licensed under the GNU GPL v2 (see LICENSE).
if not WeakAuras.IsLibsOK() then
  return
end
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)

---@class WeakAuras
local WeakAuras = WeakAuras
local L = WeakAuras.L
local prettyPrint = WeakAuras.prettyPrint
local LGF = LibStub("LibGetFrame-1.0")
-- LibCustomGlow's per-frame glow handlers are timed under "glow ..." while
-- profiling runs (see Timed in the library).
local LCG = LibStub("LibCustomGlow-1.0-foreverauras", true)
if LCG then
  LCG.StartProfiling = function(name) Private.StartProfileSystem(name) end
  LCG.StopProfiling = function(name) Private.StopProfileSystem(name) end
end

local profileData = {}
profileData.systems = {}
profileData.auras = {}

local currentProfileState, ProfilingTimer

local table_to_string
table_to_string = function(tbl, depth)
  if depth and depth >= 3 then
    return "{ ... }"
  end
  local str
  for k, v in pairs(tbl) do
    if type(v) ~= "userdata" then
      if type(v) == "table" then
        v = table_to_string(v, (depth and depth + 1 or 1))
      elseif type(v) == "function" then
        v = "function"
      elseif type(v) == "string" then
        v = '"' .. v .. '"'
      end

      if type(k) == "string" then
        k = '"' .. k .. '"'
      end

      str = (str and str .. "|cff999999,|r " or "|cff999999{|r ") .. "|cffffff99[" .. tostring(k) .. "]|r |cff999999=|r |cffffffff" .. tostring(v) .. "|r"
    end
  end
  return (str or "{ ") .. " }"
end

WeakAurasProfilingReportMixin = {}
function WeakAurasProfilingReportMixin:OnShow()
  if self.initialised then
    return
  end
  self.initialised = true

  ButtonFrameTemplate_HidePortrait(self)
  self:SetTitle(L["ForeverAuras Profiling Report"])
  self:SetSize(500, 300)
end

function WeakAurasProfilingReportMixin:ClearText()
  self.ScrollBox.messageFrame:SetText("")
end

function WeakAurasProfilingReportMixin:AddText(v)
  if not v then
    return
  end
  --- @type string?
  local m = self.ScrollBox.messageFrame:GetText()
  if m ~= "" then
    m = m .. "|n"
  end
  if type(v) == "table" then
    v = table_to_string(v)
  end
  self.ScrollBox.messageFrame.originalText = m .. v
  self.ScrollBox.messageFrame:SetText(self.ScrollBox.messageFrame.originalText)
end

local hitchActive = false
local function StartProfiling(map, id)
  if not map[id] then
    map[id] = {}
    map[id].count = 1
    map[id].start = debugprofilestop()
    map[id].elapsed = 0
    map[id].spike = 0
    map[id].calls = 1   -- ForeverAuras (dev.99): how often it ran (the focus report)
    -- ForeverAuras 1.2.4 (Dan's collector hitches): Lua allocation is attributed too (entry.alloc, the
    -- profile's allocation list; the hitch capture's per-frame buckets, HitchAccumulate)
    map[id].memStart = collectgarbage("count")
    return
  end

  if map[id].count == 0 then
    map[id].count = 1
    map[id].calls = (map[id].calls or 0) + 1
    map[id].start = debugprofilestop()
    map[id].memStart = collectgarbage("count")
  else
    map[id].count = map[id].count + 1
  end
end

local function StopProfiling(map, id)
  -- A handler that began before profiling (re)started has no entry to stop.
  if not map[id] then return end
  map[id].count = map[id].count - 1
  if map[id].count == 0 then
    local elapsed = debugprofilestop() - map[id].start
    map[id].elapsed = map[id].elapsed + elapsed
    if elapsed > map[id].spike then
      map[id].spike = elapsed
    end
    -- ForeverAuras 1.2.4: the allocation of this run (a collector step inside it can make the delta
    -- negative; such a run counts as nothing)
    if map[id].memStart then
      local delta = collectgarbage("count") - map[id].memStart
      if delta > 0 then map[id].alloc = (map[id].alloc or 0) + delta end
    end
  end
end

-- Hitch capture (/fa phitch): while active, every finished measurement is also
-- added to a per-frame bucket so a slow frame can be broken down afterwards.
-- The buckets live beside the normal totals and are only touched in this mode.
local hitch = {active = false, threshold = 30, touched = {}, events = {}, counts = {}}

-- Counts a widget call of note (container refreshes, reparenting, texture and
-- font changes) in the current frame's bucket. These calls cost the client
-- layout or loading time that no Lua profiler sees, so the counts are printed
-- with a slow frame to show what ForeverAuras asked of the client in it.
function Private.HitchCount(name, n)
  if hitch.active then hitch.counts[name] = (hitch.counts[name] or 0) + (n or 1) end
end
-- ForeverAuras: whether a capture is running, for counters whose name is
-- built on the spot (no string is made when nothing is listening).
function Private.HitchCounting()
  return hitch.active
end

-- Adds one finished measurement to the current frame's bucket for map[id]:
-- its time, and the Lua memory it allocated (garbage drives the collector's
-- steps, which the time of no handler shows).
local function HitchAccumulate(map, id, elapsed)
  local entry = map[id]
  if not entry.frame or entry.frame == 0 then
    entry.frame = 0
    entry.frameMem = 0
    hitch.touched[#hitch.touched + 1] = {entry = entry, name = id, aura = map == profileData.auras}
  end
  entry.frame = entry.frame + elapsed
  if entry.memStart then
    local total = collectgarbage("count") - entry.memStart
    if total > 0 then entry.alloc = (entry.alloc or 0) + total end   -- ForeverAuras 1.2.4: the profile's allocation list
  end
  -- ForeverAuras 1.2.4 (Dan's combat-drop hitches): when in the frame the addon's code ran, so a
  -- slow frame's untracked time can be placed before, between or after the addon's handlers
  local now = debugprofilestop()
  local start = now - elapsed
  if not hitch.firstStart or start < hitch.firstStart then hitch.firstStart = start end
  if not hitch.lastStop or now > hitch.lastStop then hitch.lastStop = now end
  if entry.memStart then
    local delta = collectgarbage("count") - entry.memStart
    if delta > 0 then entry.frameMem = (entry.frameMem or 0) + delta end
  end
end

-- Same as StopProfiling, plus the per-frame bucket used by hitch capture.
local function StopProfilingHitch(map, id)
  -- A handler that began before profiling (re)started has no entry to stop.
  if not map[id] then return end
  map[id].count = map[id].count - 1
  if map[id].count == 0 then
    local elapsed = debugprofilestop() - map[id].start
    map[id].elapsed = map[id].elapsed + elapsed
    if elapsed > map[id].spike then
      map[id].spike = elapsed
    end
    HitchAccumulate(map, id, elapsed)
  end
end

-- Helper functions used by the built-in cooldown triggers, timed one by one
-- while profiling runs ("api ..." systems) to see which part of a trigger is
-- expensive. The original functions are put back when profiling stops.
local apiWrapped = {}
local function ApiTargets()
  return {
    {WeakAuras, "WeakAuras", {"GetSpellCooldown", "GetSpellCharges", "IsSpellKnownIncludingPet",
      "GetSpellCooldownDurationNoGCD", "GetSpellCooldownDuration", "GetSpellLossOfControlCooldown"}},
    {Private.ExecEnv, "ExecEnv", {"GetEffectiveSpellId", "GetSpellCooldownData", "GetSpellInfo", "GetSpellName"}},
    {Private, "Private", {"GetWandCooldownDuration", "GetSpellCooldownData", "GCDTextAlpha"}},
  }
end
local function StopApi(name, ...)
  Private.StopProfileSystem(name)
  return ...
end
local function WrapApis()
  for _, target in ipairs(ApiTargets()) do
    local tbl, prefix, keys = target[1], target[2], target[3]
    for _, key in ipairs(keys) do
      local fn = tbl and rawget(tbl, key)
      if type(fn) == "function" then
        local name = "api " .. prefix .. "." .. key
        apiWrapped[#apiWrapped + 1] = {tbl, key, fn}
        rawset(tbl, key, function(...)
          Private.StartProfileSystem(name)
          return StopApi(name, fn(...))
        end)
      end
    end
  end
end
local function UnwrapApis()
  for i = #apiWrapped, 1, -1 do
    local entry = apiWrapped[i]
    rawset(entry[1], entry[2], entry[3])
    apiWrapped[i] = nil
  end
end

-- ForeverAuras (dev.99): "/fa pfocus <aura name>" names one aura whose time
-- the next profile breaks down: by the place in the addon that charged it
-- (the trigger scan, the region update, the conditions, the custom text...)
-- and by the systems that ran inside those charges. Printed by /fa pprint.
local focus = {id = nil, stack = {}, sites = {}, systems = {}}
local focusEnrolled = {}   -- system -> how many of its open intervals the focus enrolled
function Private.ProfileFocusReset()
  focus.stack, focus.sites, focus.systems = {}, {}, {}
  focusEnrolled = {}
end
local function FocusStart(id)
  if focus.id ~= id then return end
  local site = debugstack(3, 1, 0) or "?"
  site = site:gsub("^%s+", ""):gsub("%s+$", ""):gsub("Interface/AddOns/ForeverAuras/", ""):gsub(": in function.*$", "")
  focus.stack[#focus.stack + 1] = site
  StartProfiling(focus.sites, site)
end
local function FocusStop(id)
  if focus.id ~= id or #focus.stack == 0 then return end
  StopProfiling(focus.sites, table.remove(focus.stack))
end

-- (Astra's dev.99 review) a system enrolled in the focus at its start is closed at its stop whatever the
-- focus depth is then (a system may start before the aura's charge and stop inside it, or the reverse)
local function FocusSystemStart(system)
  if #focus.stack > 0 then
    StartProfiling(focus.systems, system)
    focusEnrolled[system] = (focusEnrolled[system] or 0) + 1
  end
end
local function FocusSystemStop(system)
  local n = focusEnrolled[system]
  if n and n > 0 then
    focusEnrolled[system] = n - 1
    StopProfiling(focus.systems, system)
  end
end

local function StartProfileSystem(system)
  StartProfiling(profileData.systems, "wa")
  StartProfiling(profileData.systems, system)
  if focus.id then FocusSystemStart(system) end
end

local function StartProfileAura(id)
  StartProfiling(profileData.auras, id)
  if focus.id then FocusStart(id) end
end

local function StopProfileSystem(system)
  StopProfiling(profileData.systems, "wa")
  StopProfiling(profileData.systems, system)
  if focus.id then FocusSystemStop(system) end
end

local function StopProfileAura(id)
  StopProfiling(profileData.auras, id)
  if focus.id then FocusStop(id) end
end

function WeakAuras.ProfileFocus(id)
  if id and id ~= "" and WeakAuras.GetData(id) then
    focus.id = id
    Private.ProfileFocusReset()
    prettyPrint(L["Profile focus: %s (the next /fa pstart ... /fa pprint breaks its time down)."]:format(id))
  elseif id and id ~= "" then
    prettyPrint(L["Profile focus: no aura named %s."]:format(id))
  else
    focus.id = nil
    Private.ProfileFocusReset()
    prettyPrint(L["Profile focus cleared."])
  end
end

local function StartProfileUID(uid)
  local id = Private.UIDtoID(uid)
  StartProfiling(profileData.auras, id)
  if focus.id then FocusStart(id) end   -- (dev.100) animations charge through the uid
end

local function StopProfileUID(uid)
  local id = Private.UIDtoID(uid)
  StopProfiling(profileData.auras, id)
  if focus.id then FocusStop(id) end
end

function Private.ProfileRenameAura(oldid, id)
  profileData.auras[id] = profileData.auras[id]
  profileData.auras[oldid] = nil
end

local RegisterProfile = function(startType)
  if startType == "boss" then
    startType = "encounter"
  end
  local delayedStart
  if startType == "encounter" then
    WeakAurasProfilingFrame:UnregisterAllEvents()
    prettyPrint(L["Your next encounter will automatically be profiled."])
    WeakAurasProfilingFrame:RegisterEvent("ENCOUNTER_START")
    WeakAurasProfilingFrame:RegisterEvent("ENCOUNTER_END")
    currentProfileState = startType
    delayedStart = true
  elseif startType == "combat" then
    WeakAurasProfilingFrame:UnregisterAllEvents()
    prettyPrint(L["Your next instance of combat will automatically be profiled."])
    WeakAurasProfilingFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    WeakAurasProfilingFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    currentProfileState = startType
    delayedStart = true
  elseif startType == "autostart" then
    prettyPrint(L["Profiling automatically started."])
    currentProfileState = "profiling"
  elseif startType and startType:match("%d") then
    WeakAurasProfilingFrame:UnregisterAllEvents()
    local time = startType + 0
    prettyPrint(L["Profiling started. It will end automatically in %d seconds"]:format(time))
    ProfilingTimer = WeakAuras.timer:ScheduleTimer(WeakAuras.StopProfile, time)
    currentProfileState = "profiling"
  else
    WeakAurasProfilingFrame:UnregisterAllEvents()
    prettyPrint(L["Profiling started."])
    currentProfileState = "profiling"
  end
  WeakAurasProfilingFrame:UpdateButtons()
  return delayedStart
end

---@diagnostic disable-next-line: duplicate-set-field
function WeakAuras.StartProfile(startType)
  if currentProfileState == "profiling" then
    prettyPrint(L["Profiling already started."])
    return
  end

  if RegisterProfile(startType) then
    -- Scheduled for later
    return
  end

  profileData.systems = {}
  profileData.auras = {}
  Private.ProfileFocusReset()
  profileData.systems.time = {}
  profileData.systems.time.start = debugprofilestop()
  profileData.systems.time.elapsed = nil
  profileData.systems.time.count = 1

  Private.StartProfileSystem = StartProfileSystem
  -- Times handlers set through Private.TimedAPI while profiling runs.
  Private.handlerTiming = true
  if #apiWrapped == 0 then WrapApis() end
  Private.StartProfileAura = StartProfileAura
  Private.StartProfileUID = StartProfileUID
  Private.StopProfileSystem = StopProfileSystem
  Private.StopProfileAura = StopProfileAura
  Private.StopProfileUID = StopProfileUID
  LGF.StartProfile()
end

local function doNothing() end

-- Hitch-capture variants of the stop functions; installed instead of the
-- normal ones by WeakAuras.StartHitchCapture.
local function StopProfileSystemHitch(system)
  if focus.id then FocusSystemStop(system) end
  StopProfilingHitch(profileData.systems, "wa")
  StopProfilingHitch(profileData.systems, system)
end

local function StopProfileAuraHitch(id)
  StopProfilingHitch(profileData.auras, id)
  if focus.id then FocusStop(id) end
end

local function StopProfileUIDHitch(uid)
  local id = Private.UIDtoID(uid)
  StopProfilingHitch(profileData.auras, id)
  if focus.id then FocusStop(id) end
end

-- ForeverAuras 1.2.4 (Astra's dev.6 review): one interval is the stretch
-- between two hitchFrame OnUpdates, measured on ONE clock
-- (debugprofilestop at those two points); the heap is read at the same
-- points, so "heap" is the NET change of the whole Lua heap over the
-- interval (allocation minus whatever the collector took back), not an
-- allocation count. The client's own profiler counters (LastTime) are
-- sampled there too, but WHEN the client publishes them relative to this
-- interval is not validated on this client, so they are labelled as the
-- client's samples. What no counter accounts for is reported as
-- "unassigned": a remainder, not a measurement of any one activity.
-- Each interval is kept as a bounded snapshot of numbers; the text is
-- built only for a slow interval and the one before it.
local function SnapshotInterval(frameMs, memDelta)
  local snap = {frameMs = frameMs, memDelta = memDelta, systems = {}, auras = {}, events = {}, counts = {}, addons = {}}
  if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum.AddOnProfilerMetric then
    local metric = Enum.AddOnProfilerMetric.LastTime
    snap.addonMs = C_AddOnProfiler.GetAddOnMetric(AddonName, metric)
    if C_AddOnProfiler.GetOverallMetric then
      local all = C_AddOnProfiler.GetOverallMetric(metric)
      if type(all) == "number" then snap.allMs = all end
      local ok, container = pcall(C_AddOnProfiler.GetAddOnMetric, "Blizzard_AuraContainer", metric)
      if ok and type(container) == "number" then snap.containerMs = container end
    end
    if C_AddOnProfiler.GetApplicationMetric then
      local ok, ms = pcall(C_AddOnProfiler.GetApplicationMetric, metric)
      if ok and type(ms) == "number" then snap.clientMs = ms end
    end
    -- the other addons' samples, only for a slow interval (a loop over every addon)
    if frameMs >= hitch.threshold and C_AddOns and C_AddOns.GetNumAddOns then
      for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name ~= AddonName and C_AddOns.IsAddOnLoaded(i) then
          local ok, ms = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
          if ok and type(ms) == "number" and ms >= 1 then snap.addons[#snap.addons + 1] = {name = name, ms = ms} end
        end
      end
    end
  end
  local waEntry = profileData.systems.wa
  snap.tracked = waEntry and waEntry.frame or 0
  for _, t in ipairs(hitch.touched) do
    if t.name ~= "wa" then
      local list = t.aura and snap.auras or snap.systems
      list[#list + 1] = {name = t.name, ms = t.entry.frame, kb = t.entry.frameMem or 0}
    end
  end
  for event, count in pairs(hitch.events) do snap.events[#snap.events + 1] = {name = event, count = count} end
  for name, count in pairs(hitch.counts) do snap.counts[#snap.counts + 1] = {name = name, count = count} end
  if hitch.firstStart and hitch.stamp then
    snap.codeFrom, snap.codeTo = hitch.firstStart - hitch.stamp, hitch.lastStop - hitch.stamp
  end
  return snap
end

-- The two report lines of a snapshot (built only when printed).
local function SummariseInterval(snap)
  local byTime = function(a, b) return a.ms > b.ms end
  sort(snap.systems, byTime)
  sort(snap.auras, byTime)
  local parts = {}
  local shown = 0
  for _, row in ipairs(snap.systems) do
    if row.ms >= 0.2 and shown < 14 then parts[#parts + 1] = ("%s %.1f"):format(row.name, row.ms); shown = shown + 1 end
  end
  shown = 0
  for _, row in ipairs(snap.auras) do
    if row.ms >= 0.2 and shown < 3 then parts[#parts + 1] = ("|cffffff99%s|r %.1f"):format(row.name, row.ms); shown = shown + 1 end
  end
  -- the systems whose runs saw the heap grow the most (net, per run; nested systems overlap)
  local allocators = {}
  for _, row in ipairs(snap.systems) do if row.kb >= 16 then allocators[#allocators + 1] = row end end
  sort(allocators, function(a, b) return a.kb > b.kb end)
  for i = 1, math.min(8, #allocators) do
    parts[#parts + 1] = ("|cffcc99ff%s|r +%.0fKB"):format(allocators[i].name, allocators[i].kb)
  end
  sort(snap.counts, function(a, b) return a.count > b.count end)
  for i = 1, math.min(8, #snap.counts) do
    parts[#parts + 1] = ("|cff99ccff%s|r x%d"):format(snap.counts[i].name, snap.counts[i].count)
  end
  sort(snap.addons, function(a, b) return a.ms > b.ms end)
  for i = 1, math.min(5, #snap.addons) do
    parts[#parts + 1] = ("|cffff9966%s|r %.1fms"):format(snap.addons[i].name, snap.addons[i].ms)
  end
  local samples = ""
  if snap.addonMs then
    samples = (" | client's samples: FA %.1fms, all addons %s, AuraContainer %s, whole client %s"):format(snap.addonMs,
      snap.allMs and ("%.1fms"):format(snap.allMs) or "?", snap.containerMs and ("%.1fms"):format(snap.containerMs) or "?",
      snap.clientMs and ("%.1fms"):format(snap.clientMs) or "?")
  end
  local unassigned = ""
  if snap.allMs then unassigned = (" | unassigned %.0fms"):format(math.max(0, snap.frameMs - snap.allMs)) end
  local placement = ""
  if snap.codeFrom then placement = (" | FA code +%.0f..+%.0fms"):format(snap.codeFrom, snap.codeTo) end
  local events = {}
  for i, e in ipairs(snap.events) do events[i] = e.count > 1 and (e.name .. "x" .. e.count) or e.name end
  local header = ("%.0fms | tracked %.1fms | heap %+.0fKB net%s%s%s%s"):format(snap.frameMs, snap.tracked, snap.memDelta,
    samples, unassigned, placement, #events > 0 and (" | " .. table.concat(events, " ")) or "")
  return header, #parts > 0 and ("   " .. table.concat(parts, ", ")) or nil
end

-- Runs at the start of every frame while hitch capture is active. Events are
-- dispatched before OnUpdate, so the frame in which combat starts or ends is
-- summarised one interval before the slow drawing it causes shows up. Each
-- interval's snapshot is therefore kept, and a slow interval is reported
-- together with the one before it.
local hitchFrame = CreateFrame("Frame")
hitchFrame:Hide()
hitchFrame:SetScript("OnUpdate", function()
  -- the interval boundary: one clock, the heap read at the same point
  local now = debugprofilestop()
  local mem = collectgarbage("count")
  if hitch.stamp then
    local frameMs = now - hitch.stamp
    local snap = SnapshotInterval(frameMs, mem - hitch.lastMem)
    if frameMs >= hitch.threshold then
      if hitch.previous then
        local header, details = SummariseInterval(hitch.previous)
        prettyPrint("Before hitch: " .. header)
        if details then print(details) end
      end
      local header, details = SummariseInterval(snap)
      prettyPrint("Hitch " .. header)
      if details then print(details) end
    end
    hitch.previous = snap
  end
  hitch.lastMem = mem
  hitch.stamp = now
  hitch.firstStart, hitch.lastStop = nil, nil
  for i, t in ipairs(hitch.touched) do
    t.entry.frame = 0
    t.entry.frameMem = 0
    hitch.touched[i] = nil
  end
  wipe(hitch.events)
  wipe(hitch.counts)
end)
-- Combat and restriction changes are labelled in the report so transitions
-- can be told apart from other slow frames; the other labels mark the common
-- causes of display work outside combat changes (target, auras, cooldowns,
-- nameplates, roster), so a slow frame can be matched to what happened in it.
local hitchEvents = {PLAYER_REGEN_DISABLED = "+combat", PLAYER_REGEN_ENABLED = "-combat",
  ADDON_RESTRICTION_STATE_CHANGED = "restriction", PLAYER_ENTERING_WORLD = "loading",
  PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus", UPDATE_MOUSEOVER_UNIT = "mouseover",
  UNIT_AURA = "aura", SPELL_UPDATE_COOLDOWN = "cooldown", SPELL_UPDATE_USABLE = "usable",
  NAME_PLATE_UNIT_ADDED = "+plate", NAME_PLATE_UNIT_REMOVED = "-plate", GROUP_ROSTER_UPDATE = "roster",
  UNIT_PET = "pet", PLAYER_EQUIPMENT_CHANGED = "equip", UNIT_SPELLCAST_SUCCEEDED = "cast",
  ZONE_CHANGED_NEW_AREA = "zone", UI_SCALE_CHANGED = "scale", COOLDOWN_VIEWER_DATA_LOADED = "cdm"}
-- Unit events are only labelled for the player and its target.
local hitchUnitEvents = {UNIT_AURA = true, UNIT_SPELLCAST_SUCCEEDED = true}
hitchFrame:SetScript("OnEvent", function(_, event, unit)
  local label = hitchEvents[event]
  if hitchUnitEvents[event] then
    if unit ~= "player" and unit ~= "target" then return end
    label = label .. ":" .. unit
  end
  hitch.events[label] = (hitch.events[label] or 0) + 1
end)

-- /fa phitch [ms]: starts profiling and reports every frame slower than ms
-- (default 30) until /fa phitch is used again. The normal profiling report
-- stays available afterwards through /fa pprint.
function WeakAuras.ToggleHitchCapture(threshold)
  if hitch.active then
    hitch.active = false; hitchActive = false
    hitchFrame:Hide()
    hitchFrame:UnregisterAllEvents()
    WeakAuras.StopProfile()
    return
  end
  if currentProfileState == "profiling" then
    WeakAuras.StopProfile()
  end
  hitch.threshold = tonumber(threshold) or 30
  WeakAuras.StartProfile()
  if currentProfileState ~= "profiling" then return end
  hitch.active = true; hitchActive = true
  hitch.lastMem = nil
  hitch.previous = nil
  hitch.stamp, hitch.firstStart, hitch.lastStop = nil, nil, nil   -- ForeverAuras 1.2.4 (the first boundary is the first OnUpdate)
  wipe(hitch.touched)
  wipe(hitch.events)
  wipe(hitch.counts)
  Private.StopProfileSystem = StopProfileSystemHitch
  Private.StopProfileAura = StopProfileAuraHitch
  Private.StopProfileUID = StopProfileUIDHitch
  for event in pairs(hitchEvents) do
    if hitchUnitEvents[event] then
      hitchFrame:RegisterUnitEvent(event, "player", "target")
    else
      hitchFrame:RegisterEvent(event)
    end
  end
  hitchFrame:Show()
  prettyPrint(("Hitch capture started: frames slower than %dms are reported. Type /fa phitch again to stop."):format(hitch.threshold))
  -- How much native aura content the Modern displays currently hold.
  if Private.BlizzardAuraDisplay and Private.BlizzardAuraDisplay.CountContainers then
    local displays, containers, shown = Private.BlizzardAuraDisplay.CountContainers()
    prettyPrint(("Modern displays active: %d, native containers: %d (%d shown)"):format(displays, containers, shown))
  end
end

-- /fa phitch login [ms] [seconds]: the next reload runs the hitch capture
-- from the moment the addon's saved variables are read, through login and
-- for `seconds` (default 20) after entering the world, then prints the slow
-- frames seen, the load time breakdown and the profile. One reload only.
local LOGIN_HITCH_SECONDS = 20
function WeakAuras.ArmLoginHitchCapture(threshold, seconds)
  if not Private.db then return end
  Private.db.hitchOnLogin = {threshold = tonumber(threshold) or 30, seconds = tonumber(seconds) or LOGIN_HITCH_SECONDS}
  prettyPrint(L["Hitch capture armed for the next reload: frames slower than %dms are reported from addon load until %d s after entering the world."]:format(
    Private.db.hitchOnLogin.threshold, Private.db.hitchOnLogin.seconds))
end

-- Called once the saved variables are read (ADDON_LOADED in ForeverAuras.lua).
function Private.StartLoginHitchCapture()
  local arm = Private.db and Private.db.hitchOnLogin
  if not arm then return end
  Private.db.hitchOnLogin = nil
  WeakAuras.ToggleHitchCapture(arm.threshold)
  if not hitch.active then return end
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
  watcher:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    prettyPrint(L["Entered the world; hitch capture continues for %d s."]:format(arm.seconds))
    C_Timer.After(arm.seconds, function()
      if hitch.active then WeakAuras.ToggleHitchCapture() end
      if Private.PrintLoadProfile then Private.PrintLoadProfile() end
      WeakAuras.PrintProfile()
    end)
  end)
end

---@diagnostic disable-next-line: duplicate-set-field
function WeakAuras.StopProfile()
  if currentProfileState ~= "profiling" then
    prettyPrint(L["Profiling not running."])
    return
  end

  prettyPrint(L["Profiling stopped."])

  -- Stopping profiling by any route also ends hitch capture.
  if hitch.active then
    hitch.active = false; hitchActive = false
    hitchFrame:Hide()
    hitchFrame:UnregisterAllEvents()
  end

  profileData.systems.time.elapsed = debugprofilestop() - profileData.systems.time.start
  profileData.systems.time.count = 0

  Private.StartProfileSystem = doNothing
  Private.handlerTiming = false
  UnwrapApis()
  Private.StartProfileAura = doNothing
  Private.StartProfileUID = doNothing
  Private.StopProfileSystem = doNothing
  Private.StopProfileAura = doNothing
  Private.StopProfileUID = doNothing
  LGF.StopProfile()

  currentProfileState = nil
  if WeakAurasProfilingFrame then
    WeakAurasProfilingFrame:UnregisterAllEvents()
    WeakAurasProfilingFrame:UpdateButtons()
  end

  if ProfilingTimer then
    WeakAuras.timer:CancelTimer(ProfilingTimer)
    ProfilingTimer = nil
  end
end

function WeakAuras.ToggleProfile()
  if not profileData.systems.time or profileData.systems.time.count ~= 1 then
    WeakAuras.StartProfile()
  else
    WeakAuras.StopProfile()
  end
end

local function CancelScheduledProfile()
  prettyPrint(L["Your scheduled automatic profile has been cancelled."])
  currentProfileState = nil
  WeakAurasProfilingFrame:UnregisterAllEvents()
  WeakAurasProfilingFrame:UpdateButtons()
end

WeakAuras.CancelScheduledProfile = CancelScheduledProfile

local function AutoStartStopProfiling(frame, event)
  if event == "ENCOUNTER_START" or event == "PLAYER_REGEN_DISABLED" then
    WeakAuras.StartProfile("autostart")
  elseif event == "ENCOUNTER_END" or event == "PLAYER_REGEN_ENABLED" then
    WeakAuras.StopProfile()
  end
end

local function ColoredSpike(spike)
  local r, g, b
  if spike < 2 then
    r, g, b = WeakAuras.GetHSVTransition(spike / 2, 0, 1, 0, 1, 1, 1, 0, 1)
  elseif spike < 2.5 then
    r, g, b = WeakAuras.GetHSVTransition((spike - 2) * 2, 1, 1, 0, 1, 1, 0.65, 0, 1)
  elseif spike < 3 then
    r, g, b = WeakAuras.GetHSVTransition((spike - 2.5) * 2, 1, 0.65, 0, 1, 1, 0, 0, 1)
  else
    r, g, b = 1, 0, 0
  end
  return ("|cff%02x%02x%02x%.2fms|r"):format(r * 255, g * 255, b * 255, spike)
end

local function PrintOneProfile(popup, name, map, total)
  if map.count ~= 0 then
    popup:AddText(name .. "  ERROR: count is not zero:" .. " " .. map.count)
  end

  local percent = ""
  if total then
    percent = (", %.2f%%"):format(100 * map.elapsed / total)
  end

  local spikeInfo = ""
  if map.spike then
    spikeInfo = ColoredSpike(map.spike)
  end

  popup:AddText(("%s |cff999999%.2fms%s (%s)|r"):format(name, map.elapsed, percent, spikeInfo))
end

local function SortProfileMap(map, sortField)
  local result = {}
  for k in pairs(map) do
    tinsert(result, k)
  end

  sort(result, function(a, b)
    if sortField then
      local x, y = map[a][sortField], map[b][sortField]
      if x and y then
        return x > y
      end
    end

    return map[a].elapsed > map[b].elapsed
  end)

  return result
end

local function TotalProfileTime(map)
  local total = 0
  for k, v in pairs(map) do
    if k ~= "time" and k ~= "wa" then
      total = total + v.elapsed
    end
  end
  return total
end

local function unitEventToMultiUnit(event)
  local count
  event, count = event:gsub("nameplate%d+$", "nameplate")
  if count == 1 then
    return event
  end
  event, count = event:gsub("boss%d$", "boss")
  if count == 1 then
    return event
  end
  event, count = event:gsub("arena%d$", "arena")
  if count == 1 then
    return event
  end
  event, count = event:gsub("raid%d+$", "group")
  if count == 1 then
    return event
  end
  event, count = event:gsub("raidpet%d+$", "group")
  if count == 1 then
    return event
  end
  event, count = event:gsub("party%d$", "party")
  if count == 1 then
    return event
  end
  event, count = event:gsub("partypet%d$", "party")
  return event
end

---@diagnostic disable-next-line: duplicate-set-field
function WeakAuras.PrintProfile()
  local popup = WeakAurasProfilingReport
  if not profileData.systems.time then
    prettyPrint(L["No Profiling information saved."])
    return
  end

  if profileData.systems.time.count == 1 then
    prettyPrint(L["Profiling still running, stop before trying to print."])
    return
  end

  popup:ClearAllPoints()
  if WeakAurasProfilingFrame and WeakAurasProfilingFrame:IsShown() then
    popup:SetParent(WeakAurasProfilingFrame)
    popup:SetPoint("TOPLEFT", WeakAurasProfilingFrame, "TOPRIGHT", 5, 0)
  else
    popup:SetParent(UIParent)
    if ForeverAurasSaved.ProfilingWindow then
      popup:SetPoint("TOPLEFT", UIParent, "TOPLEFT", ForeverAurasSaved.ProfilingWindow.xOffset or 0, ForeverAurasSaved.ProfilingWindow.yOffset or 0)
    else
      popup:SetPoint("CENTER")
    end
  end

  popup:ClearText()

  PrintOneProfile(popup, "|cff9900ffTotal time:|r", profileData.systems.time)
  PrintOneProfile(popup, "|cff9900ffTime inside WA:|r", profileData.systems.wa)
  popup:AddText(string.format("|cff9900ffTime spent inside WA:|r %.2f%%", 100 * profileData.systems.wa.elapsed / profileData.systems.time.elapsed))

  popup:AddText("")
  popup:AddText("Note: Not every aspect of each aura can be tracked.")

  popup:AddText("")
  popup:AddText("|cff9900ffAuras:|r")
  local total = TotalProfileTime(profileData.auras)
  popup:AddText("Total time attributed to auras: ", floor(total) .. "ms")
  for _, k in ipairs(SortProfileMap(profileData.auras), "spike") do
    PrintOneProfile(popup, k, profileData.auras[k], total)
  end

  if focus.id then
    popup:AddText("")
    popup:AddText("|cff9900ffFocus:|r " .. focus.id)
    local auraTotal = profileData.auras[focus.id] and profileData.auras[focus.id].elapsed or 0
    popup:AddText(("Its aura line: %.2fms. By the place that charged it (times it ran in brackets; a place inside another is counted in both, so the rows overlap and do not add up):"):format(auraTotal))
    for _, k in ipairs(SortProfileMap(focus.sites)) do
      PrintOneProfile(popup, ("%s [%d]"):format(k, focus.sites[k].calls or 0), focus.sites[k], auraTotal > 0 and auraTotal or nil)
    end
    popup:AddText("Systems that ran inside those charges (overlapping too):")
    for _, k in ipairs(SortProfileMap(focus.systems)) do
      PrintOneProfile(popup, ("%s [%d]"):format(k, focus.systems[k].calls or 0), focus.systems[k], auraTotal > 0 and auraTotal or nil)
    end
  end

  -- ForeverAuras 1.2.4 (Dan's collector hitches): who makes the garbage. The collector's work, and
  -- the frames it lands in, grow with what is allocated; these are the systems and auras that
  -- allocated the most while profiling ran (a system inside another is counted in both).
  popup:AddText("")
  popup:AddText("|cff9900ffAllocation:|r net heap growth measured over each system's runs (positive runs summed; a collector step inside a run hides part of it; nested systems overlap), most first")
  local function PrintAllocation(map, label)
    local rows = {}
    for k, v in pairs(map) do
      if (v.alloc or 0) >= 64 and k ~= "wa" and k ~= "time" then rows[#rows + 1] = k end
    end
    sort(rows, function(a, b) return map[a].alloc > map[b].alloc end)
    popup:AddText(label)
    for i = 1, math.min(15, #rows) do
      local v = map[rows[i]]
      popup:AddText(("  %s |cff999999%.0f KB in %d runs (%.1f KB a run)|r"):format(rows[i], v.alloc, v.calls or 1, v.alloc / math.max(1, v.calls or 1)))
    end
    if #rows == 0 then popup:AddText("  (nothing above 64 KB)") end
  end
  PrintAllocation(profileData.auras, "Auras:")
  PrintAllocation(profileData.systems, "Systems:")

  popup:AddText("")
  popup:AddText("|cff9900ffSystems:|r")

  -- make a new table for system data with multiUnits grouped
  local systemRegrouped = {}
  for k, v in pairs(profileData.systems) do
    local event = unitEventToMultiUnit(k)
    if systemRegrouped[event] == nil then
      systemRegrouped[event] = CopyTable(v)
    else
      if v.elapsed then
        systemRegrouped[event].elapsed = (systemRegrouped[event].elapsed or 0) + v.elapsed
      end
      if v.spike then
        systemRegrouped[event].spike = (systemRegrouped[event].spike or 0) + v.spike
      end
    end
  end

  for i, k in ipairs(SortProfileMap(systemRegrouped)) do
    if k ~= "time" and k ~= "wa" then
      PrintOneProfile(popup, k, systemRegrouped[k], profileData.systems.wa.elapsed)
    end
  end

  popup:AddText("")
  popup:AddText("|cff9900ffLibGetFrame:|r (runs in brackets; the net heap growth over its runs, as above)")
  for id, map in pairs(LGF.GetProfileData()) do
    PrintOneProfile(popup, ("%s [%d] +%.0f KB"):format(id, map.calls or 0, map.alloc or 0), map)
  end

  popup:Show()
end

WeakAurasProfilingLineMixin = {
  spikeTooltip = L["Maximum time used on a single frame"],
  timeTooltip = L["Cumulated time used during profiling"],
}

function WeakAurasProfilingLineMixin:Init(e)
  -- button.pct:SetText(pct)
  self.progressBar.name:SetText(e.name)
  self.time:SetText(("%.2fms"):format(e.time))
  self.spike:SetText(ColoredSpike(e.spike))
  self.progressBar:SetValue(e.pct)
end

local COLUMN_INFO = {
  {
    title = L["Name"],
    width = 1,
    attribute = "name",
  },
  {
    title = L["Time"],
    width = 100,
    attribute = "time",
  },
  {
    title = L["Spike"],
    width = 100,
    attribute = "spike",
  },
}

local function ApplyAlternateState(frame, alternate)
  if alternate then
    frame.progressBar:SetStatusBarColor(0.7, 0.7, 0.7, 0.7)
  else
    frame.progressBar:SetStatusBarColor(0.5, 0.5, 0.5, 0.7)
  end
end

local modes = {
  L["Auras"],
  L["Systems"],
}
WeakAurasProfilingMixin = {}

local MinPanelWidth, MinPanelHeight = 500, 300
local MinPanelMinimizedWidth, MinPanelMinimizedHeight = 250, 80
function WeakAurasProfilingMixin:OnShow()
  if self.initialised then
    return
  end
  self.initialised = true

  ButtonFrameTemplate_HidePortrait(self)
  self:SetTitle(L["ForeverAuras Profiling"])
  self:SetSize(MinPanelWidth, MinPanelHeight)
  self.ResizeButton:Init(self, MinPanelMinimizedWidth, MinPanelMinimizedHeight)
  self:SetResizeBounds(MinPanelWidth, MinPanelHeight)
  self.mode = 1
  UIDropDownMenu_SetText(self.buttons.modeDropDown, modes[1])

  self.buttons.report:SetText(L["Report Summary"])
  self.buttons.report.tooltip = L["A detailed overview of your auras and ForeverAuras systems\nCopy the whole text to Weakaura's Discord if you need assistance."]

  local minimizeButton = CreateFrame("Button", nil, self, "MaximizeMinimizeButtonFrameTemplate")
  minimizeButton:SetPoint("RIGHT", self.CloseButton, "LEFT")
  minimizeButton:SetOnMaximizedCallback(function()
    self.minimized = false
    self.buttons:Show()
    self.ResizeButton:Show()
    self.ColumnDisplay:Show()
    self.ScrollBox:Show()
    self.ScrollBar:Show()
    self.stats:Show()
    self:ClearAllPoints()
    self:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", self.right, self.top)
    self:SetHeight(self.prevHeight > MinPanelHeight and self.prevHeight or MinPanelHeight)
    self:SetWidth(self.prevWidth > MinPanelWidth and self.prevWidth or MinPanelWidth)
  end)
  minimizeButton:SetOnMinimizedCallback(function()
    self.minimized = true
    self.buttons:Hide()
    self.ResizeButton:Hide()
    self.ColumnDisplay:Hide()
    self.ScrollBox:Hide()
    self.ScrollBar:Hide()
    self.stats:Hide()
    self.right, self.top = self:GetRight(), self:GetTop()
    self:ClearAllPoints()
    self:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", self.right, self.top)
    self.prevHeight = self:GetHeight()
    self.prevWidth = self:GetWidth()
    self:SetHeight(MinPanelMinimizedHeight)
    self:SetWidth(MinPanelMinimizedWidth)
  end)

  self.ColumnDisplay:LayoutColumns(COLUMN_INFO)

  -- LayoutColumns doesn't handle resizable columns, fix it
  local headers = {}
  for header in self.ColumnDisplay.columnHeaders:EnumerateActive() do
    headers[header:GetID()] = header
  end
  local prevHeader
  for i, header in ipairs_reverse(headers) do
    header:ClearAllPoints()
    local info = COLUMN_INFO[i]
    if info.width ~= 1 then
      header:SetWidth(info.width)
    end
    if prevHeader == nil then
      header:SetPoint("BOTTOMRIGHT", -25, 1)
    else
      header:SetPoint("BOTTOMRIGHT", prevHeader, "BOTTOMLEFT", 2, 0)
    end
    if i == 1 then
      header:SetPoint("BOTTOMLEFT", 3, 0)
    end
    prevHeader = header
  end

  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("WeakAurasProfilingLineTemplate", function(frame, elementData)
    frame:Init(elementData)
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view)
  ScrollUtil.RegisterAlternateRowBehavior(self.ScrollBox, ApplyAlternateState)

  self.sortField = "time"
  self.bars = CreateDataProvider()
  self:SortByColumnIndex(2)
  self.ScrollBox:SetDataProvider(self.bars)

  self:InitDropDown()
  self:InitModeDropDown()
  self:SetScript("OnEvent", AutoStartStopProfiling)

  self:SetScript("OnUpdate", function()
    if profileData.systems.time and profileData.systems.time.count > 0 then
      self:RefreshBars()
    end
  end)
  self:UpdateButtons()
end

function WeakAurasProfilingResultButton_OnClick(self)
  WeakAuras.PrintProfile()
end

local function nextEncounterButton_OnClick(self)
  if currentProfileState ~= "encounter" then
    WeakAuras.StartProfile("encounter")
  end
  local parent = self:GetParent()
  local profilingFrame = parent.dropdown.Button:GetParent():GetParent():GetParent()
  profilingFrame:ResetBars()
  profilingFrame:UpdateButtons()
end

local function nextCombatButton_OnClick(self)
  if currentProfileState ~= "combat" then
    WeakAuras.StartProfile("combat")
  end
  local parent = self:GetParent()
  local profilingFrame = parent.dropdown.Button:GetParent():GetParent():GetParent()
  profilingFrame:ResetBars()
  profilingFrame:UpdateButtons()
end

local function startNowButton_OnClick(self)
  WeakAuras.StartProfile()
  local parent = self:GetParent()
  local profilingFrame = parent.dropdown.Button:GetParent():GetParent():GetParent()
  profilingFrame:ResetBars()
  profilingFrame:UpdateButtons()
end

function WeakAurasProfilingStopButton_OnClick(self)
  if currentProfileState == "profiling" then
    WeakAuras.StopProfile()
  else
    CancelScheduledProfile()
  end
  self:GetParent():GetParent():UpdateButtons()
end

function WeakAurasProfilingMixin:InitDropDown()
  local function Initializer(dropDown, level)
    local entries = {
      {
        text = L["Start Now"],
        func = startNowButton_OnClick,
      },
      {
        text = L["Next Encounter"],
        func = nextEncounterButton_OnClick,
      },
      {
        text = L["Next Combat"],
        func = nextCombatButton_OnClick,
      },
    }
    for _, entry in ipairs(entries) do
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true
      info.text = entry.text
      info.func = entry.func
      UIDropDownMenu_AddButton(info)
    end
  end

  local dropDown = self.buttons.startDropDown
  local dropDownButton = self.buttons.start
  UIDropDownMenu_SetInitializeFunction(dropDown, Initializer)
  UIDropDownMenu_SetDisplayMode(dropDown, "MENU")

  dropDownButton.Text:SetText(L["Start Profiling"])
  dropDownButton:SetScript("OnMouseDown", function(o, button)
    UIMenuButtonStretchMixin.OnMouseDown(dropDownButton, button)
    ToggleDropDownMenu(1, nil, dropDown, dropDownButton, 130, 20)
  end)
end

local function selectMode(self, mode)
  local parent = self:GetParent()
  local profilingFrame = parent.dropdown.Button:GetParent():GetParent():GetParent()
  profilingFrame.mode = mode
  UIDropDownMenu_SetText(profilingFrame.buttons.modeDropDown, modes[mode])
  profilingFrame:ResetBars()
  profilingFrame:RefreshBars(nil, true)
end

function WeakAurasProfilingMixin:InitModeDropDown()
  local function Initializer(dropDown, level)
    for i = 1, 2 do
      local info = UIDropDownMenu_CreateInfo()
      info.text = modes[i]
      info.func = selectMode
      info.checked = i == self.mode
      info.arg1 = i
      UIDropDownMenu_AddButton(info)
    end
  end

  local dropDown = self.buttons.modeDropDown
  UIDropDownMenu_SetWidth(dropDown, 120)
  UIDropDownMenu_JustifyText(dropDown, "LEFT")
  UIDropDownMenu_Initialize(dropDown, Initializer)
end


local lastRefresh
function WeakAurasProfilingMixin:RefreshBars(_, force)
  if force or (not lastRefresh or lastRefresh < GetTime() - 1) then
    lastRefresh = GetTime()
  else
    return
  end

  if not profileData.systems.time then
    return
  end

  local data
  if self.mode == 1 then -- auras
    data = profileData.auras
  elseif self.mode == 2 then -- systems
    data = {}
    for k, v in pairs(profileData.systems) do
      if k ~= "time" and k ~= "wa" then
        local event = unitEventToMultiUnit(k)
        if data[event] == nil then
          data[event] = CopyTable(v)
        else
          if v.elapsed then
            data[event].elapsed = (data[event].elapsed or 0) + v.elapsed
          end
          if v.spike then
            data[event].spike = (data[event].spike or 0) + v.spike
          end
        end
      end
    end
  end

  local total = TotalProfileTime(data)
  for _, name in ipairs(SortProfileMap(data)) do
    if name ~= "time" and name ~= "wa" then
      local elapsed = data[name].elapsed
      local pct = 100 * elapsed / total
      local spike = data[name].spike
      self:UpdateBar(name, elapsed, pct, spike)
    end
  end

  self.bars:Sort()
  if profileData.systems.wa then
    local timespent = profileData.systems.time.elapsed or (debugprofilestop() - profileData.systems.time.start)
    self.stats:SetText(
      ("|cFFFFFFFFTime in WA: %.2fs / %ds (%.1f%%)"):format(profileData.systems.wa.elapsed / 1000, timespent / 1000, 100 * profileData.systems.wa.elapsed / timespent)
    )
  end
end

function WeakAurasProfilingMixin:ResetBars()
  self.bars:Flush()
end

function WeakAurasProfilingMixin:UpdateBar(name, time, pct, spike)
  local elementData = self.bars:FindElementDataByPredicate(function(elementData)
    return elementData.name == name
  end)
  if elementData then
    elementData.time = time
    elementData.pct = pct
    elementData.spike = spike
    local button = WeakAurasProfilingFrame.ScrollBox:FindFrame(elementData)
    if button then
      button.time:SetText(("%.2fms"):format(time))
      button.spike:SetText(ColoredSpike(spike))
      button.progressBar:SetValue(pct)
    end
  else
    self.bars:Insert({ name = name, time = time, pct = pct, spike = spike })
  end
end

function WeakAurasProfilingMixin:SortByColumnIndex(index)
  local previousField = self.sortField
  self.sortField = COLUMN_INFO[index].attribute
  if previousField == self.sortField then
    self.sortDirection = not self.sortDirection
  else
    self.sortDirection = true
  end
  self.bars:SetSortComparator(function(lhs, rhs)
    local field = self.sortField
    local lhsF, rhsF = lhs[field] or 0, rhs[field] or 0
    if type(lhsF) == "string" then
      lhsF = lhsF:lower()
    end
    if type(rhsF) == "string" then
      rhsF = rhsF:lower()
    end
    if lhsF == rhsF then
      return lhs.name < rhs.name
    end
    if self.sortDirection then
      return lhsF > rhsF
    else
      return lhsF < rhsF
    end
  end)
end

function WeakAurasProfilingMixin:UpdateButtons()
  local b = self.buttons
  if currentProfileState == "combat" or currentProfileState == "encounter" then
    b.stop:SetText(L["Cancel"])
    b.stop:Show()
    b.start:Hide()
  elseif currentProfileState == "profiling" then
    b.stop:SetText(L["Stop"])
    b.stop:Show()
    b.start:Hide()
  else
    b.start:Show()
    b.stop:Hide()
    if profileData.systems.time then
      b.report:Show()
    end
  end
end

function WeakAurasProfilingMixin:Start()
  self:Show()
end

function WeakAurasProfilingMixin:Stop()
  WeakAuras.StopProfile()
  self:UpdateButtons()
  self:ResetBars()
end

function WeakAurasProfilingMixin:Toggle()
  if self:IsShown() then
    if currentProfileState == "profiling" then
      self:Stop()
    end
    self:Hide()
  else
    self:Start()
  end
end

local function StopSystem(name, ...)
  Private.StopProfileSystem(name)
  return ...
end

function Private.Profiled(name, func)
  return function(...)
    Private.StartProfileSystem(name)
    return StopSystem(name, func(...))
  end
end

function WeakAurasProfilingColumnDisplay_OnClick(self, columnIndex)
  self:GetParent():SortByColumnIndex(columnIndex)
end

-- ForeverAuras 1.2.4 (Dan's combat-drop hitches): "/fa memscan". The client's
-- collector walks every live Lua object, so a slow combat-drop frame grows
-- with the heap; this walks the addon's own tables and estimates how much
-- each part holds (Lua 5.1, 64-bit: a table header 56 bytes, an array slot
-- 16, a hash node 40, a string 25 plus its length, a function 64; frames
-- themselves are not Lua memory). Every object is counted once, for the
-- first root that reaches it, so the roots are walked from the most
-- specific to the most general.
local memScan = {}
local function ScanValue(v, seen)
  local t = type(v)
  if t == "string" then
    if seen[v] then return 0 end
    seen[v] = true
    return 25 + #v
  elseif t == "function" then
    if seen[v] then return 0 end
    seen[v] = true
    memScan.functions = memScan.functions + 1
    return 64
  elseif t ~= "table" then
    return 0
  end
  if seen[v] then return 0 end
  seen[v] = true
  if issecretvalue and issecretvalue(v) then return 0 end
  memScan.tables = memScan.tables + 1
  local bytes = 56
  local n = #v
  bytes = bytes + n * 16
  for k, x in pairs(v) do
    if type(k) ~= "number" or k > n or k < 1 or k % 1 ~= 0 then bytes = bytes + 40 end
    bytes = bytes + ScanValue(k, seen) + ScanValue(x, seen)
  end
  return bytes
end
local function MB(bytes) return ("%.1f MB"):format(bytes / 1048576) end
function Private.MemoryScan()
  memScan.tables, memScan.functions, memScan.refused = 0, 0, 0
  local seen = {}
  -- (Astra's dev.3 review) both readings are taken BEFORE the scan allocates its own tables, so they
  -- are comparable; the scanner's own allocation is reported separately
  local reported
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    local ok, kb = pcall(GetAddOnMemoryUsage, AddonName)
    if ok and type(kb) == "number" then reported = kb * 1024 end
  end
  local before = collectgarbage("count")
  local started = debugprofilestop()
  local lines = {}
  local total = 0
  -- the global table is never walked (a reference to it would pull in the whole UI)
  seen[_G] = true
  local function Root(name, value)
    if value == nil then return 0 end
    -- a part the client refuses to walk (secret contents) is reported as refused, the scan goes on
    local ok, bytes = pcall(ScanValue, value, seen)
    if not ok then memScan.refused = memScan.refused + 1; return 0 end
    total = total + bytes
    if bytes >= 65536 then lines[#lines + 1] = ("  %s: %s"):format(name, MB(bytes)) end
    return bytes
  end
  -- ForeverAuras (Dan's memory scans): an entry that is a table is measured
  -- field by field (same total, same walk order as ScanValue), and the three
  -- largest fields of the biggest entries are printed under them, so a 6 MB
  -- aura environment says which of its fields the memory sits behind.
  local function ScanFields(value)
    if type(value) ~= "table" or seen[value] or (issecretvalue and issecretvalue(value)) then
      return ScanValue(value, seen)
    end
    seen[value] = true
    memScan.tables = memScan.tables + 1
    local n = #value
    local bytes, fields = 56 + n * 16, {}
    for k, x in pairs(value) do
      local field = 0
      if type(k) ~= "number" or k > n or k < 1 or k % 1 ~= 0 then field = 40 end
      field = field + ScanValue(k, seen) + ScanValue(x, seen)
      bytes = bytes + field
      if field >= 65536 then fields[#fields + 1] = {name = tostring(k), bytes = field} end
    end
    sort(fields, function(a, b) return a.bytes > b.bytes end)
    return bytes, fields
  end
  local function Top(name, map, keyName)
    local parts, entries = {}, 0
    for key, value in pairs(map or {}) do
      entries = entries + 1
      local ok, bytes, fields = pcall(ScanFields, value)
      if not ok then memScan.refused = memScan.refused + 1; bytes = 0 end
      if bytes > 0 then parts[#parts + 1] = {name = key, bytes = bytes, fields = fields} end
    end
    sort(parts, function(a, b) return a.bytes > b.bytes end)
    local sum = 0
    for _, part in ipairs(parts) do sum = sum + part.bytes end
    total = total + sum
    -- (Astra's dev.3 review) all entries are counted; an entry reached by an earlier part first adds nothing here
    lines[#lines + 1] = ("  %s: %s (%d %s, %d first reached here)"):format(name, MB(sum), entries, keyName, #parts)
    for i = 1, math.min(6, #parts) do
      lines[#lines + 1] = ("      %s %s"):format(MB(parts[i].bytes), tostring(parts[i].name))
      local fields = parts[i].fields
      for j = 1, math.min(3, fields and #fields or 0) do
        lines[#lines + 1] = ("          %s .%s"):format(MB(fields[j].bytes), fields[j].name)
      end
    end
  end
  -- 1. the saved displays, by field across all displays
  local db = Private.db
  if db and db.displays then
    local fields, count = {}, 0
    for _, data in pairs(db.displays) do
      count = count + 1
      if type(data) == "table" then
        for key, value in pairs(data) do
          local ok, bytes = pcall(ScanValue, value, seen)
          if not ok then memScan.refused = memScan.refused + 1; bytes = 0 end
          fields[key] = (fields[key] or 0) + bytes + ScanValue(key, seen)
        end
      end
    end
    local parts, sum = {}, 0
    for key, bytes in pairs(fields) do parts[#parts + 1] = {name = key, bytes = bytes}; sum = sum + bytes end
    sort(parts, function(a, b) return a.bytes > b.bytes end)
    total = total + sum
    lines[#lines + 1] = ("  saved displays: %s (%d displays), the largest fields:"):format(MB(sum), count)
    for i = 1, math.min(10, #parts) do
      lines[#lines + 1] = ("      %s %s"):format(MB(parts[i].bytes), tostring(parts[i].name))
    end
    seen[db.displays] = true
    Root("saved data (other than displays)", db)
  end
  -- 2. per-display runtime tables
  -- (Astra's dev.1 review) a root is an accessor returning the CURRENT table; resolved here only
  local function RootTable(name)
    local accessor = Private.memoryRootAccessors and Private.memoryRootAccessors[name]
    if type(accessor) ~= "function" then return nil end
    local ok, value = pcall(accessor)
    if ok and type(value) == "table" then return value end
    return nil
  end
  Top("aura environments (custom code's aura_env)", RootTable("aura environments"), "displays")
  Root("custom action functions", Private.customActionsFunctions)
  local regions = {}
  for id, entry in pairs(Private.regions or {}) do regions[id] = entry.region end
  Top("live displays (regions)", regions, "regions")
  Root("clones", Private.clones)
  Root("trigger states", RootTable("trigger states"))
  Root("loaded displays list", Private.loaded)
  -- (Astra's dev.3 review) the compiled runtime stores: the load functions and the trigger functions
  Root("load functions", RootTable("load functions"))
  Root("load functions (options)", RootTable("load functions (options)"))
  Root("trigger functions (GenericTrigger)", RootTable("trigger functions (GenericTrigger)"))
  Root("loaded trigger events", RootTable("loaded trigger events"))
  -- 3. the options addon, when it has been opened this session
  Root("spell cache (options)", WeakAuras.spellCache)
  Root("options saved data", ForeverAurasOptionsSaved)
  Root("options addon (everything reachable)", WASYNC_OPTIONS_PRIVATE)
  -- 3b. (1.2.4, Dan's session-long growth; corrected per Astra's dev.1 review) additional local caches and
  -- queues of the addon's files, registered as accessors at the end of each file and resolved to their
  -- current tables here; not every closure-owned table, and never function upvalues or native memory
  local handled = {["aura environments"] = true, ["trigger states"] = true, ["load functions"] = true,
    ["load functions (options)"] = true, ["trigger functions (GenericTrigger)"] = true, ["loaded trigger events"] = true,
    ["deferred displays"] = true}
  local names = {}
  for name in pairs(Private.memoryRootAccessors or {}) do if not handled[name] then names[#names + 1] = name end end
  sort(names)
  for _, name in ipairs(names) do Root(name, RootTable(name)) end
  -- 4. the rest of the addon and its libraries
  Root("the addon's other tables (Private)", Private)
  Root("the addon's other tables (WeakAuras)", WeakAuras)
  Root("libraries (LibStub)", LibStub and LibStub.libs)
  Root("the ExecEnv", Private.ExecEnv)
  local took = debugprofilestop() - started
  local scanner = (collectgarbage("count") - before) * 1024
  prettyPrint(("Memory scan: %s estimated for the tables and strings reached (%d tables, %d function objects%s); before the scan the client attributed %s to ForeverAuras and the whole Lua heap was %s. Scan took %.0f ms; the heap moved %s during it (net, the scan's own tables less what the collector took back)."):format(
    MB(total), memScan.tables, memScan.functions, memScan.refused > 0 and (", %d refused"):format(memScan.refused) or "",
    reported and MB(reported) or "?", MB(before * 1024), took, MB(scanner)))
  for _, line in ipairs(lines) do print(line) end
  if Private.CountDeferredDisplays then
    print(("  displays not prepared on this character (never loadable here: other classes' specializations, races, faction, Never): %d"):format(Private.CountDeferredDisplays()))
  end
  print("  (estimates of reachable size, not ownership: fixed per-object overheads, no table capacity; a function's code, upvalues and environment are not walked; a shared object counts for the first part that reaches it; frames and textures are not Lua memory)")
end

-- ForeverAuras 1.2.4 (Dan's session-long growth): the file's own tables are memory scan roots (/fa memscan), resolved to the CURRENT table only when the scan runs (Astra's dev.1 review: a saved reference would pin a table a reset has replaced)
Private.memoryRootAccessors = Private.memoryRootAccessors or {}
Private.memoryRootAccessors["Profiling: profileData"] = function() return profileData end
Private.memoryRootAccessors["Profiling: apiWrapped"] = function() return apiWrapped end
Private.memoryRootAccessors["Profiling: focusEnrolled"] = function() return focusEnrolled end
Private.memoryRootAccessors["Profiling: memScan"] = function() return memScan end
