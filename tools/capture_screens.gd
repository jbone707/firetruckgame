extends SceneTree
## Reusable screenshot pack generator for a design handoff.
##
## Builds the real game (Main.tscn), redirects the save file exactly the way
## tests/run_physics_tests.gd does, and drives every state through the public
## API each system already exposes: WaterSystem.consume_water/spray, Hydrant's
## own evaluate() by simulating the hydrant_hookup action, FireIncident.health
## and .escalation, GameSession's real state machine. Nothing here fakes a
## label; every PNG shows what the game actually draws when that system is put
## in that state.
##
## MUST be run WINDOWED, not --headless. `godot --help` documents that
## --headless forces the "dummy" display driver, and dummy's only rendering
## driver is also "dummy" (no real rasterisation), so a --headless run's
## get_viewport().get_texture() has nothing real to capture. Run instead:
##
##   godot --path . --script res://tools/capture_screens.gd
##
## Optionally restrict the run to specific shots while iterating on one:
##
##   godot --path . --script res://tools/capture_screens.gd -- --only=07_hud_time_running_out,12_hud_knocking_it_down
##
## The window this opens can stay in the background; nothing here reads real
## keyboard or mouse input (Input.action_press/release simulate the hydrant key
## for the hookup sequence), so it never needs focus. Regenerate the whole pack
## after any HUD, map, or fire visual change; PNGs are gitignored on purpose so
## this script is the thing that is reviewed, not 35 binaries.
##
## Look at every PNG before trusting the pack: a state driven directly (setting
## FireIncident.health, or teleporting the truck) can still land mid-transition
## if too few frames were given to settle, and that will only show by looking.

const OUTPUT_DIR: String = "res://docs/screenshots"
const WINDSOR_MAP: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE_MAP: String = "res://resources/neighbourhood.tres"

## A save path distinct from every other tool's own (tests/run_physics_tests.gd
## uses physics_runner_save.json, tests/test_session_and_save.gd uses
## test_fire_truck_save.json), so a capture run can never collide with either
## if one is left mid-run. Never James's real save: user://fire_truck_game_save.json.
const TEST_SAVE_PATH: String = "user://screenshot_capture_save.json"
const TEST_TEMP_PATH: String = "user://screenshot_capture_save.json.tmp"

const DEFAULT_SIZE: Vector2i = Vector2i(1280, 720)
const NARROW_SIZE: Vector2i = Vector2i(960, 540)

## Close-up zoom for the world shots in group 4 (Camera2D zoom below 1.0 shows
## MORE world; above 1.0 shows less, i.e. is closer in).
const CLOSEUP_ZOOM: float = 2.2

var main: Node
var truck: TruckController
var water: WaterSystem
var ui: GameUI
var dispatch: DispatchManager
var session: GameSession
var camera: FollowCamera

var _only: PackedStringArray = []
var _written: Array[String] = []
var _skipped: Array[Dictionary] = []


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length()).split(",", false)
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame

	# Same redirect tests/run_physics_tests.gd uses. Main's _ready() has, by
	# this point, only READ the real save (SaveManager.load_game() never
	# writes) before this line replaces it; every write from here on lands on
	# this tool's own file.
	main.set_physics_process(false)
	main._save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	main._save.reset_to_defaults()

	truck = main.get_node("Truck")
	water = main._water
	ui = main._ui
	dispatch = main._dispatch
	session = main._session
	camera = main._camera
	# Instant framing beats eased framing for a screenshot: no motion to wait
	# out, and every shot is reproducible regardless of how many frames ran
	# before it.
	camera.position_smoothing_enabled = false

	main.load_map(WINDSOR_MAP)
	await physics_frame

	await _group_menus()
	await _group_hud_states()
	await _group_results_and_shop()
	await _group_world_closeups()
	await _group_zoom_comparison()
	await _group_overviews()
	await _group_narrow()

	print("\nWrote %d screenshot(s) to %s:" % [_written.size(), OUTPUT_DIR])
	for shot_name in _written:
		print("  %s.png" % shot_name)
	if not _skipped.is_empty():
		print("\nSkipped:")
		for entry in _skipped:
			print("  %s: %s" % [entry["name"], entry["reason"]])
	quit(0)


# ---------------------------------------------------------------------------
# Capture
# ---------------------------------------------------------------------------

func _wanted(shot_name: String) -> bool:
	return _only.is_empty() or _only.has(shot_name)


## Waits a few frames for whatever was just set to actually draw (queue_redraw
## is deferred to the next draw pass, and a signal-driven UI update needs a
## frame to reach the control), then grabs exactly what is on screen.
func _shot(shot_name: String) -> void:
	if not _wanted(shot_name):
		return
	for i in range(6):
		await physics_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUTPUT_DIR, shot_name]
	var error: int = image.save_png(path)
	if error == OK:
		_written.append(shot_name)
		print("wrote %s" % path)
	else:
		push_error("could not save %s (error %d)" % [path, error])


func _skip(shot_name: String, reason: String) -> void:
	if not _wanted(shot_name):
		return
	_skipped.append({"name": shot_name, "reason": reason})
	push_warning("skipping %s: %s" % [shot_name, reason])


# ---------------------------------------------------------------------------
# World helpers
# ---------------------------------------------------------------------------

## The midpoint of the first road segment carrying this street name, and the
## heading along it there. Falls back to the map's own centre and heading 0.0
## if the name is not found on the map currently loaded, so a renamed or
## removed street degrades a shot's framing rather than crashing the run.
func _road_point(road_name: String) -> Vector2:
	var definition: MapDefinition = main.get_map_definition()
	for road in definition.roads:
		if String(road.get("name", "")) == road_name:
			var points: PackedVector2Array = road["points"]
			return points[points.size() / 2]
	push_warning("no road named %s on %s, using the map centre" % [road_name, definition.map_id])
	return definition.world_bounds.get_center()


func _road_heading(road_name: String) -> float:
	var definition: MapDefinition = main.get_map_definition()
	for road in definition.roads:
		if String(road.get("name", "")) == road_name:
			var points: PackedVector2Array = road["points"]
			var mid: int = points.size() / 2
			var a: Vector2 = points[maxi(mid - 1, 0)]
			var b: Vector2 = points[mini(mid, points.size() - 1)]
			if a.is_equal_approx(b):
				return 0.0
			return a.direction_to(b).angle()
	return 0.0


## The hydrant nearest a world point, or null if the current map built none.
func _nearest_hydrant(to_position: Vector2) -> Hydrant:
	var nearest: Hydrant = null
	var nearest_distance: float = INF
	for hydrant in main._hydrants:
		var distance: float = hydrant.global_position.distance_to(to_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = hydrant
	return nearest


## The original incident_candidates entry an incident was spawned from, which
## carries the point on the street MapBuilder considers "in front of" the
## building (the same point travel_distance_to routes calls against). Empty if
## not found. incident.global_position is a different point on purpose: the
## burning building's own centroid, which can sit well inside the lot, behind
## the fence, or past the building's own wall relative to the street.
func _candidate_for(incident: FireIncident) -> Dictionary:
	for candidate in main._map_builder.get_incident_candidates():
		if String(candidate.get("id", "")) == incident.incident_id:
			return candidate
	return {}


## Every hydrant's ring and hose are drawn from whatever evaluate() last told
## them, which only runs from _refresh_hud(); nothing here ever calls that
## with the truck back out of range, so a hydrant used earlier keeps drawing
## itself as active and hooked up in every later shot that happens to frame
## its position. Called once at the end of every hydrant sequence.
func _reset_all_hydrants() -> void:
	for hydrant in main._hydrants:
		hydrant._set_active(false)
		hydrant._set_hose(false, Vector2.ZERO)


## MapBuilder's own street_label_placements(), which is a pure function of the
## road list, so this is exactly where each label was actually drawn rather
## than a guess at it. Returns {} if the street carries no label at all (too
## short, or not found).
func _label_placement(street_name: String) -> Dictionary:
	var definition: MapDefinition = main.get_map_definition()
	for placement in MapBuilder.street_label_placements(definition.roads):
		if String(placement["text"]) == street_name:
			return placement
	return {}


## A point where two roads actually branch, as a real junction reads:
## somewhere a driver would choose a direction. Two shapes of road data both
## have to work here. Windsor's OSM import splits a street into a separate
## entry at every junction, so those meet only at shared endpoints, and a
## shared endpoint where the road merely changes name (Shadetree Drive into
## Shadetree Lane) is excluded by requiring a real turn angle. Elm Grove's
## streets are each one entry running the whole grid, so two of them meet by
## CROSSING mid-segment rather than sharing an endpoint; segment intersection
## catches that shape instead.
##
## Returns {"point": Vector2, "heading": float}, or {} if the map has neither.
## "heading" is the tangent of one of the two roads AT the junction: framing
## the camera approaching along it, rather than at a fixed compass heading,
## is what actually brings the crossing road into the same shot. The first
## Windsor pass without this returned a real 77-degree junction (White Ash
## Court into Shadetree Drive) that then framed as a plain straight road,
## because a fixed heading has no reason to face either street actually
## meeting there.
func _find_junction() -> Dictionary:
	var definition: MapDefinition = main.get_map_definition()
	var roads: Array[Dictionary] = definition.roads
	const EPSILON: float = 4.0
	const MIN_BRANCH_ANGLE_DEGREES: float = 25.0

	for i in range(roads.size()):
		var a_points: PackedVector2Array = roads[i]["points"]
		for j in range(i + 1, roads.size()):
			var b_points: PackedVector2Array = roads[j]["points"]

			# Shared endpoint, OSM-style, with a real turn rather than a name
			# change straight through.
			for a_is_start in [true, false]:
				var a_end: Vector2 = a_points[0] if a_is_start else a_points[a_points.size() - 1]
				var a_other: Vector2 = a_points[1] if a_is_start else a_points[a_points.size() - 2]
				for b_is_start in [true, false]:
					var b_end: Vector2 = b_points[0] if b_is_start else b_points[b_points.size() - 1]
					var b_other: Vector2 = b_points[1] if b_is_start else b_points[b_points.size() - 2]
					if a_end.distance_to(b_end) > EPSILON:
						continue
					var a_dir: Vector2 = a_other.direction_to(a_end)
					var b_dir: Vector2 = b_end.direction_to(b_other)
					var turn_degrees: float = rad_to_deg(absf(a_dir.angle_to(b_dir)))
					if turn_degrees >= MIN_BRANCH_ANGLE_DEGREES:
						return {"point": a_end, "heading": a_dir.angle()}

			# Mid-segment crossing, grid-style.
			for a_index in range(a_points.size() - 1):
				for b_index in range(b_points.size() - 1):
					var crossing: Variant = Geometry2D.segment_intersects_segment(
						a_points[a_index], a_points[a_index + 1],
						b_points[b_index], b_points[b_index + 1]
					)
					if crossing != null:
						var tangent: Vector2 = a_points[a_index].direction_to(a_points[a_index + 1])
						return {"point": crossing, "heading": tangent.angle()}
	return {}


## Where MapBuilder actually drew a dead-end terminus, read from the built
## scene rather than re-derived from the raw road list. The first attempt at
## this scanned MapDefinition.roads for an endpoint merely close to the world
## bounds, which finds plenty of points that are close to the edge without
## being an actual single-degree dead end in MapBuilder's own welded
## RoadGraph (Windsor's fringe is documented as "ragged": short stubs from
## ways that only partly crossed the download box), so on the first run it
## framed empty asphalt with no barricade anywhere in the shot.
##
## _build_dead_end_sign's own diamond is unambiguous instead: its polygon is
## [at+up*half, at+right*half, at-up*half, at-right*half] with up = -outward,
## so points 0 and 2 are the sign's own "top" and "bottom" and hand back
## everything this needs without reproducing any of MapBuilder's placement
## arithmetic. Returns {} if the current map built no terminus at all.
func _find_edge_terminus() -> Dictionary:
	var markers: Node2D = main._map_builder.get_node_or_null("Markers")
	if markers == null:
		return {}
	for child in markers.get_children():
		if not (child is Polygon2D) or not String(child.name).begins_with("DeadEndSign_"):
			continue
		var polygon: PackedVector2Array = (child as Polygon2D).polygon
		if polygon.size() < 3:
			continue
		var sign_center: Vector2 = (polygon[0] + polygon[2]) / 2.0
		var outward: Vector2 = polygon[2].direction_to(polygon[0]) * -1.0
		if outward == Vector2.ZERO:
			continue
		var barricade_point: Vector2 = sign_center - outward * MapBuilder.SIGN_STANDOFF
		return {"point": barricade_point, "sign_center": sign_center, "outward": outward}
	return {}


## 28 and 36 both come off the same terminus: 28 is the establishing shot, the
## truck approaching the barricade from inside the map; 36 is a closer look at
## the sign itself, at MapBuilder's own SIGN_STANDOFF past the barricade, on
## the same outward heading a driver reading it would face.
##
## 36 frames the camera on the sign directly rather than on the truck: the
## truck sits ON the barricade for 28's establishing shot, which puts it
## almost on top of the sign 72 units further along the same line, and no
## truck position back on the road leaves enough clearance at a close zoom
## without also pushing the sign out of frame.
func _terminus_shots(terminus: Dictionary) -> void:
	var point: Vector2 = terminus["point"]
	var outward: Vector2 = terminus["outward"]
	var sign_center: Vector2 = terminus["sign_center"]
	var heading: float = outward.angle()

	await _place_truck(point - outward * 220.0, heading)
	await _shot("28_map_edge_barricade")

	# The sign itself stands in the verge, past the world bounds FollowCamera's
	# own limit_* is clamped to (apply_world_bounds only ever sees the
	# playable extent), so centering on it at this zoom needs the limit off
	# for this one shot or the engine clamps the view back toward the road
	# and the sign sits at the frame's edge instead of in the middle of it.
	camera.target = null
	camera.limit_enabled = false
	camera.set_zoom_level(CLOSEUP_ZOOM * 1.3)
	camera.global_position = sign_center
	for i in range(3):
		await physics_frame
	await _shot("36_dead_end_sign")
	camera.target = truck
	camera.limit_enabled = true
	camera.set_zoom_level(CLOSEUP_ZOOM)


## Teleports the truck (a sanctioned pattern here: TruckController.return_to_station
## and every physics test do exactly this) and lets the camera, which follows it
## every physics frame, catch up.
func _place_truck(position: Vector2, heading: float) -> void:
	truck.global_position = position
	truck.rotation = heading
	truck.velocity = Vector2.ZERO
	truck.set_drive_intent(0.0, 0.0, false)
	water.set_aim_world_position(position + Vector2.RIGHT.rotated(heading) * 60.0)
	water.set_spray_requested(false)
	water.cancel_refill()
	camera.target = truck
	for i in range(3):
		await physics_frame


func _refresh_hud() -> void:
	main._update_hydrants()
	main._update_hud()


# ---------------------------------------------------------------------------
# Group 1: menus
# ---------------------------------------------------------------------------

func _group_menus() -> void:
	ui.show_menu()
	await _shot("01_home_menu")

	session.open_map_select()
	await _shot("02_choose_map")

	session.open_credits()
	await _shot("03_data_and_credits")

	session.return_to_menu()

	session.start_shift()
	await _place_truck(_road_point("Shadetree Drive"), _road_heading("Shadetree Drive"))
	await _refresh_hud()
	main._set_paused(true)
	await _shot("04_pause_menu")
	main._set_paused(false)


# ---------------------------------------------------------------------------
# Group 2: HUD states, truck on Shadetree Drive
# ---------------------------------------------------------------------------

func _group_hud_states() -> void:
	var shadetree: Vector2 = _road_point("Shadetree Drive")
	var heading: float = _road_heading("Shadetree Drive")
	await _place_truck(shadetree, heading)
	await _refresh_hud()
	await _shot("05_hud_normal")

	# 06: drain the tank, then ask for the prompt with the truck away from
	# every hydrant, which is the real path to "Out of water. Find a
	# hydrant and hold E to refill".
	water.consume_water(water.tank_capacity)
	await _refresh_hud()
	await _shot("06_hud_water_empty")

	var hydrant: Hydrant = _nearest_hydrant(shadetree)
	if hydrant == null:
		_skip("08_hud_hydrant_too_fast", "Windsor built no hydrants")
		_skip("09_hud_hooking_up", "Windsor built no hydrants")
		_skip("10_hud_refilling", "Windsor built no hydrants")
		_skip("11_hud_tank_full", "Windsor built no hydrants")
	else:
		var forward: Vector2 = Vector2.RIGHT.rotated(heading)
		var radius: float = hydrant.get_interaction_radius()

		# 08: in range, but moving too fast to hook up.
		await _place_truck(hydrant.global_position + forward * (radius * 0.4), heading)
		truck.velocity = forward * 150.0
		Input.action_press("hydrant_hookup")
		await _refresh_hud()
		await _shot("08_hud_hydrant_too_fast")

		# Stationary and holding E from here on: the real hookup -> refill ->
		# full sequence, driven by WaterSystem's own _physics_process, which
		# runs every physics frame regardless of Main's being disabled.
		truck.velocity = Vector2.ZERO
		await _refresh_hud()
		await _shot("09_hud_hooking_up")

		# hydrant_hookup_time is 1.0s (60 physics frames); run comfortably past
		# it into REFILLING and capture partway through the fill.
		# hydrant_refill_rate is 50 units/s against a drained 100-unit tank, so
		# stopping at 90 frames (1.5s, ~0.5s of which is actual refilling)
		# leaves the tank clearly partial rather than freshly started or full.
		for i in range(90):
			await physics_frame
			await _refresh_hud()
		await _shot("10_hud_refilling")

		# Run the rest of the fill out. Hydrant.evaluate() reports TANK_FULL
		# and Main's own cancel-on-not-wanting-refill logic ends the hookup
		# without anything here telling it to.
		for i in range(200):
			await physics_frame
			await _refresh_hud()
			if water.water_remaining >= water.tank_capacity:
				break
		await _refresh_hud()
		await _shot("11_hud_tank_full")
		Input.action_release("hydrant_hookup")
		water.cancel_refill()
		await _place_truck(shadetree, heading)
		_reset_all_hydrants()

	# 12: knocking it down. Needs an active incident and the truck close
	# enough, with a clear line of sight, to land the stream on it.
	if dispatch.active_incident == null or not is_instance_valid(dispatch.active_incident):
		_skip("12_hud_knocking_it_down", "no active incident to spray")
		_skip("07_hud_time_running_out", "no active incident to escalate")
		_skip("13_hud_call_offscreen_arrow", "no active incident to point at")
	else:
		var incident: FireIncident = dispatch.active_incident
		water.fill_tank()
		# The candidate's own "position", not incident.global_position: the
		# incident sits at the burning building's centroid, which a straight
		# line back from it can easily land inside the building itself (see
		# DEVELOPMENT_STATUS.md's note that this has never been played). The
		# candidate position is the street-facing point Main already routes
		# calls against, so approaching from there keeps the truck on the
		# street with a clear line of sight to the fire's own grown edge.
		var candidate: Dictionary = _candidate_for(incident)
		var front_point: Vector2 = (
			Vector2(candidate["position"]) if not candidate.is_empty()
			else incident.global_position - Vector2.RIGHT.rotated(heading) * 100.0
		)
		var approach_heading: float = front_point.direction_to(incident.global_position).angle()
		await _place_truck(front_point, approach_heading)
		water.set_aim_world_position(incident.global_position)
		water.set_spray_requested(true)
		for i in range(10):
			await physics_frame
		await _refresh_hud()
		await _shot("12_hud_knocking_it_down")
		water.set_spray_requested(false)

		# 07: under URGENT_SECONDS of margin left, without waiting the real
		# clock out.
		incident.escalation = maxf(incident.escalation_limit - 20.0, 0.0)
		incident.queue_redraw()
		await _refresh_hud()
		await _shot("07_hud_time_running_out")

		# 13: the truck far enough from the active call that it is off screen,
		# so the direction arrow shows. Moved toward the map's own centre
		# rather than by a fixed offset, so this cannot land outside the
		# world bounds (and in the dark overscan band beyond them) on a map
		# where the incident already sits near an edge.
		var bounds_center: Vector2 = main.get_map_definition().world_bounds.get_center()
		var toward_center: Vector2 = incident.global_position.direction_to(bounds_center)
		if toward_center == Vector2.ZERO:
			toward_center = Vector2.RIGHT
		var far_point: Vector2 = incident.global_position + toward_center * 2000.0
		await _place_truck(far_point, 0.0)
		await _refresh_hud()
		await _shot("13_hud_call_offscreen_arrow")
		await _place_truck(shadetree, heading)


# ---------------------------------------------------------------------------
# Group 3: results and shop
# ---------------------------------------------------------------------------

func _group_results_and_shop() -> void:
	session.start_shift()
	await physics_frame

	# A won shift: extinguish all three calls outright rather than spraying
	# them out, and skip DispatchManager's confirmation pause by calling its
	# own dispatch step directly instead of waiting the real 2 seconds out.
	for call_index in range(3):
		if dispatch.active_incident == null or not is_instance_valid(dispatch.active_incident):
			break
		var incident: FireIncident = dispatch.active_incident
		incident.apply_suppression(incident.max_health)
		await physics_frame
		if session.state != GameSession.State.RESULTS and call_index < 2:
			dispatch._dispatch_next()
			await physics_frame

	if session.state == GameSession.State.RESULTS and session.last_shift_succeeded:
		await _shot("14_results_won")
	else:
		_skip("14_results_won", "shift did not resolve as a win")

	session.open_shop()
	await _shot("16_shop_buy")

	var real_credits: int = session.get_credits()
	session.save_manager.credits = 0
	main._refresh_shop()
	await _shot("18_shop_not_enough_credits")

	session.save_manager.credits = real_credits
	main._refresh_shop()
	var purchase_result: String = session.purchase_tank_upgrade()
	main._shop_status = purchase_result
	main._refresh_shop()
	await _shot("17_shop_owned")

	session.close_shop()

	# A lost shift: force the active incident's terminal loss transition
	# directly rather than waiting fire_escalation_duration seconds out.
	session.start_shift()
	await physics_frame
	if dispatch.active_incident != null and is_instance_valid(dispatch.active_incident):
		var incident: FireIncident = dispatch.active_incident
		incident.escalation = incident.escalation_limit
		incident._finish(false)
		await physics_frame

	if session.state == GameSession.State.RESULTS and not session.last_shift_succeeded:
		await _shot("15_results_lost")
	else:
		_skip("15_results_lost", "shift did not resolve as a loss")


# ---------------------------------------------------------------------------
# Group 4: world close-ups, no HUD
# ---------------------------------------------------------------------------

func _group_world_closeups() -> void:
	session.start_shift()
	await physics_frame
	ui._hud.visible = false
	camera.set_zoom_level(CLOSEUP_ZOOM)

	var shadetree: Vector2 = _road_point("Shadetree Drive")
	var heading: float = _road_heading("Shadetree Drive")
	await _place_truck(shadetree, heading)

	main._set_siren(false)
	await _shot("19_engine_lights_off")
	main._set_siren(true)
	await _shot("20_engine_lights_on")
	main._set_siren(false)

	var hydrant: Hydrant = _nearest_hydrant(shadetree)
	if hydrant == null:
		_skip("21_hydrant_out_of_range", "Windsor built no hydrants")
		_skip("22_hydrant_in_range_hose", "Windsor built no hydrants")
	else:
		var forward: Vector2 = Vector2.RIGHT.rotated(heading)
		var radius: float = hydrant.get_interaction_radius()

		await _place_truck(hydrant.global_position + forward * (radius + 70.0), heading)
		Input.action_release("hydrant_hookup")
		await _refresh_hud()
		await _shot("21_hydrant_out_of_range")

		await _place_truck(hydrant.global_position + forward * (radius * 0.4), heading)
		Input.action_press("hydrant_hookup")
		for i in range(3):
			await physics_frame
			await _refresh_hud()
		await _shot("22_hydrant_in_range_hose")
		Input.action_release("hydrant_hookup")
		water.cancel_refill()
		await _place_truck(shadetree, heading)
		_reset_all_hydrants()

	if dispatch.active_incident == null or not is_instance_valid(dispatch.active_incident):
		_skip("23_fire_full", "no active incident")
		_skip("24_fire_half", "no active incident")
		_skip("25_fire_nearly_out", "no active incident")
	else:
		var incident: FireIncident = dispatch.active_incident
		# Framed on the incident directly rather than on the truck: the truck
		# would otherwise need a clearance from the building's footprint that
		# is not known generically, and these three shots are about the fire,
		# not the truck.
		camera.target = null
		camera.set_zoom_level(1.7)
		camera.global_position = incident.global_position
		for i in range(3):
			await physics_frame

		incident.health = incident.max_health
		incident.queue_redraw()
		await _shot("23_fire_full")

		incident.health = incident.max_health * 0.5
		incident.queue_redraw()
		await _shot("24_fire_half")

		incident.health = incident.max_health * 0.08
		incident.queue_redraw()
		await _shot("25_fire_nearly_out")

		incident.health = incident.max_health
		incident.queue_redraw()
		camera.target = truck
		camera.set_zoom_level(CLOSEUP_ZOOM)

	var windsor_junction: Dictionary = _find_junction()
	if windsor_junction.is_empty():
		_skip("26_junction_windsor", "no two roads meet on this map")
	else:
		var junction_heading: float = windsor_junction["heading"]
		var junction_point: Vector2 = windsor_junction["point"]
		await _place_truck(junction_point - Vector2.RIGHT.rotated(junction_heading) * 220.0, junction_heading)
		await _shot("26_junction_windsor")

	var windsor_edge: Dictionary = _find_edge_terminus()
	if windsor_edge.is_empty():
		main.load_map(ELM_GROVE_MAP)
		await physics_frame
		var elm_grove_edge: Dictionary = _find_edge_terminus()
		if elm_grove_edge.is_empty():
			_skip("28_map_edge_barricade", "no road on either shipped map ends near its own boundary")
			_skip("36_dead_end_sign", "no road on either shipped map ends near its own boundary")
		else:
			ui._hud.visible = false
			camera.set_zoom_level(CLOSEUP_ZOOM)
			await _terminus_shots(elm_grove_edge)
		main.load_map(WINDSOR_MAP)
		await physics_frame
		ui._hud.visible = false
		camera.set_zoom_level(CLOSEUP_ZOOM)
	else:
		await _terminus_shots(windsor_edge)

	# The exact spot MapBuilder actually drew "Shadetree Drive"'s label, from
	# its own placement function, rather than the road's raw midpoint: that
	# midpoint is only ever guaranteed to be ON the road, not on the
	# particular straight stretch long enough to carry the name (see
	# MapBuilder.street_label_placements), and it landed nowhere near the
	# label on this street on the first run of this tool.
	var label: Dictionary = _label_placement("Shadetree Drive")
	if label.is_empty():
		_skip("29_street_label", "Shadetree Drive carries no label (too short a straight run)")
	else:
		var label_position: Vector2 = Vector2(label["position"])
		await _place_truck(label_position - Vector2.RIGHT.rotated(float(label["rotation"])) * 90.0, float(label["rotation"]))
		camera.set_zoom_level(1.3)
		await _shot("29_street_label")

	# 27: the same junction shot, on Elm Grove.
	main.load_map(ELM_GROVE_MAP)
	await physics_frame
	ui._hud.visible = false
	camera.set_zoom_level(CLOSEUP_ZOOM)
	var elm_grove_junction: Dictionary = _find_junction()
	if elm_grove_junction.is_empty():
		_skip("27_junction_elm_grove", "no two roads meet on this map")
	else:
		var junction_heading: float = elm_grove_junction["heading"]
		var junction_point: Vector2 = elm_grove_junction["point"]
		await _place_truck(junction_point - Vector2.RIGHT.rotated(junction_heading) * 220.0, junction_heading)
		await _shot("27_junction_elm_grove")

	main.load_map(WINDSOR_MAP)
	await physics_frame
	ui._hud.visible = true


# ---------------------------------------------------------------------------
# Group 5: zoom comparison, the same Windsor spot
# ---------------------------------------------------------------------------

func _group_zoom_comparison() -> void:
	session.start_shift()
	await physics_frame
	ui._hud.visible = true
	var shadetree: Vector2 = _road_point("Shadetree Drive")
	var heading: float = _road_heading("Shadetree Drive")
	await _place_truck(shadetree, heading)
	# Otherwise the margin and prompt still read whatever the previous
	# group's hydrant or fire sequence last left them at: neither is driven
	# by a signal, both only update from Main._update_hud()/_update_hydrants(),
	# which nothing has called since.
	await _refresh_hud()

	var zoom_shots: Array[Dictionary] = [
		{"level": 0.9, "name": "30_zoom_0.9"},
		{"level": 0.7, "name": "31_zoom_0.7"},
		{"level": 0.55, "name": "32_zoom_0.55"},
	]
	for entry in zoom_shots:
		camera.set_zoom_level(entry["level"])
		await physics_frame
		await _shot(entry["name"])
	camera.set_zoom_level(0.9)


# ---------------------------------------------------------------------------
# Group 6: whole-map overviews
# ---------------------------------------------------------------------------

func _group_overviews() -> void:
	# No HUD: an overview is about the map, and load_map() resets the
	# dispatch without telling the HUD, so the call/margin/prompt readouts
	# left showing would be stale rather than merely absent.
	ui._hud.visible = false
	await _overview("34_overview_windsor", WINDSOR_MAP)
	await _overview("33_overview_elm_grove", ELM_GROVE_MAP)
	main.load_map(WINDSOR_MAP)
	await physics_frame
	ui._hud.visible = true
	camera.target = truck
	camera.set_zoom_level(0.9)


func _overview(shot_name: String, map_path: String) -> void:
	main.load_map(map_path)
	await physics_frame
	var bounds: Rect2 = main.get_map_definition().world_bounds
	var viewport_size: Vector2 = Vector2(root.size)
	var fit_zoom: float = minf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y) * 0.92
	camera.target = null
	camera.set_zoom_level(fit_zoom)
	camera.global_position = bounds.get_center()
	for i in range(3):
		await physics_frame
	await _shot(shot_name)


# ---------------------------------------------------------------------------
# Group 7: narrow landscape
# ---------------------------------------------------------------------------

func _group_narrow() -> void:
	session.start_shift()
	await physics_frame
	ui._hud.visible = true
	camera.target = truck
	camera.set_zoom_level(0.9)
	await _place_truck(_road_point("Shadetree Drive"), _road_heading("Shadetree Drive"))
	await _refresh_hud()

	DisplayServer.window_set_size(NARROW_SIZE)
	for i in range(6):
		await physics_frame
	await _shot("35_hud_narrow_960x540")

	DisplayServer.window_set_size(DEFAULT_SIZE)
