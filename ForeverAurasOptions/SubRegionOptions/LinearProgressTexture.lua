-- Modified for ForeverAuras; namespace and/or implementation changes through 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = ForeverAuras.L;

local function createOptions(parentData, data, index, subIndex)
  local pointAnchors = {}
  local areaAnchors = {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(pointAnchors, OptionsPrivate.Private.GetAnchorsForData(child, "point"))
    Mixin(areaAnchors, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end

  local options = {
    __title = L["Linear Texture %s"]:format(subIndex),
    __order = 1,
    linearTextureVisible = {
      type = "toggle",
      width = ForeverAuras.doubleWidth,
      name = L["Show Linear Texture"],
      order = 1,
    },
    linearTextureTexture = {
      type = "input",
      width = ForeverAuras.doubleWidth - 0.15,
      name = L["Texture"],
      order = 2,
    },
    chooseTexture = {
      type = "execute",
      width = 0.15,
      name = L["Choose"],
      order = 3,
      func = function()
        local path = { "subRegions", index }
        local paths = {}
        for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
          paths[child.id] = path
        end
        OptionsPrivate.OpenTexturePicker(parentData, paths, {
          texture = "linearTextureTexture",
          color = "linearTextureColor",
          blendMode = "linearTextureBlendMode"
        }, OptionsPrivate.Private.texture_types, nil)
      end,
      imageWidth = 24,
      imageHeight = 24,
      control = "ForeverAurasIcon",
      image = "Interface\\AddOns\\ForeverAuras\\Media\\Textures\\browse",
    },
    linearTextureOrientation = {
      type = "select",
      width = ForeverAuras.normalWidth,
      name = L["Orientation"],
      order = 4,
      values = OptionsPrivate.Private.orientation_types
    },
    linearTextureWrapMode = {
      type = "select",
      width = ForeverAuras.normalWidth,
      name = L["Texture Wrap"],
      order = 5,
      values = OptionsPrivate.Private.texture_wrap_types
    },
    linearTextureInverse = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Inverse"],
      order = 5.5,
    },
    linearTextureMirror = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Mirror"],
      order = 6,
    },
    linearTextureDesaturate = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Desaturate"],
      order = 7,
    },
    linearTextureColor = {
      type = "color",
      width = ForeverAuras.normalWidth,
      name = L["Color"],
      hasAlpha = true,
      order = 8,
    },
    linearTextureBlendMode = {
      type = "select",
      width = ForeverAuras.normalWidth,
      name = L["Blend Mode"],
      order = 9,
      values = OptionsPrivate.Private.blend_types
    },
    linearTextureUser_x = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      order = 11,
      name = L["Re-center X"],
      min = -0.5,
      max = 0.5,
      bigStep = 0.01,
    },
    linearTextureUser_y = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      order = 12,
      name = L["Re-center Y"],
      min = -0.5,
      max = 0.5,
      bigStep = 0.01,
    },
    linearTextureCrop_x = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Crop X"],
      order = 13,
      min = 0,
      softMax = 2,
      bigStep = 0.01,
      isPercent = true,
    },
    linearTextureCrop_y = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Crop Y"],
      order = 14,
      min = 0,
      softMax = 2,
      bigStep = 0.01,
      isPercent = true,
    },
    -- Doesn't appear to work
    linearTextureRotation = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Texture Rotation"],
      desc = L["Uses Texture Coordinates to rotate the texture."],
      order = 15,
      min = 0,
      max = 360,
      bigStep = 1
    },
    -- Doesn't appear to work
    linearTextureAuraRotation = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Rotation"],
      order = 16,
      min = 0,
      max = 360,
      bigStep = 1
    },

    -- Anchor Options added below
  }

  OptionsPrivate.commonOptions.ProgressOptionsForSubElement(parentData, data, options, 18)
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 19, areaAnchors, pointAnchors)

  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "sublineartexture")

  return options
end

  ForeverAuras.RegisterSubRegionOptions("sublineartexture", createOptions, L["Shows a Linear Progress Texture"]);
