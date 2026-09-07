extends "res://tests/test_case.gd"
## Impact damage rules for the engine (handoff section 4).
##
## What these cover and what they do not: they drive the real TruckController's
## own damage methods, so the threshold, the scaling and the contact cooldown
## are exercised exactly as the game runs them. They do NOT step Godot's
## physics, so they cannot prove that move_and_slide reports the contact in the
## first place. Feeling a gentle bump versus a hard crash stays on the manual
## playtest list.

const TruckControllerScript: GDScript = preload("res://scripts/TruckController.gd")
const GameBalanceScript: GDScript = preload("res://scripts/GameBalance.gd")

const FRAME_DELTA: float = 1.0 / 60.0


## A controller with a fresh GameBalance attached, ready to take damage without
## being in the scene tree. The autoload does not exist in a --script run, which
## is why TruckController takes its balance as an assignable member.
func _make_truck() -> TruckController:
	var balance: Node = GameBalanceScript.new()
	var truck: TruckController = TruckControllerScript.new()
	truck.balance = balance
	truck.max_condition = balance.truck_starting_condition
	truck.condition = balance.truck_starting_condition
	return truck


## Frees the balance instance as well as the controller. Neither is in the tree,
## so nothing reclaims them automatically, and freeing only the truck leaves the
## balance behind as a leaked ObjectDB entry at exit.
func _destroy(truck: TruckController) -> void:
	var balance: Node = truck.balance
	truck.balance = null
	truck.free()
	balance.free()


func test_resting_against_a_wall_deducts_condition_exactly_once() -> void:
	var truck: TruckController = _make_truck()
	var balance: Node = truck.balance
	var starting_condition: float = truck.condition

	# A one element array, not a plain int: GDScript lambdas capture local
	# variables by value, so incrementing a captured int would be invisible out
	# here and this counter would read zero however many events actually fired.
	var damage_events: Array[int] = [0]
	truck.truck_damaged.connect(
		func(_amount: float, _speed: float) -> void: damage_events[0] += 1
	)

	# Frame 1: the crash itself. The truck arrives at 200 units/s into the wall
	# normal and loses all of it.
	truck.tick_contact_cooldown(FRAME_DELTA)
	var impact_damage: float = truck.register_wall_contact(200.0)
	assert_true(impact_damage > 0.0, "a 200 unit/s impact deals damage")

	var condition_after_impact: float = truck.condition

	# Frames 2 to 60: the player keeps the throttle buried into the same wall.
	# The truck is not moving, so the only speed it can lose per frame is the
	# speed it regained since the previous frame, which is acceleration * delta.
	var resting_speed_lost: float = balance.acceleration * FRAME_DELTA
	assert_true(
		resting_speed_lost < balance.collision_damage_threshold,
		"a resting frame's speed change stays under the damage threshold"
	)
	for _frame in range(59):
		truck.tick_contact_cooldown(FRAME_DELTA)
		truck.register_wall_contact(resting_speed_lost)

	assert_almost_eq(
		truck.condition,
		condition_after_impact,
		0.0001,
		"59 further resting frames deduct nothing more"
	)
	assert_eq(damage_events[0], 1, "exactly one damage event across 60 physics frames")
	assert_true(truck.condition < starting_condition, "the one impact did reduce condition")
	_destroy(truck)


func test_a_gentle_bump_under_the_threshold_does_no_damage() -> void:
	var truck: TruckController = _make_truck()
	var starting_condition: float = truck.condition
	var gentle: float = truck.balance.collision_damage_threshold - 1.0

	truck.tick_contact_cooldown(FRAME_DELTA)
	var damage: float = truck.register_wall_contact(gentle)

	assert_eq(damage, 0.0, "an impact just under the threshold deals no damage")
	assert_almost_eq(truck.condition, starting_condition, 0.0001, "condition is untouched")
	_destroy(truck)


func test_a_second_hard_impact_lands_once_the_cooldown_expires() -> void:
	var truck: TruckController = _make_truck()
	var cooldown: float = truck.balance.collision_contact_cooldown

	truck.tick_contact_cooldown(FRAME_DELTA)
	truck.register_wall_contact(200.0)
	var condition_after_first: float = truck.condition

	# Inside the cooldown, a second hard impact is ignored.
	truck.tick_contact_cooldown(FRAME_DELTA)
	assert_eq(
		truck.register_wall_contact(200.0), 0.0, "a hard impact inside the cooldown is ignored"
	)

	# Once it has expired, a genuine second crash counts again. Without this the
	# cooldown would be indistinguishable from simply never damaging twice.
	truck.tick_contact_cooldown(cooldown)
	assert_true(
		truck.register_wall_contact(200.0) > 0.0, "a hard impact after the cooldown damages again"
	)
	assert_true(truck.condition < condition_after_first, "the second crash reduced condition")
	_destroy(truck)


func test_damage_scales_with_impact_speed_and_condition_floors_at_zero() -> void:
	var gentle_truck: TruckController = _make_truck()
	gentle_truck.tick_contact_cooldown(FRAME_DELTA)
	var small_damage: float = gentle_truck.register_wall_contact(120.0)

	var hard_truck: TruckController = _make_truck()
	hard_truck.tick_contact_cooldown(FRAME_DELTA)
	var large_damage: float = hard_truck.register_wall_contact(240.0)

	assert_true(large_damage > small_damage, "a harder crash hurts more than a lighter one")

	# Condition must floor at zero rather than going negative, and destruction
	# must be announced exactly once however many further impacts land.
	var doomed: TruckController = _make_truck()
	var destroyed_events: Array[int] = [0]
	doomed.truck_destroyed.connect(func() -> void: destroyed_events[0] += 1)
	for _hit in range(12):
		doomed.tick_contact_cooldown(doomed.balance.collision_contact_cooldown)
		doomed.register_wall_contact(400.0)

	assert_eq(doomed.condition, 0.0, "condition floors at zero, never negative")
	assert_eq(destroyed_events[0], 1, "truck_destroyed is emitted exactly once")

	_destroy(gentle_truck)
	_destroy(hard_truck)
	_destroy(doomed)
