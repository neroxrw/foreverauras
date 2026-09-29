-- Modern Aura Group: a normal Group whose Aura (Modern) children grow together.
--
-- Nothing in Lua can know in combat which of these displays has an aura, so
-- the group cannot move its children like a Dynamic Group. Instead each child
-- draws from a "start" frame anchored to the end of the previous child's
-- content, and Blizzard's own frame sizes decide where that end is:
--   Aura(s) Found: the child's aura container, one icon (and spacing) wide per
--     aura shown, one pixel when empty.
--   Aura(s) Missing: a second, invisible container that is one icon wide when
--     the aura is present; it is anchored backwards, so the end moves back.
--   Always, and Total Duration = / >= lists: a fixed icon.
-- The group applies the chain at safe time; Blizzard keeps it in step in combat.
-- Grouped by unit frame or nameplate, each display's aura area for a unit is
-- attached to the previous display's area for the same unit instead
-- (RelinkFlowUnits). The group also sets sort order and limit.
--
-- Centered growth: nothing can halve a secret size, so every part above also
-- gets an invisible "shadow" copy at half its size, with the same filters and
-- unit. The shadows are chained backwards from the centre point; their far
-- end is where the visible row starts, so the row stays centred.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay

Display.flowGrowths = {RIGHT = "Right", LEFT = "Left", DOWN = "Down", UP = "Up",
  CENTER_HORIZONTAL = "Centered Horizontal", CENTER_VERTICAL = "Centered Vertical"}

-- Per growth: the corner a child's content starts from, the corner of an
-- Aura(s) Found container where the next child starts (with the pixel an
-- empty container keeps), and the axis.
local GROWTH = {
  RIGHT = {start = "TOPLEFT", listEnd = "TOPRIGHT", pixel = {-1, 0}, far = "TOPRIGHT", sign = {1, 0}},
  LEFT = {start = "TOPRIGHT", listEnd = "TOPLEFT", pixel = {1, 0}, far = "TOPLEFT", sign = {-1, 0}},
  DOWN = {start = "TOPLEFT", listEnd = "BOTTOMLEFT", pixel = {0, 1}, far = "BOTTOMLEFT", sign = {0, -1}},
  UP = {start = "BOTTOMLEFT", listEnd = "TOPLEFT", pixel = {0, -1}, far = "TOPLEFT", sign = {0, 1}},
}
-- Centered: the visible row grows right (or down); its shadows grow the other
-- way from the centre point on the first display (top middle, or left middle).
local function Centered(visible, shadow, centerPoint)
  local result = CopyTable(GROWTH[visible])
  result.visible, result.shadow, result.centerPoint = visible, GROWTH[shadow], centerPoint
  return result
end
GROWTH.CENTER_HORIZONTAL = Centered("RIGHT", "LEFT", "TOP")
GROWTH.CENTER_VERTICAL = Centered("DOWN", "UP", "LEFT")

-- The direction a display's own aura area grows in.
function Display.VisibleGrowth(growth)
  return GROWTH[growth] and GROWTH[growth].visible or growth
end

-- The Modern Aura Group this display belongs to, or nil.
function Display.FlowGroup(data)
  local parent = data and data.parent and ForeverAuras.GetData(data.parent)
  if parent and parent.regionType == "group" and parent.blizzardFlow then return parent end
end

function Display.FlowGrowth(data)
  local group = Display.FlowGroup(data)
  if not group then return end
  return GROWTH[group.blizzardFlowGrowth] and group.blizzardFlowGrowth or "RIGHT", tonumber(group.blizzardFlowSpacing) or 2
end

Display.flowFrameModes = {SCREEN = "Screen", UNITFRAME = "Unit Frames", NAMEPLATE = "Nameplates"}

-- "UNITFRAME" or "NAMEPLATE" when the group places its displays on each
-- unit's frame, else nil.
function Display.FlowFrameMode(data)
  local group = Display.FlowGroup(data)
  local mode = group and group.blizzardFlowFrames
  if mode == "UNITFRAME" or mode == "NAMEPLATE" then return mode end
end

-- The group's sort order for every display in it, else the trigger's own.
function Display.SortOrder(data, trigger)
  local group = Display.FlowGroup(data)
  local method, reverse
  if group then
    method, reverse = group.blizzardFlowSort, group.blizzardFlowReverse
  else
    method, reverse = trigger.sortMethod, trigger.sortReverse
  end
  -- Blizzard classification is not applied, so its sort has no meaning here.
  if not Display.sortMethods[method or "Default"] or method == "UnitFrameDebuff" then method = "Default" end
  return AuraContainerSortMethod[method or "Default"],
    reverse and AuraContainerSortDirection.Reverse or AuraContainerSortDirection.Normal
end

-- The anchor type that decides where a display's auras go: its Modern Aura
-- Group's mode when it is in one (the group is authoritative), else its own.
function Display.FrameAnchorType(data)
  if Display.FlowGroup(data) then return Display.FlowFrameMode(data) or "SCREEN" end
  return data.anchorFrameType
end

-- The group's limit of auras per display (20 without a limit), or nil.
function Display.FlowLimit(data)
  local group = Display.FlowGroup(data)
  if not group then return end
  if not group.blizzardFlowUseLimit then return 20 end
  return math.max(1, math.floor(tonumber(group.blizzardFlowLimit) or 5))
end

-- Why this display cannot join its Modern Aura Group's growth, or nil.
function Display.FlowProblem(data, trigger)
  if not Display.FlowGroup(data) then return end
  if data.regionType ~= "icon" then return "In a Modern Aura Group, use an Icon display." end
  if Display.RemainingWindow(trigger) then return "In a Modern Aura Group, Remaining Time is not available yet." end
  local mode = Display.FlowFrameMode(data)
  if mode then
    if Display.IsSingle(trigger) then return "Grouped by unit frame or nameplate, use Show On: Aura(s) Found." end
    if mode == "NAMEPLATE" and trigger.unit ~= "nameplate" then return "Grouped by nameplate, choose the Nameplate unit." end
    if mode == "UNITFRAME" and trigger.unit == "nameplate" then return "Grouped by unit frame, choose a unit other than Nameplate." end
  end
end

-- Aura containers in a Modern Aura Group depend on other displays' secret sizes,
-- so they also opt out of untrusted layout scripts, like every frame anchored
-- to an aura container must. Returns the container and whether it opted out.
function Display.CreateAuraContainer(parent, data)
  if Display.FlowGroup(data) then
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent,
      "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if ok and container then return container, true end
  end
  return CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate"), false
end

-- Anchors a container to a Modern Aura Group start frame; falls back to the
-- region when Blizzard refuses the anchor.
function Display.AnchorToContent(container, point, region, relativePoint, x, y)
  local anchor = Display.ContentAnchor(region)
  if anchor ~= region and pcall(container.SetPoint, container, point, anchor, relativePoint, x or 0, y or 0) then return true end
  container:ClearAllPoints()
  container:SetPoint(point, region, relativePoint, x or 0, y or 0)
  return anchor == region
end

-- Where this display's content is drawn from: its start frame in a Modern
-- Aura Group, else the region itself.
function Display.ContentAnchor(region)
  local native = region.blizzardAuraDisplay
  return native and native.flow and native.flow.start or region
end

-- Called by Apply before anything is laid out.
function Display.EnsureFlowStart(region, data)
  local native = region.blizzardAuraDisplay
  if not Display.FlowGroup(data) then
    if native.flow then native.flow.start:Hide(); native.flow = nil end
    return
  end
  local flow = native.flow or {}
  native.flow = flow
  if not flow.start then
    -- Anchored to other displays' aura containers, whose size is secret.
    flow.start = CreateFrame("Frame", nil, region, "DisableUntrustedLayoutScriptsTemplate")
    flow.start:EnableMouse(false)
  end
  local width, height = Display.Dimensions(data)
  flow.start:SetSize(width, height)
  flow.start:Show()
  local growth = Display.FlowGrowth(data)
  flow.growth = GROWTH[growth]
  -- Until the chain is built, start where the region is.
  flow.start:ClearAllPoints()
  flow.start:SetPoint(flow.growth.start, region, flow.growth.start)
end

-- Called by Apply once the display's parts exist: records where the next
-- child starts. presence: the Aura(s) Missing end container, when there is one.
function Display.SetFlowEnd(region, data, presence)
  local native = region.blizzardAuraDisplay
  local flow = native and native.flow
  if not flow then return end
  local g = flow.growth
  local trigger = Display.GetTrigger(data)
  local _, spacing = Display.FlowGrowth(data)
  local width, height = Display.Dimensions(data)
  local showOn = Display.ShowOn(trigger)
  if showOn == "showOnMissing" and presence then
    flow.endFrame, flow.endPoint, flow.x, flow.y = presence, g.start, 0, 0
  elseif showOn == "showOnActive" and not Display.DurationGate(data) and native.instances[1] then
    -- Several units are chained one after another; the last one ends the display.
    flow.endFrame, flow.endPoint = native.instances[#native.instances].container, g.listEnd
    flow.x, flow.y = g.pixel[1], g.pixel[2]
  else
    -- A fixed icon: Always, or a Total Duration list whose candidates overlap.
    flow.endFrame, flow.endPoint = flow.start, g.start
    flow.x, flow.y = g.sign[1] * (width + spacing), g.sign[2] * (height + spacing)
  end
end

-- The Aura(s) Missing end container: one icon plus spacing along the growth
-- axis per present aura.
function Display.FlowPresenceSize(data)
  local growth, spacing = Display.FlowGrowth(data)
  local width, height = Display.Dimensions(data)
  local along = GROWTH[growth].sign[1] ~= 0
  local size = (along and width or height) + spacing + 1
  return along and {elementWidth = size, elementHeight = height} or {elementWidth = width, elementHeight = size}
end

-- Anchors a presence container (one element of size along the growth axis)
-- so its start edge moves back by that size when the aura is present: empty,
-- it is one pixel, so what follows starts size - 1 further on. Only after its
-- aura group exists: Blizzard refuses the anchor before that.
local OPPOSITE = {TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT", BOTTOMLEFT = "TOPLEFT"}
local function AnchorBackwards(container, g, startFrame, size, region)
  local along = g.sign[1] ~= 0
  local point = along and OPPOSITE[g.start] or (g.start == "TOPLEFT" and "BOTTOMLEFT" or "TOPLEFT")
  container:ClearAllPoints()
  local ok = pcall(container.SetPoint, container, point, startFrame, g.start, g.sign[1] * size, g.sign[2] * size)
  if not ok then
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", region, "TOPLEFT")
  end
  return ok
end

-- Returns false when Blizzard refuses it.
function Display.AnchorFlowPresence(region, data, container)
  local flow = region.blizzardAuraDisplay and region.blizzardAuraDisplay.flow
  if not flow then return false end
  local layout = Display.FlowPresenceSize(data)
  local along = flow.growth.sign[1] ~= 0
  return AnchorBackwards(container, flow.growth, flow.start, along and layout.elementWidth or layout.elementHeight, region)
end

---------------------------------------------------------------------------- centered growth
-- An invisible container with the display's filters that measures presence:
-- maxCount elements of the given size, laid out towards g.
local SHADOW_GROUP = "FAShadow"
local function MeasureContainer(existing, region, data, g, layout, maxCount, filter, candidates)
  local container = existing
  if not container then
    container = Display.CreateAuraContainer(region, data)
    container:SetEnabled(false)
    container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
    -- Placed on the region first, like every aura container; chained later.
    container:SetPoint("TOPLEFT", region, "TOPLEFT")
    local ok = pcall(container.AddAuraGroup, container, SHADOW_GROUP, filter, {
      candidateFilters = candidates, maxFrameCount = maxCount, layout = layout,
      initializeFrame = function(button)
        -- Draws nothing; only the container's size is used.
        button:SetSize(layout.elementWidth, layout.elementHeight)
        button:SetAlpha(0)
        button:EnableMouse(false)
      end,
    })
    if not ok then container:Hide(); return nil end
  else
    container:SetAuraGroupFilterString(SHADOW_GROUP, filter)
    container:SetAuraGroupCandidateFilters(SHADOW_GROUP, candidates)
    container:SetAuraGroupLayout(SHADOW_GROUP, layout)
    container:SetAuraGroupMaxFrameCount(SHADOW_GROUP, maxCount)
    container:SetAuraGroupEnabled(SHADOW_GROUP, true)
  end
  local vertical = g.sign[2] ~= 0
  container:SetFlowLayoutAxis(vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal)
  container:SetFlowLayoutAnchorPoint(g.start)
  container:SetFlowLayoutGrowthDirection(g.sign[1] < 0 and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right,
    g.sign[2] > 0 and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)
  return container
end

local function HideShadow(holder, key)
  local container = holder and holder[key]
  if container then
    holder[key .. "Active"] = false
    container:SetEnabled(false)
    container:Hide()
  end
end

-- Called by Apply after the display's parts exist: builds or retires the
-- half-size shadows of a centred Modern Aura Group.
function Display.EnsureFlowShadows(region, data)
  local native = region.blizzardAuraDisplay
  local flow = native and native.flow
  local sh = flow and flow.growth.shadow
  local missing = native and native.instances[1] and native.instances[1].single and native.instances[1].single.missing
  for _, instance in ipairs(native and native.instances or {}) do
    if not sh then HideShadow(instance, "flowShadow") end
  end
  if not sh then
    HideShadow(missing, "flowShadow")
    if flow and flow.shadowStart then flow.shadowStart:Hide() end
    return
  end
  if not flow.shadowStart then
    flow.shadowStart = CreateFrame("Frame", nil, region, "DisableUntrustedLayoutScriptsTemplate")
    flow.shadowStart:EnableMouse(false)
    flow.shadowStart:SetSize(1, 1)
  end
  flow.shadowStart:Show()
  local trigger = Display.GetTrigger(data)
  local _, spacing = Display.FlowGrowth(data)
  local width, height = Display.Dimensions(data)
  local along = sh.sign[1] ~= 0
  flow.half = ((along and width or height) + spacing) / 2
  local size = flow.half + 1
  local layout = along and {elementWidth = size, elementHeight = height, elementSpacing = -1}
    or {elementWidth = width, elementHeight = size, elementSpacing = -1}
  local filter, candidates = Display.FilterString(trigger), Display.CandidateFilters(data)
  local showOn = Display.ShowOn(trigger)
  flow.shadowKind, flow.shadowList = "fixed", nil
  if showOn == "showOnActive" and not Display.DurationGate(data) then
    flow.shadowList = {}
    for _, instance in ipairs(native.instances) do
      instance.flowShadow = MeasureContainer(instance.flowShadow, region, data, sh, layout, Display.MaxAuras(data), filter, candidates)
      instance.flowShadowActive = instance.flowShadow ~= nil
      if instance.flowShadow then flow.shadowList[#flow.shadowList + 1] = instance.flowShadow end
    end
    if #flow.shadowList > 0 then flow.shadowKind = "list" end
  else
    for _, instance in ipairs(native.instances) do HideShadow(instance, "flowShadow") end
  end
  if showOn == "showOnMissing" and missing and missing.active then
    local single = {elementWidth = along and size or width, elementHeight = along and height or size}
    missing.flowShadow = MeasureContainer(missing.flowShadow, region, data, sh, single, 1, filter, candidates)
    missing.flowShadowActive = missing.flowShadow ~= nil
      and AnchorBackwards(missing.flowShadow, sh, flow.shadowStart, size, region)
    missing.flowShadowBoundUnit = nil
    if missing.flowShadowActive then flow.shadowKind = "missing" end
  else
    HideShadow(missing, "flowShadow")
  end
end

-- Keeps a display's list shadow on the same unit as its aura area.
function Display.RefreshFlowShadow(instance, unit, shown)
  local container = instance.flowShadowActive and instance.flowShadow
  if not container then return end
  if unit and instance.flowShadowUnit ~= unit then
    container:SetEnabled(false)
    container:SetUnit(unit)
    instance.flowShadowUnit = unit
  end
  container:SetShown(shown)
  container:SetEnabled(shown)
  if shown then container:UpdateAllAuras() end
end

-- Chains one display's shadows from its shadow start; returns where the next
-- display's shadows start.
local function ChainShadows(flow)
  local sh = flow.growth.shadow
  if flow.shadowKind == "list" then
    for index, container in ipairs(flow.shadowList) do
      container:ClearAllPoints()
      if index == 1 then
        pcall(container.SetPoint, container, sh.start, flow.shadowStart, sh.start)
      else
        pcall(container.SetPoint, container, sh.start, flow.shadowList[index - 1], sh.listEnd, sh.pixel[1], sh.pixel[2])
      end
    end
    return {flow.shadowList[#flow.shadowList], sh.listEnd, sh.pixel[1], sh.pixel[2]}
  elseif flow.shadowKind == "missing" then
    local single = flow.region.blizzardAuraDisplay.instances[1].single.missing
    return {single.flowShadow, sh.start, 0, 0}
  end
  return {flow.shadowStart, sh.start, sh.sign[1] * flow.half, sh.sign[2] * flow.half}
end

-- Grouped by frame: for every unit, its aura area in the first display sits
-- on the unit's frame, and each later display's area follows the previous one.
-- Called after any display in the group rebinds its units, also in combat,
-- like the aura list's own unit anchoring.
-- The group's own frame: on the screen, the row starts (or centres) at its
-- anchor point, like a Dynamic Group's children. nil before it exists.
-- The editor's nameplate stand-in (the Personal Resource Display frame),
-- shown while the options are open, as for a Dynamic Group grouped by
-- nameplate. Released when the group no longer uses it.
local function NameplatePreview(group)
  if not (Private.ensurePRDFrame and ForeverAuras.IsOptionsOpen()) then return end
  Private.ensurePRDFrame()
  local frame = Private.personalRessourceDisplayFrame
  if frame and frame.anchorFrame then frame:anchorFrame(group.id, "NAMEPLATE") end
  return frame
end

-- Grouped by frame, the editor's box for a display (the frame the mover and
-- selection outline use) is moved onto its preview icons, as a Dynamic Group
-- moves its children onto the nameplate stand-in. The display's own anchor is
-- kept and put back when the preview ends or the group stops using frames.
local function MovePreviewRegion(region, button)
  if not (region.SetAnchor and region.SetOffset) then return end
  -- Anchored anywhere else, the anchor is the display's own (set again by
  -- the editor after a change), so it is the one to keep.
  if region.relativeTo ~= button then
    region.flowPreviewSaved = {region.anchorPoint, region.relativeTo, region.relativePoint,
      region.GetXOffset and region:GetXOffset() or 0, region.GetYOffset and region:GetYOffset() or 0}
  end
  region:SetAnchor("TOPLEFT", button, "TOPLEFT")
  region:SetOffset(0, 0)
end

function Display.RestorePreviewRegion(region)
  local saved = region and region.flowPreviewSaved
  if not saved then return end
  region.flowPreviewSaved = nil
  if saved[1] and saved[2] then region:SetAnchor(saved[1], saved[2], saved[3]) end
  region:SetOffset(saved[4], saved[5])
end

-- The group's own editor box: its frame is placed by the addon on the frame
-- the preview uses (Private.AnchorFrame, FlowPreviewFrame), and its bounds
-- are set to cover the first unit's preview row, which starts at the group's
-- anchor. Put back when the group no longer previews on a frame.
local function SetGroupPreviewBounds(group, g, length, cross, ox, oy)
  local entry = Private.regions[group.id]
  local region = entry and entry.region
  if not region then return end
  local blx, bly, trx, try
  if g.sign[1] > 0 then blx, trx, try, bly = 0, length, 0, -cross
  elseif g.sign[1] < 0 then blx, trx, try, bly = -length, 0, 0, -cross
  elseif g.sign[2] < 0 then blx, trx, try, bly = 0, cross, 0, -length
  else blx, trx, bly, try = 0, cross, 0, length end
  blx, trx, bly, try = blx + ox, trx + ox, bly + oy, try + oy
  if region.GetBoundingRect ~= region.flowPreviewBoundsFn then
    region.flowPreviewBoundsSaved = region.GetBoundingRect
  end
  region.flowPreviewBoundsFn = function(self)
    self.blx, self.bly, self.trx, self.try = blx, bly, trx, try
    return blx, bly, trx, try
  end
  region.GetBoundingRect = region.flowPreviewBoundsFn
  region:GetBoundingRect()
end

function Display.RestoreGroupPreview(group)
  local entry = group and Private.regions[group.id]
  local region = entry and entry.region
  if not region then return end
  if region.flowPreviewBoundsSaved then
    if region.GetBoundingRect == region.flowPreviewBoundsFn then region.GetBoundingRect = region.flowPreviewBoundsSaved end
    region.flowPreviewBoundsSaved, region.flowPreviewBoundsFn = nil, nil
    region.boundingRect = false
    region:GetBoundingRect()
  end
end

function Display.ReleaseNameplatePreview(group)
  local frame = Private.personalRessourceDisplayFrame
  if group and frame and frame.anchorFrame then frame:anchorFrame(group.id, nil) end
end

-- Grouped by frame, the group's Position and Size settings (To Frame's point
-- and offsets) place the first aura on each frame.
local function FramePosition(group)
  return group.anchorPoint or "CENTER", tonumber(group.xOffset) or 0, tonumber(group.yOffset) or 0
end

-- Grouped by frame, the group's Anchor point places the row on the To
-- Frame's point across its growth direction (icon size, known here): top,
-- middle or bottom of a horizontal row; left, middle or right of a vertical
-- one. Along the growth, Centered growth centres it; the others start there.
local function CrossOffset(group, g, cross)
  local selfPoint = group.selfPoint or "CENTER"
  if g.sign[1] ~= 0 then
    if selfPoint:find("TOP") then return 0, 0 end
    if selfPoint:find("BOTTOM") then return 0, cross end
    return 0, cross / 2
  end
  if selfPoint:find("LEFT") then return 0, 0 end
  if selfPoint:find("RIGHT") then return -cross, 0 end
  return -cross / 2, 0
end

-- The largest icon across the growth among the group's displays.
local function GroupCross(group, g)
  local cross = 0
  for _, childID in ipairs(group.controlledChildren or {}) do
    local child = ForeverAuras.GetData(childID)
    if child and Display.Enabled(child) then
      local width, height = Display.Dimensions(child)
      cross = math.max(cross, g.sign[1] ~= 0 and height or width)
    end
  end
  return cross
end

local function UnitAnchor(mode, unit)
  local frame = mode == "UNITFRAME" and ForeverAuras.GetUnitFrame(unit) or (mode == "NAMEPLATE" and C_NamePlate.GetNamePlateForUnit(unit))
  if frame and not frame:IsForbidden() then return frame end
end

-- While an event refreshes many displays, each group is re-anchored once at
-- the end (EndFlowBatch) instead of once per display.
local batch
function Display.BeginFlowBatch() batch = batch or {} end
function Display.EndFlowBatch()
  local groups = batch
  batch = nil
  for group in pairs(groups or {}) do Display.RelinkFlowUnits(group) end
end

function Display.RelinkFlowUnits(group)
  local mode = group and group.blizzardFlowFrames
  if mode ~= "UNITFRAME" and mode ~= "NAMEPLATE" then return end
  if batch then batch[group] = true; return end
  local g = GROWTH[group.blizzardFlowGrowth] or GROWTH.RIGHT
  -- The group's own Position and Size settings, relative to each frame.
  local point, frameX, frameY = FramePosition(group)
  local cx, cy = CrossOffset(group, g, GroupCross(group, g))
  frameX, frameY = frameX + cx, frameY + cy
  local spacing = tonumber(group.blizzardFlowSpacing) or 2
  -- Centred: per unit, the shadows run backwards from the frame point first.
  local lastShadow = {}
  local sh = g.shadow
  if sh then
    for _, childID in ipairs(group.controlledChildren or {}) do
      local entry = Private.regions[childID]
      local native = entry and entry.region and entry.region.blizzardAuraDisplay
      if native and native.active then
        for _, instance in ipairs(native.instances) do
          local unit = instance.visible and instance.boundUnit
          local shadow = unit and instance.flowShadowActive and instance.flowShadow
          if shadow then
            shadow:ClearAllPoints()
            local linked = lastShadow[unit] and pcall(shadow.SetPoint, shadow, sh.start, lastShadow[unit], sh.listEnd, sh.pixel[1], sh.pixel[2])
            local frame = not linked and UnitAnchor(mode, unit)
            if frame then shadow:SetPoint(sh.start, frame, point, frameX, frameY) end
            lastShadow[unit] = shadow
          end
        end
      end
    end
  end
  local last = {}
  for _, childID in ipairs(group.controlledChildren or {}) do
    local entry = Private.regions[childID]
    local native = entry and entry.region and entry.region.blizzardAuraDisplay
    if native and native.active then
      for _, instance in ipairs(native.instances) do
        local unit = instance.visible and instance.boundUnit
        if unit then
          local container = instance.container
          container:ClearAllPoints()
          local linked = last[unit] and pcall(container.SetPoint, container, g.start, last[unit], g.listEnd, g.pixel[1], g.pixel[2])
          if not linked and lastShadow[unit] then
            -- Centred: start where the shadows end, half a spacing on.
            linked = pcall(container.SetPoint, container, g.start, lastShadow[unit], sh.listEnd,
              sh.pixel[1] + g.sign[1] * spacing / 2, sh.pixel[2] + g.sign[2] * spacing / 2)
          end
          if not linked then
            local frame = UnitAnchor(mode, unit)
            if frame then
              container:ClearAllPoints()
              container:SetPoint(g.start, frame, point, frameX, frameY)
            end
          end
          last[unit] = container
        end
      end
    end
  end
end

-- Options preview: the samples are plain frames of known size, so they are
-- simply lined up in the group's order, on a nameplate or unit frame when the
-- group is grouped by frame (the first display's preview unit), else starting
-- at the first display.
-- The units a display previews on, grouped by unit frame: those of its unit
-- setting that exist and have a frame (Smart Group: you and your party),
-- like a Dynamic Group's preview clones. {false} otherwise: one row.
local MAX_PREVIEW_UNITS = 5
function Display.FlowPreviewUnits(data)
  if Display.FlowFrameMode(data) ~= "UNITFRAME" then return {false} end
  local units = {}
  for _, unit in ipairs(Display.UnitTokens(Display.GetTrigger(data) or {})) do
    if UnitExists(unit) and ForeverAuras.GetUnitFrame(unit) then
      units[#units + 1] = unit
      if #units >= MAX_PREVIEW_UNITS then break end
    end
  end
  if #units == 0 then units[1] = "player" end
  return units
end

-- The frame a unit's preview row sits on: the editor's nameplate stand-in, or
-- the unit's frame.
local function PreviewFrame(group, unit)
  local frame
  if group.blizzardFlowFrames == "NAMEPLATE" then
    frame = NameplatePreview(group)
  elseif unit then
    frame = ForeverAuras.GetUnitFrame(unit)
  end
  if frame and not frame:IsForbidden() then return frame end
end

-- The frame the group itself is anchored to in the editor, so its box and
-- Position and Size settings work on the frame, as for a Dynamic Group grouped
-- by frame. nil when the group is not grouped by frame or the options are closed.
function Display.FlowPreviewFrame(group)
  local mode = group and group.blizzardFlow and group.blizzardFlowFrames
  if (mode ~= "UNITFRAME" and mode ~= "NAMEPLATE") or not ForeverAuras.IsOptionsOpen() then return end
  local unit
  for _, childID in ipairs(group.controlledChildren or {}) do
    local child = ForeverAuras.GetData(childID)
    if child and Display.Enabled(child) then
      unit = Display.FlowPreviewUnits(child)[1]
      break
    end
  end
  return PreviewFrame(group, unit or "player")
end

-- Options preview: the samples are plain frames of known size, so they are
-- lined up in the group's order: per unit on its frame (or on the nameplate
-- stand-in) when grouped by frame, else starting at the first display.
function Display.ArrangeFlowPreview(group)
  if not group then return end
  local mode = group.blizzardFlowFrames
  local framed = mode == "UNITFRAME" or mode == "NAMEPLATE"
  if mode ~= "NAMEPLATE" then Display.ReleaseNameplatePreview(group) end
  local g = GROWTH[group.blizzardFlowGrowth] or GROWTH.RIGHT
  local spacing = tonumber(group.blizzardFlowSpacing) or 2
  local along = g.sign[1] ~= 0
  local point, frameX, frameY = FramePosition(group)
  local function Key(sample) return framed and mode == "UNITFRAME" and sample.previewUnit or "" end
  -- Each row's length and depth, known here; centred rows start half back.
  local length, cross, firstKey = {}, {}, nil
  for _, childID in ipairs(group.controlledChildren or {}) do
    local entry = Private.regions[childID]
    local region = entry and entry.region
    if region and region.secretAuraSamplesActive then
      for _, sample in ipairs(region.secretAuraSamples or {}) do
        local button = sample.button
        if button:IsShown() then
          local key = Key(sample)
          firstKey = firstKey or key
          local width, height = button:GetWidth() or 0, button:GetHeight() or 0
          length[key] = (length[key] or 0) + (along and width or height) + spacing
          cross[key] = math.max(cross[key] or 0, along and height or width)
        end
      end
    end
  end
  local function Offset(key)
    if not g.shadow then return 0, 0 end
    local half = math.max(0, (length[key] or 0) - spacing) / 2
    return -g.sign[1] * half, -g.sign[2] * half
  end
  local previous = {}
  local onFrame = false
  for _, childID in ipairs(group.controlledChildren or {}) do
    local entry = Private.regions[childID]
    local region = entry and entry.region
    if region and region.secretAuraSamplesActive then
      local moved = false
      for _, sample in ipairs(region.secretAuraSamples or {}) do
        local button = sample.button
        if button:IsShown() then
          local key = Key(sample)
          local frame = framed and PreviewFrame(group, sample.previewUnit or nil)
          local ox, oy = Offset(key)
          -- The group's anchor point only places the row on a frame; on the
          -- screen the row sits on the first display's box, as the live auras do.
          if frame then
            local cx, cy = CrossOffset(group, g, cross[key] or 0)
            ox, oy = ox + cx, oy + cy
          end
          button:ClearAllPoints()
          if previous[key] then
            button:SetPoint(g.start, previous[key], g.far, g.sign[1] * spacing, g.sign[2] * spacing)
          elseif frame then
            button:SetPoint(g.start, frame, point, frameX + ox, frameY + oy)
          elseif g.shadow then
            button:SetPoint(g.start, region, g.centerPoint, ox, oy)
          else
            button:SetPoint(g.start, region, g.start)
          end
          -- On a frame, the display's own box follows its first icon.
          if frame and not moved then
            MovePreviewRegion(region, button)
            moved = true
          end
          onFrame = onFrame or frame ~= nil and frame ~= false
          previous[key] = button
        end
      end
      if not moved then Display.RestorePreviewRegion(region) end
    end
  end
  if onFrame and firstKey then
    local ox, oy = Offset(firstKey)
    local cx, cy = CrossOffset(group, g, cross[firstKey] or 0)
    ox, oy = ox + cx, oy + cy
    SetGroupPreviewBounds(group, g, math.max(0, (length[firstKey] or 0) - spacing), cross[firstKey] or 0, ox, oy)
  else
    Display.RestoreGroupPreview(group)
  end
end

-- Re-anchors every child of a Modern Aura Group in the group's child order.
function Display.RechainFlow(group)
  if not group then return end
  if group.blizzardFlowFrames == "UNITFRAME" or group.blizzardFlowFrames == "NAMEPLATE" then
    Display.RelinkFlowUnits(group)
    return
  end
  if InCombatLockdown() then return end
  local flows = {}
  local g = GROWTH[group.blizzardFlowGrowth] or GROWTH.RIGHT
  for _, childID in ipairs(group.controlledChildren or {}) do
    local entry = Private.regions[childID]
    local region = entry and entry.region
    local native = region and region.blizzardAuraDisplay
    local flow = native and native.active and native.flow
    -- A display not yet rebuilt for the group's current growth joins the
    -- chain when its own rebuild runs.
    if flow and flow.endFrame and flow.growth == g then
      flow.region = region
      flows[#flows + 1] = flow
    end
  end
  -- Centred: the shadows run backwards from the first display's centre point,
  -- and the visible row starts where they end, half a spacing on.
  local previous, shadowEnd
  if g.shadow and flows[1] then
    local spacing = tonumber(group.blizzardFlowSpacing) or 2
    for _, flow in ipairs(flows) do
      if flow.shadowStart and flow.shadowKind then
        flow.shadowStart:ClearAllPoints()
        if not (shadowEnd and pcall(flow.shadowStart.SetPoint, flow.shadowStart, g.shadow.start, shadowEnd[1], shadowEnd[2], shadowEnd[3], shadowEnd[4])) then
          flow.shadowStart:ClearAllPoints()
          flow.shadowStart:SetPoint(g.shadow.start, flows[1].region, g.centerPoint)
        end
        shadowEnd = ChainShadows(flow)
      end
    end
    if shadowEnd then
      previous = {endFrame = shadowEnd[1], endPoint = shadowEnd[2],
        x = shadowEnd[3] + g.sign[1] * spacing / 2, y = shadowEnd[4] + g.sign[2] * spacing / 2}
    end
  end
  for _, flow in ipairs(flows) do
    local region = flow.region
    do
      flow.start:ClearAllPoints()
      local chained = previous and pcall(flow.start.SetPoint, flow.start, flow.growth.start,
        previous.endFrame, previous.endPoint, previous.x, previous.y)
      if not chained then
        -- First display, or Blizzard refused the anchor: start at the region.
        flow.start:ClearAllPoints()
        flow.start:SetPoint(flow.growth.start, region, flow.growth.start)
      end
      previous = flow
    end
  end
end
