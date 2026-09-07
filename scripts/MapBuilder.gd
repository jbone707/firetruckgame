extends Node2D
class_name MapBuilder
## Constructs the playable scene from a MapDefinition (handoff §7, §8).
##
## Roads, street name labels and hydrant/incident markers are purely visual and
## carry no collision shape at all. Buildings and the four map-edge walls get
## collision on physics layer 1 ("world_static"), mask 0, which both stops the
## truck and blocks the water stream. Blocks, the filled land between the roads,
## get collision on layer 5 ("world_lot"): solid to the truck, transparent to
## the stream. Clean retro-inspired shapes, built-in drawing (Polygon2D/Line2D)
## and built-in fonts only, no external assets.
##
## The whole map is therefore tiled: road pavement, or block. Nothing between
## the two is drivable.

## Warm, near-black asphalt (Part 2). Every road, and every junction where two
## roads cross, is filled with this exact colour and nothing else, which is
## what makes the network read as one continuous surface: two overlapping
## opaque fills of an identical colour cannot show a seam, whereas the old
## per-road Line2D (translucent-looking at its round joints and caps) showed
## one at every crossing and made junctions read as raised or sunken boxes.
const ASPHALT_COLOR: Color = Color(0.14, 0.13, 0.125)

## Concrete band around every block. Kept clearly lighter than ASPHALT_COLOR
## (it was already lighter than the old road grey; the gap is far bigger now)
## so "road" and "sidewalk" are never a lighting judgement call.
const SIDEWALK_COLOR: Color = Color(0.74, 0.72, 0.67)

## The line where concrete meets asphalt, lighter again than the sidewalk
## itself so the boundary a fire truck must not cross reads as a drawn edge
## rather than a shade difference the player has to infer.
const KERB_COLOR: Color = Color(0.90, 0.87, 0.79)

## Dashed lane marking down the middle of every road. Muted pale yellow, kept
## dimmer than KERB_COLOR so the two kinds of line do not compete for the same
## "this is the important line" read.
const CENTERLINE_COLOR: Color = Color(0.82, 0.77, 0.52)

## Width of the concrete band around the edge of every block, world units.
const SIDEWALK_WIDTH: float = 34.0
const KERB_WIDTH: float = 5.0
const CENTERLINE_WIDTH: float = 6.0

## Dash pattern for the centreline, world units along the road.
const DASH_LENGTH: float = 44.0
const DASH_GAP: float = 32.0

## The physics layer everything that is not a building sits on inside a block:
## sidewalk, garden, fence, kerb. It stops the truck, exactly as a building
## does, but it is deliberately absent from WaterSystem's stream mask, because a
## stream clears a fence and a front lawn and does not clear a house. Without
## that split, filling the blocks in would have made every fire on the map
## unreachable from the street it faces.
const LOT_LAYER: int = 0b10000  # layer 5, world_lot
const ROOF_INSET_SCALE: float = 0.62
const WALL_THICKNESS: float = 40.0
const HYDRANT_COLOR: Color = Color(0.85, 0.05, 0.05)
const INCIDENT_MARKER_COLOR: Color = Color(1.0, 0.65, 0.0)
const LABEL_COLOR: Color = Color(0.95, 0.95, 0.90)

## Draw order, bottom to top. Every drawn node sets exactly one of these.
## Road markings sit directly on the asphalt below them; sidewalk and yard
## are drawn above the road so any antialiased pixel on their shared edge
## resolves to concrete, not tarmac; the kerb is drawn last of the ground
## layers so it sits cleanly on top of that seam, which is the one edge in
## the whole scene that is *supposed* to show, being the line between
## drivable and not.
const Z_ROAD: int = 0
const Z_ROAD_MARKING: int = 1
const Z_SIDEWALK: int = 2
const Z_YARD: int = 3
const Z_KERB: int = 4
const Z_BUILDING_BODY: int = 5
const Z_BUILDING_ROOF: int = 6
const Z_LABEL: int = 7
const Z_MARKER: int = 8

var _definition: MapDefinition = null


func build(definition: MapDefinition) -> void:
	_definition = definition

	for child in get_children():
		child.queue_free()

	var roads_root := Node2D.new()
	roads_root.name = "Roads"
	add_child(roads_root)

	var blocks_root := Node2D.new()
	blocks_root.name = "Blocks"
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

	# Every road in this map is one straight, axis-aligned span (see
	# MapDefinition.create_fictional_neighbourhood), so it can be treated as a
	# single rectangle rather than a polyline. That rectangle is computed once
	# and reused for the asphalt fill, the junction search and the centreline
	# gaps, so all three agree exactly on where each road is.
	var road_rects: Array[Rect2] = []
	for road in definition.roads:
		road_rects.append(_road_rect(road["points"], road["width"]))

	for i in range(definition.roads.size()):
		_build_road_slab(roads_root, definition.roads[i], road_rects[i])

	# A junction is just the overlap of two road rectangles. Filling that
	# overlap with one more opaque ASPHALT_COLOR polygon, drawn after every
	# road slab so it sits on top, is the "opaque intersection square drawn
	# last" approach from the handoff: it guarantees the crossing is a single
	# flat fill with no seam, without having to merge the road polygons.
	var junctions: Array[Rect2] = _find_junctions(road_rects)
	for junction in junctions:
		_build_junction_slab(roads_root, junction)

	for i in range(definition.roads.size()):
		_build_road_markings(roads_root, definition.roads[i], road_rects[i], junctions)
		_build_road_label(roads_root, definition.roads[i])

	for block in definition.blocks:
		_build_block(blocks_root, block)

	for building in definition.buildings:
		_build_building(buildings_root, building)

	# Hydrants and incident candidates are no longer drawn here. Part 4 gives
	# hydrants a real node with an interaction radius, and Part 5 marks only the
	# one call that is actually dispatched. Drawing them here as well would put
	# a second dot under every hydrant and mark three buildings the player has
	# not been sent to. The two _build_*_marker helpers below are kept because
	# they are what a future map preview tool would want.

	_build_edge_walls(walls_root, definition.world_bounds)


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


# ---------------------------------------------------------------------------
# Road, sidewalk and label construction
# ---------------------------------------------------------------------------

## The axis-aligned rectangle a straight road occupies, kerb to kerb. Works
## for any two-point road whose points share an x (a north-south avenue) or a
## share a y (an east-west street), which is every road this map produces.
func _road_rect(points: PackedVector2Array, width: float) -> Rect2:
	var p0: Vector2 = points[0]
	var p1: Vector2 = points[points.size() - 1]
	var half_width: float = width / 2.0
	if is_equal_approx(p0.x, p1.x):
		var top: float = min(p0.y, p1.y)
		return Rect2(p0.x - half_width, top, width, abs(p1.y - p0.y))
	else:
		var left: float = min(p0.x, p1.x)
		return Rect2(left, p0.y - half_width, abs(p1.x - p0.x), width)


## Every place two road rectangles overlap: the sixteen real junctions. Found
## purely from geometry, not from the street/avenue grid constants, so this
## keeps working unchanged if the road layout ever does.
func _find_junctions(road_rects: Array[Rect2]) -> Array[Rect2]:
	var junctions: Array[Rect2] = []
	for i in range(road_rects.size()):
		for j in range(i + 1, road_rects.size()):
			if not road_rects[i].intersects(road_rects[j]):
				continue
			var overlap: Rect2 = road_rects[i].intersection(road_rects[j])
			if overlap.size.x > 0.0 and overlap.size.y > 0.0:
				junctions.append(overlap)
	return junctions


func _build_road_slab(parent: Node2D, road: Dictionary, rect: Rect2) -> void:
	var slab := Polygon2D.new()
	slab.name = "Road_%s" % String(road["id"])
	slab.polygon = _rect_polygon(rect)
	slab.color = ASPHALT_COLOR
	slab.z_index = Z_ROAD
	parent.add_child(slab)


## Drawn after every _build_road_slab call, so within Roads (same parent, same
## z-index) it is later in child order and therefore on top: the fill that
## actually seals each junction into one continuous surface.
func _build_junction_slab(parent: Node2D, junction: Rect2) -> void:
	var slab := Polygon2D.new()
	slab.name = "Junction_%d_%d" % [int(junction.position.x), int(junction.position.y)]
	slab.polygon = _rect_polygon(junction)
	slab.color = ASPHALT_COLOR
	slab.z_index = Z_ROAD
	parent.add_child(slab)


## A rectangle running from a to b, width wide, oriented along a-b. Used for
## the dashed centreline; road slabs use _road_rect/_rect_polygon directly
## since every road is axis-aligned, but this stays general along the road's
## own direction so a dash never needs special-casing per axis.
func _oriented_rect_polygon(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var direction: Vector2 = (b - a).normalized()
	var perpendicular: Vector2 = Vector2(-direction.y, direction.x) * (width / 2.0)
	return PackedVector2Array([
		a + perpendicular, b + perpendicular, b - perpendicular, a - perpendicular,
	])


## The dashed centreline for one road, broken wherever the road crosses
## another one. A junction is filled solid (item 2) precisely so it must never
## carry a lane marking on top; a dash running through it would be the same
## "line crosses a box" bug the kerb fix is also avoiding, in yellow instead
## of concrete.
func _build_road_markings(parent: Node2D, road: Dictionary, rect: Rect2, junctions: Array[Rect2]) -> void:
	var points: PackedVector2Array = road["points"]
	var p0: Vector2 = points[0]
	var p1: Vector2 = points[points.size() - 1]
	var vertical: bool = is_equal_approx(p0.x, p1.x)
	var axis_start: float = min(p0.y, p1.y) if vertical else min(p0.x, p1.x)
	var length: float = rect.size.y if vertical else rect.size.x

	# Every junction this road passes through, as a [start, end] gap along the
	# road's own axis, relative to axis_start.
	var gaps: Array = []
	for junction in junctions:
		if not rect.intersects(junction):
			continue
		var overlap: Rect2 = rect.intersection(junction)
		if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
			continue
		var lo: float = (overlap.position.y if vertical else overlap.position.x) - axis_start
		var hi: float = lo + (overlap.size.y if vertical else overlap.size.x)
		gaps.append([lo, hi])
	gaps.sort_custom(func(a, b): return a[0] < b[0])

	var runs: Array = []
	var cursor: float = 0.0
	for gap in gaps:
		if gap[0] > cursor:
			runs.append([cursor, gap[0]])
		cursor = max(cursor, gap[1])
	if cursor < length:
		runs.append([cursor, length])

	var dash_index: int = 0
	for run in runs:
		var t: float = run[0]
		while t < run[1]:
			var dash_end: float = min(t + DASH_LENGTH, run[1])
			var a: Vector2 = Vector2(p0.x, axis_start + t) if vertical else Vector2(axis_start + t, p0.y)
			var b: Vector2 = Vector2(p0.x, axis_start + dash_end) if vertical else Vector2(axis_start + dash_end, p0.y)
			var dash := Polygon2D.new()
			dash.name = "Centreline_%s_%d" % [String(road["id"]), dash_index]
			dash.polygon = _oriented_rect_polygon(a, b, CENTERLINE_WIDTH)
			dash.color = CENTERLINE_COLOR
			dash.z_index = Z_ROAD_MARKING
			parent.add_child(dash)
			dash_index += 1
			t += DASH_LENGTH + DASH_GAP


func _build_road_label(parent: Node2D, road: Dictionary) -> void:
	var points: PackedVector2Array = road["points"]
	var width: float = road["width"]
	var direction: Vector2 = (points[points.size() - 1] - points[0]).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)

	var label := Label.new()
	label.name = "Label_%s" % String(road["id"])
	label.text = String(road["name"])
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 14)
	label.z_index = Z_LABEL
	var midpoint: Vector2 = (points[0] + points[points.size() - 1]) / 2.0
	var label_offset: float = width / 2.0 + SIDEWALK_WIDTH + 8.0
	label.position = midpoint + perpendicular * label_offset - Vector2(String(road["name"]).length() * 3.5, 8.0)
	parent.add_child(label)


# ---------------------------------------------------------------------------
# Blocks: the land between the roads
# ---------------------------------------------------------------------------

## One block: a concrete sidewalk band around the outside, a garden fill inside
## it, a kerb line where the concrete meets the road, and one collision body
## covering the whole thing on LOT_LAYER.
##
## Filling the blocks in is the point of this part. Before it, the gaps between
## buildings were open ground and the truck could drive between the houses and
## across the back gardens, which is what made the streets read as decoration
## rather than as the road network.
func _build_block(parent: Node2D, block: Dictionary) -> void:
	var rect: Rect2 = block["rect"]
	var block_id: String = String(block["id"])

	var sidewalk := Polygon2D.new()
	sidewalk.name = "Sidewalk_%s" % block_id
	sidewalk.polygon = _rect_polygon(rect)
	sidewalk.color = SIDEWALK_COLOR
	sidewalk.z_index = Z_SIDEWALK
	parent.add_child(sidewalk)

	var yard_rect: Rect2 = rect.grow(-SIDEWALK_WIDTH)
	if yard_rect.size.x > 0.0 and yard_rect.size.y > 0.0:
		var yard := Polygon2D.new()
		yard.name = "Yard_%s" % block_id
		yard.polygon = _rect_polygon(yard_rect)
		yard.color = block["yard_color"]
		yard.z_index = Z_YARD
		parent.add_child(yard)

	# The kerb: a light line right on the block's edge, so the boundary between
	# what can be driven on and what cannot is a visible edge rather than a
	# change of colour the player has to infer. A block's rect is exactly the
	# land between roads (blocks run kerb to kerb, handoff on this file's own
	# comment above), so this line sits exactly on every road edge and, because
	# a block never extends into a junction, it is never drawn across one: the
	# same "break it at intersections" rule item 3 asks for, satisfied by the
	# block geometry itself rather than by special-casing the corners.
	var kerb := Line2D.new()
	kerb.name = "Kerb_%s" % block_id
	kerb.points = _rect_polygon(rect)
	kerb.closed = true
	kerb.width = KERB_WIDTH
	kerb.default_color = KERB_COLOR
	kerb.z_index = Z_KERB
	parent.add_child(kerb)

	var body := StaticBody2D.new()
	body.name = "Lot_%s" % block_id
	body.collision_layer = LOT_LAYER
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = _rect_polygon(rect)
	body.add_child(shape)
	parent.add_child(body)


func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		rect.position + rect.size,
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])


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
	var centroid := Vector2.ZERO
	for p in polygon:
		centroid += p
	centroid /= float(polygon.size())

	var inset := PackedVector2Array()
	for p in polygon:
		inset.append(centroid + (p - centroid) * scale)
	return inset


# ---------------------------------------------------------------------------
# Decorative markers (hydrants and incident candidates). No collision:
# Part 4 builds the interactive hydrant/fire-target areas on their own
# layers; these are purely the map's visual marks.
# ---------------------------------------------------------------------------

func _build_hydrant_marker(parent: Node2D, hydrant: Dictionary) -> void:
	var marker := Polygon2D.new()
	marker.name = "Hydrant_%s" % String(hydrant["id"])
	marker.polygon = _circle_polygon(6.0, 8)
	marker.color = HYDRANT_COLOR
	marker.position = hydrant["position"]
	marker.z_index = Z_MARKER
	parent.add_child(marker)


func _build_incident_marker(parent: Node2D, incident: Dictionary) -> void:
	var marker := Polygon2D.new()
	marker.name = "IncidentMarker_%s" % String(incident["id"])
	marker.polygon = _circle_polygon(5.0, 4)
	marker.color = INCIDENT_MARKER_COLOR
	marker.position = incident["position"]
	marker.rotation = PI / 4.0
	marker.z_index = Z_MARKER
	parent.add_child(marker)


func _circle_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


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
