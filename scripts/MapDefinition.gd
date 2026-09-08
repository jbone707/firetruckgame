extends Resource
class_name MapDefinition
## Data-only description of a playable neighbourhood (handoff §7).
##
## This resource holds no drawing or gameplay logic. MapBuilder reads one of
## these and constructs the actual scene from it, so a future real-world
## importer only needs to produce another MapDefinition in this same shape.
## All positions on every field below are LOCAL WORLD COORDINATES.
##
## The neighbourhood produced by create_fictional_neighbourhood() below is
## entirely made up. It is not, and must never be described as, an accurate
## map of Windsor, California or any other real place (handoff §1, §7).

## Bumped whenever a field is added, removed or reinterpreted so a loader can
## detect an old save/resource and migrate or reject it.
##
## Version 2 added "blocks" and rescaled the whole neighbourhood.
##
## Version 3 is the real-map milestone. Two changes, both of which a version 2
## resource silently fails to satisfy:
##
## 1. Every feature dictionary in "roads", "buildings", "hydrants" and
##    "incident_candidates" now carries a "source" of either "osm" or
##    "synthetic", and an "osm_id" which is that feature's OpenStreetMap
##    identifier or the empty string. A map that mixes real geography with
##    invented fill has to be able to say which is which, feature by feature,
##    or the honesty rule in handoff §1 and §7 is unenforceable.
## 2. "blocks" may now be empty. On a map whose roads are not axis-aligned the
##    land between them is not a set of rectangles, so MapBuilder derives the
##    block faces from the road network instead. A non-empty "blocks" is still
##    honoured, which is how the fictional neighbourhood keeps its hand-built
##    rectangles.
const SCHEMA_VERSION: int = 3

@export var schema_version: int = SCHEMA_VERSION

## Stable machine identifier for this map, e.g. "fictional_neighbourhood_v2".
@export var map_id: String = ""

## Human-readable name, Title Case, shown to the player if the game ever
## lists more than one map.
@export var display_name: String = ""

## Where the data came from: dataset, licence, attribution, download date, and
## the query and importer that produced this resource. Empty on the fictional
## neighbourhood, which came from nowhere; filled by tools/import_osm.gd. The
## Data and Credits screen reads it, so a map carrying real data cannot be
## shipped without the credit line travelling with it.
@export var source_metadata: Dictionary = {}

## The real-world latitude/longitude box this map corresponds to, plus the
## projection constants used to get from it to world units. Empty on the
## fictional neighbourhood, which corresponds to nowhere.
@export var geographic_bounds: Dictionary = {}

## Playable extent, in local world coordinates. Used for camera limits and
## for placing the four boundary walls.
@export var world_bounds: Rect2 = Rect2()

## Where the truck spawns at the start of a shift.
@export var station_spawn_position: Vector2 = Vector2.ZERO

## Heading (radians) the truck faces at spawn, so it points down a road
## rather than into a wall or sideways across one.
@export var station_spawn_heading: float = 0.0

## Each entry: {id: String, name: String, points: PackedVector2Array,
## width: float, source: String, osm_id: String}. "points" is the road's
## centerline, at least two points. "width" is the full drivable width, from
## kerb to kerb. An imported road is one span between two junctions or dead
## ends and may bend; the road graph is derived from the geometry, so nothing
## here has to also state what connects to what.
@export var roads: Array[Dictionary] = []

## Each entry: {id: String, polygon: PackedVector2Array,
## body_color: Color, roof_color: Color, source: String, osm_id: String}.
##
## "body_color" and "roof_color" ARE NO LONGER READ (Milestone 6 Part 1).
## MapBuilder picks one roof tone from its own shared palette, from the
## building's "id", and derives the outline, the ridge and the eave shadow from
## that. The two fields were written by two different generators from two
## different palettes, which is why the fictional map and the imported one did
## not look like the same game, and why a street could carry a purple roof next
## to a red one. They are kept rather than removed for the same reason "blocks"
## below is: dropping them means a schema version, a regenerated Windsor import
## and a migration, for a field nothing reads.
@export var buildings: Array[Dictionary] = []

## The land between the roads. Each entry: {id: String, rect: Rect2,
## yard_color: Color}. A block runs kerb to kerb, so the block rectangles and
## the road pavement together tile the whole neighbourhood with nothing left
## over. Everything inside a block is solid, sidewalk and yard and lot alike:
## the only drivable surface on the map is road.
##
## NOTHING READS THIS ANY MORE (Milestone 5 Part 1). MapBuilder derives the
## land between the roads on EVERY map by cutting the road network out of the
## map rectangle, because rectangles cannot describe the land between roads that
## are not axis-aligned, and keeping a second path for the maps where they can
## would have meant the fictional map was never proving anything about the real
## one. The physics runner checks that the derived fence lands exactly where
## these rectangles used to put it, which is the last thing they are good for.
##
## The field is kept rather than removed so this is one decision rather than
## two: dropping it means a schema version 4, a regenerated neighbourhood.tres
## and a migration for a resource nobody has a stale copy of. It is dead data,
## it is named as dead data here, and removing it is James's call.
@export var blocks: Array[Dictionary] = []

## Each entry: {id: String, position: Vector2, source: String, osm_id: String}.
@export var hydrants: Array[Dictionary] = []

## Each entry: {id: String, building_id: String, position: Vector2,
## source: String, osm_id: String}. building_id must name an entry in
## "buildings".
@export var incident_candidates: Array[Dictionary] = []


## Builds the one fictional test neighbourhood used for this milestone.
##
## Laid out from the numbers below rather than typed coordinate by coordinate,
## because at this scale there are 36 houses and 9 blocks, and a hand-placed map
## drifts out of agreement with its own rules the first time a road moves. Every
## position here is derived from the road grid, so the grid is the only thing
## that has to be right.
##
## Layout: a 4x4 grid of named streets (four east-west, four north-south)
## enclosing nine blocks. Each block carries four houses, two facing the street
## to its north and two facing the street to its south, with back gardens
## between them. The station sits on Elm Avenue on the west side of the map,
## with a hydrant on the sidewalk beside it.
##
## Scale, and the measurement behind it, is recorded in DEVELOPMENT_STATUS.md:
## roads are ROAD_WIDTH wide, a little over three truck lengths, and at the
## camera's zoom one road spans about a fifth of the screen. The map is
## 4000x3000, so the player sees roughly a third of its width at a time rather
## than nearly all of it.
static func create_fictional_neighbourhood() -> MapDefinition:
	# Kerb to kerb: two lanes plus shoulders, a little over three truck lengths.
	const ROAD_WIDTH: float = 280.0
	const HALF_ROAD: float = ROAD_WIDTH / 2.0

	# East-west streets, north to south, and north-south avenues, west to east.
	const STREET_Y: Array = [250.0, 1080.0, 1910.0, 2740.0]
	const AVENUE_X: Array = [400.0, 1500.0, 2600.0, 3700.0]
	const STREET_NAMES: Array = ["Ash Street", "Birch Street", "Cedar Street", "Dogwood Street"]
	const AVENUE_NAMES: Array = ["Elm Avenue", "Fir Avenue", "Grove Avenue", "Hazel Avenue"]
	const STREET_IDS: Array = ["r_ash", "r_birch", "r_cedar", "r_dogwood"]
	const AVENUE_IDS: Array = ["r_elm", "r_fir", "r_grove", "r_hazel"]

	# How far a house's front wall stands back from the kerb: the sidewalk plus
	# a strip of front garden. Deliberately short, because a fire has to be
	# reachable from the street within GameBalance's stream_range.
	const FRONT_SETBACK: float = 40.0
	const HOUSE_DEPTH: float = 170.0
	const SIDE_MARGIN: float = 60.0
	const HOUSE_GAP: float = 40.0

	# Incident markers stand on the sidewalk, just past the kerb.
	const KERB_STANDOFF: float = 10.0

	# Hydrants stand ON the kerb face, level with the road edge rather than set
	# back onto the sidewalk. Ten units does not sound like much, but a hydrant
	# set back is ten units further from every truck that pulls up to it, and
	# hydrants are the one piece of map furniture the player has to get close to
	# on purpose.
	const HYDRANT_STANDOFF: float = 0.0

	var def := MapDefinition.new()
	def.schema_version = SCHEMA_VERSION
	def.map_id = "fictional_neighbourhood_v2"
	def.display_name = "Elm Grove"
	def.source_metadata = {}
	def.geographic_bounds = {}
	def.world_bounds = Rect2(0.0, 0.0, 4000.0, 3000.0)
	def.station_spawn_position = Vector2(AVENUE_X[0], 700.0)
	def.station_spawn_heading = PI / 2.0 # south, down Elm Avenue

	# Every street runs the full width of the map and every avenue its full
	# height. All sixteen junctions are real crossings, the network is one
	# connected graph with more than one route between any two points, and,
	# because the roads reach the boundary, the land left over is exactly the
	# rectangles between them: no ragged strip along the edge for the truck to
	# escape onto.
	var street_x0: float = def.world_bounds.position.x
	var street_x1: float = def.world_bounds.position.x + def.world_bounds.size.x
	var avenue_y0: float = def.world_bounds.position.y
	var avenue_y1: float = def.world_bounds.position.y + def.world_bounds.size.y

	var roads: Array[Dictionary] = []
	for index in range(STREET_Y.size()):
		roads.append({
			"id": STREET_IDS[index],
			"name": STREET_NAMES[index],
			"points": PackedVector2Array([
				Vector2(street_x0, STREET_Y[index]), Vector2(street_x1, STREET_Y[index]),
			]),
			"width": ROAD_WIDTH,
			"source": "synthetic",
			"osm_id": "",
		})
	for index in range(AVENUE_X.size()):
		roads.append({
			"id": AVENUE_IDS[index],
			"name": AVENUE_NAMES[index],
			"points": PackedVector2Array([
				Vector2(AVENUE_X[index], avenue_y0), Vector2(AVENUE_X[index], avenue_y1),
			]),
			"width": ROAD_WIDTH,
			"source": "synthetic",
			"osm_id": "",
		})
	def.roads = roads

	# Which lots may catch fire. Spread across the map on purpose: a shift
	# should not be three calls to the same corner. Each entry is
	# [row, column, slot], slots 0 and 1 facing the street north of the block
	# and 2 and 3 facing the street south of it.
	var candidate_lots: Array = [
		[0, 0, 1], [0, 2, 2], [1, 1, 3], [2, 0, 0], [2, 2, 1], [1, 2, 2],
	]

	# The land, as the bands of map the roads do not cover. Band 0 is the strip
	# outside the first road and the last band the strip outside the last, so
	# every square unit of the neighbourhood is either road pavement or block,
	# with nothing in between. Only the interior blocks (bands 1 to 3 on both
	# axes) are deep enough to carry houses; the edge strips are verge.
	var x_bands: Array = _bands(AVENUE_X, HALF_ROAD, street_x0, street_x1)
	var y_bands: Array = _bands(STREET_Y, HALF_ROAD, avenue_y0, avenue_y1)

	var blocks: Array[Dictionary] = []
	var buildings: Array[Dictionary] = []
	var candidates: Array[Dictionary] = []

	for band_row in range(y_bands.size()):
		for band_column in range(x_bands.size()):
			var top: float = y_bands[band_row][0]
			var bottom: float = y_bands[band_row][1]
			var left: float = x_bands[band_column][0]
			var right: float = x_bands[band_column][1]
			if right - left <= 0.0 or bottom - top <= 0.0:
				continue

			var row: int = band_row - 1
			var column: int = band_column - 1
			var interior: bool = (
				row >= 0 and row < STREET_Y.size() - 1
				and column >= 0 and column < AVENUE_X.size() - 1
			)

			blocks.append({
				"id": (
					"blk_%d%d" % [row, column] if interior
					else "verge_%d%d" % [band_row, band_column]
				),
				"rect": Rect2(left, top, right - left, bottom - top),
				"yard_color": _yard_color(band_row, band_column),
			})

			if not interior:
				continue

			var house_width: float = ((right - left) - SIDE_MARGIN * 2.0 - HOUSE_GAP) / 2.0

			for slot in range(4):
				var faces_north: bool = slot < 2
				var x0: float = left + SIDE_MARGIN + float(slot % 2) * (house_width + HOUSE_GAP)
				var y0: float = (
					top + FRONT_SETBACK if faces_north
					else bottom - FRONT_SETBACK - HOUSE_DEPTH
				)
				var house_id: String = "b_%d%d_%d" % [row, column, slot]
				buildings.append(_building(
					house_id,
					x0, y0, x0 + house_width, y0 + HOUSE_DEPTH,
					_body_color(row, column, slot), _roof_color(row, column, slot)
				))

				if candidate_lots.has([row, column, slot]):
					# The marker stands on the sidewalk in front of the house,
					# between its front wall and the kerb, which is where a
					# driver would actually pull up.
					var marker_y: float = (
						top - KERB_STANDOFF if faces_north else bottom + KERB_STANDOFF
					)
					candidates.append({
						"id": "ic_%d%d_%d" % [row, column, slot],
						"building_id": house_id,
						"position": Vector2(x0 + house_width * 0.5, marker_y),
						"source": "synthetic",
						"osm_id": "",
					})

	def.blocks = blocks
	def.buildings = buildings
	def.incident_candidates = candidates

	# Hydrants stand at the kerb, spread so no call is a long way from water.
	# h_station is the one outside the station.
	def.hydrants = [
		{"id": "h_station", "position": Vector2(AVENUE_X[0] + HALF_ROAD + HYDRANT_STANDOFF, 700.0), "source": "synthetic", "osm_id": ""},
		{"id": "h_ash_fir", "position": Vector2(1700.0, STREET_Y[0] + HALF_ROAD + HYDRANT_STANDOFF), "source": "synthetic", "osm_id": ""},
		{"id": "h_birch_west", "position": Vector2(800.0, STREET_Y[1] - HALF_ROAD - HYDRANT_STANDOFF), "source": "synthetic", "osm_id": ""},
		{"id": "h_grove_mid", "position": Vector2(AVENUE_X[2] - HALF_ROAD - HYDRANT_STANDOFF, 1500.0), "source": "synthetic", "osm_id": ""},
		{"id": "h_cedar_east", "position": Vector2(3000.0, STREET_Y[2] + HALF_ROAD + HYDRANT_STANDOFF), "source": "synthetic", "osm_id": ""},
		{"id": "h_dogwood_west", "position": Vector2(900.0, STREET_Y[3] - HALF_ROAD - HYDRANT_STANDOFF), "source": "synthetic", "osm_id": ""},
		{"id": "h_hazel_south", "position": Vector2(AVENUE_X[3] - HALF_ROAD - HYDRANT_STANDOFF, 2300.0), "source": "synthetic", "osm_id": ""},
	]

	return def


## The gaps between a set of parallel road centrelines, as [start, end] pairs,
## including the strip before the first road and the strip after the last. Given
## centres at 400 and 1500 with a half width of 140 and a map running 0 to 4000,
## this returns [0, 260], [540, 1360] and [1640, 4000].
static func _bands(centres: Array, half_width: float, from: float, to: float) -> Array:
	var bands: Array = []
	var cursor: float = from
	for centre in centres:
		bands.append([cursor, float(centre) - half_width])
		cursor = float(centre) + half_width
	bands.append([cursor, to])
	return bands


## Deterministic, quietly varied colours, so the neighbourhood does not read as
## one house repeated 36 times without a colour being typed per building.
static func _yard_color(row: int, column: int) -> Color:
	var shift: float = float((row * 3 + column) % 4) * 0.018
	return Color(0.30 + shift, 0.44 + shift * 0.6, 0.28 + shift * 0.4)


static func _body_color(row: int, column: int, slot: int) -> Color:
	const BODIES: Array = [
		Color(0.80, 0.62, 0.45), Color(0.75, 0.75, 0.70), Color(0.85, 0.80, 0.65),
		Color(0.70, 0.55, 0.45), Color(0.78, 0.72, 0.60), Color(0.82, 0.66, 0.50),
	]
	return BODIES[(row * 7 + column * 3 + slot) % BODIES.size()]


static func _roof_color(row: int, column: int, slot: int) -> Color:
	const ROOFS: Array = [
		Color(0.55, 0.20, 0.20), Color(0.25, 0.35, 0.55), Color(0.35, 0.45, 0.30),
		Color(0.45, 0.25, 0.20), Color(0.30, 0.30, 0.40), Color(0.40, 0.30, 0.55),
	]
	return ROOFS[(row * 5 + column * 2 + slot * 3) % ROOFS.size()]


static func _building(id: String, x0: float, y0: float, x1: float, y1: float, body_color: Color, roof_color: Color) -> Dictionary:
	return {
		"id": id,
		"polygon": PackedVector2Array([
			Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
		]),
		"body_color": body_color,
		"roof_color": roof_color,
		"source": "synthetic",
		"osm_id": "",
	}
