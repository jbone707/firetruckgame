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

const PHYSICS_FPS: int = 60

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
func _make_world() -> Array:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.set_physics_process(false)
	return [main, main.get_node("Truck")]


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
func _check_an_empty_lot_stops_the_truck() -> void:
	var world: Array = await _make_world()
	var main: Node = world[0]
	var truck: Node = world[1]

	var definition: MapDefinition = main._map_definition
	var lot: Rect2 = Rect2()
	for block in definition.blocks:
		if String(block["id"]) == "blk_00":
			lot = block["rect"]
	_check(lot.size.x > 0.0, "the map has a block blk_00 to drive at")
	if lot.size.x <= 0.0:
		main.queue_free()
		await physics_frame
		return

	truck.global_position = main.get_station_spawn_position()
	truck.rotation = 0.0  # due east, straight at the block
	truck.velocity = Vector2.ZERO
	var start_x: float = truck.global_position.x

	var deepest_x: float = -INF
	for _frame in range(4 * PHYSICS_FPS):
		truck.set_drive_intent(1.0, 0.0, false)
		await physics_frame
		deepest_x = maxf(deepest_x, truck.global_position.x)

	# The truck is 90 long, so its centre stops about 45 short of the kerb it is
	# pressed against. Anything past the kerb line means it drove onto the lot.
	_check(
		deepest_x > start_x + 20.0,
		"the truck actually set off toward the lot (reached x %.1f from %.1f)"
			% [deepest_x, start_x]
	)
	_check(
		deepest_x < lot.position.x,
		"four seconds of throttle at an empty lot never crosses its kerb"
			+ " (deepest x %.1f, kerb at %.1f)" % [deepest_x, lot.position.x]
	)

	main.queue_free()
	await physics_frame
