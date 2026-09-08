## Tunable combat constants, loaded from the `rules/combat` content entry
## with defaults for anything missing.
class_name CombatRules
extends RefCounted

var ap_per_turn: int = 4
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


static func from_entry(entry: Dictionary) -> CombatRules:
	var r := CombatRules.new()
	r.ap_per_turn = int(entry.get("ap_per_turn", r.ap_per_turn))
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
	return r
