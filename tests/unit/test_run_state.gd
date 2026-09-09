extends TestCase

var run: RunState


func before_each() -> void:
	run = RunState.new()
	run.begin("shard_x", 5)


func test_begin_sets_shard_and_clears() -> void:
	assert_true(run.in_shard)
	assert_eq(run.shard_id, "shard_x")
	assert_true(run.is_empty())
	run.begin("", 0)
	assert_false(run.in_shard)


func test_roll_ranges_and_scalars() -> void:
	for _i: int in 50:
		var r := run.roll({"salvage": [2, 5], "aether": 1, "xp": [3, 3]})
		assert_true(int(r["salvage"]) >= 2 and int(r["salvage"]) <= 5, "salvage %d" % r["salvage"])
		assert_eq(r["aether"], 1)
		assert_eq(r["ciphers"], 0)
		assert_eq(r["xp"], 3)


func test_cipher_chance_extremes() -> void:
	assert_eq(run.roll({"cipher_chance": 0.0})["ciphers"], 0)
	assert_eq(run.roll({"cipher_chance": 1.0})["ciphers"], 1)
	assert_eq(run.roll({"ciphers": 1, "cipher_chance": 1.0})["ciphers"], 2)


func test_collect_accumulates_and_take_snapshots() -> void:
	run.collect({"salvage": 2, "xp": 5})
	run.collect({"salvage": [3, 3], "aether": 1, "xp": 1})
	assert_eq(run.haul, {"salvage": 5, "aether": 1, "ciphers": 0})
	assert_eq(run.xp, 6)
	assert_false(run.is_empty())
	var t := run.take()
	assert_eq(t, {"salvage": 5, "aether": 1, "ciphers": 0, "xp": 6, "items": []})
	run.clear()
	assert_true(run.is_empty())
	assert_eq(t["salvage"], 5, "take() returned a copy")


func test_same_seed_same_rolls() -> void:
	var a := RunState.new()
	a.begin("s", 9)
	var b := RunState.new()
	b.begin("s", 9)
	for _i: int in 5:
		assert_eq(a.roll({"salvage": [1, 100]}), b.roll({"salvage": [1, 100]}))


func test_describe() -> void:
	assert_eq(RunState.describe({"salvage": 3, "aether": 0, "ciphers": 1, "xp": 2}), "+3 salvage, +1 ciphers, +2 xp")
	assert_eq(RunState.describe({}), "nothing")
	assert_eq(run.summary(), "haul S0 A0 C0 · XP 0 · kills 0")
