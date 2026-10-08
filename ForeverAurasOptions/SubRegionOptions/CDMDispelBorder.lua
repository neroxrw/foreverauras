-- Copyright (C) 2026 ForeverAuras. Part of ForeverAuras, licensed under the GNU GPL v2 (see LICENSE).
if not WeakAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local function createOptions(parentData, data, index, subIndex)
  local points, areas = {}, {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(points, OptionsPrivate.Private.GetAnchorsForData(child, "point"))
    Mixin(areas, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end
  -- Border geometry is independent of the dispel icon's anchor and size.
  local options = {
    __title = "Dispel Type Border " .. subIndex, __order = 1,
    dispelVisible = {type = "toggle", name = "Show Border", order = 1, width = WeakAuras.normalWidth},
    dispelBorderSize = {type = "range", control = "WeakAurasSpinBox", name = "Thickness", order = 2,
      min = 1, max = 32, step = 1, width = WeakAuras.normalWidth},
    dispelBorderOffset = {type = "range", control = "WeakAurasSpinBox", name = "Border Offset", order = 3,
      softMin = -16, softMax = 32, step = 1, width = WeakAuras.normalWidth},
  }
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 10, areas, points)
  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "subcdmdispelborder")
  return options
end
WeakAuras.RegisterSubRegionOptions("subcdmdispelborder", createOptions, "Shows a resizable border coloured by dispel type.")
