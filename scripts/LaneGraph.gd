extends RefCounted
class_name LaneGraph
## The drivable network as LANES, derived from the road network at load.
##
## RoadGraph answers "what is connected to what": it is centrelines, and a
## centreline is where a road is, not where a car drives. This adds the half of
## the model traffic needs. Every road segment carries two directional lanes,
## one each way, offset from the centreline by a quarter of the road's width,
## which is the middle of its half of the carriageway. Right-hand traffic, so a
## car travelling a to b keeps to the right of the centreline.
##
## Junctions are where the lanes actually connect. A lane stops short of the
## junction it runs into and starts again past the one it leaves, and the gap is
## spanned by a TURN: a short curve from one lane's end to another's start.
## Every legal movement is one of those, so "can a car get from here to there"
## and "what does that path look like" are the same question with one answer.
##
## BUILT FROM MapDefinition AT LOAD, NEVER STORED IN THE MAP FILE. A lane is a
## derived fact about a road, the way the junction fills and the fence line
## already are, and a map that carried its own lanes would be a map that could
## disagree with its own roads.

## Which way a turn goes, by the angle between the two headings. Godot's 2D y
## axis points down, so a positive rotation is clockwise on screen, which is a
## right turn for a driver.
enum Turn { THROUGH, LEFT, RIGHT, U_TURN }

## What stands at a junction. NONE is a bend or a dead end: no control, because
## there is nothing to give way to.
enum JunctionControl { NONE, SIGNAL, STOP }

## Half-angle, radians. A movement within this of straight on is a through
## movement and anything else is a left or a right. Generous, because a real
## junction's arms are rarely square and Windsor's are surveyed rather than
## drawn: two of its junctions meet at well under a right angle.
const THROUGH_HALF_ANGLE: float = PI / 4.0

## Road classes that make a junction important enough to signal, on their own.
## "Tertiary or above" from the milestone prompt, spelled out as the tags the
## importer actually writes.
const MAJOR_CLASSES: Array = [
	"tertiary", "tertiary_link", "secondary", "secondary_link",
	"primary", "primary_link", "trunk", "motorway",
]

## A junction with this many arms is signalled whatever it is made of.
##
## JAMES'S DECISION, taken on the measured data rather than in the abstract. The
## rule as first written was "the widest arm is tertiary or above", and on
## Windsor that is exactly two junctions, both on Hembree Lane at the far west
## edge, out of twenty; on Elm Grove, whose roads carry no highway class at all,
## it is none out of sixteen. A signal nobody drives past is not a feature. Four
## arms means a crossroads, and a crossroads is the junction that most wants
## signalling anyway.
const SIGNAL_MIN_ARMS: int = 4

## How far a lane stops short of the junction at each end, so the turn curve has
## the junction to itself and the lane's end is a sensible place to put a stop
## line. Half the road's width would be the edge of the junction fill, but
## Windsor's segments are surveyed and some are shorter than one road is wide,
## so it is also capped at a fraction of the segment: a lane always keeps most
## of its own length rather than vanishing.
const SETBACK_LENGTH_FRACTION: float = 0.32

## How far short of the very end of a road a lane stops at a dead end. Small,
## and there so that a lane's end is strictly inside the asphalt rather than
## exactly on its edge. See _junction_radius.
const DEAD_END_SETBACK: float = 6.0

## Points on each turn curve, including both ends. Turns are short and a car
## reads them as one steering input; more points is more memory for a shape
## nobody can see the facets of.
const TURN_POINTS: int = 7

## node id -> Dictionary describing the junction there. See _classify_junctions.
var junctions: Dictionary = {}

## Every directional lane. Each entry:
##   {id, edge_index, road_index, from_node, to_node, entry, exit, width,
##    highway, heading, length}
## "entry" and "exit" are the ends of the lane's own straight run, already set
## back from both junctions.
var lanes: Array[Dictionary] = []

## Every legal movement between two lanes. Each entry:
##   {id, node, from_lane, to_lane, kind, points}
var turns: Array[Dictionary] = []

## lane id -> Array[int] of turn ids leaving it.
var turns_from_lane: Dictionary = {}

## node id -> Array[int] of lane ids arriving at / leaving that node.
var lanes_into_node: Dictionary = {}
var lanes_out_of_node: Dictionary = {}

var _graph: RoadGraph = null


static func build(graph: RoadGraph, definition: MapDefinition) -> LaneGraph:
	var lane_graph := LaneGraph.new()
	lane_graph._build(graph, definition)
	return lane_graph


func get_road_graph() -> RoadGraph:
	return _graph


## Right of a heading, for a driver facing along it. Godot's y axis points down,
## so rotating a heading a quarter turn the positive way is the driver's right.
static func right_of(heading: Vector2) -> Vector2:
	return Vector2(-heading.y, heading.x)


func _build(graph: RoadGraph, definition: MapDefinition) -> void:
	_graph = graph
	_build_lanes(graph, definition)
	_build_turns(graph)
	_classify_junctions(graph, definition)


# ---------------------------------------------------------------------------
# Lanes
# ---------------------------------------------------------------------------

## How far back from a node a lane should stop. The junction fill reaches half
## the widest arriving road's width from the node, so that is the distance a
## lane has to clear to be out of the junction.
func _junction_radius(graph: RoadGraph, node: int) -> float:
	var incident: Array = graph.incident_edges.get(node, [])
	if incident.size() < 2:
		# A dead end has no junction, so there is nothing to keep clear of. It
		# still gets a small setback, because a lane ending exactly on the road's
		# last vertex ends exactly on the square end of its own slab, which is a
		# point that is ON the asphalt's boundary rather than inside it. The
		# first version of this returned zero and put two Windsor lane ends and
		# six turn points off the road by nothing at all.
		return DEAD_END_SETBACK
	var widest: float = 0.0
	for edge_index in incident:
		widest = maxf(widest, float(graph.edges[int(edge_index)]["width"]))
	return widest / 2.0


func _build_lanes(graph: RoadGraph, definition: MapDefinition) -> void:
	lanes.clear()
	lanes_into_node.clear()
	lanes_out_of_node.clear()

	for edge_index in range(graph.edges.size()):
		var edge: Dictionary = graph.edges[edge_index]
		var a: int = int(edge["a"])
		var b: int = int(edge["b"])
		# Both directions. The second is the same segment read backwards, which
		# puts its lane on the other side of the centreline without any special
		# case for which side is which.
		_add_lane(graph, definition, edge_index, a, b)
		_add_lane(graph, definition, edge_index, b, a)


func _add_lane(
	graph: RoadGraph, definition: MapDefinition, edge_index: int, from_node: int, to_node: int
) -> void:
	var edge: Dictionary = graph.edges[edge_index]
	var start: Vector2 = graph.positions[from_node]
	var finish: Vector2 = graph.positions[to_node]
	var span: Vector2 = finish - start
	var length: float = span.length()
	if length <= 0.0:
		return
	var heading: Vector2 = span / length

	# Set back from the junction at each end, but never so far that the lane
	# loses most of itself: Windsor has segments shorter than a road is wide.
	var cap: float = length * SETBACK_LENGTH_FRACTION
	var back_start: float = minf(_junction_radius(graph, from_node), cap)
	var back_end: float = minf(_junction_radius(graph, to_node), cap)

	var offset: Vector2 = right_of(heading) * float(edge["width"]) / 4.0
	var entry: Vector2 = start + heading * back_start + offset
	var exit: Vector2 = finish - heading * back_end + offset

	var road_index: int = int(edge["road_index"])
	var road: Dictionary = definition.roads[road_index]

	var id: int = lanes.size()
	lanes.append({
		"id": id,
		"edge_index": edge_index,
		"road_index": road_index,
		"from_node": from_node,
		"to_node": to_node,
		"entry": entry,
		"exit": exit,
		"width": float(edge["width"]),
		"highway": String(road.get("highway", "")),
		"name": String(road.get("name", "")),
		"heading": heading,
		"length": entry.distance_to(exit),
	})

	if not lanes_out_of_node.has(from_node):
		lanes_out_of_node[from_node] = [] as Array[int]
	lanes_out_of_node[from_node].append(id)
	if not lanes_into_node.has(to_node):
		lanes_into_node[to_node] = [] as Array[int]
	lanes_into_node[to_node].append(id)


# ---------------------------------------------------------------------------
# Turns
# ---------------------------------------------------------------------------

## Every legal movement at every node.
##
## From a lane arriving at a node, a car may leave down any lane out of that
## node EXCEPT the one that would send it straight back the way it came. That
## one movement, the U-turn, is legal only at a dead end, where it is the only
## thing a car can do.
func _build_turns(graph: RoadGraph) -> void:
	turns.clear()
	turns_from_lane.clear()

	for node in range(graph.positions.size()):
		var arriving: Array = lanes_into_node.get(node, [])
		var leaving: Array = lanes_out_of_node.get(node, [])
		var dead_end: bool = graph.incident_edges.get(node, []).size() <= 1
		for from_id in arriving:
			var incoming: Dictionary = lanes[int(from_id)]
			for to_id in leaving:
				var outgoing: Dictionary = lanes[int(to_id)]
				var reversing: bool = (
					int(outgoing["edge_index"]) == int(incoming["edge_index"])
				)
				if reversing and not dead_end:
					continue
				_add_turn(node, int(from_id), int(to_id), reversing)


func _add_turn(node: int, from_id: int, to_id: int, reversing: bool) -> void:
	var incoming: Dictionary = lanes[from_id]
	var outgoing: Dictionary = lanes[to_id]

	var kind: int = Turn.U_TURN if reversing else _classify(
		incoming["heading"], outgoing["heading"]
	)

	var id: int = turns.size()
	turns.append({
		"id": id,
		"node": node,
		"from_lane": from_id,
		"to_lane": to_id,
		"kind": kind,
		"points": _turn_points(node, incoming, outgoing),
	})
	if not turns_from_lane.has(from_id):
		turns_from_lane[from_id] = [] as Array[int]
	turns_from_lane[from_id].append(id)


## Which way a movement goes, for a movement that is NOT a reversal.
##
## U_TURN is deliberately not reachable from here. It used to be, for anything
## doubling back more than 135 degrees, and that made "kind is a U-turn" and
## "this movement goes back down the road it came from" two different things:
## Windsor has two junctions whose arms are sharp enough that an ordinary left
## turn between two different roads came out labelled a U-turn. A U-turn is a
## reversal onto the same road and nothing else, so it is set by the caller,
## which is the only place that knows.
static func _classify(incoming: Vector2, outgoing: Vector2) -> int:
	var turned: float = wrapf(outgoing.angle() - incoming.angle(), -PI, PI)
	if absf(turned) <= THROUGH_HALF_ANGLE:
		return Turn.THROUGH
	# Positive is clockwise on a y-down screen, which is the driver's right.
	return Turn.RIGHT if turned > 0.0 else Turn.LEFT


## The curve a car actually drives across the junction, from the end of the lane
## it arrived on to the start of the lane it leaves on.
##
## A quadratic Bezier with the junction's own node as the control point. That is
## the point both lanes are aimed at, so the curve leaves the first lane along
## its heading and joins the second along its heading, which is what makes a
## turn look driven rather than cut. A through movement across a straight
## junction has both ends on the same line and comes out straight, for free.
func _turn_points(node: int, incoming: Dictionary, outgoing: Dictionary) -> PackedVector2Array:
	var start: Vector2 = incoming["exit"]
	var finish: Vector2 = outgoing["entry"]
	var control: Vector2 = _graph.positions[node]

	var points := PackedVector2Array()
	for step in range(TURN_POINTS):
		var t: float = float(step) / float(TURN_POINTS - 1)
		var one: Vector2 = start.lerp(control, t)
		var two: Vector2 = control.lerp(finish, t)
		points.append(one.lerp(two, t))
	return points


# ---------------------------------------------------------------------------
# Junction control
# ---------------------------------------------------------------------------

## Which junctions get signals, which get stop signs, and on which arms.
##
## The rule, as James settled it: a junction of three arms or more is SIGNALLED
## if its widest arm is tertiary or above, or if it has four arms or more.
## Every other three-plus-arm junction gets STOP signs, on its minor arms only.
## A two-arm bend and a dead end get nothing, because there is nothing to give
## way to at either.
##
## "Minor arm" is decided by width first and by geometry second. Where the arms
## differ in width, the narrow ones stop. Where they are all the same width,
## which is most of Windsor and all of Elm Grove, the two arms most nearly
## opposite each other are the road going through and everything else stops:
## that is how a T on a residential street is actually signed, and a rule that
## only looked at width would have given a three-way junction of identical
## streets either three stop signs or none.
func _classify_junctions(graph: RoadGraph, definition: MapDefinition) -> void:
	junctions.clear()

	for node in range(graph.positions.size()):
		var incident: Array = graph.incident_edges.get(node, [])
		if incident.size() < 3:
			continue

		var here: Vector2 = graph.positions[node]
		var arms: Array[Dictionary] = []
		var widest: float = 0.0
		var widest_class: String = ""
		for edge_index in incident:
			var edge: Dictionary = graph.edges[int(edge_index)]
			var other: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
			var heading: Vector2 = (graph.positions[other] - here).normalized()
			if heading == Vector2.ZERO:
				continue
			var road: Dictionary = definition.roads[int(edge["road_index"])]
			var width: float = float(edge["width"])
			arms.append({
				"edge_index": int(edge_index),
				"heading": heading,
				"width": width,
				"highway": String(road.get("highway", "")),
				"name": String(road.get("name", "")),
			})
			if width > widest:
				widest = width
				widest_class = String(road.get("highway", ""))

		if arms.size() < 3:
			continue

		var control: int = JunctionControl.STOP
		if MAJOR_CLASSES.has(widest_class) or arms.size() >= SIGNAL_MIN_ARMS:
			control = JunctionControl.SIGNAL

		junctions[node] = {
			"node": node,
			"position": here,
			"arms": arms,
			"arm_count": arms.size(),
			"widest_width": widest,
			"widest_class": widest_class,
			"control": control,
			"stop_arms": (
				[] as Array[int] if control == JunctionControl.SIGNAL else _minor_arms(arms, widest)
			),
		}


## The arms that stop. Everything narrower than the widest, or, where they are
## all the widest, everything that is not one of the two most nearly opposite.
static func _minor_arms(arms: Array[Dictionary], widest: float) -> Array[int]:
	var minor: Array[int] = []
	var majors: Array[int] = []
	for index in range(arms.size()):
		if is_equal_approx(float(arms[index]["width"]), widest):
			majors.append(index)
		else:
			minor.append(int(arms[index]["edge_index"]))

	if majors.size() <= 2:
		# One or two widest arms: they are the road going through, and the rest
		# already stop.
		return minor

	# Three or more equally wide arms. The through route is the opposed pair:
	# the two whose headings point most nearly away from one another.
	var best_a: int = majors[0]
	var best_b: int = majors[1]
	var most_opposed: float = 2.0
	for i in range(majors.size()):
		for j in range(i + 1, majors.size()):
			var dot: float = (
				Vector2(arms[majors[i]]["heading"]).dot(Vector2(arms[majors[j]]["heading"]))
			)
			if dot < most_opposed:
				most_opposed = dot
				best_a = majors[i]
				best_b = majors[j]
	for index in majors:
		if index != best_a and index != best_b:
			minor.append(int(arms[index]["edge_index"]))
	return minor


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func get_control(node: int) -> int:
	if not junctions.has(node):
		return JunctionControl.NONE
	return int(junctions[node]["control"])


## Whether a car arriving at this node down this edge has to stop.
func arm_has_stop_sign(node: int, edge_index: int) -> bool:
	if not junctions.has(node):
		return false
	var junction: Dictionary = junctions[node]
	if int(junction["control"]) != JunctionControl.STOP:
		return false
	return junction["stop_arms"].has(edge_index)


func junction_nodes_with(control: int) -> Array[int]:
	var found: Array[int] = []
	for node in junctions:
		if int(junctions[node]["control"]) == control:
			found.append(int(node))
	found.sort()
	return found


## How many junctions got each control, for the record kept per map.
func control_counts() -> Dictionary:
	var counts: Dictionary = {"signal": 0, "stop": 0}
	for node in junctions:
		if int(junctions[node]["control"]) == JunctionControl.SIGNAL:
			counts["signal"] += 1
		else:
			counts["stop"] += 1
	return counts


## Every lane reachable from a starting lane by following turns, as a set.
##
## Used by the strong-connectivity check: a lane network a car can drive into
## and not out of is a network that will eventually park a car forever.
func lanes_reachable_from(start_lane: int) -> Dictionary:
	var seen: Dictionary = {start_lane: true}
	var stack: Array[int] = [start_lane]
	while not stack.is_empty():
		var lane_id: int = stack.pop_back()
		for turn_id in turns_from_lane.get(lane_id, [] as Array[int]):
			var next_lane: int = int(turns[int(turn_id)]["to_lane"])
			if not seen.has(next_lane):
				seen[next_lane] = true
				stack.append(next_lane)
	return seen


## Every lane that can reach the given lane, by walking the turns backwards.
func lanes_that_reach(target_lane: int) -> Dictionary:
	var backwards: Dictionary = {}
	for turn in turns:
		var to_lane: int = int(turn["to_lane"])
		if not backwards.has(to_lane):
			backwards[to_lane] = [] as Array[int]
		backwards[to_lane].append(int(turn["from_lane"]))

	var seen: Dictionary = {target_lane: true}
	var stack: Array[int] = [target_lane]
	while not stack.is_empty():
		var lane_id: int = stack.pop_back()
		for previous in backwards.get(lane_id, [] as Array[int]):
			if not seen.has(previous):
				seen[previous] = true
				stack.append(previous)
	return seen


## True when every lane can reach every other lane. Checked from one lane in
## both directions, which is the standard two-pass test and is enough: if one
## lane reaches all and is reached by all, every pair is connected through it.
func is_strongly_connected() -> bool:
	if lanes.is_empty():
		return false
	return (
		lanes_reachable_from(0).size() == lanes.size()
		and lanes_that_reach(0).size() == lanes.size()
	)
