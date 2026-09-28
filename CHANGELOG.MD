# Changelog

## Versions
## 0.13.4
- Combined Blizzard CDM Essential and Utility into one **Cooldown** trigger. Spells are detected in either category, and existing triggers convert automatically while preserving their settings.
- Fixed delayed GCD refreshes on **Spell → Cooldown/Charges/Count**.
- Fixed **Spell → Global Cooldown** trigger
- Added optional **class-pack CDM setup** function: ForeverAuras.SetupClassPackCDM
- When called, it enables CDM, populates Tracked Buffs, sets viewer visibility to Always, and enables ForeverAuras’ **Hide Blizzard’s CDM** option.
- Extended setup to restore hidden spell cooldowns to Essential or Utility while preserving already-displayed spell placements and excluding item entries from this step.
- Setup waits until out of combat, preserves unrelated settings, backs up the original configuration, and prompts for a reload when required.
- Added **Item → Ammo** trigger type.
- Supports count conditions and optional comma-separated item IDs. Leaving the filter blank counts all carried ammo; bank storage is excluded.
- Added restriction warnings for supported trigger checks and Legacy Aura spell IDs.
- Standardised the warning to one red line: **“Secret detected. Some features may be restricted in combat.”**
- Removed the old Health explanation and extra warning headings.
- Added progress texture support for restricted health, power and Blizzard Aura timers.
- Simplified spell ID tooltips and missing-rank messages.
- Fixed stale CDM state keeping removed or expired debuffs visible.
- Buff observers now attach when triggers are configured, before their first activation.
- Fixed valid spell cooldowns being skipped in “Not Displayed” because they contained buff-slot metadata.

## 0.8.6
- Fixed wand cooldown text and unwanted icon desaturation for Spell and CDM cooldown triggers. Enabled automatically.
- Improved temporary weapon-enchant and imbue detection, icons, equipment updates and expiry handling.
- Preserved observed weapon-enchant swipe duration through zoning.
- Added pulsing border and glow styles for supported Blizzard Aura highlight conditions.
- Added anchoring support for Ellesmere nameplate health bars.
- Fixed automatic text placement when text dimensions are restricted.
- Fixed restricted GUID handling in unit-name coloring.

## 0.7.1
Thanks [Anouhschka](https://github.com/Anouhschka)!
- Fixed errors when selecting invalid or forbidden frames as anchors.
- Fixed the frame picker confirming a previously hovered frame.
- Prevented the frame picker from selecting the ForeverAuras options window.
- Preserved texture and font-string anchoring when “Set Parent” is disabled.

## 0.7.0
- Dispel Type Indicator sub-element is now "Dispel Type Icon" and "Dispel Type Border", and the visuals on the border have been corrected.

## 0.6.21
- Performance Fixes
- Conditioning Aura Highlight fixes for Blizzard Aura
- Aspect Ratio / Zoom fixes for Blizzard Aura

## 0.6.12
- Fix GCD text issues once and for all, including in combat
- Fix Spell Cooldown "On Cooldown" conditioning
- Fix Debuffs via CDM on Target Swipe / Text showing "0"

## 0.6.0
- Fix Shadow Text Offsets
- Fix Dispel Indicator display for Blizzard Aura Trigger
- Add Spell -> Queued Action Trigger
- Add Condition for Spell Usable (when readable) to CDM Trigger
- Add Specialization Load condition for Forever - Note this is only activated when the last talent for each Specialization is known.

## 0.3.3
- Fix Spell ID Integration from iterating and causing crashes

## 0.2.1
- Fix previews of Blizzard CDM / Blizzard Aura Trigger
- Using the Blizzard Aura trigger, you can now add spell IDs using just one spell ID to match all names, similar to Aura (Legacy) logic
- Blizzard Aura Triggers "Force Perfect Pixel Border" is now usable
- Remove warning about being unable to save auras

## 0.1.217
- Added remaining time to CDM Buff/Debuff

## 0.1.212
- Fix Name multi matching Buff/Debuff CDM Trigger

## 0.1.210
- Fix CDM Trigger Combat handler
- Add Spell in Range condition

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