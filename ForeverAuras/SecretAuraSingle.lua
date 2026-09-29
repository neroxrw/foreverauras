-- Show On, Remaining Time, Total Duration and Approximate Match for the
-- Aura (Blizzard) trigger.
--
-- Aura(s) Found lists every matching aura in a native aura group. Aura(s)
-- Missing, Always and Remaining Time watch one unit and draw at most one aura
-- in the region's own rectangle (a "single" display).
--
-- Nothing here reads aura state in combat; Blizzard's own bindings do the work:
--   Missing: an invisible native group gives its container a width only while
--     the aura is present; a clip anchored to that width hides the Missing icon.
--   Remaining Time: a Step colour curve over the remaining duration, on native
--     duration text holding the icon as inline texture markup.
--   Total Duration: a hidden text formatted from the total duration sizes a
--     clip that holds the whole aura button (StyleDurationGate).
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay

-- Units that name one unit; group, nameplate, boss and arena are lists.
Display.singleUnits = {player = true, target = true, focus = true, pet = true, targettarget = true, focustarget = true}
-- Stored in secret* fields, not the Aura (Legacy) ones, so auras converted from
-- Legacy keep their behaviour.
Display.showOnValues = {showOnActive = "Aura(s) Found", showOnMissing = "Aura(s) Missing", showAlways = "Always"}
Display.remOperators = {["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">="}

-- Keys of the extra native parts, unique within their containers.
local MISSING_GROUP = "FAMissing"
local SLOT_ICON = "FARemainIcon"
-- A Step curve point rules from its own value upwards; <= and > move the edge
-- just past the entered number.
local REMAIN_EPS = 0.001
-- Inline texture coordinates are integers of this texture size.
local TEXCOORD_UNITS = 1024

function Display.ShowOn(trigger)
  local value = type(trigger) == "table" and trigger.secretShowOn
  return Display.showOnValues[value] and value or "showOnActive"
end

-- As in Aura (Legacy), Remaining Time applies with Show On: Aura(s) Found only.
local function UsesRemaining(trigger)
  return type(trigger) == "table" and trigger.secretUseRem == true and Display.ShowOn(trigger) == "showOnActive"
end

-- True when the settings need the single-aura drawing.
function Display.IsSingle(trigger)
  return Display.ShowOn(trigger) ~= "showOnActive" or UsesRemaining(trigger)
end

-- Returns op, seconds when a usable Remaining Time filter is configured.
function Display.RemainingWindow(trigger)
  if not UsesRemaining(trigger) then return end
  local op, x = trigger.secretRemOperator or "<", tonumber(trigger.secretRem)
  if not Display.remOperators[op] or not x or x ~= x or x < 0 or x == math.huge then return end
  return op, x
end

function Display.InRemainingWindow(value, op, x)
  if op == "<" then return value < x
  elseif op == "<=" then return value <= x
  elseif op == ">" then return value > x end
  return value >= x
end

-- Step points for the window: its edge and the edge just past it.
function Display.RemainingWindowPoints(_, x)
  return {x, x + REMAIN_EPS}
end

local function NeedsMissing(trigger)
  local showOn = Display.ShowOn(trigger)
  return showOn == "showOnMissing" or showOn == "showAlways"
end

-- A single aura, or a Dynamic Group member, is one aura at the region's corner;
-- the group positions it like any other child.
local function DrawsOne(data)
  return Display.IsSingle(Display.GetTrigger(data)) or Display.InDynamicGroup(data)
end
Display.DrawsOne = DrawsOne

function Display.Growth(data)
  if DrawsOne(data) then return "RIGHT" end
  return data.blizzardAuraDisplay and data.blizzardAuraDisplay.growth or "RIGHT"
end

function Display.MaxAuras(data)
  -- The Total Duration gate stacks candidates: room for the right one among others.
  if Display.DurationGate(data) then return 20 end
  if DrawsOne(data) then return 1 end
  return data.blizzardAuraDisplay and data.blizzardAuraDisplay.maxIcons or 10
end

function Display.PreviewShowsMissing(data)
  local trigger = Display.GetTrigger(data)
  return Display.IsSingle(trigger) and Display.ShowOn(trigger) == "showOnMissing"
end

-- The icon drawn while the aura is absent or by the Remaining Time icon: the
-- manual icon, else the first selected spell's icon. Plain spell data only.
function Display.SingleIcon(data)
  if data.iconSource == 0 and data.displayIcon and data.displayIcon ~= "" then return data.displayIcon end
  local id = Display.GetSpellIDs(Display.GetTrigger(data) or {}, false)[1]
  local texture = id and C_Spell.GetSpellTexture(id)
  if texture and not issecretvalue(texture) then return texture end
  return 134400
end

-- A secret answer keeps the display shown rather than guessing that the unit
-- is gone.
function Display.SingleUnitExists(trigger)
  local unit = trigger and trigger.unit or "player"
  if unit == "player" then return true end
  local ok, exists = pcall(UnitExists, unit)
  if not ok or issecretvalue(exists) then return true end
  return exists == true
end

-- Countdown colour rules may come from any Aura (Blizzard) trigger; all of them
-- share the one binding that the Remaining Time window also uses.
local function HasRemainingPercentConditions(data)
  for _, condition in ipairs(data.conditions or {}) do
    local check = condition.check
    if check and Display.NativeConditionKind(data, check) and Display.IsNativeDurationCondition(check) and check.variable ~= "faAuraRemaining" then
      return true
    end
  end
  return false
end

-- True when a Dynamic Group can position the display: one unit, drawn in the
-- region's own rectangle. Several units would need one clone per unit.
function Display.FitsOneSlot(data, trigger)
  if not trigger or not Display.singleUnits[trigger.unit] then return false end
  return data.anchorFrameType ~= "UNITFRAME" and data.anchorFrameType ~= "NAMEPLATE"
end

function Display.InDynamicGroup(data)
  local parent = data and data.parent and ForeverAuras.GetData(data.parent)
  while parent do
    if parent.regionType == "dynamicgroup" then return true end
    parent = parent.parent and ForeverAuras.GetData(parent.parent)
  end
  return false
end

-- Pre-release test builds had a Mode setting and reused the Legacy fields;
-- those settings move to the dedicated fields.
function Display.MigrateSingle(data, trigger)
  if trigger.secretTracking == nil then return end
  if trigger.secretTracking == "single" then
    if trigger.secretShowOn == nil and Display.showOnValues[trigger.matchesShowOn] and trigger.matchesShowOn ~= "showOnActive" then
      trigger.secretShowOn = trigger.matchesShowOn
    end
    if trigger.secretUseRem == nil and trigger.useRem then
      trigger.secretUseRem, trigger.secretRemOperator, trigger.secretRem = true, trigger.remOperator, trigger.rem
    end
    data.blizzardAuraDisplay = data.blizzardAuraDisplay or {}
    data.blizzardAuraDisplay.maxIcons = 1
  end
  trigger.secretTracking = nil
end

-- Blizzard's containers refuse to pick auras by spell ID where that could
-- single out a secret aura: debuffs on friendly units and buffs on hostile
-- units (Blizzard_AuraContainerUtil, CanApplyIdentityCandidateFilters), unless
-- every selected spell is never secret. Target-like units can be either side.
local friendlyUnits = {player = true, pet = true, group = true, party = true, raid = true}
local hostileUnits = {boss = true, arena = true}

local function NeverSecret(ids)
  if #ids == 0 or not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum.SecrecyLevel) then return false end
  for _, id in ipairs(ids) do
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, id)
    if not ok or issecretvalue(level) or level ~= Enum.SecrecyLevel.NeverSecret then return false end
  end
  return true
end

-- Returns "error" or "note" and the text for the spell ID section, or nil.
function Display.SpellIDFilterNote(trigger)
  if not (Display.UsesSpellIDs(trigger) or Display.UsesRankSpellIDs(trigger) or Display.UsesExcludedSpellIDs(trigger)) then return end
  -- Approximate Match does not ask Blizzard for spell IDs at all.
  if Display.UsesApproximate(trigger) then return end
  local ids = Display.GetSpellIDs(trigger, true)
  if Display.UsesExcludedSpellIDs(trigger) then
    for _, value in ipairs(trigger.excludedAuraSpellIDs or {}) do
      if tonumber(value) then ids[#ids + 1] = tonumber(value) end
    end
  end
  if NeverSecret(ids) then return end
  local debuff = trigger.debuffType == "HARMFUL"
  local kind = debuff and "Debuffs" or "Buffs"
  if (debuff and friendlyUnits[trigger.unit]) or (not debuff and hostileUnits[trigger.unit]) then
    -- Point to Approximate Match wherever it can help.
    if debuff and Display.approximateUnits[trigger.unit] then
      return "error", ("Blizzard hides debuffs on %s from spell ID filters in combat. Try Approximate Match.")
        :format(Display.units[trigger.unit] or trigger.unit)
    end
    return "error", ("Blizzard hides %s on %s from spell ID filters in combat.")
      :format(kind:lower(), Display.units[trigger.unit] or trigger.unit)
  end
  if not friendlyUnits[trigger.unit] and not hostileUnits[trigger.unit] then
    return "note", ("%s selected by spell ID only match while the unit is %s.")
      :format(kind, debuff and "hostile" or "friendly")
  end
end

-- One short status line for the trigger editor: green when the selection works
-- in combat (with its one limit, if any), red with the reason when it does not.
local GREEN, ORANGE, RED = "|cff33ff99", "|cffff9933", "|cffff2020"
function Display.TriggerStatus(data, trigger)
  local problem = Display.Validate(data)
  if problem then return RED .. "Won't work:|r " .. problem end
  local severity, reason = Display.SpellIDFilterNote(trigger)
  -- Blizzard still plays Actions sounds for these spell IDs (AddAuraSound).
  if severity == "error" then return RED .. "Won't work:|r " .. reason .. " " .. ORANGE .. "Sounds in Actions still play.|r" end
  local text = GREEN .. "Works in combat.|r"
  if Display.UsesApproximate(trigger) then
    local profile = Display.ApproximateProfile(trigger)
    if not profile then
      return RED .. "Won't work:|r This debuff's duration isn't known. Add a Total Duration filter."
    end
    -- Without the gate (not an Icon, Missing, Remaining Time) only Blizzard's
    -- maximum duration applies, so shorter debuffs get through.
    local _, _, source, problem = Display.GateRange(data, trigger)
    text = text .. " " .. ORANGE .. ((source and not problem) and "Approximate match, may not be exact."
      or "Approximate match: shorter debuffs can match too.") .. "|r"
  end
  if severity == "note" then
    text = text .. " " .. ORANGE .. (trigger.debuffType == "HARMFUL" and "Hostile units only." or "Friendly units only.") .. "|r"
  end
  local lateX = Display.LateGlowSpec(data, trigger)
  if lateX then
    local total = Display.LateGlowTotal(trigger)
    if not (total and total > lateX) then text = text .. " " .. ORANGE .. "Glow starts once the aura's duration is known.|r" end
  end
  return text
end

-- Problems specific to the single-aura settings; nil when they can be drawn.
function Display.ValidateSingle(data, trigger)
  local totalProblem = Display.TotalFilterProblem(data, trigger)
  if totalProblem then return totalProblem end
  -- A "Remaining Time < X" glow condition is drawn on Icon displays only.
  if data.regionType ~= "icon" then
    for _, condition in ipairs(data.conditions or {}) do
      local check = condition.check
      if check and check.variable == "faAuraRemaining" and Display.NativeConditionKind(data, check) then
        for _, change in ipairs(condition.changes or {}) do
          if Display.IsGlowProperty(data, change.property) then return "A Remaining Time glow needs an Icon display." end
        end
      end
    end
  end
  if not Display.IsSingle(trigger) then return end
  if not Display.singleUnits[trigger.unit] then
    return "Aura(s) Missing, Always and Remaining Time watch one unit: choose Player, Target, Focus, Pet, Target of Target or Target of Focus."
  end
  local showOn = Display.ShowOn(trigger)
  local op = Display.RemainingWindow(trigger)
  if UsesRemaining(trigger) and not op then
    return "Remaining Time needs a comparison and a number of seconds of 0 or more."
  end
  if NeedsMissing(trigger) or op then
    local label = op and "Remaining Time" or ("Show On: " .. Display.showOnValues[showOn])
    if data.regionType ~= "icon" then
      return label .. " is available for Icon displays. Use Show On: Aura(s) Found for other display types."
    end
    if data.anchorFrameType == "UNITFRAME" or data.anchorFrameType == "NAMEPLATE" then
      return label .. " cannot anchor to unit frames or nameplates. Anchor the aura to the screen or a frame."
    end
  end
  -- Blizzard never matches debuffs on you or your pet by spell ID while auras
  -- are secret, so a Missing icon would show even with the debuff present.
  if NeedsMissing(trigger) and trigger.debuffType == "HARMFUL" and (trigger.unit == "player" or trigger.unit == "pet")
    and (Display.UsesSpellIDs(trigger) or Display.UsesRankSpellIDs(trigger)) and not Display.UsesApproximate(trigger) then
    return "Debuffs on you or your pet can't be found by spell ID in combat. Tick Approximate Match."
  end
  if op then
    if not Display.SupportsDurationColorCondition() then
      return "This client cannot limit auras by Remaining Time."
    end
    if HasRemainingPercentConditions(data) then
      return "With Remaining Time, countdown conditions must use Remaining Time in seconds."
    end
  end
end

-- How far the Missing clip reaches past the icon, for glows, borders and texts
-- placed outside it. The invisible group button is widened to match, so a
-- present aura still closes the clip completely.
local function MissingMargin(data, width, height)
  local margin = math.ceil(math.max(width, height)) * 2 + 64
  for _, element in ipairs(data.subRegions or {}) do
    local reach = math.max(math.abs(tonumber(element.anchorXOffset) or 0), math.abs(tonumber(element.anchorYOffset) or 0),
      math.abs(tonumber(element.text_anchorXOffset) or 0), math.abs(tonumber(element.text_anchorYOffset) or 0),
      math.abs(tonumber(element.glowXOffset) or 0), math.abs(tonumber(element.glowYOffset) or 0),
      math.abs(tonumber(element.xOffset) or 0), math.abs(tonumber(element.yOffset) or 0))
    if element.type == "subglow" then reach = reach + math.ceil(math.max(width, height) * (tonumber(element.glowScale) or 1)) end
    margin = math.max(margin, math.ceil(math.max(width, height)) + reach + 64)
  end
  return margin
end

local function MissingLayout(width, height, margin)
  return {elementWidth = width + 1 + 2 * margin, elementHeight = height}
end

-- Conditions from other triggers restore the display's own desaturation;
-- the Missing option stays on top of them.
function Display.KeepMissingDesaturated(native, data)
  if native.icon and data.blizzardAuraDisplay and data.blizzardAuraDisplay.missingDesaturate then native.icon:SetDesaturated(true) end
end

-- Draws the display's idle look on the static sample in the Missing clip.
function Display.StyleMissingIcon(native, data)
  local settings = data.blizzardAuraDisplay or {}
  if native.icon then native.icon:SetDesaturated(settings.missingDesaturate == true or data.desaturate == true) end
  -- Native condition highlights describe a present aura; none apply while it is missing.
  for _, entry in ipairs(native.conditionPreview or {}) do entry.texture:Hide() end
  if native.cooldown then native.cooldown:Hide() end
  -- Dispel indicators describe the live aura's type, which an absent aura has not.
  for index, element in ipairs(data.subRegions or {}) do
    local entry = native.sharedElements and native.sharedElements[index]
    if entry and (element.type == "subcdmdispel" or element.type == "subcdmdispelborder") then
      if entry.texture then entry.texture:Hide() end
      if entry.dispelEdges then Private.DispelTypeDisplay.Hide(entry.dispelEdges) end
    end
  end
end

local function StyleMissing(missing, region, data)
  local native = missing.native
  Display.StyleNative(native, data, region)
  native.button:ClearAllPoints()
  native.button:SetPoint("TOPLEFT", region, "TOPLEFT")
  local trigger = Display.GetTrigger(data)
  local id = Display.GetSpellIDs(trigger, false)[1]
  local info = id and C_Spell.GetSpellInfo(id)
  Display.FillSampleBindings(native.button, Display.SingleIcon(data), info and info.name or "", data, false)
  Display.StyleMissingIcon(native, data)
end

local function Warn(data, message)
  Private.AuraWarnings.UpdateWarning(data.uid, "blizzard_aura_single", message and "warning" or nil, message)
end
-- Cleared by Apply before styling; any part that fails sets it again.
Display.ClearSingleWarning = function(data) Warn(data) end

-- The Missing part: its own container, so its width depends only on presence.
local function EnsureMissing(single, region, data, trigger)
  local width, height = Display.Dimensions(data)
  local margin = MissingMargin(data, width, height)
  local filter, candidates = Display.FilterString(trigger), Display.CandidateFilters(data)
  -- A container Blizzard refused is kept aside rather than recreated on every
  -- Apply; the warning stays until the next /reload.
  if single.missingFailed then
    Warn(data, single.missingFailed)
    return
  end
  local missing = single.missing
  if not missing then
    missing = {}
    local container = CreateFrame("AuraContainer", nil, region, "CustomAuraContainerTemplate")
    container:SetEnabled(false)
    container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
    -- TOPLEFT only: Blizzard sizes the container from the group; nothing reads it.
    container:SetPoint("TOPLEFT", region, "TOPLEFT")
    local ok, err = pcall(container.AddAuraGroup, container, MISSING_GROUP, filter, {
      candidateFilters = candidates,
      maxFrameCount = 1,
      layout = MissingLayout(width, height, margin),
      initializeFrame = function(button)
        -- These buttons draw nothing; only the container's width is used.
        button:SetSize(width + 1 + 2 * margin, height)
        button:EnableMouse(false)
      end,
    })
    if not ok then
      container:Hide()
      single.missingFailed = "Blizzard could not create the Aura(s) Missing display: " .. tostring(err)
      Warn(data, single.missingFailed)
      return
    end
    -- Frames anchored to a container that owns an aura group must opt out of
    -- untrusted layout scripts (Blizzard_CustomAuraContainer). Everything inside
    -- the clip is created in place, never re-parented into it.
    local clip = CreateFrame("Frame", nil, region, "DisableUntrustedLayoutScriptsTemplate")
    clip:SetClipsChildren(true)
    clip:EnableMouse(false)
    missing.container, missing.clip = container, clip
    missing.native = Display.CreateSampleNative(clip)
    single.missing = missing
  else
    missing.container:SetAuraGroupFilterString(MISSING_GROUP, filter)
    missing.container:SetAuraGroupCandidateFilters(MISSING_GROUP, candidates)
    missing.container:SetAuraGroupLayout(MISSING_GROUP, MissingLayout(width, height, margin))
    missing.container:SetAuraGroupEnabled(MISSING_GROUP, true)
  end
  -- Absent: the container is 1 px wide and the clip spans the icon plus margin.
  -- Present: its right edge moves onto the clip's right edge, closing it.
  local clip = missing.clip
  clip:ClearAllPoints()
  clip:SetPoint("TOPLEFT", missing.container, "TOPRIGHT", -1 - margin, margin)
  clip:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", margin, -margin)
  clip:SetFrameLevel(region:GetFrameLevel() + 1)
  missing.container:SetFrameLevel(region:GetFrameLevel() + 1)
  StyleMissing(missing, region, data)
  missing.active = true
end

local function DisableMissing(single)
  local missing = single.missing
  if not missing or not missing.active then return end
  missing.active = false
  missing.container:SetEnabled(false)
  missing.container:Hide()
  pcall(missing.container.SetAuraGroupEnabled, missing.container, MISSING_GROUP, false)
  missing.clip:Hide()
  missing.boundUnit = nil
end

-- A Step colour curve over the remaining duration: the colour inside the
-- window, the same colour with alpha 0 outside it. Two points: start and edge.
local function RemainingCurve(op, x, r, g, b, a)
  local curve = C_CurveUtil.CreateColorCurve()
  curve:SetType(Enum.LuaCurveType.Step)
  local below = op == "<" or op == "<="
  local edge = (op == "<=" or op == ">") and x + REMAIN_EPS or x
  local on, off = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
  if edge > 0 then curve:AddPoint(0, below and on or off) end
  curve:AddPoint(edge, below and off or on)
  return curve
end

local function Units(value) return math.floor((tonumber(value) or 0) * TEXCOORD_UNITS + 0.5) end

-- Inline texture markup: path, height, width, offsets, texture size and crop.
-- The tint and opacity come from the duration text's colour curve.
local function TextureMarkup(texture, width, height, left, right, top, bottom)
  return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(tostring(texture), height, width,
    TEXCOORD_UNITS, TEXCOORD_UNITS, Units(left), Units(right), Units(top), Units(bottom))
end

-- One aura slot on the list's own container. It picks the first matching aura
-- by the same sort as the list, so both agree on which aura is shown. Its
-- widgets anchor inside the slot button, which is sized and placed on the
-- region at configuration time.
local function EnsureSlot(single, instance, region, key, trigger, data)
  local container = instance.container
  local filter, candidates = Display.FilterString(trigger), Display.CandidateFilters(data)
  single.slots = single.slots or {}
  local slot = single.slots[key]
  if not slot then
    slot = {}
    local ok, err = pcall(container.AddAuraSlot, container, key, filter, {
      candidateFilters = candidates,
      initializeFrame = function(button)
        -- Runs inside AddAuraSlot, before Blizzard restricts the button.
        slot.button = button
        button:EnableMouse(false)
        button:SetAllPoints(region)
      end,
    })
    if not ok or not slot.button then
      Warn(data, "Blizzard could not create the Remaining Time display: " .. tostring(err))
      return
    end
    single.slots[key] = slot
  end
  -- Reconfigure disabled, then enable with the current filters.
  container:SetAuraSlotEnabled(key, false)
  local width, height = Display.Dimensions(data)
  slot.button:ClearAllPoints()
  slot.button:SetSize(width, height)
  slot.button:SetPoint("TOPLEFT", region, "TOPLEFT")
  container:SetAuraSlotFilterString(key, filter)
  container:SetAuraSlotCandidateFilters(key, candidates)
  container:SetAuraSlotSortMethod(key, AuraContainerSortMethod[trigger.sortMethod or "Default"],
    trigger.sortReverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal)
  slot.used = true
  return slot
end

local function FirstElement(data, matches)
  for index, element in ipairs(data.subRegions or {}) do
    if not Display.IsDetachedElement(data, element) and matches(element) then return element, index end
  end
end

-- Remaining Time: the list keeps drawing the aura (its countdown and glow are
-- limited to the range by Blizzard, see StyleRemainingList); this slot adds the
-- display's icon as inline artwork whose opacity follows the same range.
local function EnsureRemaining(single, instance, region, data, trigger, op, x)
  local icon = EnsureSlot(single, instance, region, SLOT_ICON, trigger, data)
  if not icon then return false end
  local width, height = Display.Dimensions(data)
  local color = data.color or {1, 1, 1, 1}
  local left, right, top, bottom = Display.IconTexCoords(data)
  -- Created at configuration time on the slot button.
  icon.text = icon.text or icon.button:CreateFontString(nil, "ARTWORK")
  icon.text:SetWordWrap(false)
  icon.text:SetFont(STANDARD_TEXT_FONT, 12, "")
  icon.text:ClearAllPoints()
  icon.text:SetPoint("CENTER", icon.button, "CENTER")
  icon.button:ClearDurationText()
  -- A refused binding would leave the display empty: report it on the aura.
  local okIcon, iconErr = pcall(icon.button.SetDurationText, icon.button, icon.text, {
    textFormat = {formatString = TextureMarkup(Display.SingleIcon(data), width, height, left, right, top, bottom), components = {}},
    textColor = {curve = RemainingCurve(op, x, color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1),
      property = Enum.DurationTextBindingProperty.RemainingDuration},
  })
  if not okIcon then
    Warn(data, "Blizzard refused the Remaining Time icon: " .. tostring(iconErr))
    return false
  end
  icon.text:Show()
  instance.container:SetAuraSlotEnabled(SLOT_ICON, true)
  return true
end

---------------------------------------------------------------------------- glow for the last seconds
-- A glow limited to a remaining-time range. Each list button carries an
-- invisible StatusBar that Blizzard fills by remaining time. With the aura's
-- total duration known, the bar is sized K px per second and placed so its fill
-- edge passes a fixed point when X seconds are left; a clip between the fill
-- edge and that point opens on the chosen side of X. The glow inside is the
-- display's own Glow element.
local LATE_K, LATE_MAX_WIDTH = 2000, 200000
local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Returns x (seconds), the glow element, its index, and whether the glow shows
-- above x (Remaining Time > / >=) instead of below it: Remaining Time with a
-- Glow turned on, or a "Remaining Time < X" condition that turns a Glow on.
function Display.LateGlowSpec(data, trigger)
  if data.regionType ~= "icon" then return end
  local op, x = Display.RemainingWindow(trigger)
  if op then
    local element, index = FirstElement(data, function(element) return element.type == "subglow" and element.glow end)
    if not element then return end
    local edge = (op == "<=" or op == ">") and x + REMAIN_EPS or x
    return edge, element, index, op == ">" or op == ">="
  end
  for _, condition in ipairs(data.conditions or {}) do
    local check = condition.check
    if not condition.linked and check and check.variable == "faAuraRemaining" and check.op == "<"
      and Display.NativeConditionKind(data, check) and tonumber(check.value) and tonumber(check.value) > 0 then
      for _, change in ipairs(condition.changes or {}) do
        if change.value == true and Display.IsGlowProperty(data, change.property) then
          local index = tonumber(change.property:match("^sub%.(%d+)%."))
          return tonumber(check.value), data.subRegions[index], index, false
        end
      end
    end
  end
end

-- Total durations seen while auras were readable (out of combat), per spell
-- ID, saved per account. Classic ranks each have their own ID.
local watchedIDs = {}
local waitingRegions = setmetatable({}, {__mode = "k"})
local function SeenDurations()
  if type(ForeverAurasSaved) ~= "table" then return end
  ForeverAurasSaved.auraDurations = ForeverAurasSaved.auraDurations or {}
  return ForeverAurasSaved.auraDurations
end

-- A spell's description and tooltip ("Lasts for 2 min.") give its duration
-- without the aura ever being seen. Cached per spell ID; spell data that has
-- not loaded is requested, and SPELL_DATA_LOAD_RESULT tries again.
local describedDurations = {}
local pendingSpellData = {}
local loadAttempted = {}
-- The patterns come from the client's own duration strings ("%d sec",
-- "%d Sek.", "%d мин.", "%d秒"), so every language works. The longest duration
-- in the text wins; decimal commas are accepted.
local NUMBER = "(%d+[%.,]?%d*)"
local DURATION_GLOBALS = {
  {1, {"INT_SPELL_DURATION_SEC", "SPELL_DURATION_SEC", "SECONDS_ABBR", "SECOND_ONELETTER_ABBR", "D_SECONDS"}},
  {60, {"INT_SPELL_DURATION_MIN", "SPELL_DURATION_MIN", "MINUTES_ABBR", "MINUTE_ONELETTER_ABBR", "D_MINUTES"}},
  {3600, {"INT_SPELL_DURATION_HOURS", "SPELL_DURATION_HOURS", "HOURS_ABBR", "HOUR_ONELETTER_ABBR", "D_HOURS"}},
}
-- English fallback, used alongside the client's strings.
local ENGLISH_UNITS = {{1, "%d sec"}, {1, "%d secs"}, {1, "%d second"}, {1, "%d seconds"},
  {60, "%d min"}, {60, "%d mins"}, {60, "%d minute"}, {60, "%d minutes"},
  {3600, "%d hour"}, {3600, "%d hours"}, {3600, "%d hr"}, {3600, "%d hrs"}}
-- Turns one format string into a Lua pattern with the number captured.
local function DurationPattern(format)
  local forms = {}
  -- "|4singular:plural;" grammar: keep every form.
  local choice = format:match("|4([^;]*);")
  if choice then
    for form in (choice .. ":"):gmatch("([^:]*):") do forms[#forms + 1] = (format:gsub("|4[^;]*;", form, 1)) end
  else
    forms[1] = format
  end
  local patterns = {}
  for _, form in ipairs(forms) do
    -- Drop colour codes, then split around the one number placeholder.
    form = form:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    local before, after = form:match("^(.-)%%[%d%$]*[%.%d]*[dfsi](.*)$")
    if before then
      local function Escape(text)
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        -- Spaces (also non-breaking ones) may vary; everything else is literal.
        return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%s+", "%%s*"):gsub("\194\160", "%%s*"))
      end
      before, after = Escape(before), Escape(after)
      -- A unit is needed on at least one side, or every number would match.
      if before ~= "" or after ~= "" then
        -- Latin unit abbreviations must end at a word boundary: "min" in
        -- "minimum" and "sec" in "secondary" are not durations.
        local boundary = after:match("[a-z]$") and "%f[%A]" or ""
        patterns[#patterns + 1] = before .. "%s*" .. NUMBER .. "%s*" .. after .. boundary
      end
    end
  end
  return patterns
end
local durationPatterns
local function DurationPatterns()
  if durationPatterns then return durationPatterns end
  durationPatterns = {}
  local seen = {}
  local function Add(seconds, format)
    if type(format) ~= "string" then return end
    for _, pattern in ipairs(DurationPattern(format)) do
      if not seen[pattern] then
        seen[pattern] = true
        durationPatterns[#durationPatterns + 1] = {pattern, seconds}
      end
    end
  end
  for _, group in ipairs(DURATION_GLOBALS) do
    for _, name in ipairs(group[2]) do Add(group[1], _G[name]) end
  end
  for _, entry in ipairs(ENGLISH_UNITS) do Add(entry[1], entry[2]) end
  return durationPatterns
end
local function SpellText(id)
  local parts = {}
  local ok, text = pcall(C_Spell.GetSpellDescription, id)
  -- The description is what says the duration; a tooltip with only its title
  -- means the spell's text has not loaded yet.
  local loaded = ok and type(text) == "string" and not issecretvalue(text) and text ~= ""
  if loaded then parts[#parts + 1] = text end
  if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
    local okTip, info = pcall(C_TooltipInfo.GetSpellByID, id)
    for _, line in ipairs(okTip and type(info) == "table" and info.lines or {}) do
      -- A tooltip can have right text with no left text; ipairs on the two
      -- values would stop at that nil and silently skip the duration.
      for _, key in ipairs({"leftText", "rightText"}) do
        local side = line[key]
        if not issecretvalue(side) and type(side) == "string" then parts[#parts + 1] = side end
      end
    end
  end
  return table.concat(parts, "\n"):lower(), loaded
end
local function DescribedDuration(id)
  if describedDurations[id] ~= nil then return describedDurations[id] or nil end
  -- Requested and still loading: nothing new to read yet.
  if pendingSpellData[id] then return end
  local text, loaded = SpellText(id)
  if not loaded and not loadAttempted[id] and C_Spell.RequestLoadSpellData then
    -- Not loaded yet: ask once; the load event clears the cache entry.
    pendingSpellData[id], loadAttempted[id] = true, true
    local ok = pcall(C_Spell.RequestLoadSpellData, id)
    if not ok then pendingSpellData[id] = nil end
    loaded = not ok
  elseif not loaded then
    -- Asked and answered: whatever is there is final.
    loaded = loadAttempted[id] == true
  end
  local best
  for _, entry in ipairs(DurationPatterns()) do
    for value in text:gmatch(entry[1]) do
      local seconds = tonumber((value:gsub(",", ".")))
      seconds = seconds and seconds * entry[2]
      if seconds and seconds > (best or 0) then best = seconds end
    end
  end
  -- "No duration" is remembered only once loading has been tried, so a
  -- half-loaded tooltip is read again after the load event.
  if best or loaded then describedDurations[id] = best or false end
  return best
end

-- The longest known total duration of the selected spells, and its source.
function Display.LateGlowTotal(trigger)
  -- A duration entered in the trigger wins over anything learned: Total
  -- Duration "=", else the glow's own Aura Duration.
  local op, total = Display.TotalFilter(trigger)
  if op == "=" then return total, "manual" end
  local manual = tonumber(trigger.secretDuration)
  if manual and manual > 0 and manual < math.huge then return manual, "manual" end
  local ids = Display.GetSpellIDs(trigger, true)
  local seen, best = SeenDurations(), nil
  for _, id in ipairs(ids) do
    local seconds = seen and tonumber(seen[id])
    if seconds and seconds > (best or 0) then best = seconds end
  end
  if best then return best, "seen" end
  for _, id in ipairs(ids) do
    local seconds = DescribedDuration(id)
    if seconds and seconds > (best or 0) then best = seconds end
  end
  if best then return best, "described" end
end

local function GlowMargin(width, height, element)
  local offset = math.max(math.abs(tonumber(element.glowXOffset) or 0), math.abs(tonumber(element.glowYOffset) or 0))
  return math.ceil(math.max(width, height) * 0.5 * (tonumber(element.glowScale) or 1)) + offset + 4
end

-- Called by StyleAppearance for each Glow element of a live list button.
-- nil: an ordinary glow. false: a timed glow whose total duration is not known
-- yet (hidden). A frame: the holder inside the clip that the glow belongs in.
function Display.TimedGlowHolder(native, data, index, frame)
  if native.preview then return end
  local trigger = Display.GetTrigger(data)
  local x, element, glowIndex, above = Display.LateGlowSpec(data, trigger)
  if not x or glowIndex ~= index then return end
  local total = Display.LateGlowTotal(trigger)
  if not total or total <= x then return false end
  local late = native.lateGlow
  if not late then
    late = {}
    late.bar = CreateFrame("StatusBar", nil, native.button)
    late.bar:SetStatusBarTexture(WHITE)
    late.bar:SetStatusBarColor(0, 0, 0, 0)
    -- Invisible: only its fill edge serves as an anchor.
    late.bar:SetAlpha(0)
    -- Inside the Total Duration gate clip, so a rejected aura never glows.
    late.clip = CreateFrame("Frame", nil, native.gateClip or native.button, "DisableUntrustedLayoutScriptsTemplate")
    late.clip:SetClipsChildren(true)
    late.holder = CreateFrame("Frame", nil, late.clip)
    late.holder:SetAllPoints(native.button)
    native.lateGlow = late
  end
  local width, height = Display.Dimensions(data)
  local margin = GlowMargin(width, height, element)
  local k = math.min(LATE_K, LATE_MAX_WIDTH / total)
  late.bar:ClearAllPoints()
  late.bar:SetSize(total * k, height + 2 * margin)
  late.clip:ClearAllPoints()
  if above then
    -- Open from the icon's left edge while more than x seconds are left.
    late.bar:SetPoint("LEFT", native.button, "LEFT", -margin - x * k, 0)
    late.clip:SetPoint("TOPLEFT", late.bar, "TOPLEFT", x * k, 0)
    late.clip:SetPoint("BOTTOMRIGHT", late.bar:GetStatusBarTexture(), "BOTTOMRIGHT")
  else
    -- Open towards the icon's right edge once fewer than x seconds are left.
    late.bar:SetPoint("LEFT", native.button, "RIGHT", margin - x * k, 0)
    late.clip:SetPoint("TOPLEFT", late.bar:GetStatusBarTexture(), "TOPRIGHT")
    late.clip:SetPoint("BOTTOMRIGHT", late.bar, "BOTTOMLEFT", x * k, 0)
  end
  native.button:SetDurationBar(late.bar, {direction = Enum.StatusBarTimerDirection.RemainingTime})
  late.clip:SetFrameLevel(frame:GetFrameLevel() + 1)
  late.clip:Show()
  return late.holder
end

-- Remaining Time on a live list button: the icon, swipe, stacks, name, border
-- and other elements would show for the whole aura, so only the countdown and
-- glows stay; the icon is drawn by the Remaining Time slot instead.
function Display.StyleRemainingList(native, data)
  if native.preview then return end
  local limited = Display.RemainingWindow(Display.GetTrigger(data)) ~= nil
  if native.conditionOverlay then native.conditionOverlay:SetShown(not limited) end
  if not limited then return end
  native.button:ClearIcon(); native.icon:Hide()
  native.button:ClearDurationCooldown(); native.cooldown:Hide()
  native.button:ClearApplicationCount(); native.button:ClearSpellName()
  native.border:Hide()
  for index, element in ipairs(data.subRegions or {}) do
    local keep = element.type == "subglow" or element.type == "subbackground"
      or (element.type == "subtext" and Display.TextKind(element.text_text) == "duration")
    local frame = native.elementFrames and native.elementFrames["shared" .. index]
    if frame and not keep then frame:Hide() end
  end
end

---------------------------------------------------------------------------- approximate match
-- Blizzard never picks debuffs on friendly units by spell ID while auras are
-- secret. Its containers do filter by an aura's properties, so Approximate
-- Match asks for a debuff with the selected one's properties instead:
--   * its duration: a Total Duration "=" filter, else learned, else read from
--     the spell's description and tooltip, so it works before any sighting;
--     on Icons the Total Duration gate then keeps only that exact duration;
--   * its dispel type and flags, once it has been seen while auras are
--     readable (out of combat, including when combat ends with it still up).
-- A different debuff with the same properties matches too.
local FINGERPRINT_FLAGS = {"canApplyAura", "isStealable", "isBossAura", "isFromPlayerOrPlayerPet", "nameplateShowAll", "nameplateShowPersonal"}
local watchedProfiles = {}
local learningRegions = setmetatable({}, {__mode = "k"})

local function RebuildLearningWatches()
  wipe(watchedProfiles); wipe(watchedIDs)
  for _, entry in pairs(learningRegions) do
    for _, id in ipairs(entry.ids) do
      if entry.approximate then watchedProfiles[id] = true end
      if entry.glow then watchedIDs[id] = true end
    end
  end
end

function Display.ReleaseAuraLearning(region)
  waitingRegions[region] = nil
  if learningRegions[region] then
    learningRegions[region] = nil
    RebuildLearningWatches()
  end
end

function Display.WatchAuraLearning(region, data, trigger, glow)
  local approximate = Display.UsesApproximate(trigger)
  if not approximate and not glow then Display.ReleaseAuraLearning(region); return end
  local ids = Display.GetSpellIDs(trigger, true)
  local key = table.concat(ids, ",") .. tostring(approximate) .. tostring(not not glow)
  if not learningRegions[region] or learningRegions[region].key ~= key then
    learningRegions[region] = {ids = ids, key = key, approximate = approximate, glow = glow}
    RebuildLearningWatches()
  end
  -- Keep learned displays subscribed so later readable changes reach them too.
  waitingRegions[region] = data
end

local function Profiles()
  if type(ForeverAurasSaved) ~= "table" then return end
  ForeverAurasSaved.auraProfiles = ForeverAurasSaved.auraProfiles or {}
  return ForeverAurasSaved.auraProfiles
end

-- Friendly units, where Blizzard refuses spell ID filters for debuffs.
Display.approximateUnits = {player = true, pet = true, group = true, party = true, raid = true}

function Display.UsesApproximate(trigger)
  return type(trigger) == "table" and trigger.secretApproximate == true and Display.approximateUnits[trigger.unit]
    and trigger.debuffType == "HARMFUL" and (Display.UsesSpellIDs(trigger) or Display.UsesRankSpellIDs(trigger)) or false
end

-- One profile for the selected ranks: the longest duration, and the dispel
-- type and flags where every seen rank agrees. Second result: "seen" when
-- learned from a sighting, "manual" when a Total Duration filter is set,
-- "duration" when only the described duration is known.
function Display.ApproximateProfile(trigger)
  local all = Profiles()
  if not all then return end
  local merged
  for _, id in ipairs(Display.GetSpellIDs(trigger, true)) do
    local profile = all[id]
    if type(profile) == "table" then
      if not merged then
        merged = CopyTable(profile)
      else
        merged.duration = math.max(merged.duration or 0, profile.duration or 0)
        if merged.dispel ~= profile.dispel then merged.dispel = nil end
        for _, key in ipairs(FINGERPRINT_FLAGS) do if merged[key] ~= profile[key] then merged[key] = nil end end
      end
    end
  end
  -- A Total Duration filter is followed as entered: it replaces every learned
  -- or described duration ("=" becomes the duration; "<=" and ">=" are applied
  -- by the filter itself, see CandidateFilters and GateRange). A learned dispel
  -- type and flags still apply.
  local op, manual = Display.TotalFilter(trigger)
  if op then
    merged = merged or {}
    merged.duration = op == "=" and manual or nil
    return merged, "manual"
  end
  if merged then return merged, "seen" end
  -- Not seen yet: the spell's description and tooltip give the duration.
  local best
  for _, id in ipairs(Display.GetSpellIDs(trigger, true)) do
    local seconds = DescribedDuration(id)
    if seconds and seconds > (best or 0) then best = seconds end
  end
  if best then return {duration = best}, "duration" end
end

function Display.ApproximateFilters(trigger, filters)
  if not Display.UsesApproximate(trigger) then return filters end
  local profile = Display.ApproximateProfile(trigger)
  -- Nothing learned yet: match nothing rather than every debuff on you.
  if not profile then filters.includeSpellIDs = {}; return filters end
  filters.includeSpellIDs, filters.excludeSpellIDs = nil, nil
  -- Durations carry a few ms of noise; permanent debuffs (0) get no limit.
  if (profile.duration or 0) > 0 then
    filters.maxDuration = math.min(filters.maxDuration or math.huge, profile.duration + 0.5)
  end
  if type(profile.dispel) == "string" then filters.includeDispelTypes = {[profile.dispel] = true} end
  for _, key in ipairs(FINGERPRINT_FLAGS) do
    if filters[key] == nil and type(profile[key]) == "boolean" then filters[key] = profile[key] end
  end
  return filters
end

-- Friendly unit tokens whose debuffs teach Approximate Match.
local function Friendly(token)
  return token == "player" or token == "pet" or (type(token) == "string" and (token:match("^party%d$") or token:match("^raid%d+$"))) ~= nil
end

-- Learns total durations and debuff properties of the selected spell IDs while
-- auras are readable: on aura changes out of combat and when combat ends.
local BOTH_FILTERS, DEBUFF_FILTER = {"HELPFUL", "HARMFUL"}, {"HARMFUL"}
local FIXED_UNITS = {"player", "target", "focus", "pet"}
local learnEvents = CreateFrame("Frame")
learnEvents:RegisterEvent("UNIT_AURA")
learnEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
learnEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
learnEvents:RegisterEvent("SPELL_DATA_LOAD_RESULT")
learnEvents:RegisterEvent("SPELLS_CHANGED")
-- Applies again every display that waits for a duration or profile.
local reapplyAfterCombat = {}
local function ReapplyWaiting(changed)
  local refresh = {}
  -- Collect affected displays first; applying one can change its subscriptions.
  for region, data in pairs(waitingRegions) do
    local entry = learningRegions[region]
    for _, id in ipairs(entry and entry.ids or {}) do
      if not changed or changed[id] then refresh[region] = data; break end
    end
  end
  for region, data in pairs(refresh) do
    if ForeverAuras.GetData(data.id) == data then Display.Apply(region, data)
    else Display.ReleaseAuraLearning(region) end
  end
end
learnEvents:SetScript("OnEvent", function(_, event, unit, updateInfo)
  if event == "SPELLS_CHANGED" then
    wipe(loadAttempted); wipe(describedDurations)
    if InCombatLockdown() then
      for id in pairs(watchedProfiles) do reapplyAfterCombat[id] = true end
      for id in pairs(watchedIDs) do reapplyAfterCombat[id] = true end
    else ReapplyWaiting() end
    return
  end
  -- A requested spell's description is now available (unit is the spell ID).
  if event == "SPELL_DATA_LOAD_RESULT" then
    if pendingSpellData[unit] then
      pendingSpellData[unit], describedDurations[unit] = nil, nil
      loadAttempted[unit] = true
      -- Displays are only rebuilt out of combat; catch up when it ends.
      if InCombatLockdown() then reapplyAfterCombat[unit] = true else ReapplyWaiting({[unit] = true}) end
    end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" and next(reapplyAfterCombat) then
    local changed = reapplyAfterCombat
    reapplyAfterCombat = {}
    ReapplyWaiting(changed)
  end
  if (not next(watchedIDs) and not next(watchedProfiles)) or InCombatLockdown()
    or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then return end
  local units
  if event == "UNIT_AURA" then
    if unit ~= "target" and unit ~= "focus" and not Friendly(unit) then return end
    -- Removals teach nothing; only new or changed auras are read.
    if type(updateInfo) == "table" and not updateInfo.isFullUpdate and not updateInfo.addedAuras
      and not updateInfo.updatedAuraInstanceIDs then return end
    units = {unit}
  elseif event == "PLAYER_TARGET_CHANGED" then
    units = {"target"}
  else
    -- Combat ended: auras still up become readable.
    units = FIXED_UNITS
    if next(watchedProfiles) then
      units = {unpack(FIXED_UNITS)}
      for i = 1, (IsInRaid() and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
      for i = 1, (not IsInRaid() and GetNumSubgroupMembers() or 0) do units[#units + 1] = "party" .. i end
    end
  end
  local seen, profiles = SeenDurations(), Profiles()
  if not seen or not profiles then return end
  local changed = {}
  -- Buff durations are only needed for timed glows (watchedIDs).
  local filters = next(watchedIDs) and BOTH_FILTERS or DEBUFF_FILTER
  for _, token in ipairs(units) do
    for _, filter in ipairs(filters) do
      for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, token, i, filter)
        if not ok or type(aura) ~= "table" then break end
        local id, duration = aura.spellId, aura.duration
        if not issecretvalue(id) and not issecretvalue(duration) and watchedIDs[id] and type(duration) == "number" and duration > 0 then
          -- Durations carry a few ms of noise; keep tenths.
          local tenths = math.floor(duration * 10 + 0.5) / 10
          if seen[id] ~= tenths then seen[id] = tenths; changed[id] = true end
        end
        -- Approximate Match profiles, for the selected spell IDs only. A debuff
        -- on an enemy teaches its duration and dispel type; the flags depend on
        -- who it is on, so they come only from friendly units, and a friendly
        -- profile is never replaced by an enemy sighting.
        if type(id) == "number" and not issecretvalue(id) and watchedProfiles[id] and filter == "HARMFUL"
          and type(duration) == "number" and not issecretvalue(duration) then
          local friendly = Friendly(token)
          local old = profiles[id]
          if friendly or not (type(old) == "table" and old.friendly) then
            local profile = {duration = math.floor(duration * 10 + 0.5) / 10, friendly = friendly or nil}
            local dispel = aura.dispelName
            if type(dispel) == "string" and not issecretvalue(dispel) then profile.dispel = dispel end
            if friendly then
              for _, key in ipairs(FINGERPRINT_FLAGS) do
                local value = aura[key]
                if type(value) == "boolean" and not issecretvalue(value) then profile[key] = value end
              end
            end
            local same = type(old) == "table"
            if same then
              for key, value in pairs(profile) do if old[key] ~= value then same = false end end
              for key in pairs(old) do if profile[key] == nil then same = false end end
            end
            if not same then profiles[id] = profile; changed[id] = true end
          end
        end
      end
    end
  end
  if next(changed) then ReapplyWaiting(changed) end
end)

---------------------------------------------------------------------------- total duration
-- "<=" is Blizzard's own maximum-duration filter. "=" and ">=" need a minimum,
-- which Blizzard does not have, so each list button gets a hidden "gate" text
-- formatted from the aura's total duration: a run of wide characters when it
-- is in range, empty otherwise. A clip spans exactly that text, and everything
-- the button draws sits inside the clip, so a wrong aura draws nothing.
-- Approximate Match uses the same gate with the spell's known duration.
-- The gate takes the button's one duration text, so %p is shown by the
-- swipe's countdown numbers. Candidates stack on one spot (Layout),
-- so rejected auras leave no gaps.
local GATE_TOLERANCE = 0.5
Display.totalOperators = {["="] = "=", ["<="] = "<=", [">="] = ">="}

-- The Total Duration filter: operator and seconds, or nil when off or invalid.
function Display.TotalFilter(trigger)
  if type(trigger) ~= "table" or not trigger.secretUseTotal then return end
  local op, x = trigger.secretTotalOperator or "=", tonumber(trigger.secretTotal)
  if not Display.totalOperators[op] or not x or x <= 0 or x ~= x or x == math.huge then return end
  return op, x
end

-- Why the gate cannot be drawn for this display, or nil.
local function GateProblem(data, trigger)
  if data.regionType ~= "icon" then
    return "Total Duration = and >= only work on Icon displays. Use <= for bars, textures and text."
  end
  if data.anchorFrameType == "UNITFRAME" or data.anchorFrameType == "NAMEPLATE" then
    return "Total Duration = and >= can't anchor to unit frames or nameplates."
  end
  if Display.IsSingle(trigger) then
    return "Total Duration = and >= only work with Show On: Aura(s) Found, without Remaining Time."
  end
  if not (Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.TotalDuration ~= nil
    and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Display.SupportsDurationColorCondition()) then
    return "This client can't check Total Duration = or >=."
  end
end

-- The total-duration range the gate should let through: lower, upper (nil for
-- no upper limit), where it comes from ("filter" or "approximate"), and why it
-- cannot be drawn (nil when it can).
function Display.GateRange(data, trigger)
  trigger = trigger or Display.GetTrigger(data)
  if not trigger then return end
  local op, x = Display.TotalFilter(trigger)
  local lower, upper, source
  if op == "=" then
    lower, upper, source = x - GATE_TOLERANCE, x + GATE_TOLERANCE, "filter"
  elseif op == ">=" then
    lower, source = x - GATE_TOLERANCE, "filter"
  elseif Display.UsesApproximate(trigger) then
    local profile = Display.ApproximateProfile(trigger)
    local duration = profile and tonumber(profile.duration)
    if duration and duration > 0 then lower, upper, source = duration - GATE_TOLERANCE, duration + GATE_TOLERANCE, "approximate" end
  end
  if not source then return end
  return math.max(0.001, lower), upper, source, GateProblem(data, trigger)
end

-- lower, upper when the gate is drawn; nil otherwise.
function Display.DurationGate(data, trigger)
  local lower, upper, _, problem = Display.GateRange(data, trigger)
  if lower and not problem then return lower, upper end
end

-- A red status for a Total Duration filter that cannot be drawn.
function Display.TotalFilterProblem(data, trigger)
  local _, _, source, problem = Display.GateRange(data, trigger)
  if source == "filter" and problem then return problem end
end

-- How far the gate clip reaches past the icon: room for the border, glows and
-- outer texts. Kept modest because the gate text's font size grows with it.
local function GateMargin(width, height)
  return math.ceil(math.max(width, height) * 0.5) + 8
end

-- Shared across buttons: one transparent colour curve, and one formatter per
-- range and fill text.
local invisibleCurve
local gateFormatters = {}
local function GateFormatter(lower, upper, fill)
  local key = table.concat({lower, tostring(upper), fill}, "|")
  if gateFormatters[key] then return gateFormatters[key] end
  local points = {{threshold = 0, format = ""}, {threshold = lower, format = fill}}
  if upper then points[3] = {threshold = upper + REMAIN_EPS, format = ""} end
  local formatter = C_StringUtil.CreateNumericRuleFormatter()
  local ok, err = pcall(formatter.SetBreakpoints, formatter, points)
  if not ok then return nil, err end
  gateFormatters[key] = formatter
  return formatter
end

-- Called at the end of StyleAppearance for every live list button.
function Display.StyleDurationGate(native, data)
  if native.preview or not native.gateClip then return end
  local clip, gate, button = native.gateClip, native.gateText, native.button
  local trigger = Display.GetTrigger(data)
  local width, height = Display.Dimensions(data)
  local lower, upper = Display.DurationGate(data, trigger)
  if not lower then
    -- No gate: the frame does not clip at all, as before the gate existed.
    clip:SetClipsChildren(false)
    clip:ClearAllPoints()
    clip:SetAllPoints(button)
    gate:Hide()
    native.cooldown:SetMinimumCountdownDuration(0)
    native.cooldown:SetCountdownFormatter(nil)
    return
  end
  local margin = GateMargin(width, height)
  -- The gate text covers the whole clip area: its font size gives the height
  -- and a run of wide characters the width. An empty text has no size, so
  -- the clip closes to nothing.
  local size = math.min(250, math.ceil(math.max(width, height) + 2 * margin))
  local fill = string.rep("W", math.ceil((width + 2 * margin) / (size / 2)) + 1)
  local formatter, err = GateFormatter(lower, upper, fill)
  local ok = formatter ~= nil
  if ok then
    gate:SetFont(STANDARD_TEXT_FONT, size, "")
    gate:SetWordWrap(false)
    -- No fixed width: the text's own width follows what the formatter writes.
    gate:SetWidth(0)
    gate:ClearAllPoints()
    gate:SetPoint("CENTER", button, "CENTER")
    -- Always transparent: only its size matters.
    if not invisibleCurve then
      invisibleCurve = C_CurveUtil.CreateColorCurve()
      invisibleCurve:SetType(Enum.LuaCurveType.Step)
      invisibleCurve:AddPoint(0, CreateColor(0, 0, 0, 0))
    end
    ok, err = pcall(button.SetDurationText, button, gate, {
      textFormat = {formatString = "{}", components = {{property = Enum.DurationTextBindingProperty.TotalDuration, formatter = formatter}}},
      textColor = {curve = invisibleCurve, property = Enum.DurationTextBindingProperty.TotalDuration},
    })
  end
  if not ok then
    Warn(data, "Blizzard refused the Total Duration check: " .. tostring(err))
    return
  end
  gate:Show()
  clip:SetClipsChildren(true)
  clip:ClearAllPoints()
  clip:SetPoint("TOPLEFT", gate, "TOPLEFT")
  clip:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT")
  -- The %p text lost its binding to the gate; the swipe's numbers replace it.
  local countdown
  for index, element in ipairs(data.subRegions or {}) do
    if element.type == "subtext" and Display.TextKind(element.text_text) == "duration" then
      local entry = native.sharedElements and native.sharedElements[index]
      if entry and entry.text then entry.text:Hide() end
      if element.text_visible ~= false and not countdown then countdown = element end
    end
  end
  if countdown then
    local cooldown = native.cooldown
    cooldown:Show()
    -- The numbers without a swipe when the icon's cooldown is turned off.
    if data.cooldown == false then
      cooldown:SetDrawSwipe(false)
      cooldown:SetDrawEdge(false)
    end
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetUseAuraDisplayTime(true)
    -- Second guard: no numbers for auras shorter than the range.
    cooldown:SetMinimumCountdownDuration(lower * 1000)
    -- The numbers take the %p text's font, colour, position and time format.
    local numbers = cooldown:GetCountdownFontString()
    if numbers then Display.StyleText(numbers, native, Display.TextSettings(countdown), "text", 18, "CENTER", 0, 0) end
    local prefix = "text_text_format_p_time_"
    local format = countdown[prefix .. "format"]
    cooldown:SetCountdownFormatter(nil)
    if format ~= nil and format ~= -1 and Private.GetDurationTextFormatter then
      pcall(cooldown.SetCountdownFormatter, cooldown, Private.GetDurationTextFormatter(countdown[prefix .. "legacy_floor"] and 0 or 99,
        countdown[prefix .. "dynamic_threshold"] or 3, countdown[prefix .. "precision"] or 1, format == -2))
    end
    button:SetDurationCooldown(cooldown)
  end
end

-- Maximum Duration becomes Total Duration "<=". Pre-release test builds had a
-- Match Exact Duration option; its duration becomes Total Duration "=".
function Display.MigrateTotal(trigger)
  if trigger.secretUseTotal == nil then
    if trigger.secretExactDuration and tonumber(trigger.secretDuration) then
      trigger.secretUseTotal, trigger.secretTotalOperator, trigger.secretTotal = true, "=", tostring(trigger.secretDuration)
      trigger.secretDuration = nil
    elseif type(trigger.maxDuration) == "number" then
      trigger.secretUseTotal, trigger.secretTotalOperator, trigger.secretTotal = true, "<=", tostring(trigger.maxDuration)
    end
  end
  trigger.maxDuration = nil
  trigger.secretExactDuration = nil
end

-- Called from Display.Apply for every instance at safe time, after the list is
-- configured and before units are bound. The single-aura parts use the first
-- instance only; containers left from an earlier multi-unit list are retired.
function Display.ConfigureSingle(instance, region, data, index)
  local trigger = Display.GetTrigger(data)
  local valid = index == 1 and Display.ValidateSingle(data, trigger) == nil
  local isSingle = valid and Display.IsSingle(trigger)
  if valid then
    local lateX = Display.LateGlowSpec(data, trigger)
    Display.WatchAuraLearning(region, data, trigger, lateX)
  elseif index == 1 then
    Display.ReleaseAuraLearning(region)
  end
  if not isSingle and not instance.single then return end
  local single = instance.single or {}
  instance.single = single
  for _, slot in pairs(single.slots or {}) do slot.used = false end
  if isSingle and NeedsMissing(trigger) then EnsureMissing(single, region, data, trigger) else DisableMissing(single) end
  local op, x = Display.RemainingWindow(trigger)
  if isSingle and op then EnsureRemaining(single, instance, region, data, trigger, op, x) end
  -- Parts no longer configured stop matching auras.
  for key, slot in pairs(single.slots or {}) do
    if not slot.used then pcall(instance.container.SetAuraSlotEnabled, instance.container, key, false) end
  end
  -- Aura(s) Missing alone draws no live aura: the list is switched off and its
  -- buttons made invisible. Otherwise the list draws (Remaining Time styles it).
  local listDraws = not isSingle or Display.ShowOn(trigger) ~= "showOnMissing"
  single.listDisabled = not listDraws
  instance.container:SetAuraGroupEnabled("Auras", listDraws)
  for _, button in ipairs(instance.buttons or {}) do button.button:SetAlpha(listDraws and 1 or 0) end
end

-- Mirrors the aura list container's unit binding and visibility; unit = nil
-- with shown = false hides the Missing part.
function Display.RefreshSingle(instance, unit, shown)
  local single = instance.single
  -- Enabling the container must not bring back a list the settings turned off.
  if shown and single and single.listDisabled then
    pcall(instance.container.SetAuraGroupEnabled, instance.container, "Auras", false)
  end
  local missing = instance.single and instance.single.missing
  if not missing or not missing.active then return end
  local container = missing.container
  -- Hiding keeps the bound unit, like the aura list container, so showing the
  -- same unit again does not rebind it.
  if unit and missing.boundUnit ~= unit then
    container:SetEnabled(false)
    container:SetUnit(unit)
    missing.boundUnit = unit
  end
  shown = shown and unit ~= nil
  container:SetShown(shown)
  container:SetEnabled(shown)
  -- A disabled container keeps its last width; the clip must not show then.
  missing.clip:SetShown(shown)
  -- No unit (no target, focus or pet): nothing is missing. The display itself
  -- stays shown, since its frames may be protected in combat; only the Missing
  -- look fades, through its alpha.
  missing.clip:SetAlpha(Display.SingleUnitExists({unit = unit}) and 1 or 0)
  if shown then container:UpdateAllAuras() end
end
