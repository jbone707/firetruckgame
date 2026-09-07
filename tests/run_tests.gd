extends SceneTree
## Shared headless test runner for Fire Truck Game.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##
## Discovers every res://tests/test_*.gd file (excluding the shared base
## class tests/test_case.gd, which matches that glob but is not itself a
## test file), instantiates it, and calls every zero-argument method whose
## name starts with "test_". Each test file extends tests/test_case.gd and
## reports outcomes through its assert_true/assert_false/assert_eq/
## assert_almost_eq helpers rather than raising on first failure, so a
## single failing assertion does not hide the rest of that test method's
## checks.
##
## Prints one PASS/FAIL line per test method, then a summary line, then
## exits with code 0 only if every assertion in every test method passed.
## Any failure anywhere produces a nonzero exit code. This exit code is the
## one thing every later part relies on to trust "the tests passed" without
## reading the output, so it must never be wrong: a passing summary MUST
## come with the assertion count already checked to be greater than zero.

const TEST_DIR: String = "res://tests"
const BASE_CLASS_FILE: String = "test_case.gd"


func _initialize() -> void:
	var exit_code: int = _run_all_tests()
	quit(exit_code)


func _run_all_tests() -> int:
	var test_files: Array[String] = _discover_test_files()

	var total_methods: int = 0
	var failed_methods: int = 0
	var total_assertions: int = 0

	for file_path in test_files:
		var script: GDScript = load(file_path)
		if script == null:
			printerr("FAIL %s: could not load script" % file_path)
			failed_methods += 1
			total_methods += 1
			continue

		var probe = script.new()
		var method_names: Array[String] = []
		for method_info in probe.get_method_list():
			var method_name: String = method_info["name"]
			if method_name.begins_with("test_"):
				method_names.append(method_name)
		method_names.sort()

		if method_names.is_empty():
			print("(no test_* methods found in %s)" % file_path)
			continue

		for method_name in method_names:
			total_methods += 1
			var instance = script.new()
			instance.call(method_name)

			var method_passed: bool = true
			var failure_messages: Array[String] = []
			for result in instance.results:
				total_assertions += 1
				if not result["passed"]:
					method_passed = false
					failure_messages.append(String(result["message"]))

			var label: String = "%s::%s" % [file_path.get_file(), method_name]
			if instance.results.is_empty():
				method_passed = false
				failure_messages.append("test method made no assertions")

			if method_passed:
				print("PASS %s" % label)
			else:
				failed_methods += 1
				print("FAIL %s: %s" % [label, "; ".join(failure_messages)])

	var passed_methods: int = total_methods - failed_methods
	print("---")
	print("%d test file(s), %d test method(s), %d assertion(s): %d passed, %d failed" % [
		test_files.size(), total_methods, total_assertions, passed_methods, failed_methods
	])

	if total_methods == 0:
		print("no tests were discovered under %s" % TEST_DIR)
		return 1

	return 1 if failed_methods > 0 else 0


func _discover_test_files() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		printerr("could not open %s" % TEST_DIR)
		return found

	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.begins_with("test_") and entry.ends_with(".gd") and entry != BASE_CLASS_FILE:
			found.append("%s/%s" % [TEST_DIR, entry])
		entry = dir.get_next()
	dir.list_dir_end()

	found.sort()
	return found
