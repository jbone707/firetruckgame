extends "res://tests/test_case.gd"
## The lane model (Milestone 9 Part 1).
##
## Three questions, asked of both shipped maps because they are shaped
## differently and every earlier geometry bug lived in that difference: Elm Grove
## is an axis-aligned grid whose roads cross in mid-span, Windsor is surveyed
## ways that bend and meet at their shared endpoints.
##
##  - Is every lane on the road? A lane a car cannot legally be on is a lane
##    that will drive traffic through somebody's garden.
##  - Does every turn join two lanes that really exist, and really meet at the
##    junction it says it is at?
##  - Can a car get from any lane to any other? A lane network with a one-way
##    trap in it parks a car forever, and no amount of looking at it finds that.

const WINDSOR: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE: String = "res://resources/neighbourhood.tres"

## How many points along each lane are tested for being on the road. The lane is
## straight, so its ends and a few points between them are the whole of it.
const LANE_SAMPLES: int = 6


func _lane_graph(map_path: String) -> LaneGraph:
	var definition: MapDefinition = load(map_path)
	return LaneGraph.build(RoadGraph.build(definition), definition)


## Every road slab and junction fill MapBuilder draws, which together are the
## asphalt. Taken from MapGeometry rather than rebuilt here, so this asks about
## the road the player drives on and not about a second idea of one.
func _road_region(map_path: String) -> Array[PackedVector2Array]:
	var definition: MapDefinition = load(map_path)
	return MapGeometry.road_slabs(RoadGraph.build(definition))


func _on_the_road(point: Vector2, region: Array[PackedVector2Array]) -> bool:
	for piece in region:
		if Geometry2D.is_point_in_polygon(point, piece):
			return true
	return false


func test_every_lane_lies_on_the_asphalt() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var region: Array[PackedVector2Array] = _road_region(map_path)
		var definition: MapDefinition = load(map_path)

		var strays: int = 0
		var worst: String = ""
		for lane in lanes.lanes:
			var entry: Vector2 = lane["entry"]
			var exit: Vector2 = lane["exit"]
			for step in range(LANE_SAMPLES):
				var t: float = float(step) / float(LANE_SAMPLES - 1)
				var point: Vector2 = entry.lerp(exit, t)
				if not _on_the_road(point, region):
					strays += 1
					worst = "lane %d on road %s at %s" % [
						int(lane["id"]), String(lane["name"]), point
					]
		assert_eq(
			strays, 0,
			"%s: every lane is on the asphalt (%d points off it, e.g. %s)" % [
				definition.map_id, strays, worst
			]
		)


## The turn curves too. A turn crosses the junction, so what it has to stay
## inside is the junction fill and the two road slabs it joins, which is the
## same road region: MapGeometry.road_slabs includes the fills.
func test_every_turn_curve_stays_on_the_asphalt() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var region: Array[PackedVector2Array] = _road_region(map_path)
		var definition: MapDefinition = load(map_path)

		var strays: int = 0
		var worst: String = ""
		for turn in lanes.turns:
			for point in turn["points"]:
				if not _on_the_road(point, region):
					strays += 1
					worst = "turn %d at node %d, %s" % [
						int(turn["id"]), int(turn["node"]), point
					]
		assert_eq(
			strays, 0,
			"%s: every turn curve is on the asphalt (%d points off it, e.g. %s)" % [
				definition.map_id, strays, worst
			]
		)


## Every turn joins a real incoming lane to a real outgoing lane, at the
## junction it claims: the lane it comes from arrives at that node, the lane it
## goes to leaves it, and the curve starts and ends exactly on those two lanes
## rather than near them.
func test_every_turn_joins_two_real_lanes_at_the_junction_it_names() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var definition: MapDefinition = load(map_path)

		var bad_lane_id: int = 0
		var wrong_node: int = 0
		var detached: int = 0
		var uturns_away_from_a_dead_end: int = 0
		var graph: RoadGraph = lanes.get_road_graph()

		for turn in lanes.turns:
			var from_id: int = int(turn["from_lane"])
			var to_id: int = int(turn["to_lane"])
			if from_id < 0 or from_id >= lanes.lanes.size() \
					or to_id < 0 or to_id >= lanes.lanes.size():
				bad_lane_id += 1
				continue
			var incoming: Dictionary = lanes.lanes[from_id]
			var outgoing: Dictionary = lanes.lanes[to_id]
			var node: int = int(turn["node"])

			if int(incoming["to_node"]) != node or int(outgoing["from_node"]) != node:
				wrong_node += 1

			var points: PackedVector2Array = turn["points"]
			if points.size() < 2 \
					or points[0].distance_to(incoming["exit"]) > 0.001 \
					or points[points.size() - 1].distance_to(outgoing["entry"]) > 0.001:
				detached += 1

			# A U-turn is only legal where there is nowhere else to go.
			if int(turn["kind"]) == LaneGraph.Turn.U_TURN:
				if graph.incident_edges.get(node, []).size() > 1:
					uturns_away_from_a_dead_end += 1

		assert_eq(bad_lane_id, 0, "%s: every turn names lanes that exist" % definition.map_id)
		assert_eq(
			wrong_node, 0,
			"%s: every turn joins a lane arriving at its node to one leaving it (%d wrong)"
				% [definition.map_id, wrong_node]
		)
		assert_eq(
			detached, 0,
			"%s: every turn curve starts on its lane's end and finishes on the next lane's"
				% definition.map_id
				+ " start (%d detached)" % detached
		)
		assert_eq(
			uturns_away_from_a_dead_end, 0,
			"%s: the only U-turns are at dead ends (%d elsewhere)" % [
				definition.map_id, uturns_away_from_a_dead_end
			]
		)


## Every road segment carries exactly two lanes, one each way, and they are on
## opposite sides of the centreline. Right-hand traffic: driving from a to b the
## lane is on the right of that heading.
func test_each_segment_carries_one_lane_each_way_on_opposite_sides() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var graph: RoadGraph = lanes.get_road_graph()
		var definition: MapDefinition = load(map_path)

		assert_eq(
			lanes.lanes.size(), graph.edges.size() * 2,
			"%s: two lanes per road segment (%d lanes, %d segments)" % [
				definition.map_id, lanes.lanes.size(), graph.edges.size()
			]
		)

		var wrong_side: int = 0
		var wrong_offset: int = 0
		for lane in lanes.lanes:
			var from_at: Vector2 = graph.positions[int(lane["from_node"])]
			var to_at: Vector2 = graph.positions[int(lane["to_node"])]
			var heading: Vector2 = (to_at - from_at).normalized()
			var centre: Vector2 = (Vector2(lane["entry"]) + Vector2(lane["exit"])) / 2.0
			# Where that midpoint sits relative to the centreline it belongs to.
			var along: Vector2 = from_at + heading * (centre - from_at).dot(heading)
			var sideways: Vector2 = centre - along
			if sideways.dot(LaneGraph.right_of(heading)) <= 0.0:
				wrong_side += 1
			if absf(sideways.length() - float(lane["width"]) / 4.0) > 0.001:
				wrong_offset += 1

		assert_eq(
			wrong_side, 0,
			"%s: every lane is on the right of its own direction of travel (%d are not)"
				% [definition.map_id, wrong_side]
		)
		assert_eq(
			wrong_offset, 0,
			"%s: and a quarter of the road's width off the centreline (%d are not)"
				% [definition.map_id, wrong_offset]
		)


## A car put down anywhere can reach everywhere, and can be reached from
## everywhere. Checked in both directions from one lane, which is the standard
## two-pass strong-connectivity test.
func test_the_lane_network_is_strongly_connected_on_both_maps() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var lanes: LaneGraph = _lane_graph(map_path)
		var definition: MapDefinition = load(map_path)

		var forward: int = lanes.lanes_reachable_from(0).size()
		var backward: int = lanes.lanes_that_reach(0).size()
		assert_eq(
			forward, lanes.lanes.size(),
			"%s: every lane is reachable from lane 0 (%d of %d)" % [
				definition.map_id, forward, lanes.lanes.size()
			]
		)
		assert_eq(
			backward, lanes.lanes.size(),
			"%s: and lane 0 is reachable from every lane (%d of %d)" % [
				definition.map_id, backward, lanes.lanes.size()
			]
		)
		assert_true(
			lanes.is_strongly_connected(),
			"%s: so the lane network is strongly connected" % definition.map_id
		)

		# Every lane has somewhere to go. A lane with no turn off it is a cul de
		# sac the strong-connectivity test above would also catch, but this names
		# the lane rather than the network.
		var dead: int = 0
		for lane in lanes.lanes:
			if lanes.turns_from_lane.get(int(lane["id"]), []).is_empty():
				dead += 1
		assert_eq(dead, 0, "%s: and every lane has a way off it" % definition.map_id)


## Which junctions got what, per map. These are the numbers the milestone record
## quotes, so they are asserted rather than only printed: a change to the rule
## has to come here and be made on purpose.
func test_the_junction_control_rule_gives_the_counts_it_is_meant_to() -> void:
	var windsor: LaneGraph = _lane_graph(WINDSOR)
	var windsor_counts: Dictionary = windsor.control_counts()
	assert_eq(int(windsor_counts["signal"]), 6, "Windsor gets six signalled junctions")
	assert_eq(int(windsor_counts["stop"]), 14, "and fourteen with stop signs")

	var elm_grove: LaneGraph = _lane_graph(ELM_GROVE)
	var elm_counts: Dictionary = elm_grove.control_counts()
	assert_eq(int(elm_counts["signal"]), 16, "Elm Grove's whole grid is signalled")
	assert_eq(int(elm_counts["stop"]), 0, "and nothing on it carries a stop sign")

	# The rule itself, not just its totals: a signal is a four-arm junction or a
	# tertiary-or-above one, and nothing else is.
	for graph in [windsor, elm_grove]:
		for node in graph.junctions:
			var junction: Dictionary = graph.junctions[node]
			var major: bool = LaneGraph.MAJOR_CLASSES.has(String(junction["widest_class"]))
			var big: bool = int(junction["arm_count"]) >= LaneGraph.SIGNAL_MIN_ARMS
			var signalled: bool = (
				int(junction["control"]) == LaneGraph.JunctionControl.SIGNAL
			)
			assert_eq(
				signalled, major or big,
				"node %d: signalled exactly when it is four-armed or tertiary and above"
					% int(node)
					+ " (%d arms, widest %s)" % [
						int(junction["arm_count"]), String(junction["widest_class"])
					]
			)

	# Two-arm bends and dead ends are not junctions at all and get no control.
	var road_graph: RoadGraph = windsor.get_road_graph()
	var controlled_bends: int = 0
	for node in range(road_graph.positions.size()):
		if road_graph.incident_edges.get(node, []).size() >= 3:
			continue
		if windsor.get_control(node) != LaneGraph.JunctionControl.NONE:
			controlled_bends += 1
	assert_eq(controlled_bends, 0, "Windsor's bends and dead ends carry no control")


## A stop-sign junction stops its minor arms and only those. On a T of three
## identical residential streets the stem stops and the road going through does
## not, which is how such a junction is really signed and is the case a rule
## that only compared widths would get wrong.
func test_stop_signs_go_on_the_minor_arms_and_the_through_road_keeps_going() -> void:
	var lanes: LaneGraph = _lane_graph(WINDSOR)

	var junctions_with_no_stop: int = 0
	var junctions_stopping_everything: int = 0
	for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.STOP):
		var junction: Dictionary = lanes.junctions[node]
		var stops: Array = junction["stop_arms"]
		if stops.is_empty():
			junctions_with_no_stop += 1
		if stops.size() >= int(junction["arm_count"]):
			junctions_stopping_everything += 1

	assert_eq(
		junctions_with_no_stop, 0,
		"every stop junction on Windsor actually carries a stop sign (%d do not)"
			% junctions_with_no_stop
	)
	assert_eq(
		junctions_stopping_everything, 0,
		"and none of them stops every arm, so a road goes through (%d do)"
			% junctions_stopping_everything
	)

	# And a signalled junction carries no stop signs at all: one junction, one
	# kind of control.
	var signals_with_stops: int = 0
	for node in lanes.junction_nodes_with(LaneGraph.JunctionControl.SIGNAL):
		if not lanes.junctions[node]["stop_arms"].is_empty():
			signals_with_stops += 1
	assert_eq(signals_with_stops, 0, "and a signalled junction carries no stop signs")
