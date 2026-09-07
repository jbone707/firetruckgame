extends RefCounted
## Shared base class for test files under tests/test_*.gd.
##
## A test file extends this, exposes zero-argument methods named test_*, and
## calls the assert_* helpers below. run_tests.gd discovers test files,
## instantiates them, calls every test_* method, and records each helper
## call's outcome through _record() rather than raising on the first
## failure, so one failing assertion does not hide the rest of a test.

## Populated by the runner before each test method runs, then read back
## after to build the pass/fail report. Each entry:
## {passed: bool, message: String}.
var results: Array[Dictionary] = []


func assert_true(condition: bool, message: String) -> void:
	_record(condition, message)


func assert_false(condition: bool, message: String) -> void:
	_record(not condition, message)


func assert_eq(actual, expected, message: String) -> void:
	_record(actual == expected, "%s (actual=%s, expected=%s)" % [message, actual, expected])


func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	var passed: bool = absf(actual - expected) <= tolerance
	_record(passed, "%s (actual=%s, expected=%s, tolerance=%s)" % [message, actual, expected, tolerance])


func _record(passed: bool, message: String) -> void:
	results.append({"passed": passed, "message": message})
