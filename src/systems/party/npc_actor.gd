## A companion standing in the world before recruitment (or any talkable
## NPC). Clicking it near the leader opens its dialogue.
class_name NpcActor
extends WorldActor

var companion_id: String = ""
var entry: Dictionary = {}
var cell: Vector2i = Vector2i.ZERO


func setup(p_id: String, p_entry: Dictionary, p_cell: Vector2i, color: Color, sheet: SpriteSheet = null, overlay: Dictionary = {}) -> void:
	companion_id = p_id
	entry = p_entry
	cell = p_cell
	name = "npc_%s" % p_id
	build_visuals(String(entry.get("short_name", entry.get("name", p_id))), color, "capsule", overlay, sheet)


## A Shard merchant (`merchants` content kind): talking opens the stock, not a dialogue.
var merchant_id: String = ""


func setup_merchant(p_id: String, p_entry: Dictionary, p_cell: Vector2i, color: Color) -> void:
	merchant_id = p_id
	entry = p_entry
	cell = p_cell
	name = "merchant_%s" % p_id
	build_visuals(String(entry.get("name", p_id)), color, "capsule", {}, null)


func is_merchant() -> bool:
	return not merchant_id.is_empty()


## A generic story NPC (`npcs` content kind): talking opens its `dialogue`.
var npc_id: String = ""


func setup_npc(p_id: String, p_entry: Dictionary, p_cell: Vector2i, color: Color) -> void:
	npc_id = p_id
	entry = p_entry
	cell = p_cell
	name = "npc_%s" % p_id
	build_visuals(String(entry.get("short_name", entry.get("name", p_id))), color, "capsule", {}, null)


func is_story_npc() -> bool:
	return not npc_id.is_empty()


func dialogue_id(recruited: bool) -> String:
	var d: Dictionary = entry.get("dialogue", {})
	return String(d.get("talk" if recruited else "recruit", ""))
