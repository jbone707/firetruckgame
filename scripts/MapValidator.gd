extends RefCounted
class_name MapValidator
## The rules any MapDefinition has to satisfy to be playable (handoff §7, §11).
##
## Written against MapDefinition and RoadGraph only, never against a particular
## map, so the fictional neighbourhood and the Windsor import go through exactly
## the same checks. That is the point: a hand-built map and an imported one that
## are judged by different rules are not comparable, and the imported one is the
## whole reason the rules had to be written down at all.
##
## validate() returns one result per rule rather than a single boolean, because
## "the map is invalid" is not actionable and "no building polygon intersects a
## road slab: 3 offenders, first is b_osm_123" is.

## The narrowest road, in world units, this project is willing to ship.
##
## The intention was to measure this: tests/run_physics_tests.gd builds an
## L-corner rig, drives the truck into it at 40% of top speed and sweeps the
## road width downward looking for the width at which the turn stops working.
## The measurement was made and it did not find one. The truck circles in about
## 55 units at cornering speed and is 40 units wide, and every road carries a
## drivable sidewalk 34 units either side, so it got round a 20 unit road, the
## narrowest the sweep tried. Road width is simply not what stops the truck
## cornering.
##
## So this number is CHOSEN, not derived, and saying otherwise would overstate
## what was proved. It is 3.5 truck widths: enough to pass an obstacle and to
## correct a bad line rather than merely enough to squeeze through. What the
## sweep does establish is that it is not too LOW, and the physics runner
## asserts exactly that, so if the truck's size, steering or speed ever change
## enough to make 140 units untenable, that runner fails and says so.
##
## Be honest about the consequence: this is the weakest of the five rules. Both
## shipped maps clear it with margin (280 and 175 units), so today it would only
## catch a future import whose width table produced something absurd.
const MIN_TURNABLE_ROAD_WIDTH: float = 140.0

## How far past the kerb a hydrant or an incident marker may stand and still
## count as being ON that road, world units. Under a truck length on purpose:
## the player has to be able to pull up at it from the road, so "at the kerb" is
## the claim being checked, not "somewhere on the block".
const KERB_REACH: float = 60.0

## Two road slabs that do not share a graph node may still touch by this much
## before it counts as an overlap, square world units. Absorbs float noise in a
## saved resource and nothing else; it is far below any real width.
const OVERLAP_TOLERANCE_AREA: float = 4.0

## The shallowest angle at which two roads are still treated as meeting rather
## than running alongside each other. Below it the wedge formula in rule 4
## diverges, so the angle is clamped here. 12 degrees lets a slip road peel off
## a main road, which the Windsor import contains at 23 degrees, without letting
## two parallel carriageways pass as one junction.
const MIN_WEDGE_ANGLE: float = 0.2094 # 12 degrees


## Every rule, as an ordered array of
## {rule: String, passed: bool, detail: String}.
static func validate(definition: MapDefinition) -> Array[Dictionary]:
	var graph: RoadGraph = RoadGraph.build(definition)
	return [
		_check_connectivity(definition, graph),
		_check_features_are_on_a_road(definition, graph),
		_check_roads_are_wide_enough_to_turn_in(definition),
		_check_roads_only_overlap_at_junctions(definition, graph),
		_check_buildings_are_off_the_road(definition, graph),
	]


static func passed(results: Array[Dictionary]) -> bool:
	for result in results:
		if not bool(result["passed"]):
			return false
	return true


static func _result(rule: String, passed_value: bool, detail: String) -> Dictionary:
	return {"rule": rule, "passed": passed_value, "detail": detail}


## Rule 1. Every piece of road reachable from the station, in one graph, with
## nothing stranded. A stranded fragment is road the player can see and can
## never drive to, which on an imported map is the single most likely defect:
## it is what a way clipped at the box edge leaves behind.
static func _check_connectivity(definition: MapDefinition, graph: RoadGraph) -> Dictionary:
	const RULE: String = "road graph is one connected component from the spawn"
	if graph.positions.is_empty():
		return _result(RULE, false, "the map has no roads at all")

	var reachable: Dictionary = graph.reachable_from(definition.station_spawn_position)
	var stranded: int = graph.positions.size() - reachable.size()
	if stranded == 0:
		return _result(RULE, true, "%d node(s), all reachable" % graph.positions.size())

	var first_stranded: Vector2 = Vector2.ZERO
	for node in range(graph.positions.size()):
		if not reachable.has(node):
			first_stranded = graph.positions[node]
			break
	return _result(RULE, false, "%d of %d node(s) unreachable, first at %s" % [
		stranded, graph.positions.size(), first_stranded
	])


## Rule 2. Every hydrant and every incident candidate stands at the kerb of a
## road, and that road is one the truck can get to. A hydrant in the middle of a
## garden is a hydrant the player runs dry next to.
static func _check_features_are_on_a_road(definition: MapDefinition, graph: RoadGraph) -> Dictionary:
	const RULE: String = "every hydrant and incident candidate is at a road and reachable"
	var reachable: Dictionary = graph.reachable_from(definition.station_spawn_position)
	var problems: Array[String] = []

	var groups: Dictionary = {"hydrant": definition.hydrants, "incident": definition.incident_candidates}
	for kind in groups:
		for feature in groups[kind]:
			var position: Vector2 = feature["position"]
			var near: Dictionary = graph.nearest_road(position)
			var allowed: float = float(near["width"]) * 0.5 + KERB_REACH
			if float(near["distance"]) > allowed:
				problems.append("%s %s is %.0f units from the nearest road, allowed %.0f" % [
					kind, feature.get("id", "?"), float(near["distance"]), allowed
				])
				continue
			var node: int = graph.nearest_node(position)
			if node < 0 or not reachable.has(node):
				problems.append("%s %s is beside road the truck cannot reach" % [
					kind, feature.get("id", "?")
				])

	if problems.is_empty():
		return _result(RULE, true, "%d hydrant(s) and %d candidate(s) all at reachable kerbs" % [
			definition.hydrants.size(), definition.incident_candidates.size()
		])
	return _result(RULE, false, "%d problem(s): %s" % [problems.size(), "; ".join(problems)])


## Rule 3. No road is narrower than the truck can turn a corner in. A road that
## fails this is not merely tight: the player physically cannot get out of it.
static func _check_roads_are_wide_enough_to_turn_in(definition: MapDefinition) -> Dictionary:
	const RULE: String = "no road is narrower than the truck can turn in"
	var narrowest: float = INF
	var offenders: Array[String] = []
	for road in definition.roads:
		var width: float = float(road["width"])
		narrowest = minf(narrowest, width)
		if width < MIN_TURNABLE_ROAD_WIDTH:
			offenders.append("%s (%s) is %.0f wide" % [road["id"], road["name"], width])
	if narrowest == INF:
		return _result(RULE, false, "the map has no roads at all")
	if offenders.is_empty():
		return _result(RULE, true, "narrowest road is %.0f units, minimum is %.0f" % [
			narrowest, MIN_TURNABLE_ROAD_WIDTH
		])
	# Named individually up to a handful; a map where every road is too narrow
	# is a scale mistake and does not need every road listed to say so.
	var listed: Array[String] = offenders.slice(0, 5)
	return _result(RULE, false, "%d road(s) below %.0f units: %s%s" % [
		offenders.size(), MIN_TURNABLE_ROAD_WIDTH, "; ".join(listed),
		"" if offenders.size() <= 5 else ", and %d more" % (offenders.size() - 5),
	])


## Rule 4. Two roads may only share pavement where they actually meet.
##
## The defect this exists to catch is two roads drawn through each other with no
## node between them: it looks like a junction, it is not one, and the road
## graph, the route length and the escalation clock then all disagree with what
## the player can see.
##
## What it must NOT catch is the pavement around a real junction. Two roads
## meeting at an angle overlap in a wedge either side of where they meet, and
## the shallower the angle the further down both arms that wedge reaches.
##
## Note that a road CROSSING another with no junction cannot survive as far as
## this check: RoadGraph splits properly crossing segments and puts a node at
## the crossing, so by the time there is a graph there is a junction. What this
## rule can therefore still catch, and what it is written to catch, is two roads
## sharing pavement ALONG THEIR LENGTH rather than at the point they meet: two
## carriageways laid on top of each other, or a width invented by the importer
## that is wider than the gap between two real centrelines.
##
## The bound is derived from the geometry rather than picked. Two roads at angle
## theta have overlapping slabs for (halfA + halfB) / sin(theta) either side of
## their closest approach, so that, and not a fixed radius, is how far an
## overlap is allowed to reach. Below MIN_WEDGE_ANGLE the two roads are near
## enough parallel that the formula stops meaning anything and the angle is
## clamped, which is the one place this rule has a limit rather than a
## derivation: two roads running exactly alongside each other for less than the
## clamped distance are accepted.
static func _check_roads_only_overlap_at_junctions(
	definition: MapDefinition, graph: RoadGraph
) -> Dictionary:
	const RULE: String = "no two roads overlap outside a junction"
	var problems: Array[String] = []

	for i in range(graph.edges.size()):
		for j in range(i + 1, graph.edges.size()):
			var first: Dictionary = graph.edges[i]
			var second: Dictionary = graph.edges[j]
			if int(first["road_index"]) == int(second["road_index"]):
				continue
			# Sharing a node IS the junction, or a bend where one road was split.
			if (
				int(first["a"]) == int(second["a"]) or int(first["a"]) == int(second["b"])
				or int(first["b"]) == int(second["a"]) or int(first["b"]) == int(second["b"])
			):
				continue

			var overlap: Array[PackedVector2Array] = Geometry2D.intersect_polygons(
				_slab(graph, first), _slab(graph, second)
			)
			var area: float = 0.0
			for piece in overlap:
				area += absf(_polygon_area(piece))
			if area <= OVERLAP_TOLERANCE_AREA:
				continue

			var first_a: Vector2 = graph.positions[int(first["a"])]
			var first_b: Vector2 = graph.positions[int(first["b"])]
			var second_a: Vector2 = graph.positions[int(second["a"])]
			var second_b: Vector2 = graph.positions[int(second["b"])]

			var meeting: PackedVector2Array = Geometry2D.get_closest_points_between_segments(
				first_a, first_b, second_a, second_b
			)
			var meeting_point: Vector2 = (meeting[0] + meeting[1]) * 0.5

			var angle: float = absf((first_b - first_a).angle_to(second_b - second_a))
			angle = minf(angle, PI - angle)
			var reach: float = (
				(float(first["width"]) + float(second["width"])) * 0.5
				/ maxf(sin(angle), sin(MIN_WEDGE_ANGLE))
			)

			var furthest: float = 0.0
			for piece in overlap:
				for point in piece:
					furthest = maxf(furthest, point.distance_to(meeting_point))
			if furthest <= reach:
				continue

			problems.append(
				"roads %s and %s share pavement %.0f units from where they meet, %.0f allowed at %.0f degrees (%.0f square units)" % [
					definition.roads[int(first["road_index"])]["id"],
					definition.roads[int(second["road_index"])]["id"],
					furthest, reach, rad_to_deg(angle), area,
				]
			)

	if problems.is_empty():
		return _result(RULE, true, "%d road segment(s) checked pairwise" % graph.edges.size())
	var listed: Array[String] = problems.slice(0, 5)
	return _result(RULE, false, "%d overlap(s): %s%s" % [
		problems.size(), "; ".join(listed),
		"" if problems.size() <= 5 else ", and %d more" % (problems.size() - 5),
	])


## Rule 5. No building stands on the road. On an imported map this is the check
## that catches an invented road width disagreeing with a real footprint, which
## would otherwise ship as a house the truck cannot drive past.
static func _check_buildings_are_off_the_road(
	definition: MapDefinition, graph: RoadGraph
) -> Dictionary:
	const RULE: String = "no building polygon intersects a road slab"
	var problems: Array[String] = []
	for building in definition.buildings:
		var polygon: PackedVector2Array = building["polygon"]
		for edge in graph.edges:
			if not Geometry2D.intersect_polygons(polygon, _slab(graph, edge)).is_empty():
				problems.append("building %s stands on road %s" % [
					building.get("id", "?"), definition.roads[int(edge["road_index"])]["id"]
				])
				break

	if problems.is_empty():
		return _result(RULE, true, "%d building(s) all clear of the pavement" % definition.buildings.size())
	var listed: Array[String] = problems.slice(0, 5)
	return _result(RULE, false, "%d building(s) on the road: %s%s" % [
		problems.size(), "; ".join(listed),
		"" if problems.size() <= 5 else ", and %d more" % (problems.size() - 5),
	])


static func _slab(graph: RoadGraph, edge: Dictionary) -> PackedVector2Array:
	return oriented_rect(
		graph.positions[int(edge["a"])], graph.positions[int(edge["b"])], float(edge["width"])
	)


## The rectangle a straight road segment covers, kerb to kerb. The single
## definition of "where the pavement is", shared with the importer and with
## MapBuilder so a check and a drawing can never disagree about it.
static func oriented_rect(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var direction: Vector2 = b - a
	if direction.length() <= 0.0001:
		return PackedVector2Array()
	direction = direction.normalized()
	var side: Vector2 = Vector2(-direction.y, direction.x) * (width * 0.5)
	return PackedVector2Array([a + side, b + side, b - side, a - side])


static func _polygon_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5
