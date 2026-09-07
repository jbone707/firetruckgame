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

	# Aim due east down an open lane at the map's edge wall, then hold the
	# throttle into it for ten seconds, which is twenty contact cooldowns.
	truck.rotation = 0.0
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
