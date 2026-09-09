## Per-kind content schemas: every base entry carries the fields its system
## reads. Mirrors docs/content-schemas.md; extend both together.
extends TestCase

## kind -> required keys. A key written "a|b" means at least one of them.
const SCHEMAS: Dictionary = {
	"abilities": ["name", "sound", "ap", "range", "damage", "accuracy"],
	"achievements": ["name", "steam_id", "when"],
	"audio": ["name", "kind", "synth|file"],
	"biomes": ["name", "palette"],
	"branches": ["name", "color"],
	"buildings": ["name", "order", "levels"],
	"classes": ["name", "branches", "resource", "stats", "abilities", "subclasses"],
	"companions": ["name", "race", "class", "dialogue", "quest"],
	"dialogue": ["name", "nodes|lines"],
	"enemies": ["name", "family", "archetype", "stats", "abilities", "art"],
	"factions": ["name", "color", "rivals", "joinable_act"],
	"maps": ["name", "biome", "spawn_marker", "legend", "rows"],
	"merchants": ["name", "stock"],
	"npcs": ["name", "dialogue"],
	"origins": ["name", "dialogue_tag"],
	"parties": ["name", "members"],
	"pickups": ["name", "grants|dialogue", "art"],
	"quests": ["name", "start", "stages"],
	"races": ["name", "overlay"],
	"resources": ["name", "max"],
	"rules": ["name"],
	"shards": ["name", "biome", "tiles", "rooms", "enemies"],
	"sprites": ["image|sheet", "frame"],
	"subclasses": ["name", "class", "abilities"],
	"talents": ["name", "branch", "tier", "cost", "effects"],
	"tiles": ["name", "layer", "walkable", "art"],
}

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


func test_every_kind_has_a_schema_and_every_entry_meets_it() -> void:
	for kind: String in registry.kinds():
		assert_true(SCHEMAS.has(kind), "content kind %s has no schema; add it to SCHEMAS and docs/content-schemas.md" % kind)
	for kind: String in SCHEMAS:
		var entries := registry.get_all(kind)
		if kind != "sprites":
			assert_true(entries.size() >= 1, "kind %s has entries" % kind)
		for e: Dictionary in entries:
			for key: String in SCHEMAS[kind]:
				var ok := false
				for alt: String in key.split("|"):
					if e.has(alt):
						ok = true
				assert_true(ok, "%s/%s lacks %s" % [kind, e["id"], key])
			for prov: String in ["_kind", "_source", "_path"]:
				assert_true(e.has(prov), "%s/%s provenance %s" % [kind, e["id"], prov])
			assert_eq(e["_kind"], kind)


func test_ids_are_file_safe_and_names_non_empty() -> void:
	var valid := RegEx.new()
	valid.compile("^[a-z0-9_]+$")
	for kind: String in SCHEMAS:
		for e: Dictionary in registry.get_all(kind):
			assert_true(valid.search(String(e["id"])) != null, "%s/%s id is lowercase snake_case" % [kind, e["id"]])
			if e.has("name"):
				assert_false(String(e["name"]).strip_edges().is_empty(), "%s/%s name" % [kind, e["id"]])
