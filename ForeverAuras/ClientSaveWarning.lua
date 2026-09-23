-- Client-saving notice; dismissal is stored with the addon settings.
local loader = CreateFrame("Frame")
local notice
local font = "Interface\\AddOns\\ForeverAuras\\Media\\Fonts\\FiraSans-Medium.ttf"

local function ShowNotice()
  if notice then notice:Show();return end
  local overlay = CreateFrame("Frame", "ForeverAurasClientSaveNotice", UIParent)
  notice = overlay
  overlay:SetAllPoints(UIParent)
  overlay:SetFrameStrata("DIALOG")
  overlay:EnableMouse(true)
  local shade = overlay:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.6)

  local panel = CreateFrame("Frame", nil, overlay)
  panel:SetSize(560, 370)
  panel:SetPoint("CENTER")
  -- Texture bands keep the gradient compatible with the beta client's UI API.
  for i = 0, 63 do
    local t = i / 63
    local band = panel:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 0, -i * 370 / 64)
    band:SetPoint("TOPRIGHT", 0, -i * 370 / 64)
    band:SetHeight(370 / 64 + 1)
    band:SetColorTexture(0.075 - t * 0.057, 0.12 - t * 0.094, 0.18 - t * 0.14, 1)
  end
  for _, edge in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
    local line = panel:CreateTexture(nil, "BORDER")
    line:SetColorTexture(0.76, 0.59, 0.29, 0.65)
    if edge == "TOP" or edge == "BOTTOM" then
      line:SetPoint(edge.."LEFT"); line:SetPoint(edge.."RIGHT"); line:SetHeight(1)
    else
      line:SetPoint("TOP"..edge); line:SetPoint("BOTTOM"..edge); line:SetWidth(1)
    end
  end
  local icon = panel:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\ForeverAuras\\Media\\Textures\\foreverauras_logo.tga")
  icon:SetSize(96, 96)
  icon:SetPoint("TOP", 0, -22)
  local subtitle = panel:CreateFontString(nil, "OVERLAY")
  subtitle:SetFont(font, 11, "")
  subtitle:SetTextColor(0.9, 0.72, 0.4)
  subtitle:SetPoint("TOP", 0, -174)
  subtitle:SetText("CLIENT NOTICE")

  local title = panel:CreateFontString(nil, "OVERLAY")
  title:SetFont("Interface\\AddOns\\ForeverAuras\\Media\\Fonts\\FiraSans-Heavy.ttf", 28, "")
  title:SetPoint("TOP", 0, -132)
  title:SetTextColor(0.96, 0.94, 0.87)
  title:SetText("ForeverAuras")
  local message = panel:CreateFontString(nil, "OVERLAY")
  message:SetFontObject(GameFontNormalLarge)
  if not message:SetFont(font, 20, "") then
    message:SetFontObject(GameFontNormalLarge)
  end
  message:SetPoint("TOPLEFT", 50, -204)
  -- Let the wrapped text determine its height instead of clipping to two anchors.
  message:SetWidth(460)
  message:SetHeight(0)
  message:SetJustifyV("TOP")
  message:SetWordWrap(true)
  message:SetJustifyH("CENTER")
  message:SetTextColor(1, 0.95, 0.88)
  message:SetText("Auras will NOT save until Blizzard address the client issue.")

  local dismiss = CreateFrame("Button", nil, panel)
  dismiss:SetSize(220, 40)
  dismiss:SetPoint("BOTTOM", 0, 28)
  local buttonBackground = dismiss:CreateTexture(nil, "BACKGROUND")
  buttonBackground:SetAllPoints()
  buttonBackground:SetColorTexture(0.95, 0.65, 0.25, 0.18)
  local label = dismiss:CreateFontString(nil, "OVERLAY")
  label:SetFont(font, 15, "")
  label:SetPoint("CENTER")
  label:SetText("I Understand")
  dismiss:SetScript("OnEnter", function() buttonBackground:SetColorTexture(0.95, 0.65, 0.25, 0.32) end)
  dismiss:SetScript("OnLeave", function() buttonBackground:SetColorTexture(0.95, 0.65, 0.25, 0.18) end)
  overlay:SetScript("OnHide", function()
    ForeverAurasSaved = ForeverAurasSaved or {}
    ForeverAurasSaved.clientSaveWarningAcknowledged = true
  end)
  dismiss:SetScript("OnClick", function() overlay:Hide() end)
  UISpecialFrames[#UISpecialFrames + 1] = "ForeverAurasClientSaveNotice"
  overlay:Show()
end

SLASH_FOREVERAURASSAVEWARNING1 = "/fawarning"
SlashCmdList.FOREVERAURASSAVEWARNING = ShowNotice

loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  if ForeverAurasSaved and ForeverAurasSaved.clientSaveWarningAcknowledged then return end
  C_Timer.After(0.8, function()
    if not (ForeverAurasSaved and ForeverAurasSaved.clientSaveWarningAcknowledged) then ShowNotice() end
  end)
end)
