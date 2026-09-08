extends "res://tests/test_case.gd"
## The signal cycle and the phase each arm belongs to (Milestone 9 Part 2).
##
## The cycle is arithmetic, so it is checked as arithmetic: a signal that is
## green both ways for a single frame is a defect nobody will ever see by
## looking, and it is the one defect a junction must not have.

const TrafficSignalsScript: GDScript = preload("res://scripts/TrafficSignals.gd")

const WINDSOR: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE: String = "res://resources/neighbourhood.tres"

## How finely the cycle is walked. A tenth of a second is finer than a physics
## frame at 60Hz is long, so nothing can hide between samples.
const STEP: float = 0.05


func _lane_graph(map_path: String) -> LaneGraph:
	var definition: MapDefinition = load(map_path)
	return LaneGraph.build(RoadGraph.build(definition), definition)


func test_the_two_phases_are_never_green_or_amber_at_the_same_time() -> void:
	var balance: Node = load("res://scripts/GameBalance.gd").new()
	var green: float = balance.signal_green_time
	var amber: float = balance.signal_amber_time
	var all_red: float = balance.signal_all_red_time
	var cycle: float = 2.0 * (green + amber + all_red)

	var both_moving: int = 0
	var all_red_samples: int = 0
	var samples: int = 0
	var time: float = 0.0
	while time < cycle * 2.0:
		var a: int = TrafficSignals.light_at(0, time, green, amber, all_red)
		var b: int = TrafficSignals.light_at(1, time, green, amber, all_red)
		var a_moving: bool = a != TrafficSignals.Light.RED
		var b_moving: bool = b != TrafficSignals.Light.RED
		if a_moving and b_moving:
			both_moving += 1
		if not a_moving and not b_moving:
			all_red_samples += 1
		samples += 1
		time += STEP

	assert_eq(
		both_moving, 0,
		"across two whole cycles the two phases are never both showing a light"
			+ " a car may cross on (%d of %d samples)" % [both_moving, samples]
	)
	assert_true(
		all_red_samples > 0,
		"and there is a moment with every arm red between them (%d samples)" % all_red_samples
	)
	balance.free()


func test_each_phase_gets_its_green_and_its_amber_once_per_cycle() -> void:
	var balance: Node = load("res://scripts/GameBalance.gd").new()
	var green: float = balance.signal_green_time
	var amber: float = balance.signal_amber_time
	var all_red: float = balance.signal_all_red_time
	var cycle: float = 2.0 * (green + amber + all_red)

	for phase in [0, 1]:
		var green_time: float = 0.0
		var amber_time: float = 0.0
		var red_time: float = 0.0
		var time: float = 0.0
		while time < cycle:
			match TrafficSignals.light_at(phase, time, green, amber, all_red):
				TrafficSignals.Light.GREEN:
					green_time += STEP
				TrafficSignals.Light.AMBER:
					amber_time += STEP
				_:
					red_time += STEP
			time += STEP

		assert_almost_eq(
			green_time, green, STEP * 2.0,
			"phase %d gets its %.0f seconds of green per cycle (%.2f)" % [
				phase, green, green_time
			]
		)
		assert_almost_eq(
			amber_time, amber, STEP * 2.0,
			"phase %d gets its %.0f seconds of amber (%.2f)" % [phase, amber, amber_time]
		)
		assert_almost_eq(
			red_time, cycle - green - amber, STEP * 2.0,
			"and is red for the rest of it (%.2f)" % red_time
		)

	# The two phases are the same cycle offset by half of it: whatever phase 0
	# is showing now, phase 1 shows half a cycle later.
	var mismatches: int = 0
	var time_two: float = 0.0
	while time_two < cycle:
		if TrafficSignals.light_at(0, time_two, green, amber, all_red) \
				!= TrafficSignals.light_at(1, time_two + cycle / 2.0, green, amber, all_red):
			mismatches += 1
		time_two += STEP
	assert_eq(mismatches, 0, "the two phases are the same cycle, half a cycle apart")

	balance.free()


## Opposing arms share a phase, on every signalled junction on both maps. This
## is the rule the whole junction rests on: two arms of the same road going
## green at different times would stop a car in the middle of the junction.
func test_opposing_arms_share_a_phase_at_every_signalled_junction() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var definition: MapDefinition = load(map_path)

		var checked: int = 0
		var wrong: int = 0
		var worst: String = ""
		for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
			var arms: Array = lanes.junctions[node]["arms"]
			var phases: Array[int] = TrafficSignals.phase_of_each_arm(arms)
			checked += 1

			# Both phases exist: a junction where every arm shared one phase
			# would be a junction that is green all round.
			if not (phases.has(0) and phases.has(1)):
				wrong += 1
				worst = "node %d has only one phase" % int(node)
				continue

			# The two arms on phase 0 are the most opposed pair there is.
			var opposed: float = 2.0
			for i in range(arms.size()):
				for j in range(i + 1, arms.size()):
					var dot: float = (
						Vector2(arms[i]["heading"]).dot(Vector2(arms[j]["heading"]))
					)
					if dot < opposed:
						opposed = dot
			var phase_zero: Array[int] = []
			for index in range(phases.size()):
				if phases[index] == 0:
					phase_zero.append(index)
			if phase_zero.size() != 2:
				wrong += 1
				worst = "node %d puts %d arms on phase 0" % [int(node), phase_zero.size()]
				continue
			var their_dot: float = Vector2(arms[phase_zero[0]]["heading"]).dot(
				Vector2(arms[phase_zero[1]]["heading"])
			)
			if absf(their_dot - opposed) > 0.0001:
				wrong += 1
				worst = "node %d pairs arms at %.3f, most opposed is %.3f" % [
					int(node), their_dot, opposed
				]
			# And the pair really does face away from one another rather than
			# merely being the least bad option on a fan of arms.
			if their_dot > -0.4:
				wrong += 1
				worst = "node %d's through pair only faces %.3f apart" % [int(node), their_dot]

		assert_true(checked > 0, "%s has signalled junctions to check" % definition.map_id)
		assert_eq(
			wrong, 0,
			"%s: every signalled junction pairs its opposing arms (%d of %d wrong, %s)" % [
				definition.map_id, wrong, checked, worst
			]
		)


## What a car is shown, junction by junction: a green or an amber somewhere on a
## signalled junction at every moment, a red on every stop-signed arm, and green
## at anything uncontrolled.
func test_what_an_arm_shows_matches_the_control_at_its_junction() -> void:
	var signals: TrafficSignals = TrafficSignalsScript.new()
	signals.balance = load("res://scripts/GameBalance.gd").new()
	var lanes: LaneGraph = _lane_graph(WINDSOR)
	signals.configure(lanes)

	assert_eq(signals.get_signal_count(), 6, "Windsor builds six signalled junctions")
	assert_eq(signals.get_stop_sign_count(), 14, "and fourteen stop signs")

	# A stop-signed arm always reads red, and the arm going through it never
	# does: a stop sign is not a signal and does not take turns.
	var stop_reads_red: int = 0
	var through_reads_green: int = 0
	var stop_arms: int = 0
	var through_arms: int = 0
	for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.STOP):
		var junction: Dictionary = lanes.junctions[node]
		for arm in junction["arms"]:
			var edge_index: int = int(arm["edge_index"])
			var light: int = signals.light_for_arm(int(node), edge_index)
			if junction["stop_arms"].has(edge_index):
				stop_arms += 1
				if light == TrafficSignals.Light.RED:
					stop_reads_red += 1
			else:
				through_arms += 1
				if light == TrafficSignals.Light.GREEN:
					through_reads_green += 1
	assert_eq(stop_reads_red, stop_arms, "every stop-signed arm reads red (%d)" % stop_arms)
	assert_eq(
		through_reads_green, through_arms,
		"and the road going through reads green (%d)" % through_arms
	)

	# At a signalled junction, some arm is nearly always able to move. The
	# exception is the intergreen, which is deliberate, so the check is not
	# "never all red" but "all red for exactly the two intergreens a cycle has":
	# a first version asked whether any second of the cycle was all red and
	# found the twelve that are supposed to be.
	var expected_all_red: float = signals.balance.signal_all_red_time * 2.0
	# Seeded with the value being looked for, so the first junction measured is
	# always an improvement on it. Seeding with zero made every junction look
	# better than the seed and left worst_all_red at zero whatever they did.
	var worst_all_red: float = expected_all_red
	var worst_node: int = -1
	for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
		var stopped_time: float = 0.0
		var time: float = 0.0
		while time < signals.cycle_length():
			signals.clock = time
			var moving: int = 0
			for arm in lanes.junctions[node]["arms"]:
				if signals.light_for_arm(int(node), int(arm["edge_index"])) \
						!= TrafficSignals.Light.RED:
					moving += 1
			if moving == 0:
				stopped_time += STEP
			time += STEP
		var deviation: float = absf(stopped_time - expected_all_red)
		if worst_node < 0 or deviation > absf(worst_all_red - expected_all_red):
			worst_all_red = stopped_time
			worst_node = int(node)

	assert_almost_eq(
		worst_all_red, expected_all_red, STEP * 4.0,
		"every signalled junction is all red for exactly its two intergreens"
			+ " (%.1f s of a %.0f s cycle, worst node %d)" % [
				worst_all_red, signals.cycle_length(), worst_node
			]
	)

	signals.balance.free()
	signals.balance = null
	signals.free()


func test_a_junction_with_no_control_always_shows_green() -> void:
	var signals: TrafficSignals = TrafficSignalsScript.new()
	signals.balance = load("res://scripts/GameBalance.gd").new()
	signals.configure(_lane_graph(WINDSOR))

	# A node that is not a junction at all: nothing to give way to, so nothing
	# stops a car.
	assert_eq(
		signals.light_for_arm(999999, 0), TrafficSignals.Light.GREEN,
		"an arm at a junction that does not exist is not stopped"
	)

	signals.balance.free()
	signals.balance = null
	signals.free()
