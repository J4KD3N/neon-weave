extends TestCase

var registry: ContentRegistry
var bastion: BastionState
var ledger: Ledger


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	bastion = BastionState.new()
	bastion.setup(registry.get_all("buildings"), {})
	ledger = Ledger.new()


func after_each() -> void:
	registry.free()


func test_setup_orders_buildings_and_starts_at_level_zero() -> void:
	assert_eq(bastion.order, ["beacon", "medbay", "workshop", "arcanum", "archive", "garden", "quarters"])
	for id: String in bastion.order:
		assert_eq(bastion.level(id), 0)
		assert_eq(bastion.max_level(id), 2)
	assert_eq(bastion.depth(), 1)
	assert_true(is_equal_approx(bastion.heal_fraction(), 0.25))
	assert_eq(bastion.hp_bonus(), 0)
	assert_eq(bastion.damage_bonus(), 0)


func test_saved_levels_are_restored_and_clamped() -> void:
	var b := BastionState.new()
	b.setup(registry.get_all("buildings"), {"beacon": 1, "workshop": 9, "ghost": 3})
	assert_eq(b.level("beacon"), 1)
	assert_eq(b.level("workshop"), 2, "clamped to max")
	assert_false(b.has("ghost"))
	assert_eq(b.to_dict(), {"beacon": 1, "medbay": 0, "workshop": 2, "arcanum": 0, "archive": 0, "garden": 0, "quarters": 0})


func test_upgrade_needs_the_cost_and_spends_it() -> void:
	assert_eq(bastion.next_cost("beacon"), {"salvage": 15, "aether": 2})
	assert_contains(bastion.can_upgrade("beacon", ledger), "cannot afford")
	assert_false(bastion.upgrade("beacon", ledger))
	ledger.bank({"salvage": 20, "aether": 2})
	assert_eq(bastion.can_upgrade("beacon", ledger), "")
	assert_true(bastion.upgrade("beacon", ledger))
	assert_eq(bastion.level("beacon"), 1)
	assert_eq(ledger.total("salvage"), 5)
	assert_eq(ledger.total("aether"), 0)
	assert_eq(bastion.depth(), 2)


func test_max_level_and_unknown_building() -> void:
	ledger.bank({"salvage": 999, "aether": 99, "ciphers": 9})
	assert_true(bastion.upgrade("beacon", ledger))
	assert_true(bastion.upgrade("beacon", ledger))
	assert_eq(bastion.level("beacon"), 2)
	assert_eq(bastion.can_upgrade("beacon", ledger), "already at max level")
	assert_eq(bastion.next_cost("beacon"), {})
	assert_eq(bastion.can_upgrade("chapel", ledger), "unknown building")
	assert_eq(bastion.depth(), 3)


func test_effects_sum_across_buildings() -> void:
	ledger.bank({"salvage": 999, "aether": 99, "ciphers": 9})
	bastion.upgrade("workshop", ledger)
	bastion.upgrade("workshop", ledger)
	bastion.upgrade("medbay", ledger)
	var fx := bastion.effects()
	assert_eq(int(fx["hp_bonus"]), 4)
	assert_eq(int(fx["damage_bonus"]), 1)
	assert_true(is_equal_approx(float(fx["heal_fraction"]), 0.6))
	assert_eq(int(fx["depth"]), 1)


func test_menu_render_lists_buildings_costs_and_launch() -> void:
	ledger.bank({"salvage": 12})
	var text := BastionMenu.render(bastion, ledger)
	assert_contains(text, "THE BASTION")
	assert_contains(text, "[1] Beacon  L0/2")
	assert_contains(text, "15 salvage, 2 aether  (cannot afford")
	assert_contains(text, "[3] Workshop  L0/2")
	assert_contains(text, "next: Plating: +2 max HP for everyone. — 12 salvage\n")
	assert_contains(text, "[N] Launch a Shard at depth 1")
	assert_eq(BastionState.describe_cost({}), "free")


func test_ledger_v2_persists_buildings_and_migrates_v1() -> void:
	var l := Ledger.new()
	l.buildings = {"beacon": 1}
	var d := l.to_dict()
	assert_eq(d["version"], Ledger.VERSION)
	assert_eq(d["buildings"], {"beacon": 1})
	var v1 := {"version": 1, "resources": {"salvage": 3, "aether": 0, "ciphers": 0}, "xp": 2, "runs_completed": 1, "runs_wiped": 0, "kills": 4}
	var migrated := Ledger.migrate(v1)
	assert_eq(migrated["version"], Ledger.VERSION)
	assert_eq(migrated["builds"], {}, "v3 adds empty builds")
	assert_eq(migrated["buildings"], {})
	var back := Ledger.new()
	back.apply(migrated)
	assert_eq(back.total("salvage"), 3)
	assert_eq(back.buildings, {})


func test_ledger_spend_is_all_or_nothing() -> void:
	ledger.bank({"salvage": 10, "aether": 1})
	assert_false(ledger.spend({"salvage": 5, "aether": 2}))
	assert_eq(ledger.total("salvage"), 10, "nothing spent on refusal")
	assert_true(ledger.spend({"salvage": 5, "aether": 1}))
	assert_eq(ledger.resources, {"salvage": 5, "aether": 0, "ciphers": 0})
	assert_true(ledger.can_afford({}))
