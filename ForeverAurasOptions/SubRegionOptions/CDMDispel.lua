if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local function createOptions(parentData, data, index, subIndex)
  local points, areas = {}, {}
  for child in OptionsPrivate.Private.TraverseLeafsOrAura(parentData) do
    Mixin(points, OptionsPrivate.Private.GetAnchorsForData(child, "point"))
    Mixin(areas, OptionsPrivate.Private.GetAnchorsForData(child, "area"))
  end
  local options = {
    __title = "Dispel Type Indicator " .. subIndex, __order = 1,
    dispelVisible = {type = "toggle", name = "Show Indicator", order = 1, width = ForeverAuras.normalWidth},
    dispelStyle = {type = "select", name = "Style", order = 2, width = ForeverAuras.normalWidth,
      values = {Icon = "Dispel Icon", Border = "Border", BorderWithIcon = "Border with Icon"}},
  }
  OptionsPrivate.commonOptions.PositionOptionsForSubElement(data, options, 10, areas, points)
  OptionsPrivate.AddUpDownDeleteDuplicate(options, parentData, index, "subcdmdispel")
  return options
end
ForeverAuras.RegisterSubRegionOptions("subcdmdispel", createOptions, "Shows Blizzard's native dispel-type icon or border.")
