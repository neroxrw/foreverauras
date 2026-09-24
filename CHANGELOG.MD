# Changelog

## Versions
## 0.1.203
- Substantial performance fix for Blizzard CDM Trigger
- Fixed fonts not displaying on first click
- Fix multi select conditioning
- Fix group select -> conditions

## 0.1.196
Improved the functionality of the Aura (Blizzard) trigger
- Added Name(s) and Exact Spell ID filter options
- Added allowed conditions for Blizzard Auras
- Improved wording

Improved the functionality of the Blizzard Cooldown Manager Trigger
- GCD Features now properly work
- By default, adding a spell into CDM will not display if you do not know the spell
- Added "Disable Spell Known Check"
- Added Name(s) and Exact Spell ID filter options

Misc fixes
- Fix several backend APIs
- Fix text being blank on Client Notice

## 0.1.180
- Improved Blizzard Aura integration

## 0.1.168
- Minor fixes for CDM

## 0.1.165
- Minor fixes for CDM Previews
- Rename CDM Trigger Dropdowns

## 0.1.161
- Fix spell cost overlay ignoring borders

## 0.1.160
- Blizzard Cooldown Manager trigger fixes.
- No longer use AuraContainer at all.

## 0.1.148
- Added new Trigger type "Blizzard Cooldown Manager"
- Added option to Hide Blizzards CDM.
- Note, the Blizzard CDM needs to be enabled for the trigger to work. If using these triggers in your Aura, the intended design is to enable the Hide Blizzard CDM option.

## 0.1.114
First released version to Curseforge for WoW Forever Beta
- Change anchor prefix from `WeakAuras:` to `ForeverAuras:`
- Fix EnchantIDs for Weapons
- Add Client save warning
- Add ItemStatus.lua
- Spelling fixes

## 0.1.103
- Add function to check if a SpellID is secret
- Change addon icon
- Remove CC warnings for other addons

## 0.1.101
- Remove "Secret Aura" type and move Blizzard controlled auras under the regular auras section on the trigger tab

## 0.1.94
- Add Private Auras warnings for Blizzard controlled auras

## 0.1.90
- Initial Repo commit after fork and adjustment of [WeakAuras2](https://github.com/WeakAuras/WeakAuras2/releases/tag/5.22.0)