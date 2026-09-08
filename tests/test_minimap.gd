extends "res://tests/test_case.gd"
## The minimap's world-to-panel mapping (Milestone 9 Part 0c).
##
## The panel is a diagram of the whole neighbourhood, so the one thing that has
## to be right is the mapping: the map's corners land on the corners of the box
## it is drawn in, nothing on the map lands outside that box, and the map is not
## stretched to the panel's aspect on the way.
##
## Checked against BOTH shipped maps, because their aspects differ and the
## letterboxing is exactly the part that behaves differently: Elm Grove is 4:3,
## the same as the panel, so its drawing fills the panel; Windsor is wider than
## it is tall by a different ratio and must come out with a band on two sides
## rather than squashed.

const MinimapScript: GDScript = preload("res://scripts/Minimap.gd")

const WINDSOR: String = "res://resources/windsor_shadetree.tres"
const ELM_GROVE: String = "res://resources/neighbourhood.tres"

## What a corner is allowed to miss its target by, panel pixels. This is
## floating point slack on a mapping made of one multiply and one add, not a
## tolerance for being roughly right.
const CORNER_EPSILON: float = 0.001


## A Minimap outside the tree. _ready() is what normally sets the size, and it
## does not run on a node that was never added, so the size is set here instead:
## everything under test is a pure function of the size and the map bounds.
func _make_minimap(map_path: String) -> Minimap:
	var minimap: Minimap = MinimapScript.new()
	minimap.size = Minimap.PANEL_SIZE
	var definition: MapDefinition = load(map_path)
	minimap.configure(definition, [])
	return minimap


func test_the_four_map_corners_land_on_the_corners_of_the_drawing() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var minimap: Minimap = _make_minimap(map_path)
		var definition: MapDefinition = load(map_path)
		var bounds: Rect2 = definition.world_bounds
		var content: Rect2 = minimap.get_content_rect()

		var corners: Array[Vector2] = [
			bounds.position,
			Vector2(bounds.end.x, bounds.position.y),
			bounds.end,
			Vector2(bounds.position.x, bounds.end.y),
		]
		var expected: Array[Vector2] = [
			content.position,
			Vector2(content.end.x, content.position.y),
			content.end,
			Vector2(content.position.x, content.end.y),
		]
		for index in range(4):
			var got: Vector2 = minimap.world_to_panel(corners[index])
			assert_true(
				got.distance_to(expected[index]) < CORNER_EPSILON,
				"%s: map corner %s lands on the drawing's corner (got %s, wanted %s)" % [
					definition.map_id, corners[index], got, expected[index]
				]
			)
		minimap.free()


func test_the_drawing_fits_inside_the_panel_and_keeps_the_map_aspect() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var minimap: Minimap = _make_minimap(map_path)
		var definition: MapDefinition = load(map_path)
		var bounds: Rect2 = definition.world_bounds
		var content: Rect2 = minimap.get_content_rect()
		var panel := Rect2(Vector2.ZERO, Minimap.PANEL_SIZE)

		assert_true(
			panel.encloses(content),
			"%s: the drawing %s is inside the panel %s" % [definition.map_id, content, panel]
		)
		assert_true(
			content.size.x > 0.0 and content.size.y > 0.0,
			"%s: the drawing has a size (%s)" % [definition.map_id, content.size]
		)
		# Not stretched: the drawn box has the map's own aspect, not the panel's.
		assert_almost_eq(
			content.size.x / content.size.y,
			bounds.size.x / bounds.size.y,
			0.001,
			"%s: the map is letterboxed, not squashed to the panel's shape" % definition.map_id
		)
		# And it fills the panel on whichever axis it is limited by, so the
		# drawing is as large as the panel allows rather than merely inside it.
		var padded := Vector2(
			Minimap.PANEL_SIZE.x - Minimap.PANEL_PADDING * 2.0,
			Minimap.PANEL_SIZE.y - Minimap.PANEL_PADDING * 2.0
		)
		assert_true(
			absf(content.size.x - padded.x) < 0.01 or absf(content.size.y - padded.y) < 0.01,
			"%s: the drawing fills one axis of the panel (%s in %s)" % [
				definition.map_id, content.size, padded
			]
		)
		minimap.free()


func test_the_station_and_every_hydrant_land_inside_the_drawing() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var minimap: Minimap = _make_minimap(map_path)
		var definition: MapDefinition = load(map_path)
		var content: Rect2 = minimap.get_content_rect()
		# Grown by a hair, because a point exactly on the map's own boundary
		# lands exactly on the edge of the drawing and Rect2.has_point excludes
		# its far edges.
		var inside: Rect2 = content.grow(0.01)

		var station: Vector2 = minimap.world_to_panel(definition.station_spawn_position)
		assert_true(
			inside.has_point(station),
			"%s: the station lands inside the drawing (%s in %s)" % [
				definition.map_id, station, content
			]
		)

		for hydrant in definition.hydrants:
			var at: Vector2 = minimap.world_to_panel(Vector2(hydrant["position"]))
			assert_true(
				inside.has_point(at),
				"%s: hydrant %s lands inside the drawing (%s)" % [
					definition.map_id, String(hydrant["id"]), at
				]
			)

		# And every road vertex, which is the thing actually drawn.
		var strays: int = 0
		var worst: String = ""
		for road in definition.roads:
			for point in road["points"]:
				if not inside.has_point(minimap.world_to_panel(point)):
					strays += 1
					worst = String(road["id"])
		assert_eq(
			strays, 0,
			"%s: no road vertex is drawn outside the panel (%d, e.g. %s)" % [
				definition.map_id, strays, worst
			]
		)
		minimap.free()


## North up, and the same way up as the world: a point further north on the map
## is further up the panel, and one further east is further right. A minimap
## that flipped either axis would still pass the corner check on its own.
func test_the_panel_is_north_up_and_the_same_way_round_as_the_world() -> void:
	var minimap: Minimap = _make_minimap(WINDSOR)
	var definition: MapDefinition = load(WINDSOR)
	var bounds: Rect2 = definition.world_bounds

	var centre: Vector2 = minimap.world_to_panel(bounds.get_center())
	var north: Vector2 = minimap.world_to_panel(
		bounds.get_center() - Vector2(0.0, bounds.size.y * 0.25)
	)
	var east: Vector2 = minimap.world_to_panel(
		bounds.get_center() + Vector2(bounds.size.x * 0.25, 0.0)
	)

	assert_true(north.y < centre.y, "north on the map is up the panel (%.1f < %.1f)" % [
		north.y, centre.y
	])
	assert_true(east.x > centre.x, "east on the map is right on the panel (%.1f > %.1f)" % [
		east.x, centre.x
	])
	assert_almost_eq(north.x, centre.x, 0.001, "and going north does not move it sideways")

	minimap.free()


## A minimap that was never given a map draws its panel and nothing else, rather
## than dividing by a zero-sized world. Main configures it on every map load, so
## this is a guard, but it is the guard that decides whether a scene built
## without a map crashes or is merely empty.
func test_a_minimap_with_no_map_maps_everything_to_its_own_centre() -> void:
	var minimap: Minimap = MinimapScript.new()
	minimap.size = Minimap.PANEL_SIZE

	assert_eq(minimap.get_content_rect().size, Vector2.ZERO, "there is no drawing")
	var mapped: Vector2 = minimap.world_to_panel(Vector2(1234.0, 5678.0))
	assert_true(
		is_finite(mapped.x) and is_finite(mapped.y),
		"and a world point still maps to a real place (%s)" % mapped
	)

	minimap.free()


## Zoomed in, the panel follows the engine: the truck lands on the middle of the
## drawing, EXCEPT where the view has been pushed back inside the map's own
## bounds, which is exactly what stops the panel showing ground that is not
## there. Both cases are checked, because a minimap that simply centred on the
## truck would pass a check that only looked at the middle of the map.
func test_zoomed_in_the_engine_is_centred_except_where_the_view_hits_a_map_edge() -> void:
	for map_path in [WINDSOR, ELM_GROVE]:
		var minimap: Minimap = _make_minimap(map_path)
		var definition: MapDefinition = load(map_path)
		var bounds: Rect2 = definition.world_bounds
		var content: Rect2 = minimap.get_content_rect()

		# The deepest level the balance offers.
		var levels: Array = minimap.get_zoom_levels()
		var deepest: float = float(levels[levels.size() - 1])
		assert_true(deepest > 1.0, "there is a level closer than the whole map (%.1f)" % deepest)
		while not is_equal_approx(minimap.get_zoom(), deepest):
			minimap.cycle_zoom()

		# Middle of the map: nothing to clamp against, so the engine is centred.
		minimap.set_truck(bounds.get_center(), 0.0)
		var centred: Vector2 = minimap.world_to_panel(bounds.get_center())
		assert_true(
			centred.distance_to(content.get_center()) < 0.01,
			"%s: at %.0fx the engine in the middle of the map is in the middle of the panel"
				% [definition.map_id, deepest]
				+ " (%s, panel centre %s)" % [centred, content.get_center()]
		)

		# A corner: the view is clamped, so the engine is NOT centred, and the
		# panel is showing map rather than void.
		var corner: Vector2 = bounds.position + Vector2(40.0, 40.0)
		minimap.set_truck(corner, 0.0)
		var at_corner: Vector2 = minimap.world_to_panel(corner)
		assert_true(
			at_corner.distance_to(content.get_center()) > 1.0,
			"%s: in a corner the engine is off centre, because the view was clamped (%s)"
				% [definition.map_id, at_corner]
		)
		assert_true(
			bounds.grow(0.01).encloses(minimap.get_view_rect()),
			"%s: and the view stays inside the map, so no void is drawn (%s in %s)" % [
				definition.map_id, minimap.get_view_rect(), bounds
			]
		)
		assert_true(
			content.grow(0.01).has_point(at_corner),
			"%s: the engine is still on the panel (%s)" % [definition.map_id, at_corner]
		)

		# And the view really is 1/deepest of the map.
		assert_almost_eq(
			minimap.get_view_rect().size.x, bounds.size.x / deepest, 0.01,
			"%s: the view is a %.0fth of the map's width" % [definition.map_id, deepest]
		)

		minimap.free()


## The whole-map level is the level the corner check above is written against,
## and cycling comes back round to it rather than stopping at the end.
func test_the_zoom_cycles_round_and_the_first_level_is_the_whole_map() -> void:
	var minimap: Minimap = _make_minimap(WINDSOR)
	var definition: MapDefinition = load(WINDSOR)
	var levels: Array = minimap.get_zoom_levels()

	assert_almost_eq(
		float(levels[0]), 1.0, 0.0001, "the first level is the whole map"
	)
	assert_true(
		minimap.get_view_rect().is_equal_approx(definition.world_bounds),
		"and at it the panel shows the whole map (%s)" % minimap.get_view_rect()
	)

	for _step in range(levels.size()):
		minimap.cycle_zoom()
	assert_eq(minimap.get_zoom_index(), 0, "cycling all the way round returns to the first")
	assert_true(
		minimap.get_view_rect().is_equal_approx(definition.world_bounds),
		"and the whole map is showing again"
	)

	minimap.free()
