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


func _make_water() -> WaterSystem:
	var balance: Node = GameBalanceScript.new()
	var water: WaterSystem = WaterSystemScript.new()
	water.balance = balance
	water.tank_capacity = balance.tank_capacity
	water.water_remaining = balance.tank_capacity
	return water


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

	var at_hydrant: Vector2 = Vector2.ZERO
	var far_away: Vector2 = Vector2(balance.hydrant_interaction_radius * 3.0, 0.0)
	var too_fast: float = balance.hydrant_max_hookup_speed + 25.0
	var slow: float = balance.hydrant_max_hookup_speed - 1.0

	var out_of_range: Dictionary = hydrant.evaluate(far_away, slow, true, false, false, 0.0)
	assert_eq(out_of_range["prompt"], Hydrant.Prompt.NONE, "no prompt out of range")
	assert_false(out_of_range["should_refill"], "no refill out of range")

	var moving: Dictionary = hydrant.evaluate(at_hydrant, too_fast, true, false, false, 0.0)
	assert_eq(moving["prompt"], Hydrant.Prompt.TOO_FAST, "a moving truck is told to slow down")
	assert_false(moving["should_refill"], "a moving truck does not refill")

	var not_holding: Dictionary = hydrant.evaluate(at_hydrant, slow, false, false, false, 0.0)
	assert_eq(not_holding["prompt"], Hydrant.Prompt.HOLD_TO_HOOK_UP, "stopped, told to hold E")
	assert_false(not_holding["should_refill"], "releasing E does not refill")

	var hooking: Dictionary = hydrant.evaluate(at_hydrant, slow, true, false, false, 0.4)
	assert_eq(hooking["prompt"], Hydrant.Prompt.HOOKING_UP, "holding E starts the hookup")
	assert_true(hooking["should_refill"], "holding E requests the refill")

	var full: Dictionary = hydrant.evaluate(at_hydrant, slow, true, true, true, 1.0)
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
