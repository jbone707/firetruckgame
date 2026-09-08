extends "res://tests/test_case.gd"
## Where the street names go (Milestone 6 Part 2).
##
## James played the Windsor map and said the street names were weirdly placed.
## They were: the label sat horizontally on the sidewalk beside the point half
## way along a road, so "Shadetree Drive" read across the kerb of the street it
## named rather than along it, and on a road that bends the midpoint of the
## whole polyline is not on any particular stretch at all.
##
## The rule now is: the middle of that street's longest STRAIGHT segment, on the
## asphalt, turned to the road, and never upside down. Two questions can go
## quietly wrong in that, and both are asked here against both shipped maps:
##
## - Is the label actually on the road? A label pushed off the centreline by
##   too much, or placed from a road's polyline while the asphalt is drawn from
##   the road GRAPH, lands on the grass and nothing else would say so.
## - Does it read the right way up? Half the segments on a real map point west,
##   and the same line drawn from the other end is the same road with the text
##   upside down.

const MAPS: Array[String] = [
	"res://resources/neighbourhood.tres",
	"res://resources/windsor_shadetree.tres",
]


func test_every_label_sits_on_the_asphalt_and_reads_the_right_way_up() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		assert_true(map != null, "%s loads as a MapDefinition" % path)
		if map == null:
			continue

		var graph: RoadGraph = RoadGraph.build(map)
		var slabs: Array[PackedVector2Array] = MapGeometry.road_slabs(graph)
		var placements: Array[Dictionary] = MapBuilder.street_label_placements(map.roads)

		assert_true(
			placements.size() > 0, "%s places at least one street label" % map.map_id
		)

		var off_road: Array[String] = []
		var upside_down: Array[String] = []
		for placement in placements:
			var position: Vector2 = placement["position"]
			var on_asphalt: bool = false
			for slab in slabs:
				if Geometry2D.is_point_in_polygon(position, slab):
					on_asphalt = true
					break
			if not on_asphalt:
				off_road.append("%s at %s" % [placement["text"], position])

			var degrees: float = rad_to_deg(float(placement["rotation"]))
			if degrees <= -90.0 or degrees > 90.0:
				upside_down.append("%s at %.1f deg" % [placement["text"], degrees])

		assert_eq(
			off_road.size(), 0,
			"%s: every label centre is on the asphalt (off road: %s)"
			% [map.map_id, off_road.slice(0, 5)]
		)
		assert_eq(
			upside_down.size(), 0,
			"%s: every label reads the right way up (upside down: %s)"
			% [map.map_id, upside_down.slice(0, 5)]
		)


## One label per street name, not one per way. Windsor's "Shadetree Drive"
## arrives as several ways split at its junctions.
func test_a_street_is_named_once_unless_it_is_long_enough_for_two() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		if map == null:
			continue
		var per_name: Dictionary = {}
		for placement in MapBuilder.street_label_placements(map.roads):
			var text: String = String(placement["text"])
			per_name[text] = int(per_name.get(text, 0)) + 1

		var too_many: Array[String] = []
		for text in per_name:
			if int(per_name[text]) > 2:
				too_many.append("%s x%d" % [text, int(per_name[text])])
		assert_eq(
			too_many.size(), 0,
			"%s: no street is named more than twice (%s)" % [map.map_id, too_many]
		)

		# The two labels on a long street must not land on top of one another.
		var by_name: Dictionary = {}
		for placement in MapBuilder.street_label_placements(map.roads):
			var text: String = String(placement["text"])
			if not by_name.has(text):
				by_name[text] = []
			by_name[text].append(Vector2(placement["position"]))
		var stacked: Array[String] = []
		for text in by_name:
			var positions: Array = by_name[text]
			if positions.size() == 2 and positions[0].distance_to(positions[1]) < 400.0:
				stacked.append(text)
		assert_eq(
			stacked.size(), 0,
			"%s: a street's two labels are well apart (%s)" % [map.map_id, stacked]
		)


## Nameless ways get nothing. On the imported map that also covers slip roads,
## which arrive nameless because tools/import_osm.gd drops the name from
## anything whose highway tag ends in "_link".
func test_nameless_ways_are_never_labelled() -> void:
	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		if map == null:
			continue
		var named: Dictionary = {}
		for road in map.roads:
			var road_name: String = String(road.get("name", "")).strip_edges()
			if road_name != "":
				named[road_name] = true
		for placement in MapBuilder.street_label_placements(map.roads):
			assert_true(
				named.has(String(placement["text"])),
				"%s: label %s names a road that has that name"
				% [map.map_id, placement["text"]]
			)
		assert_true(
			named.size() > 0, "%s has named roads at all" % map.map_id
		)


## The flip rule itself, at the angles where it is decided. Godot's y axis
## points down, so a segment running east is 0 and one running north is -90.
func test_the_readable_rotation_rule_covers_the_whole_circle() -> void:
	var cases: Array = [
		[0.0, 0.0], [45.0, 45.0], [89.0, 89.0], [90.0, 90.0],
		[91.0, -89.0], [135.0, -45.0], [179.0, -1.0], [180.0, 0.0],
		[-45.0, -45.0], [-89.0, -89.0], [-90.0, 90.0], [-135.0, 45.0], [-180.0, 0.0],
	]
	for case in cases:
		assert_almost_eq(
			rad_to_deg(MapBuilder.readable_rotation(deg_to_rad(float(case[0])))),
			float(case[1]), 0.001,
			"%.0f degrees reads as %.0f" % [float(case[0]), float(case[1])]
		)

	# Whatever the angle, the answer is in (-90, 90] and draws the same line.
	for degrees in range(-360, 361, 7):
		var angle: float = deg_to_rad(float(degrees))
		var readable: float = MapBuilder.readable_rotation(angle)
		assert_true(
			rad_to_deg(readable) > -90.0 and rad_to_deg(readable) <= 90.0 + 0.001,
			"%d degrees maps into (-90, 90]" % degrees
		)
		assert_almost_eq(
			absf(Vector2.RIGHT.rotated(readable).dot(Vector2.RIGHT.rotated(angle))), 1.0,
			0.001, "%d degrees still draws the same line" % degrees
		)


## A street with no room for its name is left unnamed rather than having the
## text overhang both junctions.
func test_a_segment_too_short_for_its_name_carries_no_label() -> void:
	var short_street: Array[Dictionary] = [{
		"id": "r_short",
		"name": "Quaking Aspen Lane",
		"points": PackedVector2Array([Vector2.ZERO, Vector2(120.0, 0.0)]),
		"width": 280.0,
	}]
	assert_eq(
		MapBuilder.street_label_placements(short_street).size(), 0,
		"a 120 unit stub does not carry an 18 character name"
	)

	var long_street: Array[Dictionary] = [{
		"id": "r_long",
		"name": "Quaking Aspen Lane",
		"points": PackedVector2Array([Vector2.ZERO, Vector2(1200.0, 0.0)]),
		"width": 280.0,
	}]
	assert_eq(
		MapBuilder.street_label_placements(long_street).size(), 1,
		"a 1200 unit street carries it once"
	)
