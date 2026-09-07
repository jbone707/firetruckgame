extends Node2D
class_name MapBuilder
## Constructs the playable scene from a MapDefinition (handoff §7, §8).
##
## Roads, sidewalks, street name labels and hydrant/incident markers are purely
## visual and carry no collision shape at all. Buildings and the four map-edge
## walls get collision on physics layer 1 ("world_static"), mask 0, which both
## stops the truck and blocks the water stream. The LOTS, the land behind the
## fences, get collision on layer 5 ("world_lot"): solid to the truck,
## transparent to the stream. Clean retro-inspired shapes, built-in drawing
## (Polygon2D/Line2D) and built-in fonts only, no external assets.
##
## Drivable: road, and the sidewalk band around it. Not drivable: the land
## behind the fences, and the houses on it. The kerb is a line the player can
## cross; the fence is the one they cannot.
##
## Nothing here assumes a road is straight, axis-aligned or rectangular
## (Milestone 5 Part 1). Every shape on the ground is derived by MapGeometry
## from the road network, so a cul-de-sac, a bend and two streets meeting at 63
## degrees are drawn and collided by the same code that draws a grid. The
## MapDefinition.blocks rectangles are no longer read at all: they cannot
## describe the land between roads that are not axis-aligned, and keeping a
## second path for the maps where they can would mean the fictional map was
## never proving anything about the real one.

## Warm, near-black asphalt (Part 2). Every road slab, and every junction fill,
## is filled with this exact colour and nothing else, which is what makes the
## network read as one continuous surface: two overlapping opaque fills of an
## identical colour cannot show a seam.
const ASPHALT_COLOR: Color = Color(0.14, 0.13, 0.125)

## Concrete band around every road. Kept clearly lighter than ASPHALT_COLOR so
## "road" and "sidewalk" are never a lighting judgement call.
const SIDEWALK_COLOR: Color = Color(0.74, 0.72, 0.67)

## The line where concrete meets asphalt, lighter again than the sidewalk
## itself so the boundary reads as a drawn edge rather than a shade difference
## the player has to infer.
const KERB_COLOR: Color = Color(0.90, 0.87, 0.79)

## Dashed lane marking down the middle of every road. Muted pale yellow, kept
## dimmer than KERB_COLOR so the two kinds of line do not compete.
const CENTERLINE_COLOR: Color = Color(0.82, 0.77, 0.52)

## Width of the concrete band outside the kerb, world units. This is the one
## number that turns the road region into the drivable region.
const SIDEWALK_WIDTH: float = 34.0
const KERB_WIDTH: float = 5.0
const CENTERLINE_WIDTH: float = 6.0

## The garden fence: where the land stops being drivable. Since sidewalks became
## drivable this, and not the kerb, is the edge that stops the truck.
const FENCE_WIDTH: float = 4.0
const FENCE_COLOR: Color = Color(0.42, 0.36, 0.28, 0.95)

## Dash pattern for the centreline, world units along the road.
const DASH_LENGTH: float = 44.0
const DASH_GAP: float = 32.0

## The physics layer the lots sit on, behind their fences. They stop the truck,
## exactly as a building does, but they are deliberately absent from
## WaterSystem's stream mask, because a stream clears a fence and a front lawn
## and does not clear a house. Without that split, filling the land in would
## have made every fire unreachable from the street it faces.
const LOT_LAYER: int = 0b10000  # layer 5, world_lot
const ROOF_INSET_SCALE: float = 0.62
const WALL_THICKNESS: float = 40.0
const LABEL_COLOR: Color = Color(0.95, 0.95, 0.90)

## Draw order, bottom to top. Every drawn node sets exactly one of these.
##
## The sidewalk is the whole drivable region, road included, and the asphalt is
## drawn ON TOP of it rather than beside it. That is what removes the seam at
## the kerb: there is no shared edge between two fills to alias along, only one
## fill ending on another, with the kerb line drawn last over the join. The
## yards sit above the sidewalk for the same reason on the far side.
const Z_SIDEWALK: int = 0
const Z_ROAD: int = 1
const Z_ROAD_MARKING: int = 2
const Z_YARD: int = 3
const Z_KERB: int = 4
const Z_FENCE: int = 5
const Z_BUILDING_BODY: int = 6
const Z_BUILDING_ROOF: int = 7
const Z_LABEL: int = 8
const Z_MARKER: int = 9  # reserved: nothing draws at this level today

var _definition: MapDefinition = null
var _graph: RoadGraph = null
var _lot_region: Array[PackedVector2Array] = []
var _kerb_region: Array[PackedVector2Array] = []


func build(definition: MapDefinition) -> void:
	_definition = definition

	for child in get_children():
		child.queue_free()

	_graph = RoadGraph.build(definition)

	var bounds: Rect2 = definition.world_bounds
	var slabs: Array[PackedVector2Array] = MapGeometry.road_slabs(_graph)
	# The kerb region and the lot region are the same operation run twice, with
	# and without the sidewalk, so the two lines can never disagree about where
	# a road is.
	_kerb_region = MapGeometry.region_outside_roads(_graph, bounds, 0.0)
	_lot_region = MapGeometry.region_outside_roads(_graph, bounds, SIDEWALK_WIDTH)

	var roads_root := Node2D.new()
	roads_root.name = "Roads"
	add_child(roads_root)

	var blocks_root := Node2D.new()
	blocks_root.name = "Lots"
	add_child(blocks_root)

	var buildings_root := Node2D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)

	var markers_root := Node2D.new()
	markers_root.name = "Markers"
	add_child(markers_root)

	var walls_root := Node2D.new()
	walls_root.name = "EdgeWalls"
	add_child(walls_root)

	_build_ground(roads_root, slabs)
	_build_centrelines(roads_root)
	_build_road_labels(roads_root)

	_build_lots(blocks_root, bounds)
	_build_kerbs(blocks_root, bounds)

	for building in definition.buildings:
		_build_building(buildings_root, building)

	# Hydrants and incident candidates are not drawn here. Hydrant is a real node
	# with its own interaction ring, and only the dispatched call is marked, by
	# FireIncident. Markers above is the empty layer they would go back in.

	_build_edge_walls(walls_root, bounds)


func get_station_spawn_position() -> Vector2:
	if _definition == null:
		return Vector2.ZERO
	return _definition.station_spawn_position


func get_station_spawn_heading() -> float:
	if _definition == null:
		return 0.0
	return _definition.station_spawn_heading


func get_world_bounds() -> Rect2:
	if _definition == null:
		return Rect2()
	return _definition.world_bounds


## The road network as a graph. Main prices a call's escalation allowance from
## this, because a route along real roads is the only honest measure of how far
## away a fire is once the roads stop being a grid.
func get_road_graph() -> RoadGraph:
	return _graph


func get_hydrant_definitions() -> Array[Dictionary]:
	if _definition == null:
		return []
	return _definition.hydrants


func get_incident_candidates() -> Array[Dictionary]:
	if _definition == null:
		return []
	return _definition.incident_candidates


func get_building_polygon(building_id: String) -> PackedVector2Array:
	if _definition == null:
		return PackedVector2Array()
	for building in _definition.buildings:
		if building.get("id", "") == building_id:
			return building["polygon"]
	return PackedVector2Array()


## The land behind the fences, as the polygons the fences are drawn from. Read
## by the physics runner, which measures where the truck actually stops against
## where this says the fence is.
func get_lot_region() -> Array[PackedVector2Array]:
	return _lot_region


## The land the asphalt does not cover, as the polygons the kerbs are drawn
## from. Read by the physics runner, which needs to know where the kerb is in
## order to prove that the truck crossed it and was then stopped by something
## further in.
func get_kerb_region() -> Array[PackedVector2Array]:
	return _kerb_region


# ---------------------------------------------------------------------------
# The ground: concrete first, asphalt over it, dashes over that
# ---------------------------------------------------------------------------

## One concrete slab and one asphalt slab per road segment and per junction,
## every one of them opaque and the same colour as its neighbours. Overlapping
## identical opaque fills cannot show a seam, which is why the junctions are
## covered by drawing another fill over them rather than by merging polygons:
## the merge is only needed where a BOUNDARY has to be found, and that is done
## once, by MapGeometry, for the kerb and the fence.
func _build_ground(parent: Node2D, slabs: Array[PackedVector2Array]) -> void:
	for index in range(slabs.size()):
		for grown in Geometry2D.offset_polygon(
			slabs[index], SIDEWALK_WIDTH, Geometry2D.JOIN_SQUARE
		):
			var concrete := Polygon2D.new()
			concrete.name = "Sidewalk_%d" % index
			concrete.polygon = grown
			concrete.color = SIDEWALK_COLOR
			concrete.z_index = Z_SIDEWALK
			parent.add_child(concrete)

	for index in range(slabs.size()):
		var asphalt := Polygon2D.new()
		asphalt.name = "Road_%d" % index
		asphalt.polygon = slabs[index]
		asphalt.color = ASPHALT_COLOR
		asphalt.z_index = Z_ROAD
		parent.add_child(asphalt)


## The dashed centreline of every road, following the road's own bends and
## broken wherever it passes through a junction. A junction is filled solid
## precisely so it must never carry a lane marking across it.
func _build_centrelines(parent: Node2D) -> void:
	var period: float = DASH_LENGTH + DASH_GAP
	for road_index in range(_definition.roads.size()):
		var road: Dictionary = _definition.roads[road_index]
		var points: PackedVector2Array = road["points"]
		var blockers: Array[Dictionary] = _junctions_on_road(road_index)

		var dash_index: int = 0
		var phase: float = 0.0
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var length: float = a.distance_to(b)
			if length <= 0.0:
				continue
			var direction: Vector2 = (b - a) / length

			var travelled: float = 0.0
			while travelled < length:
				var cycle: float = fposmod(phase + travelled, period)
				if cycle >= DASH_LENGTH:
					travelled = minf(travelled + (period - cycle), length)
					continue
				var dash_end: float = minf(travelled + (DASH_LENGTH - cycle), length)
				var from: Vector2 = a + direction * travelled
				var to: Vector2 = a + direction * dash_end
				if dash_end - travelled > 1.0 and not _blocked(from, to, blockers):
					var dash := Polygon2D.new()
					dash.name = "Centreline_%s_%d" % [String(road["id"]), dash_index]
					dash.polygon = MapGeometry.oriented_slab(from, to, CENTERLINE_WIDTH)
					dash.color = CENTERLINE_COLOR
					dash.z_index = Z_ROAD_MARKING
					parent.add_child(dash)
					dash_index += 1
				travelled = dash_end
			phase = fposmod(phase + length, period)


## Every real crossing this road passes through, as a centre and the radius the
## junction fill reaches. Only nodes where three or more segments meet count: a
## node with two is a bend in one road, and breaking the dash at every bend
## would leave an imported road dashed almost nowhere.
func _junctions_on_road(road_index: int) -> Array[Dictionary]:
	var radii: Dictionary = {}
	for edge in _graph.edges:
		if int(edge["road_index"]) != road_index:
			continue
		for key in ["a", "b"]:
			var node: int = int(edge[key])
			if _graph.incident_edges.get(node, []).size() < 3:
				continue
			var radius: float = 0.0
			for incident_index in _graph.incident_edges[node]:
				radius = maxf(radius, float(_graph.edges[int(incident_index)]["width"]) / 2.0)
			radii[node] = radius

	var found: Array[Dictionary] = []
	for node in radii:
		found.append({"centre": _graph.positions[int(node)], "radius": float(radii[node])})
	return found


static func _blocked(from: Vector2, to: Vector2, blockers: Array[Dictionary]) -> bool:
	for blocker in blockers:
		var centre: Vector2 = blocker["centre"]
		var radius: float = blocker["radius"]
		if Geometry2D.get_closest_point_to_segment(centre, from, to).distance_to(centre) <= radius:
			return true
	return false


## One label per street NAME, not per road. An imported street arrives as
## several ways split at its junctions, and labelling each of them would print
## "Shadetree Drive" five times down one street. The longest piece carries it.
func _build_road_labels(parent: Node2D) -> void:
	var longest: Dictionary = {}
	for road in _definition.roads:
		var road_name: String = String(road.get("name", "")).strip_edges()
		if road_name == "":
			continue
		var length: float = _polyline_length(road["points"])
		if not longest.has(road_name) or length > float(longest[road_name]["length"]):
			longest[road_name] = {"length": length, "road": road}

	for road_name in longest:
		var road: Dictionary = longest[road_name]["road"]
		var placement: Dictionary = _polyline_midpoint(road["points"])
		var direction: Vector2 = placement["direction"]
		var perpendicular := Vector2(-direction.y, direction.x)

		var label := Label.new()
		label.name = "Label_%s" % String(road["id"])
		label.text = String(road_name)
		label.add_theme_color_override("font_color", LABEL_COLOR)
		label.add_theme_font_size_override("font_size", 14)
		label.z_index = Z_LABEL
		var offset: float = float(road["width"]) / 2.0 + SIDEWALK_WIDTH + 8.0
		label.position = (
			Vector2(placement["position"]) + perpendicular * offset
			- Vector2(String(road_name).length() * 3.5, 8.0)
		)
		parent.add_child(label)


static func _polyline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## The point half way ALONG a road, and the direction of the road there. The
## straight-line midpoint of the two ends would sit off the road entirely on
## anything that bends.
static func _polyline_midpoint(points: PackedVector2Array) -> Dictionary:
	var half: float = _polyline_length(points) / 2.0
	var travelled: float = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length <= 0.0:
			continue
		if travelled + length >= half:
			var into: float = half - travelled
			return {
				"position": a + (b - a).normalized() * into,
				"direction": (b - a).normalized(),
			}
		travelled += length
	var last: Vector2 = points[points.size() - 1]
	var first: Vector2 = points[0]
	return {
		"position": (first + last) / 2.0,
		"direction": (last - first).normalized() if last != first else Vector2.RIGHT,
	}


# ---------------------------------------------------------------------------
# The lots: the land between the roads
# ---------------------------------------------------------------------------

## Every piece of land the roads and their sidewalks do not cover: drawn as a
## yard, outlined by the fence that stops the truck, and made solid on
## LOT_LAYER.
##
## The collision region has the buildings cut out of it, because a house is
## already solid on layer 1 and covering it a second time on layer 5 would say
## the same thing twice. Where a house stands clear of the fence line, which is
## every house on both of today's maps, that cut leaves the footprint as a hole
## rather than as part of the outline, and a hole is dropped: the house's own
## body is what stops the truck there. The yards and fences are drawn from the
## region WITHOUT that cut, so a fence runs along the street and not around
## every house on it.
func _build_lots(parent: Node2D, bounds: Rect2) -> void:
	for index in range(_lot_region.size()):
		var piece: PackedVector2Array = _lot_region[index]

		var yard := Polygon2D.new()
		yard.name = "Yard_%d" % index
		yard.polygon = piece
		yard.color = _yard_color(MapGeometry.polygon_centroid(piece))
		yard.z_index = Z_YARD
		parent.add_child(yard)

		for run in MapGeometry.boundary_runs(piece, bounds):
			var fence := Line2D.new()
			fence.name = "Fence_%d_%d" % [index, parent.get_child_count()]
			fence.points = run
			fence.width = FENCE_WIDTH
			fence.default_color = FENCE_COLOR
			fence.z_index = Z_FENCE
			parent.add_child(fence)

	var footprints: Array[PackedVector2Array] = []
	for building in _definition.buildings:
		footprints.append(building["polygon"])

	var solid: Array[PackedVector2Array] = MapGeometry.subtract_polygons(
		_lot_region, footprints
	)

	var body := StaticBody2D.new()
	body.name = "Lots"
	body.collision_layer = LOT_LAYER
	body.collision_mask = 0
	for piece in solid:
		if Geometry2D.is_polygon_clockwise(piece):
			continue
		var shape := CollisionPolygon2D.new()
		shape.polygon = piece
		body.add_child(shape)
	parent.add_child(body)


## The kerb, drawn from the road region rather than from the lot region, so it
## sits exactly on the asphalt edge at every angle. Both lines skip the map's
## own boundary: there is no kerb at the edge of the world, there is a wall.
func _build_kerbs(parent: Node2D, bounds: Rect2) -> void:
	for index in range(_kerb_region.size()):
		for run in MapGeometry.boundary_runs(_kerb_region[index], bounds):
			var kerb := Line2D.new()
			kerb.name = "Kerb_%d_%d" % [index, parent.get_child_count()]
			kerb.points = run
			kerb.width = KERB_WIDTH
			kerb.default_color = KERB_COLOR
			kerb.z_index = Z_KERB
			parent.add_child(kerb)


## Deterministic, quietly varied yard colours, taken from where the land is
## rather than from a block index, because derived lots have no index a map
## author ever chose.
static func _yard_color(centroid: Vector2) -> Color:
	var cell: int = int(absf(floorf(centroid.x / 400.0)) + absf(floorf(centroid.y / 400.0)) * 3.0)
	var shift: float = float(cell % 4) * 0.018
	return Color(0.30 + shift, 0.44 + shift * 0.6, 0.28 + shift * 0.4)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

func _build_building(parent: Node2D, building: Dictionary) -> void:
	var polygon: PackedVector2Array = building["polygon"]
	var body_color: Color = building["body_color"]
	var roof_color: Color = building["roof_color"]

	var body := Polygon2D.new()
	body.name = "Body_%s" % String(building["id"])
	body.polygon = polygon
	body.color = body_color
	body.z_index = Z_BUILDING_BODY
	parent.add_child(body)

	var roof := Polygon2D.new()
	roof.name = "Roof_%s" % String(building["id"])
	roof.polygon = _inset_polygon(polygon, ROOF_INSET_SCALE)
	roof.color = roof_color
	roof.z_index = Z_BUILDING_ROOF
	parent.add_child(roof)

	var static_body := StaticBody2D.new()
	static_body.name = "Collision_%s" % String(building["id"])
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	static_body.add_child(shape)
	parent.add_child(static_body)


func _inset_polygon(polygon: PackedVector2Array, scale: float) -> PackedVector2Array:
	if polygon.size() == 0:
		return polygon
	var centroid: Vector2 = MapGeometry.polygon_centroid(polygon)
	var inset := PackedVector2Array()
	for p in polygon:
		inset.append(centroid + (p - centroid) * scale)
	return inset


# ---------------------------------------------------------------------------
# Map-edge walls. Thick enough that a truck at GameBalance's top speed
# (250 units/second) cannot tunnel through between physics steps.
# ---------------------------------------------------------------------------

func _build_edge_walls(parent: Node2D, world_bounds: Rect2) -> void:
	var half_thickness: float = WALL_THICKNESS / 2.0

	_build_wall(
		parent, "Left",
		Vector2(world_bounds.position.x - half_thickness, world_bounds.position.y + world_bounds.size.y / 2.0),
		Vector2(WALL_THICKNESS, world_bounds.size.y + WALL_THICKNESS * 2.0)
	)
	_build_wall(
		parent, "Right",
		Vector2(world_bounds.position.x + world_bounds.size.x + half_thickness, world_bounds.position.y + world_bounds.size.y / 2.0),
		Vector2(WALL_THICKNESS, world_bounds.size.y + WALL_THICKNESS * 2.0)
	)
	_build_wall(
		parent, "Top",
		Vector2(world_bounds.position.x + world_bounds.size.x / 2.0, world_bounds.position.y - half_thickness),
		Vector2(world_bounds.size.x + WALL_THICKNESS * 2.0, WALL_THICKNESS)
	)
	_build_wall(
		parent, "Bottom",
		Vector2(world_bounds.position.x + world_bounds.size.x / 2.0, world_bounds.position.y + world_bounds.size.y + half_thickness),
		Vector2(world_bounds.size.x + WALL_THICKNESS * 2.0, WALL_THICKNESS)
	)


func _build_wall(parent: Node2D, wall_name: String, center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.name = "Wall_%s" % wall_name
	wall.position = center
	wall.collision_layer = 1
	wall.collision_mask = 0

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)

	var visual := Polygon2D.new()
	visual.color = Color(0.15, 0.15, 0.17)
	visual.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0), Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0), Vector2(-size.x / 2.0, size.y / 2.0),
	])
	visual.z_index = Z_ROAD
	wall.add_child(visual)

	parent.add_child(wall)
