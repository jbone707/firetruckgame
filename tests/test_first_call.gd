extends "res://tests/test_case.gd"
## The first call of a shift is never on the station's doorstep
## (Milestone 6 Part 3).
##
## Every other call in a shift arrives while the player is already out and
## moving, with a confirmation pause before it. The first one arrives the
## instant the shift starts, from a standing start at the station, and on
## Windsor several incident candidates sit within a few hundred route units of
## the spawn: drawing one of those first means the shift opens with a call that
## is over before the radio line has been read.
##
## So the rule is one rule about one call: the FIRST call must be at least
## GameBalance.first_call_min_route route units from the station. It is asked
## here against the real Windsor candidates and the real road graph, because a
## rule about route distance can only be trusted against routes that exist: a
## check written with invented distances would pass whether or not any candidate
## on the shipped map satisfies it.

const WINDSOR_MAP: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE_MAP: String = "res://resources/neighbourhood.tres"

## Repeated with different shuffles, because the rule acts on a shuffled queue
## and a single draw could satisfy it by luck.
const SHUFFLES: int = 60


func _routes(map: MapDefinition) -> Dictionary:
	var graph: RoadGraph = RoadGraph.build(map)
	var station: Vector2 = map.station_spawn_position
	var routes: Dictionary = {}
	for candidate in map.incident_candidates:
		var route: float = graph.route_length(station, Vector2(candidate["position"]))
		routes[String(candidate["id"])] = 0.0 if is_inf(route) else route
	return routes


func _queue(map: MapDefinition, calls: int) -> Array[Dictionary]:
	var queue: Array[Dictionary] = map.incident_candidates.duplicate()
	queue.shuffle()
	while queue.size() < calls:
		queue.append_array(map.incident_candidates)
	queue.resize(calls)
	return queue


func test_the_first_call_of_a_shift_is_a_drive_not_a_hop() -> void:
	var balance = load("res://scripts/GameBalance.gd").new()
	var minimum: float = balance.first_call_min_route

	for path in [WINDSOR_MAP, ELM_GROVE_MAP]:
		var map: MapDefinition = load(path) as MapDefinition
		assert_true(map != null, "%s loads as a MapDefinition" % path)
		if map == null:
			continue

		var routes: Dictionary = _routes(map)
		var farthest: float = 0.0
		for id in routes:
			farthest = maxf(farthest, float(routes[id]))

		# The rule can only ask for what the map can supply. If this fails, the
		# map changed and the number in GameBalance has to be looked at again.
		assert_true(
			farthest >= minimum,
			"%s has a candidate at least %.0f route units out (farthest %.0f)"
				% [map.map_id, minimum, farthest]
		)

		var too_close: Array[String] = []
		for i in range(SHUFFLES):
			var ordered: Array[Dictionary] = DispatchManager.order_first_call(
				_queue(map, balance.calls_per_shift), routes, minimum
			)
			var first: String = String(ordered[0]["id"])
			if float(routes.get(first, 0.0)) < minimum:
				too_close.append("%s at %.0f" % [first, float(routes.get(first, 0.0))])
		assert_eq(
			too_close.size(), 0,
			"%s: %d shuffles all opened at least %.0f units out (close: %s)"
				% [map.map_id, SHUFFLES, minimum, too_close.slice(0, 3)]
		)


## The rule moves one call and changes nothing else. It swaps, so the shift is
## still the same set of calls in the same number: a rule that filtered the
## queue would quietly shorten a shift on a map whose candidates are mostly
## close in.
func test_only_the_first_call_is_moved_and_the_shift_keeps_its_length() -> void:
	var map: MapDefinition = load(WINDSOR_MAP) as MapDefinition
	if map == null:
		return
	var routes: Dictionary = _routes(map)

	for i in range(SHUFFLES):
		var before: Array[Dictionary] = _queue(map, 3)
		var after: Array[Dictionary] = DispatchManager.order_first_call(
			before, routes, 2000.0
		)
		assert_eq(after.size(), before.size(), "the shift keeps its length")

		var ids_before: Array[String] = []
		var ids_after: Array[String] = []
		for candidate in before:
			ids_before.append(String(candidate["id"]))
		for candidate in after:
			ids_after.append(String(candidate["id"]))
		ids_before.sort()
		ids_after.sort()
		assert_eq(ids_after, ids_before, "the same calls, reordered at most")

		# At most one position other than the front differs: the one swapped
		# into it. Everything else stays where the shuffle put it.
		var moved: int = 0
		for index in range(1, before.size()):
			if String(before[index]["id"]) != String(after[index]["id"]):
				moved += 1
		assert_true(moved <= 1, "at most one later call moved (moved %d)" % moved)


## Where nothing on the map is far enough, the farthest candidate is used rather
## than the shift failing to start.
func test_a_map_with_no_distant_candidate_still_starts_its_shift() -> void:
	var queue: Array[Dictionary] = [
		{"id": "near"}, {"id": "middle"}, {"id": "far"},
	]
	var routes: Dictionary = {"near": 100.0, "middle": 400.0, "far": 900.0}
	var ordered: Array[Dictionary] = DispatchManager.order_first_call(
		queue, routes, 2000.0
	)
	assert_eq(ordered.size(), 3, "the shift still has three calls")
	assert_eq(String(ordered[0]["id"]), "far", "the farthest candidate opens the shift")


## Nothing measured, nothing done: a caller that hands in no routes gets the
## queue back exactly as it was rather than a reordering based on zeroes.
func test_no_measurements_means_no_reordering() -> void:
	var queue: Array[Dictionary] = [{"id": "a"}, {"id": "b"}, {"id": "c"}]
	var ordered: Array[Dictionary] = DispatchManager.order_first_call(queue, {}, 2000.0)
	assert_eq(String(ordered[0]["id"]), "a", "the queue is untouched")
	assert_eq(String(ordered[2]["id"]), "c", "right to the back of it")

	# A queue already opening far enough out is left alone too.
	var already_far: Array[Dictionary] = [{"id": "a"}, {"id": "b"}]
	var far_routes: Dictionary = {"a": 3000.0, "b": 5000.0}
	assert_eq(
		String(DispatchManager.order_first_call(already_far, far_routes, 2000.0)[0]["id"]),
		"a", "a queue that already satisfies the rule is not reshuffled"
	)
