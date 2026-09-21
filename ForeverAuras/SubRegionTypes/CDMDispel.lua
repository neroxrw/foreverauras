if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local function defaults()
  return {dispelVisible = true, dispelStyle = "Icon", anchor_mode = "point", anchor_point = "CENTER",
    self_point = "CENTER", width = 24, height = 24, xOffset = 0, yOffset = 0, anchor_area = "ALL"}
end
local function create()
  local region = CreateFrame("Frame", nil, UIParent)
  region.preview = region:CreateTexture(nil, "OVERLAY")
  region.preview:SetAllPoints(region)
  region.preview:Hide()
  function region:SetVisible(value)
    self.visible = value
    self:SetShown(value)
    if self.Update then self:Update() end
  end
  return region
end
local function modify(parent, region, parentData, data)
  region:SetParent(parent)
  region.parent = parent
  region.Anchor = function()
    region:ClearAllPoints()
    if data.anchor_mode == "point" then region:SetSize(data.width or 24, data.height or 24) end
    parent:AnchorSubRegion(region, data.anchor_mode or "point", data.anchor_mode == "area" and data.anchor_area or data.anchor_point,
      data.anchor_mode == "point" and data.self_point or nil, data.xOffset or 0, data.yOffset or 0)
  end
  region:Anchor()
  region.Update = function() Private.CDMAuraProgress.UpdateIndicator(parent, region, data) end
  region.UpdateProgress = region.Update
  parent.subRegionEvents:AddSubscriber("Update", region)
  parent.subRegionEvents:AddSubscriber("UpdateProgress", region)
  Private.CDMAuraProgress.ModifyIndicator(parent, region, parentData, data)
  region:SetVisible(data.dispelVisible ~= false)
end
local function release(region)
  if region.parent then
    region.parent.subRegionEvents:RemoveSubscriber("Update", region)
    region.parent.subRegionEvents:RemoveSubscriber("UpdateProgress", region)
  end
  Private.CDMAuraProgress.ReleaseIndicator(region, true)
  region:Hide()
end
local function supports(kind) return kind == "icon" or kind == "aurabar" or kind == "progresstexture" end
ForeverAuras.RegisterSubRegionType("subcdmdispel", "Dispel Type Indicator", supports, create, modify,
  function(region) region:Show() end, release, defaults, nil,
  {dispelVisible = {display = "Visibility", setter = "SetVisible", type = "bool", defaultProperty = true}})
