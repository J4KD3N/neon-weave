## Items v2 (S73, D-129): consumables carried in the pack and used out of
## a fight or from the action bar in one, biome drop tables through item
## families, sell-back at merchants, and cyberware that costs parts to fit.
extends TestCase

const LEDGER := "user://test_ledger_items2.json"
const SAVES := "user://test_saves_items2"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	world.settings_path = "user://test_settings_items2.json"
	world.input_path = "user://test_input_items2.json"
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.combat.animate = false


func after_each() -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(world)
	world.free()
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func test_a_consumable_is_used_out_of_a_fight_and_from_the_action_bar_in_one() -> void:
	var r := world.registry
	assert_eq(String(r.get_entry("items", "trauma_kit")["slot"]), "consumable")
	assert_eq(ItemSystem.describe_use(r.get_entry("items", "trauma_kit")["use"]), "heals 40% of max HP")
	assert_eq(ItemSystem.describe_use(r.get_entry("items", "stim_shot")["use"]), "+2 AP this turn")
	assert_eq(world.use_item("trauma_kit"), "none in the pack")
	world.ledger.items.append(ItemSystem.make("trauma_kit", [], "common", 31))
	world.ledger.items.append(ItemSystem.make("trauma_kit", [], "common", 32))
	world.ledger.items.append(ItemSystem.make("stim_shot", [], "common", 33))
	assert_eq(world.consumables_in_the_pack(), ["trauma_kit", "trauma_kit", "stim_shot"])
	assert_eq(world.use_item("trauma_kit"), "nobody is hurt")
	assert_eq(world.use_item("stim_shot"), "only in a fight")
	var m := world.party.members[1]
	m.hp = 1
	assert_eq(world.use_item("trauma_kit"), "")
	assert_eq(m.hp, 1 + int(ceil(m.max_hp * 0.2)), "shared round: half the kit to everyone")
	assert_eq(world.consumables_in_the_pack().count("trauma_kit"), 1, "one spent")
	# The pack screen and the pause menu both offer it.
	var kinds: Dictionary = {}
	for row: Dictionary in world.inventory_rows("weaver"):
		kinds[row["kind"]] = int(kinds.get(row["kind"], 0)) + 1
		if String(row["kind"]) == "use" and String(row["id"]) == "trauma_kit":
			assert_contains(String(row["label"]), "Use Trauma kit: heals 40% of max HP")
	assert_eq(int(kinds.get("use", 0)), 2, "a use row per consumable instance")
	var ids: Array[String] = []
	for item: Dictionary in world.system_items():
		ids.append(String(item["id"]))
		if String(item["id"]) == "use_trauma_kit":
			assert_contains(String(item["label"]), "Use Trauma kit (1): heals 40% of max HP")
		if String(item["id"]) == "use_stim_shot":
			assert_false(bool(item["enabled"]), "a stim is for a fight")
	assert_true(ids.has("use_trauma_kit") and ids.has("use_stim_shot"))
	# In a fight: an action per consumable, spent from the pack, gone when none are left.
	world.rules.initiative_die = 1
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	var s := world.combat.state
	var pc := s.current()
	assert_true(pc.abilities.has("use_trauma_kit") and pc.abilities.has("use_stim_shot"), "the party has the pack's actions: %s" % [pc.abilities])
	assert_false(s.active("enemy")[0].abilities.has("use_trauma_kit"), "not the enemies")
	pc.hp = 1
	assert_eq(s.can_use(pc, "use_trauma_kit", pc.cell), "")
	var before_ap := pc.ap
	var e := s.use_ability(pc, "use_trauma_kit", pc.cell)
	assert_eq(String(e["type"]), "consume")
	assert_eq(pc.hp, 1 + int(ceil(pc.max_hp * 0.4)), "the whole kit to the one who opens it")
	assert_eq(pc.ap, before_ap - 1)
	assert_eq(world.consumables_in_the_pack().count("trauma_kit"), 0, "spent from the pack")
	assert_false(pc.abilities.has("use_trauma_kit"), "none left: the action goes")
	assert_true(pc.abilities.has("use_stim_shot"))
	var e2 := s.use_ability(pc, "use_stim_shot", pc.cell)
	assert_eq(int(e2["extra_ap"]), 2)
	assert_eq(pc.ap, before_ap - 1 - 1 + 2, "one AP paid, two back")
	assert_true(s.history[s.history.size() - 1].contains("uses Stim shot: +2 AP"))
	assert_eq(world.use_item("trauma_kit"), "in a fight: use it from the action bar")


func test_drops_follow_the_biome_and_a_cache_names_its_item() -> void:
	var r := world.registry
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen: Dictionary = {}
	for _i: int in 200:
		var inst := ItemSystem.roll_drop(r, rng, "common", "null_cathedral")
		seen[String(inst["item"])] = true
	assert_true(seen.has("shock_maul") or seen.has("heavy_plate"), "the Cathedral drops its own: %s" % [seen.keys()])
	assert_false(seen.has("lucky_bolt"), "not the Undercity's")
	assert_false(seen.has("trauma_kit"), "consumables are never rolled")
	assert_true(seen.has("strut_blade") or seen.has("scrap_plating"), "the universal ones still drop")
	assert_true(ItemSystem.roll_drop(r, rng, "common", "no_such_family").has("item"), "an unknown family gets the universal items")
	var cache := r.get_entry("pickups", "supply_cache")
	assert_eq(String(Dictionary(cache["grants"])["item"]), "trauma_kit")
	var got := world.give_item("trauma_kit")
	assert_eq(String(got["item"]), "trauma_kit")
	assert_eq(world.consumables_in_the_pack(), ["trauma_kit"], "off-Shard: banked at once")
	for t: Dictionary in r.get_all("shards"):
		var pool: Array = Dictionary(t.get("pickups", {})).get("pool", [])
		var has := false
		for p: Dictionary in pool:
			if String(p["type"]) == "supply_cache":
				has = true
		assert_true(has, "%s can hold a supply cache" % t["id"])
	assert_eq(ContentValidator.validate(r, ["runtime"]).size(), 0)
	r.put("items", "zz_snack", {"name": "Snack", "slot": "consumable", "art": {"color": "#ffffff"}, "families": ["nobody"], "install": {"gold": 1}})
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "a consumable needs a use block")
	assert_any_contains(problems, "families names 'nobody'")
	assert_any_contains(problems, "install.gold is not a resource")
	r._entries["items"].erase("zz_snack")
	r._fingerprint_cache = ""


func test_the_pack_sells_back_and_cyberware_costs_parts_to_fit() -> void:
	var r := world.registry
	var blade := ItemSystem.make("strut_blade", [], "common", 41)
	var maul := ItemSystem.make("shock_maul", ["keen"], "rare", 42)
	assert_eq(ItemSystem.sell_price(r, blade), 5, "half of ten")
	assert_eq(ItemSystem.sell_price(r, maul), 13, "half of eighteen, half again for rare, floored")
	world.ledger.items.append(blade)
	world.ledger.items.append(maul)
	var fence := world.npc_at(Vector2i(17, 10)) # Dax is at (17,10); the fence is in the Bastion: use the registry directly
	world.current_merchant = "undercity_fence"
	var rows := world.merchant_rows(r.get_entry("merchants", "undercity_fence"))
	var sell_rows := 0
	for row: Dictionary in rows:
		if String(row["id"]).begins_with("sell:"):
			sell_rows += 1
			if String(row["id"]) == "sell:42":
				assert_contains(String(row["label"]), "Sell Keen Shock maul — 13 salvage")
	assert_eq(sell_rows, 2)
	var salvage := world.ledger.total("salvage")
	assert_eq(world.sell(42), "")
	assert_eq(world.ledger.total("salvage"), salvage + 13)
	assert_eq(world.ledger.items.size(), 1)
	assert_eq(world.sell(42), "not in the pack")
	world.current_merchant = ""
	assert_eq(world.sell(41), "no merchant")
	# The fence sells the consumables.
	var stock_ids: Array[String] = []
	for s: Dictionary in r.get_entry("merchants", "undercity_fence")["stock"]:
		stock_ids.append(String(s["id"]))
	assert_true(stock_ids.has("trauma_kit") and stock_ids.has("stim_shot"))
	# Cyberware costs parts to fit.
	world.protagonist = {"name": "Chrome", "race_id": "chromed", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	var suite := ItemSystem.make("optic_suite", [], "common", 43)
	world.ledger.items.append(suite)
	assert_eq(Dictionary(r.get_entry("items", "optic_suite")["install"])["salvage"], 5)
	world.ledger.resources["salvage"] = 2
	var slots := world.inventory_slots(world.party.members[0])
	var cyber := ""
	for s: String in slots:
		if s.begins_with("cyberware"):
			cyber = s
	assert_false(cyber.is_empty(), "a Chromed has the slot")
	assert_eq(world.equip("protagonist", cyber, 43), "fitting it needs 5 salvage")
	world.ledger.resources["salvage"] = 9
	assert_eq(world.equip("protagonist", cyber, 43), "")
	assert_eq(world.ledger.total("salvage"), 4, "the parts are spent")
	assert_eq(world.equip("protagonist", "weapon", 41), "", "a blade fits for nothing")
	assert_eq(world.ledger.total("salvage"), 4)
