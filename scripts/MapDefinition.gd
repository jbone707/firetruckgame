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
@export var schema_version: int = 1

## Stable machine identifier for this map, e.g. "fictional_neighbourhood_v1".
@export var map_id: String = ""

## Human-readable name, Title Case, shown to the player if the game ever
## lists more than one map.
@export var display_name: String = ""

## Intentionally empty for this fictional map. Present so a future importer
## that generates a MapDefinition from a real geographic source (handoff §7)
## can record where its data came from (dataset name, license, fetch date)
## without changing this schema.
@export var source_metadata: Dictionary = {}

## Intentionally empty for this fictional map, for the same reason as
## source_metadata: a future real-map importer needs somewhere to record the
## real-world lat/long box this neighbourhood corresponds to.
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
## width: float}. "points" is the road's centerline, at least two points.
## "width" is the full drivable width, from kerb to kerb.
@export var roads: Array[Dictionary] = []

## Each entry: {id: String, polygon: PackedVector2Array,
## body_color: Color, roof_color: Color}.
@export var buildings: Array[Dictionary] = []

## Each entry: {id: String, position: Vector2}.
@export var hydrants: Array[Dictionary] = []

## Each entry: {id: String, building_id: String, position: Vector2}.
## building_id must name an entry in "buildings".
@export var incident_candidates: Array[Dictionary] = []


## Builds the one fictional test neighbourhood used for this milestone.
##
## Layout: a 3x3 grid of named streets (three east-west, three north-south)
## forming four interior blocks, each holding two buildings set back from
## the road far enough to clear the road's own pavement plus a sidewalk.
## The station sits at the northwest corner, on Elm Avenue just north of
## its junction with Ash Street.
##
## Road width (140.0, see ROAD_WIDTH below) and every coordinate here were
## chosen to fit GameBalance's truck dimensions and stream range; see
## DEVELOPMENT_STATUS.md for the reasoning, not repeated in this comment
## because it would drift the moment either number changes.
static func create_fictional_neighbourhood() -> MapDefinition:
	const ROAD_WIDTH: float = 140.0

	var def := MapDefinition.new()
	def.schema_version = 1
	def.map_id = "fictional_neighbourhood_v1"
	def.display_name = "Elm Grove"
	def.source_metadata = {}
	def.geographic_bounds = {}
	def.world_bounds = Rect2(0.0, 0.0, 1400.0, 1000.0)
	def.station_spawn_position = Vector2(200.0, 110.0)
	def.station_spawn_heading = PI / 2.0 # south, toward Ash Street

	def.roads = [
		{
			"id": "r_ash",
			"name": "Ash Street",
			"points": PackedVector2Array([Vector2(100.0, 150.0), Vector2(1300.0, 150.0)]),
			"width": ROAD_WIDTH,
		},
		{
			"id": "r_birch",
			"name": "Birch Street",
			"points": PackedVector2Array([Vector2(100.0, 500.0), Vector2(1300.0, 500.0)]),
			"width": ROAD_WIDTH,
		},
		{
			"id": "r_cedar",
			"name": "Cedar Street",
			"points": PackedVector2Array([Vector2(100.0, 850.0), Vector2(1300.0, 850.0)]),
			"width": ROAD_WIDTH,
		},
		{
			"id": "r_elm",
			"name": "Elm Avenue",
			"points": PackedVector2Array([Vector2(200.0, 100.0), Vector2(200.0, 900.0)]),
			"width": ROAD_WIDTH,
		},
		{
			"id": "r_fir",
			"name": "Fir Avenue",
			"points": PackedVector2Array([Vector2(700.0, 100.0), Vector2(700.0, 900.0)]),
			"width": ROAD_WIDTH,
		},
		{
			"id": "r_grove",
			"name": "Grove Avenue",
			"points": PackedVector2Array([Vector2(1200.0, 100.0), Vector2(1200.0, 900.0)]),
			"width": ROAD_WIDTH,
		},
	]

	def.buildings = [
		_building("b_a1", 300.0, 250.0, 440.0, 400.0, Color(0.80, 0.62, 0.45), Color(0.55, 0.20, 0.20)),
		_building("b_a2", 470.0, 260.0, 600.0, 390.0, Color(0.75, 0.75, 0.70), Color(0.25, 0.35, 0.55)),
		_building("b_b1", 800.0, 250.0, 940.0, 400.0, Color(0.85, 0.80, 0.65), Color(0.35, 0.45, 0.30)),
		_building("b_b2", 970.0, 260.0, 1100.0, 390.0, Color(0.70, 0.55, 0.45), Color(0.45, 0.25, 0.20)),
		_building("b_c1", 300.0, 600.0, 440.0, 750.0, Color(0.78, 0.72, 0.60), Color(0.30, 0.30, 0.40)),
		_building("b_c2", 470.0, 610.0, 600.0, 740.0, Color(0.82, 0.66, 0.50), Color(0.50, 0.30, 0.25)),
		_building("b_d1", 800.0, 600.0, 940.0, 750.0, Color(0.72, 0.78, 0.72), Color(0.35, 0.50, 0.40)),
		_building("b_d2", 970.0, 610.0, 1100.0, 740.0, Color(0.76, 0.70, 0.62), Color(0.40, 0.30, 0.55)),
	]

	def.hydrants = [
		{"id": "h_station", "position": Vector2(150.0, 230.0)},
		{"id": "h_fir", "position": Vector2(780.0, 300.0)},
		{"id": "h_grove", "position": Vector2(1120.0, 700.0)},
		{"id": "h_elm_south", "position": Vector2(220.0, 780.0)},
	]

	def.incident_candidates = [
		{"id": "ic_a1", "building_id": "b_a1", "position": Vector2(370.0, 235.0)},
		{"id": "ic_b2", "building_id": "b_b2", "position": Vector2(1115.0, 325.0)},
		{"id": "ic_c2", "building_id": "b_c2", "position": Vector2(615.0, 675.0)},
		{"id": "ic_d1", "building_id": "b_d1", "position": Vector2(870.0, 585.0)},
	]

	return def


static func _building(id: String, x0: float, y0: float, x1: float, y1: float, body_color: Color, roof_color: Color) -> Dictionary:
	return {
		"id": id,
		"polygon": PackedVector2Array([
			Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1),
		]),
		"body_color": body_color,
		"roof_color": roof_color,
	}
