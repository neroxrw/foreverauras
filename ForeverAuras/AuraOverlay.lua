-- Copyright (C) 2026 ForeverAuras. Part of ForeverAuras, licensed under the GNU GPL v2 (see LICENSE).
-- ForeverAuras.AuraOverlay: a native aura slot drawn over any frame, for
-- custom code (aura init scripts, custom triggers, other addons). Blizzard
-- fills the slot while one of the given spell IDs is on the unit, in combat
-- and instances too, and drives the swipe and countdown from the aura's own
-- timer; nothing here reads aura data, so secret values never reach Lua.
--
--   local overlay = ForeverAuras.AuraOverlay(frame, {
--     spellIDs = {12345, 23456},  -- auras to look for (required)
--     debuffSpellIDs = {34567},   -- harmful auras on the unit to look for as well
--     unit = "player",            -- default "player"
--     filter = "HELPFUL",         -- Blizzard filter string, default "HELPFUL"
--     icon = false,               -- draw the aura's icon over the frame
--     texture = nil,              -- a fixed texture covering the frame while the aura is up
--     textureCoords = nil,        -- its tex coords, e.g. {0.08, 0.92, 0.08, 0.92}
--     swipe = true,               -- a cooldown driven by the remaining time
--     swipeVisible = true,        -- draw its swipe (false: numbers only)
--     countdown = true,           -- countdown numbers; countdownFont, countdownSize,
--                                 -- countdownFlags, countdownPoint, countdownX,
--                                 -- countdownY and countdownColor style them
--     border = {1, 0.85, 0, 1},   -- border colour, or false for none
--     borderSize = 2,             -- border thickness in pixels
--     levelOffset = 5,            -- frame level above the frame
--     enabled = true,
--     owner = nil,                -- the display frame this overlay belongs to, only
--                                 -- needed when the frame's parents cannot be read
--                                 -- (the addon retires the overlay with that display)
--   })
--   overlay:SetSpellIDs({...}, {debuffs...}); overlay:SetUnit("target"); overlay:SetEnabled(false)
--   overlay:SetBorderColor(r, g, b, a); overlay:SetTexture(texture, coords); overlay:Release()
--   overlay:IsReleased() -- true once released, by the code that made it or by the
--                        -- addon when the frame it covers is pooled or reassigned;
--                        -- Release() returns false while a refused frame write is
--                        -- still owed (the addon finishes it when restrictions end)
--
-- Returns nil and a message when the client refuses the slot.
if not WeakAuras.IsLibsOK() then return end
---@type string, Private
local AddonName, Private = ...

local SLOT = "Overlay"
-- Debuffs need their own slot: a slot has one Blizzard filter.
local SLOT_HARMFUL = "OverlayHarmful"
-- A map matching no aura, for a slot that currently has nothing to look for.
local NONE = {[1] = true}
local Overlay = {}
Overlay.__index = Overlay

-- ForeverAuras (Astra's overlay-reuse review, dev.4/dev.5 follow-ups): the
-- overlays drawn over each display, by the display frame that owns them, so
-- the addon can retire them when it relinquishes that frame. A display's
-- frame goes back to a shared pool when the display hides and is handed to
-- the next display of that type; an overlay custom code left on it (its
-- native slot still enabled, its countdown still bound) travelled with the
-- frame and drew over the new owner's icon. Only overlays made through this
-- API are tracked; other custom children are never touched.
--
-- Ownership is settled before anything is created: the parent's readable
-- ancestry is walked to the display frame (a frame with a regionType), or
-- the caller names the owner (options.owner, a display frame) for a parent
-- whose ancestry cannot be read. With neither, the overlay is refused (nil
-- and a message) before any native state exists, so no overlay can be live
-- without a recorded owner and a pooled frame is never cleared by guess.
-- Retirement is a set of frame writes; one the client refuses stays owned
-- and pending (the overlay stays registered, its frame is held out of the
-- pool by the caller) and is tried again from the existing restriction-end
-- drain, never from a timer.
local overlaysByOwner = setmetatable({}, {__mode = "k"})
local pendingRetirements = {}

local function IsDisplayFrame(frame)
  return type(frame) == "table" and type(frame.regionType) == "string"
end

-- The display frame above a parent, or the parent itself when no display
-- frame is above it (an overlay on a unit frame, say: the frame the caller
-- would release); nil and "unreadable" when the ancestry cannot be read.
local function ResolveOwner(parent)
  local cursor, depth = parent, 0
  while cursor and depth < 64 do
    if IsDisplayFrame(cursor) then return cursor end
    if type(cursor) ~= "table" or not cursor.GetParent then return parent end
    local ok, up = pcall(cursor.GetParent, cursor)
    if not ok then return nil, "unreadable" end
    cursor = up
    depth = depth + 1
  end
  return parent
end

local function Register(overlay, owner)
  overlay.owner = owner
  local list = overlaysByOwner[owner]
  if not list then list = {}; overlaysByOwner[owner] = list end
  list[#list + 1] = overlay
end
local function Unregister(overlay)
  local list = overlaysByOwner[overlay.owner]
  if not list then return end
  for i = #list, 1, -1 do if list[i] == overlay then table.remove(list, i) end end
  if #list == 0 then overlaysByOwner[overlay.owner] = nil end
end

-- Retires every overlay owned by the frame (a display frame, or the frame
-- an overlay was drawn over directly). Returns true when the frame carries
-- no live overlay any more, false when a retirement is still pending (the
-- caller keeps the frame out of the shared pool until a later call returns
-- true), and the number of overlays retired on this call.
function Private.ReleaseAuraOverlays(frame)
  if type(frame) ~= "table" then return true, 0 end
  local list = overlaysByOwner[frame]
  if not list then return true, 0 end
  local retired, pending = 0, false
  for i = #list, 1, -1 do
    local overlay = list[i]
    if overlay then
      if overlay:Release() then retired = retired + 1 else pending = true end
    end
  end
  return not pending, retired
end

-- Called from the restriction-end drain (BlizzardAuraDisplay.lua); finishes
-- retirements the client refused earlier. Returns how many still wait.
function Private.RetryAuraOverlayRetirements()
  local waiting = 0
  for overlay in pairs(pendingRetirements) do
    if not overlay:Release() then waiting = waiting + 1 end
  end
  return waiting
end

local function SpellIDMap(list)
  local map, any = {}, false
  for _, id in ipairs(list or {}) do
    id = tonumber(id)
    if id then map[id], any = true, true end
  end
  return any and map or NONE
end

local function Colour(texture, colour)
  texture:SetColorTexture(colour[1] or 1, colour[2] or 1, colour[3] or 1, colour[4] or 1)
end

-- Builds a slot frame's look once; Blizzard shows and hides the frame. The
-- target is the overlay for the buff slot and overlay.harmful for the debuff
-- slot, so each keeps its own textures.
local function Build(overlay, button, options)
  overlay.button = button
  button:SetAllPoints(overlay.container or overlay.owner.container)
  button:EnableMouse(false)
  -- A fixed texture under everything else, so the overlay can cover what the
  -- frame below draws (a greyed icon, its own swipe and text) while the aura
  -- is up; textureCoords match the frame's zoom.
  if options.texture then
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(button)
    texture:SetTexture(options.texture)
    if type(options.textureCoords) == "table" then texture:SetTexCoord(unpack(options.textureCoords)) end
    overlay.texture = texture
  end
  if options.icon then
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)
    overlay.icon = icon
  end
  if options.swipe ~= false then
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetDrawSwipe(options.swipeVisible ~= false)
    cooldown:SetHideCountdownNumbers(options.countdown == false)
    cooldown:SetReverse(options.reverse == true)
    -- The aura's own timer drives it; nothing is read back.
    cooldown:SetUseAuraDisplayTime(true)
    button:SetDurationCooldown(cooldown)
    overlay.cooldown = cooldown
    -- The countdown numbers take the caller's font and place; Blizzard
    -- writes the time into them.
    local numbers = options.countdown ~= false and cooldown:GetCountdownFontString()
    if numbers then
      numbers:SetFont(options.countdownFont or STANDARD_TEXT_FONT, tonumber(options.countdownSize) or 12, options.countdownFlags or "OUTLINE")
      numbers:ClearAllPoints()
      numbers:SetPoint(options.countdownPoint or "CENTER", button, options.countdownPoint or "CENTER",
        tonumber(options.countdownX) or 0, tonumber(options.countdownY) or 0)
      local colour = options.countdownColor
      if type(colour) == "table" then numbers:SetTextColor(colour[1] or 1, colour[2] or 1, colour[3] or 1, colour[4] or 1) end
      overlay.numbers = numbers
    end
  end
  if options.border ~= false then
    local size = tonumber(options.borderSize) or 2
    local colour = type(options.border) == "table" and options.border or {1, 0.85, 0, 1}
    overlay.edges = {}
    for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
      local edge = button:CreateTexture(nil, "OVERLAY")
      Colour(edge, colour)
      if side == "TOP" or side == "BOTTOM" then
        edge:SetPoint(side .. "LEFT", button, side .. "LEFT")
        edge:SetPoint(side .. "RIGHT", button, side .. "RIGHT")
        edge:SetHeight(size)
      else
        edge:SetPoint("TOP" .. side, button, "TOP" .. side)
        edge:SetPoint("BOTTOM" .. side, button, "BOTTOM" .. side)
        edge:SetWidth(size)
      end
      overlay.edges[#overlay.edges + 1] = edge
    end
  end
  if options.stacks then
    local text = button:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT, tonumber(options.stacksSize) or 12, "OUTLINE")
    text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetApplicationCount(text)
    overlay.stacks = text
  end
end

function ForeverAuras.AuraOverlay(parent, options)
  options = options or {}
  if type(parent) ~= "table" or not parent.GetFrameLevel then return nil, "AuraOverlay needs a frame to draw over." end
  if not (CustomAuraContainerAuraProcessingPolicy and C_UnitAuras) then return nil, "This client has no native aura containers." end
  -- ForeverAuras (Astra's dev.5 follow-up): the owner is known before any
  -- native state is made; see the note above the registry.
  local owner = ResolveOwner(parent)
  if not owner then
    if IsDisplayFrame(options.owner) then
      owner = options.owner
    else
      return nil, "AuraOverlay cannot tell which display owns this frame right now; pass owner = <the display's frame> or try again later."
    end
  end
  local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  container:SetEnabled(false)
  container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
  container:SetAllPoints(parent)
  -- The overlay must never take clicks from the frame it covers.
  pcall(container.EnableMouse, container, false)
  container:SetFrameLevel(parent:GetFrameLevel() + (tonumber(options.levelOffset) or 5))
  local overlay = setmetatable({container = container, parent = parent, unit = options.unit or "player",
    filter = options.filter or "HELPFUL", enabled = options.enabled ~= false, options = options}, Overlay)
  local ok, err = pcall(container.AddAuraSlot, container, SLOT, overlay.filter, {
    candidateFilters = {includeSpellIDs = SpellIDMap(options.spellIDs)},
    initializeFrame = function(button) Build(overlay, button, options) end,
  })
  if not ok then
    container:Hide()
    return nil, "Blizzard refused the aura slot: " .. tostring(err)
  end
  if options.debuffSpellIDs and #options.debuffSpellIDs > 0 then
    local added, why = overlay:AddHarmfulSlot(options.debuffSpellIDs)
    if not added then
      container:Hide()
      return nil, "Blizzard refused the debuff slot: " .. tostring(why)
    end
  end
  container:SetUnit(overlay.unit)
  container:SetEnabled(overlay.enabled)
  Register(overlay, owner)
  return overlay
end

-- The debuff slot is a second frame with the same look, added when the
-- first debuff list arrives; the container is disabled while it is added.
function Overlay:AddHarmfulSlot(list)
  if self.released or self.harmful then return true end
  local container, options = self.container, self.options
  self.harmful = {owner = self}
  container:SetEnabled(false)
  local ok, err = pcall(container.AddAuraSlot, container, SLOT_HARMFUL, "HARMFUL", {
    candidateFilters = {includeSpellIDs = SpellIDMap(list)},
    initializeFrame = function(button) Build(self.harmful, button, options) end,
  })
  if not ok then self.harmful = nil end
  container:SetEnabled(self.enabled)
  return ok, err
end

function Overlay:SetSpellIDs(list, debuffList)
  if self.released then return end
  pcall(self.container.SetAuraSlotCandidateFilters, self.container, SLOT, {includeSpellIDs = SpellIDMap(list)})
  if debuffList and #debuffList > 0 and not self.harmful then self:AddHarmfulSlot(debuffList) end
  if self.harmful then
    pcall(self.container.SetAuraSlotCandidateFilters, self.container, SLOT_HARMFUL, {includeSpellIDs = SpellIDMap(debuffList)})
  end
end

function Overlay:SetUnit(unit)
  if self.released or self.unit == unit then return end
  self.unit = unit
  -- Disabling clears the slot before the unit changes, as the displays do.
  self.container:SetEnabled(false)
  self.container:SetUnit(unit)
  self.container:SetEnabled(self.enabled)
end

function Overlay:SetEnabled(enabled)
  if self.released then return end
  self.enabled = enabled ~= false
  self.container:SetEnabled(self.enabled)
end

function Overlay:SetBorderColor(r, g, b, a)
  for _, target in ipairs({self, self.harmful}) do
    for _, edge in ipairs(target.edges or {}) do edge:SetColorTexture(r, g, b, a or 1) end
  end
end

function Overlay:SetTexture(texture, coords)
  for _, target in ipairs({self, self.harmful}) do
    if target.texture then
      target.texture:SetTexture(texture)
      if type(coords) == "table" then target.texture:SetTexCoord(unpack(coords)) end
    end
  end
end

function Overlay:GetButton()
  return self.button
end

-- Whether the overlay is still usable; custom code that keeps a handle
-- across its display's hide and show makes a new one when this is false.
function Overlay:IsReleased()
  return self.released == true
end

-- True while a retirement write the client refused is still owed.
function Overlay:CleanupPending()
  return self.pendingSteps ~= nil
end

-- ForeverAuras (Astra's overlay-reuse review, dev.4 follow-up): released is
-- set at once, so the owner's later calls (SetEnabled, SetSpellIDs, SetUnit)
-- are inert from the first request on; the container writes are each tried
-- under pcall and the ones the client refuses are remembered and owed. The
-- overlay stays registered under its owner until every write has succeeded.
-- Returns true when the retirement is complete, false while writes are owed.
local RETIREMENT = {"disable", "hide", "clear", "reparent"}
function Overlay:Release()
  if self.released and not self.pendingSteps then return true end
  self.released = true
  local container = self.container
  local steps = self.pendingSteps or {disable = true, hide = true, clear = true, reparent = true}
  if steps.disable and pcall(container.SetEnabled, container, false) then steps.disable = nil end
  if steps.hide and pcall(container.Hide, container) then steps.hide = nil end
  if steps.clear and pcall(container.ClearAllPoints, container) then steps.clear = nil end
  -- The frame the overlay sat on may be handed to another display; the
  -- released container leaves it, so nothing of the old owner's look stays
  -- parented to the new owner.
  if steps.reparent and pcall(container.SetParent, container, WeakAurasHiddenFrames or UIParent) then steps.reparent = nil end
  for _, step in ipairs(RETIREMENT) do
    if steps[step] then
      self.pendingSteps = steps
      pendingRetirements[self] = true
      return false
    end
  end
  self.pendingSteps = nil
  pendingRetirements[self] = nil
  Unregister(self)
  return true
end
