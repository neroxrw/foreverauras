if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local function createOptions(parentData, data, index, subIndex)
  local points, areas = {}, {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(points, OptionsPrivate.Private.GetAnchorsForData(child, "point"))
    Mixin(areas, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end
  local options = {
    __title = "Dispel Type Icon " .. subIndex, __order = 1,
    dispelVisible = {type = "toggle", name = "Show Icon", order = 1, width = ForeverAuras.normalWidth},
  }
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 10, areas, points)
  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "subcdmdispel")
  return options
end
ForeverAuras.RegisterSubRegionOptions("subcdmdispel", createOptions, "Shows Blizzard's native dispel-type icon.")
