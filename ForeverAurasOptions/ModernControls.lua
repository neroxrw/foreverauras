if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local Theme = OptionsPrivate.Theme
local AceGUI = LibStub("AceGUI-3.0")
local MediaWidgets = LibStub("AceGUISharedMediaWidgets-1.0", true)
local LibDD = LibStub("LibUIDropDownMenu-4.0")
local states = setmetatable({}, {__mode = "k"})
local typography = setmetatable({}, {__mode = "k"})
local hookedWidgets = setmetatable({}, {__mode = "k"})
local pixelHeights = setmetatable({}, {__mode = "k"})
local thumbnailHooks = setmetatable({}, {__mode = "k"})
local colors = {
  background = {0.065, 0.075, 0.095, 1},
  menu = {0.085, 0.095, 0.12, 1},
  border = {0.34, 0.37, 0.43, 1},
  hover = {0.15, 0.18, 0.23, 1},
  pressed = {0.105, 0.13, 0.18, 1},
  text = {0.96, 0.97, 0.99, 1},
  disabled = {0.48, 0.51, 0.57, 1},
  green = {0.22, 0.9, 0.48, 1},
  mixed = {0.89, 0.72, 0.38, 1},
}

function Theme.Pixel(frame, pixels)
  local factor
  if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
    factor = PixelUtil.GetPixelToUIUnitFactor()
  elseif GetPhysicalScreenSize then
    local _, height = GetPhysicalScreenSize()
    factor = height and height > 0 and 768 / height or 1
  else
    factor = 1
  end
  return (pixels or 1) * factor / frame:GetEffectiveScale()
end

function Theme.Snap(frame, value)
  local pixel = Theme.Pixel(frame)
  return math.floor(value / pixel + 0.5) * pixel
end

function Theme.PixelHeight(region, pixels)
  pixelHeights[region] = pixels
  region:SetHeight(Theme.Pixel(region, pixels))
end

function Theme.ZoomIcon(icon)
  if not icon or not icon.SetTexCoord then return end
  local inset = Theme.IsModern() and 0.25 * 0.25 or 0
  local atlas = icon.GetAtlas and icon:GetAtlas()
  local query = C_Texture and C_Texture.GetAtlasInfo or GetAtlasInfo
  local info = atlas and query and query(atlas)
  if info then
    local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    icon:SetTexCoord(left + (right - left) * inset, right - (right - left) * inset, top + (bottom - top) * inset, bottom - (bottom - top) * inset)
  else
    icon:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
  end
end

function Theme.ZoomThumbnail(frame)
  if not Theme.IsModern() or not frame.icon then return end
  Theme.ZoomIcon(frame.icon)
  if type(frame.SetIcon) == "function" and thumbnailHooks[frame] ~= frame.SetIcon then
    hooksecurefunc(frame, "SetIcon", function() Theme.ZoomIcon(frame.icon) end)
    thumbnailHooks[frame] = frame.SetIcon
  end
end

function Theme.Readable(region)
  if not Theme.IsModern() or region.faKeepFont then return end
  local path, size, flags = region:GetFont()
  if not path or not size then return end
  local saved = typography[region]
  if not saved then
    saved = {size = size, flags = flags or "", shadow = {region:GetShadowColor()}, offset = {region:GetShadowOffset()}}
    typography[region] = saved
  end
  local target = math.max(Theme.Pixel(region, 10), Theme.Snap(region, math.max(12, saved.size)))
  region:SetFont(path, math.max(Theme.Pixel(region), target), saved.flags)
  region:SetShadowOffset(0, 0)
end

function Theme.RestoreReadable(region)
  local saved = typography[region]
  if not saved then return end
  local path = region:GetFont()
  if path then region:SetFont(path, saved.size, saved.flags) end
  region:SetShadowColor(unpack(saved.shadow))
  region:SetShadowOffset(unpack(saved.offset))
  typography[region] = nil
end

local function State(frame)
  local state = states[frame]
  if not state then
    state = {frame = frame, originals = {}, children = {}, active = true}
    states[frame] = state
    frame:HookScript("OnSizeChanged", function()
      if state.active and not state.layoutBusy then
        state.layoutBusy = true
        Theme.SkinFrame(frame)
        state.layoutBusy = false
        if Theme.QueueGeometry then Theme.QueueGeometry() end
      end
    end)
  end
  state.active = true
  return state
end

local function Track(state, child)
  for _, current in ipairs(state.children) do if current == child then return end end
  state.children[#state.children + 1] = child
end

local function Save(state, region)
  if not region or state.originals[region] then return end
  local saved = {alpha = region:GetAlpha(), points = {}, width = region:GetWidth(), height = region:GetHeight()}
  for index = 1, region:GetNumPoints() do saved.points[index] = {region:GetPoint(index)} end
  if region.GetTexture then
    saved.texture = region:GetTexture()
    saved.atlas = region.GetAtlas and region:GetAtlas()
    saved.coords = {region:GetTexCoord()}
    saved.color = {region:GetVertexColor()}
    saved.blend = region:GetBlendMode()
  elseif region.GetTextColor then
    saved.color = {region:GetTextColor()}
    saved.justify = region:GetJustifyH()
  end
  if region.GetTextInsets then saved.textInsets = {region:GetTextInsets()} end
  if region.IsMouseEnabled then saved.mouseEnabled = region:IsMouseEnabled() end
  if region.IsMouseWheelEnabled then saved.mouseWheelEnabled = region:IsMouseWheelEnabled() end
  if region.GetBackdrop then
    saved.backdrop = region:GetBackdrop()
    saved.backdropColor = {region:GetBackdropColor()}
    saved.borderColor = {region:GetBackdropBorderColor()}
  end
  state.originals[region] = saved
end

local function HideArt(state, region)
  if not region then return end
  Save(state, region)
  region:SetAlpha(0)
end

local function HideButtonArt(state, button)
  for _, name in ipairs({"Normal", "Pushed", "Highlight", "Disabled", "Checked", "DisabledChecked"}) do
    local getter = button["Get" .. name .. "Texture"]
    if getter then HideArt(state, getter(button)) end
  end
  for _, name in ipairs({"Left", "Middle", "Right", "LeftSeparator", "RightSeparator"}) do
    HideArt(state, button[name])
    local buttonName = button:GetName()
    if buttonName then HideArt(state, _G[buttonName .. name]) end
  end
end

local glyphShapes = {
  up = {width = 9, height = 5, runs = {{4, 0, 1}, {3, 1, 1}, {5, 1, 1}, {2, 2, 1}, {6, 2, 1}, {1, 3, 1}, {7, 3, 1}, {0, 4, 1}, {8, 4, 1}}},
  down = {width = 9, height = 5, runs = {{0, 0, 1}, {8, 0, 1}, {1, 1, 1}, {7, 1, 1}, {2, 2, 1}, {6, 2, 1}, {3, 3, 1}, {5, 3, 1}, {4, 4, 1}}},
  left = {width = 5, height = 9, runs = {{4, 0, 1}, {3, 1, 1}, {2, 2, 1}, {1, 3, 1}, {0, 4, 1}, {1, 5, 1}, {2, 6, 1}, {3, 7, 1}, {4, 8, 1}}},
  right = {width = 5, height = 9, runs = {{0, 0, 1}, {1, 1, 1}, {2, 2, 1}, {3, 3, 1}, {4, 4, 1}, {3, 5, 1}, {2, 6, 1}, {1, 7, 1}, {0, 8, 1}}},
  check = {width = 11, height = 9, runs = {{9, 0, 2}, {8, 1, 3}, {7, 2, 3}, {6, 3, 3}, {0, 4, 2}, {5, 4, 3}, {1, 5, 3}, {4, 5, 3}, {2, 6, 5}, {3, 7, 3}, {4, 8, 1}}},
  dash = {width = 9, height = 2, runs = {{0, 0, 9}, {0, 1, 9}}},
}

local function Glyph(state, parent, key, kind, color)
  local glyph = state[key]
  if not glyph then
    glyph = CreateFrame("Frame", nil, parent)
    glyph.faThemeOwned = true
    glyph:EnableMouse(false)
    glyph.dots = {}
    state[key] = glyph
  end
  local pixel = Theme.Pixel(glyph)
  local shape = glyphShapes[kind]
  glyph:SetSize(shape.width * pixel, shape.height * pixel)
  glyph.faGlyphKind = kind
  for index, run in ipairs(shape.runs) do
    local dot = glyph.dots[index]
    if not dot then
      dot = glyph:CreateTexture(nil, "OVERLAY")
      dot:SetColorTexture(1, 1, 1, 1)
      if dot.SetSnapToPixelGrid then dot:SetSnapToPixelGrid(false) end
      if dot.SetTexelSnappingBias then dot:SetTexelSnappingBias(0) end
      glyph.dots[index] = dot
    end
    dot:ClearAllPoints()
    dot:SetPoint("TOPLEFT", glyph, "TOPLEFT", run[1] * pixel, -run[2] * pixel)
    dot:SetSize(run[3] * pixel, pixel)
    dot:SetVertexColor(unpack(color))
    dot:Show()
  end
  for index = #shape.runs + 1, #glyph.dots do glyph.dots[index]:Hide() end
  glyph:Show()
  return glyph
end

local function Surface(state)
  if not state.surface then
    local surface = CreateFrame("Frame", nil, state.frame)
    surface.faThemeOwned = true
    surface.faBorderInset = true
    surface:EnableMouse(false)
    surface:SetFrameLevel(state.frame:GetFrameLevel())
    state.surface = surface
  end
  state.surface:Show()
  return state.surface
end

local function AnchorGlyph(glyph, anchor)
  glyph.faAnchor = anchor
  glyph:ClearAllPoints()
  local x, y = anchor:GetCenter()
  local ratio = anchor:GetEffectiveScale() / glyph:GetEffectiveScale()
  local left = x and x * ratio - glyph:GetWidth() / 2
  local top = y and y * ratio + glyph:GetHeight() / 2
  local dx = left and Theme.Snap(glyph, left) - left or 0
  local dy = top and Theme.Snap(glyph, top) - top or 0
  glyph:SetPoint("CENTER", anchor, "CENTER", dx, dy)
end

local geometryPending = false

function Theme.QueueGeometry()
  if geometryPending or not C_Timer or not C_Timer.After then return end
  geometryPending = true
  C_Timer.After(0, function()
    geometryPending = false
    for frame in pairs(Theme.flatFrames) do
      if frame:IsVisible() then Theme.RefreshBorder(frame) end
    end
    for frame, state in pairs(states) do
      if state.active and frame:IsVisible() then
        if state.surface then state.surface:SetFrameLevel(frame:GetFrameLevel()) end
        for _, key in ipairs({"mark", "arrow"}) do
          local glyph = state[key]
          if glyph and glyph.faAnchor then AnchorGlyph(glyph, glyph.faAnchor) end
        end
      end
    end
  end)
end

local function Enabled(state)
  local widget = state.widget
  local editbox = widget and (widget.editbox or widget.editBox)
  return not (widget and widget.disabled) and (not state.frame.IsEnabled or state.frame:IsEnabled())
    and (not editbox or not editbox.IsMouseEnabled or editbox:IsMouseEnabled())
end

local function Update(state)
  if not state.active then return end
  local enabled = Enabled(state)
  local background = state.frame.faModernBackground or (not enabled and colors.background or state.pressed and colors.pressed or state.hovered and colors.hover or colors.background)
  local border = enabled and (state.hovered or state.pressed or state.focused) and Theme.colors.accent or colors.border
  if state.surface then Theme.Flat(state.surface, background, not state.noBorder and border or nil) end
  if state.arrow then
    for _, dot in ipairs(state.arrow.dots) do dot:SetVertexColor(unpack(enabled and colors.text or colors.disabled)) end
  end
  if state.text then
    state.text:SetTextColor(unpack(enabled and (state.text.faModernTextColor or colors.text) or colors.disabled))
    Theme.Readable(state.text)
  end
  if state.checkbox then
    local widget = state.widget
    local checked = widget and widget.checked or state.frame.GetChecked and state.frame:GetChecked()
    local mixed = widget and widget.tristate and widget.checked == nil
    local mark = Glyph(state, state.frame, "mark", mixed and "dash" or "check", enabled and (mixed and colors.mixed or colors.green) or colors.disabled)
    AnchorGlyph(mark, state.surface)
    mark:SetShown(checked or mixed or false)
  end
end

local function HookControl(state, button)
  if not button or button.faModernControlHook then return end
  button.faModernControlHook = true
  button:HookScript("OnEnter", function()
    state.hovered = true
    Update(state)
  end)
  button:HookScript("OnLeave", function()
    state.hovered, state.pressed = false, false
    Update(state)
  end)
  button:HookScript("OnMouseDown", function()
    state.pressed = true
    Update(state)
  end)
  button:HookScript("OnMouseUp", function()
    state.pressed = false
    Update(state)
  end)
  if button:IsObjectType("Button") then
    button:HookScript("OnEnable", function() Update(state) end)
    button:HookScript("OnDisable", function() Update(state) end)
  end
end

local function HookWidget(state)
  local widget = state.widget
  if not widget or hookedWidgets[widget] then return end
  hookedWidgets[widget] = true
  for _, name in ipairs({"SetDisabled", "SetValue", "SetTriState", "SetType", "SetLabel", "SetText", "DisableButton", "SetNumLines", "SetSpinBoxValues", "SetIsPercent"}) do
    if type(widget[name]) == "function" then
      hooksecurefunc(widget, name, function()
        if state.active then Theme.SkinFrame(state.frame) end
      end)
    end
  end
end

local function SkinCheckbox(frame, widget)
  local state = State(frame)
  state.widget, state.checkbox = widget, true
  local surface = Surface(state)
  surface:ClearAllPoints()
  local size = math.max(Theme.Pixel(frame, 16), Theme.Snap(frame, 16))
  surface:SetSize(size, size)
  surface:SetPoint("CENTER", widget and widget.checkbg or frame, "CENTER")
  if widget then
    HideArt(state, widget.checkbg)
    HideArt(state, widget.check)
    HideArt(state, widget.highlight)
    state.text = widget.text
    Save(state, state.text)
    HookWidget(state)
  else
    HideButtonArt(state, frame)
    if not frame.faModernCheckedHook then
      frame.faModernCheckedHook = true
      hooksecurefunc(frame, "SetChecked", function() Update(state) end)
    end
  end
  HookControl(state, frame)
  Update(state)
end

local function SkinSlider(slider)
  if not slider then return end
  local state = State(slider)
  Save(state, slider)
  if slider.SetBackdrop then slider:SetBackdrop(nil) end
  local thumb = slider:GetThumbTexture()
  if thumb then
    Save(state, thumb)
    thumb:SetTexture(Theme.WHITE)
    thumb:SetTexCoord(0, 1, 0, 1)
    thumb:SetVertexColor(0.48, 0.52, 0.6, 1)
    thumb:SetSize(Theme.Snap(slider, 6), Theme.Snap(slider, 22))
  end
  Theme.Flat(slider, colors.background, nil)
end

local function MirrorMark(state, texture, key, kind)
  if not texture then return end
  HideArt(state, texture)
  local mark = Glyph(state, state.frame, key, kind, colors.green)
  AnchorGlyph(mark, texture)
  mark:SetShown(texture:IsShown())
  if not texture.faModernMarkHook then
    texture.faModernMarkHook = true
    local function Refresh()
      if state.active then
        local current = state[key]
        if current then current:SetShown(texture:IsShown()) end
      end
    end
    hooksecurefunc(texture, "Show", Refresh)
    hooksecurefunc(texture, "Hide", Refresh)
    hooksecurefunc(texture, "SetShown", Refresh)
  end
end

local function SkinMenuRow(frame, widget)
  local state = State(frame)
  state.widget = widget
  local highlight = widget and widget.highlight or frame.GetHighlightTexture and frame:GetHighlightTexture()
  if highlight then
    Save(state, highlight)
    highlight:SetTexture(Theme.WHITE)
    highlight:SetTexCoord(0, 1, 0, 1)
    highlight:SetBlendMode("BLEND")
    highlight:SetVertexColor(0.7, 0.78, 0.95, 0.14)
  end
  local check = widget and widget.check or frame.check or frame.Check
  local name = frame:GetName()
  check = check or name and _G[name .. "Check"]
  MirrorMark(state, check, "mark", "check")
  local uncheck = frame.UnCheck or name and _G[name .. "UnCheck"]
  HideArt(state, uncheck)
  local arrow = widget and widget.sub or frame.ExpandArrow or name and _G[name .. "ExpandArrow"]
  if arrow then
    MirrorMark(state, arrow, "arrow", "right")
    for _, dot in ipairs(state.arrow.dots) do dot:SetVertexColor(unpack(colors.text)) end
  end
  Theme.ApplyFont(frame)
  if widget and widget.submenu then Theme.SkinMenu(widget.submenu.frame, widget.submenu) end
end

local function LayoutNativeMenu(frame, rows)
  local menuState = states[frame]
  if menuState.layoutBusy then return end
  menuState.layoutBusy = true
  table.sort(rows, function(a, b) return a:GetID() < b:GetID() end)
  local padding = math.max(Theme.Snap(frame, 7), Theme.Pixel(frame, 5))
  local width, entries = 0, {}
  for _, row in ipairs(rows) do
    if row:IsShown() and not row.customFrame then
      local state = states[row]
      local text = row:GetFontString()
      Save(state, row)
      Save(state, text)
      local _, fontSize = text:GetFont()
      local arrow = row.ExpandArrow
      local icon = row.Icon or row:GetName() and _G[row:GetName() .. "Icon"]
      local swatch = row.ColorSwatch
      local left = row.notCheckable and Theme.Snap(row, 6) or math.max(Theme.Snap(row, 24), Theme.Pixel(row, 20))
      local right = Theme.Snap(row, 6)
      local extras = {}
      for _, region in ipairs({arrow or false, swatch or false, icon or false}) do
        if region and region:IsShown() then
          Save(state, region)
          local size = math.max(Theme.Snap(row, 16), Theme.Pixel(row, 14))
          extras[#extras + 1] = {region = region, size = size, offset = right}
          right = right + size + Theme.Pixel(row, 4)
        end
      end
      local textWidth = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
      local naturalWidth = math.ceil((textWidth + left + right) / Theme.Pixel(row)) * Theme.Pixel(row)
      width = math.max(width, naturalWidth, row.minWidth or 0)
      entries[#entries + 1] = {
        row = row, text = text, left = left, right = right, extras = extras,
        height = math.ceil(math.max(state.originals[row].height, (fontSize or 12) + Theme.Pixel(row, 5)) / Theme.Pixel(row)) * Theme.Pixel(row)
      }
    end
  end
  local offset = padding
  for _, entry in ipairs(entries) do
    local row, text = entry.row, entry.text
    local state = states[row]
    state.layoutBusy = true
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -offset)
    row:SetSize(width, entry.height)
    text:ClearAllPoints()
    text:SetPoint("LEFT", row, "LEFT", entry.left, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -entry.right, 0)
    text:SetHeight(entry.height)
    text:SetJustifyH("LEFT")
    for _, extra in ipairs(entry.extras) do
      extra.region:ClearAllPoints()
      extra.region:SetPoint("RIGHT", row, "RIGHT", -extra.offset, 0)
      extra.region:SetSize(extra.size, extra.size)
    end
    if state.arrow and row.ExpandArrow then AnchorGlyph(state.arrow, row.ExpandArrow) end
    if state.mark and row.Check then AnchorGlyph(state.mark, row.Check) end
    state.layoutBusy = false
    offset = offset + entry.height
  end
  if #entries > 0 then frame:SetSize(width + padding * 2, offset + padding) end
  menuState.layoutBusy = false
end

function Theme.SkinMenu(frame, pullout)
  if not Theme.IsModern() or not frame then return end
  local state = State(frame)
  state.menu = true
  state.pullout = pullout
  Save(state, frame)
  if frame.SetBackdrop then frame:SetBackdrop(nil) end
  HideArt(state, frame.Backdrop)
  HideArt(state, frame.MenuBackdrop)
  local surface = Surface(state)
  surface:SetAllPoints(frame)
  Theme.Flat(surface, colors.menu, colors.border)
  local slider = pullout and pullout.slider or frame.slider
  if slider then
    Track(state, slider)
    SkinSlider(slider)
  end
  local rows = pullout and pullout.items or frame.contentRepo
  if rows then
    for _, entry in ipairs(rows) do
      local row = pullout and entry.frame or entry
      Track(state, row)
      SkinMenuRow(row, pullout and entry or nil)
    end
  else
    local nativeRows = {}
    for _, row in ipairs({frame:GetChildren()}) do
      if row:IsObjectType("Button") and row:GetFontString() then
        Track(state, row)
        SkinMenuRow(row)
        nativeRows[#nativeRows + 1] = row
      end
    end
    LayoutNativeMenu(frame, nativeRows)
  end
  Theme.ApplyFont(frame)
end

local function SkinDropdown(frame, widget)
  local state = State(frame)
  state.widget = widget
  local media = frame.dropButton ~= nil
  local button = media and frame.dropButton or widget.button
  local surface = Surface(state)
  surface:ClearAllPoints()
  local left = media and frame.displayButton or nil
  surface:SetPoint("BOTTOMLEFT", left or frame, left and "BOTTOMRIGHT" or "BOTTOMLEFT", left and 2 or 0, 2)
  surface:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
  surface:SetHeight(Theme.Snap(frame, 22))
  if media then
    HideArt(state, frame.DLeft)
    HideArt(state, frame.DMiddle)
    HideArt(state, frame.DRight)
  else
    local name = widget.dropdown:GetName()
    for _, side in ipairs({"Left", "Middle", "Right"}) do HideArt(state, _G[name .. side]) end
  end
  HideButtonArt(state, button)
  local text = media and frame.text or widget.text
  Save(state, text)
  text:ClearAllPoints()
  text:SetPoint("LEFT", surface, "LEFT", Theme.Snap(frame, 7), 0)
  text:SetPoint("RIGHT", surface, "RIGHT", -Theme.Snap(frame, 26), 0)
  text:SetJustifyH("LEFT")
  state.text = text
  Save(state, button)
  button:ClearAllPoints()
  button:SetPoint("TOPRIGHT", surface, "TOPRIGHT")
  button:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT")
  button:SetWidth(Theme.Snap(frame, 24))
  local arrow = Glyph(state, button, "arrow", "down", colors.text)
  AnchorGlyph(arrow, button)
  HookControl(state, button)
  HookControl(state, widget.button_cover)
  HookWidget(state)
  if widget.pullout then
    local pullout = widget.pullout
    if not pullout.faModernOpenHook then
      pullout.faModernOpenHook = true
      hooksecurefunc(pullout, "Open", function()
        local owner = pullout.userdata.obj
        local current = owner and states[owner.frame]
        if current and current.active then Theme.SkinMenu(pullout.frame, pullout) end
      end)
    end
  elseif media and not button.faModernMenuHook then
    button.faModernMenuHook = true
    button:HookScript("OnClick", function()
      if state.active and widget.dropdown then Theme.SkinMenu(widget.dropdown) end
    end)
  end
  Update(state)
end

local function SkinButton(frame, widget)
  local state = State(frame)
  state.widget = widget
  HideButtonArt(state, frame)
  local surface = Surface(state)
  surface:ClearAllPoints()
  surface:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
  surface:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
  state.text = widget and widget.title or frame:GetFontString()
  Save(state, state.text)
  HookControl(state, frame)
  HookWidget(state)
  Update(state)
end

local function HookInput(state, editbox)
  if editbox.faModernInputHook then return end
  editbox.faModernInputHook = true
  editbox:HookScript("OnEditFocusGained", function()
    state.focused = true
    Update(state)
  end)
  editbox:HookScript("OnEditFocusLost", function()
    state.focused = false
    Update(state)
  end)
  local function Refresh()
    if state.active and state.singleInput then Theme.SkinFrame(state.frame) end
  end
  for _, event in ipairs({"OnTextChanged", "OnEnterPressed", "OnReceiveDrag"}) do editbox:HookScript(event, Refresh) end
  if state.widget and state.widget.button then state.widget.button:HookScript("OnClick", Refresh) end
end

local function SkinInput(frame, widget)
  local editbox = widget.editbox
  local state = State(frame)
  state.widget, state.text, state.singleInput = widget, editbox, true
  Save(state, editbox)
  for _, region in ipairs({editbox:GetRegions()}) do
    if region:IsObjectType("Texture") then HideArt(state, region) end
  end
  local surface = Surface(state)
  surface:ClearAllPoints()
  surface:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 2)
  surface:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
  surface:SetHeight(Theme.Snap(frame, 22))
  editbox:ClearAllPoints()
  editbox:SetPoint("TOPLEFT", surface, "TOPLEFT", Theme.Pixel(frame), -Theme.Pixel(frame))
  editbox:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -Theme.Pixel(frame), Theme.Pixel(frame))
  local right = widget.button and widget.button:IsShown() and widget.button:GetWidth() + 4 or 6
  editbox:SetTextInsets(Theme.Snap(editbox, 6), Theme.Snap(editbox, right), 0, 0)
  HookControl(state, editbox)
  HookInput(state, editbox)
  HookWidget(state)
  Update(state)
end

local function SkinMultiInput(frame, widget)
  local state = State(frame)
  state.widget, state.text = widget, widget.editBox
  Save(state, widget.editBox)
  local background, scroll, bar = widget.scrollBG, widget.scrollFrame, widget.scrollBar
  Save(state, background)
  Save(state, scroll)
  if background.SetBackdrop then background:SetBackdrop(nil) end
  local path = widget.userdata and widget.userdata.path
  state.noScrollbar = type(path) == "table" and path[#path] == "description"
  local top = (widget.labelHeight and widget.labelHeight > 0 and 20 or 2) + (frame.faEditorSearchHeight or 0)
  local bottom = widget.disablebutton and 4 or (widget.button:GetHeight() + 6)
  local right = state.noScrollbar and 0 or 18
  background:ClearAllPoints()
  background:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -Theme.Snap(frame, top))
  background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Theme.Snap(frame, right), Theme.Snap(frame, bottom))
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", background, "TOPLEFT", Theme.Snap(frame, 6), -Theme.Snap(frame, 6))
  scroll:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", -Theme.Snap(frame, 6), Theme.Snap(frame, 6))
  local surface = Surface(state)
  surface:SetAllPoints(background)
  if state.noScrollbar then
    Save(state, bar)
    if not state.hiddenBar then
      state.hiddenBar, state.hiddenBarShown = bar, bar:IsShown()
      state.wheelScript = scroll:GetScript("OnMouseWheel")
    end
    bar:Hide()
    bar:EnableMouse(false)
    if not bar.faModernHiddenHook then
      bar.faModernHiddenHook = true
      bar:HookScript("OnShow", function()
        if state.active and state.noScrollbar then bar:Hide() end
      end)
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(view, delta)
      if not state.active or not state.noScrollbar then return end
      local _, size = widget.editBox:GetFont()
      local range = view:GetVerticalScrollRange()
      local nextOffset = view:GetVerticalScroll() - delta * (size or 12) * 3
      view:SetVerticalScroll(math.max(0, math.min(range, nextOffset)))
    end)
  else
    if not state.barTracked then Track(state, bar); state.barTracked = true end
    SkinSlider(bar)
    local name = bar:GetName()
    for _, suffix in ipairs({"ScrollUpButton", "ScrollDownButton"}) do
      HideArt(state, bar[suffix] or name and _G[name .. suffix])
    end
  end
  HookControl(state, widget.editBox)
  HookInput(state, widget.editBox)
  HookWidget(state)
  Update(state)
end

local function SkinArrowButton(button, direction, embedded)
  local state = State(button)
  state.noBorder = embedded == true
  HideButtonArt(state, button)
  HideArt(state, button:GetFontString())
  local surface = Surface(state)
  surface:ClearAllPoints()
  local inset = embedded and Theme.Pixel(button, 2) or 0
  surface:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
  surface:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
  local arrow = Glyph(state, button, "arrow", direction, colors.text)
  AnchorGlyph(arrow, button)
  HookControl(state, button)
  Update(state)
end

local function SkinScrollFrame(frame, widget)
  local state = State(frame)
  state.widget = widget
  local bar = widget.scrollbar
  if not bar then return end
  Track(state, bar)
  SkinSlider(bar)
  local barState = states[bar]
  local thumb = bar:GetThumbTexture()
  for _, region in ipairs({bar:GetRegions()}) do
    local owned = region == thumb or bar.faSkin and region == bar.faSkin.bg
    for _, edge in ipairs(bar.faSkin and bar.faSkin.edges or {}) do owned = owned or region == edge end
    if region:IsObjectType("Texture") and not owned then HideArt(barState, region) end
  end
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", widget.scrollframe, "TOPRIGHT", Theme.Pixel(bar, 4), -Theme.Pixel(bar, 18))
  bar:SetPoint("BOTTOMLEFT", widget.scrollframe, "BOTTOMRIGHT", Theme.Pixel(bar, 4), Theme.Pixel(bar, 18))
  bar:SetWidth(Theme.Pixel(bar, 6))
  if thumb then thumb:SetSize(Theme.Pixel(bar, 6), Theme.Pixel(bar, 22)) end
  local name = bar:GetName()
  for _, entry in ipairs({{"ScrollUpButton", "up", "BOTTOM", "TOP", 2}, {"ScrollDownButton", "down", "TOP", "BOTTOM", -2}}) do
    local button = bar[entry[1]] or name and _G[name .. entry[1]]
    if button then
      Save(state, button)
      Track(state, button)
      button:ClearAllPoints()
      button:SetPoint(entry[3], bar, entry[4], 0, Theme.Pixel(bar, entry[5]))
      button:SetSize(Theme.Pixel(bar, 14), Theme.Pixel(bar, 14))
      SkinArrowButton(button, entry[2], true)
    end
  end
  if not frame.faModernScrollHook then
    frame.faModernScrollHook = true
    hooksecurefunc(widget, "FixScroll", function()
      if state.active then Theme.SkinFrame(frame) end
    end)
  end
end

local function SkinCloseButton(state, button)
  if not button then return end
  Save(state, button)
  for _, name in ipairs({"Normal", "Pushed", "Highlight", "Disabled"}) do
    local getter = button["Get" .. name .. "Texture"]
    if getter then Save(state, getter(button)) end
  end
  Theme.SkinGlyphButton(button, "close")
end

function Theme.SkinPanel(frame)
  if not Theme.IsModern() then return end
  local state = State(frame)
  Save(state, frame)
  state.originals[frame].keepGeometry = true
  if frame.SetBackdrop then frame:SetBackdrop(nil) end
  for _, region in ipairs({frame:GetRegions()}) do
    if region:IsObjectType("Texture") then HideArt(state, region) end
  end
  for _, key in ipairs({"NineSlice", "Border", "PortraitContainer", "Inset", "TopTileStreaks"}) do
    HideArt(state, frame[key])
  end
  local surface = Surface(state)
  surface:SetAllPoints(frame)
  Theme.Flat(surface, colors.menu, colors.border)
  SkinCloseButton(state, frame.CloseButton)
  if frame.CloseButton then
    frame.CloseButton:ClearAllPoints()
    frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Theme.Snap(frame, 4), -Theme.Snap(frame, 4))
    frame.CloseButton:SetSize(Theme.Snap(frame, 20), Theme.Snap(frame, 20))
  end
end

local function SkinNativeInput(frame)
  local state = State(frame)
  state.text = frame
  Save(state, frame)
  local name = frame:GetName()
  local searchIcon = frame.searchIcon or frame.SearchIcon or name and _G[name .. "SearchIcon"]
  for _, region in ipairs({frame:GetRegions()}) do
    if region:IsObjectType("Texture") and (not frame.faModernSearch or region ~= searchIcon) then HideArt(state, region) end
  end
  local surface = Surface(state)
  surface:SetAllPoints(frame)
  local inset = Theme.Snap(frame, 6)
  if frame.faModernSearch then
    frame:SetHeight(math.max(Theme.Snap(frame, 22), Theme.Pixel(frame, 18)))
    local clear = frame.clearButton or frame.ClearButton or name and _G[name .. "ClearButton"]
    SkinCloseButton(state, clear)
    if clear then
      clear:ClearAllPoints()
      clear:SetPoint("RIGHT", frame, "RIGHT", -Theme.Snap(frame, 3), 0)
      clear:SetSize(Theme.Snap(frame, 16), Theme.Snap(frame, 16))
    end
    if searchIcon then
      Save(state, searchIcon)
      searchIcon:ClearAllPoints()
      searchIcon:SetPoint("LEFT", frame, "LEFT", Theme.Snap(frame, 5), 0)
      searchIcon:SetSize(Theme.Snap(frame, 12), Theme.Snap(frame, 12))
    end
    frame:SetTextInsets(Theme.Snap(frame, 21), Theme.Snap(frame, 23), 0, 0)
  else
    frame:SetTextInsets(inset, inset, 0, 0)
  end
  HookInput(state, frame)
  HookControl(state, frame)
  Update(state)
end

local function SkinSpinBox(frame, widget)
  local state = State(frame)
  state.widget, state.text, state.spinbox, state.singleInput = widget, widget.editbox, true, false
  widget.modern = true
  Save(state, widget.editbox)
  for _, region in ipairs({widget.editbox:GetRegions()}) do
    if region:IsObjectType("Texture") then HideArt(state, region) end
  end
  local surface = Surface(state)
  surface:ClearAllPoints()
  surface:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 2)
  surface:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
  surface:SetHeight(Theme.Snap(frame, 22))
  local width = math.max(Theme.Snap(frame, 24), Theme.Pixel(frame, 18))
  for _, entry in ipairs({{widget.leftbutton, "LEFT", "left"}, {widget.rightbutton, "RIGHT", "right"}}) do
    local button, side, direction = entry[1], entry[2], entry[3]
    Save(state, button)
    button:ClearAllPoints()
    button:SetPoint("TOP" .. side, surface, "TOP" .. side)
    button:SetPoint("BOTTOM" .. side, surface, "BOTTOM" .. side)
    button:SetWidth(width)
    Track(state, button)
    SkinArrowButton(button, direction, true)
  end
  local editbox = widget.editbox
  editbox:ClearAllPoints()
  editbox:SetPoint("TOPLEFT", widget.leftbutton, "TOPRIGHT", Theme.Pixel(frame, 2), -Theme.Pixel(frame, 2))
  editbox:SetPoint("BOTTOMRIGHT", widget.rightbutton, "BOTTOMLEFT", -Theme.Pixel(frame, 2), Theme.Pixel(frame, 2))
  editbox:SetTextInsets(Theme.Pixel(frame, 2), Theme.Pixel(frame, 2), 0, 0)
  local progress = widget.progressBar
  Save(state, progress)
  progress:SetColorTexture(unpack(Theme.colors.accent))
  progress:SetAlpha(0.35)
  progress:ClearAllPoints()
  progress:SetPoint("BOTTOMLEFT", editbox, "BOTTOMLEFT")
  progress:SetHeight(Theme.Pixel(frame))
  local range = widget.max - widget.min
  local fraction = range > 0 and math.max(0, math.min(1, ((widget:GetValue() or 0) - widget.min) / range)) or 0
  progress:SetWidth(math.max(Theme.Pixel(frame), fraction * editbox:GetWidth()))
  local handle = widget.progressBarHandle
  Save(state, handle)
  handle:ClearAllPoints()
  handle:SetPoint("BOTTOMLEFT", editbox, "BOTTOMLEFT")
  handle:SetPoint("BOTTOMRIGHT", editbox, "BOTTOMRIGHT")
  local pixel = Theme.Pixel(frame)
  handle:SetHeight(math.max(pixel, math.min(pixel * 3, math.floor(editbox:GetHeight() / (pixel * 3)) * pixel)))
  local half = Theme.Pixel(frame, 4)
  local center = math.max(half, math.min(editbox:GetWidth() - half, progress:GetWidth()))
  handle:EnableMouse(not widget.disabled)
  Save(state, widget.progressBarHandleTexture)
  widget.progressBarHandleTexture:ClearAllPoints()
  widget.progressBarHandleTexture:SetPoint("BOTTOMLEFT", editbox, "BOTTOMLEFT", center - Theme.Pixel(frame), 0)
  widget.progressBarHandleTexture:SetSize(Theme.Pixel(frame, 2), handle:GetHeight())
  HookInput(state, editbox)
  HookControl(state, editbox)
  HookWidget(state)
  if not widget.faModernWidthHook then
    widget.faModernWidthHook = true
    hooksecurefunc(widget, "OnWidthSet", function() if state.active then Theme.SkinFrame(frame) end end)
  end
  Update(state)
end

function Theme.IsOptionsFrame(frame)
  local autocomplete = LibStub("LibAPIAutoComplete-1.0", true)
  while frame and frame ~= UIParent do
    if frame.faModernScope or states[frame] and states[frame].active and states[frame].menu then return true end
    if autocomplete and frame == autocomplete.scrollBox and autocomplete.editbox then return Theme.IsOptionsFrame(autocomplete.editbox) end
    frame = frame:GetParent()
  end
  return false
end

function Theme.SkinTooltip(frame)
  if not Theme.IsModern() then return end
  local state = State(frame)
  Save(state, frame)
  if frame.SetBackdrop then frame:SetBackdrop(nil) end
  HideArt(state, frame.NineSlice)
  HideArt(state, frame.Backdrop)
  local surface = Surface(state)
  surface:SetAllPoints(frame)
  Theme.Flat(surface, colors.menu, colors.border)
  Theme.QueueGeometry()
end

local function WatchTooltip(tooltip)
  if not tooltip or tooltip.faModernTooltipHook then return end
  tooltip.faModernTooltipHook = true
  hooksecurefunc(tooltip, "Show", function()
    if tooltip:IsForbidden() then return end
    if Theme.IsModern() and Theme.IsOptionsFrame(tooltip:GetOwner()) then Theme.SkinTooltip(tooltip) else Theme.RestoreSkin(tooltip) end
  end)
  tooltip:HookScript("OnHide", function() Theme.RestoreSkin(tooltip) end)
end

WatchTooltip(GameTooltip)
WatchTooltip(LibStub("AceConfigDialog-3.0").tooltip)

function Theme.AnimateLogo(badge, logo)
  if not Theme.IsModern() then return end
  local letters = {
    {80, 38, 2}, {29, 39, 41}, {80, 39, 2}, {29, 40, 40}, {79, 40, 3}, {29, 41, 39},
    {79, 41, 4}, {29, 42, 38}, {78, 42, 5}, {29, 43, 37}, {77, 43, 7}, {29, 44, 36},
    {76, 44, 8}, {29, 45, 36}, {76, 45, 9}, {29, 46, 6}, {75, 46, 10}, {29, 47, 6},
    {74, 47, 12}, {29, 48, 6}, {73, 48, 13}, {29, 49, 6}, {72, 49, 15}, {29, 50, 6},
    {72, 50, 15}, {29, 51, 6}, {71, 51, 17}, {29, 52, 6}, {70, 52, 8}, {80, 52, 8},
    {29, 53, 6}, {69, 53, 9}, {80, 53, 9}, {29, 54, 6}, {68, 54, 9}, {81, 54, 8},
    {29, 55, 6}, {53, 55, 2}, {58, 55, 2}, {68, 55, 8}, {81, 55, 9}, {29, 56, 30},
    {67, 56, 8}, {82, 56, 8}, {29, 57, 29}, {66, 57, 9}, {82, 57, 9}, {29, 58, 28},
    {65, 58, 9}, {83, 58, 8}, {29, 59, 27}, {65, 59, 8}, {83, 59, 9}, {29, 60, 26},
    {64, 60, 8}, {84, 60, 8}, {29, 61, 26}, {63, 61, 9}, {84, 61, 9}, {29, 62, 25},
    {62, 62, 9}, {85, 62, 8}, {29, 63, 6}, {61, 63, 9}, {85, 63, 9}, {29, 64, 6},
    {61, 64, 8}, {86, 64, 8}, {29, 65, 6}, {60, 65, 9}, {86, 65, 9}, {29, 66, 6},
    {59, 66, 9}, {87, 66, 8}, {29, 67, 6}, {58, 67, 10}, {79, 67, 2}, {87, 67, 9},
    {29, 68, 6}, {58, 68, 24}, {88, 68, 8}, {29, 69, 6}, {57, 69, 25}, {89, 69, 8},
    {29, 70, 6}, {56, 70, 26}, {89, 70, 8}, {29, 71, 6}, {55, 71, 28}, {90, 71, 8},
    {29, 72, 6}, {54, 72, 29}, {90, 72, 8}, {29, 73, 6}, {54, 73, 30}, {91, 73, 8},
    {29, 74, 6}, {53, 74, 9}, {83, 74, 1}, {91, 74, 8}, {29, 75, 6}, {52, 75, 9},
    {92, 75, 8}, {29, 76, 6}, {52, 76, 8}, {92, 76, 8}, {29, 77, 6}, {52, 77, 7},
    {93, 77, 8}, {29, 78, 6}, {52, 78, 6}, {93, 78, 9}, {29, 79, 6}, {52, 79, 6},
    {94, 79, 8}, {29, 80, 6}, {52, 80, 5}, {94, 80, 9}, {29, 81, 5}, {52, 81, 4},
    {95, 81, 8}, {29, 82, 4}, {52, 82, 3}, {95, 82, 8}, {29, 83, 3}, {52, 83, 2},
    {96, 83, 7}, {29, 84, 2}, {52, 84, 2}, {96, 84, 7}, {29, 85, 1}, {52, 85, 1},
    {97, 85, 6}, {97, 86, 5}, {98, 87, 4},
  }
  local layers, animations = {}, {}
  for index, color in ipairs({{0.30, 0.65, 0.89, 1}, {0.73, 0.47, 0.27, 1}}) do
    local layer = CreateFrame("Frame", nil, badge)
    layer.faThemeOwned = true
    layer:EnableMouse(false)
    layer:SetAllPoints(logo)
    layer.runs = {}
    for _, run in ipairs(letters) do
      local texture = layer:CreateTexture(nil, "OVERLAY")
      texture:SetColorTexture(unpack(color))
      if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
      if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
      layer.runs[#layer.runs + 1] = texture
    end
    local cycle = layer:CreateAnimationGroup()
    cycle:SetLooping("REPEAT")
    for order = 1, 2 do
      local fade = cycle:CreateAnimation("Alpha")
      local from = index == order and 1 or 0
      fade:SetOrder(order)
      fade:SetDuration(2.8)
      fade:SetFromAlpha(from)
      fade:SetToAlpha(1 - from)
      fade:SetSmoothing("IN_OUT")
    end
    layers[index], animations[index] = layer, cycle
  end
  local function Layout()
    for _, layer in ipairs(layers) do
      local width, height = badge:GetSize()
      for index, run in ipairs(letters) do
        local texture = layer.runs[index]
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", layer, "TOPLEFT", run[1] * width / 128, -run[2] * height / 128)
        texture:SetSize(run[3] * width / 128, height / 128)
      end
    end
  end
  local function Start()
    Layout()
    for index, cycle in ipairs(animations) do
      layers[index]:SetAlpha(index == 1 and 1 or 0)
      cycle:Play()
    end
  end
  badge:HookScript("OnSizeChanged", Layout)
  badge:HookScript("OnShow", Start)
  badge:HookScript("OnHide", function()
    for _, cycle in ipairs(animations) do cycle:Stop() end
  end)
  Layout()
  if badge:IsVisible() then Start() end
end

function Theme.SkinFrame(frame)
  if not Theme.IsModern() or frame.faThemeOwned then return end
  local widget = frame.obj
  if frame.faModernPanel then
    Theme.SkinPanel(frame)
  elseif frame.faModernTooltip then
    Theme.SkinTooltip(frame)
  elseif frame.faModernInput and frame:IsObjectType("EditBox") then
    SkinNativeInput(frame)
  elseif frame.faModernArrow then
    SkinArrowButton(frame, frame.faModernArrow)
  elseif widget and widget.frame == frame then
    if widget.type == "ScrollFrame" and frame.faModernScroll then
      SkinScrollFrame(frame, widget)
    elseif widget.type == "CheckBox" then
      SkinCheckbox(frame, widget)
    elseif widget.type == "Dropdown" or frame.dropButton then
      SkinDropdown(frame, widget)
    elseif widget.scrollBG and widget.scrollFrame and widget.editBox then
      SkinMultiInput(frame, widget)
    elseif widget.leftbutton and widget.rightbutton and widget.editbox then
      SkinSpinBox(frame, widget)
    elseif widget.editbox and widget.editbox:IsObjectType("EditBox") then
      SkinInput(frame, widget)
    elseif widget.type == "ForeverAurasSnippetButton" then
      SkinButton(frame, widget)
      local state = states[frame]
      Save(state, widget.title)
      widget.title:SetHeight(0)
      widget.renameEditBox.faModernInput = true
      SkinNativeInput(widget.renameEditBox)
      SkinCloseButton(state, widget.deleteButton)
    elseif widget.type == "Button" or widget.type == "Keybinding" then
      SkinButton(frame, widget)
    end
  elseif frame:IsObjectType("CheckButton") then
    SkinCheckbox(frame)
  elseif frame:IsObjectType("Button") and frame:GetFontString() then
    local name = frame:GetName()
    if frame.Left or name and _G[name .. "Left"] then SkinButton(frame) end
  end
  Theme.QueueGeometry()
end

function Theme.RestoreSkin(frame)
  local state = states[frame]
  if not state or not state.active then return end
  state.active = false
  state.hovered, state.pressed = false, false
  for _, child in ipairs(state.children) do
    Theme.RevertFont(child)
    Theme.RestoreSkin(child)
  end
  state.children = {}
  for region, saved in pairs(state.originals) do
    region:SetAlpha(saved.alpha)
    if not saved.keepGeometry then
      region:ClearAllPoints()
      region:SetSize(saved.width, saved.height)
      for _, point in ipairs(saved.points) do region:SetPoint(unpack(point)) end
    end
    if region.GetTexture then
      if saved.atlas then region:SetAtlas(saved.atlas) else region:SetTexture(saved.texture) end
      region:SetTexCoord(unpack(saved.coords))
      region:SetVertexColor(unpack(saved.color))
      region:SetBlendMode(saved.blend)
    elseif region.GetTextColor then
      region:SetTextColor(unpack(saved.color))
      region:SetJustifyH(saved.justify)
    end
    if saved.textInsets then region:SetTextInsets(unpack(saved.textInsets)) end
    if saved.mouseEnabled ~= nil then region:EnableMouse(saved.mouseEnabled) end
    if saved.mouseWheelEnabled ~= nil then region:EnableMouseWheel(saved.mouseWheelEnabled) end
    if region.SetBackdrop then
      region:SetBackdrop(saved.backdrop)
      if saved.backdrop then
        region:SetBackdropColor(unpack(saved.backdropColor))
        region:SetBackdropBorderColor(unpack(saved.borderColor))
      end
    end
  end
  state.originals = {}
  if state.hiddenBar then
    state.widget.scrollFrame:SetScript("OnMouseWheel", state.wheelScript)
    state.hiddenBar:SetShown(state.hiddenBarShown)
    state.hiddenBar, state.hiddenBarShown, state.wheelScript = nil, nil, nil
  end
  state.barTracked, state.focused = nil, false
  if state.spinbox and state.widget then state.widget.modern = nil end
  for _, key in ipairs({"surface", "arrow", "mark"}) do
    if state[key] then state[key]:Hide() end
  end
  if frame.faSkin then
    frame.faSkin.bg:Hide()
    for _, edge in ipairs(frame.faSkin.edges) do edge:Hide() end
  end
end

if MediaWidgets then
  hooksecurefunc(MediaWidgets, "ReturnDropDownFrame", function(_, frame)
    if states[frame] then Theme.RevertFont(frame); Theme.RestoreSkin(frame) end
  end)
end

hooksecurefunc(LibDD, "ToggleDropDownMenu", function()
  local owner = _G.L_UIDROPDOWNMENU_OPEN_MENU
  if not Theme.IsModern() or (owner ~= ForeverAuras_DropDownMenu and not Theme.IsOptionsFrame(owner)) then return end
  for level = 1, (_G.L_UIDROPDOWNMENU_MAXLEVELS or 3) do
    local menu = _G["L_DropDownList" .. level]
    if menu and menu:IsShown() then
      Theme.SkinMenu(menu)
      Theme.ApplyFont(menu)
      if not menu.faModernHideHook then
        menu.faModernHideHook = true
        menu:HookScript("OnHide", function() Theme.RevertFont(menu); Theme.RestoreSkin(menu) end)
      end
    end
  end
end)

local refresh = CreateFrame("Frame")
refresh:RegisterEvent("UI_SCALE_CHANGED")
refresh:RegisterEvent("DISPLAY_SIZE_CHANGED")
refresh:SetScript("OnEvent", function()
  for region, pixels in pairs(pixelHeights) do region:SetHeight(Theme.Pixel(region, pixels)) end
  for frame in pairs(Theme.flatFrames) do
    if frame:IsShown() then Theme.RefreshBorder(frame) end
  end
  for frame, state in pairs(states) do
    if state.active and frame:IsShown() then
      if state.menu then
        Theme.SkinMenu(frame, state.pullout)
      elseif frame:IsObjectType("Slider") then
        SkinSlider(frame)
      else
        Theme.ApplyFont(frame)
      end
    end
  end
end)
