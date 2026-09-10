# Content schemas

Every content kind is a folder under `content/` (or a mod's `content/`),
one JSON object per file, id = file name. The registry adds `_kind`,
`_source` and `_path`. `tests/unit/test_content_schemas.gd` enforces the
required keys below on every base entry and fails when a kind appears
without a schema; keep the two in step.

| Kind | Required | Optional (read by) |
|---|---|---|
| abilities | name, ap, range, damage [min,max], accuracy | sound, damage_type, requires_los, targets ("self"), effect (vent/mark/detonate/stealth/silence/root/summon/chain/taunt/poison/counter), mark, damage_per_mark, duration, cooldown, resource_cost, heal, summon, summon_max, summon_count, aoe (radius), chain_targets, chain_range, chain_fraction, poison_damage, spread, counter_damage |
| biomes | name, palette (16 roles) | recolors |
| branches | name, color | summary |
| buildings | name, order, levels [{cost, effects, blurb}] | levels[].unlocks; effect keys read: depth, heal_fraction, hp_bonus, damage_bonus, respec, respec_refund, archive, aether_per_fragment, garden, aether_on_return, quarters |
| classes | name, branches, resource {id,name}, stats, abilities, subclasses | growth, unlocks, subclass_level, capstone (ability at `capstone_level` levels in the class) |
| companions | name, race, class, dialogue {recruit,talk,banter}, quest | short_name, faction, romanceable, approval_start, scenes [{id, label, dialogue, requires, quarters (level)}] (S35) |
| lore | name, text, order | source; found ids live in the narrative state and read in the Archive |
| endings | name, summary, when | priority (highest holding wins; 0 for the drift), epilogue {companion: {alive, dead, absent}} (S36, D-091) |
| dialogue | name, nodes (or kind "banter" + lines) | start (string or [{node, requires}]) |
| enemies | name, family, archetype, stats, abilities, art | tier, awareness, xp, loot (resources, cipher_chance, item_chance, item_rarity), traits (same vocabulary as races) |
| factions | name, color, rivals, joinable_act | summary, envoy (npc id), vendor (merchant id), area (map id), join_reputation {faction: delta} applied on joining |
| items | name, slot (weapon / armour / trinket / cyberware), art | stat_mods, damage_bonus, weight, price, min_rarity, families, craft {cost, workshop}, summary |
| affixes | name, slots (["any"] or slot names), weight | prefix (false = suffix), stat_mods, damage_bonus, min_rarity, summary |
| maps | name, biome, spawn_marker, legend, rows | npcs (companion / merchant / npc + when), pickups, enemies, transitions, triggers, doors, buildings |
| merchants | name, stock [{id,label,cost,effect}] | art; effect keys heal_fraction, grant, item (a common instance into the pack) |
| npcs | name, dialogue | short_name, faction, art |
| origins | name, dialogue_tag | stat_mods, traits, unlock_flag (earned for the account when a playthrough sets it), unlock_blurb |
| parties | name, members | summary |
| pickups | name, grants or dialogue, art | rarity (placement-side); grants.item = true drops an item of the pickup rarity; grants.lore = true finds the next fragment |
| quests | name, start, stages {id: {summary, objectives?, shard_site?, complete?, next?, next_toast?, branches? [{when, next, toast?}]}} | companion, main, faction, auto_start. Branches (S36): the first whose `when` holds wins once the objectives are done; `next` is the fallback; a stage with branches and no objectives forks at once |
| races | name, overlay {kind,color} | stat_mods, art.sheet, playable (false = companion-only), cyberware_slots, traits (D-085: resist {type: fraction}, regen_on_surface {surface: hp}, detect_hidden N, salvage_bonus, mend_after_combat, bonus_abilities [ids], ability_damage_bonus {id: n}, heal_immune_types [types], talent_cost_mod, tags [..]) |
| resources | name, max | builds_on, gain_per_cast, damage_per_stack, lock_ap_at_max, vent_ability, kind "marks", mark, max_per_target, gain_on_kill, gain_on_surface, gain_on_stealth, reveal_at_max, absorb {type,fraction}, gain_per_absorbed |
| rules | name | per-rule fields (combat incl. surface_evasion, surface_resist {surface: {type: fraction}} and surface_status {surface: {status: turns}}, attributes, progression, loot, demo) |
| shards | name, biome, tiles, rooms, enemies | corridors, surfaces, pickups, features, requires_unlock (Beacon), requires_flag (story), remix {families, templates} (pools filled by rule, D-089), grate_patch_chance, debris_density, size |
| sprites | image or sheet, frame | see docs/art-pipeline.md |
| subclasses | name, class, abilities | stat_mods, damage_bonus, summary |
| talents | name, branch, tier, cost, effects | requires, summary |
| tiles | name, layer, walkable, art | blocks_sight, cover, height, surface (mana_pool / conduit / corrosive / spore / echo / null), door, waypoint, sound |
| achievements | name, steam_id, when (conditions) | summary |
| audio | name, kind (sfx or music), synth or file | volume_db, loop, summary |

Trigger effect keys: approval, flags, recruit, quest, reputation, toast,
open_doors, enemies, victory_flag, grant, dialogue, transition, join_faction,
map_edits [{map?, cell, tile}], sequence [steps: effects + camera + pause], ending (true).
Condition keys (`requires` / `when` / `done_when`): flags, origin_tag,
race, race_tag, class, approval, reputation, recruited, not_recruited, quest,
faction (the joined faction id, "" for none yet), not_faction, party_approval_min
(every recruited companion at or above n).
