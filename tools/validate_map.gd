extends SceneTree
## Runs MapValidator over every map resource in the project, or over one named
## on the command line.
##
## Run with:
##   godot --headless --path . --script res://tools/validate_map.gd
##   godot --headless --path . --script res://tools/validate_map.gd -- res://resources/windsor_shadetree.tres
##
## Exits 0 only when every rule passes on every map. This is a tool rather than
## a test so it can be pointed at a map that is not committed yet, but the same
## rules run inside the unit suite through tests/test_map_definition.gd, so a
## map cannot be shipped without them.

const MAP_DIR: String = "res://resources"


func _initialize() -> void:
	var paths: Array[String] = _maps_to_check()
	if paths.is_empty():
		printerr("no map resources found under %s" % MAP_DIR)
		quit(1)
		return

	var failed: int = 0
	for path in paths:
		if not _validate(path):
			failed += 1

	print("---")
	print("%d map(s) checked, %d failed" % [paths.size(), failed])
	quit(1 if failed > 0 else 0)


func _maps_to_check() -> Array[String]:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() > 0:
		var named: Array[String] = []
		for argument in arguments:
			named.append(argument)
		return named

	var found: Array[String] = []
	var directory: DirAccess = DirAccess.open(MAP_DIR)
	if directory == null:
		return found
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while entry != "":
		if not directory.current_is_dir() and entry.ends_with(".tres"):
			found.append("%s/%s" % [MAP_DIR, entry])
		entry = directory.get_next()
	directory.list_dir_end()
	found.sort()
	return found


func _validate(path: String) -> bool:
	var resource: Resource = load(path)
	var map: MapDefinition = resource as MapDefinition
	if map == null:
		printerr("%s is not a MapDefinition" % path)
		return false

	print("")
	print("%s (%s, schema %d)" % [map.display_name, path, map.schema_version])
	print("  world %.0f x %.0f units, %d road(s), %d building(s), %d hydrant(s), %d candidate(s)" % [
		map.world_bounds.size.x, map.world_bounds.size.y,
		map.roads.size(), map.buildings.size(), map.hydrants.size(),
		map.incident_candidates.size(),
	])

	var results: Array[Dictionary] = MapValidator.validate(map)
	for result in results:
		print("  %s %s" % ["PASS" if result["passed"] else "FAIL", result["rule"]])
		print("       %s" % result["detail"])
	return MapValidator.passed(results)
