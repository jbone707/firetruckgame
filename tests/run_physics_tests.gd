extends SceneTree
## Integration checks that actually step Godot's physics.
##
## Run with:
##   godot --headless --path . --script res://tests/run_physics_tests.gd
##
## This exists because tests/run_tests.gd cannot. That runner calls methods
## synchronously and never advances a frame, so it can verify the damage RULE
## but not whether move_and_slide reports contacts the way the controller
## assumes. The gap was not theoretical: the first version of TruckController
## trusted move_and_slide to write a blocked result back into velocity, it did
## not, and holding the throttle against a wall re-fired a full speed crash
## every time the contact cooldown expired. Every unit test passed throughout.
##
## Exits 0 only when every check passes, like the other runner.

## The clear space the HUD rows must keep between them, world pixels. A
## LITERAL, deliberately not GameUI.HUD_ROW_SEPARATION: a check that reads the
## constant it is policing passes by construction whatever that constant
## becomes, which is exactly what the first version of this did.
const HUD_MIN_ROW_GAP: float = 6.0

const PHYSICS_FPS: int = 60

## The imported map. Several checks run twice, once on each map, because the
## fictional one cannot answer anything about angled roads and the imported one
## is the reason the geometry was rewritten.
const WINDSOR_MAP: String = "res://resources/windsor_shadetree.tres"

## The fictional map, named here rather than left to the default, because the
## default is whichever map the PLAYER last chose (Milestone 6 Part 1). Main
## reads the real save in _ready and builds that map before this runner gets a
## chance to redirect it, so a suite that said nothing about which map it
## wanted was quietly testing James's last game. On a save naming Windsor,
## eight of these checks failed on an unchanged tree, including the Elm Grove
## fence at 574, which is a number Windsor has no reason to produce.
const ELM_GROVE_MAP: String = "res://resources/neighbourhood.tres"

## The turn off Hembree Lane. The run-up is long enough to be at speed by the
## junction; the aiming point is as far down the side street as the side street
## goes, capped, because Windsor's segments are short and getting shorter as the
## land scale changes (Milestone 6 Part 2).
##
## Arriving is measured against the side street's OWN half width plus a truck
## length rather than a fixed distance: the question is whether the truck got
## onto the side street, and a truck a truck's length off the centreline of a
## street it is driving down has got onto it. A fixed number in world units
## would mean something different on each map and would have to be retuned
## every time the land scale moved.
const APPROACH_RUN_UP: float = 700.0
const SIDE_STREET_RUN: float = 900.0
const ARRIVAL_MARGIN: float = 90.0

## How close to the junction the throttle comes off, and how far off. See the
## drive loop for why.
const TURN_IN_DISTANCE: float = 420.0
const TURNING_THROTTLE: float = 0.45

## Where a world built by this runner writes its save, so the suite never
## touches the player's own.
const TEST_SAVE_PATH: String = "user://physics_runner_save.json"
const TEST_TEMP_PATH: String = "user://physics_runner_save.json.tmp"

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _check_truck_reaches_top_speed()
	await _check_wall_contact_damages_exactly_once()
	await _check_stream_hits_a_burning_building_from_outside()
	await _check_an_obstacle_blocks_the_stream()
	await _check_the_stream_stops_at_its_range()
	await _check_a_shift_starts_and_dispatches_in_the_real_scene()
	await _check_the_call_arrow_points_at_the_fire_from_any_heading()
	await _check_the_call_arrow_hides_once_the_fire_is_on_screen()
	await _check_an_empty_lot_stops_the_truck()
	await _check_a_windsor_road_is_fenced_at_both_sides()
	await _check_a_whole_shift_pays_out_on_the_windsor_map()
	await _check_a_windsor_shift_starts_whole()
	await _check_the_truck_turns_off_hembree_lane_into_a_side_street()
	await _check_the_menus_walk_the_way_a_player_walks_them()
	await _check_every_approach_to_a_hydrant_hooks_up()
	await _check_the_hose_hooks_up_by_itself_and_snaps_when_pulled()
	await _check_a_truck_rocking_on_the_boundary_hooks_up_only_once()
	await _check_the_narrowest_road_the_truck_can_turn_in()
	await _check_the_hud_rows_never_overlap()
	await _check_the_zoom_control_holds_its_level()
	await _check_the_minimap_clears_the_prompt_line_and_the_hud_column()
	await _check_the_minimap_toggle_holds_across_a_change_of_map()
	await _check_the_minimap_zoom_never_moves_the_camera_zoom()
	await _check_the_signals_run_pause_and_reset_with_the_shift()

	print("---")
	print("%d physics check(s): %d passed, %d failed" % [
		_checks, _checks - _failures.size(), _failures.size()
	])
	if _checks == 0:
		print("no physics checks ran")
		quit(1)
		return
	quit(1 if _failures.size() > 0 else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS %s" % message)
	else:
		_failures.append(message)
		print("FAIL %s" % message)


## Loads the real main scene and stops it driving itself.
##
## Main polls the keyboard every physics frame and would overwrite any intent
## injected here with zeros, since nothing is held down in a headless run. That
## is correct for the game and simply has to be switched off to drive the truck
## from a test.
##
## The save is redirected before anything else happens. Every check here drives
## the real GameSession, which banks credits to disk as they are earned, so
## without this the suite quietly paid the player 350 credits every time it ran
## and, once maps became choosable, would have changed which map their game
## opened on. A test that alters the thing it is testing around is not a test.
##
## Redirecting the save was only half of it. Main has already READ the player's
## save by the time the first physics frame lands, so the map it built is the
## one they last played. Every world is therefore told which map it wants.
func _make_world(map_path: String = ELM_GROVE_MAP) -> Array:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.set_physics_process(false)
	main._save.use_paths(TEST_SAVE_PATH, TEST_TEMP_PATH)
	main._save.reset_to_defaults()
	# Always stated, never inherited: see ELM_GROVE_MAP.
	main.load_map(map_path)
	await physics_frame
	return [main, main.get_node("Truck")]


## How far along a ray the truck leaves the asphalt, and how far along it the
## fence stands, both read off the geometry MapBuilder actually built rather
## than off any map's constants.
##
## Sampled rather than solved: the regions are arbitrary polygons at arbitrary
## angles, one step is a unit, and a unit is a fortieth of the truck's width.
func _crossings_along(
	regions: Array, from: Vector2, direction: Vector2, reach: float
) -> Array[float]:
	var found: Array[float] = []
	for region in regions:
		var crossing: float = INF
		var travelled: float = 0.0
		while travelled <= reach:
			var point: Vector2 = from + direction * travelled
			for piece in region:
				if Geometry2D.is_point_in_polygon(point, piece):
					crossing = travelled
					break
			if crossing < INF:
				break
			travelled += 1.0
		found.append(crossing)
	return found


## Four seconds of throttle from a standstill, reporting how far the nose got.
func _drive_at(truck: Node, from: Vector2, heading: float) -> float:
	truck.global_position = from
	truck.rotation = heading
	truck.velocity = Vector2.ZERO
	var direction: Vector2 = Vector2.RIGHT.rotated(heading)

	var deepest: float = -INF
	for _frame in range(4 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame
		deepest = maxf(deepest, (truck.global_position - from).dot(direction))
	return deepest + truck.get_collision_half_extents().x


func _check_truck_reaches_top_speed() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var start_position: Vector2 = truck.global_position

	for _frame in range(2 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame

	var speed: float = truck.get_forward_speed()
	var moved: float = truck.global_position.distance_to(start_position)
	_check(
		absf(speed - truck.balance.forward_max_speed) < 1.0,
		"two seconds of throttle reaches top speed (%.1f of %.1f units/s)" % [
			speed, truck.balance.forward_max_speed
		]
	)
	_check(moved > 300.0, "the truck actually moved (%.1f units)" % moved)

	main.queue_free()
	await physics_frame


func _check_wall_contact_damages_exactly_once() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	# Aim due north up Elm Avenue at the map's edge wall, then hold the throttle
	# into it for ten seconds, which is twenty contact cooldowns. The station
	# faces along this avenue and the avenue runs to the boundary, so the first
	# thing the truck meets really is the edge wall and not a kerb. Driving east
	# instead, as this check used to, now runs into the block opposite the
	# station within 95 units, which tests something else entirely.
	truck.rotation = -PI / 2.0
	truck.velocity = Vector2.ZERO
	truck.condition = truck.max_condition

	# A one element array: GDScript lambdas capture locals by value, so a
	# captured int would never be seen to increment out here.
	var damage_events: Array[int] = [0]
	truck.truck_damaged.connect(
		func(_amount: float, _speed: float) -> void: damage_events[0] += 1
	)

	for _frame in range(10 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame

	_check(
		damage_events[0] == 1,
		"holding the throttle into a wall for 10 seconds damages exactly once (got %d)"
			% damage_events[0]
	)
	_check(
		truck.condition > 0.0,
		"one wall crash does not destroy the engine outright (condition %.1f)" % truck.condition
	)
	_check(
		truck.condition < truck.max_condition,
		"the crash did cost condition (condition %.1f)" % truck.condition
	)

	main.queue_free()
	await physics_frame


## Sets up the first incident candidate as a live fire and returns
## [main, truck, water, incident, aim_point].
func _make_fire_world() -> Array:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = truck.get_node("WaterSystem")

	var candidates: Array[Dictionary] = main._map_builder.get_incident_candidates()
	var candidate: Dictionary = candidates[0]
	var incident: Node = main.spawn_incident(candidate)

	var polygon: PackedVector2Array = main._map_builder.get_building_polygon(
		String(candidate["building_id"])
	)
	var centre: Vector2 = Vector2.ZERO
	for point in polygon:
		centre += point
	centre /= float(polygon.size())

	# Park the truck clear of the building, on the street side of the candidate
	# marker. Sitting exactly on the marker puts the 90x40 body inside the
	# building wall, and the depenetration shove that follows is not a scenario
	# any of these checks are about.
	var street_side: Vector2 = (Vector2(candidate["position"]) - centre).normalized()
	truck.global_position = Vector2(candidate["position"]) + street_side * 60.0
	truck.velocity = Vector2.ZERO
	await physics_frame

	return [main, truck, water, incident, centre]


## The fire is inside a building whose walls are on the same layer that blocks
## the stream. FireIncident grows its area past those walls precisely so the
## fire is reachable from the street; if that margin were removed, the building
## would shield the fire burning inside it and the call could never be cleared.
func _check_stream_hits_a_burning_building_from_outside() -> void:
	var world: Array = await _make_fire_world()
	var main: Node = world[0]
	var water: Node = world[2]
	var incident: Node = world[3]
	var aim: Vector2 = world[4]

	var health_before: float = incident.health
	water.set_aim_world_position(aim)
	water.set_spray_requested(true)
	for _frame in range(PHYSICS_FPS):
		await physics_frame

	_check(
		incident.health < health_before,
		"a burning building is hittable from the street (health %.1f from %.1f)"
			% [incident.health, health_before]
	)
	main.queue_free()
	await physics_frame


func _check_an_obstacle_blocks_the_stream() -> void:
	var world: Array = await _make_fire_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = world[2]
	var incident: Node = world[3]
	var aim: Vector2 = world[4]

	# Drop a solid wall on the world_static layer squarely between the nozzle
	# and the fire. Building it here rather than hunting the map for a
	# convenient blocked sight line keeps the check deterministic.
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 0b0001
	blocker.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10.0, 400.0)
	shape.shape = rectangle
	blocker.add_child(shape)
	main.add_child(blocker)

	var nozzle: Vector2 = water.get_nozzle_global_position()
	blocker.global_position = nozzle.lerp(aim, 0.4)
	# The blocker's long axis is its local Y, which a rotation of theta points
	# along theta + 90 degrees. To lie ACROSS the stream rather than along it,
	# the rotation is the aim angle itself. Adding another 90 degrees, which is
	# the intuitive thing to write, leaves the wall parallel to the stream and
	# blocking nothing, and this check duly failed until it was watched.
	blocker.rotation = (aim - nozzle).angle()
	await physics_frame

	var health_before: float = incident.health
	water.set_aim_world_position(aim)
	water.set_spray_requested(true)
	var water_before: float = water.water_remaining
	for _frame in range(PHYSICS_FPS):
		await physics_frame

	_check(
		is_equal_approx(incident.health, health_before),
		"an obstacle between the nozzle and the fire blocks the stream (health %.1f)"
			% incident.health
	)
	_check(
		water.water_remaining < water_before,
		"and the water is still spent, because spraying at an obstacle costs the tank"
	)
	main.queue_free()
	await physics_frame


func _check_the_stream_stops_at_its_range() -> void:
	var world: Array = await _make_fire_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = world[2]
	var incident: Node = world[3]
	var aim: Vector2 = world[4]

	# Back the truck well beyond the stream's reach along the same line.
	var direction: Vector2 = (aim - truck.global_position).normalized()
	truck.global_position = aim - direction * (water.balance.stream_range * 3.0)
	truck.velocity = Vector2.ZERO
	await physics_frame

	var health_before: float = incident.health
	water.set_aim_world_position(aim)
	water.set_spray_requested(true)
	for _frame in range(PHYSICS_FPS):
		await physics_frame

	_check(
		is_equal_approx(incident.health, health_before),
		"a fire three times the stream range away takes no damage (health %.1f)" % incident.health
	)
	main.queue_free()
	await physics_frame


## Wiring, not rules. The session tests build their objects by hand, so they
## cannot tell whether Main actually found %Dispatch, %Session and %GameUI, nor
## whether pressing Start really begins a shift. This boots the real scene and
## drives it through the same entry point the button uses.
func _check_a_shift_starts_and_dispatches_in_the_real_scene() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var session: Node = main._session

	_check(session.state == GameSession.State.MENU, "the game opens on the menu")

	main._on_start_shift_pressed()
	await physics_frame

	_check(session.state == GameSession.State.PLAYING, "starting a shift enters PLAYING")
	_check(
		main._dispatch.active_incident != null,
		"and the first call is dispatched with a live incident"
	)
	_check(main._dispatch.call_number == 1, "on call 1")
	_check(
		main._dispatch.active_incident.get_escalation_remaining() > 0.0,
		"with escalation margin still on the clock"
	)

	# And the whole loop: put out every call and land in results with the bonus.
	var expected: int = (
		main._session.balance.credits_per_call * main._session.balance.calls_per_shift
		+ main._session.balance.shift_completion_bonus
	)
	for _call in range(main._session.balance.calls_per_shift):
		var incident: Node = main._dispatch.active_incident
		incident.apply_suppression(incident.max_health * 2.0)
		main._dispatch._confirmation_remaining = 0.0
		main._dispatch._dispatch_next()
		await physics_frame

	_check(
		session.state == GameSession.State.RESULTS,
		"clearing three calls ends the shift in results"
	)
	_check(
		session.credits_earned_this_shift == expected,
		"paying three calls and one bonus exactly once (%d of %d)"
			% [session.credits_earned_this_shift, expected]
	)

	main.queue_free()
	await physics_frame


## The off-screen call arrow, end to end in the real scene, through the same
## canvas transform the running game uses.
##
## Two separate claims. First, that the arrow points at the fire at all: the
## shipped version pointed at the world origin from every position on the map,
## because FireIncident left its node at (0, 0) and drew the building's outline
## in world coordinates from there, so global_position was the same corner of
## the neighbourhood for every call. Second, that the direction is a property of
## the world and not of the truck: the camera is north up, so turning the truck
## must not move the arrow by a single degree.
func _check_the_call_arrow_points_at_the_fire_from_any_heading() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	main._on_start_shift_pressed()
	await physics_frame
	var incident: Node = main._dispatch.active_incident

	_check(
		incident.global_position.distance_to(incident._center) < 0.01,
		"a dispatched incident stands where its building stands, not at the world origin"
			+ " (at %s)" % incident.global_position
	)

	var compass: Dictionary = {
		"east": Vector2(1.0, 0.0),
		"north": Vector2(0.0, -1.0),
		"west": Vector2(-1.0, 0.0),
		"south": Vector2(0.0, 1.0),
	}
	# Far enough that the fire is off screen whichever way the camera is clamped.
	var distance: float = 3000.0
	var first: Dictionary = {}

	# Measured from the middle of the screen, not from the truck. Near a map
	# edge the camera is clamped and the truck sits off centre, so a fire due
	# east of the TRUCK is genuinely a few degrees off due east of the SCREEN,
	# and the arrow is right to say so. The truck is stationary throughout, so
	# the camera does not lead and this point does not move between headings.
	for heading in [0.0, PI * 0.5, PI]:
		for name in compass:
			var direction: Vector2 = compass[name]
			incident.global_position = _screen_centre_world(main) + direction * distance
			truck.rotation = heading
			await physics_frame

			var state: Dictionary = main._incident_indicator_state(incident.global_position)
			if not state["shown"]:
				_check(false, "the arrow must be shown for a fire %s and far away" % name)
				continue
			if not first.has(name):
				first[name] = state["direction"]

			_check(
				state["direction"].distance_to(direction) < 0.001,
				"a fire due %s draws the arrow %s at truck heading %.2f"
					% [name, state["direction"], heading]
			)
			_check(
				first[name].distance_to(state["direction"]) < 0.001,
				"turning the truck to %.2f does not move the %s arrow" % [heading, name]
			)

	main.queue_free()
	await physics_frame


## The other half of the rule: on screen, no arrow. The shipped version never
## hid, because the origin it pointed at was almost never in shot.
func _check_the_call_arrow_hides_once_the_fire_is_on_screen() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	main._on_start_shift_pressed()
	await physics_frame
	var incident: Node = main._dispatch.active_incident
	var camera: Node = main._camera

	# Straight on top of the truck, which the camera is centred on: as on screen
	# as anything gets.
	incident.global_position = truck.global_position
	camera.snap_to_target()
	await physics_frame
	_check(
		not main._incident_indicator_state(incident.global_position)["shown"],
		"a fire in the middle of the screen shows no arrow"
	)

	# And well outside the view, which the arrow does have to catch.
	incident.global_position = truck.global_position + Vector2(3000.0, 0.0)
	await physics_frame
	var state: Dictionary = main._incident_indicator_state(incident.global_position)
	_check(state["shown"], "a fire 3000 units away shows the arrow")
	_check(
		main.get_viewport_rect().has_point(state["position"]),
		"and draws it inside the viewport at %s" % state["position"]
	)

	main.queue_free()
	await physics_frame


## The world point the middle of the screen is looking at, taken from the same
## canvas transform the game reads, so camera lead and the map edge clamp are
## both already in it.
func _screen_centre_world(main: Node) -> Vector2:
	var canvas: Transform2D = main.get_viewport().get_canvas_transform()
	return canvas.affine_inverse() * (main.get_viewport_rect().size * 0.5)


## The block fill, driven into rather than reasoned about.
##
## Before this part the land between the buildings was open ground: the truck
## could leave the road at any gap between two houses and drive across the back
## gardens, which is what made a 140 unit road read as a line painted on a field
## rather than as the only way through the neighbourhood. Blocks now carry
## collision on layer 5, and the truck's mask includes it.
##
## The station sits on Elm Avenue facing south, with block blk_00 immediately to
## its east; the truck is aimed straight at the gap between that block's north
## and south rows of houses, which is the emptiest ground on the map.
## The fictional map, driven straight off Elm Avenue into the lot beside the
## station. This is the check that says the rewrite changed nothing it was not
## meant to change (Milestone 5 Part 1).
##
## The old MapBuilder read the fence off MapDefinition.blocks, a hand-typed
## rectangle whose west edge sits at x 540 with the fence 34 further in at 574.
## Nothing reads those rectangles any more: the fence is now derived from the
## road network by cutting the roads and their sidewalks out of the map. So the
## number is asserted twice over. The derived geometry has to put the fence at
## the same 574 the hand-built rectangle did, and the truck has to be stopped
## there. Either half failing on its own would be a real defect that a check
## comparing the truck only against the derived answer would happily miss.
func _check_an_empty_lot_stops_the_truck() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	const HAND_BUILT_FENCE_X: float = 574.0
	var start: Vector2 = main.get_station_spawn_position()
	var builder: Node = main._map_builder

	# Due east off Elm Avenue, straight at the lot.
	var crossings: Array[float] = _crossings_along(
		[builder.get_kerb_region(), builder.get_lot_region()], start, Vector2.RIGHT, 600.0
	)
	var kerb: float = start.x + crossings[0]
	var fence: float = start.x + crossings[1]

	_check(
		is_equal_approx(fence, HAND_BUILT_FENCE_X),
		"the fence derived from the road network stands where the hand-built block"
			+ " rectangle put it (derived %.1f, hand-built %.1f)" % [fence, HAND_BUILT_FENCE_X]
	)
	_check(
		fence > kerb,
		"with the drivable sidewalk between the kerb and it (kerb %.1f, fence %.1f)"
			% [kerb, fence]
	)

	var deepest_nose: float = start.x + await _drive_at(truck, start, 0.0)

	_check(
		deepest_nose > start.x + 20.0,
		"the truck actually set off toward the lot (nose reached x %.1f from %.1f)"
			% [deepest_nose, start.x]
	)
	# Since sidewalks became drivable the kerb is no longer where this stops.
	# Mounting it is allowed and free; the fence 34 units further in holds.
	_check(
		deepest_nose > kerb,
		"the truck can mount the kerb onto the sidewalk (nose reached %.1f, kerb at %.1f)"
			% [deepest_nose, kerb]
	)
	_check(
		deepest_nose <= fence + 1.0,
		"four seconds of throttle at an empty lot stops at the fence"
			+ " (nose %.1f, fence at %.1f)" % [deepest_nose, fence]
	)

	main.queue_free()
	await physics_frame


## The same claim on the Windsor import, where no road is axis-aligned and
## nothing was hand-typed: driving straight off the road stops the truck at a
## fence, having let it cross a kerb first.
##
## Driven perpendicular to a real road rather than along an axis, because the
## whole question this answers is whether the fence is in the right place when
## the road runs at 63 degrees to the world. The direction, the kerb and the
## fence all come from the map's own geometry.
func _check_a_windsor_road_is_fenced_at_both_sides() -> void:
	var world: Array = await _make_world(WINDSOR_MAP)
	var main: Node = world[0]
	var truck: Node = world[1]

	var builder: Node = main._map_builder
	var graph: RoadGraph = builder.get_road_graph()

	# The longest segment that is genuinely DIAGONAL, not simply the longest.
	# The longest on this map runs within a third of a degree of due north, and
	# driving off that would prove only what Elm Grove already proves. At least
	# 15 degrees off both axes means the fence being found here is one the old
	# axis-aligned builder could not have drawn.
	const MIN_DIAGONAL: float = 0.26 # sine of about 15 degrees
	var best: Dictionary = {}
	var best_length: float = 0.0
	for edge in graph.edges:
		var from: Vector2 = graph.positions[int(edge["a"])]
		var to: Vector2 = graph.positions[int(edge["b"])]
		var direction: Vector2 = (to - from).normalized()
		if absf(direction.x) < MIN_DIAGONAL or absf(direction.y) < MIN_DIAGONAL:
			continue
		if float(edge["length"]) > best_length:
			best_length = float(edge["length"])
			best = edge
	_check(
		best_length > 200.0,
		"the Windsor map has a diagonal road segment worth driving off (%.0f units)" % best_length
	)
	if best.is_empty():
		main.queue_free()
		await physics_frame
		return

	var a: Vector2 = graph.positions[int(best["a"])]
	var b: Vector2 = graph.positions[int(best["b"])]
	var along: Vector2 = (b - a).normalized()
	var start: Vector2 = (a + b) / 2.0
	_check(
		absf(along.x) >= MIN_DIAGONAL and absf(along.y) >= MIN_DIAGONAL,
		"and that segment really does run at an angle, not along an axis"
			+ " (%.0f degrees off east)" % rad_to_deg(absf(along.angle()))
	)

	for side in [1.0, -1.0]:
		var out: Vector2 = Vector2(-along.y, along.x) * side
		var crossings: Array[float] = _crossings_along(
			[builder.get_kerb_region(), builder.get_lot_region()], start, out, 900.0
		)
		var kerb: float = crossings[0]
		var fence: float = crossings[1]
		if is_inf(fence):
			_check(false, "there is a fence somewhere off the side of the road (side %.0f)" % side)
			continue

		_check(
			fence > kerb and is_equal_approx(fence - kerb, MapBuilder.SIDEWALK_WIDTH),
			("the sidewalk off this road is exactly one sidewalk wide on side %.0f"
				+ " (kerb %.1f, fence %.1f, width %.1f)") % [side, kerb, fence, fence - kerb]
		)

		var reached: float = await _drive_at(truck, start, out.angle())
		_check(
			reached > kerb,
			"the truck mounts the kerb on side %.0f (nose reached %.1f, kerb at %.1f)"
				% [side, reached, kerb]
		)
		_check(
			reached <= fence + 1.0,
			("four seconds of throttle off the road stops at the fence, not the kerb,"
				+ " on side %.0f (nose %.1f, fence %.1f)") % [side, reached, fence]
		)

	main.queue_free()
	await physics_frame


## A whole shift on the Windsor map, paying exactly what a whole shift pays.
##
## The fictional map's version of this check has run since the first build. It
## proves the loop; it cannot prove the loop still closes on a map with 42 roads
## that bend, 255 buildings and a spawn 9,200 units down the map, which is where
## a candidate that cannot be reached, an incident with no building polygon or a
## dispatch queue carried over from another map would actually show up.
func _check_a_whole_shift_pays_out_on_the_windsor_map() -> void:
	var world: Array = await _make_world(WINDSOR_MAP)
	var main: Node = world[0]
	var session: Node = main._session

	_check(
		main.get_map_definition().map_id == "windsor_shadetree_v1",
		"the world really is built on the Windsor map (%s)" % main.get_map_definition().map_id
	)

	main._on_start_shift_pressed()
	await physics_frame

	_check(session.state == GameSession.State.PLAYING, "a shift starts on the Windsor map")
	_check(
		main._dispatch.active_incident != null,
		"and the first Windsor call is dispatched with a live incident"
	)
	_check(
		main._dispatch.active_incident != null
			and main._dispatch.active_incident.get_escalation_remaining() > 0.0,
		"with escalation margin still on the clock"
	)

	var expected: int = (
		session.balance.credits_per_call * session.balance.calls_per_shift
		+ session.balance.shift_completion_bonus
	)
	for _call in range(session.balance.calls_per_shift):
		var incident: Node = main._dispatch.active_incident
		if incident == null:
			break
		incident.apply_suppression(incident.max_health * 2.0)
		main._dispatch._confirmation_remaining = 0.0
		main._dispatch._dispatch_next()
		await physics_frame

	_check(
		session.state == GameSession.State.RESULTS,
		"clearing three Windsor calls ends the shift in results"
	)
	_check(
		session.credits_earned_this_shift == expected,
		"a whole Windsor shift pays exactly %d credits (actual %d)"
			% [expected, session.credits_earned_this_shift]
	)

	main.queue_free()
	await physics_frame


## A shift started on Windsor the way the menu starts one, checked on its very
## first physics frame (Milestone 6 Part 0).
##
## James finished the first call of a Windsor shift with the condition bar at 10
## and asked the fair question: did he crash, or does the new menu path start
## him broken? Nothing in reset_for_new_shift looked wrong, and reading it again
## would not have answered him. This does.
func _check_a_windsor_shift_starts_whole() -> void:
	var world: Array = await _make_world(WINDSOR_MAP)
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = main._water

	# The menu path exactly: choose the map, then press Start shift.
	main._on_map_chosen("windsor_shadetree_v1")
	await physics_frame
	main._on_start_shift_pressed()
	await physics_frame

	_check(
		is_equal_approx(truck.condition, truck.max_condition),
		"a Windsor shift begun from the menu starts on full condition (%.1f of %.1f)"
			% [truck.condition, truck.max_condition]
	)
	_check(
		is_equal_approx(water.water_remaining, water.tank_capacity),
		"and a full tank (%.1f of %.1f)" % [water.water_remaining, water.tank_capacity]
	)

	# And still whole ten seconds later with nothing touched, so a spawn sitting
	# inside something solid cannot drain the bar before the player moves.
	var damage_events: Array[float] = []
	truck.truck_damaged.connect(
		func(amount: float, _speed: float) -> void: damage_events.append(amount)
	)
	for _frame in range(10 * PHYSICS_FPS):
		truck.set_drive_intent(0.0, 0.0, false)
		await physics_frame
	_check(
		damage_events.is_empty() and is_equal_approx(truck.condition, truck.max_condition),
		"and is still on full condition after ten seconds parked at the station"
			+ " (%.1f, %d damage event(s))" % [truck.condition, damage_events.size()]
	)

	main.queue_free()
	await physics_frame


## Driving off Hembree Lane into the side street that joins it, through the
## junction, at speed (Milestone 6 Part 1).
##
## Honest about what this proves: the wedges Milestone 5 left across these
## mouths were drawn, not solid, so this check would have passed while the map
## looked shut. It is here because a junction the truck cannot drive through is
## the defect James reported, and nothing else in this suite ever turns one road
## into another. test_map_geometry.gd is the check that catches the drawing.
func _check_the_truck_turns_off_hembree_lane_into_a_side_street() -> void:
	var world: Array = await _make_world(WINDSOR_MAP)
	var main: Node = world[0]
	var truck: Node = world[1]
	var graph: RoadGraph = main._map_builder.get_road_graph()
	var map: MapDefinition = main.get_map_definition()

	var junction: Dictionary = _first_side_street_off(graph, map, "Hembree Lane")
	_check(
		not junction.is_empty(),
		"Hembree Lane has a side street to turn into near the station"
	)
	if junction.is_empty():
		main.queue_free()
		await physics_frame
		return

	var node: Vector2 = junction["node"]
	var approach: Vector2 = junction["approach"]
	var target: Vector2 = junction["target"]
	var arrived_within: float = float(junction["width"]) * 0.5 + ARRIVAL_MARGIN

	var damage_events: Array[float] = []
	truck.truck_damaged.connect(
		func(amount: float, _speed: float) -> void: damage_events.append(amount)
	)

	truck.global_position = approach
	truck.rotation = (node - approach).angle()
	truck.velocity = Vector2.ZERO

	# Steer at a point well down the side street and drive at the junction. A
	# junction drawn shut, or a wedge solid enough to stop the truck, shows up as
	# a truck that never arrives.
	#
	# Full throttle on the run-up and eased to TURNING_THROTTLE inside
	# TURN_IN_DISTANCE of the junction, which is what a driver does: the truck
	# tops out at 250 units a second and its turning circle at that speed is
	# wider than the junction. Still at speed, and still nothing like slow.
	var closest: float = INF
	var frames: int = 0
	for _frame in range(12 * PHYSICS_FPS):
		frames += 1
		var error: float = wrapf(
			(target - truck.global_position).angle() - truck.rotation, -PI, PI
		)
		var throttle: float = 1.0
		if truck.global_position.distance_to(node) < TURN_IN_DISTANCE:
			throttle = TURNING_THROTTLE
		truck.set_drive_intent(throttle, clampf(error * 2.0, -1.0, 1.0), false)
		await physics_frame
		closest = minf(closest, truck.global_position.distance_to(target))
		# Stopped at the target rather than driven on through it: the question is
		# whether the junction can be taken, and holding the throttle down past a
		# point 268 units into a side street only asks what is at the far end of
		# the side street.
		if closest <= arrived_within:
			break

	# Seconds, not the distance: the run stops on arrival, so the distance
	# reported would always be just inside the allowance and would say nothing.
	# The time says how much of the twelve seconds it needed.
	_check(
		closest <= arrived_within,
		"the truck drives off Hembree Lane at %s, through the junction and %.0f units"
			% [str(approach), node.distance_to(target)]
			+ " onto the %.0f unit road that joins it, in %.1f s of a possible 12.0"
			% [float(junction["width"]), float(frames) / float(PHYSICS_FPS)]
			+ " (within %.0f units of its centreline)" % arrived_within
	)
	_check(
		damage_events.is_empty(),
		"and takes nothing off the condition bar doing it (%d damage event(s))"
			% damage_events.size()
	)

	main.queue_free()
	await physics_frame


## The junction on the named road nearest the station where a differently named
## road joins it, with a point to start from on the named road and a point to
## aim at down the side street.
func _first_side_street_off(
	graph: RoadGraph, map: MapDefinition, road_name: String
) -> Dictionary:
	var station: Vector2 = map.station_spawn_position
	var best: Dictionary = {}
	var best_distance: float = INF

	for node in graph.junction_nodes():
		var main_edge: int = -1
		var side_edge: int = -1
		for edge_index in graph.incident_edges[node]:
			var here: String = String(
				map.roads[int(graph.edges[int(edge_index)]["road_index"])].get("name", "")
			)
			if here == road_name:
				if main_edge < 0 or _longer(graph, int(edge_index), main_edge):
					main_edge = int(edge_index)
			elif side_edge < 0 or _longer(graph, int(edge_index), side_edge):
				side_edge = int(edge_index)
		if main_edge < 0 or side_edge < 0:
			continue

		var distance: float = graph.positions[node].distance_to(station)
		if distance >= best_distance:
			continue
		best_distance = distance
		best = {
			"node": graph.positions[node],
			"approach": _along(graph, node, main_edge, APPROACH_RUN_UP),
			"target": _along(graph, node, side_edge, SIDE_STREET_RUN),
			"width": float(graph.edges[side_edge]["width"]),
		}
	return best


func _longer(graph: RoadGraph, edge_index: int, than: int) -> bool:
	return float(graph.edges[edge_index]["length"]) > float(graph.edges[than]["length"])


## A point "distance" along the road that leaves the node on this arm,
## following the road through its own bends and stopping where the road does.
##
## One segment is not enough to aim at. Windsor's ways are split at every
## shared node, so the arm leaving a junction can be 176 units long, and a
## point 150 units into a street is still inside the turn: the truck sweeps
## past it and its closest approach measures the width of the sweep rather than
## whether it made the turn. Following the road for several segments puts the
## aiming point somewhere the truck has to have straightened out to reach.
func _along(graph: RoadGraph, node: int, edge_index: int, distance: float) -> Vector2:
	var road: int = int(graph.edges[edge_index]["road_index"])
	var at: int = node
	var edge: int = edge_index
	var travelled: float = 0.0

	# Bounded by the number of edges, so a road that somehow loops back on
	# itself ends the walk rather than running forever.
	for _step in range(graph.edges.size() + 1):
		var other: int = int(graph.edges[edge]["b"])
		if int(graph.edges[edge]["a"]) != at:
			other = int(graph.edges[edge]["a"])
		var length: float = float(graph.edges[edge]["length"])
		if travelled + length >= distance:
			var into: float = distance - travelled
			var direction: Vector2 = (graph.positions[other] - graph.positions[at]).normalized()
			return graph.positions[at] + direction * into
		travelled += length
		at = other

		var next: int = -1
		for candidate in graph.incident_edges.get(at, []):
			if int(candidate) == edge:
				continue
			if int(graph.edges[int(candidate)]["road_index"]) != road:
				continue
			next = int(candidate)
			break
		if next < 0:
			# The road ends here, so the far end of it is the furthest point there
			# is to aim at.
			return graph.positions[at]
		edge = next
	return graph.positions[at]


## Pulling up to a hydrant, three ways, in the real scene against the real map.
##
## The rule this covers used to measure from the hydrant to the truck's CENTRE
## with a 48 unit radius, and a nose-in stop at the station hydrant measured 55:
## bumper almost touching it, and no prompt, no ring, nothing. Range is measured
## to the truck's bodywork now, so which way the truck is pointing when it stops
## no longer decides whether the hydrant exists.
func _check_every_approach_to_a_hydrant_hooks_up() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	var hydrant: Node = main._hydrants[0]
	var half: Vector2 = truck.get_collision_half_extents()
	var target: Vector2 = hydrant.global_position

	_check(
		String(hydrant.hydrant_id) == "h_station",
		"the first hydrant is the one outside the station (%s)" % hydrant.hydrant_id
	)

	# Nose in: drive due east at the kerb the hydrant stands on, and stop where
	# the map stops the truck.
	truck.global_position = Vector2(target.x - 140.0, target.y)
	truck.rotation = 0.0
	truck.velocity = Vector2.ZERO
	for _frame in range(3 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame

	var nose_in: float = hydrant.distance_to_truck(truck.global_transform, half)
	_check(
		hydrant.is_truck_in_range(truck.global_transform, half),
		"a nose-in stop at the station hydrant is in range (%.1f from the bodywork,"
			% nose_in
			+ " %.1f from the centre, radius %.1f)" % [
				truck.global_position.distance_to(target), hydrant.get_interaction_radius()
			]
	)

	# And it really is the whole rule, not just the distance: with the truck
	# stopped there and NOTHING held, this must start the hose.
	var outcome: Dictionary = hydrant.evaluate(
		1.0 / float(PHYSICS_FPS), truck.global_transform, half,
		truck.get_forward_speed(), 0.0, 100.0
	)
	_check(
		int(outcome["state"]) == Hydrant.State.LAUNCHING,
		"and stopping there throws the hose on its own, no key (prompt %d, state %d)"
			% [outcome["prompt"], outcome["state"]]
	)
	hydrant.reset_for_new_shift()

	# Alongside: facing up the street, pulled over hard against the kerb the
	# hydrant stands on. Pushed sideways rather than driven, because throttle
	# only goes forward and this is about where the truck ENDS UP, not about how
	# it got there. The stop is still the real one physics gives.
	truck.global_position = Vector2(target.x - 120.0, target.y)
	truck.rotation = -PI / 2.0
	for _frame in range(PHYSICS_FPS):
		truck.velocity = Vector2(140.0, 0.0)
		truck.move_and_slide()
		await physics_frame
	_check(
		hydrant.is_truck_in_range(truck.global_transform, half),
		"pulling up alongside is in range (%.1f from the bodywork, %.1f from the centre)" % [
			hydrant.distance_to_truck(truck.global_transform, half),
			truck.global_position.distance_to(target),
		]
	)

	# And parked alongside but stopped a full truck length short of it, which is
	# the sloppy version of the same thing.
	truck.global_position = Vector2(truck.global_position.x, target.y + 90.0)
	await physics_frame
	_check(
		hydrant.is_truck_in_range(truck.global_transform, half),
		"stopping a truck length short is still in range (%.1f from the bodywork)"
			% hydrant.distance_to_truck(truck.global_transform, half)
	)

	# At a sloppy angle, driven into the kerb.
	truck.global_position = target + Vector2(-160.0, 160.0)
	truck.rotation = -PI / 4.0
	truck.velocity = Vector2.ZERO
	for _frame in range(3 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame
	_check(
		hydrant.is_truck_in_range(truck.global_transform, half),
		"pulling up at a sloppy angle is in range (%.1f from the bodywork, %.1f from the centre)"
			% [
				hydrant.distance_to_truck(truck.global_transform, half),
				truck.global_position.distance_to(target),
			]
	)

	main.queue_free()
	await physics_frame


# ---------------------------------------------------------------------------
# How narrow a road the truck can actually turn a corner in.
#
# This is a MEASUREMENT, not an assertion about a particular map. The validator
# needs a number for "a road narrow enough that the truck cannot get round the
# corner", and inventing one from the truck's length and steering rate would be
# arithmetic about a physics engine rather than an observation of it. So the
# corner is built, driven, and narrowed until the turn stops working, and the
# width where it stops is printed and then asserted against both maps.
#
# The rig is an L: a road running east that ends at a road running south, with
# the outside of the corner fenced off, which is the tightest 90 degrees a
# player can be asked to take. The drivable corridor is the road plus the
# sidewalk band on each side, exactly as in the game, because the sidewalk is
# drivable there too and pretending otherwise would measure a corner the player
# never actually meets.
# ---------------------------------------------------------------------------

## Where the two roads of the rig meet, and how big the rig is.
const CORNER: Vector2 = Vector2(2000.0, 2000.0)
const RIG_EXTENT: float = 4000.0

## Cornering speed, as a fraction of top speed. A fire engine does not take a
## residential corner flat out, and measuring at top speed would demand roads
## wide enough for a manoeuvre no one performs. 0.4 of 250 is 100 units/second.
const CORNER_SPEED_FRACTION: float = 0.4

## Widths swept, and the step between them. Descending, stopping at the first
## width the truck cannot get round at any turn-in point.
const SWEEP_FROM_WIDTH: float = 320.0
const SWEEP_TO_WIDTH: float = 20.0
const SWEEP_STEP: float = 20.0

## Where the driver starts turning, as the truck centre's offset from the
## junction centre along the approach. Swept, because the question is whether
## the corner CAN be taken, not whether one particular turn-in policy takes it.
##
## Measured from the junction centre rather than from the kerb because the
## truck's turning circle at this speed is about 55 units, far tighter than any
## road here is wide, so the right moment to turn is set by the corner and not
## by the road width. Turning in at the kerb of a wide road, as this first did,
## simply drives into the block on the inside of the bend.
const TURN_IN_OFFSETS: Array[float] = [-160.0, -120.0, -80.0, -40.0, 0.0, 40.0]

## How long one attempt is given before it counts as failed.
const CORNER_ATTEMPT_SECONDS: float = 12.0


func _check_the_narrowest_road_the_truck_can_turn_in() -> void:
	var narrowest_that_works: float = -1.0
	var widest_that_fails: float = -1.0
	var width: float = SWEEP_FROM_WIDTH
	while width >= SWEEP_TO_WIDTH:
		var made_it: bool = false
		for turn_in in TURN_IN_OFFSETS:
			if await _try_the_corner(width, turn_in):
				made_it = true
				break
		if not made_it:
			widest_that_fails = width
			break
		narrowest_that_works = width
		width -= SWEEP_STEP

	_check(
		narrowest_that_works > 0.0,
		"the truck can turn a 90 degree corner at some road width in the sweep"
	)
	if narrowest_that_works <= 0.0:
		return

	if widest_that_fails > 0.0:
		print("     measured: the truck turns the corner at %.0f units and cannot at %.0f, driving %.0f units/second" % [
			narrowest_that_works, widest_that_fails, 250.0 * CORNER_SPEED_FRACTION,
		])
	else:
		# Said plainly rather than reported as a measured limit: no width in the
		# sweep defeated the turn, so this is a floor on the answer and not the
		# answer. The truck circles in about 55 units at this speed, which is
		# tighter than any road on either map, so road width is simply not what
		# stops it cornering.
		print("     measured: the truck turned the corner at every width down to %.0f units, the narrowest tried, driving %.0f units/second; no width in the sweep defeated it" % [
			narrowest_that_works, 250.0 * CORNER_SPEED_FRACTION,
		])

	# The number the validator holds both maps to. The sweep does not derive it
	# (see MapValidator.MIN_TURNABLE_ROAD_WIDTH for why it is a chosen floor
	# rather than a measured limit), but it can still catch it going stale: if
	# the truck ever becomes unable to corner at a width this rule accepts, this
	# fails and says so.
	_check(
		narrowest_that_works <= MapValidator.MIN_TURNABLE_ROAD_WIDTH,
		"MapValidator.MIN_TURNABLE_ROAD_WIDTH (%.0f) is not below the narrowest width driven successfully (%.0f)"
			% [MapValidator.MIN_TURNABLE_ROAD_WIDTH, narrowest_that_works]
	)


## One attempt at the corner. True when the truck ends up down the second road
## undamaged.
func _try_the_corner(road_width: float, turn_in_offset: float) -> bool:
	var world := Node2D.new()
	root.add_child(world)

	var builder := MapBuilder.new()
	world.add_child(builder)
	builder.build(_corner_map(road_width))

	var truck: Node = load("res://scenes/Truck.tscn").instantiate()
	world.add_child(truck)
	await physics_frame

	var half: float = road_width * 0.5
	var target_speed: float = truck.balance.forward_max_speed * CORNER_SPEED_FRACTION

	# Started already at cornering speed, 400 units short of the junction. The
	# first version accelerated from rest 800 units out, which spent most of the
	# attempt on the approach and failed every width by running out of time
	# rather than by running out of road.
	truck.global_position = Vector2(CORNER.x - 400.0, CORNER.y)
	truck.rotation = 0.0
	truck.velocity = Vector2(target_speed, 0.0)
	truck.condition = truck.max_condition

	# The corridor the truck has to end up in, which is the road plus the
	# drivable sidewalk on each side, minus its own half width so the check is
	# about the body and not the centre point.
	var corridor: float = half + MapBuilder.SIDEWALK_WIDTH - truck.get_collision_half_extents().y
	var finish_y: float = CORNER.y + half + 300.0

	var succeeded: bool = false
	for _frame in range(int(CORNER_ATTEMPT_SECONDS * PHYSICS_FPS)):
		var throttle: float = 1.0 if truck.get_forward_speed() < target_speed else 0.0
		var turning: bool = truck.global_position.x >= CORNER.x + turn_in_offset
		# Steer toward due south and then hold it, rather than holding full lock.
		# Full lock all the way round is not "taking the corner": the truck's
		# turning circle is tight enough that it simply carries on through 180
		# degrees and comes back up the road it arrived on, which fails at every
		# width and measures nothing.
		var steering: float = 0.0
		if turning:
			steering = clampf(angle_difference(truck.rotation, PI / 2.0) * 2.0, -1.0, 1.0)
		truck.set_drive_intent(throttle, steering, false)
		await physics_frame

		if truck.condition < truck.max_condition:
			break
		if truck.global_position.y >= finish_y and absf(truck.global_position.x - CORNER.x) <= corridor:
			succeeded = true
			break

	world.queue_free()
	await physics_frame
	return succeeded


## The rig: a road east into a road south, with the land around them fenced.
## Built so the two road rectangles cover the corner square between them with
## nothing uncovered, or the truck could cut across a hole in the map.
static func _corner_map(width: float) -> MapDefinition:
	var half: float = width * 0.5
	var yard := Color(0.30, 0.44, 0.28)

	var definition := MapDefinition.new()
	definition.map_id = "turn_rig"
	definition.display_name = "Turn Rig"
	definition.world_bounds = Rect2(0.0, 0.0, RIG_EXTENT, RIG_EXTENT)
	definition.station_spawn_position = Vector2(400.0, CORNER.y)
	definition.roads = [
		{
			"id": "r_approach", "name": "Approach",
			"points": PackedVector2Array([Vector2(0.0, CORNER.y), Vector2(CORNER.x + half, CORNER.y)]),
			"width": width, "source": "synthetic", "osm_id": "",
		},
		{
			"id": "r_exit", "name": "Exit",
			"points": PackedVector2Array([Vector2(CORNER.x, CORNER.y - half), Vector2(CORNER.x, RIG_EXTENT)]),
			"width": width, "source": "synthetic", "osm_id": "",
		},
	]
	# The rig used to list the four blocks around the corner by hand so the land
	# outside the turn was solid. It no longer does, and the corner is still
	# fenced: MapBuilder derives the land from the two roads above, which is the
	# same code path both real maps go through. That is the point of the rig now
	# as well as of the corner it tests.
	return definition


## The menus, walked the way a player walks them, in the real scene.
##
## Every claim here is about wiring that no unit test can reach: which screen
## a button opens, what Escape does from each one, and whether choosing a map
## actually swaps the neighbourhood the shift then runs on.
##
## The Escape rule is the reason this is worth a check at all. It has to back
## out exactly one level and it must never land in a running game, and the way
## that breaks is not a wrong sentence in a function, it is a state nobody
## thought about while adding a screen.
func _check_the_menus_walk_the_way_a_player_walks_them() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var session: Node = main._session
	var ui: Node = main._ui

	_check(session.state == GameSession.State.MENU, "the game opens on the home menu")

	ui.open_map_select_pressed.emit()
	await physics_frame
	_check(session.state == GameSession.State.MAP_SELECT, "Start shift opens the map choice")

	_check(session.back_out(), "Escape backs out of the map choice")
	await physics_frame
	_check(session.state == GameSession.State.MENU, "to the home menu, one level up")

	ui.open_credits_pressed.emit()
	await physics_frame
	_check(session.state == GameSession.State.CREDITS, "Data and credits opens its screen")
	_check(session.back_out(), "Escape backs out of Data and credits")
	await physics_frame
	_check(session.state == GameSession.State.MENU, "to the home menu, one level up")

	_check(
		not session.back_out(),
		"and Escape at the home menu backs out of nothing rather than into a game"
	)
	_check(session.state == GameSession.State.MENU, "leaving the player on the home menu")

	# Choosing the Windsor map: the shift starts, on that map, and the choice is
	# written to the save so the next launch opens on it.
	ui.open_map_select_pressed.emit()
	await physics_frame
	ui.map_chosen.emit("windsor_shadetree_v1")
	await physics_frame

	_check(session.state == GameSession.State.PLAYING, "choosing a map starts the shift")
	_check(
		main.get_map_definition().map_id == "windsor_shadetree_v1",
		"on the map that was chosen (%s)" % main.get_map_definition().map_id
	)
	_check(
		main._save.map_id == "windsor_shadetree_v1",
		"and the choice is remembered in the save (%s)" % main._save.map_id
	)
	_check(
		main._truck.global_position.distance_to(main.get_station_spawn_position()) < 1.0,
		"with the truck at the new map's own station, not the old map's"
	)

	# From a running game Escape pauses. It must not reach back_out() at all:
	# there is no menu above PLAYING to back out to, and the one thing this rule
	# must never do is drop the player out of a shift they are in the middle of.
	_check(
		not session.back_out(),
		"Escape in a running game backs out of nothing"
	)
	_check(
		session.state == GameSession.State.PLAYING,
		"and leaves the shift running"
	)

	main.queue_free()
	await physics_frame


## The HUD's top-right column never overlaps itself, at either resolution, in
## either state of the escalation line (Milestone 8 Part 3).
##
## Under thirty seconds the line used to grow from 15 point to 20, which made it
## taller than the row laid out for it: at four seconds left, "Time left 0:04,
## running out" sat over the credits line under it. The urgency is carried by
## the wording and by weight now, and weight does not change a row's height, so
## the panel lays out identically in both states. This asks the rendered
## rectangles rather than trusting that.
##
## Both resolutions because the column is anchored to the top right corner and
## the failure was a height, not a width: 960x540 is the smallest window this
## project has ever been run at and is where a row has least room.
func _check_the_hud_rows_never_overlap() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var ui: GameUI = main.get_node("GameUI")

	main._on_start_shift_pressed()
	await physics_frame

	for size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		get_root().content_scale_size = size
		# Both states, driven through the real setter rather than by poking the
		# label, so the check exercises the rule and not a copy of it.
		for seconds in [90.0, 4.0]:
			ui.set_margin_seconds(seconds)
			ui.set_call(1, 3)
			ui.set_credits(1250)
			ui.set_siren(true)
			await physics_frame
			await physics_frame

			var rows: Array[Control] = [
				ui._call_label, ui._margin_label, ui._credits_label, ui._siren_label,
			]
			var overlaps: Array[String] = []
			for i in range(rows.size()):
				for j in range(i + 1, rows.size()):
					var a: Rect2 = rows[i].get_global_rect()
					var b: Rect2 = rows[j].get_global_rect()
					if a.grow(HUD_MIN_ROW_GAP / 2.0).intersects(b):
						overlaps.append("%s over %s" % [rows[i].name, rows[j].name])
			_check(
				overlaps.is_empty(),
				"HUD rows keep their clear gap at %dx%d with %.0f s left (%s)" % [
					size.x, size.y, seconds, overlaps
				]
			)
			# And the whole column stays on screen.
			var lowest: float = 0.0
			for row in rows:
				lowest = maxf(lowest, row.get_global_rect().end.y)
			_check(
				lowest <= float(size.y),
				"the column ends %.0f above the bottom of a %d high window" % [
					float(size.y) - lowest, size.y
				]
			)

	get_root().content_scale_size = Vector2i(1280, 720)
	main.queue_free()
	await physics_frame


## Z cycles the three zoom levels, the camera limits follow it, and the level
## the player picked survives a change of map (Milestone 8 Part 3).
func _check_the_zoom_control_holds_its_level() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var camera: FollowCamera = main.get_node("Camera")
	var levels: Array = main._zoom_levels()

	_check(levels.size() == 3, "there are three zoom levels (%d)" % levels.size())
	_check(
		is_equal_approx(camera.get_zoom_level(), float(levels[0])),
		"a shift opens at the first level (%.2f)" % camera.get_zoom_level()
	)

	# Round the whole cycle and back, checking the two things that are measured
	# against the screen rather than against the world follow it.
	for step in range(levels.size()):
		var expected: float = float(levels[(step + 1) % levels.size()])
		main._cycle_camera_zoom()
		await physics_frame
		_check(
			is_equal_approx(camera.get_zoom_level(), expected),
			"Z moves the zoom to %.2f (got %.2f)" % [expected, camera.get_zoom_level()]
		)
		_check(
			camera.get_look_ahead_distance() > 0.0
				and is_equal_approx(
					camera.get_look_ahead_distance(),
					FollowCamera.LOOK_AHEAD_DISTANCE * (FollowCamera.ZOOM / expected)
				),
			"and the lead scales with it (%.0f)" % camera.get_look_ahead_distance()
		)
		# The overscan is half a screen at this zoom, so the limits must sit
		# outside the world by more at a wider zoom and never inside it.
		var bounds: Rect2 = main._map_builder.get_world_bounds()
		_check(
			float(camera.limit_left) < bounds.position.x
				and float(camera.limit_right) > bounds.end.x
				and float(camera.limit_top) < bounds.position.y
				and float(camera.limit_bottom) > bounds.end.y,
			"and the camera may still overscan the map at %.2f" % expected
		)

	# One more press to leave it somewhere other than the default, then change
	# map: the choice must survive.
	main._cycle_camera_zoom()
	await physics_frame
	var chosen: float = camera.get_zoom_level()
	main.load_map(WINDSOR_MAP if main._map_definition.map_id != "windsor_shadetree_v1" else ELM_GROVE_MAP)
	await physics_frame
	_check(
		is_equal_approx(camera.get_zoom_level(), chosen),
		"the chosen zoom %.2f survives a change of map (got %.2f)" % [
			chosen, camera.get_zoom_level()
		]
	)

	main.queue_free()
	await physics_frame


# ---------------------------------------------------------------------------
# The automatic hookup, in the real scene (Milestone 9 Part 0)
#
# The unit suite walks the state machine with arithmetic. These two drive the
# real truck, on the real map, through Main's own _update_hydrants, which is the
# only path the game itself ever uses. Main's _physics_process is switched off
# by _make_world (it would poll a keyboard nobody is holding), so the one
# function under test is called by hand, once per frame, with the real delta.


## Rolls the engine up to the station hydrant at a creep, checks the hose goes
## out with nothing held, then drives on and measures where it lets go.
##
## Everything happens ALONG THE ROAD, on the axis the station's own spawn
## heading names, and not on a convenient screen axis. The first version of this
## check drove east and west and could never get further than 224 units from the
## hydrant in either direction, because the station hydrant stands on the kerb of
## a street that runs north and south: east and west are the kerb and the
## station. It read the block as a hose that would not snap.
func _check_the_hose_hooks_up_by_itself_and_snaps_when_pulled() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = truck.get_node("WaterSystem")
	var delta: float = 1.0 / float(PHYSICS_FPS)

	var hydrant: Node = main._hydrants[0]
	var half: Vector2 = truck.get_collision_half_extents()
	var balance: Node = truck.balance
	var target: Vector2 = hydrant.global_position

	# The road the hydrant stands on, taken from the station's spawn heading
	# rather than assumed.
	var heading: float = main.get_station_spawn_heading()
	var along: Vector2 = Vector2.RIGHT.rotated(heading)

	# The tank is held empty for the whole check, refilled water thrown away at
	# the top of every frame. Otherwise it fills in two seconds flat, the hose
	# retracts because the job is done, and the snap this check is about never
	# gets a chance to happen: an earlier version of this check read that tidy
	# retract as a snap and reported it at 187 units.
	water.water_remaining = 0.0

	truck.global_position = target - along * 260.0
	truck.rotation = heading
	truck.velocity = Vector2.ZERO
	await physics_frame
	_check(
		not hydrant.is_truck_in_range(truck.global_transform, half),
		"the approach starts outside the ring (%.1f from the bodywork, radius %.1f)" % [
			hydrant.distance_to_truck(truck.global_transform, half),
			hydrant.get_interaction_radius(),
		]
	)

	# In at a creep, nudged rather than driven, because what is under test is the
	# hookup rule and not the accelerator.
	var creep: float = balance.hydrant_max_hookup_speed - 1.0
	var hooked_at_distance: float = -1.0
	for _frame in range(6 * PHYSICS_FPS):
		water.water_remaining = 0.0
		truck.velocity = along * creep
		truck.move_and_slide()
		await physics_frame
		main._update_hydrants(delta)
		if hooked_at_distance < 0.0 and hydrant.has_hose_out():
			hooked_at_distance = hydrant.distance_to_truck(truck.global_transform, half)
		if hydrant.get_state() == Hydrant.State.REFILLING:
			break

	_check(
		hooked_at_distance >= 0.0,
		"creeping up to the station hydrant throws the hose with no key pressed"
			+ " (at %.1f units from the bodywork)" % hooked_at_distance
	)
	_check(
		hooked_at_distance <= hydrant.get_interaction_radius() + 1.0,
		"and it went out inside the ring, not before it (%.1f, radius %.1f)" % [
			hooked_at_distance, hydrant.get_interaction_radius()
		]
	)
	_check(
		hydrant.get_state() == Hydrant.State.REFILLING,
		"and once the hose lands the tank is filling (state %d)" % hydrant.get_state()
	)

	# Water really does arrive: two frames with the drain switched off.
	water.water_remaining = 0.0
	truck.velocity = Vector2.ZERO
	for _frame in range(2):
		await physics_frame
		main._update_hydrants(delta)
	_check(
		water.water_remaining > 0.0,
		"water is actually arriving (%.2f units in two frames)" % water.water_remaining
	)

	# Now drive on down the street and find out where it lets go. Real throttle,
	# and still draining, so the only thing that can end this hose is distance.
	var snapped_at: float = -1.0
	var last_connected_at: float = -1.0
	var refilling_at_snap: bool = true
	for _frame in range(5 * PHYSICS_FPS):
		water.water_remaining = 0.0
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame
		main._update_hydrants(delta)
		var distance: float = hydrant.distance_to_truck(truck.global_transform, half)
		if hydrant.has_hose_out():
			last_connected_at = distance
			continue
		snapped_at = distance
		refilling_at_snap = water.is_refilling()
		break

	_check(
		snapped_at >= 0.0,
		"driving on snaps the hose (measured %.1f units from the bodywork)" % snapped_at
	)
	_check(
		last_connected_at > balance.hydrant_hose_slack_distance,
		"the hose was still attached past the slack distance, being dragged (%.1f, slack %.1f)"
			% [last_connected_at, balance.hydrant_hose_slack_distance]
	)
	_check(
		snapped_at > balance.hydrant_hose_slack_distance
			and snapped_at < balance.hydrant_hose_snap_distance + 20.0,
		"and it snaps between the slack distance and the snap distance (%.1f, slack %.1f,"
			% [snapped_at, balance.hydrant_hose_slack_distance]
			+ " snap %.1f)" % balance.hydrant_hose_snap_distance
	)
	_check(
		not refilling_at_snap,
		"and the refill stopped on the frame it snapped, not the frame after"
	)

	main.queue_free()
	await physics_frame


## A truck rocking on the edge of the ring throws one hose, not one per
## crossing. Same street, same axis. The tank is held empty throughout for the
## same reason as above: a full tank ends a hose politely and would mask the
## rule this is about.
func _check_a_truck_rocking_on_the_boundary_hooks_up_only_once() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]
	var water: Node = truck.get_node("WaterSystem")
	var delta: float = 1.0 / float(PHYSICS_FPS)

	var hydrant: Node = main._hydrants[0]
	var balance: Node = truck.balance
	var target: Vector2 = hydrant.global_position
	var radius: float = hydrant.get_interaction_radius()
	var half: Vector2 = truck.get_collision_half_extents()

	var heading: float = main.get_station_spawn_heading()
	var along: Vector2 = Vector2.RIGHT.rotated(heading)
	truck.rotation = heading

	# One hookup at rest, just inside the ring.
	truck.global_position = target - along * (radius - 20.0 + half.x)
	truck.velocity = Vector2.ZERO
	for _frame in range(2 * PHYSICS_FPS):
		water.water_remaining = 0.0
		await physics_frame
		main._update_hydrants(delta)
		if hydrant.get_state() == Hydrant.State.REFILLING:
			break
	_check(hydrant.get_state() == Hydrant.State.REFILLING, "hooked up once, at rest")

	# Snapped by being put well past the snap distance. The distance is measured
	# and asserted rather than assumed, because move_and_slide can shove a
	# teleported truck out of whatever it landed in.
	truck.global_position = target - along * (balance.hydrant_hose_snap_distance + 60.0 + half.x)
	truck.velocity = Vector2.ZERO
	await physics_frame
	main._update_hydrants(delta)
	_check(
		hydrant.distance_to_truck(truck.global_transform, half)
			> balance.hydrant_hose_snap_distance,
		"the truck really is past the snap distance (%.1f of %.1f)" % [
			hydrant.distance_to_truck(truck.global_transform, half),
			balance.hydrant_hose_snap_distance,
		]
	)
	_check(not hydrant.has_hose_out(), "and the hose snapped when it was pulled clear")

	# Rock across the boundary for the whole delay, always faster than a creep.
	var hookups: int = 0
	var frames: int = int(balance.hydrant_rehook_delay * float(PHYSICS_FPS))
	for frame in range(frames):
		water.water_remaining = 0.0
		var inside: bool = (frame / 10) % 2 == 0
		var offset: float = (radius - 15.0) if inside else (radius + 15.0)
		truck.global_position = target - along * (offset + half.x)
		truck.velocity = along * (balance.hydrant_max_hookup_speed + 30.0)
		await physics_frame
		main._update_hydrants(delta)
		if hydrant.get_state() == Hydrant.State.LAUNCHING:
			hookups += 1

	_check(
		hookups == 0,
		"rocking across the ring for %.1f s after a snap throws no second hose (%d hookups)"
			% [balance.hydrant_rehook_delay, hookups]
	)

	# And settling for the delay does let it hook up again: a delay, not a ban.
	truck.global_position = target - along * (radius - 20.0 + half.x)
	truck.velocity = Vector2.ZERO
	for _frame in range(int((balance.hydrant_rehook_delay + 1.0) * float(PHYSICS_FPS))):
		water.water_remaining = 0.0
		await physics_frame
		main._update_hydrants(delta)
		if hydrant.has_hose_out():
			break
	_check(
		hydrant.has_hose_out(),
		"and once it settles for %.1f s the hose goes out again (state %d)"
			% [balance.hydrant_rehook_delay, hydrant.get_state()]
	)

	main.queue_free()
	await physics_frame


## The minimap keeps out of everything else's way (Milestone 9 Part 0c).
##
## Three rectangles that share a screen: the minimap in the bottom right, the
## prompt line along the bottom, and the top-right HUD column. The prompt line
## is the one that had to move: its label used to be PRESET_BOTTOM_WIDE, so its
## rect ran the full width of the screen and straight under the minimap.
##
## Measured on get_global_rect() at both resolutions, with the longest prompt
## the game can actually produce in the label, because a check run with an empty
## prompt would pass on a label that has no width.
func _check_the_minimap_clears_the_prompt_line_and_the_hud_column() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var ui: GameUI = main.get_node("GameUI")

	main._on_start_shift_pressed()
	await physics_frame

	# The longest lines the game has. If a longer one is written later, this is
	# the list it has to be added to.
	var prompts: Array[String] = [
		"Out of water. Pull up slowly at a hydrant to refill",
		"Refilling, 100/125 units",
		"Slow down to hook up",
		"Hose snapped",
	]

	for window_size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		# BOTH, and then the screen is read back rather than assumed. Setting
		# content_scale_size alone left the UI laid out in the headless window's
		# own size, and the first version of this check was measuring rectangles
		# against a screen 1280 by 1280 that no player will ever have.
		get_root().size = window_size
		get_root().content_scale_size = window_size
		await physics_frame
		var screen: Rect2 = get_root().get_visible_rect()
		_check(
			Vector2i(screen.size) == window_size,
			"the window really is %dx%d for this pass (%s)" % [
				window_size.x, window_size.y, screen.size
			]
		)
		for prompt in prompts:
			ui.set_prompt(prompt)
			ui.set_margin_seconds(4.0)
			ui.set_call(1, 3)
			ui.set_credits(1250)
			ui.set_siren(true)
			await physics_frame
			await physics_frame

			var minimap: Rect2 = ui.get_minimap().get_global_rect()
			var button: Rect2 = ui.get_minimap().get_zoom_button().get_global_rect()
			var prompt_rect: Rect2 = ui._prompt_label.get_global_rect()
			var column: Rect2 = ui._call_label.get_global_rect().merge(
				ui._siren_label.get_global_rect()
			)

			# The zoom button lives inside the panel, so it is clear of
			# everything the panel is clear of, but it is asserted separately
			# because it is the one thing on the HUD a player has to hit.
			_check(
				minimap.encloses(button),
				"%dx%d: the zoom button %s is inside the panel %s" % [
					window_size.x, window_size.y, button, minimap
				]
			)
			_check(
				not button.intersects(prompt_rect) and not button.intersects(column),
				"%dx%d: and clear of the prompt line and the HUD column" % [
					window_size.x, window_size.y
				]
			)
			_check(
				not minimap.intersects(prompt_rect),
				"%dx%d: the minimap %s clears the prompt line %s carrying \"%s\"" % [
					window_size.x, window_size.y, minimap, prompt_rect, prompt
				]
			)
			_check(
				not minimap.intersects(column),
				"%dx%d: and clears the HUD column %s" % [
					window_size.x, window_size.y, column
				]
			)
			_check(
				not prompt_rect.intersects(column),
				"%dx%d: and the prompt line clears the HUD column too" % [
					window_size.x, window_size.y
				]
			)

		# And the panel is actually on the screen, in the corner it says it is
		# in. A minimap pushed off the bottom right would pass every intersection
		# test above by not being anywhere.
		var panel: Rect2 = ui.get_minimap().get_global_rect()
		_check(
			screen.encloses(panel),
			"%dx%d: the minimap is fully on screen (%s in %s)" % [
				window_size.x, window_size.y, panel, screen
			]
		)
		_check(
			panel.end.x > float(window_size.x) * 0.6
				and panel.end.y > float(window_size.y) * 0.6,
			"%dx%d: and it is in the bottom right corner (ends at %s)" % [
				window_size.x, window_size.y, panel.end
			]
		)

	ui.set_prompt("")
	get_root().size = Vector2i(1280, 720)
	get_root().content_scale_size = Vector2i(1280, 720)
	main.queue_free()
	await physics_frame


## M turns the panel off and on, and the choice survives a change of map, the
## same way the zoom level does.
func _check_the_minimap_toggle_holds_across_a_change_of_map() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var ui: GameUI = main.get_node("GameUI")

	_check(ui.is_minimap_shown(), "the minimap starts on")

	main._toggle_minimap()
	_check(not ui.is_minimap_shown(), "M turns it off")
	_check(
		main._transient_message == "Minimap off",
		"and says so on the prompt line (\"%s\")" % main._transient_message
	)

	main.load_map(WINDSOR_MAP)
	await physics_frame
	_check(not ui.is_minimap_shown(), "and it stays off across a change of map")

	main._toggle_minimap()
	_check(ui.is_minimap_shown(), "M turns it back on")
	main.load_map(ELM_GROVE_MAP)
	await physics_frame
	_check(ui.is_minimap_shown(), "and that survives a change of map as well")

	# The panel really was rebuilt for the map now loaded, rather than still
	# drawing the last one: the station of THIS map lands inside the drawing.
	var minimap: Minimap = ui.get_minimap()
	var station: Vector2 = minimap.world_to_panel(main.get_station_spawn_position())
	_check(
		minimap.get_content_rect().grow(0.01).has_point(station),
		"and it is drawing the map that is loaded (station at %s in %s)" % [
			station, minimap.get_content_rect()
		]
	)

	main.queue_free()
	await physics_frame


## THE TWO ZOOMS ARE INDEPENDENT.
##
## The minimap has its own zoom on N and on the button in its corner; the camera
## has had its own on Z since Milestone 8. They are two controls on one screen
## that both mean "zoom", and the one way this feature can be wrong in a way
## nobody notices until they are driving is for one of them to move the other.
## Cycled in both directions here, against the real camera in the real scene.
func _check_the_minimap_zoom_never_moves_the_camera_zoom() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var ui: GameUI = main.get_node("GameUI")
	var camera: Node = main.get_node("Camera")
	var minimap: Minimap = ui.get_minimap()

	main._on_start_shift_pressed()
	await physics_frame

	# Cycling the minimap leaves the camera exactly where it was.
	var camera_before: Vector2 = camera.zoom
	var camera_level_before: int = main._zoom_index
	for _step in range(minimap.get_zoom_levels().size() + 1):
		main._cycle_minimap_zoom()
		await physics_frame
		_check(
			camera.zoom.is_equal_approx(camera_before),
			"minimap zoom %sx leaves the camera at %s (%s)" % [
				String.num(minimap.get_zoom(), 1), camera_before, camera.zoom
			]
		)
	_check(
		main._zoom_index == camera_level_before,
		"and the camera's own zoom level is untouched (%d)" % main._zoom_index
	)

	# And the other way: cycling the camera leaves the minimap where it was.
	var minimap_before: int = minimap.get_zoom_index()
	var view_before: Rect2 = minimap.get_view_rect()
	for _step in range(main._zoom_levels().size() + 1):
		main._cycle_camera_zoom()
		await physics_frame
		_check(
			minimap.get_zoom_index() == minimap_before,
			"camera zoom %.2f leaves the minimap on level %d (%d)" % [
				camera.zoom.x, minimap_before, minimap.get_zoom_index()
			]
		)
	_check(
		minimap.get_view_rect().is_equal_approx(view_before),
		"and the minimap is still showing the same piece of the map"
	)

	# The button in the panel's corner is the same control as N, not a second
	# one that happens to look like it. Measured against where the camera is
	# NOW: the loop above deliberately moved it, and comparing against the zoom
	# it had at the top of this check would be asserting that the camera control
	# does not work.
	var camera_now: Vector2 = camera.zoom
	var by_key: int = minimap.get_zoom_index()
	minimap.get_zoom_button().pressed.emit()
	await physics_frame
	_check(
		minimap.get_zoom_index() != by_key,
		"pressing the panel's own button moves the minimap zoom too (%d to %d)" % [
			by_key, minimap.get_zoom_index()
		]
	)
	_check(
		camera.zoom.is_equal_approx(camera_now),
		"and still does not touch the camera (%s, was %s)" % [camera.zoom, camera_now]
	)

	main.queue_free()
	await physics_frame


## The signals run with the game, stop with it, and start every shift on the
## same phase (Milestone 9 Part 2).
##
## The clock is the whole of the signal system's state, so these three
## properties are the whole of its behaviour over time. The pause one is the
## reason TrafficSignals is PROCESS_MODE_PAUSABLE in Main.tscn while Main itself
## is ALWAYS: without saying so explicitly the node would inherit Main's mode,
## run behind the pause menu, and jump a junction to a different phase while the
## player was reading it.
func _check_the_signals_run_pause_and_reset_with_the_shift() -> void:
	var world: Array = await _make_world(WINDSOR_MAP)
	var main: Node = world[0]
	var signals: TrafficSignals = main.get_node("TrafficSignals")

	_check(
		signals.get_signal_count() == 6,
		"Windsor builds its six signalled junctions in the real scene (%d)"
			% signals.get_signal_count()
	)
	_check(
		signals.get_stop_sign_count() == 14,
		"and its fourteen stop signs (%d)" % signals.get_stop_sign_count()
	)

	main._on_start_shift_pressed()
	await physics_frame
	_check(
		absf(signals.clock) < 0.2,
		"a shift starts with every junction on the same phase (clock %.2f)" % signals.clock
	)

	# Running.
	var before: float = signals.clock
	for _frame in range(PHYSICS_FPS):
		await physics_frame
	var ran: float = signals.clock - before
	_check(
		ran > 0.5 and ran < 1.5,
		"a second of play advances the cycle about a second (%.2f)" % ran
	)

	# Paused. The clock must not move at all.
	# This runner IS the SceneTree, so its own "paused" is the game's pause.
	paused = true
	# A frame either side, so the check is of a whole second of real pause.
	await physics_frame
	var paused_at: float = signals.clock
	for _frame in range(PHYSICS_FPS):
		await physics_frame
	_check(
		absf(signals.clock - paused_at) < 0.001,
		"and a second of pause advances it not at all (%.4f)" % (signals.clock - paused_at)
	)
	paused = false
	await physics_frame

	# Running again from where it stopped, not from where it would have been.
	for _frame in range(PHYSICS_FPS / 2):
		await physics_frame
	_check(
		signals.clock > paused_at,
		"resuming carries on from the phase it was paused on (%.2f from %.2f)" % [
			signals.clock, paused_at
		]
	)

	# And the next shift starts the cycle over.
	main._on_start_shift_pressed()
	await physics_frame
	_check(
		absf(signals.clock) < 0.2,
		"and the next shift starts the cycle again (clock %.2f)" % signals.clock
	)

	# Elm Grove's whole grid is signalled and it has no stop signs at all.
	main.load_map(ELM_GROVE_MAP)
	await physics_frame
	_check(
		signals.get_signal_count() == 16 and signals.get_stop_sign_count() == 0,
		"Elm Grove's sixteen crossroads are all signalled, with no stop signs (%d, %d)" % [
			signals.get_signal_count(), signals.get_stop_sign_count()
		]
	)

	main.queue_free()
	await physics_frame
