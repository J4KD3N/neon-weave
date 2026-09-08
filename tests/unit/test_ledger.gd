extends TestCase

const PATH := "user://test_ledger_unit.json"


func before_each() -> void:
	_remove()


func after_each() -> void:
	_remove()


static func _remove() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_missing_file_starts_fresh() -> void:
	var l := Ledger.load_or_new(PATH)
	assert_eq(l.total("salvage"), 0)
	assert_eq(l.runs_completed, 0)
	assert_eq(l.load_error, "")


func test_save_and_load_round_trip() -> void:
	var l := Ledger.load_or_new(PATH)
	l.bank({"salvage": 7, "aether": 2, "ciphers": 1, "xp": 99})
	l.xp = 40
	l.runs_completed = 3
	l.runs_wiped = 1
	l.kills = 12
	assert_eq(l.save(), OK)
	var back := Ledger.load_or_new(PATH)
	assert_eq(back.resources, {"salvage": 7, "aether": 2, "ciphers": 1})
	assert_eq(back.xp, 40, "xp is not a resource key; bank() ignores it")
	assert_eq(back.runs_completed, 3)
	assert_eq(back.runs_wiped, 1)
	assert_eq(back.kills, 12)
	assert_eq(back.to_dict()["version"], Ledger.VERSION)


func test_bank_accumulates_and_ignores_unknown_keys() -> void:
	var l := Ledger.new()
	l.bank({"salvage": 2, "gold": 50})
	l.bank({"salvage": 3, "ciphers": 1})
	assert_eq(l.total("salvage"), 5)
	assert_eq(l.total("ciphers"), 1)
	assert_eq(l.total("gold"), 0)


func test_corrupt_file_is_reported_and_ignored() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var l := Ledger.load_or_new(PATH)
	assert_contains(l.load_error, "JSON error")
	assert_eq(l.total("salvage"), 0)


func test_migrates_pre_versioned_flat_saves() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"salvage": 4, "aether": 1, "xp": 9, "runs_completed": 2}))
	f.close()
	var l := Ledger.load_or_new(PATH)
	assert_eq(l.total("salvage"), 4)
	assert_eq(l.total("aether"), 1)
	assert_eq(l.xp, 9)
	assert_eq(l.runs_completed, 2)
	assert_eq(l.save(), OK)
	var again := Ledger.load_or_new(PATH)
	assert_eq(again.total("salvage"), 4)
