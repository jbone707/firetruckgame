extends "res://tests/test_case.gd"
## The automatic turret: what it will and will not spray at (Milestone 10 Part 4).
##
## The rules that can be asked as arithmetic are asked here. Whether a wall
## actually blocks the ray is a physics question and lives in
## tests/run_physics_tests.gd, which boots the real scene.

const WaterSystemScript: GDScript = preload("res://scripts/WaterSystem.gd")


## A WaterSystem with a balance and a tank, outside any tree. It never runs a
## frame here; every method under test is free of the scene.
func _water() -> WaterSystem:
	var water: WaterSystem = WaterSystemScript.new()
	water.balance = load("res://scripts/GameBalance.gd").new()
	water.tank_capacity = water.balance.tank_capacity
	water.water_remaining = water.tank_capacity
	return water


func _free(water: WaterSystem) -> void:
	water.balance.free()
	water.balance = null
	water.free()


## A stand-in for a fire: a Node2D that answers the two questions the turret and
## the tank ask of a target, and records what it was given.
class FakeFire extends Node2D:
	var absorbed: float = 0.0
	var terminal: bool = false

	func is_terminal() -> bool:
		return terminal

	func apply_suppression(amount: float) -> float:
		if terminal:
			return 0.0
		absorbed += amount
		return amount


func test_the_turret_takes_a_target_and_refuses_a_dead_one() -> void:
	var water: WaterSystem = _water()
	var fire := FakeFire.new()

	water.set_target(fire)
	assert_eq(water.get_target(), fire, "a live fire is accepted as the target")

	fire.terminal = true
	water.set_target(fire)
	assert_eq(water.get_target(), null, "a fire that is out is not a target at all")

	water.set_target(null)
	assert_eq(water.get_target(), null, "and nothing is nothing")

	fire.free()
	_free(water)


## Out of reach is not a target. The rule is measured from the NOZZLE, which is
## where the water leaves from, and against stream_range, which is one road
## width.
func test_a_fire_out_of_reach_is_not_in_range() -> void:
	var water: WaterSystem = _water()
	var fire := FakeFire.new()
	water.set_target(fire)

	fire.position = Vector2(water.balance.stream_range - 20.0, 0.0)
	assert_true(water.target_in_range(), "a fire just inside the stream range is in range")

	fire.position = Vector2(water.balance.stream_range + 20.0, 0.0)
	assert_false(water.target_in_range(), "and one just outside it is not")

	water.set_target(null)
	assert_false(water.target_in_range(), "with no target there is nothing in range")

	fire.free()
	_free(water)


## The tank is spent by spraying and by nothing else, and a spray with no target
## puts nothing anywhere.
##
## apply_spray_tick is the only path that takes water out of the tank, and the
## frame loop calls it only once the ray has come back holding the target. This
## checks the half of that pair that is arithmetic: the tick itself.
func test_water_goes_only_where_the_stream_lands() -> void:
	var water: WaterSystem = _water()
	var fire := FakeFire.new()

	var before: float = water.water_remaining
	var used: float = water.apply_spray_tick(1.0, fire)
	assert_almost_eq(
		used, water.balance.spray_flow_rate, 0.001,
		"a second of spraying costs a second's flow"
	)
	assert_almost_eq(
		water.water_remaining, before - water.balance.spray_flow_rate, 0.001,
		"and the tank is down by exactly that"
	)
	assert_almost_eq(
		fire.absorbed, water.balance.spray_flow_rate * water.balance.suppression_per_water_unit,
		0.001, "and the fire took all of it"
	)
	assert_true(water.is_suppressing(), "and the system says it is knocking it down")

	# A fire that is out absorbs nothing, so the tick is not suppression even
	# though the water left the tank. This is the flag the HUD line and the steam
	# both hang off.
	fire.terminal = true
	water.apply_spray_tick(1.0, fire)
	assert_false(water.is_suppressing(), "a fire that is out is not being knocked down")

	fire.free()
	_free(water)


## The swing is bounded, and it goes the short way round.
func test_the_turret_swings_at_a_bounded_rate_the_short_way() -> void:
	var most: float = 0.4

	# Exactly half a turn is the one angle with no short way round: wrapf puts
	# it on the negative boundary and either direction is equally right, so the
	# check is on the SIZE of the step and not on its sign.
	var moved: float = WaterSystemScript._rotate_towards(0.0, PI, most)
	assert_almost_eq(absf(moved), most, 0.001, "half a turn away is capped at the rate")

	moved = WaterSystemScript._rotate_towards(0.0, PI * 0.75, most)
	assert_almost_eq(moved, most, 0.001, "and three eighths of a turn goes the positive way")

	moved = WaterSystemScript._rotate_towards(0.0, 0.1, most)
	assert_almost_eq(moved, 0.1, 0.001, "and a small correction is made in one step")

	# The short way round: from just under a full turn to just over zero is a
	# small POSITIVE step, not a long negative one.
	moved = WaterSystemScript._rotate_towards(-PI + 0.05, PI - 0.05, most)
	assert_true(
		moved < -PI + 0.05,
		"the turret goes the short way round the wrap (%.3f from %.3f)"
			% [moved, -PI + 0.05]
	)

	var rate: Node = load("res://scripts/GameBalance.gd").new()
	assert_true(
		rate.turret_rotation_rate > 0.0 and rate.turret_rotation_rate < 12.0,
		"the shipped rate is a swing and not a snap (%.2f rad/s)" % rate.turret_rotation_rate
	)
	rate.free()
