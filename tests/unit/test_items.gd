## Items, affixes and cyberware (S29, D-084): rolls are seeded and shaped by
## rarity, equipment changes stats through the party builder, drops ride
## the run haul (lost on a wipe, banked on extraction), crates and
## merchants and the Workshop all feed the pack, and a loadout survives a
## save. Chromed get cyberware slots from race data; nobody else does.
extends TestCase

const LEDGER := "user://test_ledger_items.json"
const SAVES := "user://test_saves_items"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
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


func test_content_is_well_formed() -> void:
	var r := world.registry
	assert_true(r.count("items") >= 10)
	assert_true(r.count("affixes") >= 6)
	for item: Dictionary in r.get_all("items"):
		assert_true(ItemSystem.SLOT_BASES.has(String(item["slot"])), "%s slot %s" % [item["id"], item["slot"]])
		for key: String in item.get("stat_mods", {}):
			assert_true(ItemSystem.STAT_KEYS.has(key), "%s stat %s" % [item["id"], key])
		if item.has("craft"):
			assert_true(Dictionary(item["craft"]).has("cost"), "%s craft cost" % item["id"])
	for affix: Dictionary in r.get_all("affixes"):
		for slot: String in affix["slots"]:
			assert_true(slot == "any" or ItemSystem.SLOT_BASES.has(slot), "%s slot %s" % [affix["id"], slot])
	var loot := r.get_entry("rules", "loot")
	assert_eq(Array(loot["slots"]).size(), 4)
	assert_eq(int(Dictionary(loot["affixes_by_rarity"])["epic"]), 2)


func test_rolls_are_seeded_and_shaped_by_rarity() -> void:
	var r := world.registry
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	assert_eq(ItemSystem.roll_drop(r, a, "epic"), ItemSystem.roll_drop(r, b, "epic"), "same seed, same drop")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i: int in 20:
		var common := ItemSystem.roll_drop(r, rng, "common")
		assert_eq(Array(common["affixes"]).size(), 0, "common rolls no affix")
		assert_eq(String(r.get_entry("items", String(common["item"])).get("min_rarity", "common")), "common", "a common roll never picks a rare-only base")
		var rare := ItemSystem.roll_drop(r, rng, "rare")
		assert_eq(Array(rare["affixes"]).size(), 1)
		var epic := ItemSystem.roll_drop(r, rng, "epic")
		assert_eq(Array(epic["affixes"]).size(), 2)
		assert_true(Array(epic["affixes"])[0] != Array(epic["affixes"])[1], "no repeated affix")
		var base_slot := String(r.get_entry("items", String(epic["item"]))["slot"])
		for id: String in epic["affixes"]:
			var slots: Array = r.get_entry("affixes", id)["slots"]
			assert_true(slots.has("any") or slots.has(base_slot), "%s allowed on %s" % [id, base_slot])
		assert_true(int(epic["uid"]) != int(rare["uid"]), "uids differ")
	var keen := ItemSystem.make("strut_blade", ["keen", "of_haste"], "epic", 1)
	assert_eq(ItemSystem.display_name(r, keen), "Keen Strut blade of Haste")
	var m := ItemSystem.mods(r, keen)
	assert_eq(int(m["damage_bonus"]), 2, "base +1 and Keen +1")
	assert_eq(int(m["stats"]["move"]), 1, "of Haste")
	assert_contains(ItemSystem.describe(r, keen), "(weapon, epic): +1 move, +2 damage")
	assert_eq(ItemSystem.describe_mods(ItemSystem.mods(r, ItemSystem.make("lucky_bolt"))), "+2 initiative")
	assert_true(ItemSystem.roll_drop(r, rng, "common", "no_such_family").has("item"), "items without families drop for any family")


func test_slots_come_from_rules_and_race() -> void:
	var r := world.registry
	var plain := ItemSystem.slot_keys(r, r.get_entry("races", "trueborn"))
	assert_eq(plain, ["weapon", "armour", "trinket_1", "trinket_2"])
	var chromed := ItemSystem.slot_keys(r, r.get_entry("races", "chromed"))
	assert_eq(chromed, ["weapon", "armour", "trinket_1", "trinket_2", "cyberware_1", "cyberware_2"], "Chromed: two cyberware slots from race data")
	assert_eq(ItemSystem.slot_base("trinket_2"), "trinket")
	assert_eq(ItemSystem.slot_base("weapon"), "weapon")
	assert_true(ItemSystem.fits(r, ItemSystem.make("weft_charm"), "trinket_2"))
	assert_false(ItemSystem.fits(r, ItemSystem.make("weft_charm"), "weapon"))
	assert_false(ItemSystem.fits(r, ItemSystem.make("reflex_port"), "trinket_1"))


func test_equipping_changes_stats_and_the_loadout_survives_a_save() -> void:
	var m := world.party.members[0]
	var hp_before := m.max_hp
	var eva_before := int(m.stats["evasion"])
	var dmg_before := m.damage_bonus
	world.ledger.items.append(ItemSystem.make("mesh_weave", ["warded"], "rare", 11))
	world.ledger.items.append(ItemSystem.make("strut_blade", ["keen"], "rare", 12))
	world.ledger.items.append(ItemSystem.make("reflex_port", [], "common", 13))
	assert_eq(world.equip(m.member_id, "armour", 11), "")
	assert_eq(int(m.stats["evasion"]), eva_before + 8, "mesh +5, warded +3")
	assert_eq(m.max_hp, hp_before, "armour with no HP leaves HP alone")
	assert_eq(world.equip(m.member_id, "weapon", 12), "")
	assert_eq(m.damage_bonus, dmg_before + 2)
	assert_eq(world.equip(m.member_id, "trinket_1", 13), "does not fit the trinket slot")
	assert_eq(world.equip(m.member_id, "cyberware_1", 13), "no such slot", "no cyberware slot on a %s" % m.race_id)
	assert_eq(world.equip(m.member_id, "armour", 99), "not in the pack")
	assert_eq(world.ledger.items.size(), 1, "two equipped, one left")
	assert_eq(world.equipment_of(m.member_id).size(), 2)
	# Save and load: the loadout rides in the ledger builds.
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	var again := world.party.members[0]
	assert_eq(int(again.stats["evasion"]), eva_before + 8, "reloaded with the armour on")
	assert_eq(again.damage_bonus, dmg_before + 2)
	assert_eq(world.ledger.items.size(), 1)
	assert_eq(world.unequip(again.member_id, "armour"), "")
	assert_eq(int(again.stats["evasion"]), eva_before)
	assert_eq(world.ledger.items.size(), 2, "back in the pack")
	assert_eq(world.unequip(again.member_id, "armour"), "nothing there")
	# Swapping into an occupied slot returns the old one to the pack.
	world.ledger.items.append(ItemSystem.make("bolt_pistol", [], "common", 14))
	assert_eq(world.equip(again.member_id, "weapon", 14), "")
	assert_true(ItemSystem.find_uid(world.ledger.items, 12) >= 0, "the strut blade came back")
	assert_eq(int(again.stats["initiative"]), int(world.party.members[0].stats["initiative"]))


func test_drops_ride_the_haul_and_bank_on_extraction_only() -> void:
	world.enter_shard("rusted_undercity", 7)
	var inst := world.drop_item("rare")
	assert_true(inst.has("item"))
	assert_eq(world.run.items.size(), 1, "unbanked")
	assert_eq(world.ledger.items.size(), 0)
	assert_false(world.run.is_empty())
	assert_contains(RunState.describe(world.run.take()), "+1 item")
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	assert_eq(world.ledger.items.size(), 1, "banked on extraction")
	assert_eq(world.run.items.size(), 0)
	# A wipe loses the haul, items included.
	world.enter_shard("rusted_undercity", 8)
	world.drop_item("common")
	world.drop_item("common")
	assert_eq(world.run.items.size(), 2)
	world._on_combat_ended("defeat")
	world.return_home()
	assert_eq(world.ledger.items.size(), 1, "the wipe took the two")
	# Off-Shard drops bank at once.
	world.drop_item("common")
	assert_eq(world.ledger.items.size(), 2)
	assert_eq(world.run.items.size(), 0)


func test_enemy_tier_decides_drops_and_bosses_always_drop() -> void:
	world.enter_shard("rusted_undercity", 9)
	var boss := world.spawn_summoned("undercity_warlord", world.leader_cell() + Vector2i(1, 0))
	boss.tier = "boss"
	var got := world.roll_enemy_drop(boss)
	assert_true(got.has("item"), "a boss always drops")
	assert_eq(String(got["rarity"]), "epic")
	var scav := world.spawn_summoned("scav", world.leader_cell() + Vector2i(2, 0))
	var drops := 0
	for _i: int in 200:
		if not world.roll_enemy_drop(scav).is_empty():
			drops += 1
	assert_true(drops > 5 and drops < 60, "a scav drops sometimes: %d of 200" % drops)
	scav.entry = scav.entry.duplicate(true)
	scav.entry["loot"] = {"item_chance": 1.0, "item_rarity": "rare"}
	var forced := world.roll_enemy_drop(scav)
	assert_eq(String(forced["rarity"]), "rare", "the entry's own loot keys win")


func test_crates_merchants_and_the_workshop_feed_the_pack() -> void:
	# A loot crate pickup drops an item of its rarity.
	world.enter_shard("rusted_undercity", 10)
	var cell := world.leader_cell()
	var actor := PickupActor.new()
	actor.setup("loot_crate", world.registry.get_entry("pickups", "loot_crate"), cell)
	actor.set_rarity("epic", world.rarity_color("epic"))
	actor.position = world.map_view.cell_to_world(cell)
	world.pickups_node.add_child(actor)
	world.pickups.append(actor)
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_true(Dictionary(gained[0]).has("item"))
	assert_eq(String(Dictionary(Dictionary(gained[0])["item"])["rarity"]), "epic")
	assert_eq(world.run.items.size(), 1)
	# The Fence sells plating into the pack.
	world.enter_map("proto_yard")
	world.ledger.bank({"salvage": 40})
	var fence := world.registry.get_entry("merchants", "undercity_fence")
	var sells_items := false
	for row: Dictionary in fence["stock"]:
		if Dictionary(row.get("effect", {})).has("item"):
			sells_items = true
	assert_true(sells_items, "the Fence stocks an item")
	world.current_merchant = "undercity_fence"
	var before := world.ledger.items.size()
	assert_eq(world.buy("plating"), "")
	assert_eq(world.ledger.items.size(), before + 1)
	assert_eq(String(Dictionary(world.ledger.items[before])["item"]), "scrap_plating")
	# Crafting needs the Workshop and Salvage.
	assert_eq(world.craft("scrap_plating"), "needs Workshop level 1")
	world.ledger.buildings["workshop"] = 1
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)
	assert_eq(world.craft("heavy_plate"), "needs Workshop level 2")
	assert_eq(world.craft("lucky_bolt"), "not craftable")
	var salvage := world.ledger.total("salvage")
	assert_eq(world.craft("scrap_plating"), "")
	assert_eq(world.ledger.total("salvage"), salvage - 10)
	assert_eq(world.ledger.items.size(), before + 2)
	world.ledger.resources["salvage"] = 0
	assert_contains(world.craft("scrap_plating"), "needs")


func test_the_pack_screen_lists_slots_pack_and_recipes() -> void:
	world.ledger.items.append(ItemSystem.make("weft_charm", [], "common", 21))
	world.ledger.items.append(ItemSystem.make("optic_suite", [], "common", 22))
	assert_true(world.open_inventory(), "opens at home")
	assert_true(world.inventory_menu.visible)
	var rows := world.inventory_rows(world.party.members[0].member_id)
	var kinds: Dictionary = {}
	for row: Dictionary in rows:
		kinds[row["kind"]] = int(kinds.get(row["kind"], 0)) + 1
	assert_eq(int(kinds["slot"]), 4)
	assert_eq(int(kinds["item"]), 2)
	assert_true(int(kinds["craft"]) >= 3)
	var text := InventoryMenu.render("h", rows, 0)
	assert_contains(text, "Weapon: empty")
	assert_contains(text, "Optic suite (cyberware): +5 evasion  (no cyberware slot)")
	# Confirm on the charm equips it into the first free trinket slot.
	for i: int in rows.size():
		if String(rows[i]["kind"]) == "item" and int(rows[i]["id"]) == 21:
			world.inventory_menu.cursor = i
	assert_true(world.confirm_inventory())
	assert_true(world.equipment_of(world.party.members[0].member_id).has("trinket_1"))
	world.close_inventory()
	assert_false(world.inventory_menu.visible)
	world.enter_shard("rusted_undercity", 3)
	assert_false(world.open_inventory(), "not in a Shard")
