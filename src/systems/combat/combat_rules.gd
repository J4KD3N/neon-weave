## Tunable combat constants, loaded from the `rules/combat` content entry
## with defaults for anything missing.
class_name CombatRules
extends RefCounted

var ap_per_turn: int = 4
## Protagonist plus companions (GDD §7: party of up to 4).
var party_max: int = 4
var base_move: int = 6
var min_hit_chance: int = 5
var max_hit_chance: int = 95
var flank_hit_bonus: int = 15
var flank_damage_mult: float = 1.25
var friendly_fire: bool = true
var story_protected: bool = true
var awareness_default: int = 5
## Enemies within this many cells of any party member join an encounter.
var engage_radius: int = 7
var first_strike_initiative_bonus: int = 10
var initiative_die: int = 20
## Ranged hit penalty when a cover tile sits between attacker and target.
var cover_hit_penalty: int = 20
## Hit bonus from higher ground (and penalty when attacking uphill).
var elevation_hit_bonus: int = 10
var elevation_damage_bonus: int = 1
## Arcane damage multiplier when casting from a mana pool.
var mana_pool_amplify: float = 1.5
## Damage dealt to everyone on a connected conduit run when one of them is shocked.
var conduit_chain_damage: int = 2
## Damage at turn start for standing in corrosive biogrowth.
var corrosive_damage: int = 2
## Attacking from hiding: hit bonus and damage multiplier, then revealed.
var ambush_hit_bonus: int = 20
var ambush_damage_mult: float = 1.5
## Enemy tiers (entry or placement `tier`): elite and boss multipliers.
var elite_hp_mult: float = 1.5
var elite_damage_bonus: int = 1
var boss_hp_mult: float = 3.0
var boss_damage_bonus: int = 2
var boss_ap_bonus: int = 1
## Depth scaling: HP x (1 + per_level x (depth - 1)); +1 damage every N depths past 1.
var depth_hp_per_level: float = 0.15
var depth_damage_every: int = 2
## Evasion granted by standing on a surface (target side): {"spore": 10}.
var surface_evasion: Dictionary = {}
## Damage fraction a surface shrugs off for whoever stands in it (target side):
## {"echo": {"tech": 0.5}} (S33). Negative is a weakness.
var surface_resist: Dictionary = {}
## Statuses a surface lays on whoever starts a turn in it: {"null": {"silenced": 1}} (S34).
var surface_status: Dictionary = {}
## Enemy positioning weights (EnemyBrain scoring).
var ai_cover_weight: int = 4
var ai_elevation_weight: int = 4
var ai_corrosive_penalty: int = 8
var ai_mana_pool_weight: int = 3
## A rusher at or under this fraction of its HP breaks off once toward its
## allies while any are still up (S28).
var ai_retreat_hp_fraction: float = 0.3


static func from_entry(entry: Dictionary) -> CombatRules:
	var r := CombatRules.new()
	r.ap_per_turn = int(entry.get("ap_per_turn", r.ap_per_turn))
	r.party_max = int(entry.get("party_max", r.party_max))
	r.base_move = int(entry.get("base_move", r.base_move))
	r.min_hit_chance = int(entry.get("min_hit_chance", r.min_hit_chance))
	r.max_hit_chance = int(entry.get("max_hit_chance", r.max_hit_chance))
	r.flank_hit_bonus = int(entry.get("flank_hit_bonus", r.flank_hit_bonus))
	r.flank_damage_mult = float(entry.get("flank_damage_mult", r.flank_damage_mult))
	r.friendly_fire = bool(entry.get("friendly_fire", r.friendly_fire))
	r.story_protected = bool(entry.get("story_protected", r.story_protected))
	r.awareness_default = int(entry.get("awareness_default", r.awareness_default))
	r.engage_radius = int(entry.get("engage_radius", r.engage_radius))
	r.first_strike_initiative_bonus = int(entry.get("first_strike_initiative_bonus", r.first_strike_initiative_bonus))
	r.initiative_die = int(entry.get("initiative_die", r.initiative_die))
	r.cover_hit_penalty = int(entry.get("cover_hit_penalty", r.cover_hit_penalty))
	r.elevation_hit_bonus = int(entry.get("elevation_hit_bonus", r.elevation_hit_bonus))
	r.elevation_damage_bonus = int(entry.get("elevation_damage_bonus", r.elevation_damage_bonus))
	r.mana_pool_amplify = float(entry.get("mana_pool_amplify", r.mana_pool_amplify))
	r.conduit_chain_damage = int(entry.get("conduit_chain_damage", r.conduit_chain_damage))
	r.corrosive_damage = int(entry.get("corrosive_damage", r.corrosive_damage))
	r.ambush_hit_bonus = int(entry.get("ambush_hit_bonus", r.ambush_hit_bonus))
	r.ambush_damage_mult = float(entry.get("ambush_damage_mult", r.ambush_damage_mult))
	r.elite_hp_mult = float(entry.get("elite_hp_mult", r.elite_hp_mult))
	r.elite_damage_bonus = int(entry.get("elite_damage_bonus", r.elite_damage_bonus))
	r.boss_hp_mult = float(entry.get("boss_hp_mult", r.boss_hp_mult))
	r.boss_damage_bonus = int(entry.get("boss_damage_bonus", r.boss_damage_bonus))
	r.boss_ap_bonus = int(entry.get("boss_ap_bonus", r.boss_ap_bonus))
	r.depth_hp_per_level = float(entry.get("depth_hp_per_level", r.depth_hp_per_level))
	r.depth_damage_every = int(entry.get("depth_damage_every", r.depth_damage_every))
	r.surface_evasion = {}
	var se: Dictionary = entry.get("surface_evasion", {})
	for key: String in se:
		r.surface_evasion[key] = int(se[key])
	r.surface_resist = {}
	var sr: Dictionary = entry.get("surface_resist", {})
	for surface: String in sr:
		var by_type: Dictionary = {}
		for t: String in sr[surface]:
			by_type[t] = float(Dictionary(sr[surface])[t])
		r.surface_resist[surface] = by_type
	r.surface_status = {}
	var ss: Dictionary = entry.get("surface_status", {})
	for surface: String in ss:
		var by_status: Dictionary = {}
		for st: String in ss[surface]:
			by_status[st] = int(Dictionary(ss[surface])[st])
		r.surface_status[surface] = by_status
	r.ai_cover_weight = int(entry.get("ai_cover_weight", r.ai_cover_weight))
	r.ai_elevation_weight = int(entry.get("ai_elevation_weight", r.ai_elevation_weight))
	r.ai_corrosive_penalty = int(entry.get("ai_corrosive_penalty", r.ai_corrosive_penalty))
	r.ai_mana_pool_weight = int(entry.get("ai_mana_pool_weight", r.ai_mana_pool_weight))
	r.ai_retreat_hp_fraction = float(entry.get("ai_retreat_hp_fraction", r.ai_retreat_hp_fraction))
	return r
