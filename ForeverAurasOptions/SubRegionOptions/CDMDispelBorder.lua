if not ForeverAuras.IsLibsOK() then return end
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
    dispelVisible = {type = "toggle", name = "Show Border", order = 1, width = ForeverAuras.normalWidth},
    dispelBorderSize = {type = "range", control = "ForeverAurasSpinBox", name = "Thickness", order = 2,
      min = 1, max = 32, step = 1, width = ForeverAuras.normalWidth},
    dispelBorderOffset = {type = "range", control = "ForeverAurasSpinBox", name = "Border Offset", order = 3,
      softMin = -16, softMax = 32, step = 1, width = ForeverAuras.normalWidth},
  }
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 10, areas, points)
  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "subcdmdispelborder")
  return options
end
ForeverAuras.RegisterSubRegionOptions("subcdmdispelborder", createOptions, "Shows a resizable border coloured by dispel type.")
