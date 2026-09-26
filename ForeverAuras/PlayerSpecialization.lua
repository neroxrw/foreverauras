-- Player-only load conditions inferred from learned final-tier talent spells.
-- Catalog: Forever beta data from talentsforever.com and Wowhead talent records.
-- See SpecializationData-LICENSE.txt for sources and attribution.
if not ForeverAuras.IsLibsOK() then return end
local _, Private = ...
-- Keys describe talent trees, not retail specialization IDs. Include every known
-- rank so learning a higher rank cannot stop an existing aura from loading.
local specializations = {
  {"WARRIOR_ARMS", "WARRIOR", "Arms", "ability_rogue_eviscerate", {12294, 21551, 21552, 21553}}, -- Mortal Strike
  {"WARRIOR_FURY", "WARRIOR", "Fury", "ability_warrior_innerrage", {23881, 23892, 23893, 23894}}, -- Bloodthirst
  {"WARRIOR_PROTECTION", "WARRIOR", "Protection", "ability_warrior_defensivestance", {23922, 23923, 23924, 23925}}, -- Shield Slam
  {"PALADIN_HOLY", "PALADIN", "Holy", "spell_holy_holybolt", {1310911, 1311590, 1311595}}, -- Light's Vigil
  {"PALADIN_PROTECTION", "PALADIN", "Protection", "spell_holy_devotionaura", {20925, 20927, 20928}}, -- Holy Shield
  {"PALADIN_RETRIBUTION", "PALADIN", "Retribution", "spell_holy_auraoflight", {1310735}}, -- Twist of Light
  {"HUNTER_BEAST_MASTERY", "HUNTER", "Beast Mastery", "ability_hunter_beasttaming", {19574}}, -- Bestial Wrath
  {"HUNTER_MARKSMANSHIP", "HUNTER", "Marksmanship", "ability_marksmanship", {1310687, 1310785, 1310786}}, -- Sniper Shot
  {"HUNTER_SURVIVAL", "HUNTER", "Survival", "ability_hunter_swiftstrike", {1310533}}, -- Lacerating Strikes
  {"ROGUE_ASSASSINATION", "ROGUE", "Assassination", "ability_rogue_eviscerate", {1310703}}, -- Venom
  {"ROGUE_COMBAT", "ROGUE", "Combat", "ability_backstab", {13750}}, -- Adrenaline Rush
  {"ROGUE_SUBTLETY", "ROGUE", "Subtlety", "ability_stealth", {1310721}}, -- Thousand Cuts
  {"PRIEST_DISCIPLINE", "PRIEST", "Discipline", "spell_holy_wordfortitude", {10060}}, -- Power Infusion
  {"PRIEST_HOLY", "PRIEST", "Holy", "spell_holy_holybolt", {401859, 1240826, 1240827}}, -- Prayer of Mending
  {"PRIEST_SHADOW", "PRIEST", "Shadow", "spell_shadow_shadowwordpain", {15473}}, -- Shadowform
  {"SHAMAN_ELEMENTAL", "SHAMAN", "Elemental", "spell_nature_lightning", {408490, 1238299, 1238300}}, -- Lava Burst
  {"SHAMAN_ENHANCEMENT", "SHAMAN", "Enhancement", "spell_nature_lightningshield", {425336}}, -- Rage of the Farseer
  {"SHAMAN_RESTORATION", "SHAMAN", "Restoration", "spell_nature_magicimmunity", {408521, 1239242, 1239243}}, -- Riptide
  {"MAGE_ARCANE", "MAGE", "Arcane", "spell_holy_magicalsentry", {12042}}, -- Arcane Power
  {"MAGE_FIRE", "MAGE", "Fire", "spell_fire_firebolt02", {11129}}, -- Combustion
  {"MAGE_FROST", "MAGE", "Frost", "spell_frost_frostbolt02", {11426, 13031, 13032, 13033}}, -- Ice Barrier
  {"WARLOCK_AFFLICTION", "WARLOCK", "Affliction", "spell_shadow_deathcoil", {1316697}}, -- Wrack
  {"WARLOCK_DEMONOLOGY", "WARLOCK", "Demonology", "spell_shadow_metamorphosis", {425464}}, -- Demonic Pact
  {"WARLOCK_DESTRUCTION", "WARLOCK", "Destruction", "spell_shadow_rainoffire", {412758, 1293812, 1293813}}, -- Incinerate
  {"DRUID_BALANCE", "DRUID", "Balance", "spell_nature_starfall", {24858}}, -- Moonkin Form
  {"DRUID_FERAL_COMBAT", "DRUID", "Feral Combat", "ability_racial_bearform", {417141}}, -- Berserk
  {"DRUID_RESTORATION", "DRUID", "Restoration", "spell_nature_healingtouch", {408120, 1238214, 1238215}}, -- Wild Growth
}

-- Populate the usual single/multiple selection control without replacing Player
-- Class, changing imported class/spec IDs, or altering assigned-role detection.
Private.forever_spec_types = {}
Private.forever_specs_sorted = {}
local byKey = {}
for _, entry in ipairs(specializations) do
  local key, class, name, icon = entry[1], entry[2], entry[3], entry[4]
  byKey[key] = entry
  local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
  Private.forever_spec_types[key] = "|TInterface\\Icons\\" .. icon .. ":0|t " .. className .. " - " .. name
  Private.forever_specs_sorted[#Private.forever_specs_sorted + 1] = key
end

local function KnownByPlayer(spellID)
  -- Query player spell knowledge, including passives; do not inspect pet spells,
  -- buffs or CDM frames. Unavailable/restricted results do not match.
  local api = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell or IsSpellKnown
  if not api then return false end
  local ok, known = pcall(api, spellID)
  if not ok or (issecretvalue and issecretvalue(known)) then return false end
  return known == true
end

function Private.ExecEnv.IsForeverSpecialization(key)
  local entry = byKey[key]
  if not entry then return false end
  local _, class = UnitClass("player")
  if (issecretvalue and issecretvalue(class)) or class ~= entry[2] then return false end
  -- Check only published IDs for the selected tree, with no spell database scan,
  -- talent UI access, caching of combat results, or writes to Blizzard frames.
  for _, spellID in ipairs(entry[5]) do
    if KnownByPlayer(spellID) then return true end
  end
  return false
end
