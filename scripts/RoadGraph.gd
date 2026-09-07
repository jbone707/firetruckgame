extends RefCounted
class_name RoadGraph
## The road network of a MapDefinition as an actual graph: nodes, edges and
## route lengths along the pavement.
##
## Built purely from the road geometry, never from map-specific constants, so
## the same code serves both maps. That matters because the two are shaped
## differently and the differences are exactly where the old assumptions broke:
##
## - The fictional neighbourhood is a grid of long axis-aligned roads that
##   CROSS one another in mid-span. Its junctions are segment intersections,
##   not shared endpoints.
## - The Windsor import is a set of ways already split at their shared OSM
##   nodes, so its junctions are shared endpoints and its roads bend.
##
## Handling both means doing two things: snapping coincident vertices together
## (which finds the Windsor junctions) and splitting segments where they
## properly cross (which finds the fictional ones). A graph built either way
## alone is wrong on the other map.
##
## Nothing here draws or simulates. It answers: what is connected to what, how
## far is it along the roads, and which points are junctions or dead ends.

## How close two road vertices must be, in world units, to count as the same
## place. Roads are hundreds of units wide, so half a unit is far below any
## real distinction and comfortably above float noise in a saved resource.
const WELD_TOLERANCE: float = 0.5

## Node positions, indexed by node id.
var positions: PackedVector2Array = PackedVector2Array()

## Each entry: {a: int, b: int, road_index: int, length: float, width: float}.
var edges: Array[Dictionary] = []

## node id -> Array[int] of edge indices touching it.
var incident_edges: Dictionary = {}

var _cell_size: float = 1.0
var _lookup: Dictionary = {}


static func build(definition: MapDefinition) -> RoadGraph:
	var graph := RoadGraph.new()
	graph._build(definition)
	return graph


## True when every node is reachable from the node nearest to "from". Used by
## the validator for "one connected component from the spawn".
func is_connected_from(from: Vector2) -> bool:
	if positions.is_empty():
		return false
	return reachable_from(from).size() == positions.size()


## The set of node ids reachable from the node nearest to "from", as a
## Dictionary used as a set so membership tests stay cheap.
func reachable_from(from: Vector2) -> Dictionary:
	var seen: Dictionary = {}
	var start: int = nearest_node(from)
	if start < 0:
		return seen

	var stack: Array[int] = [start]
	seen[start] = true
	while not stack.is_empty():
		var node: int = stack.pop_back()
		for edge_index in incident_edges.get(node, [] as Array[int]):
			var edge: Dictionary = edges[edge_index]
			var other: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
			if not seen.has(other):
				seen[other] = true
				stack.append(other)
	return seen


func nearest_node(point: Vector2) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i in range(positions.size()):
		var distance: float = positions[i].distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Junctions are nodes where three or more road ends meet. A node with two
## edges is a bend in one road, not a crossing.
func junction_nodes() -> Array[int]:
	var found: Array[int] = []
	for node in range(positions.size()):
		if incident_edges.get(node, [] as Array[int]).size() >= 3:
			found.append(node)
	return found


func dead_end_nodes() -> Array[int]:
	var found: Array[int] = []
	for node in range(positions.size()):
		if incident_edges.get(node, [] as Array[int]).size() == 1:
			found.append(node)
	return found


## Shortest distance ALONG THE ROADS between the two nodes nearest to "from"
## and "to", plus the straight hops from each point to its nearest node.
##
## This is the number the escalation travel allowance is priced from. The old
## rule added the x and y gaps, which is the right answer only on a map whose
## every road is axis-aligned, and is quietly wrong the moment a road bends.
## Returns INF when there is no route.
func route_length(from: Vector2, to: Vector2) -> float:
	var start: int = nearest_node(from)
	var goal: int = nearest_node(to)
	if start < 0 or goal < 0:
		return INF

	var approach: float = positions[start].distance_to(from) + positions[goal].distance_to(to)
	if start == goal:
		return approach

	var distances: PackedFloat32Array = PackedFloat32Array()
	distances.resize(positions.size())
	distances.fill(INF)
	distances[start] = 0.0

	var settled: Dictionary = {}
	# Plain repeated-minimum Dijkstra. The graphs here are hundreds of nodes at
	# most and this runs on dispatch, not per frame, so a heap would be
	# machinery without a purpose.
	while true:
		var current: int = -1
		var current_distance: float = INF
		for node in range(positions.size()):
			if settled.has(node):
				continue
			if distances[node] < current_distance:
				current_distance = distances[node]
				current = node
		if current < 0 or current == goal:
			break
		settled[current] = true
		for edge_index in incident_edges.get(current, [] as Array[int]):
			var edge: Dictionary = edges[edge_index]
			var other: int = int(edge["b"]) if int(edge["a"]) == current else int(edge["a"])
			var candidate: float = current_distance + float(edge["length"])
			if candidate < distances[other]:
				distances[other] = candidate

	if distances[goal] == INF:
		return INF
	return distances[goal] + approach


## Distance from a point to the nearest road CENTRELINE, and the width of the
## road it belongs to. Returns {distance: float, width: float, road_index: int}
## with distance INF when the map has no roads.
func nearest_road(point: Vector2) -> Dictionary:
	var best: Dictionary = {"distance": INF, "width": 0.0, "road_index": -1}
	for edge in edges:
		var distance: float = _distance_to_segment(
			point, positions[int(edge["a"])], positions[int(edge["b"])]
		)
		if distance < float(best["distance"]):
			best = {
				"distance": distance,
				"width": float(edge["width"]),
				"road_index": int(edge["road_index"]),
			}
	return best


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build(definition: MapDefinition) -> void:
	# Every road, as a list of straight segments carrying the road it came from
	# and that road's width. Splitting happens on this flat list rather than on
	# the polylines, so a crossing found halfway along one segment is simply two
	# segments afterwards and nothing else has to know.
	var segments: Array[Dictionary] = []
	for road_index in range(definition.roads.size()):
		var road: Dictionary = definition.roads[road_index]
		var points: PackedVector2Array = road["points"]
		var width: float = float(road.get("width", 0.0))
		for i in range(points.size() - 1):
			if points[i].distance_to(points[i + 1]) <= WELD_TOLERANCE:
				continue
			segments.append({
				"a": points[i], "b": points[i + 1],
				"road_index": road_index, "width": width,
			})

	segments = _split_at_crossings(segments)

	_cell_size = maxf(WELD_TOLERANCE * 2.0, 1.0)
	for segment in segments:
		var a: int = _node_at(segment["a"])
		var b: int = _node_at(segment["b"])
		if a == b:
			continue
		var edge_index: int = edges.size()
		edges.append({
			"a": a, "b": b,
			"road_index": int(segment["road_index"]),
			"length": positions[a].distance_to(positions[b]),
			"width": float(segment["width"]),
		})
		_touch(a, edge_index)
		_touch(b, edge_index)


## Splits every pair of segments that properly cross, so a grid of long roads
## laid across one another becomes a graph with a node at each crossing rather
## than two sets of edges that pass through each other without meeting.
##
## Segments belonging to the same road are never split against each other: a
## road that doubles back on itself is a shape, not a junction with itself.
func _split_at_crossings(segments: Array[Dictionary]) -> Array[Dictionary]:
	# Cut points collected per segment first, then applied in one pass, because
	# a segment can be crossed more than once and splitting as we go would keep
	# invalidating the indices we are iterating.
	var cuts: Array[PackedFloat32Array] = []
	for i in range(segments.size()):
		cuts.append(PackedFloat32Array())

	for i in range(segments.size()):
		for j in range(i + 1, segments.size()):
			if int(segments[i]["road_index"]) == int(segments[j]["road_index"]):
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
				segments[i]["a"], segments[i]["b"], segments[j]["a"], segments[j]["b"]
			)
			if hit == null:
				continue
			var point: Vector2 = hit
			_add_cut(cuts[i], segments[i], point)
			_add_cut(cuts[j], segments[j], point)

	var result: Array[Dictionary] = []
	for i in range(segments.size()):
		var segment: Dictionary = segments[i]
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var ordered: Array[float] = []
		for t in cuts[i]:
			ordered.append(t)
		ordered.sort()

		var previous: Vector2 = a
		for t in ordered:
			var point: Vector2 = a.lerp(b, t)
			if previous.distance_to(point) > WELD_TOLERANCE:
				result.append({
					"a": previous, "b": point,
					"road_index": segment["road_index"], "width": segment["width"],
				})
				previous = point
		if previous.distance_to(b) > WELD_TOLERANCE:
			result.append({
				"a": previous, "b": b,
				"road_index": segment["road_index"], "width": segment["width"],
			})
	return result


## Records where along a segment a crossing falls, ignoring crossings that land
## on either end: those are already shared vertices and welding handles them.
func _add_cut(into: PackedFloat32Array, segment: Dictionary, point: Vector2) -> void:
	var a: Vector2 = segment["a"]
	var b: Vector2 = segment["b"]
	var length: float = a.distance_to(b)
	if length <= WELD_TOLERANCE:
		return
	var t: float = clampf((point - a).dot((b - a) / length) / length, 0.0, 1.0)
	if t * length <= WELD_TOLERANCE or (1.0 - t) * length <= WELD_TOLERANCE:
		return
	into.append(t)


## The node id at a position, welding onto an existing node within
## WELD_TOLERANCE. Bucketed into a coarse grid so this stays linear in the
## number of nodes rather than quadratic.
func _node_at(point: Vector2) -> int:
	var cell_x: int = int(floor(point.x / _cell_size))
	var cell_y: int = int(floor(point.y / _cell_size))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key: String = "%d,%d" % [cell_x + dx, cell_y + dy]
			for candidate in _lookup.get(key, [] as Array[int]):
				if positions[candidate].distance_to(point) <= WELD_TOLERANCE:
					return candidate

	var node: int = positions.size()
	positions.append(point)
	var own_key: String = "%d,%d" % [cell_x, cell_y]
	if not _lookup.has(own_key):
		_lookup[own_key] = [] as Array[int]
	var bucket: Array[int] = _lookup[own_key]
	bucket.append(node)
	_lookup[own_key] = bucket
	return node


func _touch(node: int, edge_index: int) -> void:
	if not incident_edges.has(node):
		incident_edges[node] = [] as Array[int]
	var list: Array[int] = incident_edges[node]
	list.append(edge_index)
	incident_edges[node] = list


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
