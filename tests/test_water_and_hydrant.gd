extends "res://tests/test_case.gd"
## Water, suppression scaling, and refill exclusivity (handoff sections 5 and 6).
##
## These drive the real WaterSystem, FireIncident and Hydrant objects outside the
## tree. Stream targeting needs a physics space and so is not covered here; the
## occlusion and exterior-hit behaviour is checked in run_physics_tests.gd.

const WaterSystemScript: GDScript = preload("res://scripts/WaterSystem.gd")
const FireIncidentScript: GDScript = preload("res://scripts/FireIncident.gd")
const HydrantScript: GDScript = preload("res://scripts/Hydrant.gd")
const GameBalanceScript: GDScript = preload("res://scripts/GameBalance.gd")

const FRAME_DELTA: float = 1.0 / 60.0

## Half the truck's 90 x 40 collision rectangle, the same shape
## TruckController.get_collision_half_extents() reads off Truck.tscn.
const TRUCK_HALF: Vector2 = Vector2(45.0, 20.0)


func _make_water() -> WaterSystem:
	var balance: Node = GameBalanceScript.new()
	var water: WaterSystem = WaterSystemScript.new()
	water.balance = balance
	water.tank_capacity = balance.tank_capacity
	water.water_remaining = balance.tank_capacity
	return water


func _make_hydrant() -> Hydrant:
	var hydrant: Hydrant = HydrantScript.new()
	hydrant.balance = GameBalanceScript.new()
	hydrant.resolve_balance()
	hydrant.hydrant_id = "hyd_test"
	return hydrant


func _destroy(node: Node) -> void:
	var balance: Node = node.balance
	node.balance = null
	node.free()
	if balance != null:
		balance.free()


## A stand-in for a fire that records what it was given, so suppression can be
## measured without building an Area2D and a polygon.
class SuppressionSpy extends RefCounted:
	var total: float = 0.0
	var calls: int = 0

	func apply_suppression(amount: float) -> float:
		total += amount
		calls += 1
		return amount


func test_water_never_goes_negative_however_hard_it_is_drained() -> void:
	var water: WaterSystem = _make_water()

	# Ask for far more than the tank holds, in one go.
	var consumed: float = water.consume_water(water.tank_capacity * 10.0)
	assert_almost_eq(consumed, water.tank_capacity, 0.0001, "consume is clamped to the tank")
	assert_eq(water.water_remaining, 0.0, "the tank empties to exactly zero")

	# And keep asking once it is empty.
	for _tick in range(100):
		assert_eq(water.consume_water(50.0), 0.0, "an empty tank consumes nothing")
	assert_eq(water.water_remaining, 0.0, "water never goes negative")

	# A negative request must not refill the tank as a side effect.
	assert_eq(water.consume_water(-25.0), 0.0, "a negative request consumes nothing")
	assert_eq(water.water_remaining, 0.0, "a negative request does not add water")

	_destroy(water)


func test_suppression_scales_with_water_actually_consumed() -> void:
	var water: WaterSystem = _make_water()
	var balance: Node = water.balance
	var spy := SuppressionSpy.new()

	# A full tick: a whole frame's flow is available.
	water.water_remaining = balance.tank_capacity
	var full_consumed: float = water.apply_spray_tick(FRAME_DELTA, spy)
	var expected_full: float = balance.spray_flow_rate * FRAME_DELTA
	assert_almost_eq(full_consumed, expected_full, 0.0001, "a full tick consumes a frame of flow")
	assert_almost_eq(
		spy.total,
		expected_full * balance.suppression_per_water_unit,
		0.0001,
		"suppression is the water consumed times the suppression rate"
	)

	# The last partial tick: less water remains than a frame of flow would use,
	# so both the consumption and the suppression must be proportionally smaller.
	var partial_spy := SuppressionSpy.new()
	var remainder: float = expected_full * 0.25
	water.water_remaining = remainder
	var partial_consumed: float = water.apply_spray_tick(FRAME_DELTA, partial_spy)

	assert_almost_eq(partial_consumed, remainder, 0.0001, "the last tick consumes only what is left")
	assert_almost_eq(
		partial_spy.total,
		remainder * balance.suppression_per_water_unit,
		0.0001,
		"the last partial tick suppresses a quarter as much, not a full tick's worth"
	)
	assert_true(
		partial_spy.total < spy.total,
		"a partial tick does strictly less work than a full one"
	)

	# Spraying at empty does nothing at all and asks for a refill.
	var empty_spy := SuppressionSpy.new()
	assert_eq(water.apply_spray_tick(FRAME_DELTA, empty_spy), 0.0, "an empty tank sprays nothing")
	assert_eq(empty_spy.calls, 0, "an empty tank applies no suppression at all")

	_destroy(water)


func test_water_missing_the_target_still_costs_the_tank() -> void:
	var water: WaterSystem = _make_water()
	var before: float = water.water_remaining

	# Handoff section 5: water is consumed while spraying even when missing.
	var consumed: float = water.apply_spray_tick(FRAME_DELTA, null)

	assert_true(consumed > 0.0, "spraying at nothing still consumes water")
	assert_almost_eq(
		water.water_remaining, before - consumed, 0.0001, "the tank drops by what was consumed"
	)
	_destroy(water)


func test_spraying_is_blocked_while_refilling_and_refill_has_priority() -> void:
	var water: WaterSystem = _make_water()

	assert_true(water.is_spray_allowed(), "spraying is allowed when not at a hydrant")

	water.begin_hookup()
	assert_false(water.is_spray_allowed(), "spraying is blocked during hookup")

	# Through the hookup delay and into refilling proper. Every count below is
	# derived from GameBalance, so these prove the rule and not the numbers.
	for _tick in range(int(water.balance.hydrant_hookup_time / FRAME_DELTA) + 2):
		water._update_refill(FRAME_DELTA)
	assert_eq(water.refill_state, WaterSystem.RefillState.REFILLING, "hookup completes into refill")
	assert_false(water.is_spray_allowed(), "spraying is still blocked while refilling")

	water.cancel_refill()
	assert_true(water.is_spray_allowed(), "spraying resumes once the refill is cancelled")
	assert_eq(
		water.refill_state, WaterSystem.RefillState.IDLE, "cancelling returns the system to idle"
	)
	_destroy(water)


func test_refill_fills_at_the_specified_rate_and_stops_at_capacity() -> void:
	var water: WaterSystem = _make_water()
	var balance: Node = water.balance
	water.water_remaining = 0.0

	water.begin_hookup()
	# Hookup first: nothing arrives during the hookup delay, whatever it is set to.
	for _tick in range(int(balance.hydrant_hookup_time / FRAME_DELTA) - 2):
		water._update_refill(FRAME_DELTA)
	assert_eq(water.water_remaining, 0.0, "no water arrives before the hookup completes")

	# One second of refilling once hooked up.
	for _tick in range(int(balance.hydrant_hookup_time / FRAME_DELTA) + 60):
		water._update_refill(FRAME_DELTA)
	assert_true(
		water.water_remaining >= balance.hydrant_refill_rate * 0.95,
		"about a second of refilling delivers about the refill rate"
	)

	# And it never overfills.
	for _tick in range(600):
		water._update_refill(FRAME_DELTA)
	assert_almost_eq(
		water.water_remaining, water.tank_capacity, 0.0001, "refilling stops at capacity"
	)
	_destroy(water)


func test_the_tank_upgrade_increases_capacity_by_a_quarter() -> void:
	var water: WaterSystem = _make_water()
	var base_capacity: float = water.balance.tank_capacity

	water.configure_capacity(false)
	assert_almost_eq(water.tank_capacity, base_capacity, 0.0001, "capacity is unchanged unowned")

	water.configure_capacity(true)
	assert_almost_eq(
		water.tank_capacity,
		base_capacity * water.balance.tank_upgrade_multiplier,
		0.0001,
		"the upgrade adds 25 percent capacity"
	)
	water.fill_tank()
	assert_almost_eq(
		water.water_remaining, base_capacity * 1.25, 0.0001, "and a new shift fills the bigger tank"
	)
	_destroy(water)


func test_fire_health_and_escalation_are_separate_and_terminal_fires_once() -> void:
	var fire: FireIncident = FireIncidentScript.new()
	fire.balance = GameBalanceScript.new()
	fire.resolve_balance()
	fire.incident_id = "inc_test"
	fire.health = fire.balance.fire_starting_health
	fire.max_health = fire.health
	fire.escalation_limit = fire.balance.fire_escalation_duration

	var extinguished: Array[int] = [0]
	fire.incident_extinguished.connect(func(_id: String) -> void: extinguished[0] += 1)

	# Suppression moves health and leaves escalation alone.
	fire.apply_suppression(30.0)
	assert_almost_eq(fire.health, 70.0, 0.0001, "suppression reduces health")
	assert_eq(fire.escalation, 0.0, "suppression does not touch escalation")

	# The killing blow absorbs only what was left, so the last tick cannot
	# over-credit, and the terminal signal fires once.
	var absorbed: float = fire.apply_suppression(500.0)
	assert_almost_eq(absorbed, 70.0, 0.0001, "the final hit absorbs only the health that remained")
	assert_eq(fire.health, 0.0, "health floors at zero")
	assert_eq(extinguished[0], 1, "incident_extinguished fires once")

	# Everything after the terminal transition is inert.
	assert_eq(fire.apply_suppression(50.0), 0.0, "an extinguished fire absorbs nothing further")
	assert_eq(extinguished[0], 1, "and does not announce itself again")
	assert_true(fire.is_terminal(), "the incident is terminal")

	_destroy(fire)


func test_a_lost_incident_cannot_also_be_extinguished() -> void:
	var fire: FireIncident = FireIncidentScript.new()
	fire.balance = GameBalanceScript.new()
	fire.resolve_balance()
	fire.incident_id = "inc_lost"
	fire.health = fire.balance.fire_starting_health
	fire.max_health = fire.health
	fire.escalation_limit = fire.balance.fire_escalation_duration

	var lost: Array[int] = [0]
	var extinguished: Array[int] = [0]
	fire.incident_lost.connect(func(_id: String) -> void: lost[0] += 1)
	fire.incident_extinguished.connect(func(_id: String) -> void: extinguished[0] += 1)

	fire._finish(false)
	assert_eq(lost[0], 1, "incident_lost fires once")

	# A stream still pointed at it as it was lost must not then extinguish it.
	fire.apply_suppression(1000.0)
	assert_eq(extinguished[0], 0, "a lost incident is never also extinguished")
	assert_eq(lost[0], 1, "and is not lost twice")

	_destroy(fire)


func test_hydrant_refuses_a_moving_truck_and_prompts_in_words() -> void:
	var hydrant: Hydrant = HydrantScript.new()
	hydrant.balance = GameBalanceScript.new()
	hydrant.resolve_balance()
	hydrant.hydrant_id = "hyd_test"
	var balance: Node = hydrant.balance

	var at_hydrant: Transform2D = Transform2D(0.0, Vector2.ZERO)
	var far_away: Transform2D = Transform2D(
		0.0, Vector2(balance.hydrant_interaction_radius * 3.0, 0.0)
	)
	var too_fast: float = balance.hydrant_max_hookup_speed + 25.0
	var slow: float = balance.hydrant_max_hookup_speed - 1.0

	var out_of_range: Dictionary = hydrant.evaluate(
		far_away, TRUCK_HALF, slow, true, false, false, 0.0
	)
	assert_eq(out_of_range["prompt"], Hydrant.Prompt.NONE, "no prompt out of range")
	assert_false(out_of_range["should_refill"], "no refill out of range")

	var moving: Dictionary = hydrant.evaluate(
		at_hydrant, TRUCK_HALF, too_fast, true, false, false, 0.0
	)
	assert_eq(moving["prompt"], Hydrant.Prompt.TOO_FAST, "a moving truck is told to slow down")
	assert_false(moving["should_refill"], "a moving truck does not refill")

	var not_holding: Dictionary = hydrant.evaluate(
		at_hydrant, TRUCK_HALF, slow, false, false, false, 0.0
	)
	assert_eq(not_holding["prompt"], Hydrant.Prompt.HOLD_TO_HOOK_UP, "stopped, told to hold E")
	assert_false(not_holding["should_refill"], "releasing E does not refill")

	var hooking: Dictionary = hydrant.evaluate(
		at_hydrant, TRUCK_HALF, slow, true, false, false, 0.4
	)
	assert_eq(hooking["prompt"], Hydrant.Prompt.HOOKING_UP, "holding E starts the hookup")
	assert_true(hooking["should_refill"], "holding E requests the refill")

	var full: Dictionary = hydrant.evaluate(at_hydrant, TRUCK_HALF, slow, true, true, true, 1.0)
	assert_eq(full["prompt"], Hydrant.Prompt.TANK_FULL, "a full tank says so")
	assert_false(full["should_refill"], "a full tank stops refilling")

	# Every prompt is a sentence, not a colour.
	assert_true(
		Hydrant.prompt_text(Hydrant.Prompt.TOO_FAST, 0.0).length() > 0, "too fast has words"
	)
	assert_true(
		Hydrant.prompt_text(Hydrant.Prompt.HOOKING_UP, 0.5).contains("50"),
		"hookup progress is stated as a percentage"
	)
	assert_eq(Hydrant.prompt_text(Hydrant.Prompt.NONE, 0.0), "", "no prompt when there is nothing to say")

	_destroy(hydrant)


## The one flag every piece of suppression feedback hangs off (Part 3): the
## steam burst, the shrinking flames' companion HUD line, and the "Knocking it
## down" prompt all read is_suppressing(). It has to mean "this tick actually
## took health off a fire", not "the trigger is held", or the game would tell
## the player the stream is working while they hose a wall.
func test_hitting_is_true_only_on_ticks_that_actually_suppressed() -> void:
	var water: WaterSystem = _make_water()
	var spy := SuppressionSpy.new()

	assert_false(water.is_suppressing(), "a tank that has not sprayed is not suppressing")

	water.apply_spray_tick(FRAME_DELTA, spy)
	assert_true(water.is_suppressing(), "a tick that lands on a fire is suppressing")
	assert_true(spy.total > 0.0, "and the fire was given a positive amount (%.3f)" % spy.total)

	# A miss: water still leaves the tank, and nothing is being put out.
	var before: float = water.water_remaining
	water.apply_spray_tick(FRAME_DELTA, null)
	assert_false(water.is_suppressing(), "a tick that hits nothing is not suppressing")
	assert_true(
		water.water_remaining < before,
		"but the miss still cost the tank (%.3f to %.3f)" % [before, water.water_remaining]
	)

	# A wall: something was hit, but it is not a fire and cannot absorb anything.
	water.apply_spray_tick(FRAME_DELTA, RefCounted.new())
	assert_false(water.is_suppressing(), "a tick that hits a wall is not suppressing")

	_destroy(water)


func test_hitting_is_false_at_an_empty_tank() -> void:
	var water: WaterSystem = _make_water()
	var spy := SuppressionSpy.new()

	water.apply_spray_tick(FRAME_DELTA, spy)
	assert_true(water.is_suppressing(), "full tank, on target, suppressing")

	water.water_remaining = 0.0
	water.apply_spray_tick(FRAME_DELTA, spy)
	assert_false(water.is_suppressing(), "an empty tank on target is not suppressing")

	var calls_before: int = spy.calls
	water.apply_spray_tick(FRAME_DELTA, spy)
	assert_eq(spy.calls, calls_before, "and the fire is not asked to absorb anything")

	_destroy(water)


## A fire that is already out returns zero from apply_suppression, and the flag
## has to follow the fire's answer rather than the request.
func test_hitting_is_false_against_a_fire_that_is_already_out() -> void:
	var water: WaterSystem = _make_water()
	var fire: FireIncident = FireIncidentScript.new()
	fire.balance = water.balance
	fire.health = 0.0
	fire.max_health = 100.0
	fire.escalation_limit = 120.0
	fire._terminal = true

	water.apply_spray_tick(FRAME_DELTA, fire)
	assert_false(water.is_suppressing(), "spraying a fire that is already out is not suppressing")

	fire.free()
	_destroy(water)


## The timing target itself (Part 4). The rules above are deliberately written
## against whatever GameBalance says; this one pins what GameBalance is meant to
## say, because "a full tank in about three seconds from hookup" is a design
## decision made at a playtest and not something the other tests can see. If it
## is retuned on purpose, this is the assertion to change, on purpose.
func test_a_full_tank_takes_about_three_seconds_from_hookup() -> void:
	var water: WaterSystem = _make_water()
	var balance: Node = water.balance
	water.water_remaining = 0.0

	var expected: float = balance.hydrant_hookup_time + balance.tank_capacity / balance.hydrant_refill_rate
	assert_true(
		expected >= 2.0 and expected <= 4.0,
		"hookup plus a full fill should be about three seconds, calculated %.2f" % expected
	)

	water.begin_hookup()
	var elapsed: float = 0.0
	# A generous ceiling, so a badly wrong value fails on the assertion below
	# rather than by hanging the runner.
	for _tick in range(int(20.0 / FRAME_DELTA)):
		if water.water_remaining >= water.tank_capacity:
			break
		water._update_refill(FRAME_DELTA)
		elapsed += FRAME_DELTA

	assert_true(
		water.water_remaining >= water.tank_capacity,
		"the tank does fill (%.1f of %.1f)" % [water.water_remaining, water.tank_capacity]
	)
	assert_almost_eq(
		elapsed, expected, 0.05,
		"an empty tank fills in the time the balance values say it should"
	)
	_destroy(water)


## Range is measured to the truck's bodywork, not to its centre (Part 1 of this
## milestone). The old centre rule made the answer depend on which way the truck
## happened to be pointing: nose in at a kerb, the centre of a 90 long truck is
## 45 further from the hydrant than it is when the same truck is parked
## alongside with its 40 wide flank to the same kerb. A player who pulled up
## square to a hydrant, bumper almost touching it, was told nothing at all.
func test_range_is_measured_to_the_truck_body_not_its_centre() -> void:
	var hydrant: Hydrant = _make_hydrant()

	# A hydrant 50 units off the truck's nose. The nose is 45 from the centre,
	# so the bodywork is 5 away and the centre is 50 away.
	hydrant.position = Vector2(50.0, 0.0)
	var facing_it: Transform2D = Transform2D(0.0, Vector2.ZERO)
	assert_almost_eq(
		hydrant.distance_to_truck(facing_it, TRUCK_HALF), 5.0, 0.001,
		"a hydrant 50 from the centre, nose on, is 5 from the bumper"
	)

	# The same hydrant with the truck turned side on: now 30 from the flank.
	var side_on: Transform2D = Transform2D(PI / 2.0, Vector2.ZERO)
	assert_almost_eq(
		hydrant.distance_to_truck(side_on, TRUCK_HALF), 30.0, 0.001,
		"and 30 from the flank when the truck is turned side on"
	)

	# Parked on top of it: zero, not "somewhere inside, distance unclear".
	hydrant.position = Vector2(10.0, 5.0)
	assert_eq(
		hydrant.distance_to_truck(facing_it, TRUCK_HALF), 0.0,
		"a hydrant under the truck is zero away"
	)

	_destroy(hydrant)


## The three approaches James asked about, at the distances measured against the
## real map in this milestone's measurement pass. All three must hook up.
func test_every_sensible_way_of_parking_at_a_hydrant_is_in_range() -> void:
	var hydrant: Hydrant = _make_hydrant()
	var radius: float = hydrant.balance.hydrant_interaction_radius

	# Measured on the map: a hydrant on the kerb face, the truck stopped hard
	# against that kerb, is 0 to 1 units from the bodywork parked alongside and
	# 0 nose in. A 45 degree sprawl is about 30. Stopping a truck length short
	# along the kerb is 46, and overshooting by 160 units of street is 115.
	var approaches: Dictionary = {
		"alongside, against the kerb": Vector2(0.0, 21.0),
		"nose in, square to the kerb": Vector2(46.0, 0.0),
		"a sloppy 45 degrees": Vector2(40.0, 40.0),
		"a truck length short along the kerb": Vector2(21.0, 91.0),
		"160 units of street past it": Vector2(21.0, 161.0),
	}
	for label in approaches:
		hydrant.position = approaches[label]
		var parked := Transform2D(PI / 2.0, Vector2.ZERO)
		var distance: float = hydrant.distance_to_truck(parked, TRUCK_HALF)
		assert_true(
			hydrant.is_truck_in_range(parked, TRUCK_HALF),
			"%s (%.1f from the bodywork, radius %.1f) must be in range"
				% [label, distance, radius]
		)

	# The far lane of a 280 unit road stays out, which is the one thing the rule
	# should still ask for: pull over to the hydrant's side of the street.
	hydrant.position = Vector2(0.0, 220.0)
	var far_lane := Transform2D(PI / 2.0, Vector2.ZERO)
	assert_false(
		hydrant.is_truck_in_range(far_lane, TRUCK_HALF),
		"the far side of the street (%.1f from the bodywork) stays out of range"
			% hydrant.distance_to_truck(far_lane, TRUCK_HALF)
	)

	_destroy(hydrant)


## Rolling to a halt with E already held used to flicker between "Slow down to
## hook up" and "Hold E to hook up" over the last stretch of the stop, because
## the threshold was a near dead stop. A slow creep now counts.
func test_a_slow_creep_counts_as_stopped_enough_to_hook_up() -> void:
	var hydrant: Hydrant = _make_hydrant()
	var balance: Node = hydrant.balance
	var at_hydrant := Transform2D(0.0, Vector2.ZERO)

	assert_true(
		balance.hydrant_max_hookup_speed >= 20.0 and balance.hydrant_max_hookup_speed <= 30.0,
		"the creep allowance should be around 20 to 30 units/s, is %.1f"
			% balance.hydrant_max_hookup_speed
	)

	var creeping: Dictionary = hydrant.evaluate(
		at_hydrant, TRUCK_HALF, 18.0, true, false, false, 0.0
	)
	assert_eq(
		creeping["prompt"], Hydrant.Prompt.HOOKING_UP,
		"creeping at 18 units/s with E held starts the hookup"
	)
	assert_true(creeping["should_refill"], "and asks for the refill")

	# Still a rule, not an abolition: driving past does not hook up.
	var driving: Dictionary = hydrant.evaluate(
		at_hydrant, TRUCK_HALF, 120.0, true, false, false, 0.0
	)
	assert_eq(
		driving["prompt"], Hydrant.Prompt.TOO_FAST, "driving past is still refused, in words"
	)
	assert_false(driving["should_refill"], "and does not refill")

	_destroy(hydrant)


## The hose is drawn to the same point the range rule measures to, so the line
## the player sees is the distance the rule used.
func test_the_hose_runs_to_the_nearest_point_of_the_truck() -> void:
	var hydrant: Hydrant = _make_hydrant()

	hydrant.position = Vector2(0.0, 60.0)
	var truck := Transform2D(0.0, Vector2.ZERO)
	var point: Vector2 = hydrant.nearest_point_on_truck(truck, TRUCK_HALF)
	assert_almost_eq(point.x, 0.0, 0.001, "the hose meets the truck's flank, not its centre")
	assert_almost_eq(point.y, 20.0, 0.001, "at the near side of a 40 wide body")
	assert_almost_eq(
		point.distance_to(hydrant.position),
		hydrant.distance_to_truck(truck, TRUCK_HALF),
		0.001,
		"and its length is exactly the distance the range rule measures"
	)

	_destroy(hydrant)
