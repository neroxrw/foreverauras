-- Modified for ForeverAuras, 2026-09-19.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local SharedMedia = LibStub("LibSharedMedia-3.0")
local Display = {}
Private.BlizzardAuraDisplay = Display
local pending = setmetatable({}, {__mode = "k"})
local pendingSounds = {}
local activeRegions = {}
local unitGlowFrameLevel = 8

Display.units = {
  player = "Player", target = "Target", focus = "Focus", pet = "Pet", mouseover = "Mouseover",
  targettarget = "Target of Target", focustarget = "Target of Focus", group = "Smart Group",
  party = "Party", raid = "Raid", boss = "Boss", arena = "Arena", nameplate = "Nameplate",
}

Display.booleanFilters = {
  {"isFromPlayerOrPlayerPet", "Own Only", "Auras cast by you or your pet. Vehicle casts are not included. Use Own Only: Include Vehicle instead to include them."},
  {"canApplyAura", "Can Apply Aura", "Auras Blizzard says your character can apply."},
  {"isStealable", "Is Stealable", "Buffs that can be stolen with abilities such as Spellsteal."},
  {"isBossAura", "Is Boss Aura", "Auras Blizzard identifies as boss auras."},
  {"isRoleAura", "Role aura", "Auras Blizzard marks as relevant to your role."},
  {"isBossOrRoleAura", "Boss or role aura", "Auras Blizzard identifies as boss auras or marks as relevant to your role."},
  {"isPriorityAura", "Priority debuff", "Debuffs Blizzard marks as high priority."},
  {"nameplateShowAll", "Marked for all nameplates", "Auras Blizzard marks for display on all nameplates."},
  {"nameplateShowPersonal", "Marked for personal debuff display", "Auras Blizzard marks for its personal-debuff display on nameplates."},
}

function Display.GetTrigger(data, displayFilters)
  if not data or type(data.triggers) ~= "table" then return end
  local source = data.progressSource and data.progressSource[1] or -1
  if source == 0 then return end
  if source < 0 then source = data.triggers.activeTriggerMode or -1 end
  if source < 0 then source = (Private.GetActiveTriggerFor and Private.GetActiveTriggerFor(data.id)) or 1 end
  local entry = data.triggers[source]
  local trigger = type(entry) == "table" and entry.trigger
  if trigger and trigger.type == "secretAura" then
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
Display.dispelTypes = {Magic = "Magic", Curse = "Curse", Disease = "Disease", Poison = "Poison", Bleed = "Bleed", [""] = "Enrage"}
Display.nativeFilters = {
  {"PLAYER", "Own Only: Include Vehicle", "Auras cast by you, your pet or your vehicle. Use this instead of the player-and-pet filter when vehicle casts should also match."},
  {"RAID", "Can apply / dispel", "Buffs you can apply, or debuffs you can dispel."},
  {"CANCELABLE", "Cancelable", "Auras that the player can cancel."},
  {"EXTERNAL_DEFENSIVE", "External defensive", "Auras Blizzard classifies as external defensives."},
  {"CROWD_CONTROL", "Crowd control", "Auras with a crowd-control effect, such as a stun or fear."},
  {"RAID_IN_COMBAT", "Shown on raid frames in combat", "Auras flagged by Blizzard for raid-frame display in combat."},
  {"RAID_PLAYER_DISPELLABLE", "Dispellable by someone in your raid", "Includes helpful enrages on enemies."},
  {"BIG_DEFENSIVE", "Big defensive", "Auras Blizzard classifies as big defensives."},
  {"IMPORTANT", "Important aura", "Blizzard's important-aura flag, including non-stealable enemy buffs shown on nameplates."},
  {"DISPELLABLE", "Dispellable", "Dispellable regardless of your or your raid's current abilities."},
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
  Default = "Blizzard default", BigDefensive = "Big defensives", UnitFrameDebuff = "Unit-frame debuffs",
  ImportantOnly = "Importance only", Expiration = "Remaining time (Blizzard priority)",
  ExpirationOnly = "Remaining time", Name = "Name (Blizzard priority)", NameOnly = "Name",
  AuraInstanceIDOnly = "Aura instance ID",
}
Display.processedTypes = {any = "Any (no classification)", Buff = "Buff", Debuff = "Debuff", Dispel = "Dispellable raid debuff"}
Display.processingOptions = {
  {"displayOnlyDispellableDebuffs", "Use dispellable-debuff classification"},
  {"ignoreBuffs", "Ignore buff classification"},
  {"ignoreDebuffs", "Ignore debuff classification"},
  {"ignoreDispelDebuffs", "Ignore dispel classification"},
}

function Display.UsesSpellIDs(trigger)
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
      end
    end
  end
  if Display.UsesSpellIDs(trigger) then
    for _, value in ipairs(trigger.auraspellids or {}) do Add(value) end
  end
  return ids
end

-- Completed public metadata scans update filters, sounds, and deferred displays.
function Display.RefreshSpellRanks()
  for region in pairs(activeRegions) do
    local data = region.blizzardAuraDisplay.data
    if Display.UsesRankSpellIDs(Display.GetTrigger(data)) then Display.Apply(region, data) end
  end
end

function Display.UsesExcludedSpellIDs(trigger)
  return trigger.secretUseExcludedSpellIDs ~= false and (#(trigger.excludedAuraSpellIDs or {}) > 0 or trigger.secretUseExcludedSpellIDs == true)
end

function Display.HasAdditionalFilters(trigger)
  if next(trigger.nativeFilters or {}) then return true end
  if Display.UsesExcludedSpellIDs(trigger) or next(trigger.includeDispelTypes or {})
    or next(trigger.excludeDispelTypes or {}) or trigger.maxDuration ~= nil
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

local function ElementFrame(native, key)
  native.elementFrames = native.elementFrames or {}
  if not native.elementFrames[key] then
    local frame = CreateFrame("Frame", nil, native.button)
    frame:SetAllPoints(native.button)
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

function Display.Eligible(data)
  return data and (data.regionType == "icon" or data.regionType == "aurabar" or data.regionType == "text") and Display.GetTrigger(data) ~= nil
end

function Display.Enabled(data)
  return Display.Eligible(data)
end

local function Capacity(trigger)
  local unit = trigger.unit
  if unit == "group" or unit == "raid" or unit == "nameplate" then return 40 end
  if unit == "party" or unit == "arena" then return 5 end
  if unit == "boss" then return 10 end
  return 1
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

local function UnitTokens(trigger)
  local unit = trigger.unit
  local result = {}
  if unit == "group" then unit = IsInRaid() and "raid" or "party" end
  if unit == "party" then
    result[1] = "player"
    for i = 1, GetNumSubgroupMembers() do result[#result + 1] = "party" .. i end
  elseif unit == "raid" then
    if IsInRaid() then for i = 1, GetNumGroupMembers() do result[i] = "raid" .. i end end
  elseif unit == "boss" or unit == "arena" or unit == "nameplate" then
    for i = 1, Capacity(trigger) do result[i] = unit .. i end
  else
    result[1] = unit
  end
  if (trigger.useUnitNames or trigger.useUnitRoles) and (trigger.unit == "group" or trigger.unit == "party" or trigger.unit == "raid") then
    local filtered = {}
    for _, token in ipairs(result) do
      local role = trigger.useUnitRoles and UnitGroupRolesAssigned(token)
      if MatchesUnitName(trigger, token) and (not trigger.useUnitRoles
        or (not issecretvalue(role) and (trigger.unitRoles or {})[role])) then
        filtered[#filtered + 1] = token
      end
    end
    return filtered
  end
  return result
end

function Display.GetPreviewUnit(data)
  local trigger = Display.GetTrigger(data)
  if not trigger then return "player" end
  for _, unit in ipairs(UnitTokens(trigger)) do
    if UnitExists(unit) and (data.anchorFrameType ~= "UNITFRAME" or ForeverAuras.GetUnitFrame(unit)) then return unit end
  end
  return "player"
end

function Display.Validate(data)
  if not Display.Eligible(data) then
    return "Select an Aura (Blizzard) trigger as the progress source of an Icon, Progress Bar or Text."
  end
  local appearanceProblem = Display.ValidateAppearance(Display.PrepareConditionAppearance(data))
  if appearanceProblem then return appearanceProblem end
  local trigger = Display.GetTrigger(data, true)
  if Display.UsesSpellIDs(trigger) and #(trigger.auraspellids or {}) == 0 then return "Enter an exact spell ID, or untick Exact Spell IDs to show all matching auras." end
  if Display.UsesRankSpellIDs(trigger) and #(trigger.auraRankSpellIDs or {}) == 0 then return "Enter a spell ID, or untick Spell ID(s) (All Ranks)." end
  if Display.UsesExcludedSpellIDs(trigger) and #(trigger.excludedAuraSpellIDs or {}) == 0 then return "Enter an ignored spell ID, or untick Ignored Exact Spell IDs." end
  if not Display.units[trigger.unit] or (trigger.debuffType ~= "HELPFUL" and trigger.debuffType ~= "HARMFUL") then
    return "Choose a supported unit and Buff or Debuff."
  end
  if trigger.unit == "nameplate" and (not C_NamePlate or not C_NamePlate.GetNamePlateForUnit) then
    return "This client does not expose nameplate frames."
  end
  for _, list in ipairs({trigger.auraspellids or {}, trigger.auraRankSpellIDs or {}, trigger.excludedAuraSpellIDs or {}}) do
    for _, value in ipairs(list) do
      local id = tonumber(value)
      if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then
        return "Each aura spell ID must be a positive whole number."
      end
    end
  end
  for _, field in ipairs(Display.booleanFilters) do
    if trigger[field[1]] ~= nil and type(trigger[field[1]]) ~= "boolean" then return "Invalid aura filter: " .. field[2] end
  end
  for _, field in ipairs(Display.processingOptions) do
    if trigger[field[1]] ~= nil and type(trigger[field[1]]) ~= "boolean" then return "Invalid classification option: " .. field[2] end
  end
  if trigger.maxDuration ~= nil and (type(trigger.maxDuration) ~= "number" or trigger.maxDuration <= 0
    or trigger.maxDuration == math.huge or trigger.maxDuration ~= trigger.maxDuration) then return "Maximum total duration must be a positive number." end
  if trigger.sortMethod and not Display.sortMethods[trigger.sortMethod] then return "Choose a supported sort order." end
  if trigger.sortMethod == "UnitFrameDebuff" and trigger.processedAuraType ~= "Debuff" and trigger.processedAuraType ~= "Dispel" then
    return "Unit-frame debuff sorting requires the Debuff or Dispellable raid debuff classification."
  end
  if trigger.processedAuraType and not Display.processedTypes[trigger.processedAuraType] then return "Choose a supported Blizzard classification." end
  local nativeKeys = {}
  for _, field in ipairs(Display.nativeFilters) do nativeKeys[field[1]] = true end
  for key, value in pairs(trigger.nativeFilters or {}) do
    if not nativeKeys[key] or type(value) ~= "boolean" then return "Choose supported Blizzard aura filters." end
  end
  if AuraUtil and AuraUtil.IsValidFilterString and not AuraUtil.IsValidFilterString(FilterString(trigger)) then
    return "This client does not support the selected Blizzard aura filters."
  end
  for _, field in ipairs({"includeDispelTypes", "excludeDispelTypes"}) do
    for name, value in pairs(trigger[field] or {}) do
      if not Display.dispelTypes[name] or value ~= true then return "Choose supported dispel types." end
    end
  end
  local parent = data.parent and ForeverAuras.GetData(data.parent)
  while parent do
    if parent.regionType == "dynamicgroup" then
      return "Secret Aura trigger detected. You cannot place this aura in a Dynamic Group."
    end
    parent = parent.parent and ForeverAuras.GetData(parent.parent)
  end
  local conditionProblem = Display.ValidateConditions(data)
  if conditionProblem then return conditionProblem end
  for when, action in pairs(data.actions or {}) do
    if when ~= "init" then
      for key, value in pairs(action) do
        if key:match("^do_") and key ~= "do_sound" and key ~= "do_message" and value then
          return "Secret Aura trigger detected. Only Chat Message, Play Sound and Hide Glows are supported in On Show/On Hide. Custom Init is available."
        end
      end
      if action.stop_sound or (action.do_sound and action.sound == " KitID") then
        return "Secret aura sounds support sound files, not Sound Kit IDs or Stop Sound."
      end
    end
  end
  for _, animation in pairs(data.animation or {}) do
    if animation.type and animation.type ~= "none" then
      return "Secret Aura trigger detected. You cannot use Animations on this aura."
    end
  end
end

local function Restricted()
  return InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret())
end

local function Warn(data, message)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_display", message and "warning" or nil, message)
end

local function SoundWarning(data, message)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_sound", message and "warning" or nil, message)
end

function Private.ResolveFojjiRecordedSound(value)
  local db = FojjiCoreDB
  if not FojjiCore or not db then return nil, "FojjiCore is not loaded." end
  if db.disableTTS then return nil, "Speech is disabled in FojjiCore." end
  if db.ttsVoiceType ~= "custom" or db.ttsRandomFavorites then
    return nil, "Select one recorded voice pack in FojjiCore. Recorded sounds cannot use synthesized TTS or random favorites."
  end
  local pack = FojjiCore.voicePacks and FojjiCore.voicePacks[db.ttsVoicePack]
  local file = pack and pack[value]
  if not file then return nil, "No recording for '" .. value .. "' in the selected FojjiCore voice pack." end
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
  return ForeverAuras.IsOptionsOpen() and not InCombatLockdown()
end

local function SyncSounds(region)
  if Restricted() then
    pendingSounds[region] = true
    return
  end
  pendingSounds[region] = nil
  local native = region.blizzardAuraDisplay
  if not native then return end
  for _, id in ipairs(native.soundIDs or {}) do C_UnitAuras.RemoveAuraSound(id) end
  native.soundIDs = {}
  local data = native.data
  SoundWarning(data)
  if not native.active or not region:IsShown() or IsPreview() then return end
  local actions = data.actions or {}
  if not ((actions.start or {}).do_sound or (actions.finish or {}).do_sound) then return end
  if not C_UnitAuras or not C_UnitAuras.AddAuraSound or not C_UnitAuras.RemoveAuraSound
    or not Enum.UnitAuraSoundTrigger then
    SoundWarning(data, "This client does not provide native aura sound registration.")
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
    SoundWarning(data, "Enable Spell ID(s) or Exact Spell ID(s) in Trigger and enter an ID that is not ignored to use aura sounds.")
    return
  end
  local failure
  local units = UnitTokens(trigger)
  for _, event in ipairs({"Added", "Removed"}) do
    local action = actions[event == "Added" and "start" or "finish"] or {}
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
        message = message or "Choose a sound file in Actions."
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
              failure = "Blizzard could not register the " .. event:lower() .. " sound for spell " .. spellID .. "."
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
  if trigger and (Display.UsesSpellIDs(trigger) or Display.UsesRankSpellIDs(trigger)) then
    local unit = trigger.unit
    local friendly = unit == "player" or unit == "pet" or unit == "group" or unit == "party" or unit == "raid"
    if friendly and trigger.debuffType == "HARMFUL" then
      warning = "Preview only: secret debuffs will not display with spell ID filters.\nConfigured sounds in Actions can still play."
    end
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

local function Suppress(region)
  local native = region.blizzardAuraDisplay
  if IsPreview() and not region.secretAuraSamplesActive and not (native and native.previewHasAuras) then
    for frame, alpha in pairs(region.blizzardSuppressed or {}) do frame:SetAlpha(alpha) end
    region.blizzardSuppressed = nil
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
end

function Display.Restore(region)
  -- Pooled samples must never survive release or a trigger switch.
  if Display.HidePreview then Display.HidePreview(region) end
  if region.secretAuraPreviewNotice then region.secretAuraPreviewNotice:Hide() end
  region.secretAuraConditionValues = nil
  for frame, alpha in pairs(region.blizzardSuppressed or {}) do frame:SetAlpha(alpha) end
  region.blizzardSuppressed = nil
  if region.blizzardOriginalUpdate then
    region.Update = region.blizzardOriginalUpdate.func
    region.blizzardOriginalUpdate = nil
  end
  if region.blizzardOriginalPreShow then
    region.PreShow = region.blizzardOriginalPreShow.func
    region.blizzardOriginalPreShow = nil
  end
end

function Display.HideUnitGlows(region)
  local native = region.blizzardAuraDisplay
  if not native then return end
  native.unitGlowsHidden = true
  for _, instance in ipairs(native.instances) do
    if instance.unitGlow then
      instance.unitGlow.container:SetEnabled(false)
      instance.unitGlow.container:Hide()
    end
  end
end

function Display.Release(region)
  Display.HideUnitGlows(region)
  Display.Restore(region)
  pending[region] = nil
  local native = region.blizzardAuraDisplay
  if native then
    native.active = false
    for _, instance in ipairs(native.instances) do
      instance.container:SetEnabled(false)
      instance.container:Hide()
    end
    activeRegions[region] = nil
    SyncSounds(region)
  end
end

local function StyleText(text, native, settings, key, size, anchor, x, y)
  local button = native.button
  local font = settings[key .. "Font"]
  text:SetFont(font and SharedMedia:Fetch("font", font) or "Fonts\\ARIALN.TTF", settings[key .. "Size"] or size, (settings[key .. "Outline"] == "None" and "" or settings[key .. "Outline"]) or "OUTLINE")
  text:SetTextColor(unpack(settings[key .. "Color"] or {1, 1, 1, 1}))
  local outline = settings[key .. "Outline"]
  local slug = outline == "OUTLINE|SLUG" or outline == "THICKOUTLINE|SLUG"
  text:SetShadowColor(unpack(slug and {0, 0, 0, 0} or settings[key .. "ShadowColor"] or {0, 0, 0, 0}))
  text:SetShadowOffset(settings[key .. "ShadowX"] or 1, settings[key .. "ShadowY"] or -1)
  local point = settings[key .. "Anchor"] or anchor
  -- Preserve the original same-point anchors until a self point is chosen.
  local selfPoint = settings[key .. "SelfPoint"]
  local target = button
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
    entry.texture:SetPoint("TOPLEFT", native.button, "TOPLEFT", (settings.glowX or 0) - settings.padding, (settings.glowY or 0) + settings.padding)
    entry.texture:SetPoint("BOTTOMRIGHT", native.button, "BOTTOMRIGHT", (settings.glowX or 0) + settings.padding, (settings.glowY or 0) - settings.padding)
  else
    entry.texture:SetPoint("CENTER", native.glowAnchor or native.button, "CENTER", settings.glowX or 0, settings.glowY or 0)
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

local function Style(native, data, region)
  Display.StyleAppearance(native, Display.PrepareConditionAppearance(data), ElementFrame, StyleText, StyleGlow)
  Display.ApplyConditionAppearance(native, region, data)
end

local function SpellIDMap(values)
  local ids = {}
  for _, value in ipairs(values or {}) do ids[tonumber(value)] = true end
  return next(ids) and ids or nil
end

local function CandidateFilters(data)
  local trigger = Display.GetTrigger(data)
  local filters = {maxDuration = trigger.maxDuration}
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

-- The editor always renders public samples; live containers remain disabled.
local function RefreshPreview(region)
  local native = region.blizzardAuraDisplay
  native.previewHasAuras = IsPreview()
  if native.previewHasAuras then
    Display.ShowPreview(region, native.data, function(sample, data)
      Display.StyleAppearance(sample, Display.PrepareConditionAppearance(data), ElementFrame, StyleText, StyleGlow)
    end)
  else
    Display.HidePreview(region)
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
  native.container:SetAuraSlotSortMethod("UnitGlow", AuraContainerSortMethod[trigger.sortMethod or "Default"],
    trigger.sortReverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
  native.container:SetAuraSlotFilterString("UnitGlow", FilterString(trigger))
  native.container:SetAuraSlotCandidateFilters("UnitGlow", CandidateFilters(data))
end

local function CompactUnits(data)
  return data.anchorFrameType ~= "UNITFRAME" and not Display.UsesNameplates(data)
    and Capacity(Display.GetTrigger(data)) > 1
end

local function Layout(native, region, data)
  local width, height = Display.Dimensions(data)
  local settings = data.blizzardAuraDisplay
  local direction = settings.growth or "RIGHT"
  local vertical = direction == "UP" or direction == "DOWN" or direction == "CENTER_VERTICAL"
  local anchor = direction == "LEFT" and "TOPRIGHT" or direction == "UP" and "BOTTOMLEFT" or "TOPLEFT"
  local container = native.container
  container:ClearAllPoints()
  local centered = direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL"
  container:SetPoint(centered and "CENTER" or anchor, region, centered and "CENTER" or anchor)
  container:SetFlowLayoutAxis(vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
  container:SetFlowLayoutAnchorPoint(anchor)
  container:SetFlowLayoutGrowthDirection(direction == "LEFT" and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
    direction == "UP" and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
  local spacing = settings.spacing or 6
  local compact = not centered and CompactUnits(data)
  -- Empty native containers are one pixel wide/high. Reserve that pixel after
  -- occupied content too, then subtract it in the anchor chain, without reading sizes.
  container:SetAuraGroupLayout("Auras", {
    elementWidth = width + (compact and not vertical and spacing + 1 or 0),
    elementHeight = height + (compact and vertical and spacing + 1 or 0),
    elementSpacing = compact and -1 or spacing,
  })
  container:SetAuraGroupMaxFrameCount("Auras", settings.maxIcons or 10)
end

local function Create(region, data)
  local display = {buttons = {}, data = data}
  local container = CreateFrame("AuraContainer", nil, region, "CustomAuraContainerTemplate")
  display.container = container
  container:SetEnabled(false)
  ConfigureProcessing(container, Display.GetTrigger(data))
  container:SetPoint("TOPLEFT", region, "TOPLEFT")
  container:AddAuraGroup("Auras", FilterString(Display.GetTrigger(data)), {
    maxFrameCount = data.blizzardAuraDisplay.maxIcons or 10,
    candidateFilters = CandidateFilters(data),
    initializeFrame = function(button)
      local native = {container = container}
      native.button = button
      button:EnableMouse(false)
      for _, area in ipairs({"inner", "outer"}) do
        native[area] = CreateFrame("Frame", nil, button)
        native[area]:SetPoint("CENTER", button, "CENTER")
        native[area]:EnableMouse(false)
      end
      native.border = button:CreateTexture(nil, "BACKGROUND")
      native.border:SetAllPoints(button)
      local base = ElementFrame(native, "sharedBase")
      native.icon = base:CreateTexture(nil, "ARTWORK")
      button:SetIcon(native.icon)
      native.cooldown = CreateFrame("Cooldown", nil, base, "CooldownFrameTemplate")
      native.cooldown:SetAllPoints(native.icon)
      native.cooldown:SetDrawBling(false)
      native.cooldown:SetHideCountdownNumbers(true)
      button:SetDurationCooldown(native.cooldown)
      local overlay = CreateFrame("Frame", nil, button)
      native.overlay = overlay
      overlay:SetAllPoints(button)
      overlay:SetFrameLevel(native.cooldown:GetFrameLevel() + 1)
      Style(native, display.data, region)
      display.buttons[#display.buttons + 1] = native
    end,
  })
  return display
end

local unitFrameGlowSizes = setmetatable({}, {__mode = "k"})

local function AnchorUnitGlow(container, frame)
  local size = unitFrameGlowSizes[frame]
  if not size then
    size = {x = 0, y = 0}
    unitFrameGlowSizes[frame] = size
    frame:HookScript("OnSizeChanged", function() Display.UnitFramesChanged() end)
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
    level = math.max(level, instance.container:GetFrameLevel())
  end
  -- Reserve the native button, three levels per element, and glow/cooldown children.
  -- Only container frames are inspected; native aura buttons may be inaccessible.
  level = level + #(native.data.subRegions or {}) * 3 + 8
  for index, element in ipairs(region.subRegions or {}) do
    if element.secretAuraDetached then element:SetFrameLevel(level + index) end
  end
end

local function RefreshUnits(region, removedUnit, changedUnit)
  local native = region.blizzardAuraDisplay
  if not native or not native.active then return end
  local data = native.data
  local trigger = Display.GetTrigger(data)
  local settings = data.blizzardAuraDisplay
  local units = UnitTokens(trigger)
  local vertical = settings.growth == "UP" or settings.growth == "DOWN" or settings.growth == "CENTER_VERTICAL"
  for index, instance in ipairs(native.instances) do
    local container = instance.container
    local unit = units[index]
    if not changedUnit or unit == changedUnit then
      local unitFrames = data.anchorFrameType == "UNITFRAME"
      local nameplates = not unitFrames and Display.UsesNameplates(data)
      local anchorFrame
      if unit then
        if unitFrames then
          anchorFrame = ForeverAuras.GetUnitFrame(unit)
        elseif nameplates and unit ~= removedUnit then
          anchorFrame = C_NamePlate.GetNamePlateForUnit(unit)
        end
      end
      if anchorFrame and anchorFrame:IsForbidden() then anchorFrame = nil end
      -- Live aura visibility must not affect the editor samples.
      local shown = not IsPreview() and unit ~= nil and region:IsShown() and (not (unitFrames or nameplates) or anchorFrame ~= nil)
      local parent = unitFrames and data.anchorFrameParent ~= false and anchorFrame or region
      -- Disabling clears native aura assignments and restarts their animations.
      if instance.boundUnit ~= unit or container:GetParent() ~= parent then
        container:SetEnabled(false)
        if unit then container:SetUnit(unit) end
        instance.boundUnit = unit
        if container:GetParent() ~= parent then container:SetParent(parent) end
      end
      container:SetAlpha(parent == region and 1 or data.alpha or 1)
      container:SetFrameStrata((data.frameStrata == nil or data.frameStrata == 1) and parent:GetFrameStrata() or region:GetFrameStrata())
      if unitFrames then
        -- Keep native aura content above the unit glow and its two child layers.
        local level = anchorFrame and settings.unitGlow and anchorFrame:GetFrameLevel() + unitGlowFrameLevel + 3 or parent:GetFrameLevel() + 1
        container:SetFrameLevel(level)
        container:ClearAllPoints()
        container:SetPoint(data.selfPoint or "CENTER", anchorFrame or region, data.anchorPoint or "CENTER", data.xOffset or 0, data.yOffset or 0)
      elseif nameplates then
        container:ClearAllPoints()
        container:SetPoint("BOTTOM", anchorFrame or region, "TOP", settings.nameplateX or 0, settings.nameplateY or 8)
      else
        local direction = settings.growth or "RIGHT"
        local anchor = direction == "LEFT" and "TOPRIGHT" or direction == "UP" and "BOTTOMLEFT" or "TOPLEFT"
        container:ClearAllPoints()
        if direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL" then
          container:SetPoint("CENTER", region, "CENTER")
        elseif CompactUnits(data) and index > 1 then
          local previous = native.instances[index - 1].container
          local edge = direction == "LEFT" and "TOPLEFT" or direction == "UP" and "TOPLEFT"
            or direction == "DOWN" and "BOTTOMLEFT" or "TOPRIGHT"
          container:SetPoint(anchor, previous, edge,
            vertical and 0 or (direction == "LEFT" and 1 or -1),
            vertical and (direction == "UP" and -1 or 1) or 0)
        else
          container:SetPoint(anchor, region, anchor)
        end
      end
      instance.visible = shown
      container:SetShown(shown)
      container:SetEnabled(shown)
      if shown then container:UpdateAllAuras() end
      if instance.unitGlow then
        local glowContainer = instance.unitGlow.container
        local frame = unitFrames and unit and settings.unitGlow and anchorFrame
        if frame and frame:IsForbidden() then frame = nil end
        local glowShown = not IsPreview() and frame ~= nil and frame ~= false and region:IsShown() and not native.unitGlowsHidden and settings.unitGlow == true
        local glowParent = frame or region
        if instance.unitGlow.boundUnit ~= unit or glowContainer:GetParent() ~= glowParent then
          glowContainer:SetEnabled(false)
          if unit then glowContainer:SetUnit(unit) end
          instance.unitGlow.boundUnit = unit
          if glowContainer:GetParent() ~= glowParent then glowContainer:SetParent(glowParent) end
        end
        glowContainer:ClearAllPoints()
        if frame then AnchorUnitGlow(glowContainer, frame) else glowContainer:SetAllPoints(glowParent) end
        glowContainer:SetFrameStrata(glowParent:GetFrameStrata())
        glowContainer:SetFrameLevel(glowParent:GetFrameLevel() + unitGlowFrameLevel)
        glowContainer:SetShown(glowShown)
        glowContainer:SetEnabled(glowShown)
        if glowShown then glowContainer:UpdateAllAuras() end
      end
    end
  end
  Display.UpdateDetachedFrameLevels(region)
  RefreshPreview(region)
end

local unitFrameRefreshPending
function Display.UnitFramesChanged()
  if unitFrameRefreshPending then return end
  local needed
  for region in pairs(activeRegions) do
    local data = region.blizzardAuraDisplay.data
    if data.anchorFrameType == "UNITFRAME" then needed = true; break end
  end
  if not needed then return end
  unitFrameRefreshPending = true
  -- LibGetFrame can report several frame changes together during a roster update.
  C_Timer.After(0, function()
    unitFrameRefreshPending = nil
    for region in pairs(activeRegions) do
      local data = region.blizzardAuraDisplay.data
      if data.anchorFrameType == "UNITFRAME" then RefreshUnits(region) end
    end
  end)
end

function Display.Apply(region, data)
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
    Suppress(region)
  else
    Display.HidePreview(region)
  end
  if Restricted() then
    pending[region] = data
    Warn(data, "Display > Secret Aura Settings changes will apply when aura restrictions end.")
    return
  end
  if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    local loaded, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    if not loaded then Warn(data, "Cannot load Blizzard_AuraContainer: " .. tostring(reason)); return end
  end
  local native = region.blizzardAuraDisplay
  if not native then
    native = {instances = {}, data = data}
    region.blizzardAuraDisplay = native
    region:HookScript("OnHide", function()
      Display.HideUnitGlows(region)
      for _, instance in ipairs(native.instances) do
        instance.container:SetEnabled(false)
        instance.container:Hide()
      end
      SyncSounds(region)
    end)
    region:HookScript("OnShow", function()
      native.unitGlowsHidden = false
      if native.active then RefreshUnits(region); SyncSounds(region) end
    end)
  end
  native.data = data
  if IsPreview() then UpdatePreviewNotice(region) end
  native.unitGlowsHidden = false
  -- Reserve containers before combat; roster and plate events only rebind existing ones.
  for index = 1, Capacity(Display.GetTrigger(data)) do
    if not native.instances[index] then native.instances[index] = Create(region, data) end
  end
  for _, instance in ipairs(native.instances) do
    instance.data = data
    -- Apply the complete configuration before Blizzard refreshes visible auras.
    instance.container:SetEnabled(false)
    for _, button in ipairs(instance.buttons) do Style(button, data, region) end
    Layout(instance, region, data)
    local trigger = Display.GetTrigger(data)
    ConfigureProcessing(instance.container, trigger)
    instance.container:SetAuraGroupSortMethod("Auras", AuraContainerSortMethod[trigger.sortMethod or "Default"],
      trigger.sortReverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
    instance.container:SetAuraGroupFilterString("Auras", FilterString(trigger))
    instance.container:SetAuraGroupCandidateFilters("Auras", CandidateFilters(data))
    ConfigureUnitGlow(instance, region, data)
  end
  native.active = true
  activeRegions[region] = true
  RefreshUnits(region)
  pending[region] = nil
  SyncSounds(region)
  Warn(data)
end

local function Install(region)
  if not region.blizzardOriginalUpdate then
    local update = region.Update
    region.blizzardOriginalUpdate = {func = update}
    region.Update = function(self, ...)
      if update then update(self, ...) end
      Suppress(self)
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
  Install(region)
  local native = region.blizzardAuraDisplay
  if native and native.data == data and not pending[region] and Display.Validate(data) == nil then
    native.unitGlowsHidden = false
    native.active = true
    activeRegions[region] = true
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
  if region.secretAuraProgressSourceIndex ~= key then Display.Modify(region, data) end
end

function Display.Modify(region, data)
  local trigger = Display.GetTrigger(data)
  local key = trigger and (data.progressSource and data.progressSource[1] or -1) or 0
  if key < 0 then key = (data.triggers.activeTriggerMode and data.triggers.activeTriggerMode > 0 and data.triggers.activeTriggerMode)
    or (Private.GetActiveTriggerFor and Private.GetActiveTriggerFor(data.id)) or 1 end
  region.secretAuraProgressSourceIndex = key
  region.secretAuraConditionValues = nil
  if not Display.Enabled(data) then Display.Release(region); Warn(data); SoundWarning(data); return end
  Install(region)
  Display.Apply(region, data)
end

-- Native containers watch UNIT_AURA themselves. Only rebind when their unit can change.
local unitEvents = {
  GROUP_ROSTER_UPDATE = {group = true, party = true, raid = true},
  PLAYER_ROLES_ASSIGNED = {group = true, party = true, raid = true},
  PLAYER_TARGET_CHANGED = {target = true, targettarget = true},
  PLAYER_FOCUS_CHANGED = {focus = true, focustarget = true},
  UPDATE_MOUSEOVER_UNIT = {mouseover = true},
  INSTANCE_ENCOUNTER_ENGAGE_UNIT = {boss = true},
  ARENA_OPPONENT_UPDATE = {arena = true},
}

local function NeedsUnitRefresh(mode, event, unit)
  if event == "UNIT_TARGET" then
    return (mode == "targettarget" and unit == "target") or (mode == "focustarget" and unit == "focus")
  elseif event == "UNIT_PET" then
    return mode == "pet" and unit == "player"
  end
  local modes = unitEvents[event]
  return modes == nil or modes[mode] == true
end

local events = CreateFrame("Frame")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
-- Reconfigure physical-pixel borders when the screen's pixel-to-UI ratio changes.
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
  "UPDATE_MOUSEOVER_UNIT", "UNIT_TARGET", "UNIT_PET", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "ARENA_OPPONENT_UPDATE",
  "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_NAME_UPDATE", "PLAYER_ROLES_ASSIGNED"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, unit)
  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    for region in pairs(activeRegions) do Display.Apply(region, region.blizzardAuraDisplay.data) end
    return
  end
  if event == "UNIT_AURA" then
    if IsPreview() then
      for region in pairs(activeRegions) do
        for _, instance in ipairs(region.blizzardAuraDisplay.instances) do
          if instance.visible and instance.boundUnit == unit then
            RefreshPreview(region)
            break
          end
        end
      end
    end
    return
  end
  for region in pairs(activeRegions) do
    local mode = Display.GetTrigger(region.blizzardAuraDisplay.data).unit
    if event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
      if Display.UsesNameplates(region.blizzardAuraDisplay.data) then
        if mode == "nameplate" then
          RefreshUnits(region, event == "NAME_PLATE_UNIT_REMOVED" and unit or nil, unit)
        else
          RefreshUnits(region)
        end
      end
    elseif NeedsUnitRefresh(mode, event, unit) then
      RefreshUnits(region)
    end
    if (event == "GROUP_ROSTER_UPDATE" or event == "UNIT_NAME_UPDATE" or event == "PLAYER_ROLES_ASSIGNED") and unitEvents.GROUP_ROSTER_UPDATE[mode] then SyncSounds(region) end
  end
  if Restricted() then return end
  if event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
    for region in pairs(activeRegions) do Display.RefreshConditionAppearance(region) end
  end
  for region in pairs(pendingSounds) do SyncSounds(region) end
  for region, data in pairs(pending) do
    if ForeverAuras.GetData(data.id) == data and Private.regions[data.id] and Private.regions[data.id].region == region then
      Display.Apply(region, data)
    else
      pending[region] = nil
    end
  end
end)
