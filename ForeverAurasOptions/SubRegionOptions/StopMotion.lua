-- Modified for ForeverAuras, 2026-09-18.
if not ForeverAuras.IsLibsOK() then return end
---@type string
local AddonName = ...
---@class OptionsPrivate
local OptionsPrivate = select(2, ...)

local L = ForeverAuras.L;

local texture_types = ForeverAuras.StopMotion.texture_types
local texture_data = ForeverAuras.StopMotion.texture_data
local animation_types = ForeverAuras.StopMotion.animation_types

local function createOptions(parentData, data, index, subIndex)

  local pointAnchors = {}
  local areaAnchors = {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(pointAnchors, OptionsPrivate.Private.GetAnchorsForData(child, "point"))
    Mixin(areaAnchors, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end

  local textureNameHasData = OptionsPrivate.Private.StopMotionBase.textureNameHasData
  local setTextureFunc = OptionsPrivate.Private.StopMotionBase.setTextureFunc
  local options = {
    __title = L["Stop Motion %s"]:format(subIndex),
    __order = 1,
    stopmotionVisible = {
      type = "toggle",
      width = ForeverAuras.doubleWidth,
      name = L["Show Stop Motion"],
      order = 1,
    },
    stopmotionTexture = {
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
          texture = "stopmotionTexture",
          color = "stopmotionColor",
          blendMode = "stopmotionBlendMode"
        }, texture_types, setTextureFunc)
      end,
      imageWidth = 24,
      imageHeight = 24,
      control = "ForeverAurasIcon",
      image = "Interface\\AddOns\\ForeverAuras\\Media\\Textures\\browse",
    },
    stopmotionColor = {
      type = "color",
      width = ForeverAuras.normalWidth,
      name = L["Color"],
      hasAlpha = true,
      order = 4
    },
    stopmotionDesaturate = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Desaturate"],
      order = 5,
    },
    customRows = {
        type = "input",
        width = ForeverAuras.doubleWidth / 3,
        name = L["Rows"],
        validate = ForeverAuras.ValidateNumeric,
        get = function()
          return data.customRows and tostring(data.customRows) or "";
        end,
        set = function(info, v)
          data.customRows = v and tonumber(v) or 0
          ForeverAuras.Add(parentData)
        end,
        order = 6,
        hidden = function()
          return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
        end
    },
    customColumns = {
        type = "input",
        width = ForeverAuras.doubleWidth / 3,
        name = L["Columns"],
        validate = ForeverAuras.ValidateNumeric,
        get = function()
          return data.customColumns and tostring(data.customColumns) or "";
        end,
        set = function(info, v)
          data.customColumns = v and tonumber(v) or 0
          ForeverAuras.Add(parentData)
        end,
        order = 7,
        hidden = function()
          return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
        end
    },
    customFrames = {
        type = "input",
        width = ForeverAuras.doubleWidth / 3,
        name = L["Frame Count"],
        validate = ForeverAuras.ValidateNumeric,
        get = function()
          return data.customFrames and tostring(data.customFrames) or "";
        end,
        set = function(info, v)
          data.customFrames = v and tonumber(v) or 0
          ForeverAuras.Add(parentData)
        end,
        order = 8,
        hidden = function()
          return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
        end
    },
    customFileWidth = {
      type = "input",
      width = ForeverAuras.normalWidth / 2,
      name = L["File Width"],
      desc = L["Must be a power of 2"],
      validate = function(info, val)
        if val ~= nil and val ~= "" and (not tonumber(val) or tonumber(val) >= 2^31 or math.frexp(val) ~= 0.5) then
          return false;
        end
        return true
      end,
      get = function()
        return data.customFileWidth and tostring(data.customFileWidth) or "";
      end,
      set = function(info, v)
        data.customFileWidth = v and tonumber(v) or 0
        ForeverAuras.Add(parentData)
      end,
      order = 9,
      hidden = function()
        return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
      end
    },
    customFileHeight = {
      type = "input",
      width = ForeverAuras.normalWidth / 2,
      name = L["File Height"],
      desc = L["Must be a power of 2"],
      validate = function(info, val)
        if val ~= nil and val ~= "" and (not tonumber(val) or tonumber(val) >= 2^31 or math.frexp(val) ~= 0.5) then
          return false;
        end
        return true
      end,
      get = function()
        return data.customFileHeight and tostring(data.customFileHeight) or "";
      end,
      set = function(info, v)
        data.customFileHeight = v and tonumber(v) or 0
        ForeverAuras.Add(parentData)
      end,
      order = 10,
      hidden = function()
        return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
      end
    },
    customFrameWidth = {
      type = "input",
      width = ForeverAuras.normalWidth / 2,
      name = L["Frame Width"],
      validate = ForeverAuras.ValidateNumeric,
      desc = L["Can set to 0 if Columns * Width equal File Width"],
      get = function()
        return data.customFrameWidth and tostring(data.customFrameWidth) or "";
      end,
      set = function(info, v)
        data.customFrameWidth = v and tonumber(v) or 0
        ForeverAuras.Add(parentData)
      end,
      order = 11,
      hidden = function()
        return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
      end
    },
    customFrameHeight = {
      type = "input",
      width = ForeverAuras.normalWidth / 2,
      name = L["Frame Height"],
      validate = ForeverAuras.ValidateNumeric,
      desc = L["Can set to 0 if Rows * Height equal File Height"],
      get = function()
        return data.customFrameHeight and tostring(data.customFrameHeight) or "";
      end,
      set = function(info, v)
        data.customFrameHeight = v and tonumber(v) or 0
        ForeverAuras.Add(parentData)
      end,
      order = 12,
      hidden = function()
        return texture_data[data.stopmotionTexture] or textureNameHasData(data.stopmotionTexture)
      end
    },
    stopmotionBlendMode = {
      type = "select",
      width = ForeverAuras.normalWidth,
      name = L["Blend Mode"],
      order = 13,
      values = OptionsPrivate.Private.blend_types
    },
    animationType = {
      type = "select",
      width = ForeverAuras.normalWidth,
      name = L["Animation Mode"],
      order = 14,
      values = animation_types
    },

    -- progress source added below

    startPercent = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Animation Start"],
      min = 0,
      max = 1,
      bigStep = 0.01,
      order = 17,
      isPercent = true
    },
    endPercent = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Animation End"],
      min = 0,
      max = 1,
      bigStep  = 0.01,
      order = 18,
      isPercent = true
    },

    inverse = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Inverse"],
      order = 19
    },

    frameRate = {
     type = "range",
     control = "ForeverAurasSpinBox",
     width = ForeverAuras.normalWidth,
     name = L["Frame Rate"],
     min = 3,
     max = 120,
     step = 1,
     bigStep = 3,
     order = 20,
     disabled = function() return data.animationType == "progress" end;
    },

    -- Anchor settings added below

    barModelClip = {
      type = "toggle",
      width = ForeverAuras.normalWidth,
      name = L["Clipped by Foreground"],
      order = 27,
      hidden = function()
        return not (parentData.regionType == "aurabar"
                    and data.anchor_mode == "area"
                    and data.anchor_area == "fg")
      end
    },

    scale = {
      type = "range",
      control = "ForeverAurasSpinBox",
      width = ForeverAuras.normalWidth,
      name = L["Scale Factor"],
      order = 28,
      softMin = 0.5,
      softMax = 3,
      step = 0.1,
      hidden = function()
        if parentData.regionType == "aurabar"
          and data.anchorMode == "area"
          and data.anchor_area == "fg"
          and data.barModelClip
        then
          return true
        end
        return data.anchor_mode ~= "area"
      end
    },
  }

  local progressSourceHiden = function()
    return not(data.animationType == "progress")
  end

  OptionsPrivate.commonOptions.ProgressOptionsForSubElement(parentData, data, options, 15, progressSourceHiden)
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 21, areaAnchors, pointAnchors)
  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "substopmotion")

  return options
end

  ForeverAuras.RegisterSubRegionOptions("substopmotion", createOptions, L["Shows a Stop Motion"]);
