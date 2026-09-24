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
  if trigger.cdmSpell ~= nil then
    if trigger.cdmSelection ~= "spell" and trigger.event == "Blizzard Cooldown Manager" then
      local resolved = Private.ResolveCDMSpell(trigger, "OPTIONS")
      local entries = Private.CDMCatalog()
      local entry = #resolved == 1 and entries[resolved[1]]
      local info = entry and C_CooldownViewer.GetCooldownViewerCooldownInfo(resolved[1])
      if info then
        if info.equipSlot or info.spellCategoryID then trigger.event = "Blizzard CDM Item"
        elseif entry.category == Enum.CooldownViewerCategory.Utility then trigger.event = "Blizzard CDM Utility" end
      end
    end
    if tostring(trigger.cdmSpell):find("%S") then
      if trigger.cdmExact then
        trigger.cdmExactIDs = trigger.cdmExactIDs or {tostring(trigger.cdmSpell)}
        trigger.cdmUseExactIDs = true
      else
        trigger.cdmNames = trigger.cdmNames or {tostring(trigger.cdmSpell)}
        trigger.cdmUseNames = true
      end
    end
    trigger.cdmSpell, trigger.cdmExact = nil, nil
    C_Timer.After(0, function() ForeverAuras.Add(data); Private.UpdateFakeStatesFor(data.id) end)
  end
  Add("typeSpacer", {type = "description", name = " ", width = "full"})
  Add("help", {type = "description", name = "Spells must be active in the CDM to be displayed. Type /cdm and add them.", width = "full"})
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
  Add("remainingEnabled", {type = "toggle", name = "Remaining Time", width = ForeverAuras.normalWidth,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" end,
    desc = "Filters active, timed auras using readable CDM remaining time. Missing, permanent, or secret timers do not match.",
    get = function() return trigger.cdmUseRemaining or false end,
    set = function(_, value) Save("cdmUseRemaining", value) end})
  Add("remainingOperator", {type = "select", name = "", width = 0.5,
    values = {['<'] = '<', ['<='] = '<=', ['>'] = '>', ['>='] = '>='},
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseRemaining end,
    get = function() return trigger.cdmRemainingOperator or "<" end,
    set = function(_, value) Save("cdmRemainingOperator", value) end})
  Add("remainingSeconds", {type = "input", name = "Seconds", width = ForeverAuras.normalWidth - 0.5,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseRemaining end,
    get = function() return tostring(trigger.cdmRemainingTime or 10) end,
    validate = function(_, value)
      local number = tonumber(value)
      return (number and number >= 0 and number < math.huge) or "Enter a non-negative number of seconds."
    end,
    set = function(_, value) Save("cdmRemainingTime", tonumber(value)) end})
  Add("totalEnabled", {type = "toggle", name = "Total Duration", width = ForeverAuras.normalWidth,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" end,
    desc = "Filters active, timed auras using readable CDM total time. Missing, permanent, or secret timers do not match.",
    get = function() return trigger.cdmUseTotal or false end,
    set = function(_, value) Save("cdmUseTotal", value) end})
  Add("totalOperator", {type = "select", name = "", width = 0.5,
    values = {['<'] = '<', ['<='] = '<=', ['>'] = '>', ['>='] = '>='},
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseTotal end,
    get = function() return trigger.cdmTotalOperator or "<" end,
    set = function(_, value) Save("cdmTotalOperator", value) end})
  Add("totalSeconds", {type = "input", name = "Seconds", width = ForeverAuras.normalWidth - 0.5,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseTotal end,
    get = function() return tostring(trigger.cdmTotalTime or 10) end,
    validate = function(_, value)
      local number = tonumber(value)
      return (number and number >= 0 and number < math.huge) or "Enter a non-negative number of seconds."
    end,
    set = function(_, value) Save("cdmTotalTime", tonumber(value)) end})
  Add("elapsedEnabled", {type = "toggle", name = "Elapsed Time", width = ForeverAuras.normalWidth,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" end,
    desc = "Filters active, timed auras using readable CDM elapsed time. Missing, permanent, or secret timers do not match.",
    get = function() return trigger.cdmUseElapsed or false end,
    set = function(_, value) Save("cdmUseElapsed", value) end})
  Add("elapsedOperator", {type = "select", name = "", width = 0.5,
    values = {['<'] = '<', ['<='] = '<=', ['>'] = '>', ['>='] = '>='},
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseElapsed end,
    get = function() return trigger.cdmElapsedOperator or ">=" end,
    set = function(_, value) Save("cdmElapsedOperator", value) end})
  Add("elapsedSeconds", {type = "input", name = "Seconds", width = ForeverAuras.normalWidth - 0.5,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseElapsed end,
    get = function() return tostring(trigger.cdmElapsedTime or 10) end,
    validate = function(_, value)
      local number = tonumber(value)
      return (number and number >= 0 and number < math.huge) or "Enter a non-negative number of seconds."
    end,
    set = function(_, value) Save("cdmElapsedTime", tonumber(value)) end})
  Add("stacksEnabled", {type = "toggle", name = "Stack Count", width = ForeverAuras.normalWidth,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" end,
    desc = "Filters active auras using readable CDM stack counts. Missing or secret stack counts do not match. All enabled filters must match.",
    get = function() return trigger.cdmUseStacks or false end,
    set = function(_, value) Save("cdmUseStacks", value) end})
  Add("stacksOperator", {type = "select", name = "", width = 0.5,
    values = {['<'] = '<', ['<='] = '<=', ['>'] = '>', ['>='] = '>=', ['=='] = '=', ['~='] = '!='},
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseStacks end,
    get = function() return trigger.cdmStackOperator or ">=" end,
    set = function(_, value) Save("cdmStackOperator", value) end})
  Add("stacksCount", {type = "input", name = "Stacks", width = ForeverAuras.normalWidth - 0.5,
    hidden = function() return trigger.event ~= "Blizzard CDM Buff" or not trigger.cdmUseStacks end,
    get = function() return tostring(trigger.cdmStackCount or 1) end,
    validate = function(_, value)
      local number = tonumber(value)
      return (number and number >= 0 and number < math.huge and number == math.floor(number)) or "Enter a non-negative whole number."
    end,
    set = function(_, value) Save("cdmStackCount", tonumber(value)) end})
  Add("extra", {
    type = "execute", control = "ForeverAurasExpandSmall", width = "full", hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" end,
    name = function()
      local settings = {}
      if trigger.cdmTrack == "cooldown" then settings[#settings + 1] = "Cooldown" elseif trigger.cdmTrack == "charges" then settings[#settings + 1] = "Charge recharge" end
      if trigger.use_ignoreSpellKnown then settings[#settings + 1] = "Disable Spell Known Check" end
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
  Add("hideGCDText", {type = "toggle", name = "Hide global cooldown text", width = "full", hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end, desc = "Hides GCD countdown numbers, including %p and %t text. Spell cooldown and charge recharge text remain visible while the GCD swipe is shown.", get = function() return trigger.cdmHideGCDText ~= false end, set = function(_, value) Save("cdmHideGCDText", value) end})
  Add("ignoreSpellKnown", {type = "toggle", name = "Disable Spell Known Check", width = "full",
    hidden = function() return trigger.cdmSource == "buff" or trigger.event == "Blizzard CDM Item" or not view.extra end,
    get = function() return trigger.use_ignoreSpellKnown or false end,
    set = function(_, value) Save("use_ignoreSpellKnown", value) end})


  do
    order = 20
    Add("spellSelection", {type = "header", name = "Spell Selection Filters"})
    local function Selector(title, label, prefix, flag, storage, exact, baseOrder, itemID)
      options[prefix .. "Toggle"] = {
        type = "toggle", name = title, width = ForeverAuras.normalWidth - 0.2, order = baseOrder,
        get = function() return trigger[flag] or false end,
        set = function(_, value) Save(flag, value) end,
      }
      options[prefix .. "DisabledSpace"] = {
        type = "description", name = "", width = ForeverAuras.normalWidth + 0.2, order = baseOrder + 0.001,
        hidden = function() return trigger[flag] == true end,
      }
      local size = #(trigger[storage] or {}) + 1
      OptionsPrivate.CreateAuraSpellOptions(options, data, triggernum, size, exact, false,
        prefix, baseOrder, flag, storage, label, nil, false, function() return trigger[flag] == true end,
        function() Save(storage, trigger[storage]) end)
      for i = 1, size do
        local input = options[prefix .. i]
        if itemID then
          local function ItemName()
            local id = tonumber(trigger[storage] and trigger[storage][i])
            Private.CDMRequestItemData(id)
            return id and C_Item and C_Item.GetItemNameByID(id)
          end
          local icon = options[prefix .. "icon" .. i]
          icon.name = function() return ItemName() or "" end
          icon.image = function()
            local id = tonumber(trigger[storage] and trigger[storage][i])
            local texture = id and C_Item and C_Item.GetItemIconByID(id)
            return texture and tostring(texture) or "", 18, 18
          end
          icon.disabled = function() return not ItemName() end
          input.get = function()
            local raw = trigger[storage] and trigger[storage][i]
            if not raw then return "" end
            return ("%s (%s)"):format(raw, ItemName() or "Unknown Item") .. "\0" .. raw
          end
        end
        if exact then
          input.validate = function(_, value)
            if value == "" then return true end
            local id = tonumber(value)
            return (id and id > 0 and id < 2147483647 and id == math.floor(id)) or (itemID and "Enter a positive whole-number Item ID." or "Enter a positive whole-number Spell ID.")
          end
        end
      end
    end
    Selector("Name(s)", trigger.cdmSource == "buff" and "Aura Name" or "Spell Name", "cdmPicker_name", "cdmUseNames", "cdmNames", false, 21)
    Selector("Exact Spell ID(s)", "Spell ID", "cdmPicker_spellid", "cdmUseExactIDs", "cdmExactIDs", true, 25)
    if trigger.event == "Blizzard CDM Item" then
      Selector("Exact Item ID(s)", "Item ID", "cdmPicker_itemid", "cdmUseItemIDs", "cdmItemIDs", true, 29, true)
    end
    order = 35
  end
  Add("filters", {type = "header", name = "Blizzard CDM Filters"})
  Add("search", {type = "input", name = "Search", width = "full", get = function() return view.search or "" end,
    set = function(_, value) view.search = value; Refresh() end})
  Add("available", {type = "toggle", name = "Show only available", width = ForeverAuras.normalWidth,
    get = function() return view.availableOnly or false end, set = function(_, value) view.availableOnly = value; Refresh() end})
  Add("maxRank", {type = "toggle", name = "Show only max rank", width = ForeverAuras.normalWidth,
    get = function() return view.maxRank or false end, set = function(_, value) view.maxRank = value; Refresh() end})
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
      highest[name] = math.max(highest[name] or 0, rank)
    end
  end
  table.sort(rows, function(a,b) if a.name ~= b.name then return a.name < b.name end; if a.rank ~= b.rank then return a.rank > b.rank end; return a.id < b.id end)
  local query = (view.search or ""):lower()
  for _, row in ipairs(rows) do
    if (not view.availableOnly or row.known) and row.label:lower():find(query, 1, true)
      and (not view.maxRank or row.rank == highest[row.name]) then
      Add("entry" .. row.id, {type = "toggle", name = row.label, desc = row.category, width = "full", image = row.icon, imageWidth = 18, imageHeight = 18,
        get = function() return Checked(row.id) end,
        set = function(_, value)
          selected[row.id] = nil; selected[tostring(row.id)] = value or nil
          Save("cdmSpells", trigger.cdmSpells)
        end})
    end
  end

end
