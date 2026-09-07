extends "res://tests/test_case.gd"
## Validates resources/neighbourhood.tres against the geometric rules a
## driveable, reachable map must satisfy (handoff §7, this brief's
## "tests/test_map_definition.gd" section).
##
## Allowances chosen and why:
## - KERB_ALLOWANCE (20.0 world units) on top of a road's own half-width is
##   how far off the actual pavement a hydrant or an incident's front door
##   may sit and still count as "next to the road": enough for a sidewalk
##   plus a couple of truck-widths of margin, not so much that a hydrant on
##   the far side of a whole city block would pass.
## - STATION_HYDRANT_MAX_DISTANCE (300.0 world units) for "a hydrant near
##   the station": the map's full diagonal is about 1720 units, so 300 is
##   clearly "the one right outside", not just "somewhere on the map".

const MAP_PATH: String = "res://resources/neighbourhood.tres"
const KERB_ALLOWANCE: float = 20.0
const STATION_HYDRANT_MAX_DISTANCE: float = 300.0
const MIN_HYDRANTS: int = 3
const MIN_INCIDENT_CANDIDATES: int = 3


func _load_map() -> MapDefinition:
	var res: Resource = load(MAP_PATH)
	return res as MapDefinition


func test_hydrants_are_adjacent_to_a_road() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	for hydrant in map.hydrants:
		var distance: float = _distance_to_nearest_road(hydrant["position"], map.roads)
		var allowed: float = _max_allowed_offroad_distance(hydrant["position"], map.roads)
		assert_true(
			distance <= allowed,
			"hydrant %s is %.1f units from the nearest road centerline, allowed %.1f" % [hydrant["id"], distance, allowed]
		)


func test_incident_candidates_are_adjacent_to_a_road() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	for incident in map.incident_candidates:
		var distance: float = _distance_to_nearest_road(incident["position"], map.roads)
		var allowed: float = _max_allowed_offroad_distance(incident["position"], map.roads)
		assert_true(
			distance <= allowed,
			"incident candidate %s is %.1f units from the nearest road centerline, allowed %.1f" % [incident["id"], distance, allowed]
		)


func test_every_road_is_reachable_from_the_station() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	var reached: Dictionary = _reachable_road_ids(map)
	for road in map.roads:
		var road_id: String = road["id"]
		assert_true(reached.has(road_id), "road %s is not reachable from the station by any chain of touching roads" % road_id)


func test_all_ids_are_unique_and_non_empty() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	var seen: Dictionary = {}
	var duplicate_found: bool = false
	var empty_found: bool = false

	var all_entries: Array = []
	all_entries.append_array(map.roads)
	all_entries.append_array(map.buildings)
	all_entries.append_array(map.hydrants)
	all_entries.append_array(map.incident_candidates)

	for entry in all_entries:
		var id: String = String(entry.get("id", ""))
		if id == "":
			empty_found = true
			continue
		if seen.has(id):
			duplicate_found = true
		seen[id] = true

	assert_false(empty_found, "every road/building/hydrant/incident id must be non-empty")
	assert_false(duplicate_found, "every road/building/hydrant/incident id must be unique across the whole map definition")


func test_incident_candidates_reference_real_buildings() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	var building_ids: Dictionary = {}
	for building in map.buildings:
		building_ids[String(building["id"])] = true

	for incident in map.incident_candidates:
		var building_id: String = String(incident["building_id"])
		assert_true(building_ids.has(building_id), "incident candidate %s names building_id %s, which does not exist" % [incident["id"], building_id])


func test_minimum_counts_and_station_hydrant() -> void:
	var map: MapDefinition = _load_map()
	assert_true(map != null, "neighbourhood.tres must load as a MapDefinition")
	if map == null:
		return

	assert_true(map.hydrants.size() >= MIN_HYDRANTS, "expected at least %d hydrants, found %d" % [MIN_HYDRANTS, map.hydrants.size()])
	assert_true(map.incident_candidates.size() >= MIN_INCIDENT_CANDIDATES, "expected at least %d incident candidates, found %d" % [MIN_INCIDENT_CANDIDATES, map.incident_candidates.size()])

	var closest_distance: float = INF
	for hydrant in map.hydrants:
		var distance: float = map.station_spawn_position.distance_to(hydrant["position"])
		closest_distance = minf(closest_distance, distance)

	assert_true(
		closest_distance <= STATION_HYDRANT_MAX_DISTANCE,
		"expected at least one hydrant within %.1f units of the station spawn, closest was %.1f" % [STATION_HYDRANT_MAX_DISTANCE, closest_distance]
	)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Perpendicular distance from a point to the nearest point on any road's
## centerline, minimised across every road and every segment of each road's
## (possibly multi-point) polyline.
func _distance_to_nearest_road(point: Vector2, roads: Array[Dictionary]) -> float:
	var best: float = INF
	for road in roads:
		var points: PackedVector2Array = road["points"]
		for i in range(points.size() - 1):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
			best = minf(best, point.distance_to(closest))
	return best


## The largest off-road distance that still counts as "adjacent to the
## road": half the width of whichever road is actually nearest, plus the
## fixed kerb allowance.
func _max_allowed_offroad_distance(point: Vector2, roads: Array[Dictionary]) -> float:
	var best_distance: float = INF
	var best_half_width: float = 0.0
	for road in roads:
		var points: PackedVector2Array = road["points"]
		var half_width: float = float(road["width"]) / 2.0
		for i in range(points.size() - 1):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
			var distance: float = point.distance_to(closest)
			if distance < best_distance:
				best_distance = distance
				best_half_width = half_width
	return best_half_width + KERB_ALLOWANCE


## Two roads count as touching/intersecting if any segment of one crosses
## any segment of the other, or if the closest points between two segments
## are within the combined half-widths of the two roads' pavement (catches
## T-junctions and near-touching endpoints without requiring an exact
## geometric crossing).
func _roads_touch(road_a: Dictionary, road_b: Dictionary) -> bool:
	var points_a: PackedVector2Array = road_a["points"]
	var points_b: PackedVector2Array = road_b["points"]
	var combined_half_width: float = (float(road_a["width"]) + float(road_b["width"])) / 2.0

	for i in range(points_a.size() - 1):
		for j in range(points_b.size() - 1):
			var a1: Vector2 = points_a[i]
			var a2: Vector2 = points_a[i + 1]
			var b1: Vector2 = points_b[j]
			var b2: Vector2 = points_b[j + 1]

			var intersection = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if intersection != null:
				return true

			var closest_pair: PackedVector2Array = Geometry2D.get_closest_points_between_segments(a1, a2, b1, b2)
			if closest_pair.size() == 2:
				var distance: float = closest_pair[0].distance_to(closest_pair[1])
				if distance <= combined_half_width:
					return true

	return false


## Flood-fills the road adjacency graph starting from whichever road the
## station spawn point sits nearest to, and returns the set of reached road
## ids as a Dictionary used as a set (id -> true).
func _reachable_road_ids(map: MapDefinition) -> Dictionary:
	var start_id: String = ""
	var start_distance: float = INF
	for road in map.roads:
		var points: PackedVector2Array = road["points"]
		var local_best: float = INF
		for i in range(points.size() - 1):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(map.station_spawn_position, points[i], points[i + 1])
			local_best = minf(local_best, map.station_spawn_position.distance_to(closest))
		if local_best < start_distance:
			start_distance = local_best
			start_id = road["id"]

	var reached: Dictionary = {}
	if start_id == "":
		return reached

	var queue: Array[String] = [start_id]
	reached[start_id] = true

	while not queue.is_empty():
		var current_id: String = queue.pop_back()
		var current_road: Dictionary = _find_road(map.roads, current_id)

		for candidate in map.roads:
			var candidate_id: String = candidate["id"]
			if reached.has(candidate_id):
				continue
			if _roads_touch(current_road, candidate):
				reached[candidate_id] = true
				queue.append(candidate_id)

	return reached


func _find_road(roads: Array[Dictionary], road_id: String) -> Dictionary:
	for road in roads:
		if road["id"] == road_id:
			return road
	return {}
