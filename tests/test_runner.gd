## Headless unit-test runner.
##
##   godot --headless --path . -s tests/test_runner.gd
##
## Discovers `tests/unit/test_*.gd`, instantiates each [TestCase], runs every
## `test_*` method, prints a report and exits 1 on any failure.
##
## Tests run in the first process frame, not in `_initialize`: the root
## window is not inside the tree until initialisation finishes, so nodes
## added during `_initialize` never receive `_ready`.
##
## A runtime script error aborts the test method without recording a
## failure, so CI also greps the log for "SCRIPT ERROR".
extends SceneTree

const TEST_DIR := "res://tests/unit"

var _ran := false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var failed := run_all()
	quit(1 if failed > 0 else 0)
	return true


## Runs every test file; returns the number of failed tests.
func run_all() -> int:
	var passed := 0
	var failed := 0
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for file: String in files:
		if not (file.begins_with("test_") and file.get_extension() == "gd"):
			continue
		var path: String = TEST_DIR.path_join(file)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL %s: script does not compile" % path)
			failed += 1
			continue
		var instance: Object = script.new()
		if not instance is TestCase:
			print("FAIL %s: does not extend TestCase" % path)
			failed += 1
			continue
		var case: TestCase = instance
		print(file)
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			case.reset()
			case.before_each()
			case.call(name)
			case.after_each()
			if case.failures.is_empty():
				passed += 1
				print("  PASS %s" % name)
			else:
				failed += 1
				print("  FAIL %s" % name)
				for failure: String in case.failures:
					print("       %s" % failure)
	print("")
	print("%d passed, %d failed" % [passed, failed])
	return failed
