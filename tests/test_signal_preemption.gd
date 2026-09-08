extends "res://tests/test_case.gd"
## Signal preemption: what the siren does to a junction, and what it must never
## do (Milestone 10 Part 2).
##
## Driven as arithmetic, like the cycle it modifies. TrafficSignals.advance()
## exists so the clock, the approach scan and the sequences can all be stepped
## without a scene tree, and every check here steps it at a physics frame so
## nothing can hide between samples.

const TrafficSignalsScript: GDScript = preload("res://scripts/TrafficSignals.gd")

const WINDSOR: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE: String = "res://resources/neighbourhood.tres"

const FRAME: float = 1.0 / 60.0


func _lane_graph(map_path: String) -> LaneGraph:
	var definition: MapDefinition = load(map_path)
	return LaneGraph.build(RoadGraph.build(definition), definition)


func _signals(map_path: String) -> TrafficSignals:
	var signals: TrafficSignals = TrafficSignalsScript.new()
	signals.balance = load("res://scripts/GameBalance.gd").new()
	signals.configure(_lane_graph(map_path))
	return signals


func _free(signals: TrafficSignals) -> void:
	signals.balance.free()
	signals.balance = null
	signals.free()


## A signalled junction, the arm the engine comes in on, and a point on that arm
## the given distance back from the junction along its own centreline.
##
## Returns {node, edge_index, position, heading} or an empty Dictionary when the
## map has no signalled junction with an arm that long, which is a fact about
## the map rather than a failure and is asserted on by the caller.
func _approach_to_a_signal(lanes: LaneGraph, back: float) -> Dictionary:
	var graph: RoadGraph = lanes.get_road_graph()
	for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
		var junction: Dictionary = lanes.junctions[node]
		for arm in junction["arms"]:
			var edge: Dictionary = graph.edges[int(arm["edge_index"])]
			if float(edge["length"]) < back:
				continue
			var heading: Vector2 = Vector2(arm["heading"])
			return {
				"node": int(node),
				"edge_index": int(arm["edge_index"]),
				# The arm's heading points away from the junction, so this is a
				# point back down it, and the engine faces the other way.
				"position": Vector2(junction["position"]) + heading * back,
				"heading": -heading,
			}
	return {}


## The engine has to be inside range AND sounding, and the two are separate
## conditions. Same position, same heading, twice.
func test_preemption_needs_the_siren_and_the_range_together() -> void:
	var lanes: LaneGraph = _lane_graph(WINDSOR)
	var signals: TrafficSignals = _signals(WINDSOR)
	var balance: Node = signals.balance

	var approach: Dictionary = _approach_to_a_signal(lanes, 400.0)
	assert_true(
		not approach.is_empty(),
		"Windsor has a signalled junction with an arm at least 400 units long"
	)
	if approach.is_empty():
		_free(signals)
		return
	var node: int = int(approach["node"])

	# Siren off, right on top of the junction: nothing.
	signals.set_engine_state(approach["position"], approach["heading"], false)
	for _frame in range(30):
		signals.advance(FRAME)
	assert_true(
		signals.approaching_junctions().is_empty(),
		"with the siren off no junction is being approached at all"
	)
	assert_eq(
		signals.preempt_state_of(node), TrafficSignals.Preempt.NONE,
		"and the junction 400 units ahead is running its ordinary cycle"
	)

	# Siren on, far outside the range: still nothing. Placed along the same arm,
	# well past the reach, so only the distance has changed.
	var far: Vector2 = (
		Vector2(lanes.junctions[node]["position"])
		- Vector2(approach["heading"]) * (balance.signal_preempt_distance * 3.0)
	)
	signals.set_engine_state(far, approach["heading"], true)
	for _frame in range(30):
		signals.advance(FRAME)
	assert_false(
		signals.approaching_junctions().has(node),
		"with the siren on but %.0f units out, the junction is not approached"
			% (balance.signal_preempt_distance * 3.0)
	)

	# Siren on, inside the range: the sequence starts.
	signals.set_engine_state(approach["position"], approach["heading"], true)
	for _frame in range(30):
		signals.advance(FRAME)
	assert_true(
		signals.approaching_junctions().has(node),
		"with the siren on and 400 units out, the junction is being approached"
	)
	assert_eq(
		signals.preempt_approach_arm(node), int(approach["edge_index"]),
		"down the arm the engine is actually on"
	)
	assert_true(
		signals.preempt_state_of(node) != TrafficSignals.Preempt.NONE,
		"and the junction has left its ordinary cycle"
	)

	_free(signals)


## THE ONE RULE. Stepped a frame at a time through a whole preemption, on both
## maps, from every arm of every signalled junction that is long enough to stand
## on: at no sample may the engine's arm be green while any other arm is showing
## anything but red.
##
## This is the check the removal proof is aimed at. Deleting the cross-arm-red
## precondition from light_for_junction_phase, so that GREEN and HOLD leave the
## other phases on the ordinary cycle, fails it on both maps.
func test_the_approach_arm_never_goes_green_before_the_cross_arms_are_red() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var definition: MapDefinition = load(map_path)
		var graph: RoadGraph = lanes.get_road_graph()

		var checked: int = 0
		var violations: int = 0
		var worst: String = "none"

		for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
			var junction: Dictionary = lanes.junctions[node]
			# The arm's own phase partner is the road going the other way on the
			# same street, and it is green when the engine's arm is green,
			# during a preemption exactly as during the ordinary cycle. The rule
			# is about the CROSS arms: everything on the other phase.
			var phases: Array[int] = TrafficSignals.phase_of_each_arm(junction["arms"])
			for index in range(junction["arms"].size()):
				var arm: Dictionary = junction["arms"][index]
				var edge: Dictionary = graph.edges[int(arm["edge_index"])]
				if float(edge["length"]) < 260.0:
					continue
				var signals: TrafficSignals = _signals(map_path)
				# Start the junction at a different point in its cycle for each
				# arm, so the sequence is not always entered from the same place.
				signals.clock = fmod(float(checked) * 3.7, signals.cycle_length())
				var heading: Vector2 = -Vector2(arm["heading"])
				var stand: Vector2 = (
					Vector2(junction["position"]) - heading * 250.0
				)
				signals.set_engine_state(stand, heading, true)
				checked += 1

				# Twelve seconds: long enough for the amber, the all red, the
				# green, and a good stretch of holding it.
				for _frame in range(12 * 60):
					signals.advance(FRAME)
					var mine: int = signals.light_for_arm(int(node), int(arm["edge_index"]))
					if mine != TrafficSignals.Light.GREEN:
						continue
					if signals.preempt_state_of(int(node)) == TrafficSignals.Preempt.NONE:
						# The ordinary cycle, which its own tests already cover.
						continue
					for other_index in range(junction["arms"].size()):
						if phases[other_index] == phases[index]:
							continue
						var other: Dictionary = junction["arms"][other_index]
						var theirs: int = signals.light_for_arm(
							int(node), int(other["edge_index"])
						)
						if theirs != TrafficSignals.Light.RED:
							violations += 1
							worst = "node %d arm %d green while arm %d showed %d" % [
								int(node), int(arm["edge_index"]),
								int(other["edge_index"]), theirs
							]
				_free(signals)

		assert_true(checked > 0, "%s has arms long enough to approach on" % definition.map_id)
		assert_eq(
			violations, 0,
			"%s: no preempted green with a cross arm still moving (%d approach(es), %s)" % [
				definition.map_id, checked, worst
			]
		)


## The sequence in order, with a stopwatch on it: red on the approach while the
## cross arms clear, then every arm red, then the green. The whole delay is
## signal_amber_time plus signal_all_red_time and the check reads it off the
## junction rather than off the constants added together.
func test_the_sequence_runs_amber_then_all_red_then_green() -> void:
	var lanes: LaneGraph = _lane_graph(ELM_GROVE)
	var signals: TrafficSignals = _signals(ELM_GROVE)
	var balance: Node = signals.balance

	var approach: Dictionary = _approach_to_a_signal(lanes, 300.0)
	assert_true(not approach.is_empty(), "Elm Grove has an arm at least 300 units long")
	if approach.is_empty():
		_free(signals)
		return
	var node: int = int(approach["node"])
	var edge_index: int = int(approach["edge_index"])

	# Started on a clock where the approach arm is NOT already green, so the
	# sequence runs in full. Phase 0's green begins at 0, so half a leg into
	# phase 1's green is a moment where the cross road is moving and the
	# engine's is not, whichever phase the engine's arm turns out to be.
	signals.clock = balance.signal_green_time + balance.signal_amber_time \
		+ balance.signal_all_red_time + balance.signal_green_time * 0.5
	if signals.light_for_arm(node, edge_index) == TrafficSignals.Light.GREEN:
		signals.clock = balance.signal_green_time * 0.5

	signals.set_engine_state(approach["position"], approach["heading"], true)

	var saw_clearing: bool = false
	var saw_all_red: bool = false
	var green_at: float = -1.0
	var started_at: float = -1.0
	var elapsed: float = 0.0
	for _frame in range(15 * 60):
		signals.advance(FRAME)
		elapsed += FRAME
		var state: int = signals.preempt_state_of(node)
		if state != TrafficSignals.Preempt.NONE and started_at < 0.0:
			started_at = elapsed
		if state == TrafficSignals.Preempt.CLEARING:
			saw_clearing = true
			assert_eq(
				signals.light_for_arm(node, edge_index), TrafficSignals.Light.RED,
				"the engine's own arm is red while the cross arms clear"
			)
		if state == TrafficSignals.Preempt.ALL_RED:
			saw_all_red = true
		if state == TrafficSignals.Preempt.GREEN and green_at < 0.0:
			green_at = elapsed

	assert_true(saw_clearing, "the cross arms are given their amber")
	assert_true(saw_all_red, "and then every arm is red before anything moves")
	assert_true(green_at > 0.0, "and then the engine's arm goes green")

	var delay: float = green_at - started_at
	var expected: float = balance.signal_amber_time + balance.signal_all_red_time
	assert_almost_eq(
		delay, expected, 4.0 * FRAME,
		"the whole delay is the amber plus the all red (%.2f s, expected %.2f)"
			% [delay, expected]
	)

	_free(signals)


## The engine drives through and away, and the junction goes back to work.
##
## "Away" is not simulated as a drive here; the engine is simply put on the far
## side of the junction facing away from it, which is what a drive through
## produces and is the state the forward-only scan has to answer correctly. The
## junction must hold its green for signal_preempt_resume_hold and then rejoin
## the cycle at the phase after the engine's, which is a green for the road that
## was stopped.
func test_the_cycle_resumes_after_the_engine_clears_the_junction() -> void:
	var lanes: LaneGraph = _lane_graph(ELM_GROVE)
	var signals: TrafficSignals = _signals(ELM_GROVE)
	var balance: Node = signals.balance

	var approach: Dictionary = _approach_to_a_signal(lanes, 300.0)
	assert_true(not approach.is_empty(), "Elm Grove has an arm at least 300 units long")
	if approach.is_empty():
		_free(signals)
		return
	var node: int = int(approach["node"])
	var edge_index: int = int(approach["edge_index"])
	var heading: Vector2 = Vector2(approach["heading"])

	signals.set_engine_state(approach["position"], heading, true)
	for _frame in range(8 * 60):
		signals.advance(FRAME)
	assert_eq(
		signals.preempt_state_of(node), TrafficSignals.Preempt.GREEN,
		"eight seconds of approach leaves the junction holding the engine's green"
	)
	var approach_phase: int = signals.light_for_arm(node, edge_index)
	assert_eq(approach_phase, TrafficSignals.Light.GREEN, "and that arm is green")

	# Through, and away: past the junction on the same heading, far enough that
	# the arm behind is no longer the arm ahead.
	signals.set_engine_state(
		Vector2(lanes.junctions[node]["position"]) + heading * 600.0, heading, true
	)
	# One scan interval, so the walk has been redone.
	for _frame in range(12):
		signals.advance(FRAME)
	assert_false(
		signals.approaching_junctions().has(node),
		"the junction behind the engine is no longer being approached"
	)
	assert_eq(
		signals.preempt_state_of(node), TrafficSignals.Preempt.HOLD,
		"so it moves to its hold"
	)
	assert_eq(
		signals.light_for_arm(node, edge_index), TrafficSignals.Light.GREEN,
		"and the green is held rather than snatched back"
	)

	var held: float = 0.0
	while signals.preempt_state_of(node) == TrafficSignals.Preempt.HOLD and held < 10.0:
		signals.advance(FRAME)
		held += FRAME
	assert_almost_eq(
		held, balance.signal_preempt_resume_hold, 0.3,
		"the hold is signal_preempt_resume_hold long (%.2f s)" % held
	)
	assert_eq(
		signals.preempt_state_of(node), TrafficSignals.Preempt.NONE,
		"and then the ordinary cycle has it back"
	)

	# The next phase, which is the road that was stopped, gets the green.
	var cross_is_green: bool = false
	for arm in lanes.junctions[node]["arms"]:
		if int(arm["edge_index"]) == edge_index:
			continue
		if signals.light_for_arm(node, int(arm["edge_index"])) == TrafficSignals.Light.GREEN:
			cross_is_green = true
	assert_true(
		cross_is_green,
		"the cycle resumes from the next phase, so the cross road moves first"
	)
	assert_eq(
		signals.light_for_arm(node, edge_index), TrafficSignals.Light.RED,
		"and the arm that had the preemption is red again"
	)

	_free(signals)


## A junction the engine never goes near is untouched, and keeps the map-wide
## clock it shares with every other junction. Preemption is one junction's
## business, not the map's.
func test_a_junction_the_engine_never_approaches_keeps_the_map_clock() -> void:
	var lanes: LaneGraph = _lane_graph(ELM_GROVE)
	var signals: TrafficSignals = _signals(ELM_GROVE)

	var approach: Dictionary = _approach_to_a_signal(lanes, 300.0)
	if approach.is_empty():
		_free(signals)
		return
	var node: int = int(approach["node"])

	signals.set_engine_state(approach["position"], approach["heading"], true)
	for _frame in range(10 * 60):
		signals.advance(FRAME)

	var far_nodes: Array[int] = []
	for other in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
		if int(other) == node:
			continue
		if signals.approaching_junctions().has(int(other)):
			continue
		far_nodes.append(int(other))
	assert_true(far_nodes.size() > 0, "Elm Grove has signals the engine is nowhere near")

	var off_cycle: int = 0
	for other in far_nodes:
		if signals.preempt_state_of(other) != TrafficSignals.Preempt.NONE:
			off_cycle += 1
	assert_eq(
		off_cycle, 0,
		"%d untouched junction(s), none of them preempted" % far_nodes.size()
	)

	_free(signals)
