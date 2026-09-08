extends SceneTree
## Turns the committed OpenStreetMap extract into a second MapDefinition
## (handoff §7, §11).
##
## Run with:
##   godot --headless --path . --script res://tools/import_osm.gd
##
## Reads data/source/windsor_shadetree_smoketree.json, which is the raw, one
## time Overpass response, and writes resources/windsor_shadetree.tres. The
## game never reads the JSON and never touches the network: the .tres is the
## only thing it loads, exactly as it loads neighbourhood.tres.
##
## Data (c) OpenStreetMap contributors, ODbL. See ATTRIBUTION.md.
##
## The result is NOT an accurate map of Windsor and must never be described as
## one. Road centrelines, building footprints and the fire station are real.
## Road widths, hydrants, lot fill, incident choices and every colour are
## invented. Every feature written carries source "osm" with its OSM id, or
## source "synthetic", so the two can never be confused after the fact.
##
## This script is deterministic. Nothing here is random, nothing reads the
## clock, and every list is ordered before it is used, so running it twice
## produces a byte-identical resource. tests/test_osm_import.gd depends on that.

const SOURCE_PATH: String = "res://data/source/windsor_shadetree_smoketree.json"
const OUTPUT_PATH: String = "res://resources/windsor_shadetree.tres"

const MAP_ID: String = "windsor_shadetree_v1"
const DISPLAY_NAME: String = "Windsor Test Area"

# The bounding box, repeated from the Overpass query so the projection and the
# download can be checked against each other. If these ever disagree with
# data/source/windsor_shadetree_smoketree.overpassql, the projection is wrong.
const CENTRE_LAT: float = 38.5439893
const CENTRE_LON: float = -122.7953823
const MIN_LAT: float = 38.5422777
const MAX_LAT: float = 38.5457009
const MIN_LON: float = -122.7982498
const MAX_LON: float = -122.7925148

## World units per real metre, and the whole reason for the number.
##
## Milestone 5 set this at 25, chosen so that a real 11.0 metre residential
## street came out 275 units wide against the fictional map's 280, and every
## other distance followed from it. James played the result and said the scale
## felt off: the roads were the width he liked, but the truck read as a toy and
## every straight was long. Measuring it says the same thing (tools/
## measure_scale.gd, all in truck lengths):
##
##                      road width   house width   junction spacing
##     Elm Grove              3.11          2.63               9.22
##     Windsor at 25          3.06          3.76              19.52
##
## The road was matched and everything else was not. Real houses are half again
## bigger than Elm Grove's against the same truck and real blocks are more than
## twice as long, which is what makes a straight feel long and the truck feel
## small on it.
##
## So the land is drawn smaller and the ROADS ARE NOT (see
## WIDTH_UNITS_BY_CLASS). 14 units per metre is where the two ratios that were
## wrong come closest to Elm Grove's together: houses land at 0.80 of Elm
## Grove's ratio and junction spacing at 1.19, against 1.43 and 2.12 before.
## Anything smaller shrinks the houses further to bring the blocks in, and
## anything larger leaves the blocks long. The world goes from 12,499 by 9,500
## units to 7,000 by 5,320.
##
## What this deliberately breaks: a metre of Windsor and a metre of its roads
## are no longer the same length. The roads are exaggerated, the land is real.
## That is the rule, and DESIGN.md states it.
const UNITS_PER_METRE: float = 14.0

## World units per metre of ROAD WIDTH, which is Milestone 5's 25 and does not
## move with the land. Only reached by a way that carries its own width or lane
## count; no way in this extract carries either, so in practice
## WIDTH_UNITS_BY_CLASS sets every width on the map.
const ROAD_UNITS_PER_METRE: float = 25.0

## Kerb to kerb width in WORLD UNITS by highway class, used when the way
## carries no width or lanes tag. Not one road in this extract carries either,
## so in practice this table sets every width on the map.
##
## In units rather than metres because the roads are the one thing on this map
## that must not move when the land is drawn smaller (Milestone 6 Part 2). Road
## width is what the truck's speed, turning circle, stream range, hydrant radius
## and camera zoom were tuned against, and it is the number James said was
## right. Every value here is the width Milestone 5 drew at 25 units per metre,
## rounded, except residential, which is nudged from 275 onto Elm Grove's own
## 280 so the street the truck spends its shift on is the same street on both
## maps.
##
## The ordinary American cross sections they came from: two lanes plus parking
## for residential and unclassified, two lanes plus a turn allowance for
## tertiary, four lanes for secondary, a single ramp lane with shoulders for a
## link, and a shared surface for living_street and service.
const WIDTH_UNITS_BY_CLASS: Dictionary = {
	"primary": 400.0,
	"primary_link": 200.0,
	"secondary": 363.0,
	"secondary_link": 213.0,
	"tertiary": 313.0,
	"tertiary_link": 200.0,
	"unclassified": 275.0,
	"residential": 280.0,
	"living_street": 225.0,
	"service": 175.0,
}

## Classes an engine can drive, before the extra test applied to service ways.
const DRIVABLE_CLASSES: Array = [
	"primary", "primary_link", "secondary", "secondary_link",
	"tertiary", "tertiary_link", "unclassified", "residential", "living_street",
]

## Service tags that are never a through road whatever their shape: a driveway
## or a parking aisle is not a street, and importing them would put the truck
## in people's gardens.
const NON_THROUGH_SERVICE: Array = ["driveway", "parking_aisle", "drive-through", "emergency_access"]

## A lane, and the shoulder allowance added to a lanes-derived width, metres.
const LANE_WIDTH_METRES: float = 3.5
const SHOULDER_METRES: float = 2.0

## Fallback width in world units for a drivable class missing from the table
## above.
const DEFAULT_WIDTH_UNITS: float = 280.0

## How far a footprint may be shrunk about its centre to clear a road slab,
## and the step it is tried at. Half is the floor: a house drawn at less than
## half its surveyed size is not that house any more, and dropping it says so
## honestly where drawing a hut would not.
const MIN_ADJUST_SCALE: float = 0.5
const ADJUST_STEP: float = 0.02

## How far past the kerb an incident marker and a hydrant stand, world units.
## Matched to the fictional map, where the marker is on the sidewalk and the
## hydrant is level with the road edge.
const MARKER_STANDOFF: float = 10.0
const HYDRANT_STANDOFF: float = 0.0

## Synthetic lot fill. Frontage is sampled every SAMPLE_METRES along each side
## of each road; a run of at least MIN_RUN_METRES with no real footprint inside
## the band from the kerb out to LOT_DEPTH_METRES gets one synthetic lot.
## How many points across the frontage band's DEPTH are tested before that
## stretch counts as empty. One, the original, misses any house that does not
## happen to contain the band's midline (Milestone 8 Part 1).
const BAND_SAMPLES: int = 5

## Clear ground a synthetic lot must leave around itself, world units, against
## real footprints and against other lots. 20 units is about a fifth of a truck
## length: enough that two roofs never share an edge and read as one building.
const LOT_CLEARANCE_UNITS: float = 20.0

## Overlap, in square world units, below which two footprints count as merely
## touching. Clipper returns hairline slivers where two terraced houses share a
## wall, and a sliver is not a house drawn on a house.
const FOOTPRINT_OVERLAP_EPSILON_AREA: float = 4.0

const FRONTAGE_SAMPLE_METRES: float = 5.0
const FRONTAGE_MIN_RUN_METRES: float = 30.0
const FRONTAGE_SETBACK_METRES: float = 6.0
const LOT_DEPTH_METRES: float = 16.0
const LOT_MAX_LENGTH_METRES: float = 30.0

## Synthetic hydrants. At least MIN_HYDRANTS go down, at junctions, no two
## closer than this, plus one placed near the station whatever the spacing.
const MIN_HYDRANTS: int = 3
const HYDRANT_MIN_SPACING_METRES: float = 90.0
const STATION_HYDRANT_MAX_METRES: float = 60.0

## How many buildings may catch fire, and how far apart they have to be so a
## shift is not three calls to the same corner.
const INCIDENT_CANDIDATES: int = 6
const INCIDENT_MIN_SPACING_METRES: float = 60.0

var _metres_per_degree_latitude: float = 0.0
var _metres_per_degree_longitude: float = 0.0
var _world_bounds: Rect2 = Rect2()
var _log: Array[String] = []


func _initialize() -> void:
	_metres_per_degree_latitude = _metres_per_degree_lat(CENTRE_LAT)
	_metres_per_degree_longitude = _metres_per_degree_lon(CENTRE_LAT)
	_world_bounds = Rect2(
		0.0, 0.0,
		(MAX_LON - MIN_LON) * _metres_per_degree_longitude * UNITS_PER_METRE,
		(MAX_LAT - MIN_LAT) * _metres_per_degree_latitude * UNITS_PER_METRE
	)

	var elements: Array = _read_elements()
	if elements.is_empty():
		quit(1)
		return

	var definition: MapDefinition = _import(elements)
	if definition == null:
		quit(1)
		return

	var error: int = ResourceSaver.save(definition, OUTPUT_PATH)
	if error != OK:
		printerr("could not save %s: error %d" % [OUTPUT_PATH, error])
		quit(1)
		return

	for line in _log:
		print(line)
	print("wrote %s" % OUTPUT_PATH)
	quit(0)


func _note(line: String) -> void:
	_log.append(line)


# ---------------------------------------------------------------------------
# Reading
# ---------------------------------------------------------------------------

func _read_elements() -> Array:
	if not FileAccess.file_exists(SOURCE_PATH):
		printerr("no OpenStreetMap extract at %s" % SOURCE_PATH)
		return []
	var file: FileAccess = FileAccess.open(SOURCE_PATH, FileAccess.READ)
	if file == null:
		printerr("could not open %s (error %d)" % [SOURCE_PATH, FileAccess.get_open_error()])
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("%s is not a JSON object" % SOURCE_PATH)
		return []
	var root: Dictionary = parsed
	var elements: Variant = root.get("elements", null)
	if typeof(elements) != TYPE_ARRAY:
		printerr("%s has no elements array" % SOURCE_PATH)
		return []

	var timestamp: String = String(root.get("osm3s", {}).get("timestamp_osm_base", "unknown"))
	_note("read %d elements from %s (OSM timestamp %s)" % [
		(elements as Array).size(), SOURCE_PATH, timestamp
	])
	return elements


# ---------------------------------------------------------------------------
# Projection: local tangent plane metres from the box, then world units
# ---------------------------------------------------------------------------

## Metres per degree of latitude at a given latitude, WGS84 series. Latitude
## degrees are very nearly constant; longitude degrees are not, which is why
## both are evaluated once at the centre of the box and then treated as flat.
## Over 500 metres the error from doing so is far below one world unit.
static func _metres_per_degree_lat(latitude_degrees: float) -> float:
	var phi: float = deg_to_rad(latitude_degrees)
	return 111132.92 - 559.82 * cos(2.0 * phi) + 1.175 * cos(4.0 * phi) - 0.0023 * cos(6.0 * phi)


static func _metres_per_degree_lon(latitude_degrees: float) -> float:
	var phi: float = deg_to_rad(latitude_degrees)
	return 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi) + 0.118 * cos(5.0 * phi)


## World position of a latitude/longitude. World x runs east from the box's
## west edge and world y runs SOUTH from its north edge, because Godot's y axis
## points down the screen and north has to be up.
func _project(latitude: float, longitude: float) -> Vector2:
	return Vector2(
		(longitude - MIN_LON) * _metres_per_degree_longitude * UNITS_PER_METRE,
		(MAX_LAT - latitude) * _metres_per_degree_latitude * UNITS_PER_METRE
	)


func _metres(units: float) -> float:
	return units / UNITS_PER_METRE


func _units(metres: float) -> float:
	return metres * UNITS_PER_METRE


# ---------------------------------------------------------------------------
# The import itself
# ---------------------------------------------------------------------------

func _import(elements: Array) -> MapDefinition:
	var ways: Array[Dictionary] = []
	var nodes: Array[Dictionary] = []
	for element in elements:
		if typeof(element) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = element
		match String(item.get("type", "")):
			"way": ways.append(item)
			"node": nodes.append(item)
	# Ordered by OSM id so the whole import is reproducible regardless of the
	# order Overpass happened to answer in.
	ways.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
	nodes.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))

	_report_dropped_layers(ways)

	var roads: Array[Dictionary] = _import_roads(ways)
	if roads.is_empty():
		printerr("no drivable roads survived the import")
		return null

	var definition := MapDefinition.new()
	definition.schema_version = MapDefinition.SCHEMA_VERSION
	definition.map_id = MAP_ID
	definition.display_name = DISPLAY_NAME
	definition.world_bounds = _world_bounds
	definition.roads = roads

	var spawn: Dictionary = _choose_station(ways, roads)
	definition.station_spawn_position = spawn["position"]
	definition.station_spawn_heading = spawn["heading"]

	# Anything the truck cannot actually reach from the station is not part of
	# this map. A stub left hanging outside the box, or a service road that only
	# ever touched a way that was dropped, would otherwise pass through as road
	# the player can see and never drive to.
	definition.roads = _keep_reachable_roads(definition)
	if definition.roads.size() < roads.size():
		_note("dropped %d road segment(s) not reachable from the station" % [
			roads.size() - definition.roads.size()
		])

	var graph: RoadGraph = RoadGraph.build(definition)

	definition.buildings = _import_buildings(ways, definition, graph)
	definition.blocks = []
	definition.hydrants = _place_hydrants(definition, graph, spawn["position"])
	definition.incident_candidates = _choose_incidents(definition, graph)

	definition.geographic_bounds = {
		"centre_latitude": CENTRE_LAT,
		"centre_longitude": CENTRE_LON,
		"min_latitude": MIN_LAT,
		"max_latitude": MAX_LAT,
		"min_longitude": MIN_LON,
		"max_longitude": MAX_LON,
		"units_per_metre": UNITS_PER_METRE,
		"metres_per_degree_latitude": _metres_per_degree_latitude,
		"metres_per_degree_longitude": _metres_per_degree_longitude,
		"projection": "local tangent plane, y increases south",
	}
	definition.source_metadata = {
		"dataset": "OpenStreetMap",
		"licence": "Open Data Commons Open Database License (ODbL)",
		"licence_url": "https://opendatacommons.org/licenses/odbl/",
		# The copyright symbol itself, not "(c)". ATTRIBUTION.md records this as
		# the required credit line and the Data and Credits screen prints this
		# exact string, so the two have to be the same characters or the doc is
		# describing something the game does not say.
		"attribution": "© OpenStreetMap contributors",
		"copyright_url": "https://www.openstreetmap.org/copyright",
		"download_date": "2026-09-07",
		"source_file": SOURCE_PATH,
		"query_file": "res://data/source/windsor_shadetree_smoketree.overpassql",
		"importer": "res://tools/import_osm.gd",
		# Player-facing copy: it is printed on the Data and Credits screen word
		# for word. It used to end "Every feature carries its own source field",
		# which is true, is the reason the rest can be trusted, and means nothing
		# to somebody who came to drive a fire truck. It is kept in
		# ATTRIBUTION.md, where the people it is for will read it.
		"accuracy_note": (
			"Not an accurate map of Windsor. Streets and building footprints are"
			+ " from OpenStreetMap; hydrants, some lots and all colours are"
			+ " synthetic."
		),
	}

	_report(definition, graph)
	return definition


## Bridges, tunnels and layered crossings are not expected anywhere in this box
## and nothing in the renderer or the road graph handles them. If any turn up,
## they are dropped rather than flattened into the same surface as the road
## underneath, and the drop is reported rather than left silent.
func _report_dropped_layers(ways: Array[Dictionary]) -> void:
	var dropped: Array[String] = []
	for way in ways:
		var tags: Dictionary = way.get("tags", {})
		if not tags.has("highway"):
			continue
		if tags.has("bridge") or tags.has("tunnel") or tags.has("layer"):
			dropped.append(String(way.get("id", 0)))
	if dropped.is_empty():
		_note("no bridges, tunnels or layer tags in the extract, as expected")
	else:
		_note("DROPPED %d way(s) carrying bridge/tunnel/layer: %s" % [
			dropped.size(), ", ".join(dropped)
		])


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------

func _import_roads(ways: Array[Dictionary]) -> Array[Dictionary]:
	var highways: Array[Dictionary] = []
	for way in ways:
		var tags: Dictionary = way.get("tags", {})
		if not tags.has("highway"):
			continue
		if tags.has("bridge") or tags.has("tunnel") or tags.has("layer"):
			continue
		highways.append(way)

	# Which nodes the unambiguously drivable classes use. A service way counts
	# as a through road only if BOTH its ends land on that network: a service
	# way with one end loose is a driveway or a parking aisle whatever it is
	# tagged, and a service way with neither end on it is not reachable anyway.
	var through_nodes: Dictionary = {}
	for way in highways:
		if not DRIVABLE_CLASSES.has(String(way["tags"]["highway"])):
			continue
		for node_id in way.get("nodes", []):
			through_nodes[int(node_id)] = true

	var kept: Array[Dictionary] = []
	var service_kept: int = 0
	var service_dropped: int = 0
	for way in highways:
		var tags: Dictionary = way["tags"]
		var highway_class: String = String(tags["highway"])
		if DRIVABLE_CLASSES.has(highway_class):
			kept.append(way)
			continue
		if highway_class != "service":
			continue
		if NON_THROUGH_SERVICE.has(String(tags.get("service", ""))):
			service_dropped += 1
			continue
		var node_ids: Array = way.get("nodes", [])
		if node_ids.size() < 2:
			service_dropped += 1
			continue
		if through_nodes.has(int(node_ids[0])) and through_nodes.has(int(node_ids[node_ids.size() - 1])):
			kept.append(way)
			service_kept += 1
		else:
			service_dropped += 1
	_note("service ways: %d kept as through roads, %d dropped" % [service_kept, service_dropped])

	# How many kept ways use each node. A node used twice or more is where two
	# ways meet, and every one of them has to become a break in the polyline or
	# the graph would have two roads passing through each other without a
	# junction between them.
	var node_uses: Dictionary = {}
	for way in kept:
		for node_id in way.get("nodes", []):
			var key: int = int(node_id)
			node_uses[key] = int(node_uses.get(key, 0)) + 1

	var roads: Array[Dictionary] = []
	for way in kept:
		roads.append_array(_split_way(way, node_uses))
	_note("roads: %d way(s) became %d segment(s) split at shared nodes" % [kept.size(), roads.size()])
	return roads


## One OSM way, clipped to the box and cut at every node it shares with another
## way, as a list of road entries. Each entry runs from one junction or dead end
## to the next and may bend in between.
func _split_way(way: Dictionary, node_uses: Dictionary) -> Array[Dictionary]:
	var node_ids: Array = way.get("nodes", [])
	var geometry: Array = way.get("geometry", [])
	if node_ids.size() != geometry.size() or node_ids.size() < 2:
		return []

	var tags: Dictionary = way["tags"]
	var way_id: int = int(way.get("id", 0))
	# A way with no name tag keeps no name, and MapBuilder draws no label for it
	# (Milestone 6 Part 3). It used to be given one made out of its highway
	# class, which put "Unnamed secondary link" across a slip road on the map
	# James was playing. A street sign is the name of a street; there is no
	# street here called that, and an honest map says nothing rather than
	# something invented.
	#
	# A link is never labelled even when the data names it. A slip road carries
	# the name of the road it joins, so labelling it prints that road's name a
	# second time in a place it does not belong.
	var road_name: String = String(tags.get("name", ""))
	if String(tags.get("highway", "")).ends_with("_link"):
		road_name = ""
	var width: float = _road_width_units(tags)

	# Clip first, so a way that leaves the box comes back as one or more runs
	# that stop cleanly on the boundary instead of trailing off the map.
	var runs: Array = _clip_to_box(node_ids, geometry)

	var out: Array[Dictionary] = []
	for run in runs:
		var points: Array = run["points"]
		var ids: Array = run["ids"]
		var start: int = 0
		for i in range(1, points.size()):
			var is_shared: bool = ids[i] >= 0 and int(node_uses.get(ids[i], 0)) >= 2
			if not is_shared and i < points.size() - 1:
				continue
			if i - start < 1:
				continue
			var slice := PackedVector2Array()
			for k in range(start, i + 1):
				slice.append(points[k])
			if _polyline_length(slice) <= RoadGraph.WELD_TOLERANCE:
				start = i
				continue
			out.append({
				"id": "r_osm_%d_%d" % [way_id, out.size()],
				"name": road_name,
				"points": slice,
				"width": width,
				"source": "osm",
				"osm_id": "way/%d" % way_id,
				"highway": String(tags["highway"]),
			})
			start = i
	return out


## The way's geometry as runs of polyline inside the box, cut on the boundary
## where it leaves and rejoined where it comes back.
##
## Clipped per SEGMENT rather than per vertex, which is the only version that
## is actually right: a road can cross the box between two vertices that are
## both outside it, and a vertex-by-vertex filter drops such a road entirely
## without noticing. Old Redwood Highway in this extract is exactly that shape,
## although in its case the crossing is a sliver at the south-west corner under
## a metre long, so it is pruned again immediately as unreachable.
##
## Points created on the boundary carry node id -1: they are not real OSM nodes
## and must never be treated as shared, or two unrelated roads that happen to
## leave the map at the same place would be welded into a junction.
func _clip_to_box(node_ids: Array, geometry: Array) -> Array:
	var points: Array = []
	var ids: Array = []
	for i in range(geometry.size()):
		points.append(_project(float(geometry[i]["lat"]), float(geometry[i]["lon"])))
		ids.append(int(node_ids[i]))

	var runs: Array = []
	var current_points: Array = []
	var current_ids: Array = []

	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var span: Variant = _clip_segment(a, b)
		if span == null:
			if current_points.size() >= 2:
				runs.append({"points": current_points, "ids": current_ids})
			current_points = []
			current_ids = []
			continue

		var t0: float = span[0]
		var t1: float = span[1]
		if current_points.is_empty() or t0 > 0.0:
			# Either the first piece of a run, or the road has come back into
			# the box after being outside, which starts a new one.
			if current_points.size() >= 2:
				runs.append({"points": current_points, "ids": current_ids})
			current_points = [a.lerp(b, t0)]
			current_ids = [ids[i] if t0 <= 0.0 else -1]
		current_points.append(a.lerp(b, t1))
		current_ids.append(ids[i + 1] if t1 >= 1.0 else -1)
		if t1 < 1.0:
			runs.append({"points": current_points, "ids": current_ids})
			current_points = []
			current_ids = []

	if current_points.size() >= 2:
		runs.append({"points": current_points, "ids": current_ids})
	return runs


## The part of segment a-b that lies inside the box, as [t0, t1] along it, or
## null when none of it does. Liang-Barsky: four half-plane tests, exact, and it
## answers the outside-to-outside crossing case that a vertex test cannot.
func _clip_segment(a: Vector2, b: Vector2) -> Variant:
	var low: float = 0.0
	var high: float = 1.0
	var delta: Vector2 = b - a
	var edge_directions: Array[float] = [-delta.x, delta.x, -delta.y, delta.y]
	var edge_distances: Array[float] = [
		a.x - _world_bounds.position.x,
		_world_bounds.position.x + _world_bounds.size.x - a.x,
		a.y - _world_bounds.position.y,
		_world_bounds.position.y + _world_bounds.size.y - a.y,
	]

	for i in range(4):
		var direction: float = edge_directions[i]
		var distance: float = edge_distances[i]
		if is_zero_approx(direction):
			# Parallel to this edge: either wholly inside it or wholly outside.
			if distance < 0.0:
				return null
			continue
		var crossing: float = distance / direction
		if direction < 0.0:
			if crossing > high:
				return null
			low = maxf(low, crossing)
		else:
			if crossing < low:
				return null
			high = minf(high, crossing)

	if low > high:
		return null
	return [low, high]


## Kerb to kerb width in world units: the way's own width tag if it has one,
## else its lane count, else the class table.
##
## A tagged width is a real measurement and so is converted at
## ROAD_UNITS_PER_METRE, the road exaggeration, never at UNITS_PER_METRE, the
## land scale. Using the land scale here would draw a street tagged 11 metres
## at 154 units and one merely CLASSED residential at 280, side by side.
func _road_width_units(tags: Dictionary) -> float:
	if tags.has("width"):
		var metres: float = _parse_width_metres(String(tags["width"]))
		if metres > 0.0:
			return metres * ROAD_UNITS_PER_METRE
	if tags.has("lanes"):
		var lanes: float = String(tags["lanes"]).to_float()
		if lanes >= 1.0:
			return (lanes * LANE_WIDTH_METRES + SHOULDER_METRES) * ROAD_UNITS_PER_METRE
	var highway_class: String = String(tags.get("highway", ""))
	return float(WIDTH_UNITS_BY_CLASS.get(highway_class, DEFAULT_WIDTH_UNITS))


## OSM width values are metres unless they name a unit. Only feet are handled,
## because feet are the only other unit that appears in American data in
## practice; anything else returns 0 and falls through to the class table.
static func _parse_width_metres(raw: String) -> float:
	var text: String = raw.strip_edges().to_lower()
	if text.ends_with("ft") or text.ends_with("'"):
		return text.trim_suffix("ft").trim_suffix("'").strip_edges().to_float() * 0.3048
	if text.ends_with("m"):
		text = text.trim_suffix("m").strip_edges()
	return text.to_float()


static func _polyline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## Every road segment the truck can actually reach from the station, found on
## the graph rather than by trusting the ways to be connected.
func _keep_reachable_roads(definition: MapDefinition) -> Array[Dictionary]:
	var graph: RoadGraph = RoadGraph.build(definition)
	var reachable: Dictionary = graph.reachable_from(definition.station_spawn_position)

	var live_roads: Dictionary = {}
	for edge in graph.edges:
		if reachable.has(int(edge["a"])) and reachable.has(int(edge["b"])):
			live_roads[int(edge["road_index"])] = true

	var kept: Array[Dictionary] = []
	for index in range(definition.roads.size()):
		if live_roads.has(index):
			kept.append(definition.roads[index])
	return kept


# ---------------------------------------------------------------------------
# Station
# ---------------------------------------------------------------------------

## Where the truck starts. A real fire station in the box wins; the spawn is its
## own footprint snapped onto the nearest road, because the truck has to start
## on pavement rather than inside a building. Only if there is no station does
## this invent one, on the widest road near the centre of the box.
func _choose_station(ways: Array[Dictionary], roads: Array[Dictionary]) -> Dictionary:
	var station_centre: Variant = null
	var station_id: String = ""
	for way in ways:
		var tags: Dictionary = way.get("tags", {})
		if String(tags.get("amenity", "")) != "fire_station":
			continue
		var centroid: Variant = _way_centroid(way)
		if centroid == null:
			continue
		var point: Vector2 = centroid
		if not _world_bounds.has_point(point):
			continue
		station_centre = point
		station_id = "way/%d" % int(way.get("id", 0))
		_note("station: real fire station %s (%s) in the box" % [
			station_id, String(tags.get("name", "unnamed"))
		])
		break

	if station_centre == null:
		# No station in the box: put the spawn on the widest road nearest the
		# centre, and mark it invented.
		var centre: Vector2 = _world_bounds.position + _world_bounds.size * 0.5
		var widest: float = 0.0
		for road in roads:
			widest = maxf(widest, float(road["width"]))
		var best_point: Vector2 = centre
		var best_distance: float = INF
		for road in roads:
			if float(road["width"]) < widest - 0.5:
				continue
			var points: PackedVector2Array = road["points"]
			for i in range(points.size() - 1):
				var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(
					centre, points[i], points[i + 1]
				)
				var distance: float = candidate.distance_to(centre)
				if distance < best_distance:
					best_distance = distance
					best_point = candidate
		station_centre = best_point
		station_id = ""
		_note("station: no fire station in the box, synthetic spawn on the widest central road")

	var snapped: Dictionary = _snap_to_road(station_centre, roads)
	return {
		"position": snapped["position"],
		"heading": snapped["heading"],
		"source": "osm" if station_id != "" else "synthetic",
		"osm_id": station_id,
	}


## The nearest point on any road centreline, and a heading along that road.
func _snap_to_road(point: Vector2, roads: Array[Dictionary]) -> Dictionary:
	var best_point: Vector2 = point
	var best_direction: Vector2 = Vector2.RIGHT
	var best_distance: float = INF
	for road in roads:
		var points: PackedVector2Array = road["points"]
		for i in range(points.size() - 1):
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(
				point, points[i], points[i + 1]
			)
			var distance: float = candidate.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best_point = candidate
				best_direction = (points[i + 1] - points[i]).normalized()
	return {"position": best_point, "heading": best_direction.angle()}


func _way_centroid(way: Dictionary) -> Variant:
	var geometry: Array = way.get("geometry", [])
	if geometry.is_empty():
		return null
	var total := Vector2.ZERO
	for point in geometry:
		total += _project(float(point["lat"]), float(point["lon"]))
	return total / float(geometry.size())


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

func _import_buildings(
	ways: Array[Dictionary], definition: MapDefinition, graph: RoadGraph
) -> Array[Dictionary]:
	var buildings: Array[Dictionary] = []
	var clipped_out: int = 0
	var on_road: int = 0
	var adjusted_count: int = 0

	var parts: int = 0
	for way in ways:
		var tags: Dictionary = way.get("tags", {})
		if not tags.has("building"):
			continue
		# A building:part is a piece OF a building, mapped so that a block of
		# flats can carry different heights per wing. Drawn as a footprint in its
		# own right it is a second roof laid on top of the first. This extract
		# has none, so the rule changes nothing today and is here so the next
		# extract cannot introduce the defect silently.
		if tags.has("building:part"):
			parts += 1
			continue
		var polygon: PackedVector2Array = _way_polygon(way)
		if polygon.size() < 3:
			continue

		# Kept whole or not at all. A footprint half outside the box would draw
		# a house sliced off by the fence, and clipping it would invent a wall
		# that is not in the data.
		var inside: bool = true
		for point in polygon:
			if not _world_bounds.has_point(point):
				inside = false
				break
		if not inside:
			clipped_out += 1
			continue

		# A real footprint that overlaps a road slab is a disagreement between the
		# real footprint and this importer's invented road width, and the invented
		# number is the one that must give way rather than the data. Narrowing the
		# road to fit is not on offer: it would silently make a street the truck
		# cannot turn in.
		#
		# Milestone 5 dropped the building. That was tolerable while the roads were
		# real widths and only a handful of footprints touched them, and it is not
		# now: the roads are exaggerated against a smaller world, so a road reaches
		# further into the land than the survey says and takes whole terraces with
		# it. So the house is set back instead, shrunk about its own centre until
		# it clears the pavement, and marked adjusted_for_road so that nothing
		# downstream can mistake it for a footprint as surveyed. One that cannot
		# clear the road at MIN_ADJUST_SCALE of itself is not that house any more
		# and is still dropped.
		var adjusted: bool = false
		if _overlaps_any_road(polygon, definition, graph):
			var inset: PackedVector2Array = _inset_clear_of_roads(polygon, definition, graph)
			if inset.is_empty():
				on_road += 1
				continue
			polygon = inset
			adjusted = true
			adjusted_count += 1

		var osm_id: int = int(way.get("id", 0))
		buildings.append({
			"id": "b_osm_%d" % osm_id,
			"polygon": polygon,
			"body_color": _body_color(osm_id),
			"roof_color": _roof_color(osm_id),
			"source": "osm",
			"osm_id": "way/%d" % osm_id,
			"adjusted_for_road": adjusted,
		})

	_note("buildings: %d imported, %d set back off a road slab, %d dropped for crossing the box edge, %d dropped for overlapping a road slab, %d building:part(s) skipped" % [
		buildings.size(), adjusted_count, clipped_out, on_road, parts
	])

	buildings = _drop_overlapping_footprints(buildings)

	var synthetic: Array[Dictionary] = _synthesize_lots(definition, buildings, graph)
	buildings.append_array(synthetic)
	_note("buildings: %d synthetic lot(s) added on road frontage with no footprints" % synthetic.size())
	return buildings


func _way_polygon(way: Dictionary) -> PackedVector2Array:
	var geometry: Array = way.get("geometry", [])
	var polygon := PackedVector2Array()
	for point in geometry:
		polygon.append(_project(float(point["lat"]), float(point["lon"])))
	# OSM closes an area by repeating its first node; a Godot polygon does not.
	if polygon.size() >= 2 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.01:
		polygon.remove_at(polygon.size() - 1)
	return polygon


## The footprint shrunk about its own centre until it clears every road slab,
## or an empty polygon when it cannot at MIN_ADJUST_SCALE of itself.
##
## Shrinking rather than clipping, because a clipped footprint has a straight
## edge lying exactly along the kerb, which draws a terrace of houses with their
## front walls flush to the road. A house set back reads as a house set back.
##
## Stepped rather than solved: the overlap test is a polygon intersection
## against every road segment, the answer only has to be a scale that clears,
## and ADJUST_STEP of a footprint is a few units.
func _inset_clear_of_roads(
	polygon: PackedVector2Array, definition: MapDefinition, graph: RoadGraph
) -> PackedVector2Array:
	var centroid: Vector2 = _centroid(polygon)
	var scale: float = 1.0 - ADJUST_STEP
	while scale >= MIN_ADJUST_SCALE:
		var shrunk := PackedVector2Array()
		for point in polygon:
			shrunk.append(centroid + (point - centroid) * scale)
		if not _overlaps_any_road(shrunk, definition, graph):
			return shrunk
		scale -= ADJUST_STEP
	return PackedVector2Array()


## True when any part of the polygon lies on the pavement of any road.
func _overlaps_any_road(
	polygon: PackedVector2Array, definition: MapDefinition, graph: RoadGraph
) -> bool:
	for edge in graph.edges:
		var a: Vector2 = graph.positions[int(edge["a"])]
		var b: Vector2 = graph.positions[int(edge["b"])]
		var slab: PackedVector2Array = oriented_rect(a, b, float(edge["width"]))
		if not Geometry2D.intersect_polygons(polygon, slab).is_empty():
			return true
	return false


## The rectangle a straight road segment covers, kerb to kerb, oriented along
## the segment. The one place road pavement is turned into a polygon, shared by
## the importer, the validator and MapBuilder so all three agree exactly.
static func oriented_rect(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var direction: Vector2 = (b - a)
	if direction.length() <= 0.0001:
		return PackedVector2Array()
	direction = direction.normalized()
	var side: Vector2 = Vector2(-direction.y, direction.x) * (width * 0.5)
	return PackedVector2Array([a + side, b + side, b - side, a - side])


## Two real footprints that overlap are a house drawn on top of a house
## (Milestone 8 Part 1). One wholly inside another is a courtyard, an outbuilding
## mapped twice, or a part mapped as a whole; a partial overlap is two surveys
## disagreeing. Either way only one roof can be drawn there, so the larger
## footprint wins and the smaller is dropped, by name, in the notes.
##
## This extract has no such pair, so on today's data this is a no-op and is
## honest about it. It exists because the rule "no two buildings overlap" is
## about to become a validator rule, and a rule the importer cannot satisfy
## would make every future extract a manual repair job.
func _drop_overlapping_footprints(buildings: Array[Dictionary]) -> Array[Dictionary]:
	var areas: Array[float] = []
	var boxes: Array[Rect2] = []
	for building in buildings:
		areas.append(MapGeometry.polygon_area(building["polygon"]))
		boxes.append(_polygon_bounds(building["polygon"]))

	var dropped: Dictionary = {}
	for i in range(buildings.size()):
		if dropped.has(i):
			continue
		for j in range(i + 1, buildings.size()):
			if dropped.has(j) or not boxes[i].intersects(boxes[j]):
				continue
			var shared: float = 0.0
			for piece in Geometry2D.intersect_polygons(
				buildings[i]["polygon"], buildings[j]["polygon"]
			):
				shared += MapGeometry.polygon_area(piece)
			if shared <= FOOTPRINT_OVERLAP_EPSILON_AREA:
				continue
			# The smaller goes, whether it was wholly inside or only partly over.
			var loser: int = j if areas[j] <= areas[i] else i
			dropped[loser] = true
			_note("buildings: dropped %s, overlapping %s by %.0f square units" % [
				String(buildings[loser]["id"]),
				String(buildings[j if loser == i else i]["id"]),
				shared,
			])
			if loser == i:
				break

	if dropped.is_empty():
		_note("buildings: no two real footprints overlap")
		return buildings

	var kept: Array[Dictionary] = []
	for i in range(buildings.size()):
		if not dropped.has(i):
			kept.append(buildings[i])
	_note("buildings: %d real footprint(s) dropped for overlapping another" % dropped.size())
	return kept


## Fills empty road frontage with plain rectangular lots, so a block with no
## OSM footprints along it is not just open ground the player drives past.
##
## Every lot produced is marked synthetic. Nothing here pretends to be a
## building that exists.
##
## A lot may not touch anything (Milestone 8 Part 1). The first version asked
## whether ONE point, the centre of the frontage band, was inside a real
## footprint, and laid a full-depth lot wherever that point was clear. A house
## set back further or nearer than that single sample was invisible to it, so
## twelve of Windsor's synthetic lots were laid straight over real houses: every
## overlapping pair on the map was one synthetic lot on one or more real
## footprints, which is what "houses on top of houses" was. The same single
## point decided whether the lot was inside the world, which is why seven lots
## straddled the left wall with half of each outside the map.
##
## So the band is now sampled across its whole depth, and, whatever the sampling
## concludes, every finished lot is tested as a POLYGON against the real
## footprints, the lots already accepted, the road slabs and the world bounds,
## with a margin. Anything that cannot meet that is dropped rather than moved:
## a lot is invented ground and costs nothing to give up, while moving one would
## put it where no frontage was measured.
func _synthesize_lots(
	definition: MapDefinition, real_buildings: Array[Dictionary], graph: RoadGraph
) -> Array[Dictionary]:
	var sample_step: float = _units(FRONTAGE_SAMPLE_METRES)
	var min_run: float = _units(FRONTAGE_MIN_RUN_METRES)
	var setback: float = _units(FRONTAGE_SETBACK_METRES)
	var depth: float = _units(LOT_DEPTH_METRES)
	var max_length: float = _units(LOT_MAX_LENGTH_METRES)

	var lots: Array[Dictionary] = []
	for edge_index in range(graph.edges.size()):
		var edge: Dictionary = graph.edges[edge_index]
		var a: Vector2 = graph.positions[int(edge["a"])]
		var b: Vector2 = graph.positions[int(edge["b"])]
		var length: float = a.distance_to(b)
		if length < min_run:
			continue
		var direction: Vector2 = (b - a) / length
		var normal := Vector2(-direction.y, direction.x)
		var half_width: float = float(edge["width"]) * 0.5

		for sign_index in range(2):
			var side: Vector2 = normal if sign_index == 0 else -normal
			var run_start: float = -1.0
			var travelled: float = 0.0
			while travelled <= length:
				# Sampled ACROSS the band, not once down the middle of it: a
				# house set back further or nearer than a single mid-band point
				# is invisible to one sample, and that is what laid lots over
				# real houses.
				var occupied: bool = false
				for step in range(BAND_SAMPLES):
					var into: float = (
						half_width + setback
						+ depth * (float(step) + 0.5) / float(BAND_SAMPLES)
					)
					var probe: Vector2 = a + direction * travelled + side * into
					if (
						not _world_bounds.has_point(probe)
						or _point_in_any(probe, real_buildings)
						or _point_in_any_lot(probe, lots)
					):
						occupied = true
						break
				if occupied:
					if run_start >= 0.0 and travelled - run_start >= min_run:
						lots.append_array(_lots_along(
							a, direction, side, half_width + setback, depth,
							run_start, travelled, max_length, lots.size()
						))
					run_start = -1.0
				elif run_start < 0.0:
					run_start = travelled
				travelled += sample_step
			if run_start >= 0.0 and length - run_start >= min_run:
				lots.append_array(_lots_along(
					a, direction, side, half_width + setback, depth,
					run_start, length, max_length, lots.size()
				))

	# A lot is laid out against ONE road, at a setback measured off that road's
	# kerb, and nothing in that says it clears the next road along. It always did
	# while the roads were real widths; once they are exaggerated against a
	# smaller world (Milestone 6 Part 2) two of them ran across a neighbouring
	# street, which the validator caught. A synthetic lot is invented ground and
	# costs nothing to give up, so any that lands on pavement is dropped rather
	# than moved: moving it would put a lot somewhere no frontage was measured.
	# Ids keep the numbers they were given, so a dropped lot leaves a gap rather
	# than renaming its neighbours.
	var clear: Array[Dictionary] = []
	var on_road: int = 0
	var on_building: int = 0
	var on_lot: int = 0
	var outside: int = 0
	for lot in lots:
		var polygon: PackedVector2Array = lot["polygon"]
		if not _polygon_inside_world(polygon):
			outside += 1
			continue
		if _overlaps_any_road(polygon, definition, graph):
			on_road += 1
			continue
		# Grown by the margin, so a lot that merely touches a house or another
		# lot is dropped too: two roofs sharing an edge read as one L-shaped
		# building, which is a different lie from the one being fixed.
		var grown: PackedVector2Array = _grown_polygon(polygon, LOT_CLEARANCE_UNITS)
		if _polygon_hits_any(grown, real_buildings):
			on_building += 1
			continue
		if _polygon_hits_any(grown, clear):
			on_lot += 1
			continue
		clear.append(lot)
	_note(
		"buildings: %d synthetic lot(s) proposed, %d kept; dropped %d on a road, %d on a real footprint, %d on another lot, %d outside the world"
			% [lots.size(), clear.size(), on_road, on_building, on_lot, outside]
	)
	return clear


func _polygon_inside_world(polygon: PackedVector2Array) -> bool:
	for point in polygon:
		if not _world_bounds.has_point(point):
			return false
	return true


static func _grown_polygon(polygon: PackedVector2Array, by: float) -> PackedVector2Array:
	var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(
		polygon, by, Geometry2D.JOIN_SQUARE
	)
	return grown[0] if grown.size() > 0 else polygon


static func _polygon_hits_any(
	polygon: PackedVector2Array, others: Array[Dictionary]
) -> bool:
	for other in others:
		if not Geometry2D.intersect_polygons(polygon, other["polygon"]).is_empty():
			return true
	return false


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var box := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		box = box.expand(point)
	return box


func _lots_along(
	origin: Vector2, direction: Vector2, side: Vector2, offset: float, depth: float,
	from: float, to: float, max_length: float, index_base: int
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var span: float = to - from
	var count: int = maxi(1, int(ceil(span / max_length)))
	var each: float = span / float(count)
	for i in range(count):
		var lot_from: float = from + each * float(i)
		var lot_to: float = lot_from + each
		var near_left: Vector2 = origin + direction * lot_from + side * offset
		var near_right: Vector2 = origin + direction * lot_to + side * offset
		var polygon := PackedVector2Array([
			near_left, near_right, near_right + side * depth, near_left + side * depth,
		])
		var id_seed: int = index_base + out.size()
		out.append({
			"id": "b_syn_%d" % id_seed,
			"polygon": polygon,
			"body_color": _body_color(id_seed * 7919),
			"roof_color": _roof_color(id_seed * 7919),
			"source": "synthetic",
			"osm_id": "",
		})
	return out


static func _point_in_any(point: Vector2, buildings: Array[Dictionary]) -> bool:
	for building in buildings:
		if Geometry2D.is_point_in_polygon(point, building["polygon"]):
			return true
	return false


static func _point_in_any_lot(point: Vector2, lots: Array[Dictionary]) -> bool:
	for lot in lots:
		if Geometry2D.is_point_in_polygon(point, lot["polygon"]):
			return true
	return false


# ---------------------------------------------------------------------------
# Hydrants
# ---------------------------------------------------------------------------

## Real hydrants first. This extract contains none at all, so in practice every
## hydrant on this map is synthetic: one near the station, then junctions
## working outward until there are at least three and the map is covered.
func _place_hydrants(
	definition: MapDefinition, graph: RoadGraph, spawn: Vector2
) -> Array[Dictionary]:
	var hydrants: Array[Dictionary] = []
	# (Real emergency=fire_hydrant nodes would be read here. The Part 0 report
	# records that the box contains none; the branch is kept because the next
	# imported area may well have them.)

	var junctions: Array[int] = graph.junction_nodes()
	# Ordered by distance from the station, so the map is covered outward from
	# where the truck starts and the ordering does not depend on graph internals.
	junctions.sort_custom(func(a, b):
		var da: float = graph.positions[a].distance_squared_to(spawn)
		var db: float = graph.positions[b].distance_squared_to(spawn)
		if is_equal_approx(da, db):
			return a < b
		return da < db
	)

	var spacing: float = _units(HYDRANT_MIN_SPACING_METRES)
	for node in junctions:
		var position: Vector2 = _kerb_position(graph, node)
		var too_close: bool = false
		for existing in hydrants:
			if Vector2(existing["position"]).distance_to(position) < spacing:
				too_close = true
				break
		if too_close:
			continue
		hydrants.append({
			"id": "h_syn_%d" % hydrants.size(),
			"position": position,
			"source": "synthetic",
			"osm_id": "",
		})

	# Handoff §6 asks for one near the station specifically. The junction sweep
	# above may not have put one there, so this is checked rather than assumed.
	var station_limit: float = _units(STATION_HYDRANT_MAX_METRES)
	var has_station_hydrant: bool = false
	for hydrant in hydrants:
		if Vector2(hydrant["position"]).distance_to(spawn) <= station_limit:
			has_station_hydrant = true
			break
	if not has_station_hydrant:
		var near: Dictionary = graph.nearest_road(spawn)
		var offset: float = float(near["width"]) * 0.5 + HYDRANT_STANDOFF
		hydrants.append({
			"id": "h_syn_station",
			"position": _kerb_beside(graph, spawn, offset),
			"source": "synthetic",
			"osm_id": "",
		})

	if hydrants.size() < MIN_HYDRANTS:
		printerr("only %d hydrants placed, handoff §6 needs at least %d" % [
			hydrants.size(), MIN_HYDRANTS
		])
	_note("hydrants: 0 real in the extract, %d synthetic placed" % hydrants.size())
	return hydrants


## A point at the kerb beside a junction: out along one of its roads far enough
## to clear the junction fill, then across to the road edge. A hydrant in the
## middle of a junction would be a hydrant the truck has to park on.
func _kerb_position(graph: RoadGraph, node: int) -> Vector2:
	var edge_indices: Array[int] = graph.incident_edges.get(node, [] as Array[int])
	if edge_indices.is_empty():
		return graph.positions[node]
	var edge: Dictionary = graph.edges[edge_indices[0]]
	var other: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
	var along: Vector2 = (graph.positions[other] - graph.positions[node]).normalized()
	var half_width: float = float(edge["width"]) * 0.5
	var base: Vector2 = graph.positions[node] + along * (half_width * 1.6)
	return base + Vector2(-along.y, along.x) * (half_width + HYDRANT_STANDOFF)


## A point at the kerb beside an arbitrary spot on a road.
func _kerb_beside(graph: RoadGraph, point: Vector2, offset: float) -> Vector2:
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var best_distance: float = INF
	for edge in graph.edges:
		var a: Vector2 = graph.positions[int(edge["a"])]
		var b: Vector2 = graph.positions[int(edge["b"])]
		var distance: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))
		if distance < best_distance:
			best_distance = distance
			best_a = a
			best_b = b
	var direction: Vector2 = (best_b - best_a).normalized()
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, best_a, best_b)
	return closest + Vector2(-direction.y, direction.x) * offset


# ---------------------------------------------------------------------------
# Incident candidates
# ---------------------------------------------------------------------------

## The largest imported buildings that the truck can actually get to, spread out
## so a shift is not three calls to the same street. Largest because a big
## footprint reads as a real destination and gives the stream something to aim
## at; reachable because a fire behind a fence is a fire the player cannot fight.
##
## Real footprints only, unless there are not enough of them. A synthetic lot is
## a rectangle this importer invented to stop a frontage reading as waste
## ground, and the invented ones are systematically bigger than the real houses,
## so ranking the two together by area hands every call to a lot that does not
## exist. Dispatching the player to a real address is the whole point of
## importing real geography.
func _choose_incidents(definition: MapDefinition, graph: RoadGraph) -> Array[Dictionary]:
	var chosen: Array[Dictionary] = _rank_incidents(definition, graph, "osm")
	if chosen.size() < INCIDENT_CANDIDATES:
		_note("only %d real footprint(s) qualified as incident candidates, filling from synthetic lots" % chosen.size())
		chosen.append_array(_rank_incidents(definition, graph, "synthetic", chosen))

	var real_count: int = 0
	for candidate in chosen:
		if String(candidate["source"]) == "osm":
			real_count += 1
	_note("incident candidates: %d chosen (%d on real footprints, %d on synthetic lots)" % [
		chosen.size(), real_count, chosen.size() - real_count
	])
	return chosen


func _rank_incidents(
	definition: MapDefinition, graph: RoadGraph, want_source: String,
	already: Array[Dictionary] = []
) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for building in definition.buildings:
		if String(building.get("source", "")) != want_source:
			continue
		var polygon: PackedVector2Array = building["polygon"]
		var centroid: Vector2 = _centroid(polygon)
		var near: Dictionary = graph.nearest_road(centroid)
		if float(near["distance"]) == INF:
			continue
		# Close enough to the road that the stream reaches from the street.
		var frontage: float = float(near["width"]) * 0.5 + _units(LOT_DEPTH_METRES + 6.0)
		if float(near["distance"]) > frontage:
			continue
		ranked.append({
			"building": building,
			"centroid": centroid,
			"area": absf(_polygon_area(polygon)),
		})

	ranked.sort_custom(func(a, b):
		if is_equal_approx(float(a["area"]), float(b["area"])):
			return String(a["building"]["id"]) < String(b["building"]["id"])
		return float(a["area"]) > float(b["area"])
	)

	var spacing: float = _units(INCIDENT_MIN_SPACING_METRES)
	var chosen: Array[Dictionary] = []
	for entry in ranked:
		if already.size() + chosen.size() >= INCIDENT_CANDIDATES:
			break
		var centroid: Vector2 = entry["centroid"]
		var too_close: bool = false
		for existing in already + chosen:
			if Vector2(existing["position"]).distance_to(centroid) < spacing:
				too_close = true
				break
		if too_close:
			continue
		var building: Dictionary = entry["building"]
		chosen.append({
			"id": "ic_%s" % String(building["id"]),
			"building_id": String(building["id"]),
			"position": _marker_position(centroid, graph),
			"source": String(building.get("source", "synthetic")),
			"osm_id": String(building.get("osm_id", "")),
		})
	return chosen


## Where the destination marker stands: on the frontage between the building and
## the kerb, which is where a driver would actually pull up.
func _marker_position(centroid: Vector2, graph: RoadGraph) -> Vector2:
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	var best_width: float = 0.0
	var best_distance: float = INF
	for edge in graph.edges:
		var a: Vector2 = graph.positions[int(edge["a"])]
		var b: Vector2 = graph.positions[int(edge["b"])]
		var distance: float = centroid.distance_to(
			Geometry2D.get_closest_point_to_segment(centroid, a, b)
		)
		if distance < best_distance:
			best_distance = distance
			best_a = a
			best_b = b
			best_width = float(edge["width"])
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(centroid, best_a, best_b)
	var toward: Vector2 = (centroid - closest)
	if toward.length() <= 0.0001:
		return closest
	return closest + toward.normalized() * (best_width * 0.5 + MARKER_STANDOFF)


static func _centroid(polygon: PackedVector2Array) -> Vector2:
	if polygon.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in polygon:
		total += point
	return total / float(polygon.size())


static func _polygon_area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


# ---------------------------------------------------------------------------
# Colours. Deterministic from an id, so the map is varied without a colour
# being typed per building and without any randomness to defeat idempotence.
# ---------------------------------------------------------------------------

static func _body_color(seed_value: int) -> Color:
	const BODIES: Array = [
		Color(0.80, 0.62, 0.45), Color(0.75, 0.75, 0.70), Color(0.85, 0.80, 0.65),
		Color(0.70, 0.55, 0.45), Color(0.78, 0.72, 0.60), Color(0.82, 0.66, 0.50),
	]
	return BODIES[absi(seed_value) % BODIES.size()]


static func _roof_color(seed_value: int) -> Color:
	const ROOFS: Array = [
		Color(0.55, 0.20, 0.20), Color(0.25, 0.35, 0.55), Color(0.35, 0.45, 0.30),
		Color(0.45, 0.25, 0.20), Color(0.30, 0.30, 0.40), Color(0.40, 0.30, 0.55),
	]
	return ROOFS[absi(seed_value / 3) % ROOFS.size()]


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

func _report(definition: MapDefinition, graph: RoadGraph) -> void:
	var real_buildings: int = 0
	for building in definition.buildings:
		if String(building.get("source", "")) == "osm":
			real_buildings += 1
	var real_hydrants: int = 0
	for hydrant in definition.hydrants:
		if String(hydrant.get("source", "")) == "osm":
			real_hydrants += 1

	var names: Array[String] = []
	var unnamed: int = 0
	for road in definition.roads:
		var road_name: String = String(road["name"])
		if road_name == "":
			unnamed += 1
			continue
		if not names.has(road_name):
			names.append(road_name)
	names.sort()

	var total_length: float = 0.0
	for edge in graph.edges:
		total_length += float(edge["length"])

	_note("scale: %.1f world units per metre" % UNITS_PER_METRE)
	_note("world: %.0f x %.0f units (%.0f x %.0f metres)" % [
		definition.world_bounds.size.x, definition.world_bounds.size.y,
		_metres(definition.world_bounds.size.x), _metres(definition.world_bounds.size.y),
	])
	_note("roads: %d segment(s), %d graph node(s), %d junction(s), %d dead end(s), %.0f units of road" % [
		definition.roads.size(), graph.positions.size(),
		graph.junction_nodes().size(), graph.dead_end_nodes().size(), total_length,
	])
	_note("streets: %s" % ", ".join(names))
	_note("streets: %d segment(s) carry no name and are drawn without a label" % unnamed)
	_note("buildings: %d total, %d real, %d synthetic" % [
		definition.buildings.size(), real_buildings, definition.buildings.size() - real_buildings,
	])
	_note("hydrants: %d total, %d real, %d synthetic" % [
		definition.hydrants.size(), real_hydrants, definition.hydrants.size() - real_hydrants,
	])
	_note("incident candidates: %d" % definition.incident_candidates.size())
	_note("station spawn: %.0f, %.0f facing %.1f degrees" % [
		definition.station_spawn_position.x, definition.station_spawn_position.y,
		rad_to_deg(definition.station_spawn_heading),
	])
