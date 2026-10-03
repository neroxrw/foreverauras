-- Modified for ForeverAuras, 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

-- Lua APIs
local pairs  = pairs

-- WoW APIs
local CreateFrame = CreateFrame

local AceGUI = LibStub("AceGUI-3.0")

---@class ForeverAuras
local ForeverAuras = ForeverAuras
local L = ForeverAuras.L

local iconPicker

local spellCache = ForeverAuras.spellCache

local cachedNames, cachedCache
local function CacheNames(cache)
  if cachedNames and cachedCache == cache then return cachedNames end
  cachedNames, cachedCache = {}, cache
  for name in pairs(cache) do cachedNames[#cachedNames + 1] = name end
  table.sort(cachedNames, function(a, b) return a:lower() < b:lower() or a:lower() == b:lower() and a < b end)
  return cachedNames
end
if spellCache.AddIcon then
  hooksecurefunc(spellCache, "AddIcon", function() cachedNames, cachedCache = nil, nil end)
end

function OptionsPrivate.IconPickerPageSize(width, height)
  local columns = math.max(1, math.floor(math.max(0, width) / 52))
  local rows = math.max(1, math.floor(math.max(0, height - 3) / 55))
  return math.min(96, columns * rows)
end

function OptionsPrivate.IconPickerResults(query, baseObject, paths, groupIcon, limit)
  limit = math.max(1, math.min(96, math.floor(tonumber(limit) or 96)))
  local results, used = {}, {}
  local private = OptionsPrivate.Private
  local function Add(name, icon)
    icon = tonumber(icon) or icon
    if #results >= limit or used[icon] or (type(icon) ~= "number" and type(icon) ~= "string") then return end
    if type(icon) == "number" and (icon <= 0 or icon >= math.huge or icon ~= icon) or icon == "" then return end
    used[icon] = true
    results[#results + 1] = {name = name or tostring(icon), icon = icon}
  end
  local function AddSpell(spell)
    if type(spell) ~= "string" and type(spell) ~= "number" then return end
    if type(spell) == "number" and (spell <= 0 or spell >= math.huge or spell ~= spell) or spell == "" then return end
    local name, _, icon = private.ExecEnv.GetSpellInfo(spell)
    if name and icon and icon ~= 136243 then Add(name, icon) end
  end
  local function AddAura(aura)
    if not aura then return end
    local path = paths and paths[aura.id]
    if path then Add(aura.id, private.ValueFromPath(aura, path)) end
    Add(aura.id, aura.displayIcon)
    Add(aura.id, aura.icon)
    for _, entry in ipairs(aura.triggers or {}) do
      local trigger = entry.trigger
      if trigger then
        AddSpell(trigger.spellId)
        for _, key in ipairs({"spellIds", "spellNames", "auraspellids", "auranames"}) do
          if type(trigger[key]) == "table" then
            for _, spell in ipairs(trigger[key]) do AddSpell(spell) end
          end
        end
      end
    end
  end
  query = tostring(query or ""):match("^%s*(.-)%s*$")
  local number = tonumber(query)
  if number then AddSpell(number); return results end
  if query == "" then
    if baseObject then
      if groupIcon then
        AddAura(baseObject)
      else
        for aura in private.TraverseLeafsOrAura(baseObject) do
          AddAura(aura)
          if #results >= limit then return results end
        end
      end
    end
    if IsSpellKnown then
      for _, id in ipairs(private.AuraSpellCatalogIDs or {}) do
        if IsSpellKnown(id) then AddSpell(id) end
        if #results >= limit then return results end
      end
    end
  else
    AddSpell(query)
  end
  local cache = spellCache.Get()
  local lower = query:lower()
  for _, name in ipairs(CacheNames(cache)) do
    if lower == "" or name:lower():find(lower, 1, true) then
      for _, key in ipairs({"spells", "achievements"}) do
        for _, icon in (cache[name][key] or ""):gmatch("(%d+)=(%d+)") do
          Add(name, tonumber(icon))
          if #results >= limit then return results end
        end
      end
    end
  end
  if query == "" and #results < limit then
    for _, id in ipairs(private.AuraSpellCatalogIDs or {}) do
      AddSpell(id)
      if #results >= limit then break end
    end
  end
  return results
end

local function ConstructIconPicker(frame)
  local Theme = OptionsPrivate.Theme
  local modern = Theme.IsModern()
  local group = AceGUI:Create(modern and "SimpleGroup" or "InlineGroup")
  group.noAutoHeight = true
  group.frame:SetParent(frame);
  group.frame.faModernPanel = true
  group.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -17, 46);
  group.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, modern and -43 or -50);
  if modern then
    group.content:ClearAllPoints()
    group.content:SetPoint("TOPLEFT", group.frame, "TOPLEFT", 8, -44)
    group.content:SetPoint("BOTTOMRIGHT", group.frame, "BOTTOMRIGHT", -8, 8)
    local separator = Theme.Solid(group.frame, "ARTWORK", Theme.colors.border)
    separator:SetPoint("TOPLEFT", group.frame, "TOPLEFT", 8, -36)
    separator:SetPoint("TOPRIGHT", group.frame, "TOPRIGHT", -8, -36)
    Theme.PixelHeight(separator, 1)
  end
  group.frame:Hide();
  group:SetLayout("fill");

  local scroll = AceGUI:Create("ScrollFrame");
  scroll:SetLayout("flow");
  scroll.frame.faModernScroll = true
  function scroll:FixScroll()
    if self.updateLock then return end
    self.updateLock = true
    local height, viewheight = self.content:GetHeight(), self.scrollframe:GetHeight()
    local overflow = height > viewheight + 2
    local reserve = overflow and (modern and Theme.Pixel(self.frame, 22) or 20) or 0
    local changed = self.scrollBarShown ~= (overflow or nil)
    self.scrollBarShown = overflow or nil
    self.scrollbar:SetShown(overflow)
    self.scrollframe:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -reserve, 0)
    if self.content.original_width then self.content.width = self.content.original_width - reserve end
    if not overflow then
      self.scrollbar:SetValue(0)
      self:SetScroll(0)
    else
      local status = self.status or self.localstatus
      local value = math.max(0, math.min(1000, (status.offset or 0) / (height - viewheight) * 1000))
      self.scrollbar:SetValue(value)
      self:SetScroll(value)
    end
    if changed then self:DoLayout() end
    self.updateLock = nil
  end
  scroll.frame:SetClipsChildren(true);
  group:AddChild(scroll);

  local input
  local fillGeneration, pageSize = 0, 0
  local function PageSize()
    local width, height = scroll.scrollframe:GetSize()
    return OptionsPrivate.IconPickerPageSize(width, height)
  end
  local function iconPickerFill(subname)
    pageSize = PageSize()
    scroll:PauseLayout()
    scroll:ReleaseChildren()
    scroll:SetScroll(0)
    for _, entry in ipairs(OptionsPrivate.IconPickerResults(subname, group.baseObject, group.paths, group.groupIcon, pageSize)) do
      local button = AceGUI:Create("ForeverAurasIconButton")
      button:SetName(entry.name)
      button:SetTexture(entry.icon)
      button:SetClick(function() group:Pick(entry.icon) end)
      scroll:AddChild(button)
    end
    scroll:ResumeLayout()
    scroll:DoLayout()
    Theme.ApplyFont(group.frame)
  end
  local function ScheduleFill(delay)
    fillGeneration = fillGeneration + 1
    local generation = fillGeneration
    C_Timer.After(delay, function()
      if generation == fillGeneration and group.frame:IsVisible() then iconPickerFill(input:GetText()) end
    end)
  end
  group.frame:HookScript("OnHide", function() fillGeneration = fillGeneration + 1 end)
  scroll.scrollframe:HookScript("OnSizeChanged", function()
    if input and group.frame:IsVisible() then
      C_Timer.After(0, function()
        if group.frame:IsVisible() and PageSize() ~= pageSize then ScheduleFill(0) end
      end)
    end
  end)

  input = CreateFrame("EditBox", "ForeverAurasFilterInput", group.frame, "SearchBoxTemplate")
  input.faModernInput, input.faModernSearch = true, true
  local resettingInput = false
  input:SetScript("OnTextChanged", function(self)
    SearchBoxTemplate_OnTextChanged(self)
    if not resettingInput then ScheduleFill(0.15) end
  end);
  input:SetScript("OnEnterPressed", function() fillGeneration = fillGeneration + 1; iconPickerFill(input:GetText()) end);
  input:SetScript("OnEscapePressed", function()
    input:SetText("")
    fillGeneration = fillGeneration + 1
    iconPickerFill("")
    input:ClearFocus()
  end);
  input:SetWidth(200);
  input:SetHeight(15);
  input:SetFont(STANDARD_TEXT_FONT, 10, "")
  if modern then
    input:SetPoint("TOPRIGHT", group.frame, "TOPRIGHT", -10, -7)
  else
    input:SetPoint("BOTTOMRIGHT", group.frame, "TOPRIGHT", -3, -10)
  end

  function OptionsPrivate.RefreshIconPicker()
    cachedNames, cachedCache = nil, nil
    if group.frame:IsVisible() then ScheduleFill(0) end
  end

  local icon = AceGUI:Create("ForeverAurasIconButton");
  icon.frame:Disable();
  icon.frame:SetParent(group.frame);
  if modern then
    icon.frame:SetPoint("TOPLEFT", group.frame, "TOPLEFT", 8, -4)
    icon:SetHeight(28)
    icon:SetWidth(28)
  else
    icon.frame:SetPoint("BOTTOMLEFT", group.frame, "TOPLEFT", 44, -15)
    icon:SetHeight(36)
    icon:SetWidth(36)
  end

  local iconLabel = input:CreateFontString(nil, "OVERLAY", modern and "GameFontHighlightSmall" or "GameFontNormalHuge");
  iconLabel:SetNonSpaceWrap("true");
  iconLabel:SetJustifyH("LEFT");
  iconLabel:SetPoint("LEFT", icon.frame, "RIGHT", modern and 8 or 5, 0);
  iconLabel:SetPoint("RIGHT", input, "LEFT", modern and -16 or -50, 0);
  if modern then iconLabel:SetMaxLines(1) end

  function group.Pick(self, texturePath)
    local valueToPath = OptionsPrivate.Private.ValueToPath
    if self.groupIcon then
      valueToPath(self.baseObject, self.paths[self.baseObject.id], texturePath)
      ForeverAuras.Add(self.baseObject)
      ForeverAuras.ClearAndUpdateOptions(self.baseObject.id)
      ForeverAuras.UpdateThumbnail(self.baseObject)
    else
      for child in OptionsPrivate.Private.TraverseLeafsOrAura(self.baseObject) do
        valueToPath(child, self.paths[child.id], texturePath)
        ForeverAuras.Add(child)
        ForeverAuras.ClearAndUpdateOptions(child.id)
        ForeverAuras.UpdateThumbnail(child);
      end
    end
    local success = icon:SetTexture(texturePath) and texturePath;
    if(success) then
      iconLabel:SetText(texturePath);
    else
      iconLabel:SetText();
    end
  end

  function group.Open(self, baseObject, paths, groupIcon)
    local valueFromPath = OptionsPrivate.Private.ValueFromPath
    self.baseObject = baseObject
    self.paths = paths
    self.groupIcon = groupIcon
    if groupIcon then
      local value = valueFromPath(self.baseObject, paths[self.baseObject.id])
      self.givenPath = value
    else
      self.givenPath = {};
      for child in OptionsPrivate.Private.TraverseLeafsOrAura(baseObject) do
        if child and paths[child.id] then
          local value = valueFromPath(child, paths[child.id])
          self.givenPath[child.id] = value or "";
        end
      end
    end
    local preview = groupIcon and self.givenPath or nil
    if not groupIcon then
      for child in OptionsPrivate.Private.TraverseLeafsOrAura(baseObject) do
        if self.givenPath[child.id] and self.givenPath[child.id] ~= "" then
          preview = self.givenPath[child.id]
          break
        end
      end
    end
    if preview and preview ~= "" then
      icon:SetTexture(preview)
      iconLabel:SetText(preview)
    else
      icon.texture:SetTexture(nil)
      iconLabel:SetText(nil)
    end
    frame.window = "icon";
    frame:UpdateFrameVisible()
    fillGeneration = fillGeneration + 1
    resettingInput = true
    input:SetText("")
    resettingInput = false
    iconPickerFill("")
  end

  function group.Close()
    frame.window = "default";
    frame:UpdateFrameVisible()
    ForeverAuras.FillOptions()
  end

  function group.CancelClose()
    local valueToPath = OptionsPrivate.Private.ValueToPath
    if group.groupIcon then
      valueToPath(group.baseObject, group.paths[group.baseObject.id], group.givenPath)
      ForeverAuras.Add(group.baseObject)
      ForeverAuras.ClearAndUpdateOptions(group.baseObject.id)
      ForeverAuras.UpdateThumbnail(group.baseObject)
    else
      for child in OptionsPrivate.Private.TraverseLeafsOrAura(group.baseObject) do
        if (group.givenPath[child.id]) then
          valueToPath(child, group.paths[child.id], group.givenPath[child.id])
          ForeverAuras.Add(child);
          ForeverAuras.ClearAndUpdateOptions(child.id)
          ForeverAuras.UpdateThumbnail(child);
        end
      end
    end

    group.Close();
  end

  local cancel = CreateFrame("Button", nil, group.frame, "UIPanelButtonTemplate");
  cancel:SetScript("OnClick", group.CancelClose);
  cancel:SetPoint("BOTTOMRIGHT", -20, -24)
  cancel:SetHeight(20);
  cancel:SetWidth(100);
  cancel:SetText(L["Cancel"]);

  local close = CreateFrame("Button", nil, group.frame, "UIPanelButtonTemplate");
  close:SetScript("OnClick", group.Close);
  close:SetPoint("RIGHT", cancel, "LEFT", -10, 0);
  close:SetHeight(20);
  close:SetWidth(100);
  close:SetText(L["Okay"]);

  return group
end

function OptionsPrivate.IconPicker(frame, noConstruct)
  iconPicker = iconPicker or (not noConstruct and ConstructIconPicker(frame))
  return iconPicker
end
