extends RefCounted
class_name MapGeometry
## The polygon regions a map is drawn and collided from, derived from its road
## network alone (Milestone 5 Part 1).
##
## The old MapBuilder treated every road as an axis-aligned rectangle and read
## the land between them out of MapDefinition.blocks, which are rectangles too.
## Neither survives a real map: an imported road bends, meets another at
## whatever angle the ground happens to give, and stops dead in a cul-de-sac,
## and the land left over between roads like that is not a set of rectangles and
## cannot be written as one.
##
## So nothing here knows about rectangles or axes. Two regions are derived, both
## by the same operation, and everything the player sees or hits comes from one
## of them:
##
## - the KERB region: the map, minus every road slab. Its boundary is the kerb.
## - the LOT region: the map, minus every road slab grown outward by the
##   sidewalk width. Its boundary is the fence, which is where the truck stops.
##
## Between the two lies the sidewalk: drivable, mountable, and free, exactly as
## before. Deriving both from the same slabs is what makes the kerb and the
## fence agree at every angle without either being computed twice.
##
## Why subtraction rather than a union of the roads: Godot's Geometry2D merges
## two polygons at a time, and a road network that encloses a block unions into
## a ring, which is a polygon with a hole, which the next merge cannot take as
## input. Clipping the map rectangle by one slab at a time never builds a ring:
## as long as the road network reaches the edge of the map, every piece it
## leaves behind is a simple polygon. MapValidator checks exactly that on every
## map, so a map that broke the assumption would fail the checker rather than
## quietly draw wrongly.

## Lot pieces smaller than this are dropped. Near-parallel roads leave slivers a
## few units across between them, and fencing one off would put an invisible
## wall in the road for no gain. 400 square units is a 20 by 20 patch, against a
## truck that is 90 by 40, so nothing droppable could ever have held the truck.
const MIN_LOT_AREA: float = 400.0

## How close a boundary edge must be to the map's own edge to be treated as the
## map edge rather than as a kerb or a fence. The wall along the boundary is
## neither, and drawing one there would ring the whole map in a line.
const BOUNDARY_EPSILON: float = 1.0


## Every road segment as an oriented slab, kerb to kerb, plus one convex fill at
## every node where two or more segments meet.
##
## The fills are the junctions. Two slabs meeting at an angle overlap on the
## inside of the turn and leave a wedge of bare ground on the outside; the
## convex hull of every slab cross-section at the shared node covers that wedge
## exactly, at any angle, and adds nothing where a road runs straight through.
## A dead end has one segment and gets no fill, which is what makes a cul-de-sac
## stop square rather than flare.
static func road_slabs(graph: RoadGraph) -> Array[PackedVector2Array]:
	var slabs: Array[PackedVector2Array] = []
	for edge in graph.edges:
		var a: Vector2 = graph.positions[int(edge["a"])]
		var b: Vector2 = graph.positions[int(edge["b"])]
		if a.distance_to(b) <= 0.0:
			continue
		slabs.append(oriented_slab(a, b, float(edge["width"])))

	for node in range(graph.positions.size()):
		var fill: PackedVector2Array = junction_fill(graph, node)
		if fill.size() >= 3:
			slabs.append(fill)
	return slabs


## The convex fill at one node, or an empty array at a dead end. Built from the
## cross-section of every segment arriving at the node, so a node where a wide
## road meets a narrow one is covered out to the wider road's edge without the
## narrow one being widened along its length.
static func junction_fill(graph: RoadGraph, node: int) -> PackedVector2Array:
	var incident: Array = graph.incident_edges.get(node, [])
	if incident.size() < 2:
		return PackedVector2Array()

	var here: Vector2 = graph.positions[node]
	var points: PackedVector2Array = PackedVector2Array()
	for edge_index in incident:
		var edge: Dictionary = graph.edges[int(edge_index)]
		var other_node: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
		var direction: Vector2 = (graph.positions[other_node] - here).normalized()
		if direction == Vector2.ZERO:
			continue
		var perpendicular: Vector2 = (
			Vector2(-direction.y, direction.x) * float(edge["width"]) / 2.0
		)
		points.append(here + perpendicular)
		points.append(here - perpendicular)
	if points.size() < 3:
		return PackedVector2Array()
	return Geometry2D.convex_hull(points)


## A rectangle running from a to b, width wide, square across both ends and
## oriented along a-b. The one shape every road, dash and junction is built from.
static func oriented_slab(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var direction: Vector2 = (b - a).normalized()
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * (width / 2.0)
	return PackedVector2Array([
		a + perpendicular, b + perpendicular, b - perpendicular, a - perpendicular,
	])


## The land the roads do not cover: the map rectangle with every slab, grown
## outward by "grow", cut out of it. A grow of 0 gives the kerb region and the
## sidewalk width gives the lot region.
static func region_outside_roads(
	graph: RoadGraph, bounds: Rect2, grow: float, minimum_area: float = MIN_LOT_AREA
) -> Array[PackedVector2Array]:
	var region: Array[PackedVector2Array] = [rect_polygon(bounds)]
	for slab in road_slabs(graph):
		for cutter in _grown(slab, grow):
			region = _clip_region(region, cutter)
	return _cleaned(region, minimum_area)


## The same region with a set of polygons (the buildings) also cut out of it.
## Kept separate from region_outside_roads because the yards and fences are
## drawn from the land BETWEEN the roads, houses and all, while the lot
## collision is only the land that is not already solid for another reason.
static func subtract_polygons(
	region: Array[PackedVector2Array],
	polygons: Array[PackedVector2Array],
	minimum_area: float = MIN_LOT_AREA
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = region.duplicate()
	for polygon in polygons:
		if polygon.size() < 3:
			continue
		result = _clip_region(result, polygon)
	return _cleaned(result, minimum_area)


## True when any piece of a region is a hole rather than solid ground. Godot
## marks a hole by winding it clockwise. Nothing here can draw or collide a
## hole, so this is the question MapValidator asks of every map.
static func has_holes(region: Array[PackedVector2Array]) -> bool:
	for piece in region:
		if Geometry2D.is_polygon_clockwise(piece):
			return true
	return false


## One closed boundary broken into the open runs that are NOT the map's own
## edge. The kerb and the fence are drawn from these: a lot band that reaches
## the edge of the map is bounded there by the boundary wall, not by a fence,
## and drawing the closed loop would ring the whole map in a line that means
## nothing.
static func boundary_runs(
	polygon: PackedVector2Array, bounds: Rect2
) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var count: int = polygon.size()
	if count < 3:
		return runs

	var dropped: bool = false
	var current: PackedVector2Array = PackedVector2Array()
	for i in range(count):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % count]
		if _on_boundary(a, bounds) and _on_boundary(b, bounds):
			dropped = true
			if current.size() >= 2:
				runs.append(current)
			current = PackedVector2Array()
			continue
		if current.is_empty():
			current.append(a)
		current.append(b)
	if current.size() >= 2:
		runs.append(current)

	# Nothing lay on the boundary, so the whole loop is real fence: hand it back
	# closed rather than as one run that stops a vertex short of itself.
	if not dropped:
		return [polygon]

	# The walk starts mid-loop, so a run that ends where another begins is one
	# fence split by the seam. Rejoin it.
	if runs.size() >= 2 and runs[0][0] == runs[runs.size() - 1][runs[runs.size() - 1].size() - 1]:
		var last: PackedVector2Array = runs.pop_back()
		var joined: PackedVector2Array = last.duplicate()
		for i in range(1, runs[0].size()):
			joined.append(runs[0][i])
		runs[0] = joined
	return runs


static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])


static func polygon_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(polygon.size()):
		total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(total) / 2.0


static func polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for point in polygon:
		sum += point
	return sum / float(polygon.size())


# ---------------------------------------------------------------------------

static func _grown(slab: PackedVector2Array, grow: float) -> Array[PackedVector2Array]:
	if grow <= 0.0:
		return [slab]
	# JOIN_SQUARE keeps a grown rectangle a rectangle. A rounded join would eat
	# the corners, and the fictional map's fence lines are checked against exact
	# coordinates that only a square join reproduces.
	return Geometry2D.offset_polygon(slab, grow, Geometry2D.JOIN_SQUARE)


static func _clip_region(
	region: Array[PackedVector2Array], cutter: PackedVector2Array
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for piece in region:
		for clipped in Geometry2D.clip_polygons(piece, cutter):
			result.append(clipped)
	return result


static func _cleaned(
	region: Array[PackedVector2Array], minimum_area: float
) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for piece in region:
		if piece.size() < 3:
			continue
		if polygon_area(piece) < minimum_area:
			continue
		result.append(piece)
	return result


static func _on_boundary(point: Vector2, bounds: Rect2) -> bool:
	return (
		absf(point.x - bounds.position.x) <= BOUNDARY_EPSILON
		or absf(point.y - bounds.position.y) <= BOUNDARY_EPSILON
		or absf(point.x - bounds.end.x) <= BOUNDARY_EPSILON
		or absf(point.y - bounds.end.y) <= BOUNDARY_EPSILON
	)
