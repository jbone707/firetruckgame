extends "res://tests/test_case.gd"
## The one building renderer both maps use (Milestone 6 Part 1).
##
## James played the rescaled Windsor map and said the houses were ugly. They
## were: each building was a flat, randomly coloured block wrapped in a thick
## beige ring of the same shape, and the two colours came from two different
## palettes depending on which map you were on, because MapDefinition and
## tools/import_osm.gd each invented their own. Purple and red roofs next to
## one another on a residential street is not a style, it is an absence of one.
##
## So the colour is no longer in the map data at all. MapBuilder picks it from
## one shared palette, from the building's own ID, and this file asks the two
## questions that rule can quietly stop satisfying: is it deterministic, and
## does it only ever return a palette entry. Both are asked against every
## building on both shipped maps rather than against invented IDs, because the
## IDs the maps actually carry ("b_00_1" on one, "w_b_240311707" on the other)
## are the input, and a hash that behaves on one shape of string and collapses
## on another would pass a test written with made-up names.

const MAPS: Array[String] = [
	"res://resources/neighbourhood.tres",
	"res://resources/windsor_shadetree.tres",
]


func test_roof_colours_are_deterministic_and_only_ever_from_the_palette() -> void:
	var total: int = 0
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		assert_true(map != null, "%s loads as a MapDefinition" % path)
		if map == null:
			continue

		var off_palette: Array[String] = []
		var unstable: Array[String] = []
		var used: Dictionary = {}

		for building in map.buildings:
			var id: String = String(building["id"])
			var colour: Color = MapBuilder.roof_color_for(id)
			total += 1
			used[colour] = true
			if not MapBuilder.ROOF_PALETTE.has(colour):
				off_palette.append(id)
			if MapBuilder.roof_color_for(id) != colour:
				unstable.append(id)

		assert_true(
			map.buildings.size() > 0, "%s has buildings to colour" % map.map_id
		)
		assert_eq(
			off_palette.size(), 0,
			"%s: every roof colour is a palette entry (off palette: %s)"
			% [map.map_id, off_palette.slice(0, 5)]
		)
		assert_eq(
			unstable.size(), 0,
			"%s: asking twice gives the same colour (unstable: %s)"
			% [map.map_id, unstable.slice(0, 5)]
		)
		# A hash that returned one entry for every ID would satisfy both rules
		# above and give a street of 30 identical houses.
		assert_true(
			used.size() >= 3,
			"%s uses at least three of the five roof tones (used %d)"
			% [map.map_id, used.size()]
		)
	assert_true(total > 200, "both maps together colour %d buildings" % total)


## The colour must not depend on anything but the ID. Same ID, same colour,
## whichever map it came off and whatever else the building dictionary says.
func test_the_colour_depends_on_the_id_and_nothing_else() -> void:
	assert_eq(
		MapBuilder.roof_color_for("b_00_1"), MapBuilder.roof_color_for("b_00_1"),
		"the same ID gives the same colour"
	)
	assert_true(
		MapBuilder.roof_color_for("b_00_1") != MapBuilder.roof_color_for("b_00_2")
		or MapBuilder.roof_color_for("b_00_1") != MapBuilder.roof_color_for("b_00_3"),
		"neighbouring IDs do not all collapse onto one tone"
	)
	assert_eq(
		MapBuilder.ROOF_PALETTE.size(), 5, "the palette is the five tones it says it is"
	)


## FNV-1a, written out here rather than called, so a change to the hash inside
## MapBuilder shows up as a failure instead of as every house on both maps
## quietly changing colour.
func test_the_id_hash_is_the_stated_one() -> void:
	for text in ["", "a", "b_00_1", "w_b_240311707"]:
		var expected: int = 2166136261
		for byte in text.to_utf8_buffer():
			expected = (expected ^ int(byte)) & 0xFFFFFFFF
			expected = (expected * 16777619) & 0xFFFFFFFF
		assert_eq(
			MapBuilder.stable_hash(text), expected, "FNV-1a of %s" % [text]
		)


## The ridge runs along the footprint's LONGEST axis, not along a world axis,
## and stays inside the roof it is drawn on.
func test_the_ridge_follows_the_longest_axis_and_stays_on_the_roof() -> void:
	# A house twice as wide as it is deep: the ridge runs east-west.
	var wide := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(200.0, 0.0), Vector2(200.0, 100.0), Vector2(0.0, 100.0),
	])
	var ridge: PackedVector2Array = MapBuilder.ridge_line(wide)
	assert_eq(ridge.size(), 2, "a rectangle gets a ridge")
	if ridge.size() == 2:
		assert_almost_eq(
			absf((ridge[1] - ridge[0]).normalized().y), 0.0, 0.001,
			"the ridge of a wide house runs east-west"
		)
		assert_true(
			Geometry2D.is_point_in_polygon(ridge[0], wide)
			and Geometry2D.is_point_in_polygon(ridge[1], wide),
			"both ends of the ridge are on the roof"
		)
		assert_true(
			(ridge[1] - ridge[0]).length() < 200.0,
			"the ridge stops short of both walls"
		)

	# The same house turned 30 degrees: the ridge turns with it.
	var turned := PackedVector2Array()
	for point in wide:
		turned.append((point - Vector2(100.0, 50.0)).rotated(deg_to_rad(30.0)))
	var turned_ridge: PackedVector2Array = MapBuilder.ridge_line(turned)
	assert_eq(turned_ridge.size(), 2, "a turned rectangle gets a ridge")
	if turned_ridge.size() == 2:
		var angle: float = (turned_ridge[1] - turned_ridge[0]).angle()
		assert_almost_eq(
			absf(rad_to_deg(fposmod(angle + PI, PI))), 30.0, 0.5,
			"the ridge turned with the house"
		)


## Every footprint on both maps produces a ridge that lies on it. An imported
## footprint is not a tidy rectangle, and a ridge computed from the longest edge
## of an L-shaped building could easily leave the roof.
func test_every_real_footprint_gets_a_ridge_that_lies_on_it() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		if map == null:
			continue
		var missing: int = 0
		var strayed: Array[String] = []
		for building in map.buildings:
			var polygon: PackedVector2Array = building["polygon"]
			var ridge: PackedVector2Array = MapBuilder.ridge_line(polygon)
			if ridge.size() != 2:
				missing += 1
				continue
			var midpoint: Vector2 = (ridge[0] + ridge[1]) / 2.0
			if not Geometry2D.is_point_in_polygon(midpoint, polygon):
				strayed.append(String(building["id"]))
		assert_eq(missing, 0, "%s: every footprint got a ridge" % map.map_id)
		assert_eq(
			strayed.size(), 0,
			"%s: every ridge lies on its own roof (strayed: %s)"
			% [map.map_id, strayed.slice(0, 5)]
		)
