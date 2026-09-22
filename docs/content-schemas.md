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
| companions | name, race, class, dialogue {recruit,talk,banter}, quest | short_name, faction ("" for none), romanceable, approval_start, scenes [{id, label, dialogue, requires, quarters (level), once (default true), romance (only on a romanceable companion; hidden while `NarrativeState.romance` names someone else), dead (offered for a companion with `<id>_dead` instead of one in the party)}] (S35, S37 D-092) |
| locales | name | ui {English source: text}, content {kind.id.path: text} (S55; see docs/localization.md); pseudo: true makes the entry a transform instead of a table |
| lore | name, text, order | source; found ids live in the narrative state and read in the Archive |
| endings | name, summary, when | priority (highest holding wins; 0 for the drift), epilogue {companion: {alive, dead, absent, taken?, loyal?, romanced?, lost?}} read down a ladder (lost/dead, taken, romanced, loyal, alive, absent; a missing rung falls through), modifiers [{when, text}] paragraphs added when their conditions hold (S36, D-091; S37; S43, D-098) |
| difficulties | name, rules | summary (the title screen's blurb), order, default (exactly one in the base game); rules is an overlay {rules entry id: {field: value}} written over that entry for the story (S50): the base game ships story, balanced (the default, no overlay) and tactician; the validator refuses a field the rules entry does not have |
| dialogue | name, nodes (or kind "banter" + lines) | act (1–3, counted by the reactivity test, S44); start (string or [{node, requires}]); a node may carry `voice` (a companion id or "player"): the speaker borrows that voice and the panel says so (S40) |
| enemies | name, family, archetype, stats, abilities, art | art.sheet (a sprites id that exists) or art.placeholder "rig" (S56: one or the other, the validator refuses neither); tier, awareness, xp, loot (resources, cipher_chance, item_chance, item_rarity), traits (same vocabulary as races) |
| factions | name, color, rivals, joinable_act | summary, envoy (npc id), vendor (merchant id), area (map id), join_reputation {faction: delta} applied on joining |
| items | name, slot (weapon / armour / trinket / cyberware), art | stat_mods, damage_bonus, weight, price, min_rarity, families, craft {cost, workshop}, summary |
| affixes | name, slots (["any"] or slot names), weight | prefix (false = suffix), stat_mods, damage_bonus, min_rarity, summary |
| maps | name, biome, spawn_marker, legend, rows | npcs (companion / merchant / npc, each with an optional `when`; a companion placement also waits on the flag and never stands in once dead, S38), pickups, enemies, transitions, triggers, doors, buildings |
| merchants | name, stock [{id,label,cost,effect}] | art; effect keys heal_fraction, grant, item (a common instance into the pack) |
| npcs | name, dialogue | art.color (also the portrait's colour, S52), race (optional: its overlay on the portrait), short_name, faction, art |
| origins | name, dialogue_tag | stat_mods, traits, unlock_flag (earned for the account when a playthrough sets it), unlock_blurb (shown on the creator while the origin is locked, S51) |
| parties | name, members | summary |
| pickups | name, grants or dialogue, art | rarity (placement-side); grants.item = true drops an item of the pickup rarity; grants.lore = true finds the next fragment |
| quests | name, start, stages {id: {summary, objectives?, shard_site? {pickup, template? (only placed in that Shard template, S41)}, complete?, next?, next_toast?, branches? [{when, next, toast?}]}} | companion, main, faction, auto_start. start_when (conditions; the quest starts itself when they first hold, with start_toast; S40). Branches (S36): the first whose `when` holds wins once the objectives are done; `next` is the fallback; a stage with branches and no objectives forks at once |
| races | name, overlay {kind,color} | art.sheet or art.placeholder "rig" (S56), stat_mods, art.sheet, playable (false = companion-only), cyberware_slots, traits (D-085: resist {type: fraction}, regen_on_surface {surface: hp}, detect_hidden N, salvage_bonus, mend_after_combat, bonus_abilities [ids], ability_damage_bonus {id: n}, heal_immune_types [types], talent_cost_mod, tags [..]) |
| resources | name, max | builds_on, gain_per_cast, damage_per_stack, lock_ap_at_max, vent_ability, kind "marks", mark, max_per_target, gain_on_kill, gain_on_surface, gain_on_stealth, reveal_at_max, absorb {type,fraction}, gain_per_absorbed |
| rules | name | lighting: ambient, glow_energy, glow_radius, max_lights, party_light {energy, radius} (S56); performance: the budget (max_cells, max_nodes, max_enemies, max_pickups, logic_ms, frame_ms) tools/perf_budget.gd measures every map and the largest Shard against (S53); appearance: tones and accents ({id, name, color}) the creator offers (S51; a sheet saves the ids under `appearance`, empty = the race's default look; the placeholder rig paints them, a sprite sheet swaps its `skin` and `accent` palette roles); combat: the CombatRules tunables (a `difficulties` entry overlays any rules entry for the story, S50; S48 adds boss_telegraph_round: a boss uses no 3-AP ability in its first round(s); rest_after_victory: the standing party regains this fraction of max HP after a win; depth_hp_per_level 0.10 and boss_hp_mult 2.5 since S48); demo: end_flag, enabled (false in the base game; `--demo` turns the boundary on); credits: lines (rolled on the ending panel, S43) | per-rule fields (combat incl. surface_evasion, surface_resist {surface: {type: fraction}} and surface_status {surface: {status: turns}}, attributes, progression, loot, demo) |
| shards | name, biome, tiles, rooms, enemies | corridors, surfaces, pickups, features, requires_unlock (Beacon), requires_flag (story), remix {families, templates} (pools filled by rule, D-089), grate_patch_chance, debris_density, size  enemies.extra_groups_max caps the groups depth adds (S48) |
| sprites | image or sheet, frame | see docs/art-pipeline.md |
| subclasses | name, class, abilities | stat_mods, damage_bonus, summary |
| talents | name, branch, tier, cost, effects | requires, summary |
| tiles | name, layer, walkable, art | art.glow (a palette role: the tile gets a point light of that colour, S56), blocks_sight, cover, height, surface (mana_pool / conduit / corrosive / spore / echo / null), door, waypoint, sound |
| achievements | name, steam_id, when (conditions) | summary |
| audio | name, kind (sfx or music), synth or file | volume_db, loop, summary |

`tools/validate_mods.gd` and `ContentValidator` check every row above plus the vocabularies below (S45).

Effect keys (triggers, sequence steps and dialogue choices alike since S39): approval, flags, recruit, quest, reputation, toast,
open_doors, enemies ([{type, cell} or {type, offset: [dx, dy] from the leader}, tier?]), victory_flag, grant, lore (a fragment id), dialogue, transition, join_faction,
map_edits [{map?, cell, tile}], sequence [steps: effects + camera + pause + when (a step skipped when its conditions fail, S41)], ending (true), dismiss (a companion id: off the roster and out of the party; flags are the content's), victory_flag (one flag or a list),
romance ({commit: id} | {end: true}; a commitment is refused while another stands).
Condition keys (`requires` / `when` / `done_when`): flags, origin_tag,
race, race_tag, class, approval, reputation, recruited (walking with the party:
recruited and not waiting at the Bastion, D-093), not_recruited, quest,
faction (the joined faction id, "" for none yet), not_faction, party_approval_min
(every recruited companion at or above n), romance (the committed companion id,
"" for nobody), not_romance, romance_open (nobody, or that companion),
party_race and party_race_tag (anyone walking with the party, S44), attribute
({name: {min, max}} on the leader's creator attributes, S44), disguised (true when
the leader's race carries the `disguise` tag and arcane >= rules/attributes.disguise_arcane_min, S44).
