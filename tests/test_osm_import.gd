extends "res://tests/test_case.gd"
## Checks the imported Windsor resource against the rules the importer claims to
## enforce (Milestone 5 Part 1).
##
## These are checks on the OUTPUT, not on tools/import_osm.gd's internals,
## because the .tres is what the game loads and a resource that is right by
## accident is still right. The importer can be rewritten freely as long as
## these keep passing.
##
## The idempotence claim is not testable from inside the unit runner, which
## cannot re-launch the engine. It is checked by running the importer twice and
## comparing the file hash; the command is in README.md.

const MAP_PATH: String = "res://resources/windsor_shadetree.tres"

## How far a road's stated endpoint may sit from the graph node it welded onto
## before something has gone wrong. RoadGraph welds within half a unit, so a
## whole unit of slack here is generous and still far below any real distance.
const ENDPOINT_TOLERANCE: float = 1.0

## A dead end within this distance of the map edge is a road running off the
## side of the box, which is expected and correct. Anything further in is a
## dead end in the middle of the neighbourhood and has to be a real one.
const BOUNDARY_SLACK: float = 2.0


func _load_map() -> MapDefinition:
	return load(MAP_PATH) as MapDefinition


func test_the_imported_map_loads_at_the_current_schema() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "windsor_shadetree.tres must load as a MapDefinition")
	if map == null:
		return
	assert_eq(map.schema_version, MapDefinition.SCHEMA_VERSION, "imported map is at the current schema version")
	assert_true(map.roads.size() > 0, "imported map has roads")
	assert_true(map.buildings.size() > 0, "imported map has buildings")
	assert_true(map.world_bounds.size.x > 0.0 and map.world_bounds.size.y > 0.0, "imported map has a world extent")


## The rule this part exists to prove: a road segment does not simply stop in
## mid air. Every end of every road is a junction where three or more roads
## meet, a continuation where exactly two roads join end to end, or a dead end.
func test_every_road_endpoint_is_a_junction_a_continuation_or_a_dead_end() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	var graph: RoadGraph = RoadGraph.build(map)
	for road in map.roads:
		var points: PackedVector2Array = road["points"]
		for endpoint in [points[0], points[points.size() - 1]]:
			var node: int = graph.nearest_node(endpoint)
			assert_true(node >= 0, "road %s endpoint has a graph node" % road["id"])
			if node < 0:
				continue
			assert_true(
				graph.positions[node].distance_to(endpoint) <= ENDPOINT_TOLERANCE,
				"road %s endpoint %s sits on its graph node" % [road["id"], endpoint]
			)
			var degree: int = graph.incident_edges.get(node, [] as Array[int]).size()
			assert_true(
				degree >= 1,
				"road %s endpoint is attached to at least one road, not isolated" % road["id"]
			)


## The failure the check above cannot see on its own: a road that ends part way
## along another road WITHOUT a node there, which reads as a junction and drives
## as a wall. A genuine dead end is either a cul-de-sac head, well clear of
## every other road, or a road running off the edge of the box.
func test_no_dead_end_is_a_missed_junction() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	var graph: RoadGraph = RoadGraph.build(map)
	var bounds: Rect2 = map.world_bounds
	for node in graph.dead_end_nodes():
		var point: Vector2 = graph.positions[node]
		if _is_on_boundary(point, bounds):
			continue

		var own_edge: Dictionary = graph.edges[graph.incident_edges[node][0]]
		for edge_index in range(graph.edges.size()):
			var edge: Dictionary = graph.edges[edge_index]
			if int(edge["a"]) == node or int(edge["b"]) == node:
				continue
			var a: Vector2 = graph.positions[int(edge["a"])]
			var b: Vector2 = graph.positions[int(edge["b"])]
			var distance: float = point.distance_to(
				Geometry2D.get_closest_point_to_segment(point, a, b)
			)
			assert_true(
				distance > float(edge["width"]) * 0.5,
				"dead end at %s lies on the pavement of another road (%.1f units from its centreline, half width %.1f); it should be a junction" % [
					point, distance, float(edge["width"]) * 0.5
				]
			)
		assert_true(own_edge.size() > 0, "dead end at %s belongs to a road" % point)


## Every feature says where it came from. Without this the map cannot honestly
## distinguish the real streets from the invented fill, which handoff §1 and §7
## require it to do.
func test_every_feature_declares_its_source() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	var groups: Dictionary = {
		"road": map.roads,
		"building": map.buildings,
		"hydrant": map.hydrants,
		"incident candidate": map.incident_candidates,
	}
	for kind in groups:
		for feature in groups[kind]:
			var source: String = String(feature.get("source", ""))
			assert_true(
				source == "osm" or source == "synthetic",
				"%s %s declares source \"osm\" or \"synthetic\" (got \"%s\")" % [
					kind, feature.get("id", "?"), source
				]
			)
			if source == "osm":
				assert_true(
					String(feature.get("osm_id", "")).begins_with("way/")
					or String(feature.get("osm_id", "")).begins_with("node/"),
					"%s %s carries its OpenStreetMap id" % [kind, feature.get("id", "?")]
				)


func test_the_map_records_where_its_data_came_from() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	for key in ["dataset", "licence", "attribution", "copyright_url", "download_date"]:
		assert_true(
			String(map.source_metadata.get(key, "")) != "",
			"source_metadata records \"%s\"" % key
		)
	# The copyright symbol itself, not "(c)". ATTRIBUTION.md records this exact
	# string as the required credit line and the Data and Credits screen prints
	# it verbatim, so all three have to be the same characters.
	assert_eq(
		String(map.source_metadata.get("attribution", "")),
		"© OpenStreetMap contributors",
		"source_metadata carries the required credit line"
	)
	for key in ["min_latitude", "max_latitude", "min_longitude", "max_longitude", "units_per_metre"]:
		assert_true(
			map.geographic_bounds.has(key),
			"geographic_bounds records \"%s\"" % key
		)


func test_incident_candidates_name_buildings_that_exist() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	var building_ids: Dictionary = {}
	for building in map.buildings:
		building_ids[String(building["id"])] = true

	assert_true(map.incident_candidates.size() >= 3, "at least three incident candidates (handoff §7)")
	for candidate in map.incident_candidates:
		assert_true(
			building_ids.has(String(candidate["building_id"])),
			"incident candidate %s names a building that exists" % candidate["id"]
		)


static func _is_on_boundary(point: Vector2, bounds: Rect2) -> bool:
	return (
		absf(point.x - bounds.position.x) <= BOUNDARY_SLACK
		or absf(point.x - (bounds.position.x + bounds.size.x)) <= BOUNDARY_SLACK
		or absf(point.y - bounds.position.y) <= BOUNDARY_SLACK
		or absf(point.y - (bounds.position.y + bounds.size.y)) <= BOUNDARY_SLACK
	)


## The two halves of "the roads are exaggerated and the land is not"
## (Milestone 6 Part 2), asserted separately so a change to either one is a
## deliberate edit and not a drift.
##
## The land scale is 14 units per metre, chosen by measuring Windsor's houses
## and block lengths against Elm Grove's and the truck's own length; the numbers
## are in DEVELOPMENT_STATUS.md and can be taken again with
## tools/measure_scale.gd. A residential street is 280 units wide whatever the
## land scale is, which is Elm Grove's own road width, because that is the
## number the truck was tuned against and the one James said was right.
func test_the_land_is_drawn_at_the_chosen_scale_and_the_roads_are_not() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	assert_almost_eq(
		float(map.geographic_bounds.get("units_per_metre", 0.0)), 14.0, 0.001,
		"the land is projected at 14 world units per metre"
	)
	assert_almost_eq(
		map.world_bounds.size.x, 7000.0, 1.0, "which makes the world 7,000 units across"
	)
	assert_almost_eq(
		map.world_bounds.size.y, 5320.0, 1.0, "and 5,320 down"
	)

	var residential: Array[float] = []
	for road in map.roads:
		if String(road.get("highway", "")) == "residential":
			residential.append(float(road.get("width", 0.0)))
	assert_true(residential.size() > 0, "the map has residential streets to measure")
	for width in residential:
		assert_almost_eq(
			width, 280.0, 0.001,
			"every residential street is Elm Grove's 280 units wide, not 14 x 11 metres"
		)


## A footprint that had to be moved off the pavement says so in the data.
##
## The roads are wider against the land than the survey says, so a few real
## footprints now stand where the pavement is drawn. Those are shrunk about
## their own centre until they clear it, which makes them no longer the shape
## OpenStreetMap recorded, and a flag on the feature is the only thing that
## keeps that distinguishable afterwards.
func test_every_real_building_says_whether_it_was_moved_off_the_road() -> void:
	var map: MapDefinition = _load_map()
	if map == null:
		assert_true(false, "windsor_shadetree.tres must load as a MapDefinition")
		return

	var adjusted: int = 0
	for building in map.buildings:
		if String(building.get("source", "")) != "osm":
			continue
		assert_true(
			building.has("adjusted_for_road"),
			"real building %s records whether it was set back off a road" % building["id"]
		)
		if bool(building.get("adjusted_for_road", false)):
			adjusted += 1

	# Named rather than merely counted: this is a small number today and a large
	# one would mean the road widths and the land scale had drifted apart.
	assert_true(
		adjusted <= 10,
		"at most ten real footprints were set back off a road (%d were)" % adjusted
	)
