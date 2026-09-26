-- Editor-only sample frames reuse native appearance styling without binding live auras.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = Private.BlizzardAuraDisplay

local function CreateSample(region)
  local button = CreateFrame("Frame", nil, region)
  button:EnableMouse(false)
  button.bindings = {}
  -- These adapters belong only to ordinary preview frames, never AuraContainer children.
  -- Appearance code can therefore bind the same icon, timer, name and stack widgets.
  for _, kind in ipairs({"Icon", "DurationText", "ApplicationCount", "SpellName", "DurationBar", "DurationCooldown"}) do
    button["Clear" .. kind] = function(self) self.bindings[kind] = {} end
    button["Set" .. kind] = function(self, widget, options)
      self.bindings[kind] = self.bindings[kind] or {}
      self.bindings[kind][#self.bindings[kind] + 1] = {widget = widget, options = options}
    end
  end
  function button:AddAuraShownAnimation(animation) animation:Play() end
  function button:RemoveAuraShownAnimation(animation) animation:Stop() end
  -- Preview the same Blizzard assets as the native bindings, using a public sample type.
  function button:AddDispelTypeTexture(texture, options)
    if options.style == Enum.CustomAuraButtonDispelTypeTextureStyle.Border then
      AuraUtil.SetAuraBorderAtlas(texture, "Magic", false)
    else
      AuraUtil.SetAuraDispelTypeIcon(texture, "Magic")
    end
    texture:SetVertexColor(1, 1, 1, 1)
    texture:Show()
  end
  local native = {button = button, preview = true}
  for _, area in ipairs({"inner", "outer"}) do
    native[area] = CreateFrame("Frame", nil, button)
    native[area]:SetPoint("CENTER", button, "CENTER")
  end
  native.border = button:CreateTexture(nil, "BACKGROUND")
  native.border:SetAllPoints(button)
  local base = CreateFrame("Frame", nil, button)
  base:SetAllPoints(button)
  native.elementFrames = {sharedBase = base}
  native.icon = base:CreateTexture(nil, "ARTWORK")
  native.cooldown = CreateFrame("Cooldown", nil, base, "CooldownFrameTemplate")
  native.cooldown:SetAllPoints(native.icon)
  native.cooldown:SetDrawBling(false)
  native.overlay = CreateFrame("Frame", nil, button)
  native.overlay:SetAllPoints(button)
  -- Loop sample progress just as the framework renews expired OPTIONS timers.
  -- Only shown samples receive OnUpdate; keep text and bars in step with the swipe.
  button:SetScript("OnUpdate", function(self, elapsed)
    if not ForeverAuras.IsOptionsOpen() then Display.HidePreview(region); return end
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.05 then return end
    self.elapsed = 0
    local now = GetTime()
    if not self.expires or self.expires <= now then
      self.expires = now + 6
      for _, entry in ipairs(self.bindings.DurationCooldown or {}) do entry.widget:SetCooldown(now, 6) end
    end
    local remaining = math.max(0, self.expires - now)
    for _, entry in ipairs(self.bindings.DurationText or {}) do
      entry.widget:SetText(remaining < 3 and string.format("%.1f", remaining) or tostring(math.ceil(remaining)))
    end
    for _, entry in ipairs(self.bindings.DurationBar or {}) do
      entry.widget:SetValue(self.inverse and 6 - remaining or remaining)
    end
  end)
  return native
end

function Display.HidePreview(region)
  region.secretAuraSamplesActive = false
  for _, sample in ipairs(region.secretAuraSamples or {}) do sample.button:Hide() end
end

function Display.ShowPreview(region, data, StyleSample)
  local ids = Display.GetSpellIDs(Display.GetTrigger(data), false)
  if #ids == 0 then ids[1] = false end
  local settings = data.blizzardAuraDisplay
  local count = math.min(#ids, settings.maxIcons or 10)
  local width, height = Display.Dimensions(data)
  local growth, spacing = settings.growth or "RIGHT", settings.spacing or 6
  local vertical = growth == "UP" or growth == "DOWN" or growth == "CENTER_VERTICAL"
  local centered = growth == "CENTER_HORIZONTAL" or growth == "CENTER_VERTICAL"
  local anchor = growth == "LEFT" and "TOPRIGHT" or growth == "UP" and "BOTTOMLEFT" or "TOPLEFT"
  region.secretAuraSamples = region.secretAuraSamples or {}
  Display.HidePreview(region)
  region.secretAuraSamplesActive = true
  for index = 1, count do
    local sample = region.secretAuraSamples[index] or CreateSample(region)
    region.secretAuraSamples[index] = sample
    local button = sample.button
    button.expires, button.inverse = GetTime() + 6, data.inverse == true
    local info = ids[index] and C_Spell.GetSpellInfo(ids[index])
    -- Use the configured entry once, not every expanded rank of that entry.
    sample.name, sample.iconID = info and info.name or "Aura", info and info.iconID or 134400
    StyleSample(sample, data)
    local offset = (index - 1 - (centered and (count - 1) / 2 or 0)) * ((vertical and height or width) + spacing)
    local x = not vertical and (growth == "LEFT" and -offset or offset) or 0
    local y = vertical and (growth == "UP" and offset or -offset) or 0
    button:ClearAllPoints()
    button:SetPoint(centered and "CENTER" or anchor, region, centered and "CENTER" or anchor, x, y)
    -- Like ordinary OPTIONS states, each sample has a six-second duration.
    for kind, entries in pairs(button.bindings) do
      for _, entry in ipairs(entries) do
        local widget = entry.widget
        if kind == "Icon" then widget:SetTexture(sample.iconID)
        elseif kind == "SpellName" then widget:SetText(sample.name)
        elseif kind == "ApplicationCount" then widget:SetText("3")
        elseif kind == "DurationText" then widget:SetText("6")
        elseif kind == "DurationBar" then
          widget:SetMinMaxValues(0, 6)
          widget:SetValue(data.inverse and 0 or 6)
        elseif kind == "DurationCooldown" then
          widget:SetCooldown(GetTime(), 6)
          widget:Show()
        end
      end
    end
    button:Show()
  end
end
