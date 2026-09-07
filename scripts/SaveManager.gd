extends RefCounted
class_name SaveManager
## Credits and upgrade ownership, persisted under user:// (handoff section 9).
##
## Deliberately small. It holds a schema version, a nonnegative integer credit
## balance and one boolean, validates every one of them on load, and treats a
## missing or malformed file as recoverable rather than fatal: a player who
## loses a save should start a fresh shift, not meet an error.
##
## Writes go to a temporary file which is then renamed over the real one, so a
## crash midway through a write leaves the previous save intact rather than a
## half-written file that loads as garbage.

## Version 2 (Milestone 5 Part 2) adds "map_id": which neighbourhood the player
## last chose. A version 1 file is MIGRATED rather than rejected: it is a
## complete, valid save that simply predates there being more than one map, and
## the older rule here, which started fresh on any version it did not recognise,
## would have taken the credits off every existing player to add a field with an
## obvious default. Rejection is for a file that cannot be trusted, not for one
## that is merely old.
const SCHEMA_VERSION: int = 2

## The oldest version this build can still read. Anything below it is genuinely
## unreadable rather than simply old.
const OLDEST_READABLE_VERSION: int = 1

const SAVE_PATH: String = "user://fire_truck_game_save.json"
const TEMP_PATH: String = "user://fire_truck_game_save.json.tmp"

var credits: int = 0
var tank_upgrade_owned: bool = false

## Which map the player last played, as a MapCatalogue id. Never a resource
## path: a path in a save file is a promise about where a file lives that a
## later build has to keep.
var map_id: String = MapCatalogue.DEFAULT_ID

## Set when the last load fell back to defaults, so the caller can say so.
var last_load_diagnostic: String = ""

var _save_path: String = SAVE_PATH
var _temp_path: String = TEMP_PATH


## Points this instance at different files, so a test does not overwrite the
## player's real save.
func use_paths(save_path: String, temp_path: String) -> void:
	_save_path = save_path
	_temp_path = temp_path


func reset_to_defaults() -> void:
	credits = 0
	tank_upgrade_owned = false
	map_id = MapCatalogue.DEFAULT_ID


## True when the file was read and every field validated. False means defaults
## are in place and last_load_diagnostic says why, which is not an error state.
func load_game() -> bool:
	last_load_diagnostic = ""
	reset_to_defaults()

	if not FileAccess.file_exists(_save_path):
		last_load_diagnostic = "no save file yet, starting fresh"
		return false

	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		last_load_diagnostic = (
			"save file could not be opened (error %d), starting fresh" % FileAccess.get_open_error()
		)
		push_warning(last_load_diagnostic)
		return false

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_load_diagnostic = "save file is not valid JSON, starting fresh"
		push_warning(last_load_diagnostic)
		return false

	var data: Dictionary = parsed
	var version: Variant = data.get("schema_version", null)
	if typeof(version) != TYPE_FLOAT and typeof(version) != TYPE_INT:
		last_load_diagnostic = "save file has no usable schema version, starting fresh"
		push_warning(last_load_diagnostic)
		return false
	var file_version: int = int(version)
	if file_version < OLDEST_READABLE_VERSION or file_version > SCHEMA_VERSION:
		last_load_diagnostic = (
			"save file is schema version %d, this build reads %d to %d, starting fresh"
			% [file_version, OLDEST_READABLE_VERSION, SCHEMA_VERSION]
		)
		push_warning(last_load_diagnostic)
		return false

	# Credits must be a whole number and must not be negative. JSON has no
	# integer type, so a float that is not whole is rejected rather than
	# silently truncated: 100.7 in a save file means the file was tampered with
	# or written by something else.
	var raw_credits: Variant = data.get("credits", null)
	if typeof(raw_credits) != TYPE_FLOAT and typeof(raw_credits) != TYPE_INT:
		last_load_diagnostic = "save file has no usable credit balance, starting fresh"
		push_warning(last_load_diagnostic)
		return false
	var credits_float: float = float(raw_credits)
	if credits_float < 0.0 or not is_equal_approx(credits_float, roundf(credits_float)):
		last_load_diagnostic = (
			"save file credit balance %s is not a whole nonnegative number, starting fresh"
			% str(raw_credits)
		)
		push_warning(last_load_diagnostic)
		return false

	var raw_upgrade: Variant = data.get("tank_upgrade_owned", null)
	if typeof(raw_upgrade) != TYPE_BOOL:
		last_load_diagnostic = "save file has no usable upgrade flag, starting fresh"
		push_warning(last_load_diagnostic)
		return false

	credits = int(credits_float)
	tank_upgrade_owned = raw_upgrade

	# The map. A version 1 file has no such field and is not wrong for that, so
	# it migrates silently to the default. A version 2 file naming a map this
	# build does not ship falls back to the default and SAYS SO, but keeps the
	# credits: a map that has been renamed is not a reason to take a player's
	# money, and the older all-or-nothing rule would have done exactly that.
	map_id = MapCatalogue.DEFAULT_ID
	if file_version < 2:
		last_load_diagnostic = (
			"save file is schema version %d, migrated to %d with the %s map"
			% [file_version, SCHEMA_VERSION, MapCatalogue.title_for(MapCatalogue.DEFAULT_ID)]
		)
		return true

	var raw_map: Variant = data.get("map_id", null)
	if typeof(raw_map) != TYPE_STRING or not MapCatalogue.is_known(String(raw_map)):
		last_load_diagnostic = (
			"save file names no map this build ships (%s), falling back to %s"
			% [str(raw_map), MapCatalogue.title_for(MapCatalogue.DEFAULT_ID)]
		)
		push_warning(last_load_diagnostic)
		return true

	map_id = String(raw_map)
	return true


## Writes to a temporary file and renames it over the real one. Returns false
## and leaves any existing save untouched if the write could not be completed.
func save_game() -> bool:
	var data: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"credits": maxi(credits, 0),
		"tank_upgrade_owned": tank_upgrade_owned,
		"map_id": map_id if MapCatalogue.is_known(map_id) else MapCatalogue.DEFAULT_ID,
	}

	var file: FileAccess = FileAccess.open(_temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("could not open the temporary save file (error %d)" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var directory: DirAccess = DirAccess.open(_save_path.get_base_dir())
	if directory == null:
		push_warning("could not open the save directory")
		return false
	var error: int = directory.rename(_temp_path.get_file(), _save_path.get_file())
	if error != OK:
		push_warning("could not replace the save file (error %d)" % error)
		return false
	return true


## Adds credits and persists immediately, per handoff section 3: a call's
## credits are banked as it is completed, including when the shift later fails.
func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	credits += amount
	save_game()


## Remembers the map the player chose, so the next launch opens on it. Refuses
## a map this build does not ship rather than writing an id nothing can load.
func set_map(new_map_id: String) -> bool:
	if not MapCatalogue.is_known(new_map_id):
		push_warning("refusing to save an unknown map id: %s" % new_map_id)
		return false
	if map_id == new_map_id:
		return true
	map_id = new_map_id
	return save_game()


## Returns true only if the purchase actually happened. Refuses a repeat
## purchase and refuses to spend below zero (handoff section 9).
func purchase_tank_upgrade(cost: int) -> bool:
	if tank_upgrade_owned:
		return false
	if credits < cost:
		return false
	credits -= cost
	tank_upgrade_owned = true
	save_game()
	return true
