if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local views = setmetatable({}, {__mode = "k"})
function OptionsPrivate.AddCooldownViewerOptions(options, data, triggernum)
  local Private = OptionsPrivate.Private
  local trigger = data.triggers[triggernum].trigger
  if trigger.type == "cdm" then trigger.cdmSource = trigger.event == "Blizzard CDM Buff" and "buff" or "cooldown" end
  views[data] = views[data] or {}
  views[data][triggernum] = views[data][triggernum] or {}
  local view = views[data][triggernum]
  for key in pairs(options) do
    if key:find("cdmSpells", 1, true) or key:find("cdmShowGCD", 1, true) then options[key] = nil end
  end
  local function Refresh() ForeverAuras.ClearAndUpdateOptions(data.id) end
  local function Save(key, value)
    trigger[key] = value
    ForeverAuras.Add(data)
    Private.ScanForLoads({[data.id] = true})
    ForeverAuras.UpdateThumbnail(data)
    Private.UpdateFakeStatesFor(data.id)
    Refresh()
  end
  local order = 10.01
  local function Add(key, option)
    option.order = order
    order = order + 0.001
    options["cdmPicker_" .. key] = option
  end
  trigger.cdmSpells = trigger.cdmSpells or {multi = {}}
  trigger.cdmSpells.multi = trigger.cdmSpells.multi or {}
  local selected = trigger.cdmSpells.multi
  if trigger.cdmSpell ~= nil and trigger.cdmSelection ~= "spell" then
    local resolved = Private.ResolveCDMSpell(trigger, "OPTIONS")
    for _, id in ipairs(resolved) do selected[tostring(id)] = true end
    if trigger.event == "Blizzard Cooldown Manager" and #resolved == 1 then
      local entries = Private.CDMCatalog()
      local entry, info = entries[resolved[1]], C_CooldownViewer.GetCooldownViewerCooldownInfo(resolved[1])
      if entry and info then
        if info.equipSlot or info.spellCategoryID then trigger.event = "Blizzard CDM Item"
        elseif entry.category == Enum.CooldownViewerCategory.Utility then trigger.event = "Blizzard CDM Utility" end
      end
    end
    trigger.cdmSpell, trigger.cdmExact = nil, nil
    C_Timer.After(0, function() ForeverAuras.Add(data); Private.UpdateFakeStatesFor(data.id) end)
  end
  Add("typeSpacer", {type = "description", name = " ", width = "full"})
  Add("help", {type = "description", name = "To see more spells, type /CDM and add them.", width = "full"})
  Add("open", {type = "execute", name = "Open CDM", width = ForeverAuras.normalWidth,
    disabled = function() return InCombatLockdown() or not C_CooldownViewer end,
    func = function()
      if not C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then C_AddOns.LoadAddOn("Blizzard_CooldownViewer") end
      if CooldownViewerSettings then ShowUIPanel(CooldownViewerSettings) end
    end})
  Add("refresh", {type = "execute", name = "Refresh from Blizzard CDM", width = ForeverAuras.normalWidth, func = Refresh})
  Add("display", {type = "header", name = "Display", hidden = function() return trigger.event == "Blizzard CDM Item" end})
  Add("show", {type = "select", name = "Show", width = ForeverAuras.normalWidth, values = {always = "Always", cooldown = "On Cooldown", ready = "Not on Cooldown"}, hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" end, get = function() return trigger.cdmShow or "always" end, set = function(_, value) Save("cdmShow", value) end})
  Add("buffShow", {type = "select", name = "Show", width = ForeverAuras.normalWidth, values = {always = "Always", active = "Aura Active", missing = "Aura Missing"}, hidden = function() return trigger.cdmSource ~= "buff" end, get = function() return trigger.cdmBuffShow or "active" end, set = function(_, value) Save("cdmBuffShow", value) end})
  Add("requireTarget", {type = "toggle", name = "Require attackable target", width = ForeverAuras.normalWidth,
    hidden = function() return trigger.cdmSource ~= "buff" end,
    desc = "Only show this trigger's auras while you have a target you can attack. Applies to all selected entries and all Show modes.",
    get = function() return trigger.cdmRequireTarget or false end,
    set = function(_, value) Save("cdmRequireTarget", value) end})
  Add("extra", {
    type = "execute", control = "ForeverAurasExpandSmall", width = "full", hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" end,
    name = function()
      local settings = {}
      if trigger.cdmTrack == "cooldown" then settings[#settings + 1] = "Cooldown" elseif trigger.cdmTrack == "charges" then settings[#settings + 1] = "Charge recharge" end
      if trigger.use_cdmShowGCD then settings[#settings + 1] = "Show GCD" end
      if trigger.cdmHideGCDText ~= false then settings[#settings + 1] = "Hide GCD text" end
      return "|cFFffcc00Extra Options:|r " .. (#settings > 0 and table.concat(settings, "; ") or "None")
    end,
    image = function() return view.extra and "expanded" or "collapsed" end, imageWidth = 15, imageHeight = 15,
    func = function() view.extra = not view.extra; Refresh() end,
  })
  Add("track", {type = "select", name = "Track cooldowns", width = ForeverAuras.normalWidth, hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end, values = {auto = "Auto", cooldown = "Cooldown", charges = "Charge recharge"}, get = function() return trigger.cdmTrack or "auto" end, set = function(_, value) Save("cdmTrack", value) end})
  Add("trackSpacer", {type = "description", name = "", width = ForeverAuras.normalWidth, hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end})
  Add("includeGCD", {type = "toggle", name = "Show global cooldown", width = "full", hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end, get = function() return trigger.use_cdmShowGCD or false end, set = function(_, value) Save("use_cdmShowGCD", value) end})
  Add("hideGCDText", {type = "toggle", name = "Hide global cooldown text", width = "full", hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end, desc = "Hides the icon cooldown countdown numbers during a global cooldown. Custom text such as %p is configured separately.", get = function() return trigger.cdmHideGCDText ~= false end, set = function(_, value) Save("cdmHideGCDText", value) end})

  Add("spell", {type = "input", name = "Spell name or ID", width = "full", hidden = function() return trigger.event == "Blizzard CDM Item" end,
    desc = "When filled, this takes priority over the checklist. Clear it to use checked entries. A name creates one display across aura ranks, or uses the highest available cooldown rank. A spell ID matches that specific spell. The spell must be assigned in Blizzard's CDM.",
    get = function() return trigger.cdmSpell or "" end,
    set = function(_, value)
      trigger.cdmSelection, trigger.cdmExact = "spell", nil
      Save("cdmSpell", value:match("^%s*(.-)%s*$"))
    end})
  Add("filters", {type = "header", name = "Blizzard CDM Filters"})
  Add("search", {type = "input", name = "Search", width = "full", get = function() return view.search or "" end,
    set = function(_, value) view.search = value; Refresh() end})
  Add("maxRank", {type = "toggle", name = "Show only max rank", width = ForeverAuras.normalWidth,
    get = function() return view.maxRank or false end, set = function(_, value) view.maxRank = value; Refresh() end})
  Add("available", {type = "toggle", name = "Show only available", width = ForeverAuras.normalWidth,
    get = function() return view.availableOnly or false end, set = function(_, value) view.availableOnly = value; Refresh() end})
  Add("selected", {type = "toggle", name = "Selected only", width = ForeverAuras.normalWidth,
    get = function() return view.selectedOnly or false end, set = function(_, value) view.selectedOnly = value; Refresh() end})
  Add("entries", {type = "header", name = "Blizzard CDM Entries"})
  local catalog = C_CooldownViewer and Private.CDMCatalog() or {}
  local rows, highest = {}, {}
  local function Checked(id) return selected[id] or selected[tostring(id)] or false end
  for id, entry in pairs(catalog) do
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
    if info and Private.CDMEntryMatches(trigger, entry, info) then
      local identity = Private.CDMIdentity(id, entry, info)
      local spellID = info.spellID or identity.spellID
      local spell = spellID and C_Spell.GetSpellInfo(spellID)
      local item = trigger.event == "Blizzard CDM Item"
      local name = not item and spell and spell.name or identity.name
      local rankText = not item and spellID and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
      local rank = rankText and tonumber(rankText:match("%d+")) or 0
      local label = name .. (rankText and rankText ~= "" and (" (" .. rankText .. ")") or "")
      local shownID = item and identity.itemID or spellID
      if shownID then label = label .. " [" .. shownID .. "]" end
      rows[#rows + 1] = {id = id, name = name, label = label, rank = rank, known = entry.known, icon = not item and spell and spell.iconID or identity.icon, category = Private.CDMCategoryName(entry.category)}
      local best = highest[name]
      if not best or (entry.known and not best.known) or (entry.known == best.known and rank > best.rank) then highest[name] = {rank = rank, known = entry.known} end
    end
  end
  table.sort(rows, function(a,b) if a.name ~= b.name then return a.name < b.name end; if a.rank ~= b.rank then return a.rank > b.rank end; return a.id < b.id end)
  local query = (view.search or ""):lower()
  for _, row in ipairs(rows) do
    if (not view.availableOnly or row.known) and (not view.selectedOnly or Checked(row.id)) and row.label:lower():find(query, 1, true)
      and (not view.maxRank or Checked(row.id) or (row.rank == highest[row.name].rank and row.known == highest[row.name].known)) then
      Add("entry" .. row.id, {type = "toggle", name = row.label, desc = row.category, width = "full", image = row.icon, imageWidth = 18, imageHeight = 18,
        get = function() return Checked(row.id) end,
        set = function(_, value)
          selected[row.id] = nil; selected[tostring(row.id)] = value or nil
          Save("cdmSpells", trigger.cdmSpells)
        end})
    end
  end

end
