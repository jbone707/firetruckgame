extends "res://tests/test_case.gd"
## The regions MapBuilder draws and collides from, checked at every junction on
## every map (Milestone 6 Part 1).
##
## Milestone 5 derived the land between the roads by cutting the road slabs out
## of the map rectangle one at a time. On Windsor that produced eight pieces of
## "land" lying inside the road, six of them wedges across the mouths of side
## streets, each drawn with a kerb line around it: the map read as one long road
## whose turnings were painted shut. Nothing caught it, because the rule in
## force asked only whether the FINAL region contained a hole, and by then every
## hole had been cut open again.
##
## So the question is asked where the damage shows instead. Two ways, because
## either alone can pass while the map is wrong:
##
## - Drive into every junction. A point on each arm's centreline, just inside
##   the widest kerb at that junction, has to be on the asphalt and in neither
##   region. A wedge across a mouth fails this.
## - Look at every piece of both regions. No piece may lie inside the road at
##   all. A stray piece somewhere no junction probe happens to land fails this.
##
## Both maps, because the fictional one is where the numbers are known and the
## imported one is the only one whose roads meet at real angles.

const MAPS: Array[String] = [
	"res://resources/neighbourhood.tres",
	"res://resources/windsor_shadetree.tres",
]

## How far past the widest kerb at a junction the probe stands, world units.
## Far enough in to be past any rounding at the kerb itself, and less than a
## quarter of the truck's length, so a wedge small enough to slip past this is
## smaller than anything the truck could be stopped by.
const PROBE_INSIDE_KERB: float = 20.0

## The sidewalk band MapBuilder puts around every road, repeated here rather
## than read from it: this file asks what the geometry says, and MapBuilder is
## a Node2D that a unit test has no business instantiating.
const SIDEWALK_WIDTH: float = 34.0


func test_every_junction_arm_is_open_asphalt() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		assert_true(map != null, "%s loads as a MapDefinition" % path)
		if map == null:
			continue

		var graph: RoadGraph = RoadGraph.build(map)
		var slabs: Array[PackedVector2Array] = MapGeometry.road_slabs(graph)
		var kerb_region: Array[PackedVector2Array] = MapGeometry.region_outside_roads(
			graph, map.world_bounds, 0.0
		)
		var lot_region: Array[PackedVector2Array] = MapGeometry.region_outside_roads(
			graph, map.world_bounds, SIDEWALK_WIDTH
		)

		var arms: int = 0
		var off_asphalt: Array[String] = []
		var in_land: Array[String] = []
		for node in graph.junction_nodes():
			for edge_index in graph.incident_edges[node]:
				arms += 1
				var probe: Vector2 = _probe_point(graph, node, int(edge_index))
				if not _inside_any(slabs, probe):
					off_asphalt.append(str(probe))
				elif _inside_region(kerb_region, probe) or _inside_region(lot_region, probe):
					in_land.append(str(probe))

		assert_true(arms > 0, "%s has junctions to check (%d arms)" % [map.map_id, arms])
		assert_eq(
			off_asphalt.size(), 0,
			"%s: every one of %d junction arms is asphalt %.0f units inside the kerb%s"
				% [map.map_id, arms, PROBE_INSIDE_KERB, _first(off_asphalt)]
		)
		assert_eq(
			in_land.size(), 0,
			"%s: no junction arm has kerb, sidewalk or yard drawn across it%s"
				% [map.map_id, _first(in_land)]
		)


func test_no_piece_of_either_region_lies_inside_the_road() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		if map == null:
			continue

		var graph: RoadGraph = RoadGraph.build(map)
		var slabs: Array[PackedVector2Array] = MapGeometry.road_slabs(graph)

		for grow in [0.0, SIDEWALK_WIDTH]:
			var region: Array[PackedVector2Array] = MapGeometry.region_outside_roads(
				graph, map.world_bounds, grow
			)
			var wedges: Array[String] = []
			for piece in region:
				if _piece_is_inside_the_road(piece, slabs):
					wedges.append("%s (area %.0f)" % [
						str(MapGeometry.polygon_centroid(piece)), MapGeometry.polygon_area(piece),
					])
			assert_eq(
				wedges.size(), 0,
				"%s: no piece of the region grown by %.0f sits inside the road (%d pieces)%s"
					% [map.map_id, grow, region.size(), _first(wedges)]
			)
			assert_false(
				MapGeometry.has_holes(region),
				"%s: the region grown by %.0f came out without holes" % [map.map_id, grow]
			)


## A point on one arm's centreline, PROBE_INSIDE_KERB past the widest kerb at
## the junction, so a narrow side street is probed beyond the wide road it
## joins rather than beyond its own edge. Never past the far end of a short
## arm.
func _probe_point(graph: RoadGraph, node: int, edge_index: int) -> Vector2:
	var edge: Dictionary = graph.edges[edge_index]
	var other: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
	var here: Vector2 = graph.positions[node]
	var direction: Vector2 = (graph.positions[other] - here).normalized()

	var widest: float = 0.0
	for incident in graph.incident_edges[node]:
		widest = maxf(widest, float(graph.edges[int(incident)]["width"]))
	var out: float = widest / 2.0 + PROBE_INSIDE_KERB
	return here + direction * minf(out, float(edge["length"]) * 0.9)


## Samples the inside of a piece rather than its corners. A real land block's
## corners sit ON the kerb, which counts as inside a slab and would call every
## block a wedge.
func _piece_is_inside_the_road(
	piece: PackedVector2Array, slabs: Array[PackedVector2Array]
) -> bool:
	var centroid: Vector2 = MapGeometry.polygon_centroid(piece)
	var samples: Array[Vector2] = []
	if Geometry2D.is_point_in_polygon(centroid, piece):
		samples.append(centroid)
	for point in piece:
		samples.append(point.lerp(centroid, 0.15))

	var inside: int = 0
	for sample in samples:
		if not Geometry2D.is_point_in_polygon(sample, piece):
			continue
		if not _inside_any(slabs, sample):
			return false
		inside += 1
	return inside > 0


## The slabs are shapes rather than a region: they overlap by design and their
## winding carries no meaning, so a hole test would be wrong here.
func _inside_any(shapes: Array[PackedVector2Array], point: Vector2) -> bool:
	for piece in shapes:
		if Geometry2D.is_point_in_polygon(point, piece):
			return true
	return false


func _inside_region(region: Array[PackedVector2Array], point: Vector2) -> bool:
	for piece in region:
		if Geometry2D.is_polygon_clockwise(piece):
			continue
		if Geometry2D.is_point_in_polygon(point, piece):
			return true
	return false


func _first(offenders: Array[String]) -> String:
	if offenders.is_empty():
		return ""
	return ", first at %s" % offenders[0]
