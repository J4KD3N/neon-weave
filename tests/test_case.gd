## Base class for unit tests. Subclass in `tests/unit/test_*.gd`; every
## method starting with `test_` is run by `tests/test_runner.gd`.
## Zero dependencies on purpose (see docs/decisions.md D-006).
class_name TestCase
extends RefCounted

var failures: Array[String] = []


## Runs before every test method.
func before_each() -> void:
	pass


## Runs after every test method.
func after_each() -> void:
	pass


func reset() -> void:
	failures.clear()


func fail(message: String) -> void:
	failures.append(message)


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		fail("expected true" + _suffix(message))


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		fail("expected false" + _suffix(message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		fail("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual), _suffix(message)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if actual == unexpected:
		fail("expected anything but %s%s" % [var_to_str(unexpected), _suffix(message)])


func assert_contains(haystack: Variant, needle: Variant, message: String = "") -> void:
	var found := false
	if haystack is String:
		found = String(haystack).contains(String(needle))
	elif haystack is Array or haystack is PackedStringArray:
		found = needle in haystack
	elif haystack is Dictionary:
		found = (haystack as Dictionary).has(needle)
	if not found:
		fail("expected %s to contain %s%s" % [var_to_str(haystack), var_to_str(needle), _suffix(message)])


## True when any recorded string contains `fragment`.
func assert_any_contains(items: Array[String], fragment: String, message: String = "") -> void:
	for item: String in items:
		if item.contains(fragment):
			return
	fail("no item contains '%s' in %s%s" % [fragment, var_to_str(items), _suffix(message)])


static func _suffix(message: String) -> String:
	return "" if message.is_empty() else " — " + message
