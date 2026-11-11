-- Modified for ForeverAuras, 2026-10-23.
-- Modifications Copyright (C) 2026 ForeverAuras. Licensed under the GNU GPL v2 (see LICENSE).
if not WeakAuras.IsLibsOK() then return end
local L = WeakAuras.L
local _, Private = ...
-- Frames and hooks from this file are timed by the profiler (see Private.TimedAPI).
local CreateFrame, hooksecurefunc, TimedHookScript, C_Timer = Private.TimedAPI("BlizzardAuraDisplay")
local SharedMedia = LibStub("LibSharedMedia-3.0")
local Display = {}
Private.BlizzardAuraDisplay = Display
local pending = setmetatable({}, {__mode = "k"})
-- ForeverAuras (cell chain, dev.49 review): the generation of a display's
-- settings requests (pending[region] writes made for a NEWER intent: a
-- Modify under restrictions, a repair, a handoff), so a build that finishes
-- later (a reserve completed in the background, a held probe) acknowledges
-- only the request it made and leaves a newer one for the paced apply (the
-- saved table may be the same one, so identity alone cannot tell them apart).
-- Marked by MarkRequest at the request sites; read as a stamp.
local requestStamp = setmetatable({}, {__mode = "k"})
-- ForeverAuras (dev.72): frames a chained display's request has waited in
-- the restricted drain for the members after it (ChainOrderWaits); scoped
-- to the request: a new request starts the count afresh.
local chainOrderWaits = setmetatable({}, {__mode = "k"})
local function MarkRequest(region)
  requestStamp[region] = (requestStamp[region] or 0) + 1
  chainOrderWaits[region] = nil
  return requestStamp[region]
end
-- ForeverAuras: the paced drain of `pending` (defined below; ApplyDisplay queues to it).
local draining, drainingNow, DrainPending = false, false, nil
local drainCursor = 0   -- ForeverAuras (dev.74): where the paced drain's walk of the queue resumes (DrainPending)
-- ForeverAuras (combat-reload probe): displays whose first build under
-- restrictions failed; built again, as new, when the restrictions end (the
-- restriction-end handler moves them to pending). Not tried again before.
local retryAfterRestrictions = setmetatable({}, {__mode = "k"})
-- ForeverAuras (dev.70): chained displays built under aura restrictions as
-- their ordinary (one-spot) construction, to be built again as chained when
-- the restrictions end (RestrictionEndHandoff). Separate from the set-aside
-- builds above: these displays are active and healthy meanwhile.
local chainDeferredRetry = setmetatable({}, {__mode = "k"})
-- Whether a build of this display is queued (SecretAuraFlow.lua reads it to tell a live member from an unloaded one).
function Display.IsBuildPending(region) return pending[region] ~= nil end
-- Every Modern display builds this way under restrictions (1.2.0; developed
-- as a probe on the FA Test displays).
local function ProbeEligible(data)
  return type(data) == "table"
end
-- ForeverAuras: the build reports of the 1.2.0 release candidates (timings,
-- button counts and failures, printed to chat behind a saved flag) are
-- retired for the release; the callers stay as the record of what each
-- step learns. The old flag is cleared so it does nothing if still saved.
-- ForeverAuras (dev.64): the reports print again behind a new saved flag,
-- ForeverAurasSaved.rowCellsDebug ("/fa cells debug on|off"; read when a
-- report is made, so no reload): Dan's combat reload of the row cells
-- (dev.63) showed the chained members only after combat, and the stop's
-- reason is in these reports. Printed under pcall: a report may carry a
-- client error text.
-- ForeverAuras (1.3.8, Dan's combat garbage): the reports on the hot paths (every unit refresh,
-- every instance, every target change) formatted their text before this function dropped it, about
-- 4 KB of strings per 40-slot pass with the flag off. Those sites ask BuildReporting() first.
local function BuildReporting()
  return type(ForeverAurasSaved) == "table" and ForeverAurasSaved.rowCellsDebug == true
end
Display.BuildReporting = BuildReporting   -- (the hot sites read it through Display: a review harness runs them as slices)
local function CombatBuildReport(msg)
  if BuildReporting() then
    pcall(print, "|cff88ccff" .. L["FA build:"] .. "|r " .. tostring(msg))
  end
end
Display.BuildReport = CombatBuildReport   -- ForeverAuras (dev.80): the chain's refusals and measurement failures report through it too
do
  -- The saved variables arrive after this file runs: the retired flag is cleared at login.
  local clearFlag = CreateFrame("Frame")
  clearFlag:RegisterEvent("PLAYER_LOGIN")
  clearFlag:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if type(ForeverAurasSaved) == "table" then ForeverAurasSaved.debugCombatBuild = nil end
  end)
end
-- The frames of a probe build are owned by a ledger, per region, from the
-- moment each is allocated until it is cleaned: every aura container made
-- for the region while the build runs (Display.CreateAuraContainer notes
-- them), the unit glow container, the Missing clip, slot and stage
-- (Display.NoteAllocation), whether or not the constructor that made them
-- got as far as attaching them to the instance. Cleaning is tried at
-- restriction end, on release and before a normal build, independently of
-- whether the display is rebuilt; a frame the client has locked
-- (Display.Locked) is kept for the next try, never taken for cleaned, and
-- a rebuild waits while any is kept. The ledger is weak by region.
local abandonedFrames = setmetatable({}, {__mode = "k"})
-- Called by every allocation of a frame that belongs to an instance; a
-- region being built by the probe (region.faProbeAllocations) keeps the list.
function Display.NoteAllocation(region, frame)
  -- ForeverAuras (dev.35 review): a probe build's list, or the attempt
  -- ledger of an ordinary build's reserve instance (DrainInstanceQueues).
  local list = region and (region.faProbeAllocations or region.faAttemptAllocations)
  if list and frame then list[#list + 1] = frame end
end
local function RetainFrame(region, frame)
  if not frame then return end
  local ledger = abandonedFrames[region] or {}
  abandonedFrames[region] = ledger
  for _, held in ipairs(ledger) do if held == frame then return end end
  ledger[#ledger + 1] = frame
end
local function RetainAllocations(region)
  local list = region.faProbeAllocations
  region.faProbeAllocations = nil
  for _, frame in ipairs(list or {}) do RetainFrame(region, frame) end
end
-- Private duration bindings are not frames and survive container retirement.
-- Keep refused disables on the same cleanup lifetime as abandoned frames.
local abandonedGlowBindings = {}
local function RetireInstanceGlowBindings(region, instance)
  if not Display.DisableGlowBinding then return end
  for _, record in ipairs(instance.buttons or {}) do
    local owner = record.glowBinding
    if owner and owner.binding then
      -- Capture this owner, not the record's possibly replaced future owner.
      local entry = {glowBinding = owner}
      local ok = Display.DisableGlowBinding(entry)
      local held = abandonedGlowBindings[region]
      if not ok then
        held = held or {}
        abandonedGlowBindings[region] = held
        held[owner] = entry
        abandonedFrames[region] = abandonedFrames[region] or {}
      elseif held then
        held[owner] = nil
        if not next(held) then abandonedGlowBindings[region] = nil end
      end
    end
  end
end
-- ForeverAuras (dev.36 review): the frames an instance is known to own, as a
-- set, so an attempt's allocation ledger can tell a frame a kept instance
-- took over from one left unattached (FailReserveAttempt).
local function InstanceFrames(instance, into)
  into = into or {}
  local function add(frame) if frame then into[frame] = true end end
  add(instance.container); add(instance.flowShadow); add(instance.flowMeasure); add(instance.unitGlow and instance.unitGlow.container); add(instance.missingSlot)
  local single = instance.single
  if single then
    add(single.stage)
    local missing = single.missing
    if missing then add(missing.container); add(missing.clip); add(missing.presence); add(missing.flowShadow) end
  end
  for _, entry in pairs(instance.flowRemainSlots or {}) do add(entry.holder) end
  return into
end
-- ForeverAuras (dev.37 review): the ONE ledger-finalization rule for a
-- reserve attempt's allocations (queue.ledger, filled by NoteAllocation):
-- at every terminal or discard transition (failure, success, queue replaced
-- by a new apply, stale/inactive disposal in the drain, editor flush,
-- release), each frame allocated during the attempt that no surviving
-- instance owns (InstanceFrames) is retained for cleaning; frames a kept
-- instance owns are untouched. A pause for the frame budget keeps the
-- ledger. Success is not proof of ownership: EnsureMissing allocates a
-- presence sibling, catches its refusal and returns without attaching it.
local function ReconcileLedger(region, queue)
  local native = region and region.blizzardAuraDisplay
  if region then region.faAttemptAllocations = nil end
  local ledger = queue and queue.ledger
  if not ledger then return end
  queue.ledger = nil
  local kept = {}
  for _, instance in ipairs(native and native.instances or {}) do InstanceFrames(instance, kept) end
  for _, frame in ipairs(ledger) do if not kept[frame] then RetainFrame(region, frame) end end
end
-- The frames an instance is known to own (the allocation list covers a
-- build's own; an instance kept from an earlier build has none there).
local function RetainInstanceFrames(region, instance)
  RetireInstanceGlowBindings(region, instance)
  RetainFrame(region, instance.container)
  RetainFrame(region, instance.flowShadow)
  RetainFrame(region, instance.flowMeasure)   -- ForeverAuras (dev.78): the end measurement's container
  RetainFrame(region, instance.unitGlow and instance.unitGlow.container)
  RetainFrame(region, instance.missingSlot)
  local single = instance.single
  if single then
    RetainFrame(region, single.stage)
    local missing = single.missing
    if missing then
      RetainFrame(region, missing.container)
      RetainFrame(region, missing.clip)
      RetainFrame(region, missing.presence)
      RetainFrame(region, missing.flowShadow)
    end
  end
end
local function CleanFrame(frame)
  if Display.Locked(frame) then return false end
  return pcall(function()
    if frame.SetEnabled then frame:SetEnabled(false) end
    frame:Hide()
    Display.RetireFrame(frame)
  end)
end
-- Cleans what it can; returns true when nothing is left in the ledger.
local function CleanAbandoned(region)
  local list = abandonedFrames[region]
  local bindings = abandonedGlowBindings[region]
  if not list and not bindings then return true end
  if bindings then
    for owner, entry in pairs(bindings) do
      if Display.DisableGlowBinding(entry) then bindings[owner] = nil end
    end
    if not next(bindings) then abandonedGlowBindings[region], bindings = nil, nil end
  end
  local kept = {}
  for _, frame in ipairs(list or {}) do
    if not CleanFrame(frame) then kept[#kept + 1] = frame end
  end
  abandonedFrames[region] = (#kept > 0 or bindings) and kept or nil
  return #kept == 0 and bindings == nil
end
-- Containers locked in combat: hidden, or given their units, once it ends.
local lockedHide = setmetatable({}, {__mode = "k"})
local lockedUnits = setmetatable({}, {__mode = "k"})
-- ForeverAuras (1.3.6-dev.10, Astra's nameplate combat-end review): the unit
-- tokens a display still owes a refresh for, per region, when a targeted unit
-- event (a plate added or removed, a plate changing side) met a container the
-- client would not let the addon touch. Before, that refusal marked the whole
-- region (lockedUnits) and the restriction-end drain refreshed all its slots
-- (40 for a nameplate display) for one plate's worth of work. lockedUnits
-- keeps its meaning for refusals that concern the whole display (geometry,
-- erasers, status, a full refresh).
local pendingTokens = setmetatable({}, {__mode = "k"})
local pendingSounds = {}
local activeRegions = {}
-- ForeverAuras: the active Modern displays, for the Missing veil across
-- loading screens (SecretAuraSingle.lua, Display.SettleMissing).
function Display.ActiveRegions() return pairs(activeRegions) end
-- For the hitch report: how many Modern displays are active and how many
-- native aura containers they hold (shown ones counted separately).
function Display.CountContainers()
  local displays, containers, shown = 0, 0, 0
  for region in pairs(activeRegions) do
    displays = displays + 1
    local native = region.blizzardAuraDisplay
    for _, instance in ipairs(native and native.instances or {}) do
      containers = containers + 1
      if instance.visible then shown = shown + 1 end
    end
  end
  return displays, containers, shown
end
local unitGlowFrameLevel = 8

Display.units = {
  player = L["Player"], target = L["Target"], focus = L["Focus"], pet = L["Pet"], mouseover = L["Mouseover"],
  targettarget = L["Target of Target"], focustarget = L["Target of Focus"], pettarget = L["Pet Target"], group = L["Smart Group"],
  party = L["Party"], raid = L["Raid"], boss = L["Boss"], arena = L["Arena"], nameplate = L["Nameplate"],
  member = L["Specific Unit"],
}

local specificUnitPatterns = {
  {"^party[1-4]$", "party"}, {"^partypet[1-4]$", "party"},
  {"^raid(%d+)$", "raid", 40}, {"^raidpet(%d+)$", "raid", 40},
  {"^boss[1-8]$", "boss"}, {"^arena[1-5]$", "arena"},
}

function Display.SpecificUnit(trigger)
  local text = type(trigger) == "table" and type(trigger.specificUnit) == "string" and trigger.specificUnit:lower():match("^%s*(%S+)%s*$")
  if not text then return end
  for _, pattern in ipairs(specificUnitPatterns) do
    local number = text:match(pattern[1])
    if number then
      local n = tonumber(number)
      if not pattern[3] or (n and n >= 1 and n <= pattern[3]) then return text, pattern[2] end
    end
  end
end

function Display.UnitCategory(trigger)
  if type(trigger) ~= "table" then return end
  if trigger.unit == "member" then return select(2, Display.SpecificUnit(trigger)) end
  return trigger.unit
end

Display.booleanFilters = {
  {"isFromPlayerOrPlayerPet", L["Cast by a Player"], L["Auras cast by any player or player pet, not only yours. For your own auras, use Own Only."]},
  {"canApplyAura", L["Can Apply Aura"], L["Auras Blizzard says your character can apply."]},
  {"isStealable", L["Is Stealable"], L["Buffs that can be stolen with abilities such as Spellsteal."]},
  {"isBossAura", L["Is Boss Aura"], L["Auras Blizzard identifies as boss auras."]},
  {"isRoleAura", L["Role aura"], L["Auras Blizzard marks as relevant to your role."]},
  {"isBossOrRoleAura", L["Boss or role aura"], L["Auras Blizzard identifies as boss auras or marks as relevant to your role."]},
  {"isPriorityAura", L["Priority debuff"], L["Debuffs Blizzard marks as high priority."]},
  {"nameplateShowAll", L["Marked for all nameplates"], L["Auras Blizzard marks for display on all nameplates."]},
  {"nameplateShowPersonal", L["Marked for personal debuff display"], L["Auras Blizzard marks for its personal-debuff display on nameplates."]},
}

-- The saved Aura (Modern) trigger that drives the display. Options write to
-- this table; GetTrigger below may return a working copy.
-- A cut that starts between screen pixels redraws what it holds blurred; the
-- engine rounds it to whole pixels, also where its place cannot be read.
function Display.ClipChildren(frame)
  frame:SetClipsChildren(true)
  if frame.SetRoundLayoutToNearestPixel then frame:SetRoundLayoutToNearestPixel(true) end
end

function Display.GetSavedTrigger(data)
  if not data or type(data.triggers) ~= "table" then return end
  local source = data.progressSource and data.progressSource[1] or -1
  if source == 0 then return end
  if source < 0 then source = data.triggers.activeTriggerMode or -1 end
  if source < 0 then source = (Private.GetActiveTriggerFor and Private.GetActiveTriggerFor(data.id)) or 1 end
  local entry = data.triggers[source]
  local trigger = type(entry) == "table" and entry.trigger
  if trigger and trigger.type == "secretAura" then return trigger end
end

function Display.GetTrigger(data, displayFilters)
  local trigger = Display.GetSavedTrigger(data)
  if trigger then
    if displayFilters then
      trigger = CopyTable(trigger)
      trigger.processedAuraType = nil
      if trigger.sortMethod == "UnitFrameDebuff" then trigger.sortMethod = "Default" end
      for _, field in ipairs(Display.processingOptions) do trigger[field[1]] = nil end
    end
    if trigger.processedAuraType or trigger.sortMethod == "UnitFrameDebuff" then
      trigger = CopyTable(trigger)
      trigger.processedAuraType = nil
      if trigger.sortMethod == "UnitFrameDebuff" then trigger.sortMethod = "Default" end
    end
    return trigger
  end
end

function Display.HasTrigger(data)
  for _, entry in ipairs(data and data.triggers or {}) do
    if type(entry) == "table" and entry.trigger and entry.trigger.type == "secretAura" then return true end
  end
  return false
end

function Display.UsesNameplates(data)
  local trigger = Display.GetTrigger(data)
  return (trigger and trigger.unit == "nameplate") or data.anchorFrameType == "NAMEPLATE"
end

local function IsNameplateFilter(key)
  return key == "nameplateShowAll" or key == "nameplateShowPersonal"
end
Display.dispelTypes = {Magic = L["Magic"], Curse = L["Curse"], Disease = L["Disease"], Poison = L["Poison"], Bleed = L["Bleed"], [""] = L["Enrage"]}
Display.nativeFilters = {
  {L["PLAYER"], L["Own Only"], L["Auras cast by you, your pet or your vehicle."]},
  {L["RAID"], L["Can apply / dispel"], L["Buffs you can apply, or debuffs you can dispel."]},
  {L["CANCELABLE"], L["Cancelable"], L["Auras that the player can cancel."]},
  {L["EXTERNAL_DEFENSIVE"], L["External defensive"], L["Auras Blizzard classifies as external defensives."]},
  {L["CROWD_CONTROL"], L["Crowd control"], L["Auras with a crowd-control effect, such as a stun or fear."]},
  {L["RAID_IN_COMBAT"], L["Shown on raid frames in combat"], L["Auras flagged by Blizzard for raid-frame display in combat."]},
  {L["RAID_PLAYER_DISPELLABLE"], L["Dispellable by someone in your raid"], L["Includes helpful enrages on enemies."]},
  {L["BIG_DEFENSIVE"], L["Big defensive"], L["Auras Blizzard classifies as big defensives."]},
  {L["IMPORTANT"], L["Important aura"], L["Blizzard's important-aura flag, including non-stealable enemy buffs shown on nameplates."]},
  {L["DISPELLABLE"], L["Dispellable"], L["Dispellable regardless of your or your raid's current abilities."]},
}

function Display.FilterApplies(key, trigger)
  local buffOnly = {CANCELABLE=true, EXTERNAL_DEFENSIVE=true, BIG_DEFENSIVE=true, IMPORTANT=true, isStealable=true}
  local debuffOnly = {CROWD_CONTROL=true, isPriorityAura=true, isBossAura=true, isRoleAura=true, isBossOrRoleAura=true}
  return not (buffOnly[key] and trigger.debuffType ~= "HELPFUL") and not (debuffOnly[key] and trigger.debuffType ~= "HARMFUL")
end

local function FilterString(trigger)
  local filters = {trigger.debuffType}
  for _, field in ipairs(Display.nativeFilters) do
    local value = (trigger.nativeFilters or {})[field[1]]
    if value ~= nil and Display.FilterApplies(field[1], trigger) then filters[#filters + 1] = (value and "" or "!") .. field[1] end
  end
  if trigger.includeNameplateOnly and trigger.unit == "nameplate" then filters[#filters + 1] = "INCLUDE_NAME_PLATE_ONLY" end
  return table.concat(filters, "|")
end
Display.sortMethods = {
  Default = L["Blizzard default"], BigDefensive = L["Big defensives"], UnitFrameDebuff = L["Blizzard debuff order"],
  ImportantOnly = L["Importance only"], Expiration = L["Remaining time (Blizzard priority)"],
  ExpirationOnly = L["Remaining time"], Name = L["Name (Blizzard priority)"], NameOnly = L["Name"],
  AuraInstanceIDOnly = L["Order applied"],
}
Display.processedTypes = {any = L["Any (no classification)"], Buff = L["Buff"], Debuff = L["Debuff"], Dispel = L["Dispellable raid debuff"]}
Display.processingOptions = {
  {"displayOnlyDispellableDebuffs", L["Use dispellable-debuff classification"]},
  {"ignoreBuffs", L["Ignore buff classification"]},
  {"ignoreDebuffs", L["Ignore debuff classification"]},
  {"ignoreDispelDebuffs", L["Ignore dispel classification"]},
}

-- Spell Lists: a trigger can take its spell IDs (and a name, icon and label)
-- from a list another aura sets at run time with
-- ForeverAuras.SetAuraSpellList(key, list) (SecretAuraTrigger.lua), so a few
-- displays can stand in for many: a backend assigns one item per display from
-- its own options. An unset or empty list matches nothing.
Display.spellLists = {}
function Display.UsesSpellList(trigger)
  return type(trigger) == "table" and type(trigger.secretSpellList) == "string" and trigger.secretSpellList ~= ""
end
function Display.SpellList(trigger)
  return Display.UsesSpellList(trigger) and Display.spellLists[trigger.secretSpellList] or nil
end

function Display.UsesSpellIDs(trigger)
  if Display.UsesSpellList(trigger) then return true end
  return trigger.secretUseSpellIDs ~= false and (#(trigger.auraspellids or {}) > 0 or trigger.secretUseSpellIDs == true)
end

-- Keep the original exact-ID flag and storage unchanged for existing auras.
function Display.UsesRankSpellIDs(trigger)
  return trigger.secretUseRankSpellIDs == true
end

function Display.GetSpellIDs(trigger, expandRanks)
  local ids, seen = {}, {}
  local function Add(value)
    local id = tonumber(value)
    if id and id > 0 and id < 2147483647 and id == math.floor(id) and not seen[id] then
      seen[id] = true; ids[#ids + 1] = id
    end
  end
  if Display.UsesRankSpellIDs(trigger) then
    for _, value in ipairs(trigger.auraRankSpellIDs or {}) do
      local id = tonumber(value)
      if id and id > 0 and id < 2147483647 and id == math.floor(id) then
        Add(id)
        if expandRanks then
          for _, rankID in ipairs(Private.GetAuraSpellRanks(id) or {}) do Add(rankID) end
        end
      elseif type(value) == "string" and value ~= "" and Private.SpellIDsByName then
        -- ForeverAuras: an aura name typed into Name(s), as in Aura (Legacy):
        -- every spell ID with that name (its ranks and variants share it).
        for _, nameID in ipairs(Private.SpellIDsByName(value) or {}) do Add(nameID) end
      end
    end
  end
  local list = Display.SpellList(trigger)
  if list then
    for _, value in ipairs(list.spellIDs) do Add(value) end
  end
  -- Same name: every spell ID with the same name as a Spell ID(s) or Spell
  -- List selection (hidden ranks and server variants missing from the rank
  -- data), from the client's own spell data (Private.SameNameSpellIDs,
  -- SecretAuraRanks.lua). Exact Spell ID(s) are exact, as in Aura (Legacy):
  -- they are added after the expansion so no name is taken from them.
  if expandRanks and Display.UsesNames(trigger) and Private.SameNameSpellIDs then
    local selected = {}
    for index, id in ipairs(ids) do selected[index] = id end
    for _, id in ipairs(selected) do
      for _, same in ipairs(Private.SameNameSpellIDs(id) or {}) do Add(same) end
    end
  end
  if Display.UsesSpellIDs(trigger) then
    for _, value in ipairs(trigger.auraspellids or {}) do Add(value) end
  end
  return ids
end

-- Same-name matching applies to Spell ID(s) and Spell Lists, as Aura (Legacy)
-- matches by name; Exact Spell ID(s) match only the IDs entered.
function Display.UsesNames(trigger)
  return type(trigger) == "table" and (Display.UsesRankSpellIDs(trigger) or Display.UsesSpellList(trigger))
end

function Display.UsesExcludedSpellIDs(trigger)
  return trigger.secretUseExcludedSpellIDs ~= false and (#(trigger.excludedAuraSpellIDs or {}) > 0 or trigger.secretUseExcludedSpellIDs == true)
end

function Display.HasAdditionalFilters(trigger)
  if next(trigger.nativeFilters or {}) then return true end
  if Display.UsesExcludedSpellIDs(trigger) or next(trigger.includeDispelTypes or {})
    or next(trigger.excludeDispelTypes or {}) or Display.TotalFilter(trigger) ~= nil
    or (trigger.processedAuraType and trigger.processedAuraType ~= "any") then return true end
  for _, field in ipairs(Display.booleanFilters) do
    if trigger[field[1]] ~= nil and (not IsNameplateFilter(field[1]) or trigger.unit == "nameplate") then return true end
  end
  return false
end

-- Elements are ordered back to front, independently of the aura's frame strata.
function Display.Elements(settings)
  if not settings.elements then
    settings.elements = {"border"}
    if settings.glow then table.insert(settings.elements, "glow") end
    if settings.duration ~= false then table.insert(settings.elements, "duration") end
    if settings.stacks ~= false then table.insert(settings.elements, "stack") end
    if settings.label and settings.label ~= "" then table.insert(settings.elements, "label") end
  end
  return settings.elements
end

-- The holder of everything FA draws on a button besides the icon and
-- cooldown (borders, texts, glows, condition highlights). A Start animation
-- only reaches the icon and cooldown Blizzard draws, so the holder fades in
-- over the animation instead (BuildAuraAnimation).
-- ForeverAuras: the frame a button's artwork is anchored to: its box
-- (BuildButton), the same rectangle as the button unless a Grid member's own
-- X/Y Offset moves it (SetBoxOffset); the button itself where there is no box
-- (editor samples, SecretAuraPreview.lua).
function Display.Box(native)
  return native.box or native.button
end

-- ForeverAuras: moves a button's artwork by (x, y) inside the button, for a
-- Grid member's own X/Y Offset: the client places the button in its cell and
-- the artwork is drawn offset from it, so other members' cells do not move.
-- Only on buttons built with a box; a locked box (made under aura
-- restrictions) is left as it is. Returns true when the offset is in place
-- (applied now, or already so), false when the client refused it, so the
-- Grid's completion accounting sees a refused offset (dev.5 review).
function Display.SetBoxOffset(native, x, y)
  local box = native.box
  if not box then return true end
  x, y = tonumber(x) or 0, tonumber(y) or 0
  if native.boxX == x and native.boxY == y then return true end
  -- The memo is dropped before the anchors are touched and set only once
  -- both points are in place: a refusal between the two leaves a box with
  -- no anchors, which no earlier offset may be taken to describe (dev.6 review).
  native.boxX, native.boxY = nil, nil
  local ok = pcall(function()
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", native.button, "TOPLEFT", x, y)
    box:SetPoint("BOTTOMRIGHT", native.button, "BOTTOMRIGHT", x, y)
  end)
  if ok then native.boxX, native.boxY = x, y end
  return ok
end

function Display.ElementHolder(native)
  if not native.elements then
    native.elements = CreateFrame("Frame", nil, native.gateClip or native.button)
    native.elements:SetAllPoints(Display.Box(native))
    native.elements:EnableMouse(false)
  end
  return native.elements
end

local function ElementFrame(native, key)
  native.elementFrames = native.elementFrames or {}
  if not native.elementFrames[key] then
    -- Icons: every element lives in the Total Duration gate clip (SecretAuraSingle.lua).
    -- The icon's own frame hangs on the clip; the rest on the elements holder.
    local frame = CreateFrame("Frame", nil, key == "sharedBase" and (native.gateClip or native.button) or Display.ElementHolder(native))
    frame:SetAllPoints(Display.Box(native))
    frame:EnableMouse(false)
    native.elementFrames[key] = frame
  end
  return native.elementFrames[key]
end

function Display.Migrate(data)
  local legacy = data.blizzardAuraDisplay
  if data.blizzardAuraDisplay and data.blizzardAuraDisplay.enabled and data.triggers and #data.triggers == 1
    and data.triggers[1].trigger.type == "aura2" then
    data.triggers[1].trigger.type = "secretAura"
    data.blizzardAuraDisplay.enabled = nil
  end
  for _, entry in ipairs(data.triggers or {}) do
    if type(entry) == "table" and entry.trigger and entry.trigger.type == "secretAura" then
      entry.trigger.unit = entry.trigger.unit or "player"
      entry.trigger.debuffType = entry.trigger.debuffType or "HELPFUL"
      entry.trigger.auraspellids = entry.trigger.auraspellids or {}
      entry.trigger.useExactSpellId = true
      entry.trigger.onlyMaw = nil
      -- Settings from pre-release test builds (SecretAuraSingle.lua).
      Display.MigrateSingle(data, entry.trigger)
      -- Maximum Duration becomes Total Duration.
      Display.MigrateTotal(entry.trigger)
      data.blizzardAuraDisplay = data.blizzardAuraDisplay or {}
      data.blizzardAuraDisplay.enabled = nil
    end
  end
  if Display.HasTrigger(data) then
    Display.MigrateAppearance(data, legacy)
    for _, element in ipairs(data.subRegions or {}) do
      if element.type == "subtext" then
        if element.text_alpha == nil then element.text_alpha = 1 end
        if element.text_anchorXOffset == nil then element.text_anchorXOffset = element.anchorXOffset or 0 end
        if element.text_anchorYOffset == nil then element.text_anchorYOffset = element.anchorYOffset or 0 end
      end
    end
    Display.MigrateSounds(data)
    data.blizzardAuraDisplay.soundSpellIDs = nil
    data.blizzardAuraDisplay.soundIgnoreDisplayFilters = nil
  end
end

-- ForeverAuras: Texture displays draw on the aura button too (a plain
-- texture shown with the aura; SecretAuraAppearance.lua, StyleAppearance).
local eligibleTypes = {icon = true, aurabar = true, text = true, progresstexture = true, texture = true}
Display.eligibleTypes = eligibleTypes
function Display.Eligible(data)
  return data and eligibleTypes[data.regionType] == true and Display.GetTrigger(data) ~= nil
end

function Display.Enabled(data)
  return Display.Eligible(data)
end

local function UnitCount(unit)
  if unit == "group" or unit == "raid" or unit == "nameplate" then return 40 end
  if unit == "party" or unit == "arena" then return 5 end
  if unit == "boss" then return 10 end
  return 1
end

local groupModes = {group = true, party = true, raid = true}

-- "PlayersAndPets" or "PetsOnly" when a group trigger includes pets, else nil.
function Display.IncludesPets(trigger)
  if type(trigger) ~= "table" or not trigger.useIncludePets or not groupModes[trigger.unit] then return end
  return trigger.includePets == "PetsOnly" and "PetsOnly" or "PlayersAndPets"
end

local function PetToken(token)
  if token == "player" then return "pet" end
  local kind, index = token:match("^(%a+)(%d+)$")
  if kind == "party" or kind == "raid" then return kind .. "pet" .. index end
end

local function Capacity(trigger, data)
  -- Missing and Always watch exactly one unit token, except on unit frames and
  -- nameplates. (Remaining Time on Icons is validated to single units, which
  -- give 1 below; on other display types it is a list.)
  if Display.ShowOn and Display.ShowOn(trigger) ~= "showOnActive"
    and not (data and Display.UnitPlacedMissing and Display.UnitPlacedMissing(data, trigger)) then return 1 end
  local count = UnitCount(trigger.unit)
  if Display.IncludesPets(trigger) == "PlayersAndPets" then count = count * 2 end
  return count
end

local function MatchesUnitName(trigger, unit)
  if not trigger.useUnitNames then return true end
  local name = Private.ExecEnv.UnitName(unit)
  if issecretvalue(name) or not name then return false end
  name = strlower(name)
  for _, wanted in ipairs(trigger.unitNames or {}) do
    if name == strlower(wanted) then return true end
  end
  return false
end

-- Filter by Hostility, as on Aura (Legacy) (same useHostility/hostility
-- fields): nameplate tokens cover friends and enemies alike, and a target,
-- focus, mouseover, target-of or specific unit can be either side. True when
-- the unit's side matches; a side the client hides (a secret answer) passes.
-- Units the filter is offered for (SecretAuraTriggerOptions.lua shows it for these).
Display.hostilityUnits = {nameplate = true, target = true, focus = true, mouseover = true,
  targettarget = true, focustarget = true, pettarget = true, member = true}
-- Units a class filter is offered for besides groups: those that can be a player.
Display.classUnits = {nameplate = true, target = true, focus = true, mouseover = true,
  targettarget = true, focustarget = true, pettarget = true, member = true, arena = true}
function Display.UsesHostility(trigger)
  return type(trigger) == "table" and Display.hostilityUnits[trigger.unit] == true and trigger.useHostility == true
end
function Display.HostilityMatches(trigger, unit)
  if not unit or not Display.UsesHostility(trigger) then return true end
  local hostile = UnitCanAttack("player", unit)
  if issecretvalue(hostile) then return true end
  return (hostile == true) == (trigger.hostility ~= "friendly")
end

-- Class filter (useUnitClass/unitClass): offered for groups and for units
-- that can be a player (Display.classUnits). UnitClass stays readable for
-- group members; a hidden answer fails the filter rather than guessing.
-- A group pet is judged by its owner (the roster entry the filter selected).
local function Controlling(unit)
  return WeakAuras.petUnitToUnit and WeakAuras.petUnitToUnit[unit] or unit
end

local function ClassMatches(trigger, unit)
  if not trigger.useUnitClass then return true end
  if not (groupModes[trigger.unit] or Display.classUnits[trigger.unit]) then return true end
  unit = Controlling(unit)
  local ok, _, class = pcall(UnitClass, unit)
  return ok and type(class) == "string" and not issecretvalue(class) and (trigger.unitClass or {})[class] == true
end

-- Ignore Self: the player's own token (its pet follows in a group, as pets
-- are added after the filter). The client's own UnitIsUnit is asked, not the
-- cached compatibility wrapper, so a changed token never inherits an answer;
-- a hidden answer counts as not self.
local function IsSelf(trigger, unit)
  if not trigger.ignoreSelf then return false end
  if not (groupModes[trigger.unit] or Display.hostilityUnits[trigger.unit]) then return false end
  unit = Controlling(unit)
  local ok, isSelf = pcall(UnitIsUnit, "player", unit)
  return ok and not issecretvalue(isSelf) and isSelf == true
end

-- Whether a bound unit may draw (and sound) for this trigger: hostility,
-- class and self, as the options offer them for the trigger's unit. Group
-- tokens were already filtered by UnitTokens; this is what judges single
-- units and nameplates in their slots.
function Display.UnitEligible(trigger, unit)
  if not unit or type(trigger) ~= "table" then return true end
  return Display.HostilityMatches(trigger, unit) and ClassMatches(trigger, unit) and not IsSelf(trigger, unit)
end

-- True when a change of the unit a token stands for can change eligibility
-- (the sounds registered for it follow, SyncSounds).
function Display.UsesUnitEligibility(trigger)
  return type(trigger) == "table" and (Display.UsesHostility(trigger)
    or (trigger.useUnitClass and Display.classUnits[trigger.unit] == true)
    or (trigger.ignoreSelf and Display.hostilityUnits[trigger.unit] == true)) or false
end

local function UnitTokens(trigger)
  local unit = trigger.unit
  local result = {}
  if unit == "member" then
    result[1] = Display.SpecificUnit(trigger)
    return result
  end
  if unit == "group" then unit = IsInRaid() and "raid" or "party" end
  if unit == "party" then
    result[1] = "player"
    for i = 1, GetNumSubgroupMembers() do result[#result + 1] = "party" .. i end
  elseif unit == "raid" then
    if IsInRaid() then for i = 1, GetNumGroupMembers() do result[i] = "raid" .. i end end
  elseif unit == "boss" or unit == "arena" or unit == "nameplate" then
    for i = 1, UnitCount(unit) do result[i] = unit .. i end
  else
    result[1] = unit
  end
  -- Group members a filter leaves out get no part of the display at all (no
  -- slot in a row): names, assigned roles, class (useUnitClass/unitClass, as
  -- Aura (Legacy)'s Filter by Class) and Ignore Self (the player's own token;
  -- the player's pet follows, as pets are added after). Class is read with
  -- UnitClass, which stays readable for group members; a hidden answer drops
  -- the member rather than guessing.
  -- Only group tokens are dropped from the list: the roster decides the
  -- list, and it is rebound on roster, role and name events. Single units
  -- and nameplates keep one token per slot (a nameplate's container is its
  -- slot, so a shorter list would move every plate's display); they are
  -- judged per unit instead (Display.UnitEligible, used by the binding).
  local group = groupModes[trigger.unit] == true
  if group and (trigger.useUnitNames or trigger.useUnitRoles or trigger.useUnitClass or trigger.ignoreSelf) then
    local filtered = {}
    for _, token in ipairs(result) do
      local role = trigger.useUnitRoles and UnitGroupRolesAssigned(token)
      if ClassMatches(trigger, token) and not IsSelf(trigger, token) and MatchesUnitName(trigger, token)
        and (not trigger.useUnitRoles or (not issecretvalue(role) and (trigger.unitRoles or {})[role])) then
        filtered[#filtered + 1] = token
      end
    end
    result = filtered
  end
  local pets = Display.IncludesPets(trigger)
  if pets then
    local withPets = {}
    for _, token in ipairs(result) do
      if pets == "PlayersAndPets" then withPets[#withPets + 1] = token end
      withPets[#withPets + 1] = PetToken(token)
    end
    result = withPets
  end
  return result
end

Display.UnitTokens = UnitTokens

function Display.GetPreviewUnit(data)
  local trigger = Display.GetTrigger(data)
  if not trigger then return "player" end
  for _, unit in ipairs(UnitTokens(trigger)) do
    if UnitExists(unit) and (data.anchorFrameType ~= "UNITFRAME" or WeakAuras.GetUnitFrame(unit)) then return unit end
  end
  return "player"
end

function Display.Validate(data)
  if not Display.Eligible(data) then
    if Display.HasTrigger(data) and not eligibleTypes[data.regionType] then
      return L["Aura (Modern) works on Icon, Progress Bar, Progress Texture, Texture and Text displays."]
    end
    return L["Set Dynamic Information to this trigger."]
  end
  if data.regionType == "progresstexture" and Private.ProgressTextureNative.IsCircular(data.orientation) and not Enum.StatusBarRenderMode then
    return L["This client does not support native circular Progress Textures."]
  end
  local appearanceProblem = Display.ValidateAppearance(Display.PrepareConditionAppearance(data))
  if appearanceProblem then return appearanceProblem end
  local trigger = Display.GetTrigger(data, true)
  if Display.UsesSpellIDs(trigger) and #(trigger.auraspellids or {}) == 0 and not Display.UsesSpellList(trigger) then return L["Enter an exact spell ID, or untick Exact Spell IDs to show all matching auras."] end
  if Display.UsesRankSpellIDs(trigger) and #(trigger.auraRankSpellIDs or {}) == 0 then return L["Enter an aura name or spell ID, or untick Name(s)."] end
  if Display.UsesExcludedSpellIDs(trigger) and #(trigger.excludedAuraSpellIDs or {}) == 0 then return L["Enter an ignored spell ID, or untick Ignored Exact Spell IDs."] end
  if not Display.units[trigger.unit] or (trigger.debuffType ~= "HELPFUL" and trigger.debuffType ~= "HARMFUL") then
    return L["Choose a supported unit and Buff or Debuff."]
  end
  if trigger.unit == "member" and not Display.SpecificUnit(trigger) then
    return L["Enter a Specific Unit such as party1, raid5, boss1 or arena2."]
  end
  if trigger.unit == "nameplate" and (not C_NamePlate or not C_NamePlate.GetNamePlateForUnit) then
    return L["This client does not expose nameplate frames."]
  end
  for _, list in ipairs({trigger.auraspellids or {}, trigger.excludedAuraSpellIDs or {}}) do
    for _, value in ipairs(list) do
      local id = tonumber(value)
      if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then
        return L["Each aura spell ID must be a positive whole number."]
      end
    end
  end
  -- ForeverAuras: Name(s) takes an aura name or a spell ID.
  for _, value in ipairs(trigger.auraRankSpellIDs or {}) do
    local id = tonumber(value)
    if id and (id <= 0 or id == math.huge or id ~= math.floor(id)) then return L["Each aura spell ID must be a positive whole number."] end
    if not id and (type(value) ~= "string" or value == "") then return L["Each aura spell ID must be a positive whole number."] end
  end
  for _, field in ipairs(Display.booleanFilters) do
    if trigger[field[1]] ~= nil and type(trigger[field[1]]) ~= "boolean" then return L["Invalid aura filter: %s"]:format(field[2]) end
  end
  for _, field in ipairs(Display.processingOptions) do
    if trigger[field[1]] ~= nil and type(trigger[field[1]]) ~= "boolean" then return L["Invalid classification option: %s"]:format(field[2]) end
  end
  if trigger.maxDuration ~= nil and (type(trigger.maxDuration) ~= "number" or trigger.maxDuration <= 0
    or trigger.maxDuration == math.huge or trigger.maxDuration ~= trigger.maxDuration) then return L["Maximum total duration must be a positive number."] end
  if trigger.sortMethod and not Display.sortMethods[trigger.sortMethod] then return L["Choose a supported sort order."] end
  if trigger.sortMethod == "UnitFrameDebuff" and trigger.processedAuraType ~= "Debuff" and trigger.processedAuraType ~= "Dispel" then
    return L["Unit-frame debuff sorting requires the Debuff or Dispellable raid debuff classification."]
  end
  if trigger.processedAuraType and not Display.processedTypes[trigger.processedAuraType] then return L["Choose a supported Blizzard classification."] end
  local nativeKeys = {}
  for _, field in ipairs(Display.nativeFilters) do nativeKeys[field[1]] = true end
  for key, value in pairs(trigger.nativeFilters or {}) do
    if not nativeKeys[key] or type(value) ~= "boolean" then return L["Choose supported Blizzard aura filters."] end
  end
  if AuraUtil and AuraUtil.IsValidFilterString and not AuraUtil.IsValidFilterString(FilterString(trigger)) then
    return L["This client does not support the selected Blizzard aura filters."]
  end
  for _, field in ipairs({"includeDispelTypes", "excludeDispelTypes"}) do
    for name, value in pairs(trigger[field] or {}) do
      if not Display.dispelTypes[name] or value ~= true then return L["Choose supported dispel types."] end
    end
  end
  -- Show On and Remaining Time have their own unit and display rules.
  local singleProblem = Display.ValidateSingle(data, trigger)
  if singleProblem then return singleProblem end
  -- A Dynamic Group is allowed, with a warning (DynamicGroupWarning). A
  -- Modern Aura Group has its own rules (SecretAuraFlow.lua).
  local flowProblem = Display.FlowProblem(data, trigger)
  if flowProblem then return flowProblem end
  local conditionProblem = Display.ValidateConditions(data)
  if conditionProblem then return conditionProblem end
  for when, action in pairs(data.actions or {}) do
    if when ~= "init" then
      for key, value in pairs(action) do
        if key:match("^do_") and key ~= "do_sound" and key ~= "do_message" and value then
          return L["With an Aura (Modern) trigger, On Show/On Hide support Play Sound and Hide Glows only. Custom Init is available."]
        end
      end
      if action.stop_sound or (action.do_sound and action.sound == " KitID") then
        return L["Secret aura sounds support sound files, not Sound Kit IDs or Stop Sound."]
      end
    end
  end
  for _, animation in pairs(data.animation or {}) do
    if animation.type and animation.type ~= "none" then
      return L["With an Aura (Modern) trigger, the display's own Start/Main/Finish animations do not play; use the aura animations on the Animations tab."]
    end
  end
end

local function Restricted()
  return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret())
end

function Display.Locked(frame)
  if frame == nil or not frame.GetParent then return false end
  if frame.IsForbidden and frame:IsForbidden() then return true end
  return not pcall(frame.GetParent, frame)
end
-- Locked, or protected in combat (a secure button, or anything it hangs from).
function Display.Busy(frame)
  if Display.Locked(frame) then return true end
  return frame ~= nil and InCombatLockdown() and frame.IsProtected ~= nil and frame:IsProtected()
end
local Locked = Display.Busy

local function Warn(data, message)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_display", message and "warning" or nil, message)
end

local function SoundWarning(data, message)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_sound", message and "warning" or nil, message)
end

function Private.ResolveFojjiRecordedSound(value)
  local db = FojjiCoreDB
  if not FojjiCore or not db then return nil, "FojjiCore is not loaded." end
  if db.disableTTS then return nil, L["Speech is disabled in FojjiCore."] end
  if db.ttsVoiceType ~= "custom" or db.ttsRandomFavorites then
    return nil, L["Select one recorded voice pack in FojjiCore. Recorded sounds cannot use synthesized TTS or random favorites."]
  end
  local pack = FojjiCore.voicePacks and FojjiCore.voicePacks[db.ttsVoicePack]
  local file = pack and pack[value]
  if not file then return nil, L["No recording for '%s' in the selected FojjiCore voice pack."]:format(value) end
  return file
end

local function SoundChannel()
  local channel = FojjiCore and FojjiCoreDB and FojjiCoreDB.ttsSoundChannel
  if channel == "Sound Effects" then channel = "SFX" end
  if channel == "Master" or channel == "SFX" or channel == "Music" or channel == "Ambience" or channel == "Dialog" then return channel end
  return "Master"
end

-- Migrate once; Actions becomes the single source of sound settings.
function Display.MigrateSounds(data)
  local settings = data.blizzardAuraDisplay
  if settings.actionSounds then return end
  data.actions = data.actions or {}
  for _, event in ipairs({"Added", "Removed"}) do
    local when = event == "Added" and "start" or "finish"
    data.actions[when] = data.actions[when] or {}
    local action = data.actions[when]
    local value = settings.soundMode == "file" and (settings["sound" .. event .. "File"] or settings["sound" .. event]) or settings["sound" .. event]
    if not action.do_sound and settings.soundMode and settings.soundMode ~= "none" and value and value ~= "" and value ~= 1 then
      action.do_sound = true
      action.sound_channel = SoundChannel()
      if settings.soundMode == "fojji" then
        action.sound = " Fojji"
        action.sound_fojji = value
      else
        action.sound = " custom"
        action.sound_path = tostring(value)
      end
    end
  end
  settings.soundMode, settings.soundAdded, settings.soundRemoved = nil, nil, nil
  settings.soundAddedFile, settings.soundRemovedFile = nil, nil
  settings.actionSounds = true
end

local function IsPreview()
  return WeakAuras.IsOptionsOpen() and not InCombatLockdown()
end

-- The trigger's units that may sound: hostility, class and self filters apply
-- to sounds as to the display (Display.UnitEligible).
local function EligibleUnits(trigger)
  local units = {}
  for _, unit in ipairs(UnitTokens(trigger)) do
    if Display.UnitEligible(trigger, unit) then units[#units + 1] = unit end
  end
  return units
end

local function SyncSounds(region)
  if Restricted() then
    pendingSounds[region] = true
    return
  end
  pendingSounds[region] = nil
  local native = region.blizzardAuraDisplay
  if not native then return end
  -- Unchanged units, spells and sound actions: the registrations stand.
  local signature
  local live = native.active and Display.GetTrigger(native.data) ~= nil and region:IsShown() and not IsPreview()
  if live then
    local trigger = Display.GetTrigger(native.data)
    local actions = native.data.actions or {}
    local parts = {}
    for _, key in ipairs({"start", "finish"}) do
      local action = actions[key] or {}
      parts[#parts + 1] = table.concat({tostring(action.do_sound), tostring(action.sound), tostring(action.sound_path),
        tostring(action.sound_fojji), tostring(action.sound_channel)}, ",")
    end
    parts[#parts + 1] = table.concat(EligibleUnits(trigger), ",")
    parts[#parts + 1] = tostring(Display.RawShowOn(trigger))
    parts[#parts + 1] = table.concat(Display.GetSpellIDs(trigger, true), ",")
    parts[#parts + 1] = table.concat(trigger.excludedAuraSpellIDs or {}, ",")
    signature = table.concat(parts, "|")
    if signature == native.soundSignature then return end
  end
  native.soundSignature = signature
  for _, id in ipairs(native.soundIDs or {}) do C_UnitAuras.RemoveAuraSound(id) end
  native.soundIDs = {}
  local data = native.data
  SoundWarning(data)
  if not live then return end
  local actions = data.actions or {}
  if not ((actions.start or {}).do_sound or (actions.finish or {}).do_sound) then return end
  if not C_UnitAuras or not C_UnitAuras.AddAuraSound or not C_UnitAuras.RemoveAuraSound
    or not Enum.UnitAuraSoundTrigger then
    SoundWarning(data, L["This client does not provide native aura sound registration."])
    return
  end
  local trigger = Display.GetTrigger(data)
  local spellIDs = {}
  for _, value in ipairs(Display.GetSpellIDs(trigger, true)) do
    local id = tonumber(value)
    if id and id > 0 and id < math.huge and id == math.floor(id) then spellIDs[id] = true end
  end
  if Display.UsesExcludedSpellIDs(trigger) then
    for _, value in ipairs(trigger.excludedAuraSpellIDs or {}) do
      local id = tonumber(value)
      if id then spellIDs[id] = nil end
    end
  end
  if not next(spellIDs) then
    SoundWarning(data, L["Enable Name(s) or Exact Spell ID(s) in the Trigger and enter a spell that is not ignored to use aura sounds."])
    return
  end
  local failure
  local units = EligibleUnits(trigger)
  -- On Show / On Hide follow the display: with Show On Missing the display
  -- appears when the aura is removed, so the sounds swap over.
  local showOnMissing = Display.RawShowOn(trigger) == "showOnMissing"
  for _, event in ipairs({"Added", "Removed"}) do
    local onShow = (event == "Added") ~= showOnMissing
    local action = actions[onShow and "start" or "finish"] or {}
    if action.do_sound then
      local file, message
      if action.sound == " Fojji" then
        file, message = Private.ResolveFojjiRecordedSound(action.sound_fojji or "")
      elseif action.sound == " custom" then
        file = tonumber(action.sound_path) or action.sound_path
      elseif action.sound ~= " KitID" then
        file = action.sound
      end
      if not file or file == "" or file == 1 then
        file = nil
        message = message or L["Choose a sound file in Actions."]
      end
      if file then
        for _, unit in ipairs(units) do
          for spellID in pairs(spellIDs) do
            local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger[event], {
              unitToken = unit, spellID = spellID,
              soundFileName = type(file) == "string" and file or nil,
              soundFileID = type(file) == "number" and file or nil,
              outputChannel = action.sound_channel or "Master",
            })
            if ok and id then
              native.soundIDs[#native.soundIDs + 1] = id
            else
              failure = L["Blizzard could not register the %s sound for spell %s."]:format(event:lower(), spellID)
            end
          end
        end
      else
        failure = message
      end
    end
  end
  SoundWarning(data, failure)
end

local function UpdatePreviewNotice(region)
  local data = region.blizzardAuraDisplay and region.blizzardAuraDisplay.data
  local trigger = Display.GetTrigger(data)
  local warning
  -- Same rule as the trigger's status line: only a selection Blizzard always
  -- refuses (not never-secret spells) gets the notice.
  if trigger and Display.SpellIDFilterNote(trigger) == "error" then
    warning = L["Preview only: these auras will not display in combat with spell ID filters.\nConfigured sounds in Actions can still play."]
  end
  if warning then
    if not region.secretAuraPreviewNotice then
      local text = region:CreateFontString(nil, "OVERLAY")
      text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
      text:SetPoint("TOP", region, "BOTTOM", 0, -6)
      text:SetWidth(300)
      text:SetTextColor(1, 0.8, 0.2)
      region.secretAuraPreviewNotice = text
    end
    region.secretAuraPreviewNotice:SetText(warning)
    region.secretAuraPreviewNotice:Show()
  elseif region.secretAuraPreviewNotice then
    region.secretAuraPreviewNotice:Hide()
  end
end

-- ForeverAuras: a Glow element of a suppressed display (alpha 0 while the
-- editor's samples stand for it) stops its own animated glow, which nobody
-- could see; it starts again when the display's look is restored. Each
-- glow moved its lines every frame, and a pack of a hundred glowing
-- displays spent most of the frame on them in the editor (issue #136).
local function StopSuppressedGlows(region)
  for _, frame in ipairs(region.subRegions or {}) do
    if frame.type == "subglow" and frame.glow and frame.glowStop and not frame.secretAuraDetached then frame.glowStop(frame) end
  end
end
local function RestoreSuppressedGlows(region)
  for _, frame in ipairs(region.subRegions or {}) do
    if frame.type == "subglow" and frame.glow and frame.SetVisible and not frame.secretAuraDetached then frame:SetVisible(true) end
  end
end
local function Suppress(region)
  local native = region.blizzardAuraDisplay
  if IsPreview() and not region.secretAuraSamplesActive and not (native and native.previewHasAuras) then
    local wasSuppressed = region.blizzardSuppressed ~= nil
    for frame, alpha in pairs(region.blizzardSuppressed or {}) do frame:SetAlpha(alpha) end
    region.blizzardSuppressed = nil
    if wasSuppressed then RestoreSuppressedGlows(region) end
    UpdatePreviewNotice(region)
    return
  end
  if region.secretAuraPreviewNotice then region.secretAuraPreviewNotice:Hide() end
  region.blizzardSuppressed = region.blizzardSuppressed or {}
  local saved = region.blizzardSuppressed
  for _, key in ipairs({"icon", "cooldown", "button", "bar", "secretBar", "text", "background"}) do
    local frame = region[key]
    if frame and frame.SetAlpha then
      if saved[frame] == nil then saved[frame] = frame:GetAlpha() end
      frame:SetAlpha(0)
    end
  end
  -- Progress Texture stores drawable textures inside its geometry wrappers.
  if region.regionType == "progresstexture" then
    local function SuppressTexture(texture)
      if saved[texture] == nil then saved[texture] = texture:GetAlpha() end
      texture:SetAlpha(0)
    end
    SuppressTexture(region.foreground.texture)
    SuppressTexture(region.background.texture)
    for _, spinner in ipairs({region.foregroundSpinner, region.backgroundSpinner}) do
      for _, texture in ipairs(spinner.textures) do SuppressTexture(texture) end
    end
    for _, texture in ipairs(region.extraTextures) do SuppressTexture(texture.texture) end
    for _, spinner in ipairs(region.extraSpinners) do
      for _, texture in ipairs(spinner.textures) do SuppressTexture(texture) end
    end
    if region.nativeProgress then SuppressTexture(region.nativeProgress.bar) end
  end
  -- A Texture display draws through a TextureBase wrapper around its texture.
  if region.regionType == "texture" and region.texture and region.texture.texture then
    local texture = region.texture.texture
    if saved[texture] == nil then saved[texture] = texture:GetAlpha() end
    texture:SetAlpha(0)
  end
  -- AuraBar stores its background on bar, but parents the texture to the region.
  local background = region.bar and region.bar.bg
  if background then
    if saved[background] == nil then saved[background] = background:GetAlpha() end
    background:SetAlpha(0)
  end
  for _, frame in ipairs(region.subRegions or {}) do
    if frame.SetAlpha and not frame.secretAuraDetached then
      if saved[frame] == nil then saved[frame] = frame:GetAlpha() end
      frame:SetAlpha(0)
    end
  end
  StopSuppressedGlows(region)
end

function Display.Restore(region)
  -- Pooled samples must never survive release or a trigger switch.
  if Display.HidePreview then Display.HidePreview(region) end
  if Display.RestorePreviewRegion then Display.RestorePreviewRegion(region) end
  if region.secretAuraPreviewNotice then region.secretAuraPreviewNotice:Hide() end
  region.secretAuraConditionValues = nil
  -- ForeverAuras: a reset waiting for access belongs to the released look
  -- (SecretAuraConditions.ResetConditionProperty); replayed later it would
  -- paint an old saved value over a rebuilt display.
  region.secretAuraPendingResets = nil
  local wasSuppressed = region.blizzardSuppressed ~= nil
  for frame, alpha in pairs(region.blizzardSuppressed or {}) do frame:SetAlpha(alpha) end
  region.blizzardSuppressed = nil
  if wasSuppressed then RestoreSuppressedGlows(region) end
  if region.blizzardOriginalUpdate then
    region.Update = region.blizzardOriginalUpdate.func
    region.blizzardOriginalUpdate = nil
  end
  if region.blizzardOriginalPreShow then
    region.PreShow = region.blizzardOriginalPreShow.func
    region.blizzardOriginalPreShow = nil
  end
end

-- ForeverAuras: switches off one display's client work: every container
-- it owns (the aura list, its list shadow in a Modern Aura Group, its unit
-- glow, and the Missing parts through RefreshSingle). A frame the client has
-- locked (in combat, when it hangs from a protected unit frame or plate) is
-- noted in lockedHide and switched off when restrictions end; before, only
-- the aura list was retried then, so a unit glow or list shadow locked at
-- release time stayed enabled, bound to its unit and processed by the
-- client for the rest of the session.
-- ForeverAuras (dev.92, Dan's A icons; Astra's dev.90 review): EDITOR
-- RETENTION. Opening the editor pauses every display (Private.Pause: the
-- regions collapse, their OnHide quiets the containers) and closing it unloads
-- them all and loads them again (Private.Resume: Release, then the load scan).
-- Each of those disabled the live containers, and the client releases every
-- aura's button of a disabled container and hands the buttons out again from
-- a free list it walks in hash order - the cells of a chained member then
-- show the same auras on other cells. Between Private.Pause and the end of
-- Private.Resume a live container is RETAINED instead: kept enabled and
-- bound, hidden by alpha, remembered here; when the editor is closed and the
-- displays are loaded again, those loaded again take their container as it
-- is (ApplyInstance keeps an unchanged configuration; RefreshUnits shows it
-- again), and the retained containers of the displays NOT loaded again are
-- quieted then, as a release would have. Restrictions take no part (a
-- container under them is left to the ordinary path).
local retainedInstances = {}   -- instance -> region, owned until the container is live again or quieted for good
local editorRetaining = false
-- (dev.95, Astra's dev.93 review 1) the region collapses with the pause, and
-- the client answers a hidden ancestor with a full rebuild of the container
-- (its own OnHide/OnShow) and drops its aura events while hidden: keeping it
-- enabled under a hidden region keeps nothing. A retained container is moved
-- under a shown holder of its own for the retention (alpha 0 hides it), and
-- back under its parent when its display is live again (RefreshUnits).
local retentionHolder
-- Keep the physical stage and each accepted write, even when changing mode
-- makes MissingStage return nil. A reused stage must not stay unbuffered.
local function SetRetainedStages(instance, muted)
  local stages = instance.mutedStages
  if muted then
    local stage = instance.single and instance.single.stage
    if stage then
      stages = stages or {}; instance.mutedStages = stages
      stages[stage] = stages[stage] or {}
    end
  end
  if not stages then return true end
  local active = Display.MissingStage and Display.MissingStage(instance)
  local accepted = true
  for stage, state in pairs(stages) do
    local ready = true
    if not muted and stage ~= active then
      -- The old stage is now unused. Hide it before restoring its buffer so
      -- an empty, still-shown buffer cannot composite a black rectangle.
      local ok, parent = pcall(instance.container.GetParent, instance.container)
      if not ok or (issecretvalue and issecretvalue(parent)) or parent == stage then ready = false
      else ready = pcall(stage.Hide, stage) end
    end
    local first, second = muted and "buffer" or "flatten", muted and "flatten" or "buffer"
    local firstSetter = muted and stage.SetIsFrameBuffer or stage.SetFlattensRenderLayers
    local secondSetter = muted and stage.SetFlattensRenderLayers or stage.SetIsFrameBuffer
    local value = not muted
    if ready and state[first] ~= value then
      ready = pcall(firstSetter, stage, value)
      if ready then state[first] = value end
    end
    if ready and state[second] ~= value then
      ready = pcall(secondSetter, stage, value)
      if ready then state[second] = value end
    end
    if ready and not muted then stages[stage] = nil
    elseif not ready then accepted = false end
  end
  if next(stages) == nil then instance.mutedStages = nil end
  return accepted
end
-- DISABLE-blend textures cannot rely on parent alpha to hide them. Block
-- restyles before hiding/reparenting, including native records made later.
local function MuteErasers(instance)
  instance.eraserMuted, instance.eraserRestorePending = true, true
  local accepted = true
  for _, native in ipairs(instance.buttons or {}) do
    if native.eraser and not pcall(native.eraser.Hide, native.eraser) then accepted = false end
  end
  if accepted then accepted = SetRetainedStages(instance, true) end
  instance.eraserMuteFailed = not accepted or nil
  return accepted
end
local function RestoreErasers(instance, data)
  if not instance.eraserRestorePending then return true end
  if not data or not Display.StyleEraser then return false end
  -- Never re-enable a destructive eraser before its framebuffer exists and
  -- the live container has actually returned to that framebuffer.
  local ok, ready = pcall(function()
    local trigger = Display.GetTrigger(data)
    if Display.ErasedMissing and Display.ErasedMissing(data, trigger, Display.UnitPlacedMissing(data, trigger)) then
      local stage = Display.MissingStage(instance)
      local parent = instance.container:GetParent()
      if issecretvalue and issecretvalue(parent) then return false end
      return stage ~= nil and parent == stage
    end
    return true
  end)
  if not ok or (issecretvalue and issecretvalue(ready)) or not ready then return false end
  if not SetRetainedStages(instance, false) then return false end
  instance.eraserMuted = nil
  local accepted = true
  for _, native in ipairs(instance.buttons or {}) do
    if native.eraser and not pcall(Display.StyleEraser, native, data) then accepted = false end
  end
  instance.eraserRestorePending = not accepted or nil
  if accepted then instance.eraserMuteFailed = nil end
  return accepted
end
local function RetainInstance(instance, region)
  local container = instance.container
  if not (container and container.faEnabled == true and instance.applied and not Locked(container)) then return false end
  if not MuteErasers(instance) then
    if region then lockedUnits[region] = true end
    return false
  end
  if not pcall(container.SetAlpha, container, 0) then return false end
  if not retentionHolder then
    retentionHolder = CreateFrame("Frame", nil, UIParent)
    retentionHolder:SetSize(1, 1)
    retentionHolder:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    retentionHolder:Show()
  end
  local okP = pcall(container.SetParent, container, retentionHolder)
  if not okP then pcall(container.SetAlpha, container, instance.baseAlpha or 1); return false end
  instance.appliedStrata, instance.appliedLevel = nil, nil
  instance.retainedMuted = true
  retainedInstances[instance] = region or true
  return true
end
-- a retained container whose display is live again: back under its parent, as it is (no enable cycle)
local function RestoreRetained(instance, parent)
  local container = instance.container
  if container:GetParent() ~= parent then
    if not pcall(container.SetParent, container, parent) then return false end
    instance.appliedStrata, instance.appliedLevel = nil, nil
  end
  retainedInstances[instance] = nil
  instance.retainedMuted = nil
  instance.visible = true
  return true
end
-- a retained container whose display did not come back: quieted for good, the ownership kept until the
-- disable AND the hide went through (Astra's dev.93 review 2); a locked one is quieted when restrictions end
local function QuietRetained(instance)
  local container = instance.container
  local region = retainedInstances[instance]
  if Locked(container) then
    if type(region) == "table" then lockedHide[region] = true end
    return false
  end
  local ok = pcall(function() container:SetEnabled(false); container:Hide() end)
  if not ok then
    if type(region) == "table" then lockedHide[region] = true end
    return false
  end
  instance.visible = false
  instance.retainedMuted = nil
  retainedInstances[instance] = nil
  return true
end
-- (dev.95, Dan's dev.94 lines) the resume LOADS the displays again after it
-- returns (the paced drain, the next frames), so the retention cannot end
-- when Private.Resume ends: the cleanup waits for each retained display to
-- be loaded again (its binding pass restores the container) or to be left
-- unloaded, and quiets only the latter; a bounded number of looks, then
-- whatever is still retained and not live is quieted.
-- (Astra's dev.94 results) the retained flag alone says only "not yet
-- restored by a binding pass", never "not loaded": the verdict comes from the
-- load lifecycle (Private.loaded, a pending or retried build, the live
-- construction's own instance list), and each editor cycle is a generation of
-- its own, so an older cycle's cleanup never touches a newly retained one.
-- a display the load lifecycle brings back: the load scan loaded it (the core loaded map), or its build is
-- pending or retried
local function Returning(region)
  if type(region) ~= "table" then return false end
  if pending[region] ~= nil or retryAfterRestrictions[region] ~= nil then return true end
  local native = region.blizzardAuraDisplay
  local id = native and native.data and native.data.id
  return id ~= nil and Private.loaded ~= nil and Private.loaded[id] == true
end
local reconcileLooks = 0
local retentionGeneration = 0
local function ReconcileRetained(generation)
  if editorRetaining or generation ~= retentionGeneration then return end
  reconcileLooks = reconcileLooks + 1
  local again = false
  for instance, region in pairs(retainedInstances) do
    if not instance.retainedMuted then
      retainedInstances[instance] = nil
    else
      local native = type(region) == "table" and region.blizzardAuraDisplay
      -- loaded again (Private.loaded says so as soon as the load scan decided, before the paced build runs)
      local loading = Returning(region)
      -- the live construction: this instance still its own (it restores itself in its next binding pass),
      -- or superseded by a fresh one (quieted now, loaded or not: the fresh construction owns the display)
      local current, built = false, native and native.active and native.instances ~= nil
      if built then
        for _, live in ipairs(native.instances) do if live == instance then current = true; break end end
      end
      local superseded = built and not current
      if superseded then
        QuietRetained(instance)
      elseif loading or (built and current) then
        -- (1.2.0, Astra's audit 3) a display still loading or still owning this instance is never quieted
        -- by the bound: the looks stop, the ownership stays, and its next binding pass restores it
        if reconcileLooks < 30 then again = true end
      else
        QuietRetained(instance)
      end
    end
  end
  if again then C_Timer.After(0.1, function() ReconcileRetained(generation) end) end
end
-- (dev.97, Dan's dev.96 screenshots) the client rebuilds a container's aura
-- assignments once it was hidden, even through an ancestor: a region hidden
-- by the pause hides its container before the OnHide hook can move it, and
-- the move under the shown holder then shows it again - a full rebuild, the
-- auras handed out in another order. The live containers are moved under
-- the holder BEFORE the pause hides anything (the region still shown: no
-- visibility change for the container), and moved back only under a region
-- that is visible again (RestoreRetained's caller, RefreshUnits).
local function RetainLiveInstances()
  if Restricted() or not Private.regions then return end
  for _, entry in pairs(Private.regions) do
    local region = entry and entry.region
    local native = region and region.blizzardAuraDisplay
    if native and native.active and native.instances and region:IsVisible() then
      for _, instance in ipairs(native.instances) do
        if not instance.retainedMuted and instance.visible ~= false and not Locked(instance.container) then
          RetainInstance(instance, region)
        end
      end
    end
  end
end
function Display.EditorRetention(on)
  if CombatBuildReport then CombatBuildReport(("editor retention %s"):format(on and "on" or "off")) end
  retentionGeneration = retentionGeneration + 1   -- an older cycle's pending cleanup stops here
  if on then editorRetaining = true; RetainLiveInstances(); return end
  editorRetaining = false
  reconcileLooks = 0
  local generation = retentionGeneration
  C_Timer.After(0, function() ReconcileRetained(generation) end)
end
-- the restriction-end handler and a later quiet revisit what could not be quieted
function Display.QuietRetainedLater()
  for instance, region in pairs(retainedInstances) do
    if not editorRetaining and instance.retainedMuted then
      -- (1.2.0, Astra's audit 3) the same eligibility as the reconciliation: a loading display, or a live
      -- construction that still owns this instance, keeps its container
      local native = type(region) == "table" and region.blizzardAuraDisplay
      local current = false
      if native and native.active and native.instances then
        for _, live in ipairs(native.instances) do if live == instance then current = true; break end end
      end
      -- A live replacement supersedes this retained instance even while the display is loaded.
      local superseded = native and native.active and native.instances ~= nil and not current
      if superseded or (not current and not Returning(region)) then QuietRetained(instance) end
    end
  end
end
function Display.EditorRetaining() return editorRetaining end

local function QuietInstance(region, instance)
  local locked = false
  -- ForeverAuras 1.2.1 (dev.115): a quieted record's own glow binding (SecretAuraSingle.lua, the timed
  -- chain's glow) stops with it; a refused disable keeps the owner for the next attempt
  if Display.DisableGlowBinding then
    for _, native in ipairs(instance.buttons or {}) do
      if native.glowBinding then
        if not Display.DisableGlowBinding(native, true) then locked = true end
        if native.glowBinding.resumePending then instance.glowResumePending = true end
      end
    end
  end
  -- ForeverAuras: a quieted instance is not visible, whatever the client
  -- lets us do to its frames right now: the per-unit rows of a Modern Aura
  -- Group grouped by frame (SecretAuraFlow.lua, RelinkFlowUnits) chain only
  -- visible instances, and a hidden display's containers used to stay in
  -- them until the next unit refresh.
  instance.visible = false
  if Locked(instance.container) then
    locked = true
  elseif (editorRetaining or (instance.retainedMuted and Returning(region))) and not Restricted()
    and (instance.retainedMuted or RetainInstance(instance, region)) then
    -- (dev.92) retained through the editor: enabled and bound, hidden by alpha, under the shown holder
    -- (dev.96, Dan's dev.95 lines) and still retained when the region hides AFTER the retention ended for a
    -- display the loads bring back (WeakAuras.Add collapses the region before its rebuild): its binding
    -- pass restores the container; disabling here was the reset
  else
    -- (dev.94) said with "/fa cells debug on" for a chained member: the quiet that disables, and why it was not retained
    if instance.chained and Display.BuildReporting and Display.BuildReporting() then
      CombatBuildReport(("%s: list quieted (retaining %s, restricted %s, applied %s, enabled %s, retained %s)"):format(tostring(instance.data and instance.data.id),
        tostring(editorRetaining), tostring(Restricted()), tostring(instance.applied), tostring(instance.container.faEnabled), tostring(instance.retainedMuted)))
    end
    if instance.retainedMuted then
      -- (1.2.0, Astra's audit 2) a retained container quieted here goes through the protected cleanup:
      -- the ownership is kept until its disable AND hide went through, a refusal is revisited later
      if not QuietRetained(instance) then locked = true end
    else
      instance.container:SetEnabled(false)
      instance.container:Hide()
    end
  end
  for _, key in ipairs({"flowShadow", "flowMeasure"}) do   -- ForeverAuras (dev.78): the end measurement's container with the shadow's
    local shadow = instance[key]
    if shadow then
      if Locked(shadow) then
        locked = true
      elseif shadow.faEnabled or shadow:IsShown() then
        shadow.faEnabled = false
        shadow:SetEnabled(false)
        shadow:Hide()
      end
    end
  end
  local glow = instance.unitGlow and instance.unitGlow.container
  if glow then
    if Locked(glow) then
      locked = true
    else
      glow:SetEnabled(false)
      glow:Hide()
    end
  end
  -- The Missing parts are switched off by RefreshSingle (the caller), which
  -- gives up on a locked one; it is retried from here as well.
  local missing = instance.single and instance.single.missing
  if missing and missing.active and (Locked(missing.container) or Locked(missing.clip)
    or (missing.presence and Locked(missing.presence)) or (missing.flowShadow and Locked(missing.flowShadow))) then
    locked = true
  end
  if locked then lockedHide[region] = true end
end

function Display.HideUnitGlows(region)
  local native = region.blizzardAuraDisplay
  if not native then return end
  native.unitGlowsHidden = true
  for _, instance in ipairs(native.instances) do
    if instance.unitGlow then
      if Locked(instance.unitGlow.container) then
        lockedHide[region] = true
      else
        instance.unitGlow.container:SetEnabled(false)
        instance.unitGlow.container:Hide()
      end
    end
  end
end

function Display.Release(region)
  Display.ReleaseAuraLearning(region)
  Display.HideUnitGlows(region)
  Display.Restore(region)
  pending[region] = nil
  -- ForeverAuras (combat-reload probe): an unloaded display's retry is
  -- cancelled; frames of a stopped build are cleaned when possible.
  retryAfterRestrictions[region] = nil
  chainDeferredRetry[region] = nil
  chainOrderWaits[region] = nil
  -- ForeverAuras (cell chain, dev.41 review): the cancelled job's latch goes
  -- with it (a later request may queue again); the epoch's count and a stop
  -- stay, so an unload does not hand out new attempts.
  do
    local record = region.blizzardAuraDisplay and region.blizzardAuraDisplay.reapplyRequests
    if record then record.pending, record.wanted = nil, nil end
    -- A commit still held by a batch is dropped with the display (an
    -- activation of the same prepared construction asks again, Activate;
    -- the next apply asks for its own).
    local native = region.blizzardAuraDisplay
    if native then native.chainCommitPending = nil end
    -- ForeverAuras (cell chain, dev.47 review): a probe build the chain pass
    -- has not accepted yet (its finishing held by a batch) is released as a
    -- stopped build is: its instances retired with its allocations (below),
    -- its accounting closed, nothing of it kept for a cheap reactivation (the
    -- display is made new when it is shown again). No retry: it is unloaded.
    if native and native.probeHeld then
      native.probeHeld = nil
      for _, instance in ipairs(native.instances) do
        instance.finishing, instance.finishFailed = nil, nil
        local missing = instance.single and instance.single.missing
        if missing then missing.active = false end
        RetainInstanceFrames(region, instance)
        if Display.CancelPendingListAlpha then Display.CancelPendingListAlpha(instance) end
      end
      native.instances = {}
      native.probeBuild = nil
    end
  end
  RetainAllocations(region)
  CleanAbandoned(region)
  -- ForeverAuras (dev.68/69): an unloaded display's spine is let go ONLY
  -- when its construction is gone with it (a held or stopped probe build:
  -- no instances left). A healthy display keeps its instances for a cheap
  -- reactivation (Activate), and keeps its prepared spine with them (Astra's
  -- dev.68 review: a released spine under a kept instance was reactivated
  -- as complete with nothing anchored).
  do
    local native = region.blizzardAuraDisplay
    if native and Display.ReleaseChainSpine and #native.instances == 0 then Display.ReleaseChainSpine(native) end
  end
  if Display.CancelEditorApply then Display.CancelEditorApply(region) end
  -- ForeverAuras (1.3.6-dev.12, Astra's dev.10 review): a released display owes
  -- no token work; nothing of it may be served to whatever this region shows next.
  pendingTokens[region] = nil
  local native = region.blizzardAuraDisplay
  if native then
    native.active = false
    -- ForeverAuras (dev.36/37 reviews): a reserve attempt released mid-way
    -- leaves its unattached allocations to cleaning (ReconcileLedger). The
    -- guard lets the review harnesses run this function as a slice.
    if ReconcileLedger then ReconcileLedger(region, native.instanceQueue) end
    native.instanceQueue = nil
    for _, instance in ipairs(native.instances) do
      QuietInstance(region, instance)
      Display.RefreshSingle(instance, nil, false)
    end
    -- A released display draws nothing, so no Missing or Remaining Time part can be failing.
    Private.AuraWarnings.UpdateWarning(native.data.uid, "blizzard_aura_single", nil)
    Private.AuraWarnings.UpdateWarning(native.data.uid, "blizzard_aura_dynamicgroup", nil)
    -- ForeverAuras (cell chain): nor a row cell (PublishChainWarnings keys).
    for _, key in ipairs({"blizzard_aura_chain_why", "blizzard_aura_chain", "blizzard_aura_chain_more"}) do
      Private.AuraWarnings.UpdateWarning(native.data.uid, key, nil)
    end
    activeRegions[region] = nil
    SyncSounds(region)
    -- The next display in a Modern Aura Group starts where this one did.
    Display.RechainFlow(Display.FlowGroup(native.data))
    Display.RefreshGridFor(region)
  end
end

local function StyleText(text, native, settings, key, size, anchor, x, y)
  local button = native.button
  local font = settings[key .. "Font"]
  local outline = settings[key .. "Outline"]
  -- Native aura bindings and their previews must inherit shadows just like subtext.
  Private.ApplyTextFont(text, nil, font and SharedMedia:Fetch("font", font) or "Fonts\\ARIALN.TTF",
    settings[key .. "Size"] or size, (outline == "None" and "" or outline) or "OUTLINE",
    settings[key .. "ShadowColor"] or {0, 0, 0, 0}, settings[key .. "ShadowX"] or 1, settings[key .. "ShadowY"] or -1)
  text:SetTextColor(unpack(settings[key .. "Color"] or {1, 1, 1, 1}))
  local point = settings[key .. "Anchor"] or anchor
  -- Preserve the original same-point anchors until a self point is chosen.
  local selfPoint = settings[key .. "SelfPoint"]
  -- Texts hang from the visual box (Display.Box): the button, or a Grid member's offset box.
  local target = Display.Box(native)
  local area = point:sub(1, 6)
  if area == "INNER_" or area == "OUTER_" then
    target = area == "INNER_" and native.inner or native.outer
    point = point:sub(7)
  end
  selfPoint = selfPoint or ((area == "INNER_" or area == "OUTER_") and "AUTO" or point)
  if selfPoint == "AUTO" then
    selfPoint = area == "INNER_" and point or area == "OUTER_" and Private.inverse_point_types[point] or "CENTER"
  end
  text:ClearAllPoints()
  text:SetPoint(selfPoint, target, point, settings[key .. "X"] or x, settings[key .. "Y"] or y)
  text:SetJustifyH(settings[key .. "Justify"] or "CENTER")
end

local function CreateGlow(native, unitGlow)
  local glow = {}
  for _, kind in ipairs({"proc", "pulse"}) do
    local texture = (unitGlow and native.overlay or ElementFrame(native, "glow")):CreateTexture(nil, "OVERLAY", nil, -1)
    texture:SetBlendMode("ADD")
    texture:SetDesaturated(true)
    texture:Hide()
    local group = texture:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    group:SetToFinalAlpha(true)
    local entry = {texture = texture, group = group, animations = {}}
    glow[kind] = entry
    if kind == "proc" then
      texture:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
      -- Keep the atlas hidden unless the native animation supplies its opacity.
      local opacity = group:CreateAnimation("Alpha")
      opacity:SetTarget(texture)
      opacity:SetOrder(1)
      opacity:SetFromAlpha(1)
      opacity:SetToAlpha(1)
      opacity:SetDuration(0.001)
      local animation = group:CreateAnimation("FlipBook")
      animation:SetTarget(texture)
      animation:SetOrder(1)
      animation:SetFlipBookRows(6)
      animation:SetFlipBookColumns(5)
      animation:SetFlipBookFrames(30)
      animation:SetFlipBookFrameWidth(0)
      animation:SetFlipBookFrameHeight(0)
      entry.animations[1] = animation
    else
      texture:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
      texture:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
      for index = 1, 2 do
        local animation = group:CreateAnimation("Alpha")
        animation:SetTarget(texture)
        animation:SetOrder(index)
        animation:SetFromAlpha(index == 1 and 0.25 or 1)
        animation:SetToAlpha(index == 1 and 1 or 0.25)
        entry.animations[index] = animation
      end
    end
  end
  native.glow = glow
  return glow
end

local function StyleGlow(native, data, unitGlow)
  local settings = data.blizzardAuraDisplay
  if unitGlow then
    settings = {
      glow = settings.unitGlow, glowType = settings.unitGlowType, glowColor = settings.unitGlowColor,
      glowDuration = settings.unitGlowDuration, glowX = settings.unitGlowX, glowY = settings.unitGlowY, useGlowColor = settings.unitUseGlowColor,
      padding = settings.unitGlowPadding or 0,
    }
  end
  local glow = native.glow
  if not glow and not settings.glow then return end
  glow = glow or CreateGlow(native, unitGlow)
  if glow.registered then
    native.button:RemoveAuraShownAnimation(glow.registered)
    glow.registered = nil
  end
  for _, kind in ipairs({"proc", "pulse"}) do
    glow[kind].group:Stop()
    glow[kind].texture:Hide()
  end
  if not settings.glow then return end
  local entry = glow[settings.glowType or "proc"] or glow.proc
  local scale = math.max(0.5, settings.glowScale or 1)
  local duration = math.max(0.1, settings.glowDuration or 1)
  entry.texture:ClearAllPoints()
  if unitGlow then
    entry.texture:SetPoint("TOPLEFT", Display.Box(native), "TOPLEFT", (settings.glowX or 0) - settings.padding, (settings.glowY or 0) + settings.padding)
    entry.texture:SetPoint("BOTTOMRIGHT", Display.Box(native), "BOTTOMRIGHT", (settings.glowX or 0) + settings.padding, (settings.glowY or 0) - settings.padding)
  else
    entry.texture:SetPoint("CENTER", native.glowAnchor or Display.Box(native), "CENTER", settings.glowX or 0, settings.glowY or 0)
    entry.texture:SetSize(math.max(4, native.glowWidth or data.width or data.fixedWidth or 200) * 1.4 * scale, math.max(4, native.glowHeight or data.height or data.fontSize or 18) * 1.4 * scale)
  end
  entry.texture:SetVertexColor(unpack(settings.useGlowColor ~= false and settings.glowColor or {1, 0.82, 0, 1}))
  entry.texture:SetAlpha(entry == glow.pulse and 0.25 or 0)
  for _, animation in ipairs(entry.animations) do animation:SetDuration(duration / #entry.animations) end
  entry.texture:Show()
  -- Blizzard owns animation playback as secret aura visibility changes.
  native.button:AddAuraShownAnimation(entry.group)
  glow.registered = entry.group

end

-- Show On: Aura(s) Gained. An aura new to the unit fades in, holds for the
-- trigger's seconds and fades out; its button rests at alpha 0 otherwise, so
-- the display shows only what just happened (a buff an enemy gains, say). The fade is an
-- animation group handed to the button (AddAuraAssignedAnimation), which
-- Blizzard plays when it assigns an aura to the button and never on an
-- update: nothing here reads the aura. A build without that call plays it
-- whenever the aura is shown. Proven first in the Enemy Nameplate Spells aura
-- with its own container; the aura's rest alpha is the one live alpha write
-- besides ConfigureSingle (SecretAuraSingle.lua), which defers to it.
local FLASH_IN, FLASH_OUT = 0.1, 0.3
-- Show On: Aura(s) Gained (SecretAuraTriggerOptions.lua): the trigger stays a
-- Found list (secretShowOn nil) with secretGained set, so everything else
-- treats it as Found; only the drawing here reads it.
function Display.GainedSeconds(trigger)
  if type(trigger) ~= "table" or not trigger.secretGained or Display.ShowOn(trigger) ~= "showOnActive" then return 0 end
  -- The time and stack gates hide auras their own way; with one set (an
  -- import, say) the trigger is a plain Found list.
  if trigger.secretUseRem or trigger.secretUseTotal or trigger.secretUseStacks then return 0 end
  local seconds = tonumber(trigger.secretGainedSeconds) or 1.5
  return seconds > 0 and seconds or 0
end
function Display.FlashSeconds(data)
  return Display.GainedSeconds(Display.GetSavedTrigger(data))
end
-- From first light to gone.
function Display.FlashLength(data)
  local seconds = Display.FlashSeconds(data)
  return seconds > 0 and FLASH_IN + seconds + FLASH_OUT or 0
end
local function StyleFlash(native, data)
  local button = native.button
  local seconds = Display.FlashSeconds(data)
  local flash = native.flash
  if seconds <= 0 then
    if flash and flash.registered then
      if flash.assigned then button:RemoveAuraAssignedAnimation(flash.group) else button:RemoveAuraShownAnimation(flash.group) end
      flash.registered, flash.assigned = nil, nil
      flash.group:Stop()
      button:SetAlpha(1)
    end
    return
  end
  if not flash then
    local group = button:CreateAnimationGroup()
    group:SetToFinalAlpha(true)
    local into = group:CreateAnimation("Alpha")
    into:SetFromAlpha(0); into:SetToAlpha(1); into:SetDuration(FLASH_IN); into:SetOrder(1)
    local hold = group:CreateAnimation("Alpha")
    hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetOrder(2)
    local out = group:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(FLASH_OUT); out:SetOrder(3)
    flash = {group = group, hold = hold}
    native.flash = flash
  end
  flash.hold:SetDuration(seconds)
  if not flash.registered then
    if button.AddAuraAssignedAnimation then
      button:AddAuraAssignedAnimation(flash.group)
      flash.assigned = true
    else
      button:AddAuraShownAnimation(flash.group)
    end
    flash.registered = true
  end
  button:SetAlpha(0)
end
-- Whether this button rests at alpha 0 between flashes (ConfigureSingle).
function Display.FlashRests(native)
  local flash = native and native.flash
  return flash ~= nil and flash.registered == true
end

-- Aura animations (the Animations tab of an Aura (Modern) list): native
-- animation groups the client plays on each aura's button, since nothing
-- else reaches a button. Start plays when the client assigns an aura to a
-- button (AddAuraAssignedAnimation); Main loops while the aura is shown
-- (AddAuraShownAnimation). The display's own trigger is always active, so
-- these are never driven by trigger state. A freshly bound unit's existing
-- auras are all assigned at once and play Start together, as a display's own
-- Start plays when it first shows. There is no hook for an aura ending, so
-- there is no Finish.
Display.auraStartTypes = {none = L["None"], fade = L["Fade In"], zoom = L["Zoom In"], spin = L["Spin In"], bounce = L["Bounce In"]}
Display.auraMainTypes = {none = L["None"], pulse = L["Pulse"], spin = L["Spin"], wobble = L["Wobble"], bounce = L["Bounce"]}
function Display.AuraAnimation(data, kind)
  local settings = data.blizzardAuraDisplay and data.blizzardAuraDisplay[kind == "start" and "auraStart" or "auraMain"]
  if type(settings) ~= "table" then return "none", 0 end
  local types = kind == "start" and Display.auraStartTypes or Display.auraMainTypes
  local animType = types[settings.type] and settings.type or "none"
  local duration = tonumber(settings.duration) or (kind == "start" and 0.3 or 1)
  if animType == "none" or duration <= 0 then return "none", 0 end
  -- Gained plays its own fade; Start is its flash, and Main may not touch alpha.
  if Display.FlashSeconds(data) > 0 and (kind == "start" or animType == "pulse") then return "none", 0 end
  return animType, duration
end
local function BuildAuraAnimation(native, data, kind, animType, duration)
  local button = native.button
  local group = button:CreateAnimationGroup()
  local function Alpha(from, to, order, seconds)
    local a = group:CreateAnimation("Alpha"); a:SetFromAlpha(from); a:SetToAlpha(to); a:SetOrder(order); a:SetDuration(seconds); return a
  end
  local function Move(x, y, order, seconds)
    local a = group:CreateAnimation("Translation"); a:SetOffset(x, y); a:SetOrder(order); a:SetDuration(seconds); return a
  end
  local function Turn(degrees, order, seconds)
    local a = group:CreateAnimation("Rotation"); a:SetDegrees(degrees); a:SetOrigin("CENTER", 0, 0); a:SetOrder(order); a:SetDuration(seconds); return a
  end
  -- One Scale on the button reaches everything: children inherit it, and a
  -- pixel-perfect border (StyleBorder, ignoring the parent scale) follows the
  -- button's corners it is anchored to. A second Scale aimed at the border
  -- would double it up.
  local function Grow(from, to, order, seconds)
    local a = group:CreateAnimation("Scale"); a:SetOrigin("CENTER", 0, 0); a:SetOrder(order); a:SetDuration(seconds)
    if a.SetScaleFrom then a:SetScaleFrom(from, from); a:SetScaleTo(to, to) else a:SetScale(to / from, to / from) end
    return a
  end
  -- The button's own size is secret inside a container; the display's is not.
  local _, height = Display.Dimensions(data)
  local hop = math.max(4, (tonumber(height) or 30) * 0.25)
  if kind == "start" then
    -- The elements (Display.ElementHolder: borders, texts, glows) are held
    -- at alpha 0 by an animation of the group aimed at the holder while a
    -- Start animation moves the icon, and reappear when it ends. Only an
    -- animation reaches them: the client plays the group itself, with no
    -- Lua scripts run and no progress queries allowed. Fade In needs none,
    -- as the button's alpha carries them.
    if animType ~= "fade" then
      local elements = Display.ElementHolder(native)
      local hold = group:CreateAnimation("Alpha"); hold:SetTarget(elements)
      hold:SetFromAlpha(0); hold:SetToAlpha(0); hold:SetOrder(1); hold:SetDuration(duration)
    end
    if animType == "fade" then Alpha(0, 1, 1, duration)
    elseif animType == "zoom" then Grow(0.5, 1, 1, duration); Alpha(0, 1, 1, duration)
    elseif animType == "spin" then Turn(-360, 1, duration); Alpha(0, 1, 1, duration)
    elseif animType == "bounce" then Move(0, hop, 1, duration / 2); Move(0, -hop, 2, duration / 2) end
  else
    group:SetLooping("REPEAT")
    if animType == "pulse" then Alpha(1, 0.4, 1, duration / 2); Alpha(0.4, 1, 2, duration / 2)
    elseif animType == "spin" then Turn(-360, 1, duration)
    elseif animType == "wobble" then Turn(8, 1, duration / 4); Turn(-16, 2, duration / 2); Turn(8, 3, duration / 4)
    elseif animType == "bounce" then Move(0, hop, 1, duration / 2); Move(0, -hop, 2, duration / 2) end
  end
  return group
end
local function StyleAuraAnimations(native, data)
  local button = native.button
  native.auraAnims = native.auraAnims or {}
  for _, kind in ipairs({"start", "main"}) do
    local animType, duration = Display.AuraAnimation(data, kind)
    local current = native.auraAnims[kind]
    if current and (current.type ~= animType or current.duration ~= duration) then
      if kind == "start" then button:RemoveAuraAssignedAnimation(current.group) else button:RemoveAuraShownAnimation(current.group) end
      current.group:Stop()
      native.auraAnims[kind] = nil
      current = nil
    end
    if not current and animType ~= "none" then
      local group = BuildAuraAnimation(native, data, kind, animType, duration)
      if kind == "start" then button:AddAuraAssignedAnimation(group) else button:AddAuraShownAnimation(group) end
      native.auraAnims[kind] = {type = animType, duration = duration, group = group}
    end
  end
end

-- ForeverAuras: the parts of a button's styling are timed for the profiler
-- (/fa pprint), so a slow build of many displays can be read (issue #136).
local function Style(native, data, region)
  Private.StartProfileSystem("aura (modern) - style: appearance")
  Display.StyleAppearance(native, Display.PrepareConditionAppearance(data), ElementFrame, StyleText, StyleGlow)
  Private.StopProfileSystem("aura (modern) - style: appearance")
  Private.StartProfileSystem("aura (modern) - style: conditions")
  Display.ApplyPresentConditions(native, data, region and region.secretAuraGates)
  Display.ApplyConditionAppearance(native, region, data, true)
  Private.StopProfileSystem("aura (modern) - style: conditions")
  Private.StartProfileSystem("aura (modern) - style: eraser")
  if Display.StyleEraser then Display.StyleEraser(native, data) end
  Private.StopProfileSystem("aura (modern) - style: eraser")
  -- Editor samples stay shown; only live buttons flash. Both play the aura animations.
  Private.StartProfileSystem("aura (modern) - style: animations")
  if not native.preview then StyleFlash(native, data) end
  StyleAuraAnimations(native, data)
  Private.StopProfileSystem("aura (modern) - style: animations")
end

local function SpellIDMap(values)
  local ids = {}
  for _, value in ipairs(values or {}) do ids[tonumber(value)] = true end
  return next(ids) and ids or nil
end

local function RawCandidateFilters(data)
  local trigger = Display.GetTrigger(data)
  -- Total Duration: "<=" is Blizzard's own limit; "=" also narrows the
  -- candidates before the gate (StyleDurationGate) picks the exact one.
  local totalOp, total = Display.TotalFilter(trigger)
  local filters = {maxDuration = totalOp == "<=" and total + 0.05 or totalOp == "=" and total + 0.5 or nil}
  -- Rank and exact selections form one union; ignored exact IDs still win.
  if Display.UsesSpellIDs(trigger) or Display.UsesRankSpellIDs(trigger) then
    filters.includeSpellIDs = SpellIDMap(Display.GetSpellIDs(trigger, true)) or {}
  end
  if Display.UsesExcludedSpellIDs(trigger) then filters.excludeSpellIDs = SpellIDMap(trigger.excludedAuraSpellIDs) end
  for _, field in ipairs(Display.booleanFilters) do
    if Display.FilterApplies(field[1], trigger) and (not IsNameplateFilter(field[1]) or trigger.unit == "nameplate") then filters[field[1]] = trigger[field[1]] end
  end
  for _, field in ipairs({"includeDispelTypes", "excludeDispelTypes"}) do
    if next(trigger[field] or {}) then
      filters[field] = {}
      for name, value in pairs(trigger[field]) do filters[field][name] = value end
    end
  end
  return filters
end
Display.RawCandidateFilters = RawCandidateFilters

local function CandidateFilters(data)
  return Display.MergedCandidateFilters and Display.MergedCandidateFilters(data) or RawCandidateFilters(data)
end

-- The editor always renders public samples; live containers remain disabled.
-- Samples depend only on the settings, which Apply restyles; unit and roster
-- changes keep samples already drawn for the same settings.
local function RefreshPreview(region)
  local native = region.blizzardAuraDisplay
  native.previewHasAuras = IsPreview()
  if native.previewHasAuras then
    if not (region.secretAuraSamplesActive and native.previewStyled == native.data) then
      Display.ShowPreview(region, native.data, function(sample, data)
        Display.StyleAppearance(sample, Display.PrepareConditionAppearance(data), ElementFrame, StyleText, StyleGlow)
      end)
      native.previewStyled = native.data
    end
    -- In a Modern Aura Group the samples line up like the live auras.
    Display.ArrangeFlowPreview(Display.FlowGroup(native.data))
  else
    -- The editor's boxes go back to their own places.
    Display.RestorePreviewRegion(region)
    -- ForeverAuras: the group's box follows the members still previewed;
    -- arranged again rather than restored, which threw it away whenever one
    -- member left the preview while the editor stayed open.
    Display.HidePreview(region)
    local flowGroup = Display.FlowGroup(native.data)
    if flowGroup and WeakAuras.IsOptionsOpen() then Display.ArrangeFlowPreview(flowGroup) else Display.RestoreGroupPreview(flowGroup) end
  end
  Suppress(region)
  if IsPreview() then UpdatePreviewNotice(region) end
end

local function ConfigureProcessing(container, trigger)
  container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
end

local function ConfigureUnitGlow(instance, region, data)
  local native = instance.unitGlow
  if data.anchorFrameType ~= "UNITFRAME" or not data.blizzardAuraDisplay.unitGlow then
    if native then native.container:SetEnabled(false); native.container:Hide() end
    return
  end
  local trigger = Display.GetTrigger(data)
  if not native then
    native = {container = CreateFrame("AuraContainer", nil, region, "CustomAuraContainerTemplate")}
    Display.NoteAllocation(region, native.container)
    instance.unitGlow = native
    native.container:SetEnabled(false)
    ConfigureProcessing(native.container, trigger)
    native.container:AddAuraSlot("UnitGlow", FilterString(trigger), {
      candidateFilters = CandidateFilters(data),
      initializeFrame = function(button)
        native.button = button
        button:SetFrameLevel(native.container:GetFrameLevel() + 1)
        button:SetAllPoints(native.container)
        button:EnableMouse(false)
        native.overlay = CreateFrame("Frame", nil, button)
        native.overlay:SetAllPoints(button)
        native.overlay:SetFrameLevel(native.container:GetFrameLevel() + 2)
        StyleGlow(native, data, true)
      end,
    })
  else
    native.container:SetEnabled(false)
    StyleGlow(native, data, true)
  end
  ConfigureProcessing(native.container, trigger)
  native.container:SetAuraSlotSortMethod("UnitGlow", Display.SortOrder(data, trigger))
  native.container:SetAuraSlotFilterString("UnitGlow", FilterString(trigger))
  native.container:SetAuraSlotCandidateFilters("UnitGlow", CandidateFilters(data))
end

local function CompactUnits(data)
  -- In a Modern Aura Group on the screen, units are always chained.
  if Display.FlowGroup(data) and not Display.FlowFrameMode(data) then return Capacity(Display.GetTrigger(data), data) > 1 end
  return data.anchorFrameType ~= "UNITFRAME" and not Display.UsesNameplates(data)
    and Capacity(Display.GetTrigger(data), data) > 1
end

function Display.IconsPerRow(data)
  if Display.FlowGroup(data) or Display.DrawsOne(data) or Display.UsesGate(data) or CompactUnits(data) then return end
  -- One icon has nothing to wrap, and a display limited to one aura is drawn
  -- with an aura slot (WantsSlot), which has no group layout to set: the row
  -- layout below would raise "aura group 'Auras' was not found".
  if Display.MaxAuras(data) == 1 then return end
  local count = tonumber(data.blizzardAuraDisplay and data.blizzardAuraDisplay.perRow)
  if count and count >= 1 then return math.floor(count) end
end

-- direction: RIGHT, LEFT, UP, DOWN, CENTER_HORIZONTAL or CENTER_VERTICAL.
-- rows: where new rows go (UP or DOWN for rows, LEFT or RIGHT for columns).
-- Returns the corner the flow starts from, the point that places the
-- container, and the horizontal and vertical directions.
function Display.WrapLayout(direction, rows)
  local vertical = direction == "UP" or direction == "DOWN" or direction == "CENTER_VERTICAL"
  local horizontal, verticalDirection
  if vertical then
    horizontal = rows == "LEFT" and "LEFT" or "RIGHT"
    verticalDirection = direction == "UP" and "UP" or "DOWN"
  else
    horizontal = direction == "LEFT" and "LEFT" or "RIGHT"
    verticalDirection = rows == "UP" and "UP" or "DOWN"
  end
  local corner = (verticalDirection == "UP" and "BOTTOM" or "TOP") .. (horizontal == "LEFT" and "RIGHT" or "LEFT")
  local point = corner
  if direction == "CENTER_HORIZONTAL" then point = verticalDirection == "UP" and "BOTTOM" or "TOP"
  elseif direction == "CENTER_VERTICAL" then point = horizontal == "LEFT" and "RIGHT" or "LEFT" end
  return corner, point, horizontal, verticalDirection, vertical
end

function Display.ApplyFlowWrap(container, corner, horizontal, verticalDirection, vertical, perRow, width, height, spacing)
  container:SetFlowLayoutAxis(vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
  container:SetFlowLayoutAnchorPoint(corner)
  container:SetFlowLayoutGrowthDirection(horizontal == "LEFT" and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
    verticalDirection == "UP" and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
  local size = vertical and height or width
  if container.SetFlowLayoutMaximumLineSize then
    container:SetFlowLayoutMaximumLineSize(perRow and perRow * size + (perRow - 1) * spacing + 0.5 or nil)
  end
end

local function ApplyWrap(container, direction, rows, perRow, width, height, spacing)
  local corner, _, horizontal, verticalDirection, vertical = Display.WrapLayout(direction, rows)
  Display.ApplyFlowWrap(container, corner, horizontal, verticalDirection, vertical, perRow, width, height, spacing)
end
Display.ApplyWrap = ApplyWrap

local function AnchorWrappedList(container, region, data)
  local settings = data.blizzardAuraDisplay
  local _, point = Display.WrapLayout(Display.Growth(data), settings.rowGrowth)
  container:ClearAllPoints()
  container:SetPoint(point, region, point)
end

-- ForeverAuras: where a single-aura display's one slot button goes: the
-- region's corner for the growth direction, or its centre. Used by Layout,
-- and by Create for a slot button made under aura restrictions, which the
-- client locks the moment it is made (seen in game: after a reload in
-- combat the button, placed only here, had no position at all, so the
-- countdown and the other texts on it never showed).
local function PlaceSlotButton(button, region, data, width, height)
  local direction = Display.Growth(data)
  local anchor = direction == "LEFT" and "TOPRIGHT" or direction == "UP" and "BOTTOMLEFT" or "TOPLEFT"
  local centered = direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL"
  button:SetSize(width, height)
  button:ClearAllPoints()
  if centered then button:SetPoint("CENTER", region, "CENTER")
  else button:SetPoint(anchor, Display.ContentAnchor(region), anchor) end
end

local function Layout(native, region, data)
  local width, height = Display.Dimensions(data)
  local settings = data.blizzardAuraDisplay
  -- The single-aura drawing pins the one slot to the region's top-left corner.
  local direction = Display.Growth(data)
  local vertical = direction == "UP" or direction == "DOWN" or direction == "CENTER_VERTICAL"
  local anchor = direction == "LEFT" and "TOPRIGHT" or direction == "UP" and "BOTTOMLEFT" or "TOPLEFT"
  local container = native.container
  local perRow = Display.IconsPerRow(data)
  if perRow then
    local spacing = settings.spacing or 6
    AnchorWrappedList(container, region, data)
    ApplyWrap(container, direction, settings.rowGrowth, perRow, width, height, spacing)
    container:SetAuraGroupLayout("Auras", {elementWidth = width, elementHeight = height, elementSpacing = spacing, lineSpacing = spacing})
    container:SetAuraGroupMaxFrameCount("Auras", Display.MaxAuras(data))
    return
  end
  if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(nil) end
  container:ClearAllPoints()
  local centered = direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL"
  -- In a Modern Aura Group the content starts where the previous display ends.
  if centered then container:SetPoint("CENTER", region, "CENTER")
  else Display.AnchorToContent(container, anchor, region, anchor) end
  -- An aura slot's button is placed here, where the group's one button would
  -- be laid out; a slot has no group layout or count to set.
  if native.slotMain then
    -- The button hangs from the region, never from its container: a container
    -- the client has locked keeps its old place, and a button anchored to it
    -- stayed where the display used to be after the display moved.
    for _, entry in ipairs(native.buttons) do
      local button = entry.button
      -- The placement Create gave the button, still current: nothing to write.
      local placed = button.faSlotPlaced
      button.faSlotPlaced = nil
      if placed and placed.region == region and placed.data == data and placed.width == width and placed.height == height
        and placed.growth == Display.Growth(data) then
        -- kept as placed
      elseif not pcall(PlaceSlotButton, button, region, data, width, height) then
        -- Access denied (a button made under restrictions keeps the place
        -- Create gave it): the display is applied again when the
        -- restrictions end (SecretAuraSingle.lua, TakePendingRelayout).
        if Display.NotePendingRelayout then Display.NotePendingRelayout(region) end
      end
    end
    return
  end
  container:SetFlowLayoutAxis(vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
  container:SetFlowLayoutAnchorPoint(anchor)
  container:SetFlowLayoutGrowthDirection(direction == "LEFT" and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
    direction == "UP" and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
  local _, flowSpacing = Display.FlowGrowth(data)
  local spacing = flowSpacing or settings.spacing or 6
  -- A Modern Aura Group measures a list by its container, so it uses the compact
  -- layout whose width is exactly the icons shown.
  -- Only an Aura(s) Found list without a gate or Remaining Time is measured that way;
  -- a fixed icon keeps slots of exactly its size.
  local trigger = Display.GetTrigger(data)
  local measured = trigger and Display.ShowOn(trigger) == "showOnActive" and not Display.UsesGate(data)
    and not (Display.RemainingRange and Display.RemainingRange(trigger))
  local compact = not centered and (CompactUnits(data) or flowSpacing ~= nil and measured)
  -- The Total Duration and Stack Count gates stack every candidate on the same
  -- spot: only the one that passes is drawn, so the others must not take space.
  if Display.UsesGate(data) then spacing = -(vertical and height or width) end
  -- Empty native containers are one pixel wide/high. Reserve that pixel after
  -- occupied content too, then subtract it in the anchor chain, without reading sizes.
  container:SetAuraGroupLayout("Auras", {
    elementWidth = width + (compact and not vertical and spacing + 1 or 0),
    elementHeight = height + (compact and vertical and spacing + 1 or 0),
    elementSpacing = compact and -1 or spacing,
  })
  container:SetAuraGroupMaxFrameCount("Auras", Display.MaxAuras(data))
end

local function BuildButton(container, button, withBox)
  local native = {container = container}
  native.button = button
  button:EnableMouse(false)
  -- ForeverAuras: Grid buttons (withBox) get a box every piece of artwork
  -- hangs from: the button's rectangle, unless the member's own X/Y Offset
  -- moves it (Display.SetBoxOffset), so the artwork of a button the client
  -- places in a grid cell can sit beside its cell. Other buttons have no box
  -- and their artwork hangs from the button itself (Display.Box falls back to
  -- it): no extra frame per button outside a Grid. Made here, inside the
  -- client's initializeFrame, never later under restrictions.
  if withBox then
    -- ForeverAuras (dev.77): the box opts out of untrusted layout scripts
    -- like the clip and the chain's frames (a Centered row hangs it, through
    -- the chain, from the shadows' end: a secret-sized container)
    native.box = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
    native.box:SetAllPoints(button)
    native.box:EnableMouse(false)
  end
  local box = native.box or button
  -- Whether the button's box is rounded to whole pixels is decided per
  -- display in StyleAppearance: only inside a Modern Aura Group, whose row is
  -- laid out on the pixel grid. Elsewhere a rounded box (34x32 units at 1.2
  -- pixels a unit is 41x38 pixels, not 40.8x38.4) ends a row short of the
  -- plain icons beside it, which WeakAuras never rounds.
  -- Gate clip (Total Duration, Remaining Time, Stack Count): created before
  -- any element on every display type (StyleDurationGate). It does not
  -- clip while no gate is used.
  native.gateClip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
  Display.ClipChildren(native.gateClip)
  native.gateClip:SetAllPoints(box)
  native.gateText = button:CreateFontString(nil, "BACKGROUND")
  for _, area in ipairs({"inner", "outer"}) do
    native[area] = CreateFrame("Frame", nil, button)
    native[area]:SetPoint("CENTER", box, "CENTER")
    native[area]:EnableMouse(false)
  end
  native.border = (native.gateClip or button):CreateTexture(nil, "BACKGROUND")
  native.border:SetAllPoints(box)
  -- Eraser for the Missing look (SecretAuraSingle.lua, Display.StyleEraser):
  -- drawn with blending disabled inside a frame buffer, it overwrites what is
  -- beneath the button with nothing while the button is shown. On the button
  -- itself, outside the gate clip, so it can reach past the icon.
  native.eraser = button:CreateTexture(nil, "BACKGROUND", nil, -8)
  native.eraser:SetColorTexture(0, 0, 0, 0)
  native.eraser:SetBlendMode("DISABLE")
  native.eraser:Hide()
  local base = ElementFrame(native, "sharedBase")
  native.icon = base:CreateTexture(nil, "ARTWORK")
  -- Placed like the icons of other displays (not rounded to whole pixels), so rows line up.
  native.icon:SetSnapToPixelGrid(false)
  native.icon:SetTexelSnappingBias(0)
  button:SetIcon(native.icon)
  native.cooldown = CreateFrame("Cooldown", nil, base, "CooldownFrameTemplate")
  native.cooldown:SetAllPoints(native.icon)
  native.cooldown:SetDrawBling(false)
  native.cooldown:SetHideCountdownNumbers(true)
  local numbers = native.cooldown:GetCountdownFontString()
  if numbers then
    -- Keep the digits independent of the swipe's frame level. The font string
    -- changes parent before Blizzard adopts the cooldown; it stays on this
    -- holder for the button's lifetime.
    local holder = CreateFrame("Frame", nil, native.gateClip)
    native.countdownTextHolder = holder
    holder:SetAllPoints(box)
    holder:EnableMouse(false)
    holder:Hide()
    numbers:SetParent(holder)
    numbers:SetDrawLayer("OVERLAY", 0)
  end
  button:SetDurationCooldown(native.cooldown)
  local overlay = CreateFrame("Frame", nil, Display.ElementHolder(native))
  native.overlay = overlay
  overlay:SetAllPoints(box)
  overlay:SetFrameLevel(native.cooldown:GetFrameLevel() + 1)
  return native
end
Display.BuildNativeButton = BuildButton

-- A display that draws one aura (DrawsOne: Always, Missing, Remaining Time
-- on an icon, or a list limited to one) gets an aura slot instead of an aura
-- group: a group is built as a batch of buttons the client sizes and lays
-- out, a slot is one button placed by this file (Layout), so the container
-- is cheaper to build and to re-read. Lists, gated displays (which stack
-- candidates) and Modern Aura Group containers keep the group.
local function WantsSlot(data, inFlow, container)
  return not inFlow and container.AddAuraSlot ~= nil and Display.MaxAuras(data) == 1
end
Display.WantsSlot = WantsSlot

-- ForeverAuras (dev.34 review, reserve fix): the container is allocated
-- first and the rest of the construction runs guarded, so a container whose
-- setup fails part way is owned (retained for cleaning, disabled, hidden)
-- before the error reaches the caller: nothing allocated is left untracked.
local CreateBody
local function Create(region, data)
  local display = {buttons = {}, data = data}
  local container, inFlow = Display.CreateAuraContainer(region, data)
  display.container = container
  local ok, err = pcall(CreateBody, display, container, inFlow, region, data)
  if not ok then
    pcall(container.SetEnabled, container, false)
    pcall(container.Hide, container)
    RetainFrame(region, container)
    error(err, 0)
  end
  return display
end
function CreateBody(display, container, inFlow, region, data)
  -- ForeverAuras (dev.31 diagnostics): the build history notes the container.
  if Display.NoteCarrierEvent then Display.NoteCarrierEvent(region, "container", inFlow and "flow" or "plain") end
  -- Made for a Modern Aura Group (SecretAuraFlow.lua); Apply replaces it on a change.
  display.flowContainer = inFlow
  container:SetEnabled(false)
  local trigger = Display.GetTrigger(data)
  ConfigureProcessing(container, trigger)
  container:SetPoint("TOPLEFT", region, "TOPLEFT")
  -- ForeverAuras (combat-reload probe): a display first built while
  -- restrictions are on (a reload in combat) styles each button here, in
  -- the client's initializeFrame call, which runs before the client
  -- restricts the button (Blizzard_AuraContainerFrameProviders.lua);
  -- styled later, in ApplyInstance, the button was already forbidden (seen
  -- in game, 1.1.0-dev.6). Failures are counted, not ignored, so an
  -- incomplete build is not taken for a finished one (ApplyInstance).
  -- Whether this is a probe build is decided once, when the build starts
  -- (Apply, native.probeBuild), for its whole lifetime, reserve included.
  -- ForeverAuras (dev.34, reserve fix): also for ANY container made while
  -- restrictions are on, whatever the display's build was classed as when
  -- it began: a background reserve created after a fight started (the
  -- paced drain goes on in combat) had its buttons styled by ApplyInstance
  -- after the callback, when the client had already locked them (seen in
  -- game: ten "SetSize on bad self" after a combat reload; reproduced by
  -- the reviewer on the actual source). Early styling per created instance
  -- is separate from the whole-build probe ownership (native.probeBuild).
  display.styleEarly = ((region.blizzardAuraDisplay and region.blizzardAuraDisplay.probeBuild) or Restricted()) or nil
  display.earlyOK, display.earlyFailed = 0, 0
  -- ForeverAuras (diagnostic, with the build report on): what the client's
  -- callback finds, for the buttons it adds after the first batch: whether
  -- the button and its container can be touched at all, before anything is
  -- built on it (the probe that found the locked containers, rc.28; its
  -- chat print is retired with the build reports).
  display.creating = true
  if type(Display.summaryCounts) == "table" then Display.summaryCounts.containersSetUp = (Display.summaryCounts.containersSetUp or 0) + 1 end   -- (1.2.5 summary: main containers reaching setup)
  -- ForeverAuras (independent carriers, SecretAuraFlow.lua): a list in such
  -- a row gets a box per button, placed at the row through the carrier
  -- translation, here inside the client's callback. A refused placement is
  -- counted like a refused style: the build is not taken for complete, and
  -- the display says so in the editor.
  -- The mode is fixed for the container's lifetime (the box exists or not
  -- per button); a display whose mode changes gets new containers
  -- (ApplyDisplay). The placement uses the display's current data, as a
  -- later button's styling does; the editor warning comes from the row
  -- layout (SetFlowEnd), which places every box again after this.
  local independent = inFlow and Display.FlowIndependent ~= nil and Display.FlowIndependent(data) or false
  display.independent = independent
  -- ForeverAuras (cell chain, SecretAuraChain.lua): a filtered list in an
  -- opted-in row gets a box per button too (its chain places it), and its
  -- records are counted so an eleventh is handled (NoteChainOverflow).
  local chained = inFlow and Display.FlowChain ~= nil and Display.FlowChain(data) ~= nil
  display.chained = chained
  local withBox = independent or chained
  -- ForeverAuras: the client's callbacks on this container, for the
  -- /fa carriers print: those made with the container and the later ones (a
  -- raised count or a later batch), each as attempts, buttons built and
  -- styled, and failures (with the last failed operation), and how many of
  -- the later ones ran under aura restrictions. Later attempts are also
  -- summed on the region, so a container made again (a rebuild, a mode
  -- change) does not forget them; a reload does (dev.19 review).
  -- Counts: "initial" callbacks are constructed here and styled later by
  -- ApplyInstance, so they count as constructed (built, box placed), not
  -- styled; a "later" callback is built only when constructed, styled and
  -- placed. A callback fails once however many of its operations did
  -- (operation failures are counted apart), and a later one is also counted
  -- under restrictions as a success or a failure, so a mixed run can be read
  -- (dev.20 review). The history on the region sums later callbacks across
  -- replaced containers; it is history, not the current state.
  display.callbacks = {
    initial = {attempts = 0, constructed = 0, failed = 0, operations = 0},
    later = {attempts = 0, built = 0, failed = 0, operations = 0, restricted = 0, restrictedBuilt = 0, restrictedFailed = 0},
  }
  local function History(field)
    local owner = region.blizzardAuraDisplay
    if not owner then return end
    owner.carrierHistory = owner.carrierHistory or {attempts = 0, restricted = 0, failed = 0, built = 0, restrictedBuilt = 0, restrictedFailed = 0}
    owner.carrierHistory[field] = owner.carrierHistory[field] + 1
  end
  local function PlaceBox(native)
    if not independent then return true end  -- a chained list's box is placed by its chain link (StyleDurationGate)
    local ok, result, why = pcall(Display.PlaceCarrierBox, native, region, display.data)
    if ok and result == true then return true end
    -- The current refusal, not the first one ever (dev.19 review).
    display.carrierBoxError = ok and tostring(why) or tostring(result)
    -- Said in the editor now, from the current state. The record is not in
    -- the instance's list yet (appended once, at the end), so it is passed
    -- along (dev.20 review: the first late refusal showed no warning).
    if Display.PublishCarrierWarnings then pcall(Display.PublishCarrierWarnings, region, display.data, native) end
    return false
  end
  local function initializeFrame(button)
    local native
    local phase = display.creating and "initial" or "later"
    local counter = display.callbacks[phase]
    local restricted = phase == "later" and Restricted()
    counter.attempts = counter.attempts + 1
    if restricted then counter.restricted = counter.restricted + 1 end
    if phase == "later" then History("attempts"); if restricted then History("restricted") end end
    local callbackFailed = false
    local function Count(_, field, failure)
      -- An operation failed; the callback fails once.
      counter.operations = counter.operations + 1
      display.lastCallbackFailure = phase .. ": " .. tostring(failure)
      if callbackFailed then return end
      callbackFailed = true
      counter.failed = counter.failed + 1
      if phase == "later" then
        History("failed")
        if restricted then counter.restrictedFailed = counter.restrictedFailed + 1; History("restrictedFailed") end
      end
    end
    if display.styleEarly then
      -- A button that could not be built is counted; the failure stops the
      -- build (Apply). Other builds raise as before.
      local okBuild, built = pcall(BuildButton, container, button, withBox)
      if not okBuild then
        display.earlyFailed = display.earlyFailed + 1
        display.styleError = display.styleError or tostring(built)
        Count(phase, "failed", "build: " .. tostring(built))
        return
      end
      native = built
    elseif Restricted() then
      -- ForeverAuras: a button the client adds under aura restrictions to a
      -- display built before them (a container made for its reserve, or a
      -- raised frame count) can already be locked when this runs (seen in
      -- game with 48 displays loaded: "EnableMouse on bad self" from
      -- BuildButton, ten times over). It is left as the client made it and
      -- the display is applied again when the restrictions end, which
      -- builds and styles it (SecretAuraSingle.lua, TakePendingRelayout).
      local okBuild, built = pcall(BuildButton, container, button, withBox)
      if not okBuild then
        -- The client never offers this frame again, so the re-apply must
        -- make new containers (ApplyDisplay, rebuildFresh): applied in
        -- place it would keep the bare button, an empty slot in the list
        -- (seen in game: holes in a buff list that lasted past the fight).
        local owner = region.blizzardAuraDisplay
        if owner then owner.rebuildFresh = true end
        if Display.NotePendingRelayout then Display.NotePendingRelayout(region) end
        Count(phase, "failed", "build: " .. tostring(built))
        return
      end
      native = built
    else
      local okBuild, built = pcall(BuildButton, container, button, withBox)
      if not okBuild then Count(phase, "failed", "build: " .. tostring(built)); error(built, 0) end
      native = built
    end
    -- ForeverAuras (cell chain): the record knows its display, region and
    -- index, so its styling can chain it to the previous record.
    native.region, native.instance, native.record = region, display, #display.buttons + 1
    -- ForeverAuras (independent carriers): the box goes on the row before the
    -- button is styled, while nothing of the button's is restricted yet.
    local boxPlaced = PlaceBox(native)
    if not boxPlaced then Count(phase, "failed", "box: " .. tostring(display.carrierBoxError)) end
    -- The buttons made with the container are styled by ApplyInstance right
    -- after, once; only a button the client adds later (a raised frame count)
    -- is styled here. Styling twice was a fifth of every display's build.
    local styled = true
    if display.styleEarly then
      local ok, err = pcall(Style, native, display.data, region)
      native.styledEarly = ok or nil
      styled = ok
      if ok and boxPlaced then display.earlyOK = display.earlyOK + 1
      else
        display.earlyFailed = display.earlyFailed + 1
        display.styleError = display.styleError or (ok and display.carrierBoxError or tostring(err))
      end
      if not ok then Count(phase, "failed", "style: " .. tostring(err)) end
    elseif display.applied then
      if Restricted() then
        -- As above: a refused styling is made good when the restrictions end.
        local ok, err = pcall(Style, native, display.data, region)
        styled = ok
        if not ok then Count(phase, "failed", "style: " .. tostring(err)) end
        if (not ok or not boxPlaced) and Display.NotePendingRelayout then Display.NotePendingRelayout(region) end
      else
        local ok, err = pcall(Style, native, display.data, region)
        if not ok then Count(phase, "failed", "style: " .. tostring(err)); error(err, 0) end
        if not boxPlaced and Display.NotePendingRelayout then Display.NotePendingRelayout(region) end
      end
    elseif not boxPlaced and Display.NotePendingRelayout then
      Display.NotePendingRelayout(region)
    end
    if not callbackFailed and boxPlaced and styled then
      if phase == "initial" then counter.constructed = counter.constructed + 1
      else
        counter.built = counter.built + 1
        History("built")
        if restricted then counter.restrictedBuilt = counter.restrictedBuilt + 1; History("restrictedBuilt") end
      end
    end
    display.buttons[#display.buttons + 1] = native
  end
  if WantsSlot(data, inFlow, container) then
    local width, height = Display.Dimensions(data)
    local ok = pcall(container.AddAuraSlot, container, "Auras", FilterString(trigger), {
      candidateFilters = CandidateFilters(data),
      sortMethod = Display.SortOrder(data, trigger),
      initializeFrame = function(button)
        -- ForeverAuras: placed here, before the client locks the button
        -- (see PlaceSlotButton). The placement is remembered on the button,
        -- so the Layout of this same build does not write it again (which
        -- a locked button refuses, and which then queued a needless
        -- rebuild after the fight, rc.15 review). In a build under
        -- restrictions a failed placement is counted with the build's
        -- failures (rc.17 review); Layout then places the button later.
        local placed, err = true, nil
        if display.styleEarly then placed, err = pcall(PlaceSlotButton, button, region, data, width, height)
        else PlaceSlotButton(button, region, data, width, height) end
        if placed then
          button.faSlotPlaced = {region = region, data = data, width = width, height = height, growth = Display.Growth(data)}
        else
          display.earlyFailed = display.earlyFailed + 1
          display.styleError = display.styleError or tostring(err)
        end
        initializeFrame(button)
      end,
    })
    if ok and display.buttons[1] then
      display.slotMain = true
      display.creating = nil
      return display
    end
    -- The client refused the slot: the group below draws instead.
    wipe(display.buttons)
  end
  display.slotMain = false
  container:AddAuraGroup("Auras", FilterString(trigger), {
    maxFrameCount = Display.MaxAuras(data),
    candidateFilters = CandidateFilters(data),
    initializeFrame = initializeFrame,
  })
  display.creating = nil
  return display
end
-- Frames cannot be destroyed. Ones no longer used are hidden under a hidden
-- holder, outside every display's frame tree.
local retiredHolder
function Display.RetireFrame(frame)
  if not frame then return end
  if type(Display.summaryCounts) == "table" then Display.summaryCounts.retirementAttempts = (Display.summaryCounts.retirementAttempts or 0) + 1 end   -- (1.2.5 summary: attempts, a refused one counts too)
  retiredHolder = retiredHolder or CreateFrame("Frame")
  retiredHolder:Hide()
  if frame.SetEnabled then frame:SetEnabled(false) end
  frame:Hide()
  frame:ClearAllPoints()
  frame:SetParent(retiredHolder)
end

-- True when a frame's current strata or level differs from the wanted one.
-- Containers made for a Modern Aura Group report secret values; those are
-- always set, as they cannot be compared.
local function Changed(current, wanted)
  return issecretvalue(current) or current ~= wanted
end

-- Like Changed, for a native container whose strata or level this file sets.
-- A secret current value is compared with the value last set here (stored on
-- the instance under key), so a Modern Aura Group container is not re-layered,
-- walking all of its buttons, on every refresh. The stored values are cleared
-- whenever the container changes parent, which resets its layering.
local function LayerChanged(instance, key, current, wanted)
  if issecretvalue(current) then return instance[key] ~= wanted end
  return current ~= wanted
end

local unitFrameGlowSizes = setmetatable({}, {__mode = "k"})

local function AnchorUnitGlow(container, frame)
  local size = unitFrameGlowSizes[frame]
  if not size then
    size = {x = 0, y = 0}
    unitFrameGlowSizes[frame] = size
    TimedHookScript(frame, "OnSizeChanged", function() Display.UnitFramesChanged() end)
  end
  local width, height = frame:GetSize()
  if not issecretvalue(width) and not issecretvalue(height) then
    -- Proc artwork has a transparent inset. Use fixed layout margins, not a
    -- looping Scale animation. Keep the last public margins if layout is secret.
    size.x, size.y = width * 0.2, height * 0.2
  end
  container:SetPoint("TOPLEFT", frame, "TOPLEFT", -size.x, size.y)
  container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size.x, -size.y)
end

function Display.UpdateDetachedFrameLevels(region)
  local native = region.blizzardAuraDisplay
  if not native or not native.active then return end
  local level = region:GetFrameLevel()
  for _, instance in ipairs(native.instances) do
    -- A Modern Aura Group's containers may report a secret level; they sit
    -- just above the region, which the reserve below covers.
    if not Locked(instance.container) then
      local containerLevel = instance.container:GetFrameLevel()
      if not issecretvalue(containerLevel) then level = math.max(level, containerLevel) end
    end
  end
  -- Reserve the native button, three levels per element, and glow/cooldown children.
  -- Only container frames are inspected; native aura buttons may be inaccessible.
  level = level + #(native.data.subRegions or {}) * 3 + 8
  for index, element in ipairs(region.subRegions or {}) do
    if element.secretAuraDetached and not Locked(element) then element:SetFrameLevel(level + index) end
  end
end

-- Ignore Dead / Ignore Disconnected: that unit's part of the display is hidden.
local function UnitIgnored(trigger, unit)
  if not unit or not trigger then return false end
  if trigger.ignoreDisconnected then
    local ok, connected = pcall(UnitIsConnected, unit)
    if ok and not issecretvalue(connected) and connected == false then return true end
  end
  if trigger.ignoreDead then
    local ok, dead = pcall(UnitIsDeadOrGhost, unit)
    if ok and not issecretvalue(dead) and dead == true then return true end
  end
  -- Ignore out of checking range (ignoreInvisible, as Aura (Legacy)): a group
  -- member too far away for the client to see has no readable auras either.
  -- Offered for groups only, and applied only there.
  if trigger.ignoreInvisible and groupModes[trigger.unit] then
    local ok, visible = pcall(UnitIsVisible, unit)
    if ok and not issecretvalue(visible) and visible == false then return true end
  end
  return false
end

-- Shared with SecretAuraGrid.lua (a grid member's group is switched off).
Display.UnitIgnored = UnitIgnored

local function ApplyUnitStatus(instance, trigger)
  local hidden = UnitIgnored(trigger, instance.visible and instance.boundUnit)
  -- Settling after a unit change (see the binding below).
  if instance.settleUntil and GetTime() < instance.settleUntil then hidden = true end
  instance.statusHidden = hidden or nil
  -- (dev.90) a container muted for the editor stays at alpha 0 (RefreshUnits)
  -- ForeverAuras 1.2.10 (Dan's reminders gone after a wipe until a reload): a container the client
  -- has locked (a death in combat) takes no alpha; before, the status was still recorded as applied,
  -- so a later event found nothing to do and the part stayed faded for the session. The write is
  -- owed instead (statusAlphaPending) and made when restrictions end (statusEvents below).
  -- ForeverAuras 1.2.10-dev.3 (Dan: reminders stuck in combat until combat drop since dev.2): alpha is
  -- not a protected write, so a container that is merely protected in combat (Display.Busy) still takes
  -- it, as it always did; only a forbidden or unparentable container (Display.Locked) owes the write.
  if not (Display.Locked and Display.Locked(instance.container)) and pcall(instance.container.SetAlpha, instance.container, (hidden or instance.previewMuted) and 0 or instance.baseAlpha or 1) then
    instance.statusAlphaPending = nil
  else
    instance.statusAlphaPending = true
  end
end

-- A protected layout can still accept the native content delegate. This is
-- only a request: no aura state or secret geometry is read, and no frame
-- configuration changes. Existing unit-refresh recovery owns any refusal.
-- Return accepted/refused request counts; ineligible containers return 0, 0.
function Display.RequestBoundAuraRefresh(container, boundUnit, unit, shown, force)
  if not (container and force and shown and unit and boundUnit == unit and container.faEnabled == true) then return 0, 0 end
  local ok = pcall(function() container:UpdateAllAuras() end)
  if ok then Private.HitchCount("UpdateAllAuras"); return 1, 0 end
  return 0, 1
end

-- unitChanged: the token may now name another unit. Every active part of
-- the display must request content for that unit while retaining its layout.
local function RefreshUnits(region, removedUnit, changedUnit, unitChanged)
  local native = region.blizzardAuraDisplay
  if not native or not native.active then return end
  if native.instanceQueue and not IsPreview() and Display.FlushInstanceQueue then Display.FlushInstanceQueue(region) end
  local data = native.data
  local trigger = Display.GetTrigger(data)
  -- No Aura (Modern) trigger drives the display right now: nothing to bind.
  if not trigger then return end
  local settings = data.blizzardAuraDisplay
  -- ForeverAuras: the parts of a refresh are timed for the profiler
  -- (/fa pprint), to read a slow build of many displays (issue #136).
  Private.StartProfileSystem("aura (modern) - units: tokens")
  local units = UnitTokens(trigger)
  Private.StopProfileSystem("aura (modern) - units: tokens")
  local growth = Display.Growth(data)
  local vertical = growth == "UP" or growth == "DOWN" or growth == "CENTER_VERTICAL"
  -- A Modern Aura Group grouped by frame places these on unit frames or
  -- nameplates itself (RelinkFlowUnits, below).
  local frameMode = Display.FlowFrameMode(data)
  -- ForeverAuras (1.3.6-dev.1, Astra's nameplate combat-end review): what a
  -- unit refresh is asked to do and what it visits, counted into the hitch
  -- capture only (/fa phitch); nothing here runs when no capture is active.
  local counting = Private.HitchCounting and Private.HitchCounting()
  -- ForeverAuras (1.3.6-dev.12, Astra's dev.10 review): changedUnit is one
  -- token (a string) or a SET of tokens (a table, from the restriction-end
  -- drain), refreshed in this one pass; the instances it names are selected
  -- BEFORE anything is asked of their containers, so an unrelated instance is
  -- neither visited nor lock-checked. A full pass (no token) covers every
  -- token; what it cannot do now it marks for the whole region again
  -- (lockedUnits), so tokens owed from earlier targeted events are no longer
  -- separately owed once that pass has run (below the loop).
  -- (Astra's dev.12 review) a token is acknowledged only when its instance's
  -- refresh has run to the end: a refresh that stops early (an error in a
  -- write) leaves it, and every token not yet reached, owed to the next drain.
  local tokenSet = type(changedUnit) == "table" and changedUnit or nil
  local owed = pendingTokens[region]
  local fullPass = not changedUnit and not removedUnit
  local selected = 0
  if counting then
    local what = "all tokens"
    if tokenSet then local n = 0; for _ in pairs(tokenSet) do n = n + 1 end; what = ("%d owed tokens, one pass"):format(n)
    elseif changedUnit then what = "one token" elseif removedUnit then what = "one removed" end
    Private.HitchCount(("units refresh %s: %s"):format(tostring(trigger.unit), what))
    Private.HitchCount("units refresh: " .. tostring(data.id))   -- (1.3.6-dev.17, diagnostic) the display
  end
  for index, instance in ipairs(native.instances) do
    local container = instance.container
    local unit = units[index]
    if changedUnit and not (tokenSet and unit ~= nil and tokenSet[unit] or unit == changedUnit) then
      -- not selected: nothing is asked of this instance
    elseif Locked(container) then
      selected = selected + 1
      -- ForeverAuras (1.3.6-dev.10/12): a targeted event owes work for the
      -- token it could not serve; a full refresh (no token) still marks the
      -- whole region as before.
      if changedUnit then
        if unit ~= nil then
          owed = owed or {}
          pendingTokens[region] = owed
          owed[unit] = true
        end
      else
        lockedUnits[region] = true
      end
      if counting then Private.HitchCount("units refresh: locked instance") end
      -- Re-read every active part for this token, not only its live picture:
      -- Always/Missing clips and row measurements must observe the same unit.
      -- Protected geometry remains deferred through lockedUnits above.
      local accepted, refused = 0, 0
      if unitChanged and instance.visible == true
        and not instance.retainedMuted and not instance.previewMuted and not IsPreview() then
        accepted, refused = Display.RequestBoundAuraRefresh(container, instance.boundUnit, unit, true, true)
        local a, r = Display.RefreshSingleContent(instance, unit, true, true)
        accepted, refused = accepted + a, refused + r
        a, r = Display.RefreshFlowContent(instance, unit, true, true)
        accepted, refused = accepted + a, refused + r
        local glow = instance.unitGlow
        if glow and glow.wanted and settings.unitGlow == true and not native.unitGlowsHidden then
          a, r = Display.RequestBoundAuraRefresh(glow.container, glow.boundUnit, unit, true, true)
          accepted, refused = accepted + a, refused + r
        end
      end
      if unitChanged and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: container %d is locked: content refresh requests accepted %d, refused %d (the full refresh waits for restrictions to end)"):format(tostring(data.id), index, accepted, refused)) end
      if counting and (accepted > 0 or refused > 0) then
        Private.HitchCount("units refresh: locked content requests accepted", accepted)
        Private.HitchCount("units refresh: locked content requests refused", refused)
      end
    else
      selected = selected + 1
      -- In a Modern Aura Group the group's mode decides (screen, unit frames or
      -- nameplates); the display's own anchor is not used for its auras.
      local unitFrames, nameplates
      if Display.FlowGroup(data) then
        unitFrames, nameplates = frameMode == "UNITFRAME", frameMode == "NAMEPLATE"
      else
        unitFrames = data.anchorFrameType == "UNITFRAME"
        nameplates = not unitFrames and Display.UsesNameplates(data)
      end
      local anchorFrame
      if unit then
        if unitFrames then
          anchorFrame = WeakAuras.GetUnitFrame(unit)
        elseif nameplates and unit ~= removedUnit then
          -- ForeverAuras: the plate's visible bar, as the flow groups use (SecretAuraFlow.lua, NameplateAnchor).
          anchorFrame = Display.NameplateAnchor and Display.NameplateAnchor(unit) or C_NamePlate.GetNamePlateForUnit(unit)
        end
      end
      if anchorFrame and anchorFrame:IsForbidden() then anchorFrame = nil end
      -- Live aura visibility must not affect the editor samples.
      Private.StartProfileSystem("aura (modern) - units: bind")
      local wouldShow = unit ~= nil and region:IsShown() and (not (unitFrames or nameplates) or anchorFrame ~= nil)
        and not native.gridMember and Display.UnitEligible(trigger, unit)
      local shown = not IsPreview() and wouldShow
      -- ForeverAuras (dev.90, Dan's A icons; Astra's order-stability note): in
      -- the editor a LIVE container that would be shown is not disabled (that
      -- made the client release every aura's button and hand them out again in
      -- another order when the editor closed); it is kept enabled and bound,
      -- hidden by alpha alone while the editor's samples draw in its place,
      -- and shown again as it is when the editor closes. Its unit events keep
      -- it current meanwhile. Only a container that is already live on this
      -- unit and parent qualifies; anything else takes the ordinary path.
      -- An erased Missing look (SecretAuraSingle.lua) draws the aura slot and
      -- the Missing look in one frame buffer: the slot's parent is that stage.
      local parent = unitFrames and data.anchorFrameParent ~= false and anchorFrame
        or (Display.MissingStage and Display.MissingStage(instance)) or region
      local muted = IsPreview() and wouldShow and container.faEnabled == true and instance.boundUnit == unit
        and container:GetParent() == parent and not Locked(container)
      if muted then shown = true end
      -- (dev.92) a container retained through the editor (QuietInstance) is live: shown again as it is when
      -- its display is loaded again, or kept muted while the editor is open
      -- (dev.93, Dan's dev.92 lines) the binding pass during the pause (the region hidden, the editor not yet
      -- open) retains a live container the same way instead of disabling it
      if editorRetaining and not shown and not instance.retainedMuted and container.faEnabled == true and not Restricted()
        and instance.boundUnit == unit and container:GetParent() == parent and not Locked(container) then
        RetainInstance(instance, region)
      end
      if instance.retainedMuted and container.faEnabled ~= true then
        -- (dev.96) retained but disabled meanwhile (an ordinary quiet): the retention is over for it, the
        -- ordinary path below parents it back and enables it
        instance.retainedMuted = nil
        retainedInstances[instance] = nil
      end
      if instance.retainedMuted and container.faEnabled == true then
        -- (dev.97) and only under a parent that is visible: moved under a hidden one, the container would
        -- hide and the client rebuild it when shown (the region's OnShow runs this pass again)
        if not IsPreview() and wouldShow and not Restricted() and parent:IsVisible() then
          -- live again: back under its parent as it is (RestoreRetained); refused, it stays retained
          if not RestoreRetained(instance, parent) then muted = true end
        else muted = true end   -- kept enabled and bound, hidden by alpha, until its display is live again
        if muted then shown = true end
      end
      -- Nothing about the container's content changes when it keeps its unit,
      -- parent, enabled state and visibility, and no nameplate was reassigned
      -- (removedUnit/changedUnit): Blizzard keeps a live container current from
      -- UNIT_AURA itself, so the enable and full refresh below are skipped then.
      -- The same holds for its anchors: they are set again only when the frame
      -- they hang from changed (unit frames and nameplates come and go).
      -- unitChanged alone does not force this refresh: enabling and refreshing
      -- every aura slot on each target change was a visible stutter; a kept
      -- token's slot is re-read in place instead (below).
      local unchanged = instance.boundUnit == unit and (container:GetParent() == parent or instance.retainedMuted)
        and container.faEnabled == true and (instance.visible == true or instance.retainedMuted or instance.previewMuted) and not removedUnit and not changedUnit
      local reanchor = not unchanged or instance.anchoredTo ~= (anchorFrame or region) or not instance.anchored
      -- ForeverAuras (dev.89, Astra's dev.88 review P2): "anchored" is committed only once the intended
      -- placement went through (below); a refused one leaves it pending and the restriction-end refresh
      -- (lockedUnits) tries again
      instance.anchoredTo = anchorFrame or region
      local placedOK = true
      -- Disabling clears native aura assignments and restarts their animations.
      if instance.boundUnit ~= unit or (container:GetParent() ~= parent and not instance.retainedMuted) then
        container:SetEnabled(false)
        if unit then container:SetUnit(unit); Private.HitchCount("container SetUnit") end
        instance.boundUnit = unit
        if container:GetParent() ~= parent then
          container:SetParent(parent)
          Private.HitchCount("container SetParent")
          instance.appliedStrata, instance.appliedLevel = nil, nil
        end
      end
      instance.baseAlpha = parent == region and 1 or data.alpha or 1
      -- Strata and level are set only when they change: each change walks
      -- every button of the container.
      local strata = (data.frameStrata == nil or data.frameStrata == 1) and parent:GetFrameStrata() or region:GetFrameStrata()
      if LayerChanged(instance, "appliedStrata", container:GetFrameStrata(), strata) then
        container:SetFrameStrata(strata)
        Private.HitchCount("container SetFrameStrata")
        instance.appliedStrata = strata
      end
      -- Kept for the Missing look: containers in a Modern Aura Group report secret levels.
      instance.drawStrata, instance.drawLevel = strata, nil
      Private.StopProfileSystem("aura (modern) - units: bind")
      Private.StartProfileSystem("aura (modern) - units: anchor")
      if unitFrames then
        -- Keep native aura content above the unit glow and its two child layers.
        local level = anchorFrame and settings.unitGlow and anchorFrame:GetFrameLevel() + unitGlowFrameLevel + 3 or parent:GetFrameLevel() + 1
        if LayerChanged(instance, "appliedLevel", container:GetFrameLevel(), level) then
          container:SetFrameLevel(level)
          instance.appliedLevel = level
        end
        instance.drawLevel = level
        if not frameMode and reanchor then
          container:ClearAllPoints()
          container:SetPoint(data.selfPoint or "CENTER", anchorFrame or region, data.anchorPoint or "CENTER", data.xOffset or 0, data.yOffset or 0)
        end
      elseif frameMode then
        -- Placed by RelinkFlowUnits.
      elseif not reanchor then
        -- Same anchor frame as before: the points stand.
      elseif nameplates then
        container:ClearAllPoints()
        if data.anchorFrameType == "NAMEPLATE" then
          -- Anchored to nameplates: the display's Position and Size settings.
          container:SetPoint(data.selfPoint or "BOTTOM", anchorFrame or region, data.anchorPoint or "TOP", data.xOffset or 0, data.yOffset or 0)
        else
          -- Nameplate unit on a screen anchor: above the plate (older auras
          -- may still carry their own offsets).
          container:SetPoint("BOTTOM", anchorFrame or region, "TOP", settings.nameplateX or 0, settings.nameplateY or 8)
        end
      else
        local direction = growth
        local anchor = direction == "LEFT" and "TOPRIGHT" or direction == "UP" and "BOTTOMLEFT" or "TOPLEFT"
        -- ForeverAuras (dev.87, Dan's D after a combat reload): under restrictions the container is not cleared
        -- before it is anchored again (the anchor below may be refused, and a container with no anchors has no
        -- place: D's main list "left nil" after its combat build); a point set again replaces its anchor
        if not Restricted() then container:ClearAllPoints() end
        if Display.IconsPerRow(data) then
          AnchorWrappedList(container, region, data)
        elseif direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL" then
          container:SetPoint("CENTER", region, "CENTER")
        elseif CompactUnits(data) and index > 1 then
          local previous = native.instances[index - 1].container
          local edge = direction == "LEFT" and "TOPLEFT" or direction == "UP" and "TOPLEFT"
            or direction == "DOWN" and "BOTTOMLEFT" or "TOPRIGHT"
          container:SetPoint(anchor, previous, edge,
            vertical and 0 or (direction == "LEFT" and 1 or -1),
            vertical and (direction == "UP" and -1 or 1) or 0)
        else
          -- In a Modern Aura Group the content starts where the previous display ends.
          placedOK = Display.AnchorToContent(container, anchor, region, anchor) and true or false
        end
      end
      if reanchor then
        instance.anchored = placedOK
        if not placedOK then lockedUnits[region] = true end
      end
      Private.StopProfileSystem("aura (modern) - units: anchor")
      Private.StartProfileSystem("aura (modern) - units: status")
      if instance.missingSlot and reanchor then
        local slotPoint
        if frameMode then slotPoint = Display.FlowUnitStart(Display.FlowGroup(data))
        elseif unitFrames then slotPoint = data.selfPoint or "CENTER"
        elseif nameplates then slotPoint = data.anchorFrameType == "NAMEPLATE" and (data.selfPoint or "BOTTOM") or "BOTTOM" end
        instance.missingSlot:ClearAllPoints()
        if not (slotPoint and pcall(instance.missingSlot.SetPoint, instance.missingSlot, slotPoint, container, slotPoint)) then
          instance.missingSlot:SetPoint("TOPLEFT", region, "TOPLEFT")
        end
      end
      -- Flash (StyleFlash): whenever the client re-reads a unit's auras (a new
      -- unit, an enable, a nameplate that came back or a new unit behind a
      -- kept token), its existing auras are all assigned at once and would
      -- flash together, though none is new. The container stays hidden until
      -- those flashes have run. A Start animation (StyleAuraAnimations) does
      -- play then, as a display's own Start plays when it first shows.
      local flashLength = Display.FlashLength(data)
      if shown and flashLength > 0 and (container.faEnabled ~= true or not unchanged or unitChanged) then
        instance.settleUntil = GetTime() + flashLength + 0.2
        C_Timer.After(flashLength + 0.3, function()
          if instance.settleUntil and GetTime() >= instance.settleUntil then
            instance.settleUntil = nil
            ApplyUnitStatus(instance, Display.GetSavedTrigger(data))
          end
        end)
      elseif not shown then
        instance.settleUntil = nil
      end
      instance.visible = shown
      ApplyUnitStatus(instance, trigger)
      if container:IsShown() ~= shown then container:SetShown(shown) end
      -- Enabled only when the state changes: a hidden display's container is
      -- already disabled when its unit events are handled, and a shown one
      -- that kept unit, parent and anchors needs no full refresh.
      if container.faEnabled ~= shown or (shown and not unchanged) then
        -- (dev.91) said with "/fa cells debug on" for a chained member: the write that resets the list's buttons
        if instance.chained and Display.BuildReporting and Display.BuildReporting() then
          CombatBuildReport(("%s: list %s (enabled %s -> %s, unchanged %s: unit %s/%s, parent %s, visible %s, removed %s, changed %s, preview %s, muted %s)"):format(tostring(data.id),
            shown and "enabled and re-read" or "disabled", tostring(container.faEnabled), tostring(shown), tostring(unchanged), tostring(instance.boundUnit), tostring(unit),
            tostring(container:GetParent() == parent), tostring(instance.visible), tostring(removedUnit), tostring(changedUnit), tostring(IsPreview()), tostring(muted)))
        end
        container:SetEnabled(shown)
        -- (1.3.6-dev.1) the enable cycle, apart from the re-read in place below
        Private.HitchCount(shown and "units refresh: container enabled" or "units refresh: container disabled")
        if shown then
          container:UpdateAllAuras(); Private.HitchCount("UpdateAllAuras")
          if counting then Private.HitchCount("UpdateAllAuras: " .. tostring(data.id)) end   -- (1.3.6-dev.17, diagnostic)
        end
        if unitChanged and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: container %s (unit %s)"):format(tostring(data.id), shown and "enabled and re-read" or "disabled", tostring(unit))) end
      elseif shown and unitChanged then
        Private.HitchCount("units refresh: re-read in place")
        if Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: list re-read in place (unit changed; unit %s, bound %s)"):format(tostring(data.id), tostring(unit), tostring(instance.boundUnit))) end
        -- A new unit behind a kept token: the client only re-reads a container
        -- on UNIT_AURA for its unit or when it is shown or enabled again, so
        -- it would keep showing the previous unit's auras. Re-read in place,
        -- without the enable cycle (which clears and lays out again).
        container:UpdateAllAuras(); Private.HitchCount("UpdateAllAuras")
      end
      if unitChanged and unchanged and not shown and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: unit changed but the container is not shown (unit %s, eligible %s)"):format(tostring(data.id), tostring(unit), tostring(wouldShow))) end
      Private.StopProfileSystem("aura (modern) - units: status")
      -- (dev.90) the muted container hidden by alpha; shown again as it was when the editor closes
      if muted then
        local stage = instance.single and instance.single.stage
        if not instance.previewMuted or instance.eraserMuteFailed
          or (stage and not (instance.mutedStages and instance.mutedStages[stage])) then
          -- (dev.92, Astra) committed only when the write went through; refused, the container is disabled
          -- as before (the ordinary editor path), so no live artwork stays visible under the samples
          if MuteErasers(instance) and pcall(container.SetAlpha, container, 0) then
            instance.previewMuted = true
          else container:SetEnabled(false); instance.visible = false; lockedUnits[region] = true end
        end
      elseif instance.previewMuted then
        instance.previewMuted = nil
        pcall(container.SetAlpha, container, instance.baseAlpha or 1)
        ApplyUnitStatus(instance, Display.GetSavedTrigger(data))
      end
      if instance.eraserRestorePending and shown and not muted and not editorRetaining and not IsPreview()
        and not instance.retainedMuted and not instance.previewMuted then
        if not RestoreErasers(instance, data) then lockedUnits[region] = true end
      end
      -- The Missing container follows the same unit and visibility as the aura
      -- slot, and is refreshed with it when the unit behind the token can have
      -- changed: left alone, it kept the previous target's state (the Missing
      -- look stayed closed after de-targeting, and flickered on re-targeting).
      Private.StartProfileSystem("aura (modern) - units: single")
      local singleReady = Display.RefreshSingle(instance, unit, shown and not muted, unitChanged or not unchanged)
      Private.StopProfileSystem("aura (modern) - units: single")
      -- So does a centred Modern Aura Group's half-size shadow.
      Private.StartProfileSystem("aura (modern) - units: shadow")
      local flowReady = Display.RefreshFlowShadow(instance, unit, shown and not muted, unitChanged or not unchanged)
      Private.StopProfileSystem("aura (modern) - units: shadow")
      if singleReady == false or flowReady == false then lockedUnits[region] = true end
      Private.StartProfileSystem("aura (modern) - units: glow")
      if instance.unitGlow then
        local glowContainer = instance.unitGlow.container
        local frame = unitFrames and unit and settings.unitGlow and anchorFrame
        if frame and frame:IsForbidden() then frame = nil end
        -- The glow follows the same unit filters as the icon (Display.UnitEligible)
        -- and its Ignore Dead / Ignore Disconnected status (UnitIgnored).
        local glowWanted = not IsPreview() and frame ~= nil and frame ~= false and region:IsShown() and not native.unitGlowsHidden
          and settings.unitGlow == true and Display.UnitEligible(trigger, unit)
        local glowShown = glowWanted and not UnitIgnored(trigger, unit)
        local glowParent = frame or region
        if instance.unitGlow.boundUnit ~= unit or glowContainer:GetParent() ~= glowParent then
          glowContainer:SetEnabled(false)
          if unit then glowContainer:SetUnit(unit) end
          instance.unitGlow.boundUnit = unit
          if glowContainer:GetParent() ~= glowParent then glowContainer:SetParent(glowParent) end
        end
        glowContainer:ClearAllPoints()
        if frame then AnchorUnitGlow(glowContainer, frame) else glowContainer:SetAllPoints(glowParent) end
        if Changed(glowContainer:GetFrameStrata(), glowParent:GetFrameStrata()) then glowContainer:SetFrameStrata(glowParent:GetFrameStrata()) end
        local glowLevel = glowParent:GetFrameLevel() + unitGlowFrameLevel
        if Changed(glowContainer:GetFrameLevel(), glowLevel) then glowContainer:SetFrameLevel(glowLevel) end
        -- Remembered without the status part, so a death or disconnect can
        -- toggle the glow from the status events without a full refresh.
        instance.unitGlow.wanted = glowWanted == true
        glowContainer:SetShown(glowShown)
        glowContainer:SetEnabled(glowShown)
        if glowShown then glowContainer:UpdateAllAuras() end
      end
      Private.StopProfileSystem("aura (modern) - units: glow")
      -- ForeverAuras (1.3.6-dev.12): this token's work ran to the end (a write
      -- it refused above became whole-region debt, lockedUnits), so an entry
      -- owed for it from an earlier refused pass is retired now, not before.
      if owed and unit ~= nil and owed[unit] then
        owed[unit] = nil
        if next(owed) == nil then pendingTokens[region] = nil; owed = nil end
      end
    end
  end
  -- (1.3.6-dev.12) a full pass has now covered every token: what it could not do
  -- is whole-region debt, so nothing stays separately owed.
  if fullPass and pendingTokens[region] then pendingTokens[region] = nil end
  if counting then Private.HitchCount("units refresh: instances visited", selected) end
  -- A healthy activation reuses prepared records, so their private glow
  -- bindings must resume without restyling or resetting native assignments.
  -- Retained/editor-hidden instances wait until their live appearance returns.
  if Display.ResumeGlowBinding and not IsPreview() and region:IsShown() then
    for _, instance in ipairs(native.instances) do
      if instance.glowResumePending and instance.visible and instance.container.faEnabled == true
        and not instance.retainedMuted and not instance.previewMuted then
        local waiting = false
        for _, record in ipairs(instance.buttons or {}) do
          if record.glowBinding and not Display.ResumeGlowBinding(record) then waiting = true end
        end
        instance.glowResumePending = waiting or nil
        if waiting then lockedUnits[region] = true end
      end
    end
  end
  -- Every display in the group relinks all of them, so the order in which
  -- they rebind their units does not matter.
  Private.StartProfileSystem("aura (modern) - units: relink")
  -- (1.3.8) a targeted pass relinks the rows of the units it served only (SecretAuraFlow.lua)
  if frameMode then Display.RelinkFlowUnits(Display.FlowGroup(data), changedUnit) end
  Private.StopProfileSystem("aura (modern) - units: relink")
  Private.StartProfileSystem("aura (modern) - units: levels")
  Display.UpdateDetachedFrameLevels(region)
  Private.StopProfileSystem("aura (modern) - units: levels")
  Private.StartProfileSystem("aura (modern) - units: preview")
  RefreshPreview(region)
  Private.StopProfileSystem("aura (modern) - units: preview")
  Private.StartProfileSystem("aura (modern) - units: grid")
  Display.RefreshGridFor(region)
  Private.StopProfileSystem("aura (modern) - units: grid")
end
Display.RefreshUnits = RefreshUnits

-- ForeverAuras: LibGetFrame rescans the unit frames a second after a roster
-- change (GROUP_ROSTER_UPDATE), so a display grouped by unit frame sat on
-- the old frame for about that long after a party became a raid, or the
-- reverse. Blizzard's frames announce the change themselves when they are
-- given their units (CompactUnitFrame_SetUnit for raid-style frames,
-- UnitFrame_SetUnit for the party frames); a rescan is asked for at once,
-- once per frame, and only while a shown display is placed on unit frames.
-- The rescan fires FRAME_UNIT_UPDATE, which reaches UnitFramesChanged.
local unitFrameRescanQueued = false
local function QueueUnitFrameRescan(unit)
  if unitFrameRescanQueued or (issecretvalue and issecretvalue(unit)) then return end
  if type(unit) ~= "string" or not (unit:find("^party") or unit:find("^raid")) then return end
  local needed
  for region in pairs(activeRegions) do
    local data = region.blizzardAuraDisplay.data
    if data.anchorFrameType == "UNITFRAME" or Display.FlowFrameMode(data) == "UNITFRAME" then needed = true; break end
  end
  if not needed then return end
  unitFrameRescanQueued = true
  C_Timer.After(0, function()
    unitFrameRescanQueued = false
    local LGF = LibStub and LibStub("LibGetFrame-1.0", true)
    if LGF and LGF.ScanForUnitFrames then LGF.ScanForUnitFrames() end
  end)
end
if CompactUnitFrame_SetUnit then hooksecurefunc("CompactUnitFrame_SetUnit", function(_, unit) QueueUnitFrameRescan(unit) end) end
if UnitFrame_SetUnit then hooksecurefunc("UnitFrame_SetUnit", function(_, unit) QueueUnitFrameRescan(unit) end) end

local unitFrameRefreshPending
function Display.UnitFramesChanged()
  if unitFrameRefreshPending then return end
  local needed
  for region in pairs(activeRegions) do
    local data = region.blizzardAuraDisplay.data
    if data.anchorFrameType == "UNITFRAME" or Display.FlowFrameMode(data) == "UNITFRAME" then needed = true; break end
  end
  if not needed then return end
  unitFrameRefreshPending = true
  -- LibGetFrame can report several frame changes together during a roster update.
  C_Timer.After(0, function()
    unitFrameRefreshPending = nil
    for region in pairs(activeRegions) do
      local data = region.blizzardAuraDisplay.data
      if region:IsShown() and (data.anchorFrameType == "UNITFRAME" or Display.FlowFrameMode(data) == "UNITFRAME") then RefreshUnits(region) end
    end
  end)
end

-- The display's frames stay shown (their contents cannot be known in combat),
-- so a Dynamic Group keeps its place even when no aura is there.
Display.dynamicGroupWarning = L["Aura (Modern) in a Dynamic Group: It keeps its position even when no aura is shown. Use a Modern Aura Group to keep dynamic behaviour."]
-- Information, not a warning: a Modern display in a Dynamic Group is a
-- deliberate layout in the class packs, and a warning there climbed up to
-- every pack's icon and hid real ones. The note stays in the tooltip.
local function DynamicGroupWarning(data)
  local inGroup = Display.Enabled(data) and Display.InDynamicGroup(data)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_dynamicgroup", inGroup and "info" or nil,
    inGroup and Display.dynamicGroupWarning or nil)
end

-- ForeverAuras (dev.90, Dan's A icons; Astra's order-stability note): what the
-- container's aura group is configured with, as one key: a build whose key
-- is the one already applied to a live container leaves the container alone
-- (no disable, no processing policy, no sort/candidate setters), because each
-- of those makes the client release every aura's button and hand the buttons
-- out again from a free list it walks in hash order - the cells of a chained
-- member then show the same auras in another order ("the A icons swap" after
-- the editor closes). The key covers the group's mode, sort and direction, the
-- filter string, the candidate filters (serialised whole) and the batch size;
-- the enabled state of the list is kept apart (ConfigureSingle). The key is
-- recorded only after the writes went through.
local function ApplyInstance(region, data, index, instance)
  instance.data = data
  -- New settings may place the container elsewhere: RefreshUnits anchors again.
  instance.anchored = nil
  local trigger = Display.GetTrigger(data)
  local function SerializeValue(value, depth)
    depth = depth or 0
    if type(value) ~= "table" then return tostring(value) end
    if depth > 6 then return "{...}" end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. SerializeValue(value[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  local okM, maxAuras = pcall(Display.MaxAuras, data)
  local method, direction = Display.SortOrder(data, trigger)
  local filter, candidates = FilterString(trigger), CandidateFilters(data)
  local config = table.concat({tostring(instance.slotMain), tostring(method), tostring(direction), tostring(filter),
    SerializeValue(candidates), tostring(okM and maxAuras or "?")}, "|")
  -- (dev.90) a live container applied again with the same configuration keeps its auras' buttons
  local keep = instance.applied == true and instance.appliedConfig == config and instance.container.faEnabled == true
    and not instance.styleEarly and not Restricted()
  instance.keptConfig = keep
  if Display.FlowChain and Display.FlowChain(data) then instance.container.faReportDisable = data.id end   -- (dev.94 diagnostic, SecretAuraFlow.lua TrackEnabled)
  -- (dev.91) said with "/fa cells debug on", for a member of a row with cells: whether the list was kept or
  -- configured again, and why (Dan: the A icons still move)
  if Display.FlowChain and Display.FlowChain(data) and Display.BuildReporting and Display.BuildReporting() then
    CombatBuildReport(("%s: list %s (%s)"):format(tostring(data.id), keep and "kept" or "configured again",
      keep and "same configuration" or (not instance.applied and "first build" or instance.appliedConfig ~= config and ("configuration changed: " .. tostring(instance.appliedConfig) .. " -> " .. tostring(config))
        or instance.container.faEnabled ~= true and "container not live" or instance.styleEarly and "styled early" or Restricted() and "restricted" or "?")))
  end
  if not keep then instance.container:SetEnabled(false) end
  -- Timed per phase for the profiler (see ApplyDisplay).
  Private.StartProfileSystem("aura (modern) - build: style buttons")
  -- ForeverAuras (combat-reload probe): a button styled early (Create) is
  -- not styled again now; one that was not is styled under pcall while
  -- restrictions are on, so the failure is counted and the build reported
  -- incomplete (the caller queues the display for a rebuild when the
  -- restrictions end) instead of counted as done.
  local probe = instance.styleEarly
  instance.lateFailed = 0
  for _, button in ipairs(instance.buttons) do
    if button.styledEarly then
      button.styledEarly = nil
    elseif probe then
      local ok, err = pcall(Style, button, data, region)
      if not ok then
        instance.lateFailed = instance.lateFailed + 1
        instance.styleError = instance.styleError or tostring(err)
      end
    else
      Style(button, data, region)
    end
  end
  Private.StopProfileSystem("aura (modern) - build: style buttons")
  -- ForeverAuras (cell chain): the member's end on the last record
  -- (FinishChain checks every record's link first). In a probe build a
  -- refusal or an incomplete link is counted with the build's failures
  -- (NoteSlotFailure: the report below names it and the build stops); in
  -- an ordinary build it takes the chain's failure contract
  -- (NoteChainFailure: counted, said, a bounded re-apply; dev.40 review).
  if instance.chained and Display.FinishChain then
    local native = region.blizzardAuraDisplay
    local okEnd, whyEnd = Display.FinishChain(region, instance, native and native.chainCalib)
    if not okEnd then
      if instance.styleEarly then
        if Display.NoteSlotFailure then Display.NoteSlotFailure(instance, "chain end", whyEnd) end
      elseif Display.NoteChainFailure then
        Display.NoteChainFailure(region, instance, "end", whyEnd)
      end
    end
  end
  Private.StartProfileSystem("aura (modern) - build: layout")
  Layout(instance, region, data)
  Private.StopProfileSystem("aura (modern) - build: layout")
  if not keep then
    instance.appliedConfig = nil
    ConfigureProcessing(instance.container, trigger)
    if instance.slotMain then
      instance.container:SetAuraSlotSortMethod("Auras", Display.SortOrder(data, trigger))
      instance.container:SetAuraSlotFilterString("Auras", FilterString(trigger))
      instance.container:SetAuraSlotCandidateFilters("Auras", CandidateFilters(data))
    else
      instance.container:SetAuraGroupSortMethod("Auras", Display.SortOrder(data, trigger))
      instance.container:SetAuraGroupFilterString("Auras", FilterString(trigger))
      instance.container:SetAuraGroupCandidateFilters("Auras", CandidateFilters(data))
    end
    instance.appliedConfig = config
  end
  ConfigureUnitGlow(instance, region, data)
  Private.StartProfileSystem("aura (modern) - build: single")
  Display.ConfigureSingle(instance, region, data, index)
  Private.StopProfileSystem("aura (modern) - build: single")
  -- From here on, buttons the client adds are styled as they are made (Create).
  instance.applied = true
  -- ForeverAuras (combat-reload probe): the result of a probe build, with
  -- the early styling, the later styling and the build errors counted
  -- apart; printed by the caller, which stops the build on any failure.
  if instance.styleEarly then
    instance.styleEarly = nil
    local failed = (instance.earlyFailed or 0) + (instance.lateFailed or 0)
    CombatBuildReport(("%s: %d buttons, %d styled early, %d failed early, %d failed later%s"):format(
      tostring(data.id), #instance.buttons, instance.earlyOK or 0, instance.earlyFailed or 0, instance.lateFailed or 0,
      instance.styleError and (" (" .. instance.styleError .. ")") or ""))
    -- The condition look recorded so far was painted with the early styling
    -- (setup = true reaches the buttons); a value or reset that arrives while
    -- the restrictions last marks the display dirty itself (SetConditionProperty,
    -- ResetConditionProperty), so nothing is marked here. Marking every probe
    -- build dirty repainted every button of every display built in combat in
    -- the one frame the restrictions ended (seen in game: a 67 ms hitch with
    -- 40 nameplate instances), for displays whose look was already right.
    region.secretAuraConditionValues = region.secretAuraConditionValues or {}
    instance.probeFailed = failed > 0
    return failed == 0
  end
  return true
end

local EDITOR_INSTANCES_NOW, EDITOR_INSTANCES_PER_FRAME = 2, 4
-- Only the units present now are built at once; the rest of the reserve
-- follows in the background, a few milliseconds per frame.
-- ForeverAuras: 2 ms rather than 4. The builds after login ran beside other
-- addons' work in the same frames; a smaller slice per frame keeps those
-- frames shorter and spreads the builds over a few more.
local BACKGROUND_BUDGET = 2
-- ForeverAuras: one build budget per frame, shared by the two drains
-- (DrainPending and DrainInstanceQueues): each used to keep its own, and
-- both timers can fire in the same frame (seen in game: a 17.9 ms timer
-- frame made of a 4 ms drain overrunning on a heavy display plus the 2 ms
-- background drain overrunning on another). The drain that comes second in
-- a frame already spent finds nothing left and waits for the next one.
-- GetTime() is constant within a frame, so it serves as the frame's stamp.
local FRAME_BUDGET = 4
local frameStamp, frameUsed = nil, 0
local function FrameBudgetLeft()
  local stamp = GetTime()
  if stamp ~= frameStamp then frameStamp, frameUsed = stamp, 0 end
  return FRAME_BUDGET - frameUsed
end
local function FrameBudgetSpend(ms)
  frameUsed = frameUsed + ms
end
local instanceQueues = {}
-- ForeverAuras (combat-reload probe): a probe build that failed is undone
-- (its containers retired, as a re-created display's are) and the display
-- is set aside until the restrictions end, when it is built again as new.
-- Nothing of it is counted as finished meanwhile.
local function AbandonProbeBuild(region, data, why)
  local native = region.blizzardAuraDisplay
  if native then
    native.applying = nil -- ForeverAuras (cell chain): no longer being applied (RequestReapply)
    for _, instance in ipairs(native.instances) do
      local missing = instance.single and instance.single.missing
      if missing then missing.active = false end
      RetainInstanceFrames(region, instance)
      if Display.CancelPendingListAlpha then Display.CancelPendingListAlpha(instance) end
    end
    native.instances = {}
    -- (A probe build keeps its own allocation list, RetainAllocations below;
    -- the ordinary-reserve ledger does not exist for it.)
    native.instanceQueue, instanceQueues[region] = nil, nil
    native.active = false
  end
  pendingTokens[region] = nil -- (1.3.6-dev.12) a stopped build owes no token work
  if native then native.probeBuild = nil end
  -- ForeverAuras (dev.68): the stopped build's spine is let go (the retry prepares it again).
  if native and Display.ReleaseChainSpine then Display.ReleaseChainSpine(native) end
  RetainAllocations(region)
  CleanAbandoned(region)
  activeRegions[region] = nil
  -- ForeverAuras (cell chain, dev.48 review): the settings the retry builds
  -- are the display's CURRENT ones. A newer saved table already queued for
  -- this display (a Modify made while this build was held or its reserve
  -- still going, under restrictions) is that intent and is kept as the
  -- retry; the failed build's own table is revived only when nothing newer
  -- was asked for. Stale tables are dropped by the handoff as before.
  local queued = pending[region]
  pending[region] = nil
  if queued and queued ~= data and WeakAuras.GetData(data.id) == queued then data = queued end
  retryAfterRestrictions[region] = data
  -- ForeverAuras: shown on the aura (cleared by Finish when the display is
  -- built), so a display missing during a fight is explained in the editor.
  -- Seen in game: Remaining Time (slot) displays, whose slot buttons the
  -- client locks together with every frame under them once made in combat.
  Warn(data, L["This display will be built when aura restrictions end."])
  CombatBuildReport(("%s stopped (%s); built again when restrictions end."):format(tostring(data.id), tostring(why)))
end
-- Whether a display set aside must still wait (Apply, Activate).
local function WaitingForRetry(region)
  return retryAfterRestrictions[region] ~= nil and Restricted()
end

local instanceDraining = false

-- The units a display needs right away, at login.
local function UnitsNow(trigger)
  local unit = trigger and trigger.unit
  if unit == "boss" or unit == "arena" then return UnitCount(unit) end
  if unit == "nameplate" then
    -- Plate tokens are not packed: build up to the highest one shown now.
    local highest = 1
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    for _, plate in ipairs(ok and plates or {}) do
      local token = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
      local index = type(token) == "string" and not issecretvalue(token) and tonumber(token:match("^nameplate(%d+)$"))
      if index and index > highest then highest = index end
    end
    return highest
  end
  return math.max(1, #UnitTokens(trigger))
end

local function FinishApply(region, data)
  local native = region.blizzardAuraDisplay
  -- ForeverAuras (dev.31 diagnostics): the build history notes the finish.
  if Display.NoteCarrierEvent then Display.NoteCarrierEvent(region, "finish", ("%d instances"):format(#native.instances)) end
  -- Where the next display in a Modern Aura Group starts, then the whole chain.
  local single = native.instances[1] and native.instances[1].single
  -- Timed per part for the profiler (see Style).
  Private.StartProfileSystem("aura (modern) - finish: flow")
  -- ForeverAuras (dev.78): an ordinary member of a row with cells marks its end with a measurement chain
  -- (before the shadows: a Centered shadow reuses its calibration, dev.79)
  if Display.EnsureFlowMeasure then Display.EnsureFlowMeasure(region, data, native) end
  Display.EnsureFlowShadows(region, data)
  Display.EnsureFlowRemaining(region, data)
  Display.SetFlowEnd(region, data, single and single.missing and single.missing.active and single.missing.presenceActive and single.missing.presence)
  Private.StopProfileSystem("aura (modern) - finish: flow")
  Private.StartProfileSystem("aura (modern) - finish: rechain")
  -- ForeverAuras (cell chain, dev.46 review): a chained display with a
  -- prepared end asks this chain pass to take it and commit (CommitChain at
  -- the end of RechainFlow; kept pending while a batch holds the pass).
  local chainedInstance = native.instances[1]
  if chainedInstance and chainedInstance.chained and native.flow and native.flow.chainEndReady then
    native.chainCommitPending, native.chainCommitResult = {instance = chainedInstance}, nil
  end
  -- A refusal found by this pass asks for its re-apply as one made during
  -- the apply (wanted): this finish drops pending[region] below and then
  -- makes the request once (RequestReapply).
  local wasApplying = native.applying
  native.applying = true
  Display.RechainFlow(Display.FlowGroup(data))
  native.applying = wasApplying
  Private.StopProfileSystem("aura (modern) - finish: rechain")
  Private.StartProfileSystem("aura (modern) - finish: units")
  RefreshUnits(region)
  Private.StopProfileSystem("aura (modern) - finish: units")
  -- ForeverAuras (cell chain, dev.49 review): this build's own request was
  -- taken when it started (ApplyDisplay); a request made since (a Modify
  -- while a reserve or a held probe finished in the background) is NEWER
  -- and stays for the paced apply. (The stamp is read through a global
  -- lookup where a review harness runs this function alone.)
  if pending[region] and not (requestStamp and (requestStamp[region] or 0) ~= (native.buildStamp or 0)) then pending[region] = nil end
  -- ForeverAuras (dev.82): a Centered row with cells under restrictions binds
  -- its shadows' records once no member of it is queued any more (this build
  -- may have been the last; ActivateShadows); the new containers take the
  -- unit as this display's did above.
  if Display.ActivateShadows and Restricted and Restricted() then
    local activated = Display.ActivateShadows(Display.FlowGroup(data))
    for _, other in ipairs(activated or {}) do RefreshUnits(other) end
  end
  Private.StartProfileSystem("aura (modern) - finish: sounds and warnings")
  SyncSounds(region)
  Warn(data)
  -- ForeverAuras (dev.36 review): a display whose reserve is stopped for
  -- these settings keeps its explanation after a refresh of its working
  -- instances (ReserveStopped / StoppedWarning, defined with the drain).
  if Display.StoppedWarning then Display.StoppedWarning(region, data) end
  -- ForeverAuras (cell chain, dev.40 review): the display's row-cell texts
  -- follow its current state here too, so a display that left the row (no
  -- flow: SetFlowEnd returned before publishing) drops them. The re-apply
  -- this finish completes is no longer pending; a chain that went through
  -- whole closes the record of refusals (a stopped one keeps it, with its
  -- warning).
  if Display.PublishChainWarnings and not (native and native.flow) then Display.PublishChainWarnings(region, data) end
  local record = native and native.reapplyRequests
  if record then
    record.pending = nil
    if native.chainFailure then
      if record.wanted then record.wanted = nil; Display.RequestReapply(region, record.why) end
    elseif not record.stopped and not native.chainCommitPending then
      -- Verified (or no chain): the record is closed. A commit still held by
      -- a batch keeps it until the flush's pass decides (dev.46 review).
      native.reapplyRequests = nil
    end
  end
  -- A whole chain needs no restricted hand-over of its own any more (dev.45
  -- review: an apply that completed before the restriction-end handler ran
  -- left it, and the handler built the display again); another refusal's
  -- hand-over stays. Only once verified (not while the commit is held).
  if native and not native.chainFailure and not native.chainCommitPending and Display.CancelPendingRelayout then Display.CancelPendingRelayout(region, "chain") end
  Private.StopProfileSystem("aura (modern) - finish: sounds and warnings")
end

-- ForeverAuras: a probe build's finishing, for the first pass (ApplyDisplay)
-- and for a reserve finished in the background (DrainInstanceQueues) alike.
-- The build's failure accounting stays open through it (the row measurement
-- is made there): a slot setup, formatter or binding refused in it counts
-- (NoteSlotFailure, instance.finishFailed) and stops the build like a failure
-- in the buttons would (rc.51 and rc.52 reviews: the measurement was made
-- after success had been reported, and the background pass skipped the
-- check). Returns true when the build may be kept. A build stopped after the
-- restrictions already ended is tried again next frame (AbandonProbeBuild
-- otherwise waits for the restriction-end handler, which has passed).
-- ForeverAuras (cell chain, dev.47 review): a chained probe build whose
-- chain pass a batch holds (the paced drain's own hold, an outer load hold)
-- is neither finished nor failed when its finish returns: the pass that
-- verifies its place decides (CommitChain -> SettleProbeCommit). Until then
-- the build keeps its failure accounting (instance.finishing) and its frame
-- ownership (native.probeBuild, region.faProbeAllocations). Returns true, true.
-- Stopped after the restrictions already ended: the restriction-end
-- handler, which moves set-aside builds to the paced drain, has passed,
-- so the same hand-over is made here (the drain's shared frame budget
-- paces it with everything else; rc.53 review). The request is dropped
-- by whatever completes the display first (FinishApply clears pending,
-- a finished build clears the retry), so nothing is built twice.
-- (The retry holds the current settings, dev.48 review: a newer table
-- queued while the build was held is built, not this build's own.)
-- (1.2.0, Astra's audit 4) shared by the finish-stage failure and the
-- reserve-stage failures of a probe build: the latter only recorded the
-- retry, which nothing serviced once restrictions had already ended.
function Display.HandOverStoppedBuild(region)
  local retry = retryAfterRestrictions[region]
  if not Restricted() and CleanAbandoned(region) and retry and WeakAuras.GetData(retry.id) == retry then
    retryAfterRestrictions[region] = nil
    pending[region] = retry
    if MarkRequest then MarkRequest(region) end
    -- the drain runs a frame later (never a rebuild inside the reserve loop); one already scheduled sees it
    if not draining then
      draining = true
      C_Timer.After(0, DrainPending)
    end
  end
end
local function FinishProbeBuild(region, data)
  local native = region.blizzardAuraDisplay
  for _, instance in ipairs(native.instances) do instance.finishing, instance.finishFailed = true, 0 end
  native.probeHeld = nil
  local okFinish, err = pcall(FinishApply, region, data)
  if okFinish and native.chainCommitPending then
    -- Held: nothing failed so far and the chain pass has not decided; the
    -- accounting stays open for it (SettleProbeCommit closes it once).
    local counted = 0
    for _, instance in ipairs(native.instances) do counted = counted + (instance.finishFailed or 0) end
    if counted == 0 then
      native.probeHeld = data
      return true, true
    end
  end
  local finishFailed, finishError = 0, nil
  for _, instance in ipairs(native.instances) do
    finishFailed = finishFailed + (instance.finishFailed or 0)
    finishError = finishError or (instance.finishFailed and instance.finishFailed > 0 and instance.styleError) or nil
    instance.finishing, instance.finishFailed = nil, nil
  end
  if okFinish and finishFailed == 0 then return true end
  if not okFinish then
    AbandonProbeBuild(region, data, "finishing failed: " .. tostring(err))
  else
    CombatBuildReport(("%s: %d failed while finishing%s"):format(tostring(data.id), finishFailed, finishError and (" (" .. finishError .. ")") or ""))
    AbandonProbeBuild(region, data, "the row measurement could not be made")
  end
  -- (HandOverStoppedBuild above, kept inline here: the finish is checked on its own by the harnesses.)
  local retry = retryAfterRestrictions[region]
  if not Restricted() and CleanAbandoned(region) and retry and WeakAuras.GetData(retry.id) == retry then
    retryAfterRestrictions[region] = nil
    pending[region] = retry
    if MarkRequest then MarkRequest(region) end
    if not draining then
      draining = true
      C_Timer.After(0, DrainPending)
    end
  end
  return false
end
-- The held probe build's decision, made by the chain pass that verified its
-- place (CommitChain, both outcomes): accepted when nothing was counted
-- against it (the frames belong to the live display, unless its reserve is
-- still being built), stopped and set aside otherwise (a refused placement
-- or reveal was counted by NoteChainFailure into the open finishing), with
-- the same hand-over as a finish that failed at once (above). Made exactly
-- once; nothing to do for a build that was not held.
function Display.SettleProbeCommit(region)
  local native = region and region.blizzardAuraDisplay
  local data = native and native.probeHeld
  if not data then return end
  native.probeHeld = nil
  local finishFailed, finishError = 0, nil
  for _, instance in ipairs(native.instances) do
    finishFailed = finishFailed + (instance.finishFailed or 0)
    finishError = finishError or (instance.finishFailed and instance.finishFailed > 0 and instance.styleError) or nil
    instance.finishing, instance.finishFailed = nil, nil
  end
  if native.data ~= data then return end -- replaced meanwhile: the new apply owns the display
  if finishFailed == 0 and native.chainCommitResult == true then
    if not native.instanceQueue then region.faProbeAllocations, native.probeBuild = nil, nil end
    retryAfterRestrictions[region] = nil
    return
  end
  CombatBuildReport(("%s: %d failed while finishing%s"):format(tostring(data.id), math.max(1, finishFailed), finishError and (" (" .. finishError .. ")") or ""))
  AbandonProbeBuild(region, data, "the row did not take the display's place")
  -- (The retry holds the current settings, dev.48 review: a newer table
  -- queued while the build was held is built, not this build's own.)
  local retry = retryAfterRestrictions[region]
  if not Restricted() and CleanAbandoned(region) and retry and WeakAuras.GetData(retry.id) == retry then
    retryAfterRestrictions[region] = nil
    pending[region] = retry
    if MarkRequest then MarkRequest(region) end
    if not draining then
      draining = true
      C_Timer.After(0, DrainPending)
    end
  end
end

-- ForeverAuras (dev.34, reserve fix): a reserve instance of an ordinary
-- build that failed while restrictions were on (or whose container could
-- not be made). The partial instance (if any) is removed from the display's
-- list, quieted and its frames retained for cleaning (RetainInstanceFrames,
-- as a stopped probe build does), the rest of the reserve is dropped, and
-- the display is set aside for a new apply when restrictions end
-- (retryAfterRestrictions; Apply then creates the missing instances afresh).
-- Already unrestricted: handed to the paced drain at once, as FinishProbeBuild
-- does after a late failure. The display's built instances keep working.
local RESERVE_RETRIES = 2
local function StoppedText(count, why)
  return L["Blizzard refused the extra units of this display %d times (%s). They are left out until the display's settings change or the interface is reloaded."]:format(count, tostring(why))
end
-- ForeverAuras (dev.34-36 reviews, reserve fix): the failure handling of an
-- ORDINARY build's background reserve, per ATTEMPT (one drain of one queue).
--  - Ownership: queue.owned holds the instances THIS attempt created; only
--    they can be retired. queue.ledger holds every FRAME allocated while the
--    attempt runs (NoteAllocation through region.faAttemptAllocations, kept
--    open through the creation, the setup of new and existing instances and
--    the finish, closed on every exit): on failure, each ledger frame that no
--    surviving instance took over (InstanceFrames) is retained for cleaning,
--    so a sibling made and refused before it was attached (a presence or
--    shadow container) never escapes; a kept instance's working frames are
--    not touched.
--  - RetireReserveInstance: a failed instance of this attempt is taken out of
--    the display's list, quieted and its known frames retained.
--  - FailReserveAttempt: ONE record per failed attempt on the display
--    (native.reserveFailure: settings epoch, count, why); recovery once:
--    under restrictions a retry when they end (not counted); unrestricted a
--    paced retry at once, at most RESERVE_RETRIES times for the same settings
--    epoch (Display.Modify counts it; activation and layout do not); then
--    "stopped": no further reserve for these settings (ReserveStopped gates
--    ApplyDisplay), the working instances stay, the editor says why
--    (StoppedWarning, re-published after every finish while stopped).
local function ReserveStopped(native)
  local record = native and native.reserveFailure
  return record ~= nil and record.stopped == true and record.epoch == (native.settingsEpoch or 0)
end
function Display.StoppedWarning(region, data)
  local native = region and region.blizzardAuraDisplay
  if native and ReserveStopped(native) and native.data == data then
    Warn(data, StoppedText(native.reserveFailure.count, native.reserveFailure.why))
  end
end
local function RetireReserveInstance(region, instance)
  local native = region.blizzardAuraDisplay
  if native then
    for i = #native.instances, 1, -1 do if native.instances[i] == instance then table.remove(native.instances, i) end end
  end
  pcall(QuietInstance, region, instance)
  RetainInstanceFrames(region, instance)
  if Display.CancelPendingListAlpha then Display.CancelPendingListAlpha(instance) end
end
local function FailReserveAttempt(region, queue, failed, why)
  local native = region.blizzardAuraDisplay
  for _, instance in ipairs(failed or {}) do if queue.owned and queue.owned[instance] then RetireReserveInstance(region, instance) end end
  ReconcileLedger(region, queue)
  if native then native.instanceQueue = nil end
  instanceQueues[region] = nil
  local data = queue.data
  if WeakAuras.GetData(data.id) ~= data then return end
  local epoch = native and native.settingsEpoch or 0
  local record = native and native.reserveFailure
  if not (record and record.epoch == epoch) then record = {epoch = epoch, count = 0}; if native then native.reserveFailure = record end end
  record.why, record.data = tostring(why), data
  if Restricted() then
    retryAfterRestrictions[region] = data
    return
  end
  record.count = record.count + 1
  if record.count > RESERVE_RETRIES then
    record.stopped = true
    Warn(data, StoppedText(record.count, record.why))
    return
  end
  CleanAbandoned(region)
  pending[region] = data
  if MarkRequest then MarkRequest(region) end
  if not draining then
    draining = true
    C_Timer.After(0, DrainPending)
  end
end

-- ForeverAuras (cell chain, SecretAuraChain.lua; dev.40 review): a display
-- asking to be applied again because a link or the end of its chain was
-- refused (NoteChainFailure). One record per settings epoch
-- (native.reapplyRequests), counted per JOB, not per refusal: while a
-- re-apply is pending (record.pending, cleared by FinishApply) further
-- requests join it. Under restrictions the request is the pending relayout
-- their end applies (not counted, as a refused reserve); otherwise the
-- paced drain, at most RESERVE_RETRIES times for the same epoch, then
-- stopped: no further re-apply for these settings from any entry, the
-- display keeps one spot in the row and the editor says why
-- (PublishChainWarnings; a successful apply closes the record).
function Display.RequestReapply(region, why)
  local native = region and region.blizzardAuraDisplay
  if not native or not (native.active or native.applying) or not native.data then return end
  local data = native.data
  if WeakAuras.GetData(data.id) ~= data then return end
  local epoch = native.settingsEpoch or 0
  local record = native.reapplyRequests
  if not (record and record.epoch == epoch) then record = {epoch = epoch, count = 0}; native.reapplyRequests = record end
  record.why = tostring(why)
  if record.stopped then return end
  -- Asked while the display is being applied (the pending job itself, or a
  -- first apply): FinishApply drops this apply's pending entry at its end,
  -- so it makes the request then, once.
  if native.applying then record.wanted = true; return end
  if record.pending then return end
  record.pending = true
  if Restricted() then
    if Display.NotePendingRelayout then Display.NotePendingRelayout(region, "chain") end
    return
  end
  record.count = record.count + 1
  if record.count > RESERVE_RETRIES then
    record.stopped, record.pending = true, nil
    if Display.PublishChainWarnings then Display.PublishChainWarnings(region, data) end
    return
  end
  pending[region] = data
  record.stamp = MarkRequest and MarkRequest(region) or nil -- (guarded: review harnesses run this function alone)
  if not draining then
    draining = true
    C_Timer.After(0, DrainPending)
  end
end
-- ForeverAuras (cell chain, dev.43 review): a chain completed outside an
-- apply (CompleteChain): the repair job it may have queued is cancelled (no
-- duplicate repair) and the epoch's record closed, unless stopped.
function Display.ChainRepaired(region)
  local native = region and region.blizzardAuraDisplay
  local record = native and native.reapplyRequests
  if not record then return end
  if record.pending then
    -- Its own job only: a request made since (a Modify of the same saved
    -- table under restrictions) is newer and stays (dev.49 review).
    if pending[region] == native.data and (not requestStamp or record.stamp == requestStamp[region]) then pending[region] = nil end
    -- The restricted hand-over too (its own reason; another refusal's stays).
    if Display.CancelPendingRelayout then Display.CancelPendingRelayout(region, "chain") end
  end
  record.pending, record.wanted = nil, nil
  if not record.stopped then native.reapplyRequests = nil end
end
-- Whether the chain's re-apply is stopped for the display's current settings.
function Display.ReapplyStopped(native)
  local record = native and native.reapplyRequests
  return record ~= nil and record.stopped == true and record.epoch == (native.settingsEpoch or 0)
end

-- The finishing pass after an ordinary build's reserve, with the attempt's
-- failure contract. EVERY instance is marked finishing, so a refused slot
-- write during the finish (NoteSlotFailure) is counted wherever it lands:
-- on an instance this attempt made, which is then retired, or on an
-- existing one (its measurement is made again by the retry; the instance
-- itself is kept). A finishing exception fails every new instance. Any
-- failure is one failed attempt; success closes the record.
local function FinishReserve(region, queue)
  local native = region.blizzardAuraDisplay
  for _, instance in ipairs(native.instances) do instance.finishing, instance.finishFailed = true, 0 end
  local okFinish, err = pcall(FinishApply, region, queue.data)
  local failed, any, why = {}, false, nil
  for _, instance in ipairs(native.instances) do
    local refused = (instance.finishFailed or 0) > 0
    if refused then any = true; why = why or instance.styleError end
    if queue.owned[instance] and (not okFinish or refused) then failed[#failed + 1] = instance end
    instance.finishing, instance.finishFailed = nil, nil
  end
  if okFinish and not any then
    -- Success too is reconciled: an allocation refused and left unattached
    -- inside a handled path (EnsureMissing) is retained for cleaning.
    ReconcileLedger(region, queue)
    native.reserveFailure = nil
    return true
  end
  if not okFinish then geterrorhandler()(err); why = "finishing failed: " .. tostring(err) end
  FailReserveAttempt(region, queue, failed, why)
  return false
end

local function DrainInstanceQueues()
  instanceDraining = false
  local more, abandoned = false, false
  -- Nothing left of this frame's budget: the next frame (FrameBudgetLeft).
  local left = FrameBudgetLeft()
  if left <= 0 then
    instanceDraining = true
    C_Timer.After(0, DrainInstanceQueues)
    return
  end
  local startedAt = debugprofilestop()
  local deadline = startedAt + math.min(BACKGROUND_BUDGET, left)
  for region in pairs(instanceQueues) do
    local native = region.blizzardAuraDisplay
    local queue = native and native.instanceQueue
    if not queue or not native.active or native.data ~= queue.data then
      -- ForeverAuras (dev.37 review): a stale or inactive attempt's ledger is
      -- reconciled before the queue is forgotten.
      ReconcileLedger(region, queue)
      instanceQueues[region] = nil
    elseif Restricted() and not queue.background then
      -- An editor rebuild waits for restrictions to end (Apply). The reserve
      -- of a display built in the background keeps growing in combat: its
      -- new containers hold no auras yet, and a nameplate display loaded
      -- during a fight needs them for the plates that appear in it.
      ReconcileLedger(region, queue)
      native.instanceQueue, instanceQueues[region] = nil, nil
      pending[region] = queue.data
      if MarkRequest then MarkRequest(region) end
    elseif debugprofilestop() > deadline then
      more = true
    else
      local last = queue.background and queue.total or math.min(queue.nextIndex + EDITOR_INSTANCES_PER_FRAME - 1, queue.total)
      local index = queue.nextIndex
      -- ForeverAuras (combat-reload probe): a probe build that fails here
      -- (a container not made, a button not styled, setup or finishing
      -- failed) is stopped and set aside (AbandonProbeBuild); the other
      -- displays in the queue go on.
      local probeBuild = native.probeBuild
      while index <= last do
        local ok, instance = true, native.instances[index]
        local startedInstance = debugprofilestop()
        -- ForeverAuras (dev.35/36 reviews): an ordinary build's attempt owns
        -- what it makes: queue.owned takes the instances made here, and the
        -- attempt ledger (queue.ledger, open for the whole attempt: creation,
        -- setup of new and existing instances, finish) takes every frame
        -- allocated meanwhile (NoteAllocation); reconciled by ReconcileLedger on exit.
        if not probeBuild then
          queue.owned = queue.owned or {}
          queue.ledger = queue.ledger or {}
          region.faAttemptAllocations = queue.ledger
        end
        if not instance then
          ok, instance = pcall(Create, region, queue.data)
          if ok and not probeBuild then queue.owned[instance] = true end
        end
        if ok then
          native.instances[index] = instance
          local probe = instance.styleEarly
          local okApply, complete = xpcall(ApplyInstance, geterrorhandler(), region, queue.data, index, instance)
          -- ForeverAuras: a reserve instance built in the background is
          -- named like a main build when it takes long (Display.Apply).
          local tookInstance = debugprofilestop() - startedInstance
          if tookInstance > 5 then CombatBuildReport(("%s reserve instance %d built in %.1f ms"):format(tostring(queue.data.id), index, tookInstance)) end
          -- ForeverAuras (dev.34, reserve fix): a failed reserve of an
          -- ORDINARY build (its buttons could not all be built or styled, or
          -- its setup raised) is handled on its own: the instance is taken
          -- out, quieted and its frames retained (never offered as a unit's
          -- instance), the queue stops, and the display is set to be applied
          -- again when restrictions end (or at once, paced, if they already
          -- have). The healthy instances stay active. The probe-build path
          -- below is unchanged (the whole build is its unit of failure).
          if (not okApply or complete == false) and not probeBuild then
            FailReserveAttempt(region, queue, {instance}, okApply and (instance.styleError or "a button could not be made or styled") or tostring(complete))
            abandoned = true
            break
          elseif probe and (not okApply or complete == false) then
            AbandonProbeBuild(region, queue.data, okApply and "a button could not be made or styled" or "setup failed")
            if Display.HandOverStoppedBuild then Display.HandOverStoppedBuild(region) end   -- (1.2.0, Astra's audit 4)
            abandoned = true
            break
          end
        elseif probeBuild then
          AbandonProbeBuild(region, queue.data, "container could not be made: " .. tostring(instance))
          if Display.HandOverStoppedBuild then Display.HandOverStoppedBuild(region) end   -- (1.2.0, Astra's audit 4)
          abandoned = true
          break
        else
          -- ForeverAuras (dev.34, reserve fix): a reserve container that
          -- could not be made is a failure of this reserve, reported and
          -- retried like a failed reserve instance, not the end of the queue
          -- taken as done.
          geterrorhandler()(instance)
          FailReserveAttempt(region, queue, nil, "container could not be made: " .. tostring(instance))
          abandoned = true
          break
        end
        index = index + 1
        if queue.background and debugprofilestop() > deadline then break end
      end
      -- The ledger stays on the queue between frames; the region-level hook is
      -- closed whenever this pass leaves the queue (reopened by the next pass).
      region.faAttemptAllocations = nil
      if abandoned then
        abandoned = false
      else
      queue.nextIndex = index
      if index > queue.total then
        native.instanceQueue, instanceQueues[region] = nil, nil
        if queue.background then
          if probeBuild then
            -- The same guarded finishing as the first pass (FinishProbeBuild);
            -- a held chain pass keeps the ownership open (dev.47 review).
            local okProbe, held = FinishProbeBuild(region, queue.data)
            if okProbe and not held then region.faProbeAllocations, native.probeBuild = nil, nil end
          else
            -- ForeverAuras (dev.34-36 reviews): guarded and counted (FinishReserve),
            -- with the attempt ledger open through the finish.
            region.faAttemptAllocations = queue.ledger
            FinishReserve(region, queue)
            region.faAttemptAllocations = nil
          end
        else
          -- ForeverAuras (dev.38 review, Astra's patch): the completed editor
          -- queue is a terminal transition too: its attempt ledger is
          -- reconciled before the units refresh.
          ReconcileLedger(region, queue)
          RefreshUnits(region)
        end
      else
        more = true
      end
      end
    end
  end
  FrameBudgetSpend(debugprofilestop() - startedAt)
  if more and not instanceDraining then
    instanceDraining = true
    C_Timer.After(0, DrainInstanceQueues)
  end
end

function Display.FlushInstanceQueue(region)
  local native = region.blizzardAuraDisplay
  local queue = native and native.instanceQueue
  if not queue or queue.background then return end
  ReconcileLedger(region, queue)
  native.instanceQueue, instanceQueues[region] = nil, nil
  if Restricted() then pending[region] = queue.data; if MarkRequest then MarkRequest(region) end; return end
  if native.data ~= queue.data then return end
  for index = queue.nextIndex, queue.total do
    native.instances[index] = native.instances[index] or Create(region, queue.data)
    ApplyInstance(region, queue.data, index, native.instances[index])
  end
end

local ApplyDisplay
function Display.Apply(region, data)
  -- ForeverAuras (combat-reload probe): a build set aside is not tried
  -- again before the restrictions end.
  if WaitingForRetry(region) then retryAfterRestrictions[region] = data; return end
  -- Frames of a stopped build still locked: the replacement waits too.
  if abandonedFrames[region] and not CleanAbandoned(region) then retryAfterRestrictions[region] = data; return end
  if Display.ForgetAppearanceKey then Display.ForgetAppearanceKey(data) end
  local profile = Private.loadProfile
  if not profile or profile.done then
    Private.StartProfileSystem("aura (modern) - build")
    -- ForeverAuras: with the build report on, a build over 5 ms is named,
    -- so the one display behind a long frame can be found.
    local startedBuild = debugprofilestop()
    -- ForeverAuras (cell chain): an apply that raises (an unguarded write
    -- in an ordinary build) is no longer being applied: the flag
    -- RequestReapply reads is dropped before the error goes on to the
    -- caller's handler with its message (which names where it happened;
    -- the frames below this one are not in the handler's stack any more).
    local okApply, errApply = pcall(ApplyDisplay, region, data)
    if not okApply then
      if region.blizzardAuraDisplay then region.blizzardAuraDisplay.applying = nil end
      error(errApply, 0)
    end
    local tookBuild = debugprofilestop() - startedBuild
    if tookBuild > 5 then
      local native = region.blizzardAuraDisplay
      -- (dev.81) a row member says whether its row's cells are on (the group opted in) and whether it is chained
      local rowNote = ""
      local group = Display.FlowGroup and Display.FlowGroup(data)
      if group then
        local cells = Display.FlowIndependentGroup and Display.FlowIndependentGroup(group)
        rowNote = cells and (Display.FlowChain and Display.FlowChain(data) and "; cells on, chained" or "; cells on") or "; cells off"
      end
      CombatBuildReport(("%s built in %.1f ms (%d instances%s)"):format(tostring(data.id), tookBuild, native and #native.instances or 0, rowNote))
    end
    Private.StopProfileSystem("aura (modern) - build")
    return
  end
  local started = debugprofilestop()
  local okApply, errApply = pcall(ApplyDisplay, region, data) -- ForeverAuras (cell chain): as above
  if not okApply then
    if region.blizzardAuraDisplay then region.blizzardAuraDisplay.applying = nil end
    error(errApply, 0)
  end
  profile.modern[data.id] = (profile.modern[data.id] or 0) + debugprofilestop() - started
end

function ApplyDisplay(region, data)
  DynamicGroupWarning(data)
  if not Display.Enabled(data) then Display.Release(region); Warn(data); SoundWarning(data); return end
  Suppress(region)
  local problem = Display.Validate(data)
  if problem then Display.Release(region); Warn(data, problem); return end
  -- Public editor frames can update while native container changes are deferred.
  -- They never bind units or consume live aura state.
  if IsPreview() then
    Display.ShowPreview(region, data, function(sample, appearance)
      Display.StyleAppearance(sample, Display.PrepareConditionAppearance(appearance), ElementFrame, StyleText, StyleGlow)
    end)
    Display.ArrangeFlowPreview(Display.FlowGroup(data))
    Suppress(region)
  else
    Display.HidePreview(region)
    Display.RestorePreviewRegion(region)
    -- ForeverAuras: as above, the group's box is arranged again, not restored.
    local flowGroup = Display.FlowGroup(data)
    if flowGroup and WeakAuras.IsOptionsOpen() then Display.ArrangeFlowPreview(flowGroup) else Display.RestoreGroupPreview(flowGroup) end
  end
  -- Built right after login, a few per frame, instead of during the loading screen.
  if not IsPreview() and not WeakAuras.IsLoginFinished() then
    pending[region] = data
    if MarkRequest then MarkRequest(region) end
    return
  end
  -- ForeverAuras: only a display that already exists waits for restrictions
  -- to end, since its buttons may hold live auras the client will not let
  -- an addon touch. A first build has none: the client lets an addon create
  -- a container, add its group, bind a unit and enable it in combat (probed
  -- in game with auras secret), so an aura whose load conditions first
  -- become true in combat is drawn then, not when the fight is over.
  local existing = region.blizzardAuraDisplay
  if Restricted() and existing and #existing.instances > 0 then
    pending[region] = data
    if MarkRequest then MarkRequest(region) end
    Warn(data, L["Display changes will apply when aura restrictions end."])
    return
  end
  -- ForeverAuras: a first build under restrictions that arrives from a load
  -- scan (an aura whose load conditions became true as the fight began) is
  -- queued for the paced drain (DrainPending, a few milliseconds per frame)
  -- instead of being built inside the scan's own frame. Seen in game: with
  -- 48 extra displays the combat-start frame carried the load scan plus
  -- 12 ms of Modern builds. The display appears a frame or two later.
  if Restricted() and not (existing and #existing.instances > 0) and not drainingNow then
    pending[region] = data
    if MarkRequest then MarkRequest(region) end
    if not draining then
      draining = true
      C_Timer.After(0, DrainPending)
    end
    return
  end
  if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    if not loaded then Warn(data, L["Cannot load Blizzard_AuraContainer: %s"]:format(tostring(reason))); return end
  end
  local native = region.blizzardAuraDisplay
  if not native then
    native = {instances = {}, data = data}
    region.blizzardAuraDisplay = native
  end
  -- ForeverAuras: the spell list this build reads (SecretAuraTrigger.lua,
  -- Display.ListSignature); a later publish compares against it.
  native.listSignature = Display.ListSignature and Display.ListSignature(data) or nil
  -- ForeverAuras (combat-reload probe): a build that starts under
  -- restrictions on an eligible display is a probe build for its whole
  -- lifetime, its background reserve included, whatever combat does
  -- meanwhile; its frames are noted from allocation (NoteAllocation) until
  -- it finishes cleanly, when the list is dropped (both finishing paths).
  -- A build starting while an earlier probe build's reserve is still going
  -- drops that list: its frames are either kept by this build (live) or
  -- retired by it; a failure of this build inventories the live instances
  -- itself (RetainInstanceFrames).
  region.faProbeAllocations = nil
  native.probeBuild = (Restricted() and ProbeEligible(data)) or nil
  if native.probeBuild then region.faProbeAllocations = {} end
  if not native.hooksInstalled then
    native.hooksInstalled = true
    TimedHookScript(region, "OnHide", function()
      Display.HideUnitGlows(region)
      for _, instance in ipairs(native.instances) do
        QuietInstance(region, instance)
        Display.RefreshSingle(instance, nil, false)
      end
      SyncSounds(region)
      Display.RefreshGridFor(region)
    end)
    TimedHookScript(region, "OnShow", function()
      native.unitGlowsHidden = false
      if native.active then RefreshUnits(region); SyncSounds(region) end
    end)
  end
  -- ForeverAuras (dev.35 review): the record of refused reserves belongs
  -- to a settings epoch (counted by Display.Modify); another epoch starts
  -- afresh. Activation and layout do not change the epoch.
  if native.reserveFailure and native.reserveFailure.epoch ~= (native.settingsEpoch or 0) then native.reserveFailure = nil end
  -- ForeverAuras (cell chain): the chain's re-apply record belongs to an epoch too.
  if native.reapplyRequests and native.reapplyRequests.epoch ~= (native.settingsEpoch or 0) then native.reapplyRequests = nil end
  native.data = data
  -- ForeverAuras (cell chain): measured again by the first link of this
  -- apply; this apply's refusals and records past the batch are counted
  -- afresh (every record is styled again below). The display counts as
  -- being applied (RequestReapply) until it is active.
  native.chainCalib, native.chainFailure, native.chainOverflow = nil, nil, nil
  -- ForeverAuras (dev.70; dev.74 wording): the optional combat fallback
  -- ("/fa cells fallback on", off by default): a chained display applied
  -- under aura restrictions is built as its ordinary construction (one
  -- spot, the release's gates: FlowChain reads native.chainDeferred and
  -- answers "deferred"), kept active, and built again as chained when the
  -- restrictions end. The packed construction itself IS built in combat
  -- (dev.72, Dan's combat reload: the spine and every connection are written
  -- before any record is bound, the cells from the last back to the first,
  -- the row from its last member back); this is a chosen one-spot mode, not
  -- a necessity.
  native.chainDeferred = nil
  if Restricted() and type(ForeverAurasSaved) == "table" and ForeverAurasSaved.rowCellsFallback and Display.FlowChain and Display.FlowChain(data) then
    native.chainDeferred = true
    chainDeferredRetry[region] = data
  end
  -- ForeverAuras (cell chain, dev.46 review): an unrestricted build stages
  -- its cells quiet; FinishApply asks the row to take the end and the chain
  -- pass reveals them (CommitChain). A probe build (in combat) shows them
  -- inline, where its records are still writable; its placement is verified
  -- the same way and a refusal counts with the build's failures.
  native.chainQuiet = (not native.probeBuild and Display.FlowChain and Display.FlowChain(data)) and {refused = 0} or nil
  native.chainCommitPending, native.chainCommitResult = nil, nil
  -- ForeverAuras (cell chain, dev.49 review): this build fulfils or
  -- supersedes any request queued before it (the drain took its own; a
  -- direct Modify builds the saved table a queued request asked for);
  -- FinishApply acknowledges no request made after this point.
  pending[region] = nil
  if MarkRequest then native.buildStamp = requestStamp[region] or 0 end
  -- A probe build still waiting for its held chain pass is replaced by this
  -- apply: its open accounting closes with it (dev.47 review).
  if native.probeHeld then
    native.probeHeld = nil
    for _, instance in ipairs(native.instances) do instance.finishing, instance.finishFailed = nil, nil end
  end
  native.applying = true
  -- ForeverAuras (dev.31 diagnostics): the build history, recorded at the
  -- event itself with the editor/combat/secret state of that moment.
  if Display.NoteCarrierEvent then Display.NoteCarrierEvent(region, "apply", IsPreview() and "preview" or "live") end
  -- A Modern Aura Group child draws from its start frame (SecretAuraFlow.lua).
  Display.EnsureFlowStart(region, data)
  -- The samples were styled above; RefreshPreview keeps them.
  native.previewStyled = IsPreview() and data or nil
  if IsPreview() then UpdatePreviewNotice(region) end
  native.unitGlowsHidden = false
  -- Joining or leaving a Modern Aura Group needs containers made for it: the old
  -- ones are retired (frames cannot be destroyed, so they stay hidden).
  -- The same when the display changes between one aura (a slot) and a list
  -- or a gated display (a group): the slot or group is fixed at creation.
  local wantsFlow = Display.FlowGroup(data) ~= nil
  local first = native.instances[1]
  -- ForeverAuras: also when a button the client added under restrictions
  -- could not be built (Create): only new containers get new, buildable
  -- buttons. Never under restrictions (Apply waits for them to end).
  local fresh = native.rebuildFresh and not Restricted()
  if fresh then native.rebuildFresh = nil end
  -- ForeverAuras (independent carriers): joining or leaving the experiment
  -- changes how every button is built (its box), so the containers are
  -- made again, as for a slot/group change.
  local wantsIndependent = wantsFlow and Display.FlowIndependent ~= nil and Display.FlowIndependent(data) or false
  -- ForeverAuras (cell chain): joining or leaving the chain changes the
  -- buttons' construction (box) too.
  local wantsChained = wantsFlow and Display.FlowChain ~= nil and Display.FlowChain(data) ~= nil or false
  if first and (fresh or first.flowContainer ~= wantsFlow
    or (first.slotMain ~= nil and first.slotMain ~= WantsSlot(data, wantsFlow, first.container))
    or (first.independent or false) ~= wantsIndependent
    or (first.chained or false) ~= wantsChained) then
    -- (dev.91) said with "/fa cells debug on": the containers made new, and why
    local why = fresh and "a fresh rebuild was asked" or first.flowContainer ~= wantsFlow and "row membership changed" or (first.chained or false) ~= wantsChained and "chain mode changed" or "mode changed"
    if wantsChained then CombatBuildReport(("%s: containers made new (%s)"):format(tostring(data.id), why)) end
    -- (1.2.5 summary) the containers made new, by reason
    local reasons = type(Display.summaryCounts) == "table" and Display.summaryCounts.freshBuilds
    if reasons then reasons[why] = (reasons[why] or 0) + 1 end
    for _, instance in ipairs(native.instances) do
      RetireInstanceGlowBindings(region, instance)
      instance.container:SetEnabled(false)
      instance.container:Hide()
      Display.RefreshSingle(instance, nil, false)
      if instance.single and instance.single.missing then instance.single.missing.active = false end
      -- Retired frames leave the region: every frame under it is walked again
      -- whenever its parent, strata or level is set.
      Display.RetireFrame(instance.container)
      if instance.flowShadow then Display.RetireFrame(instance.flowShadow) end
      if instance.flowMeasure then Display.RetireFrame(instance.flowMeasure) end
      if instance.unitGlow then Display.RetireFrame(instance.unitGlow.container) end
      -- ForeverAuras (combat-reload probe): a discarded instance needs no alpha repair.
      if Display.CancelPendingListAlpha then Display.CancelPendingListAlpha(instance) end
    end
    native.instances = {}
    -- ForeverAuras (cell chain): the retired frames are hidden; nothing of an
    -- old construction can stay drawn (chainReserve, chainBuilt; SetFlowEnd).
    native.chainReserve, native.chainBuilt = nil, nil
    -- ForeverAuras (dev.68): the spine of the retired construction is let go with it.
    if Display.ReleaseChainSpine then Display.ReleaseChainSpine(native) end
  end
  -- ForeverAuras (dev.67/68): a chained display's calibration and spine are
  -- made HERE, outside the client's record callbacks (SecretAuraChain.lua,
  -- PrepareChain): the hypothesis this build tests is that under aura
  -- restrictions a frame made inside a record's callback is locked with that
  -- record afterwards, whatever its parent (Dan's combat reloads: "holder to
  -- the previous cell: Attempt to access forbidden object" from record 6 on,
  -- with the spans under the button and under the region alike). The
  -- preparation is part of the build's contract (Astra's dev.67 review): a
  -- probe build that cannot prepare is stopped and set aside like one whose
  -- container could not be made; an ordinary build records the refusal as a
  -- chain failure (one spot, explained, the bounded repair) and goes on - its
  -- links then fail "not prepared" without allocating anything in a callback.
  if Display.PrepareChain then
    local prepared, why = Display.PrepareChain(region, data, native)
    if not prepared then
      if native.probeBuild then
        AbandonProbeBuild(region, data, "the row cells could not be prepared: " .. tostring(why))
        return
      end
      Display.NoteChainFailure(region, nil, "link", why)
    end
  end
  -- Reserve containers before combat; roster and plate events only rebind existing ones.
  local trigger = Display.GetTrigger(data)
  local total = math.max(Capacity(trigger, data), #native.instances)
  local now, background = total, false
  if IsPreview() then
    now = math.min(total, EDITOR_INSTANCES_NOW)
  else
    now = math.min(total, UnitsNow(trigger))
    background = true
  end
  -- Phases are timed separately (/fa phitch, /fa pprint) so a slow build can
  -- be read: container creation, per-instance styling, the finishing pass.
  Private.StartProfileSystem("aura (modern) - build: create")
  for index = 1, now do
    if not native.instances[index] then
      if native.probeBuild then
        local ok, created = pcall(Create, region, data)
        if not ok then
          Private.StopProfileSystem("aura (modern) - build: create")
          AbandonProbeBuild(region, data, "container could not be made: " .. tostring(created))
          return
        end
        native.instances[index] = created
      else
        native.instances[index] = Create(region, data)
      end
    end
  end
  Private.StopProfileSystem("aura (modern) - build: create")
  Display.ClearSingleWarning(data)
  -- ForeverAuras (dev.37 review): a queue replaced by this apply has its
  -- attempt ledger reconciled first (unattached leftovers retained).
  if ReconcileLedger then ReconcileLedger(region, native.instanceQueue) end
  native.instanceQueue, instanceQueues[region] = nil, nil
  -- ForeverAuras (dev.35 review): a display whose reserve was refused
  -- repeatedly for these settings builds no further reserve (ReserveStopped);
  -- its working instances are kept. New settings reopen it (Modify).
  if now < total and not (ReserveStopped and ReserveStopped(native)) then
    native.instanceQueue = {data = data, nextIndex = now + 1, total = total, background = background, owned = {}, ledger = {}}
    instanceQueues[region] = true
  end
  -- ForeverAuras (combat-reload probe): a probe build whose buttons could
  -- not all be made and styled, or whose setup failed, is stopped here and
  -- built again when the restrictions end (AbandonProbeBuild), not left
  -- half styled nor counted as finished.
  for index = 1, now do
    local instance = native.instances[index]
    if instance.styleEarly then
      local ok, complete = pcall(ApplyInstance, region, data, index, instance)
      if not ok or complete == false then
        AbandonProbeBuild(region, data, ok and "a button could not be made or styled" or ("setup failed: " .. tostring(complete)))
        return
      end
    else
      ApplyInstance(region, data, index, instance)
    end
  end
  native.active = true
  native.applying = nil -- ForeverAuras (cell chain): applied; RequestReapply goes by active from here
  native.appliedTrigger = Display.GetSavedTrigger(data)
  activeRegions[region] = true
  Private.StartProfileSystem("aura (modern) - build: finish")
  if native.probeBuild then
    local okProbe, held = FinishProbeBuild(region, data)
    if not okProbe then
      Private.StopProfileSystem("aura (modern) - build: finish")
      return
    end
    -- Built: the frames belong to the live display now, unless a reserve is
    -- still being built in the background (dropped when that finishes) or
    -- the chain pass that verifies the display's place is held by a batch
    -- (decided by SettleProbeCommit; dev.47 review).
    if not native.instanceQueue and not held then region.faProbeAllocations, native.probeBuild = nil, nil end
  else
    FinishApply(region, data)
  end
  -- ForeverAuras: a finished build is not tried again (a retry noted by an
  -- earlier stopped build would have rebuilt it once more).
  retryAfterRestrictions[region] = nil
  Private.StopProfileSystem("aura (modern) - build: finish")
  if native.instanceQueue and not instanceDraining then
    instanceDraining = true
    C_Timer.After(0, DrainInstanceQueues)
  end
end

-- Shared with SecretAuraSingle.lua.
Display.FilterString = FilterString
Display.CandidateFilters = CandidateFilters
Display.StyleNative = Style
Display.StyleText = StyleText

local function Install(region)
  if not region.blizzardOriginalUpdate then
    local update = region.Update
    region.blizzardOriginalUpdate = {func = update}
    region.Update = function(self, ...)
      if update then update(self, ...) end
      Suppress(self)
      if Display.UpdateMissingSource then Display.UpdateMissingSource(self) end
    end
  end
  if not region.blizzardOriginalPreShow then
    region.blizzardOriginalPreShow = {func = region.PreShow}
    region.PreShow = function(self) Suppress(self) end
  end
  Suppress(region)
end

function Display.Activate(region, data)
  if not Display.Enabled(data) then Display.Release(region); return end
  if WaitingForRetry(region) then retryAfterRestrictions[region] = data; return end
  Install(region)
  local native = region.blizzardAuraDisplay
  -- ForeverAuras: a display holding a button it could not build (Create,
  -- rebuildFresh) is not switched back on as it is; Apply makes it new.
  -- ForeverAuras (cell chain, dev.43 review): a pending entry that is the
  -- chain's own queued repair of these settings does not force a build now;
  -- the display is reused quiet and the one budgeted job stays queued.
  local ownRepair = native and native.data == data and pending[region] == data and native.reapplyRequests ~= nil and native.reapplyRequests.pending == true
  -- ForeverAuras (dev.72, Astra's dev.70 review): a construction built as one
  -- spot under restrictions (the combat fallback) keeps the intent to be
  -- packed when it is shown again: under restrictions the restriction-end
  -- request is restored, otherwise the repack is queued (the kept instance
  -- shows meanwhile).
  local repack = false
  if native and native.chainDeferred and native.data == data then
    if Restricted() then chainDeferredRetry[region] = data
    else
      if not pending[region] then
        pending[region] = data
        if MarkRequest then MarkRequest(region) end
        if not draining then draining = true; C_Timer.After(0, DrainPending) end
      end
      repack = pending[region] == data   -- the kept one-spot instance is reused meanwhile
    end
  end
  if native and native.data == data and (not pending[region] or ownRepair or repack) and not native.rebuildFresh and Display.Validate(data) == nil
    and #native.instances >= Capacity(Display.GetTrigger(data), data) then
    Display.FlushInstanceQueue(region)
    -- Reloading an existing display must restore its learning subscription too.
    local trigger = Display.GetTrigger(data)
    Display.WatchAuraLearning(region, data, trigger, Display.LateGlowSpec(data, trigger))
    native.unitGlowsHidden = false
    native.active = true
    activeRegions[region] = true
    -- ForeverAuras (cell chain, dev.41/42 reviews): a display whose chain is
    -- incomplete (a refused link or end, chainFailure) is switched on as it
    -- is (quiet, one spot) and its bounded PACED repair is asked for again
    -- (RequestReapply: the paced drain, counted per job, within the epoch's
    -- allowance; the unload dropped the earlier job's latch). A stopped one
    -- is reused as it is, with its explanation published again (Release
    -- cleared it). Nothing is built in this frame.
    if native.chainFailure then
      if Display.ReapplyStopped and Display.ReapplyStopped(native) then
        if Display.PublishChainWarnings then Display.PublishChainWarnings(region, data) end
      elseif Display.RequestReapply then
        Display.RequestReapply(region, native.chainFailure.what)
      end
    elseif native.chainQuiet and native.instances[1] and native.instances[1].chained then
      -- ForeverAuras (cell chain, dev.47 review): a healthy construction
      -- staged quiet whose commit the unload cancelled while a batch held
      -- it (Release): the same prepared frames ask this chain pass to take
      -- them again (CommitChain reveals them once the row has verifiably
      -- taken the end; held, they stay quiet and pending until the flush).
      -- The current instance, not the cancelled request's; the epoch's
      -- repair allowance is untouched (no refusal happened). A quiet display
      -- without a prepared end has nothing to commit: its bounded repair is
      -- asked for, as for a refused end.
      if native.flow and native.flow.chainEndReady then
        native.chainCommitPending, native.chainCommitResult = {instance = native.instances[1]}, nil
      elseif Display.RequestReapply and not (Display.ReapplyStopped and Display.ReapplyStopped(native)) then
        Display.RequestReapply(region, L["the member's end (%s)"]:format("the end is not in place"))
      end
    end
    Display.RechainFlow(Display.FlowGroup(data))
    RefreshUnits(region)
    SyncSounds(region)
  else
    Display.Apply(region, data)
  end
end

function Display.SyncProgressSource(region, data)
  if not data then return end
  local trigger = Display.GetTrigger(data)
  local key = trigger and (data.progressSource and data.progressSource[1] or -1) or 0
  if key < 0 then key = (data.triggers.activeTriggerMode and data.triggers.activeTriggerMode > 0 and data.triggers.activeTriggerMode)
    or (Private.GetActiveTriggerFor and Private.GetActiveTriggerFor(data.id)) or 1 end
  if region.secretAuraProgressSourceIndex ~= key then
    -- Another trigger turning on or off can change the index while the same
    -- Aura (Modern) trigger still drives the display: nothing to rebuild.
    local native = region.blizzardAuraDisplay
    if native and native.active and native.data == data and native.appliedTrigger
      and native.appliedTrigger == Display.GetSavedTrigger(data) then
      region.secretAuraProgressSourceIndex = key
      return
    end
    -- The same Aura (Modern) trigger selected again after another trigger
    -- supplied the information (its unit did not exist): the display is still
    -- built, so it is only switched back on. This also works in combat, where
    -- a rebuild waits for restrictions to end.
    if native and not native.active and native.data == data and native.appliedTrigger
      and native.appliedTrigger == Display.GetSavedTrigger(data) then
      region.secretAuraProgressSourceIndex = key
      Display.Activate(region, data)
      return
    end
    Display.Modify(region, data)
  end
end

-- In the editor one action can modify a display several times in one frame, and
-- many displays at once: multi-select setters, texture pickers, paste. A display
-- that is already built is rebuilt once, on the next frame, a few per frame.
local EDITOR_APPLIES_PER_FRAME = 2
local editorQueue = {}
local editorDraining = false
local function DrainEditorQueue()
  local regions = {}
  for region in pairs(editorQueue) do regions[#regions + 1] = region end
  local done = 0
  for _, region in ipairs(regions) do
    if done >= EDITOR_APPLIES_PER_FRAME then break end
    local data = editorQueue[region]
    editorQueue[region] = nil
    -- Skip displays deleted, renamed or replaced since they were queued.
    local entry = Private.regions[data.id]
    if entry and entry.region == region and (WeakAuras.GetData(data.id) or data) == data and Display.Enabled(data) then
      xpcall(Display.Apply, geterrorhandler(), region, data)
      done = done + 1
    end
  end
  if next(editorQueue) then C_Timer.After(0, DrainEditorQueue) else editorDraining = false end
end

function Display.CancelEditorApply(region)
  editorQueue[region] = nil
end

-- ForeverAuras (diagnostic, Dan's stray numbers after the editor closes):
-- "/fa bindcheck" lists Modern displays whose native binding and frame
-- disagree: a binding whose data names another display than the frame now
-- serves, an active binding on a hidden frame, a container whose parent is
-- not the frame it was bound to, and a frame in the editor or pending
-- queues that no longer belongs to the display queued for it. Read only;
-- it changes nothing.
function Display.BindingCheck()
  local lines, checked = {}, 0
  local function note(text) lines[#lines + 1] = "  " .. text end
  for region in pairs(activeRegions) do
    checked = checked + 1
    local native = region.blizzardAuraDisplay
    local data = native and native.data
    if data and data.id ~= region.id then
      note(("%s (clone %s): bound as %s"):format(tostring(region.id), tostring(region.cloneId), tostring(data.id)))
    end
    if native and native.active and not region:IsShown() then
      note(("%s (clone %s): active binding on a hidden frame"):format(tostring(region.id), tostring(region.cloneId)))
    end
    for index, instance in ipairs(native and native.instances or {}) do
      local container = instance.container
      if container then
        local ok, parent = pcall(container.GetParent, container)
        if ok and parent ~= nil and parent ~= region and (not region.GetParent or parent ~= region:GetParent()) then
          local name = parent.GetName and parent:GetName() or (parent.id and tostring(parent.id)) or "?"
          note(("%s (clone %s): container %d parented to %s"):format(tostring(region.id), tostring(region.cloneId), index, tostring(name)))
        end
        if container.IsShown and container:IsShown() and not region:IsShown() then
          note(("%s (clone %s): container %d shown while its display is hidden"):format(tostring(region.id), tostring(region.cloneId), index))
        end
      end
    end
  end
  for region, data in pairs(editorQueue) do
    if data and data.id ~= region.id then note(("editor queue: frame of %s queued for %s"):format(tostring(region.id), tostring(data.id))) end
  end
  for region, data in pairs(pending) do
    if data and data.id ~= region.id then note(("pending queue: frame of %s queued for %s"):format(tostring(region.id), tostring(data.id))) end
  end
  local prettyPrint = WeakAuras.prettyPrint or print
  prettyPrint(("Binding check: %d active Modern displays, %d problem(s)."):format(checked, #lines))
  for _, line in ipairs(lines) do prettyPrint(line) end
end

-- ForeverAuras: a Remaining Time window on an Icon shows one aura, the first
-- the client picks by the sort order, and the window only opens and closes
-- over that one (the client cannot filter by remaining time). With no spell
-- selected it is whatever sorts first among all matching auras, usually not
-- the one meant (seen in game: all player buffs with 55 s or less showed
-- nothing, the slot holding an hour-long buff). Other filters can narrow
-- the display to one aura without a spell list, so this warns, not forbids.
local function RemainingSelectionProblem(data)
  local trigger = Display.GetSavedTrigger(data)
  if not trigger or data.regionType ~= "icon" or not Display.Enabled(data) then return end
  if not Display.RemainingWindow(trigger) or Display.ShowOn(trigger) ~= "showOnActive" then return end
  if #Display.GetSpellIDs(trigger, true) > 0 then return end
  return L["Remaining Time shows one aura: the first that matches the trigger, and the time window applies to that one only. Select the spell(s) in the trigger so the window applies to the aura you mean."]
end

function Display.Modify(region, data)
  -- ForeverAuras (dev.35 review): a settings change is a new epoch for the
  -- display's refused-reserve record (FailReserveAttempt, ReserveStopped).
  local native = region and region.blizzardAuraDisplay
  if native then native.settingsEpoch = (native.settingsEpoch or 0) + 1 end
  -- ForeverAuras: a member's settings change is a new attempt for a Grid
  -- whose build the client refused (SecretAuraGrid.lua, GridSettingsChanged);
  -- visibility and condition changes do not come through here.
  -- Only a display that can take part in the Grid (a Modern trigger the
  -- Grid accepts) reopens it; an ordinary display or clone made in the same
  -- group does not (dev.9 review). A runtime trigger change
  -- (SyncProgressSource) comes through here too and may legitimately reopen it.
  -- A display that took part in the stopped attempt counts too, whatever it
  -- is now (editing the failing member out of the Grid frees the rest).
  if Display.GridSettingsChanged then
    local group = Display.FlowGroup(data)
    if group then
      local eligible = Display.Enabled(data) and not (Display.GridProblem and Display.GridProblem(data))
      if eligible or (Display.GridMemberAttempted and Display.GridMemberAttempted(group.id, data.id)) then
        Display.GridSettingsChanged(group.id)
      end
    end
  end
  local flowProblem = Display.FlowNormalProblem(data)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_flow_member", flowProblem and "warning" or nil, flowProblem)
  local selectionProblem = RemainingSelectionProblem(data)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_remaining_selection", selectionProblem and "warning" or nil, selectionProblem)
  local afterGate = Display.FlowAfterGateProblem and Display.FlowAfterGateProblem(data)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_flow_after_gate", afterGate and "warning" or nil, afterGate)
  -- ForeverAuras: the order of a Modern Aura Group decides that warning for
  -- every member, and reordering changes the group, not the members: their
  -- warnings are refreshed here (rc.29 review: a warning stayed after the
  -- member was moved before the filtered one).
  -- A member's own filters decide the warning for the other members too (a
  -- second gated member of the row), so when a member's filters start or stop
  -- gating it, its row's members are refreshed as well (not on every rebuild:
  -- a large pack's load would check every member for every member).
  local warnGroup = (data.regionType == "group" and data.blizzardFlow) and data or nil
  if not warnGroup and Display.FlowGated then
    local gated = Display.FlowGated(data)
    if region.flowGatedWarned ~= nil and region.flowGatedWarned ~= gated then warnGroup = Display.FlowGroup(data) end
    region.flowGatedWarned = gated
  end
  if warnGroup and Display.FlowAfterGateProblem then
    for _, childID in ipairs(warnGroup.controlledChildren or {}) do
      local child = childID ~= data.id and WeakAuras.GetData(childID)
      if child then
        local childProblem = Display.FlowAfterGateProblem(child)
        Private.AuraWarnings.UpdateWarning(child.uid, "blizzard_aura_flow_after_gate", childProblem and "warning" or nil, childProblem)
      end
    end
  end
  -- ForeverAuras: a refused windowed countdown (SecretAuraAppearance.lua,
  -- BindText) is reported again by the build that follows, if it is still
  -- refused; a display whose Remaining Time filter was removed drops it here
  -- (rc.19 review).
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_countdown", nil)
  local trigger = Display.GetTrigger(data)
  local key = trigger and (data.progressSource and data.progressSource[1] or -1) or 0
  if key < 0 then key = (data.triggers.activeTriggerMode and data.triggers.activeTriggerMode > 0 and data.triggers.activeTriggerMode)
    or (Private.GetActiveTriggerFor and Private.GetActiveTriggerFor(data.id)) or 1 end
  region.secretAuraProgressSourceIndex = key
  region.secretAuraConditionValues = nil
  -- ForeverAuras: see Display.Restore; the rebuilt display starts clean.
  region.secretAuraPendingResets = nil
  if not Display.Enabled(data) then Display.Release(region); Warn(data); SoundWarning(data); return end
  Install(region)
  local native = region.blizzardAuraDisplay
  if WeakAuras.IsOptionsOpen() and native and native.active and native.data == data and not Restricted() then
    editorQueue[region] = data
    if not editorDraining then
      editorDraining = true
      C_Timer.After(0, DrainEditorQueue)
    end
    return
  end
  editorQueue[region] = nil
  Display.Apply(region, data)
end

-- Native containers watch UNIT_AURA themselves. Only rebind when their unit can change.
local unitEvents = {
  GROUP_ROSTER_UPDATE = {group = true, party = true, raid = true, member = true},
  PLAYER_ROLES_ASSIGNED = {group = true, party = true, raid = true},
  PLAYER_TARGET_CHANGED = {target = true, targettarget = true},
  PLAYER_FOCUS_CHANGED = {focus = true, focustarget = true},
  UPDATE_MOUSEOVER_UNIT = {mouseover = true},
  INSTANCE_ENCOUNTER_ENGAGE_UNIT = {boss = true, member = true},
  ARENA_OPPONENT_UPDATE = {arena = true, member = true},
  -- Names only matter to group displays filtered by player name.
  UNIT_NAME_UPDATE = {group = true, party = true, raid = true},
  -- Combat and restriction changes do not change which units are watched.
  PLAYER_REGEN_ENABLED = {},
  ADDON_RESTRICTION_STATE_CHANGED = {},
}

local function NeedsUnitRefresh(mode, event, unit, trigger)
  -- A unit's class can arrive after the unit did (with its name): a display
  -- filtered by class re-judges its unit then, whatever the unit mode.
  if event == "UNIT_NAME_UPDATE" and trigger and trigger.useUnitClass then
    if groupModes[mode] then return true end
    -- Single units and nameplates: only when the named unit is one the display watches.
    for _, token in ipairs(UnitTokens(trigger)) do
      -- A pet is judged by its owner, so the owner's name update counts too.
      local owner = WeakAuras.petUnitToUnit and WeakAuras.petUnitToUnit[token] or token
      if token == unit or owner == unit then return true end
      local ok, same = pcall(UnitIsUnit, token, unit)
      if ok and not issecretvalue(same) and same == true then return true end
      if owner ~= token then
        ok, same = pcall(UnitIsUnit, owner, unit)
        if ok and not issecretvalue(same) and same == true then return true end
      end
    end
    return false
  end
  if event == "UNIT_TARGET" then
    return (mode == "targettarget" and unit == "target") or (mode == "focustarget" and unit == "focus")
      or (mode == "pettarget" and unit == "pet")
  elseif event == "UNIT_PET" then
    -- A new pet brings a new target of pet.
    return ((mode == "pet" or mode == "pettarget") and unit == "player") or mode == "member" or Display.IncludesPets(trigger) ~= nil
  end
  local modes = unitEvents[event]
  return modes == nil or modes[mode] == true
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
-- Reconfigure physical-pixel borders when the screen's pixel-to-UI ratio changes.
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET", "UNIT_PET", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ARENA_OPPONENT_UPDATE",
  "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE", "PLAYER_ROLES_ASSIGNED", "UNIT_FACTION"}) do events:RegisterEvent(event) end
-- The unit-frame glow follows its instance's status (ApplyUnitStatus): shown
-- only when the binding wanted it, the display has not hidden its glows, and
-- the unit is not ignored. A glow the client will not let addon code touch
-- right now (combat) is noted and brought up to date when combat ends.
local glowStatusPending = {}
local function SyncGlowStatus(region, instance)
  local glow = instance.unitGlow
  local native = region.blizzardAuraDisplay
  if not glow or not glow.container or not native then return end
  if Locked(glow.container) then glowStatusPending[region] = true; return end
  local shown = glow.wanted == true and not native.unitGlowsHidden and not instance.statusHidden
  if glow.container:IsShown() ~= shown then
    glow.container:SetShown(shown)
    glow.container:SetEnabled(shown)
    if shown then glow.container:UpdateAllAuras() end
  end
end

-- Deaths, releases and disconnects only change the affected unit's alpha.
local statusEvents = CreateFrame("Frame")
for _, event in ipairs({"UNIT_CONNECTION", "UNIT_HEALTH", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED"}) do statusEvents:RegisterEvent(event) end
-- ForeverAuras 1.2.10 (Dan's reminders gone after a death until a reload): Ignore Out of Range
-- (ignoreInvisible) hides every member's part while the player is a ghost (nobody is visible from
-- the graveyard), and nothing re-checked it: a member's own flags do not change when the PLAYER
-- comes back. The player's own death, release and return re-check every bound unit's status.
for _, event in ipairs({"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST"}) do statusEvents:RegisterEvent(event) end
local playerStatusEvents = {PLAYER_DEAD = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true}
-- A group member coming into or leaving the client's view (UnitIsVisible), for
-- Ignore out of checking range: the events Aura (Legacy) uses for it. (Not
-- UNIT_IN_RANGE_UPDATE, which tracks UnitInRange and costs the client extra.)
statusEvents:RegisterEvent("PARTY_MEMBER_ENABLE")
statusEvents:RegisterEvent("PARTY_MEMBER_DISABLE")
statusEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
statusEvents:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")   -- (1.2.10) the owed status alphas
statusEvents:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
    -- (1.2.10) the status alphas the client refused in combat are written now, from the current status
    for region in pairs(activeRegions) do
      local native = region.blizzardAuraDisplay
      local trigger = Display.GetSavedTrigger(native.data)
      for _, instance in ipairs(native and native.instances or {}) do
        local missing = instance.single and instance.single.missing
        if trigger and (instance.statusAlphaPending or (missing and missing.active and missing.statusAlphaPending)) then
          if instance.statusAlphaPending then ApplyUnitStatus(instance, trigger) end
          Display.RefreshSingleStatus(instance)
        end
      end
    end
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    -- Glow status changes skipped in combat are replayed.
    for region in pairs(glowStatusPending) do
      glowStatusPending[region] = nil
      local native = region.blizzardAuraDisplay
      for _, instance in ipairs(native and native.instances or {}) do SyncGlowStatus(region, instance) end
    end
    return
  end
  local everyUnit = playerStatusEvents[event] == true   -- (1.2.10) the player's death, release or return
  if not everyUnit and type(unit) ~= "string" then return end
  for region in pairs(activeRegions) do
    local native = region.blizzardAuraDisplay
    -- Read only: the saved trigger, without the copy GetTrigger may make.
    local trigger = Display.GetSavedTrigger(native.data)
    -- ForeverAuras: hidden displays skip this too (see the event dispatch).
    if region:IsShown() and trigger and (trigger.ignoreDead or trigger.ignoreDisconnected or trigger.ignoreInvisible) then
      -- ForeverAuras: a grid member draws in the grid's container, not its own.
      if native.gridMember and Display.RefreshGridStatus then
        if everyUnit then
          for _, instance in ipairs(native.instances) do if instance.boundUnit then Display.RefreshGridStatus(region, instance.boundUnit) end end
        else
          Display.RefreshGridStatus(region, unit)
        end
      end
      local single = #native.instances == 1
      for _, instance in ipairs(native.instances) do
        local bound = instance.visible and instance.boundUnit
        if bound and (everyUnit or bound == unit or (single and Private.ExecEnv.UnitIsUnit(bound, unit)))
          and (UnitIgnored(trigger, bound) or nil) ~= instance.statusHidden then
          ApplyUnitStatus(instance, trigger)
          Display.RefreshSingleStatus(instance)
          -- The unit-frame glow follows Ignore Dead / Ignore Disconnected too.
          SyncGlowStatus(region, instance)
        end
      end
    end
  end
end)

-- Displays waiting for restrictions to end are rebuilt a few per frame, so
-- the end of combat does not rebuild every display in one frame.
-- The budget covers only the Lua side; each rebuild also costs the client
-- drawing time afterwards, so it is kept small.
local PENDING_BUDGET = 4
draining = false
-- ForeverAuras: Modern Aura Groups whose Grid must be built or rebuilt once
-- restrictions allow it (SecretAuraGrid.lua, RebuildGrid), by id. Drained by
-- DrainPending with the displays, under the same frame budget, one group per
-- job and each job on its own error boundary; a request is taken from the
-- set only when its job runs, and the group's data is looked up then, so a
-- group deleted, replaced or turned back into a row meanwhile is not rebuilt
-- from stale data. Started by the restriction-end handler (combat end, or
-- aura restrictions ending on their own), never inside the event itself.
local gridPending = {}
-- ForeverAuras: true while DrainPending applies its batch (see ApplyDisplay).
drainingNow = false
DrainPending = function()
  -- Before login completes, the login callback starts the drain.
  if not WeakAuras.IsLoginFinished() then draining = false; return end
  -- ForeverAuras (combat-reload probe): under restrictions (a reload in
  -- combat) only a display that already has buttons waits, as Apply itself
  -- decides; a first build goes ahead, its buttons styled in the client's
  -- initializeFrame call before they are restricted (Create). A build that
  -- still fails is queued again (DrainInstanceQueues) and waits.
  local restricted = Restricted()
  local started = debugprofilestop()
  -- The frame's shared budget (FrameBudgetLeft): none left, the next frame.
  local budget = math.min(PENDING_BUDGET, FrameBudgetLeft())
  if budget <= 0 then C_Timer.After(0, DrainPending); return end
  -- Modern Aura Groups re-anchor once per group after this batch, not once
  -- per rebuilt display (the same batching a load scan uses).
  if Display.BeginFlowLoad then Display.BeginFlowLoad() end
  -- ForeverAuras: builds applied from here are not queued again (ApplyDisplay).
  drainingNow = true
  -- ForeverAuras (dev.70): under restrictions a chained member is built only
  -- after the NEXT chained member of its row is whole (every record made):
  -- a member's frames all hang from the previous member's end, which the
  -- client guards once that member's records are bound, so the row is built
  -- from its last member back to its first (ChainOrderWaits). A member
  -- waited for too long (a build that never completes) is built anyway and
  -- takes the ordinary refusal path.
  local function ChainOrderWaits(region, data)
    if not (restricted and Display.ChainOrderBlocker) then return false end
    -- (dev.72, Astra's dev.70 review) counted off the display's native state: a
    -- fresh combat load has none yet, and the order must hold there most of all;
    -- the count is per queued request (cleared when the wait ends)
    local waited = (chainOrderWaits[region] or 0)
    if waited >= 180 then chainOrderWaits[region] = nil; return false end
    local blocker = Display.ChainOrderBlocker(region, data, pending)
    if blocker then
      chainOrderWaits[region] = waited + 1
      if waited == 0 then CombatBuildReport(("%s waits for %s (built from the row's last member back)"):format(tostring(data.id), tostring(blocker))) end
      return true
    end
    if Display.FlowChain and Display.FlowChain(data) then CombatBuildReport(("%s builds now (no member after it is queued, no chained one incomplete; waited %d frame(s))"):format(tostring(data.id), waited)) end
    chainOrderWaits[region] = nil
    return false
  end
  -- ForeverAuras (dev.74, Astra's dev.72 review): the queue is walked from
  -- where the last frame's walk stopped, not from its head: when the waiting
  -- members at the head use up the frame's budget on their order scans, the
  -- ready ones behind them are still reached on the next frames (a snapshot
  -- of the queue; every entry is checked against the live queue and the
  -- current data before it is built, as before).
  local queue, count = {}, 0
  for region, data in pairs(pending) do count = count + 1; queue[count] = region end
  -- (dev.79, Astra's dev.77 review: the cursor advanced inside the walk AND
  -- indexed by the step, a stride of two that starved every other entry)
  local base, visited = drainCursor, 0
  for step = 1, count do
    local region = queue[((base + step - 1) % count) + 1]
    local data = pending[region]
    visited = step
    if data then
      local existing = region.blizzardAuraDisplay
      -- (dev.72) the order scans are charged to the budget as the builds are;
      -- an entry the budget stops before its scan is the next frame's first
      if debugprofilestop() - started > budget then visited = step - 1; break end
      visited = step
      if not (restricted and (not ProbeEligible(data) or (existing and #existing.instances > 0))) and not ChainOrderWaits(region, data) then
        pending[region] = nil
        if WeakAuras.GetData(data.id) == data and Private.regions[data.id] and Private.regions[data.id].region == region then
          xpcall(Display.Apply, geterrorhandler(), region, data)
          if debugprofilestop() - started > budget then break end
        end
      end
    end
  end
  drainCursor = count > 0 and ((base + visited) % count) or 0
  drainingNow = false
  -- ForeverAuras: the groups' re-chains run here, so they are charged to the
  -- frame's budget with the builds (rc.50 review: charged before them, the
  -- reserve drain could start more work in a frame already past its budget).
  if Display.EndFlowLoad then Display.EndFlowLoad() end
  -- ForeverAuras: Grid rebuilds set aside under restrictions, one group per
  -- job within the same budget (dev.4 review: they ran all at once inside
  -- the combat-end event, and one error there lost the rest). After the
  -- displays' batch is closed, so each job's rechain runs and is measured
  -- here, not merely queued for the batch flush (dev.5 review).
  -- While an outer hold is open (the editor's batched pick, OptionsFrame),
  -- a rechain would only join that batch and be flushed with every other
  -- one at once, outside this measured sequence: the requests wait for the
  -- hold to end, which restarts the drain (SecretAuraFlow.lua, EndFlowLoad).
  local held = Display.FlowLoadHeld and Display.FlowLoadHeld()
  if not restricted and not held then
    for id in pairs(gridPending) do
      if debugprofilestop() - started > budget then break end
      gridPending[id] = nil
      local data = WeakAuras.GetData(id)
      if data and Display.FlowGrid(data) and Private.regions[id] then
        xpcall(Display.RechainFlow, geterrorhandler(), data)
      end
    end
  end
  FrameBudgetSpend(debugprofilestop() - started)
  local profile = Private.loadProfile
  if profile and profile.done and not profile.deferredDone then
    profile.deferred = (profile.deferred or 0) + debugprofilestop() - started
    profile.deferredFrames = (profile.deferredFrames or 0) + 1
    if not next(pending) then profile.deferredDone = true end
  end
  -- Only waiting displays left under restrictions: the restriction-end
  -- handler restarts the drain, rather than polling every frame.
  local again = false
  for region, data in pairs(pending) do
    local existing = region.blizzardAuraDisplay
    if not (restricted and (not ProbeEligible(data) or (existing and #existing.instances > 0))) then again = true; break end
  end
  if not restricted and not held and next(gridPending) then again = true end
  if again then C_Timer.After(0, DrainPending) else draining = false end
end
-- ForeverAuras: called when an outer flow hold ends (EndFlowLoad): Grid
-- rebuilds that waited for it are drained from the next frame on.
function Display.ResumeGridDrain()
  if next(gridPending) and not draining and WeakAuras.IsLoginFinished() and not Restricted() then
    draining = true
    C_Timer.After(0, DrainPending)
  end
end

-- ForeverAuras: asks for a group's Grid to be rebuilt by the paced drain once
-- restrictions allow it (SecretAuraGrid.lua). Out of restrictions the drain
-- starts on the next frame; under them, the restriction-end handler starts it.
function Display.QueueGridRebuild(id)
  if not id then return end
  gridPending[id] = true
  if not draining and WeakAuras.IsLoginFinished() and not Restricted() then
    draining = true
    C_Timer.After(0, DrainPending)
  end
end
-- Drops a group's queued Grid rebuild (the group was deleted or turned into a row).
function Display.CancelGridRebuild(id)
  if id then gridPending[id] = nil end
end

Private.callbacks:RegisterCallback("WEAKAURAS_LOGIN_COMPLETE", function()
  if next(pending) and not draining then
    draining = true
    C_Timer.After(0, DrainPending)
  end
end)

events:SetScript("OnEvent", function(_, event, unit)
  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    for region in pairs(activeRegions) do pending[region] = region.blizzardAuraDisplay.data; if MarkRequest then MarkRequest(region) end end
    if not draining then
      draining = true
      DrainPending()
    end
    return
  end
  -- Only the target's, focus's and pet's targets are watched. (The pet was
  -- dropped here, so a Pet Target display kept the previous target's auras.)
  if event == "UNIT_TARGET" and unit ~= "target" and unit ~= "focus" and unit ~= "pet" then return end
  -- Modern Aura Groups re-anchor once after all their displays rebound units.
  Display.BeginFlowBatch()
  for region in pairs(activeRegions) do
    local trigger = Display.GetSavedTrigger(region.blizzardAuraDisplay.data)
    local mode = trigger and trigger.unit
    -- ForeverAuras: a hidden display (unloaded, or prepared ahead of its
    -- first load, PrewarmRegions) does no unit work on events; its OnShow
    -- refreshes its units and sounds when it is shown again (rc.50 review:
    -- hidden target displays rebound on every target change).
    if not region:IsShown() then
      -- nothing
      if event == "PLAYER_TARGET_CHANGED" and mode == "target" and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: target changed, display hidden (no unit work)"):format(tostring(region.id))) end
    elseif event == "UNIT_FACTION" then
      -- A plate's side changed (PvP flag, mind control): re-check its hostility.
      if mode == "nameplate" then
        if type(unit) == "string" and not issecretvalue(unit) and unit:match("^nameplate%d+$") and Display.UsesHostility(trigger) then
          RefreshUnits(region, nil, unit, true)
        end
      elseif Display.UsesHostility(trigger) then
        -- A target, focus or specific unit changed side: its display re-checks the filter.
        RefreshUnits(region, nil, nil, true)
      end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
      if Display.UsesNameplates(region.blizzardAuraDisplay.data) then
        -- (1.3.6-dev.1) one count per display handling the plate event
        Private.HitchCount(event == "NAME_PLATE_UNIT_REMOVED" and "nameplate removed: displays refreshed" or "nameplate added: displays refreshed")
        -- ForeverAuras (1.3.6-dev.18, Astra's allocation question): the plate event's work
        -- is attributed to the display in the profile (/fa pprint: aura list, KB and ms);
        -- a no-op unless profiling runs.
        Private.StartProfileAura(region.id)
        if mode == "nameplate" then
          RefreshUnits(region, event == "NAME_PLATE_UNIT_REMOVED" and unit or nil, unit, true)
        else
          RefreshUnits(region, nil, nil, true)
        end
        Private.StopProfileAura(region.id)
      end
    elseif pending[region] and not Restricted() then
      -- Rebuilt below; refreshing it first would be wasted.
      -- ForeverAuras 1.2.1 (Dan's stale target countdown, Astra's trace): said under /fa cells debug
      if event == "PLAYER_TARGET_CHANGED" and mode == "target" and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: target changed, a rebuild is pending (no refresh now)"):format(tostring(region.id))) end
    elseif NeedsUnitRefresh(mode, event, unit, trigger) then
      if event == "PLAYER_TARGET_CHANGED" and mode == "target" and Display.BuildReporting and Display.BuildReporting() then CombatBuildReport(("%s: target changed, refreshing its units (restricted %s)"):format(tostring(region.id), tostring(Restricted()))) end
      RefreshUnits(region, nil, nil, true)
    end
    if not region:IsShown() then
      -- As above.
    elseif trigger and (event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED"
      or (event == "UNIT_NAME_UPDATE" and (trigger.useUnitNames or trigger.useUnitClass))) and unitEvents.GROUP_ROSTER_UPDATE[mode] then
      SyncSounds(region)
    elseif trigger and Display.UsesUnitEligibility(trigger)
      and (event == "UNIT_FACTION" or NeedsUnitRefresh(mode, event, unit, trigger)) then
      -- A new target, focus, plate or side can change which units may sound.
      SyncSounds(region)
    end
  end
  Display.EndFlowBatch()
  if Restricted() then return end
  if event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    for region in pairs(activeRegions) do Display.RefreshConditionAppearance(region) end
  end
  for region in pairs(pendingSounds) do SyncSounds(region) end
  -- (1.3.6-dev.1) the restriction-end drains, counted per region they visit
  if Private.HitchCounting and Private.HitchCounting() then
    local hides, locks = 0, 0
    for _ in pairs(lockedHide) do hides = hides + 1 end
    for _ in pairs(lockedUnits) do locks = locks + 1 end
    if hides > 0 then Private.HitchCount(("drain on %s: lockedHide regions"):format(tostring(event)), hides) end
    if locks > 0 then Private.HitchCount(("drain on %s: lockedUnits regions (full refresh each)"):format(tostring(event)), locks) end
    local owed = 0
    for _, tokens in pairs(pendingTokens) do for _ in pairs(tokens) do owed = owed + 1 end end
    if owed > 0 then Private.HitchCount(("drain on %s: owed tokens (one pass per region)"):format(tostring(event)), owed) end
  end
  for region in pairs(lockedHide) do
    lockedHide[region] = nil
    local native = region.blizzardAuraDisplay
    if native and not (native.active and region:IsShown()) then
      -- ForeverAuras: the same switch-off as at release time, now that the
      -- frames can be reached; a frame still locked is noted again.
      for _, instance in ipairs(native.instances) do
        QuietInstance(region, instance)
        Display.RefreshSingle(instance, nil, false)
      end
    end
  end
  for region in pairs(lockedUnits) do
    lockedUnits[region] = nil
    -- (1.3.6-dev.12) a full pass covers the region's owed tokens too (RefreshUnits drops them)
    if region.blizzardAuraDisplay and region.blizzardAuraDisplay.active then RefreshUnits(region, nil, nil, true) else pendingTokens[region] = nil end
  end
  -- ForeverAuras (1.3.6-dev.10/12, Astra's reviews): the tokens a region still
  -- owes are refreshed in ONE targeted pass per region (the set is handed to
  -- RefreshUnits), so the display-wide finishing work runs once however many
  -- plates changed. A token refused again is owed again by that pass; a
  -- token whose plate was removed and reassigned meanwhile is re-bound to its
  -- current plate and unit, exactly as the event would have. Regions are
  -- listed first: the pass may give back a region's entry while we walk.
  -- (Astra's dev.12 review) the set stays owned while the pass runs: the pass
  -- retires each token as its instance completes, so a pass that stops early
  -- leaves the failed token and the unvisited ones for the next drain.
  local owedRegions
  for region in pairs(pendingTokens) do owedRegions = owedRegions or {}; owedRegions[#owedRegions + 1] = region end
  if owedRegions then
    for _, region in ipairs(owedRegions) do
      local tokens = pendingTokens[region]
      if tokens then
        local native = region.blizzardAuraDisplay
        if native and native.active then RefreshUnits(region, nil, tokens, true) else pendingTokens[region] = nil end
      end
    end
  end
  -- ForeverAuras (Astra's overlay-reuse review, dev.4 follow-up): custom
  -- overlay retirements the client refused are tried again now, then the
  -- clones held out of the pool for them are pooled (AuraOverlay.lua,
  -- Private.PoolHeldClones in ForeverAuras.lua). Both sets are normally empty.
  if Private.RetryAuraOverlayRetirements then Private.RetryAuraOverlayRetirements() end
  if Private.PoolHeldClones then Private.PoolHeldClones() end
  -- ForeverAuras (dev.95): retained containers that could not be quieted when the editor closed
  if Display.QuietRetainedLater then Display.QuietRetainedLater() end
  -- ForeverAuras (combat-reload probe): list alphas a build in combat
  -- could not set (SecretAuraSingle.lua, ApplyPendingListAlpha).
  if Display.ApplyPendingListAlpha then Display.ApplyPendingListAlpha() end
  -- ForeverAuras (combat-reload probe): a display whose aura slot buttons
  -- refused their layout during a build in combat (SecretAuraSingle.lua,
  -- SlotWrite) is applied again now that they can be reached; only the
  -- displays noted there are visited.
  for _, region in ipairs((Display.TakePendingRelayout and Display.TakePendingRelayout()) or {}) do
    local native = region.blizzardAuraDisplay
    -- ForeverAuras (dev.72): a display whose build was set aside (a retry
    -- waiting for its abandoned frames to be cleaned) is not queued by a
    -- relayout: the retry below rebuilds it, with the current settings, once
    -- those frames are released
    if native and native.data and activeRegions[region] and not pending[region] and not retryAfterRestrictions[region] and not abandonedFrames[region] then pending[region] = native.data; if MarkRequest then MarkRequest(region) end end
  end
  -- ForeverAuras (combat-reload probe): the builds set aside are tried
  -- again, as new, their leftover frames cleaned first.
  for region in pairs(abandonedFrames) do CleanAbandoned(region) end
  for region, data in pairs(retryAfterRestrictions) do
    if not abandonedFrames[region] then
      retryAfterRestrictions[region] = nil
      if WeakAuras.GetData(data.id) == data then pending[region] = data; if MarkRequest then MarkRequest(region) end end
    end
  end
  -- ForeverAuras (dev.70): chained displays built as one spot under the restrictions are built again, chained.
  for region, data in pairs(chainDeferredRetry) do
    chainDeferredRetry[region] = nil
    local current = WeakAuras.GetData(data.id)
    if current and Private.regions[data.id] and Private.regions[data.id].region == region and not pending[region] then
      pending[region] = current; if MarkRequest then MarkRequest(region) end
    end
  end
  -- ForeverAuras: drained from the next frame on, not inside this handler:
  -- the restriction-end event already carries the game's own work and the
  -- condition refresh above (seen in game: a 19 ms frame with the queued
  -- rebuilds applied here).
  if (next(pending) or next(gridPending)) and not draining then
    draining = true
    C_Timer.After(0, DrainPending)
  end
  if next(instanceQueues) and not instanceDraining then
    instanceDraining = true
    C_Timer.After(0, DrainInstanceQueues)
  end
end)

for _, frame in ipairs({events, statusEvents}) do
  frame:SetScript("OnEvent", Private.Profiled("aura (modern) - events", frame:GetScript("OnEvent")))
end

-- ForeverAuras 1.2.5 (Astra's dev.8 review: bounded counts across combat and
-- death transitions, instead of frame polling or another heap scan): "/fa
-- modern" with no name prints the Modern displays' resource counts, the
-- builds made so far (fresh ones by reason, retired frames), the queues and
-- ledgers, and the same counts recorded at the last transitions (combat
-- start and end, death, resurrection), so growth across a series of fights
-- shows as rising numbers between entries. Recorded only at those events.
Display.summaryCounts = {freshBuilds = {}}
local function CountKeys(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
-- The counts are of the addon's own Lua structures (a subset: main instances and their addon-owned
-- button lists, the secondary containers each instance owns, the queues and ledgers); not native
-- record pools, not frames the client owns, and taken at the event, before paced repairs settle.
local function SummaryCounts()
  local c = Display.summaryCounts
  local regions, instances, buttons, visibleInstances, secondary, retained, abandoned, abandonedEntries = 0, 0, 0, 0, 0, 0, 0, 0
  for region in pairs(activeRegions) do
    regions = regions + 1
    local native = region.blizzardAuraDisplay
    for _, instance in ipairs(native and native.instances or {}) do
      instances = instances + 1
      buttons = buttons + #(instance.buttons or {})
      if instance.visible then visibleInstances = visibleInstances + 1 end
      -- the secondary containers an instance owns: the row shadow, the end measurement, the unit-frame
      -- glow's container, the Missing slot and the single display's Missing container
      if instance.flowShadow then secondary = secondary + 1 end
      if instance.flowMeasure then secondary = secondary + 1 end
      if instance.unitGlow and instance.unitGlow.container then secondary = secondary + 1 end
      if instance.missingSlot then secondary = secondary + 1 end
      if instance.single and instance.single.missing then secondary = secondary + 1 end
    end
  end
  for _ in pairs(retainedInstances) do retained = retained + 1 end
  for _, list in pairs(abandonedFrames) do abandonedEntries = abandonedEntries + 1; abandoned = abandoned + #list end
  -- (Astra's dev.1 review) the refused glow-binding owners inside every region's bucket, not the buckets
  local bindingRegions, bindingOwners = 0, 0
  for _, owners in pairs(abandonedGlowBindings) do bindingRegions = bindingRegions + 1; bindingOwners = bindingOwners + CountKeys(owners) end
  local fresh = 0
  for _, n in pairs(c.freshBuilds) do fresh = fresh + n end
  return {
    regions = regions, instances = instances, buttons = buttons, visibleInstances = visibleInstances, secondaryContainers = secondary,
    containersSetUp = c.containersSetUp or 0, freshBuilds = fresh, retirementAttempts = c.retirementAttempts or 0,
    pending = CountKeys(pending), orderWaits = CountKeys(chainOrderWaits), retryAfterRestrictions = CountKeys(retryAfterRestrictions),
    deferredRetry = CountKeys(chainDeferredRetry), lockedUnits = CountKeys(lockedUnits), lockedHide = CountKeys(lockedHide),
    retained = retained, abandonedLedgers = abandonedEntries, abandonedFrames = abandoned,
    abandonedBindingRegions = bindingRegions, abandonedBindingOwners = bindingOwners,
    queues = CountKeys(instanceQueues), editorQueue = CountKeys(editorQueue), gridPending = CountKeys(gridPending), pendingSounds = CountKeys(pendingSounds),
    heapMB = collectgarbage("count") / 1024,
  }
end
local summaryOrder = {"regions", "instances", "buttons", "visibleInstances", "secondaryContainers", "containersSetUp", "freshBuilds",
  "retirementAttempts", "pending", "orderWaits", "retryAfterRestrictions", "deferredRetry", "lockedUnits", "lockedHide", "retained",
  "abandonedLedgers", "abandonedFrames", "abandonedBindingRegions", "abandonedBindingOwners", "queues", "editorQueue", "gridPending", "pendingSounds"}
local summaryLog, SUMMARY_LOG_MAX = {}, 24
local function RecordSummary(label)
  local entry = SummaryCounts()
  entry.label, entry.at = label, GetTime()
  summaryLog[#summaryLog + 1] = entry
  while #summaryLog > SUMMARY_LOG_MAX do table.remove(summaryLog, 1) end
end
local summaryEvents = CreateFrame("Frame")
Private.frames["Modern Summary Events"] = summaryEvents
summaryEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
summaryEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
summaryEvents:RegisterEvent("PLAYER_DEAD")
summaryEvents:RegisterEvent("PLAYER_ALIVE")
summaryEvents:RegisterEvent("PLAYER_UNGHOST")
local summaryLabels = {PLAYER_REGEN_DISABLED = "+combat", PLAYER_REGEN_ENABLED = "-combat", PLAYER_DEAD = "dead", PLAYER_ALIVE = "alive", PLAYER_UNGHOST = "unghost"}
summaryEvents:SetScript("OnEvent", function(_, event) RecordSummary(summaryLabels[event] or event) end)
function Display.PrintSummary()
  local now = SummaryCounts()
  local parts = {}
  for _, key in ipairs(summaryOrder) do parts[#parts + 1] = key .. " " .. tostring(now[key]) end
  WeakAuras.prettyPrint(("Modern displays now (heap %.0f MB; the addon's own structures, a subset, at this moment): %s"):format(now.heapMB, table.concat(parts, ", ")))
  local reasons = {}
  for why, n in pairs(Display.summaryCounts.freshBuilds) do reasons[#reasons + 1] = why .. " x" .. n end
  table.sort(reasons)
  if #reasons > 0 then print("  containers made new, by reason: " .. table.concat(reasons, "; ")) end
  if #summaryLog == 0 then print("  no transition recorded yet (combat start/end, death, resurrection)") return end
  print(("  the last %d transitions (each line: what changed since the line before it; a number only when it changed):"):format(#summaryLog))
  local previous
  for _, entry in ipairs(summaryLog) do
    local changes = {}
    for _, key in ipairs(summaryOrder) do
      if previous and entry[key] ~= previous[key] then changes[#changes + 1] = ("%s %+d"):format(key, entry[key] - previous[key]) end
    end
    print(("    %s %.0fs ago, heap %.0f MB: %s"):format(entry.label, GetTime() - entry.at, entry.heapMB,
      previous and (#changes > 0 and table.concat(changes, ", ") or "no change") or "first"))
    previous = entry
  end
end

-- ForeverAuras 1.2.4 (Dan's session-long growth): the file's own tables are memory scan roots (/fa memscan), resolved to the CURRENT table only when the scan runs (Astra's dev.1 review: a saved reference would pin a table a reset has replaced)
Private.memoryRootAccessors = Private.memoryRootAccessors or {}
Private.memoryRootAccessors["BlizzardAuraDisplay: Display"] = function() return Display end
Private.memoryRootAccessors["BlizzardAuraDisplay: pending"] = function() return pending end
Private.memoryRootAccessors["BlizzardAuraDisplay: requestStamp"] = function() return requestStamp end
Private.memoryRootAccessors["BlizzardAuraDisplay: chainOrderWaits"] = function() return chainOrderWaits end
Private.memoryRootAccessors["BlizzardAuraDisplay: retryAfterRestrictions"] = function() return retryAfterRestrictions end
Private.memoryRootAccessors["BlizzardAuraDisplay: chainDeferredRetry"] = function() return chainDeferredRetry end
Private.memoryRootAccessors["BlizzardAuraDisplay: abandonedFrames"] = function() return abandonedFrames end
Private.memoryRootAccessors["BlizzardAuraDisplay: abandonedGlowBindings"] = function() return abandonedGlowBindings end
Private.memoryRootAccessors["BlizzardAuraDisplay: lockedHide"] = function() return lockedHide end
Private.memoryRootAccessors["BlizzardAuraDisplay: lockedUnits"] = function() return lockedUnits end
Private.memoryRootAccessors["BlizzardAuraDisplay: pendingSounds"] = function() return pendingSounds end
Private.memoryRootAccessors["BlizzardAuraDisplay: activeRegions"] = function() return activeRegions end
Private.memoryRootAccessors["BlizzardAuraDisplay: retainedInstances"] = function() return retainedInstances end
Private.memoryRootAccessors["BlizzardAuraDisplay: unitFrameGlowSizes"] = function() return unitFrameGlowSizes end
Private.memoryRootAccessors["BlizzardAuraDisplay: instanceQueues"] = function() return instanceQueues end
Private.memoryRootAccessors["BlizzardAuraDisplay: editorQueue"] = function() return editorQueue end
Private.memoryRootAccessors["BlizzardAuraDisplay: glowStatusPending"] = function() return glowStatusPending end
Private.memoryRootAccessors["BlizzardAuraDisplay: gridPending"] = function() return gridPending end
