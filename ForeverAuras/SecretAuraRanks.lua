-- Resolve public spell metadata independently of the player's learned spellbook.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
local families, scanning = {}, false

function Private.GetAuraSpellRanks(id)
  local info = C_Spell.GetSpellInfo(id)
  if not info or issecretvalue(info.name) or type(info.name) ~= "string" or info.name == "" then return {id} end
  local key = info.name
  -- Name matching is the ordinary non-exact aura semantics. Rank subtext can be
  -- unloaded even for valid spells, so it must not silently drop lower ranks.
  families[key] = families[key] or {ids = {}, minimumEnd = id}
  if not scanning and not families[key].complete then
    scanning = true
    Private.Threads:Add("secretAuraRanks", function()
      -- Use the same end-of-database heuristic as the existing spell cache.
      -- Yield between IDs and pause in combat; never inspect active aura data.
      while true do
        -- Snapshot requested names. Names added mid-scan receive a full later pass;
        -- retain only requested families, not another full spell database in memory.
        local targets, minimumEnd = {}, 0
        for name, family in pairs(families) do
          if not family.complete then
            targets[name] = family
            minimumEnd = math.max(minimumEnd, family.minimumEnd)
          end
        end
        if not next(targets) then break end
        local spellID, misses = 0, 0
        while misses < 80000 or spellID < minimumEnd do
          if not InCombatLockdown() then
            spellID = spellID + 1
            local candidate = C_Spell.GetSpellInfo(spellID)
            misses = candidate and 0 or misses + 1
            local family = candidate and not issecretvalue(candidate.name) and targets[candidate.name]
            if family then family.ids[#family.ids + 1] = spellID end
          end
          coroutine.yield(0.01, "ranks")
        end
        for _, family in pairs(targets) do family.complete = true end
        -- Reapply native filters through their normal restriction-aware lifecycle.
        if Private.BlizzardAuraDisplay.RefreshSpellRanks then Private.BlizzardAuraDisplay.RefreshSpellRanks() end
      end
      scanning = false
    end, "background")
  end
  return families[key].complete and families[key].ids or {id}
end
