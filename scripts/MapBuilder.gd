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

const ROAD_COLOR: Color = Color(0.28, 0.28, 0.30)
const SIDEWALK_COLOR: Color = Color(0.72, 0.72, 0.68)

## Width of the concrete band around the edge of every block, world units.
const SIDEWALK_WIDTH: float = 34.0

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
const KERB_COLOR: Color = Color(0.55, 0.55, 0.52)

const Z_ROAD: int = 0
const Z_SIDEWALK: int = 1
const Z_YARD: int = 2
const Z_BUILDING_BODY: int = 3
const Z_BUILDING_ROOF: int = 4
const Z_LABEL: int = 5
const Z_MARKER: int = 6

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

	for road in definition.roads:
		_build_road(roads_root, road)

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

func _build_road(parent: Node2D, road: Dictionary) -> void:
	var points: PackedVector2Array = road["points"]
	var width: float = road["width"]

	var surface := Line2D.new()
	surface.name = "Road_%s" % String(road["id"])
	surface.points = points
	surface.width = width
	surface.default_color = ROAD_COLOR
	surface.joint_mode = Line2D.LINE_JOINT_ROUND
	surface.begin_cap_mode = Line2D.LINE_CAP_ROUND
	surface.end_cap_mode = Line2D.LINE_CAP_ROUND
	surface.z_index = Z_ROAD
	parent.add_child(surface)

	if points.size() < 2:
		return

	# Sidewalks are no longer drawn per road. They belong to the blocks now,
	# which run kerb to kerb, so a sidewalk laid alongside a road would be a
	# second one on top of the block's own and would spill across every
	# junction it passed through.
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

	# The kerb: a darker line right on the block's edge, so the boundary between
	# what can be driven on and what cannot is a visible edge rather than a
	# change of colour the player has to infer.
	var kerb := Line2D.new()
	kerb.name = "Kerb_%s" % block_id
	kerb.points = _rect_polygon(rect)
	kerb.closed = true
	kerb.width = 4.0
	kerb.default_color = KERB_COLOR
	kerb.z_index = Z_SIDEWALK
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
