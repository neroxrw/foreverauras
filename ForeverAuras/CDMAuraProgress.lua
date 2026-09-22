if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local Display = {}
Private.CDMAuraProgress = Display

function Display.IsConfigured(data)
  if not data or type(data.triggers) ~= "table" then return false end
  local source = data.progressSource and data.progressSource[1] or -1
  if source == 0 then return false end
  if source < 0 then source = data.triggers.activeTriggerMode or -1 end
  if source < 0 and #data.triggers == 1 then source = 1 end
  local entry = data.triggers[source]
  return type(entry) == "table" and entry.trigger and entry.trigger.type == "cdm" and entry.trigger.event == "Blizzard CDM Buff" or false
end

local function SourceState(parent, explicit)
  local source = explicit or (parent.progressSource and parent.progressSource[1]) or -1
  if source > 0 then return parent.states and parent.states[source] end
  if source == -1 then return parent.state end
end

function Display.Modify(region, data)
  region.cdmProgressData = data
  region.cdmNativeProgress = nil
end
function Display.Update(region) region.cdmNativeProgress = nil end
function Display.Style(region) end
function Display.SyncFrameLevels(region, force) end
function Display.ModifyText(parent, sub, parentData, config) end
function Display.HideText(sub) sub.cdmNativeText = nil end

function Display.UpdateText(parent, sub, config, kind, explicitTrigger)
  if not kind then return false end
  local state = SourceState(parent, explicitTrigger)
  if not state or not state.cdmBuff then return false end
  if not sub.text:GetFont() then return true end
  Private.CopyCDMCountdownText(sub.text, state, kind)
  return true
end

function Display.ModifyIndicator(parent, sub, parentData, config)
  Display.ReleaseIndicator(sub)
end
function Display.ReleaseIndicator(sub, forget)
  if sub.preview then sub.preview:Hide() end
end
function Display.UpdateIndicator(parent, sub, config)
  local state = SourceState(parent)
  local dispel
  if sub.visible and state and state.show and state.cdmBuff then
    dispel = state.cdmDispelName
    if state.cdmTextPreview and state.auraActive ~= true then dispel = "Magic" end
  end
  if type(dispel) ~= "string" or dispel == "" then sub.preview:Hide(); return end
  if config.dispelStyle == "Border" or config.dispelStyle == "BorderWithIcon" then
    AuraUtil.SetAuraBorderAtlas(sub.preview, dispel, config.dispelStyle == "BorderWithIcon")
  else
    AuraUtil.SetAuraDispelTypeIcon(sub.preview, dispel)
  end
  sub.preview:Show()
end
