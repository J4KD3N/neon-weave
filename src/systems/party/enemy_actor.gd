## An enemy standing in the world. Data comes from the `enemies` content
## kind; the map places instances by cell.
class_name EnemyActor
extends WorldActor

var enemy_id: String = ""
var entry: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO
var archetype: String = "rusher"
var awareness: int = 5
var stats: Dictionary = {}
var abilities: Array[String] = []
## Tier ("", "elite", "boss") and the flat bonuses it and depth grant (StatBlock.for_enemy).
var tier: String = ""
var damage_bonus: int = 0
var ap_bonus: int = 0


func setup(p_id: String, p_entry: Dictionary, p_cell: Vector2i, p_stats: Dictionary, default_awareness: int, sheet: SpriteSheet = null, tint_override: Color = Color.TRANSPARENT) -> void:
	enemy_id = p_id
	entry = p_entry
	cell = p_cell
	archetype = String(entry.get("archetype", "rusher"))
	awareness = int(entry.get("awareness", default_awareness))
	stats = p_stats
	var ab: Array = entry.get("abilities", [])
	abilities.assign(ab)
	max_hp = maxi(int(stats.get("hp", 1)), 1)
	hp = max_hp
	tier = String(stats.get("tier", ""))
	damage_bonus = int(stats.get("damage_bonus", 0))
	ap_bonus = int(stats.get("ap_bonus", 0))
	name = "%s_%d_%d" % [enemy_id, cell.x, cell.y]
	var art: Dictionary = entry.get("art", {})
	var color := Color.html(String(art.get("color", "#c94b3a")))
	if tint_override.a > 0.0:
		color = tint_override
	var label := String(entry.get("name", enemy_id))
	if tier == "elite":
		label = "Elite " + label
	build_visuals(label, color, String(art.get("shape", "capsule")), {}, sheet)
