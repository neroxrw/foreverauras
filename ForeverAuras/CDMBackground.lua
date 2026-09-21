if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local names = {"EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer"}
local viewers = setmetatable({}, {__mode = "k"})
local applying = false
local function Hidden() return Private.db and Private.db.cdmHideBlizzard == true end
local function Accessible(frame) return not frame.IsForbidden or not frame:IsForbidden() end
local function ApplyAlpha(frame, alpha)
  if applying or not Accessible(frame) then return end
  local record = viewers[frame]
  if not record then return end
  if alpha ~= nil and not (issecretvalue and issecretvalue(alpha)) then record.alpha = alpha end
  applying = true
  frame:SetAlpha(Hidden() and 0 or record.alpha)
  applying = false
end
function Private.ApplyCDMBackground()
  if InCombatLockdown() then return end
  if Hidden() and C_CVar and C_CVar.GetCVarBool and not C_CVar.GetCVarBool("cooldownViewerEnabled") then
    C_CVar.SetCVar("cooldownViewerEnabled", "1")
  end
  for _, name in ipairs(names) do
    local viewer = _G[name]
    if viewer and Accessible(viewer) and (Hidden() or viewers[viewer]) then
      if not viewers[viewer] then
        local alpha = viewer:GetAlpha()
        if issecretvalue and issecretvalue(alpha) then alpha = 1 end
        viewers[viewer] = {alpha = alpha}
        hooksecurefunc(viewer, "SetAlpha", ApplyAlpha)
      end
      ApplyAlpha(viewer)
    end
  end
  if Private.ScanEvents then Private.ScanEvents("FA_CDM_REFRESH") end
end
local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "COOLDOWN_VIEWER_DATA_LOADED", "CVAR_UPDATE"}) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, name)
  if event == "CVAR_UPDATE" and name ~= "cooldownViewerEnabled" then return end
  Private.ApplyCDMBackground()
end)
