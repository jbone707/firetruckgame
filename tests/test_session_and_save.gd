extends "res://tests/test_case.gd"
## Rewards, the shop and persistence (handoff sections 3 and 9).

const GameSessionScript: GDScript = preload("res://scripts/GameSession.gd")
const DispatchManagerScript: GDScript = preload("res://scripts/DispatchManager.gd")
const TruckControllerScript: GDScript = preload("res://scripts/TruckController.gd")
const WaterSystemScript: GDScript = preload("res://scripts/WaterSystem.gd")
const FireIncidentScript: GDScript = preload("res://scripts/FireIncident.gd")
const SaveManagerScript: GDScript = preload("res://scripts/SaveManager.gd")
const GameBalanceScript: GDScript = preload("res://scripts/GameBalance.gd")

const TEST_SAVE_PATH: String = "user://test_fire_truck_save.json"
const TEST_TEMP_PATH: String = "user://test_fire_truck_save.json.tmp"

## A square building for every candidate, so incidents can be built without a
## map. A plain function rather than a const: a PackedVector2Array built from an
## array literal is not a constant expression in GDScript, and writing it as one
## is a parse error rather than a slow-burn bug.
static func building_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(80.0, 0.0), Vector2(80.0, 80.0), Vector2(0.0, 80.0)
	])


## Stands in for Main: hands out incidents and clears them, and knows where the
## station is. Everything GameSession and DispatchManager ask of the world.
class FakeSpawner extends Node:
	var incidents: Array = []
	var clear_calls: int = 0

	## Shared with the rest of the harness. Without this every incident would
	## call resolve_balance(), find no autoload outside a running scene, and
	## build a GameBalance of its own that nothing ever frees.
	var balance: Node = null

	func spawn_incident(candidate: Dictionary) -> FireIncident:
		var incident: FireIncident = load("res://scripts/FireIncident.gd").new()
		incident.balance = balance
		add_child(incident)
		incident.setup(
			String(candidate["id"]),
			String(candidate["building_id"]),
			load("res://tests/test_session_and_save.gd").building_polygon()
		)
		# Outside a running scene the _process callback never fires, so
		# escalation only advances when a test asks it to. That is deliberate.
		incidents.append(incident)
		return incident

	func clear_incidents() -> void:
		clear_calls += 1
		for incident in incidents:
			if is_instance_valid(incident):
				remove_child(incident)
				incident.free()
		incidents.clear()

	func get_station_spawn_position() -> Vector2:
		return Vector2.ZERO

	func get_station_spawn_heading() -> float:
		return 0.0


class Harness extends RefCounted:
	var spawner: FakeSpawner
	var dispatch: DispatchManager
	var truck: TruckController
	var water: WaterSystem
	var save: SaveManager
	var session: GameSession
	var balance: Node

	func destroy() -> void:
		spawner.clear_incidents()
		session.free()
		dispatch.free()
		water.free()
		truck.free()
		spawner.free()
		balance.free()


func _make_harness() -> Harness:
	var harness := Harness.new()
	harness.balance = GameBalanceScript.new()

	harness.spawner = FakeSpawner.new()
	harness.spawner.balance = harness.balance

	harness.dispatch = DispatchManagerScript.new()
	harness.dispatch.balance = harness.balance

	harness.truck = TruckControllerScript.new()
	harness.truck.balance = harness.balance
	harness.truck.max_condition = harness.balance.truck_starting_condition
	harness.truck.condition = harness.truck.max_condition

	harness.water = WaterSystemScript.new()
	harness.water.balance = harness.balance
	harness.water.tank_capacity = harness.balance.tank_capacity
	harness.water.water_remaining = harness.balance.tank_capacity

	harness.save = SaveManagerScript.new()
	harness.save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	harness.save.reset_to_defaults()

	harness.session = GameSessionScript.new()
	harness.session.balance = harness.balance

	var candidates: Array[Dictionary] = [
		{"id": "ic_1", "building_id": "b1", "position": Vector2(10.0, 10.0)},
		{"id": "ic_2", "building_id": "b2", "position": Vector2(20.0, 20.0)},
		{"id": "ic_3", "building_id": "b3", "position": Vector2(30.0, 30.0)},
	]
	harness.dispatch.setup(harness.spawner, candidates)
	harness.session.setup(
		harness.spawner, harness.dispatch, harness.truck, harness.water, harness.save
	)
	return harness


func _clear_save_files() -> void:
	for path in [TEST_SAVE_PATH, TEST_TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Puts out whatever call is active, without a stream: the reward path is what
## is being tested, not the water.
func _extinguish_active(harness: Harness) -> void:
	var incident: FireIncident = harness.dispatch.active_incident
	incident.apply_suppression(incident.max_health * 2.0)
	# The dispatch confirmation pause needs a nudge, since _process does not run.
	harness.dispatch._confirmation_remaining = 0.0
	harness.dispatch._dispatch_next()


func test_a_completed_call_pays_once_however_often_the_signal_arrives() -> void:
	var harness: Harness = _make_harness()
	harness.session.start_shift()

	var incident: FireIncident = harness.dispatch.active_incident
	assert_true(incident != null, "a call is dispatched at the start of a shift")

	var credits_before: int = harness.session.get_credits()
	incident.apply_suppression(incident.max_health * 2.0)
	assert_eq(
		harness.session.get_credits(),
		credits_before + harness.balance.credits_per_call,
		"putting a fire out pays once"
	)

	# Re-announce the same incident. FireIncident guards its own terminal
	# transition, so this reaches GameSession's guard directly.
	harness.session._on_call_extinguished(incident.incident_id)
	harness.session._on_call_extinguished(incident.incident_id)
	assert_eq(
		harness.session.get_credits(),
		credits_before + harness.balance.credits_per_call,
		"a repeated announcement for the same call pays nothing further"
	)
	assert_eq(harness.session.completed_calls, 1, "and does not advance the shift twice")

	harness.destroy()
	_clear_save_files()


func test_the_shift_bonus_is_paid_once_for_three_calls() -> void:
	var harness: Harness = _make_harness()
	harness.session.start_shift()

	for _call in range(harness.balance.calls_per_shift):
		_extinguish_active(harness)

	var expected: int = (
		harness.balance.credits_per_call * harness.balance.calls_per_shift
		+ harness.balance.shift_completion_bonus
	)
	assert_eq(harness.session.get_credits(), expected, "three calls plus one shift bonus")
	assert_eq(harness.session.state, GameSession.State.RESULTS, "the shift ends in results")
	assert_true(harness.session.last_shift_succeeded, "and is recorded as a success")

	# Nothing that arrives after the shift has ended can pay again.
	harness.session._end_shift(true, "again")
	harness.session._on_call_extinguished("ic_1")
	assert_eq(harness.session.get_credits(), expected, "no further payment after the shift ends")

	harness.destroy()
	_clear_save_files()


func test_credits_earned_survive_a_failed_shift() -> void:
	var harness: Harness = _make_harness()
	harness.session.start_shift()

	_extinguish_active(harness)
	var banked: int = harness.session.get_credits()
	assert_eq(banked, harness.balance.credits_per_call, "the first call is banked immediately")

	# Now lose the shift outright.
	harness.truck.condition = 0.0
	harness.session._on_truck_destroyed()

	assert_false(harness.session.last_shift_succeeded, "the shift is recorded as a failure")
	assert_eq(harness.session.get_credits(), banked, "a failed shift does not take credits back")
	assert_eq(
		harness.session.get_credits(),
		harness.balance.credits_per_call,
		"and no completion bonus was paid for a failed shift"
	)

	harness.destroy()
	_clear_save_files()


func test_credits_survive_a_reload_from_disk() -> void:
	_clear_save_files()
	var harness: Harness = _make_harness()
	harness.session.start_shift()
	_extinguish_active(harness)
	var banked: int = harness.session.get_credits()
	assert_true(banked > 0, "there is something to persist")

	# A brand new SaveManager reading the same file, as a fresh launch would.
	var reloaded: SaveManager = SaveManagerScript.new()
	reloaded.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	var loaded_cleanly: bool = reloaded.load_game()

	assert_true(loaded_cleanly, "the save file loads cleanly: %s" % reloaded.last_load_diagnostic)
	assert_eq(reloaded.credits, banked, "credits come back from disk unchanged")

	harness.destroy()
	_clear_save_files()


func test_the_upgrade_cannot_be_bought_twice_or_without_the_credits() -> void:
	var harness: Harness = _make_harness()
	var cost: int = harness.balance.tank_upgrade_cost

	# Too poor.
	harness.save.credits = cost - 1
	var poor_result: String = harness.session.purchase_tank_upgrade()
	assert_false(harness.session.has_tank_upgrade(), "an underfunded purchase is refused")
	assert_eq(harness.save.credits, cost - 1, "and takes nothing")
	assert_true(poor_result.contains("Not enough"), "and says why: %s" % poor_result)

	# Now affordable.
	harness.save.credits = cost + 25
	harness.session.purchase_tank_upgrade()
	assert_true(harness.session.has_tank_upgrade(), "the upgrade is bought")
	assert_eq(harness.save.credits, 25, "and costs exactly its price")

	# And cannot be bought again.
	var repeat_result: String = harness.session.purchase_tank_upgrade()
	assert_eq(harness.save.credits, 25, "a repeat purchase takes nothing")
	assert_true(repeat_result.contains("already"), "and says so: %s" % repeat_result)

	harness.destroy()
	_clear_save_files()


func test_the_upgraded_tank_applies_on_the_next_shift() -> void:
	var harness: Harness = _make_harness()
	var base_capacity: float = harness.balance.tank_capacity

	harness.save.credits = harness.balance.tank_upgrade_cost
	harness.session.purchase_tank_upgrade()
	assert_almost_eq(
		harness.water.tank_capacity, base_capacity, 0.0001, "the tank is unchanged mid-shift"
	)

	harness.session.start_shift()
	assert_almost_eq(
		harness.water.tank_capacity,
		base_capacity * harness.balance.tank_upgrade_multiplier,
		0.0001,
		"and the bigger tank arrives with the next shift"
	)
	assert_almost_eq(
		harness.water.water_remaining,
		harness.water.tank_capacity,
		0.0001,
		"a new shift fills the upgraded tank"
	)
	harness.destroy()
	_clear_save_files()


func test_a_new_shift_clears_the_previous_one_completely() -> void:
	var harness: Harness = _make_harness()
	harness.session.start_shift()

	_extinguish_active(harness)
	harness.truck.condition = 12.0
	harness.water.water_remaining = 3.0
	harness.water.begin_hookup()
	harness.session._on_truck_destroyed()

	var clears_before: int = harness.spawner.clear_calls
	harness.session.start_shift()

	assert_eq(harness.spawner.clear_calls, clears_before + 1, "old incidents are cleared")
	assert_eq(harness.session.completed_calls, 0, "call progress resets")
	assert_eq(harness.session.credits_earned_this_shift, 0, "shift earnings reset")
	assert_almost_eq(
		harness.truck.condition,
		harness.balance.truck_starting_condition,
		0.0001,
		"condition is restored"
	)
	assert_almost_eq(
		harness.water.water_remaining, harness.water.tank_capacity, 0.0001, "the tank is refilled"
	)
	assert_eq(
		harness.water.refill_state,
		WaterSystem.RefillState.IDLE,
		"a hookup in progress does not survive into the new shift"
	)
	assert_eq(harness.dispatch.call_number, 1, "and the new shift is on its first call")

	harness.destroy()
	_clear_save_files()


func test_a_malformed_save_falls_back_to_defaults_with_a_diagnostic() -> void:
	_clear_save_files()

	var cases: Array[Dictionary] = [
		{"text": "this is not json at all", "why": "unparseable text"},
		{"text": '{"schema_version": 1, "credits": -50, "tank_upgrade_owned": false}',
			"why": "negative credits"},
		{"text": '{"schema_version": 1, "credits": 10.5, "tank_upgrade_owned": false}',
			"why": "a fractional credit balance"},
		{"text": '{"schema_version": 99, "credits": 10, "tank_upgrade_owned": false}',
			"why": "an unknown schema version"},
		{"text": '{"credits": 10, "tank_upgrade_owned": false}', "why": "no schema version"},
		{"text": '{"schema_version": 1, "credits": 10}', "why": "no upgrade flag"},
	]

	for case in cases:
		var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		file.store_string(String(case["text"]))
		file.close()

		var save: SaveManager = SaveManagerScript.new()
		save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
		var ok: bool = save.load_game()

		assert_false(ok, "%s is rejected" % case["why"])
		assert_eq(save.credits, 0, "%s falls back to zero credits" % case["why"])
		assert_false(save.tank_upgrade_owned, "%s falls back to no upgrade" % case["why"])
		assert_true(
			save.last_load_diagnostic.length() > 0, "%s leaves a diagnostic" % case["why"]
		)

	_clear_save_files()


func test_a_good_save_round_trips_and_never_writes_negative_credits() -> void:
	_clear_save_files()

	var save: SaveManager = SaveManagerScript.new()
	save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	save.credits = 275
	save.tank_upgrade_owned = true
	assert_true(save.save_game(), "the save is written")
	assert_false(
		FileAccess.file_exists(TEST_TEMP_PATH),
		"the temporary file is renamed away rather than left behind"
	)

	var reloaded: SaveManager = SaveManagerScript.new()
	reloaded.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	assert_true(reloaded.load_game(), "and reads back cleanly")
	assert_eq(reloaded.credits, 275, "credits round trip")
	assert_true(reloaded.tank_upgrade_owned, "the upgrade flag round trips")

	# A negative balance must never reach the file, whatever put it in memory.
	save.credits = -999
	save.save_game()
	var after: SaveManager = SaveManagerScript.new()
	after.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	assert_true(after.load_game(), "the file is still valid after a negative balance")
	assert_eq(after.credits, 0, "a negative balance is clamped to zero on write")

	_clear_save_files()


## The shop button the player actually sees, alongside the purchase rule above.
## Three states, each a word rather than a colour, and the button is disabled in
## two of them rather than hidden: a control that vanishes when you cannot
## afford it leaves the player wondering whether they missed something.
func test_the_shop_button_states_match_the_purchase_rule() -> void:
	var GameUIScript: GDScript = load("res://scripts/GameUI.gd")
	var cost: int = 200

	var affordable: Dictionary = GameUIScript.upgrade_button_state(false, cost, cost)
	assert_eq(affordable["text"], "Buy bigger tank", "exactly enough credits can buy")
	assert_false(affordable["disabled"], "and the button is live")

	var poor: Dictionary = GameUIScript.upgrade_button_state(false, cost - 1, cost)
	assert_eq(poor["text"], "Not enough credits", "one credit short says so in words")
	assert_true(poor["disabled"], "and the button is disabled, not hidden")

	var owned: Dictionary = GameUIScript.upgrade_button_state(true, cost * 5, cost)
	assert_eq(owned["text"], "Owned", "an owned upgrade says owned")
	assert_true(owned["disabled"], "and cannot be bought again")

	# Owned wins over affordability, so a rich owner is never told they are poor.
	var owned_and_poor: Dictionary = GameUIScript.upgrade_button_state(true, 0, cost)
	assert_eq(owned_and_poor["text"], "Owned", "owned beats broke")

	# And the states line up with what GameSession would actually do.
	var harness: Harness = _make_harness()
	harness.save.credits = harness.balance.tank_upgrade_cost - 1
	var refused: String = harness.session.purchase_tank_upgrade()
	assert_true(
		GameUIScript.upgrade_button_state(
			false, harness.save.credits, harness.balance.tank_upgrade_cost
		)["disabled"],
		"the button is disabled in exactly the case the session refuses: %s" % refused
	)
	harness.destroy()
	_clear_save_files()


## Money reads the same everywhere it is shown.
func test_credits_are_formatted_the_same_way_on_every_screen() -> void:
	var GameUIScript: GDScript = load("res://scripts/GameUI.gd")
	assert_eq(GameUIScript.format_credits(350), "350 credits", "the usual case")
	assert_eq(GameUIScript.format_credits(0), "0 credits", "nothing earned still reads in credits")
	assert_eq(GameUIScript.format_credits(1), "1 credit", "and one is singular")


## The map choice, across the schema bump that introduced it.
##
## A version 1 save is a complete, valid save that simply predates there being
## more than one map. Rejecting it, which is what this loader did to every
## version it did not recognise, would have taken the credits and the upgrade
## off every existing player in exchange for adding a field with an obvious
## default. So the migration is the check: the old save keeps everything it had
## and gains the default map.
func test_an_old_save_without_a_map_migrates_to_the_default_map() -> void:
	_clear_save_files()

	var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string('{"schema_version": 1, "credits": 275, "tank_upgrade_owned": true}')
	file.close()

	var save: SaveManager = SaveManagerScript.new()
	save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	var ok: bool = save.load_game()

	assert_true(ok, "a version 1 save loads rather than being thrown away")
	assert_eq(save.credits, 275, "and keeps its credits")
	assert_true(save.tank_upgrade_owned, "and keeps its upgrade")
	assert_eq(
		save.map_id, MapCatalogue.DEFAULT_ID,
		"and arrives on the default map (%s)" % save.map_id
	)
	assert_true(
		save.last_load_diagnostic.length() > 0,
		"and says it was migrated rather than doing it silently"
	)

	# Saving it again writes the new schema, so the migration happens once.
	save.save_game()
	var reloaded: SaveManager = SaveManagerScript.new()
	reloaded.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	assert_true(reloaded.load_game(), "the migrated save reloads")
	assert_eq(reloaded.credits, 275, "with the credits still there")
	assert_eq(reloaded.map_id, MapCatalogue.DEFAULT_ID, "and the map still set")
	assert_eq(
		reloaded.last_load_diagnostic, "",
		"and nothing left to migrate the second time"
	)

	_clear_save_files()


## A save naming a map this build does not ship falls back to the default and
## says so, WITHOUT taking the player's credits. A renamed or dropped map is a
## reason to put someone on another map, not a reason to empty their bank.
func test_a_save_naming_an_unknown_map_keeps_the_credits() -> void:
	_clear_save_files()

	var file: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	file.store_string(
		'{"schema_version": 2, "credits": 410, "tank_upgrade_owned": false,'
		+ ' "map_id": "a_map_that_was_removed"}'
	)
	file.close()

	var save: SaveManager = SaveManagerScript.new()
	save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)

	assert_true(save.load_game(), "the save still loads")
	assert_eq(save.credits, 410, "with the credits untouched")
	assert_eq(save.map_id, MapCatalogue.DEFAULT_ID, "on the default map")
	assert_true(save.last_load_diagnostic.length() > 0, "and a diagnostic saying why")

	_clear_save_files()


## Choosing a map writes it through to disk immediately, so the next launch
## opens on it, and an id nothing can load is refused rather than written.
func test_the_chosen_map_persists_and_an_unknown_one_is_refused() -> void:
	_clear_save_files()

	var save: SaveManager = SaveManagerScript.new()
	save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	save.load_game()
	assert_eq(save.map_id, MapCatalogue.DEFAULT_ID, "a fresh save starts on the default map")

	var windsor: String = "windsor_shadetree_v1"
	assert_true(MapCatalogue.is_known(windsor), "the Windsor map is one this build ships")
	assert_true(save.set_map(windsor), "choosing it succeeds")

	var reloaded: SaveManager = SaveManagerScript.new()
	reloaded.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	assert_true(reloaded.load_game(), "the save reloads")
	assert_eq(reloaded.map_id, windsor, "on the map that was chosen")

	assert_false(
		reloaded.set_map("not_a_map"), "an unknown map id is refused"
	)
	assert_eq(reloaded.map_id, windsor, "and does not disturb the map already chosen")

	_clear_save_files()


## Every map the menu offers has to be loadable and has to carry its own honest
## lines. A map that reached the menu without them would be the whole failure
## this project is trying not to have.
func test_every_offered_map_loads_and_carries_its_own_notes() -> void:
	var entries: Array[Dictionary] = MapCatalogue.entries()
	assert_true(entries.size() >= 2, "the menu offers more than one map")

	var seen_default: bool = false
	for entry in entries:
		var map_id: String = String(entry["id"])
		if map_id == MapCatalogue.DEFAULT_ID:
			seen_default = true

		var map: MapDefinition = load(String(entry["path"])) as MapDefinition
		assert_true(map != null, "%s loads as a MapDefinition" % map_id)
		if map == null:
			continue
		assert_eq(map.map_id, map_id, "%s is the map the catalogue says it is" % map_id)
		assert_true(
			String(entry["title"]).strip_edges() != "", "%s has a title on its button" % map_id
		)
		assert_true(
			(entry["notes"] as Array).size() >= 1, "%s says something honest about itself" % map_id
		)

		# A map carrying real-world data must name where it came from.
		if not map.source_metadata.is_empty():
			assert_true(
				String(map.source_metadata.get("attribution", "")).length() > 0,
				"%s carries an attribution line" % map_id
			)

	assert_true(seen_default, "the default map is one of the maps offered")
	assert_true(
		MapCatalogue.path_for("not_a_map") == MapCatalogue.path_for(MapCatalogue.DEFAULT_ID),
		"an unknown map id resolves to the default map's path"
	)


## The Windsor map's notes, verbatim. These two sentences are the reason the map
## may be shipped at all: the streets are real and the hydrants are invented,
## and a player is told both before they choose it. A rewording is a decision,
## not a tidy-up, so it has to break a check.
func test_the_windsor_map_says_what_is_real_and_what_is_not() -> void:
	var notes: Array = []
	for entry in MapCatalogue.entries():
		if String(entry["id"]) == "windsor_shadetree_v1":
			notes = entry["notes"]

	assert_true(
		notes.has("Streets from OpenStreetMap; buildings partly synthetic"),
		"the map select says the streets are real and the buildings are not entirely"
	)
	assert_true(
		notes.has("Hydrant locations are placeholders, not real"),
		"and that the hydrants are placeholders"
	)


## The Data and Credits screen actually displays what ATTRIBUTION.md says it
## displays: the credit line, the licence, and the copyright URL as text.
##
## Read from the same static function the panel is built from, so this is what a
## player sees and not a second copy of it.
func test_the_credits_screen_shows_the_credit_line_and_the_licence() -> void:
	var lines: Array[String] = GameUI.credit_lines()
	var joined: String = "\n".join(lines)

	assert_true(
		joined.contains("© OpenStreetMap contributors"),
		"the required credit line is on the screen"
	)
	assert_true(
		joined.contains("Open Data Commons Open Database License (ODbL)"),
		"the licence is named"
	)
	assert_true(
		joined.contains("https://www.openstreetmap.org/copyright"),
		"the copyright URL appears as text, since a link cannot be followed here"
	)
	assert_true(
		joined.contains("Not an accurate map of Windsor"),
		"and the screen says it is not an accurate map"
	)
	assert_true(
		joined.contains("Hydrant locations are placeholders, not real"),
		"and that the hydrants are placeholders"
	)
