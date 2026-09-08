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


## The damage curve, after James's playtest (Milestone 9).
##
## He reported that damage happened "when you are stopped or very slow and
## turning" and asked for it to be "more a high speed thing not just a tiny
## tap". Two changes: the threshold went 60 to 120, and the cost above it went
## from linear to the square of how far up the range the impact sits. This
## checks the SHAPE rather than the numbers, so retuning the numbers on purpose
## does not fail it, but flattening the curve back out does.
func test_damage_is_a_high_speed_thing_and_a_slow_knock_costs_nothing() -> void:
	var truck: TruckController = _make_truck()
	var balance: Node = truck.balance
	var threshold: float = balance.collision_damage_threshold
	var top: float = balance.forward_max_speed

	assert_true(
		threshold >= top * 0.4,
		"the threshold is a real fraction of top speed, not a scratch (%.0f of %.0f)"
			% [threshold, top]
	)

	# Everything at or under the threshold is free, including the speeds a player
	# places the engine at.
	for speed in [0.0, 10.0, 40.0, 80.0, threshold]:
		assert_eq(
			truck.damage_for_impact(speed), 0.0,
			"arriving at %.0f units/s costs nothing" % speed
		)

	# A flat-out head-on costs what the balance says it costs.
	assert_almost_eq(
		truck.damage_for_impact(top), balance.collision_damage_at_top_speed, 0.0001,
		"a flat-out head-on costs the full amount"
	)

	# And the curve is convex: the second half of the range costs far more than
	# the first. Under the old linear rule these two halves cost the same.
	var quarter: float = threshold + (top - threshold) * 0.25
	var half: float = threshold + (top - threshold) * 0.5
	var three_quarters: float = threshold + (top - threshold) * 0.75
	var first_half: float = truck.damage_for_impact(half)
	var second_half: float = truck.damage_for_impact(top) - first_half
	assert_true(
		second_half > first_half * 2.0,
		"the top half of the range costs more than twice the bottom half (%.1f against %.1f)"
			% [second_half, first_half]
	)
	assert_true(
		truck.damage_for_impact(quarter) < balance.collision_damage_at_top_speed * 0.1,
		"a quarter of the way up costs under a tenth of a crash (%.1f)"
			% truck.damage_for_impact(quarter)
	)
	assert_true(
		truck.damage_for_impact(three_quarters) > truck.damage_for_impact(half) * 2.0,
		"and three quarters of the way up costs more than twice half way"
	)

	# Still monotonic, and still survivable twice: the shape Milestone 4 settled.
	assert_true(
		truck.damage_for_impact(top) * 2.0 < truck.max_condition,
		"two flat-out crashes leave the engine alive (%.1f of %.0f)" % [
			truck.damage_for_impact(top) * 2.0, truck.max_condition
		]
	)
	assert_true(
		truck.damage_for_impact(top) * 3.0 > truck.max_condition,
		"and a third ends the shift"
	)

	_destroy(truck)
