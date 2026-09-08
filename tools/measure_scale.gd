extends SceneTree
## Measures how big a map's world is against the truck that drives it
## (Milestone 6 Part 2).
##
## Run with:
##   godot --headless --path . --script res://tools/measure_scale.gd
##
## James played Windsor and said the scale felt off: the roads were the width he
## liked on Elm Grove, but the truck read as a toy and every straight was long.
## He was right, and the reason is that Elm Grove's houses and blocks were drawn
## to suit the truck while Windsor's are real American ones at 25 world units
## per metre, which is three or four times bigger relative to the same truck.
##
## Three numbers say it, all divided by the truck's own length so they can be
## compared between a fictional map and a real one:
##
## - road width, which is the number that was already matched and should stay
##   matched
## - house footprint width, taken as the side of a square of the same area,
##   because a real footprint is not a rectangle and its bounding box overstates
##   anything built at an angle
## - the distance from one junction to the next along the roads, which is what
##   makes a straight feel long
##
## Measurement only. Nothing here decides anything or writes anything.

const MAPS: Array[String] = [
	"res://resources/neighbourhood.tres",
	"res://resources/windsor_shadetree.tres",
]
const TRUCK_SCENE: String = "res://scenes/Truck.tscn"


func _initialize() -> void:
	var truck_length: float = _truck_length()
	print("truck length: %.1f world units" % truck_length)
	print("")
	print("%-28s %10s %10s %10s" % ["", "road", "house", "junction"])
	print("%-28s %10s %10s %10s" % ["map", "width", "width", "spacing"])
	print("")

	for path in MAPS:
		var map: MapDefinition = load(path) as MapDefinition
		if map == null:
			printerr("%s does not load as a MapDefinition" % path)
			continue
		var graph: RoadGraph = RoadGraph.build(map)

		var road: float = _median_road_width(map)
		var house: float = _median_house_width(map)
		var spacing: float = _median_junction_spacing(graph)

		print("%-28s %10.1f %10.1f %10.1f   world units" % [map.map_id, road, house, spacing])
		print("%-28s %10.2f %10.2f %10.2f   truck lengths" % [
			"", road / truck_length, house / truck_length, spacing / truck_length,
		])
		print("    %d road(s), %d building(s), %d junction(s), world %.0f by %.0f" % [
			map.roads.size(), map.buildings.size(), graph.junction_nodes().size(),
			map.world_bounds.size.x, map.world_bounds.size.y,
		])
		var scale: Dictionary = map.geographic_bounds
		if scale.has("units_per_metre"):
			print("    %.1f world units per metre" % float(scale["units_per_metre"]))
		print("")

	quit(0)


func _truck_length() -> float:
	var truck: Node = load(TRUCK_SCENE).instantiate()
	var shape: CollisionShape2D = truck.get_node("CollisionShape2D")
	var size: Vector2 = (shape.shape as RectangleShape2D).size
	truck.free()
	return size.x


func _median_road_width(map: MapDefinition) -> float:
	var widths: Array[float] = []
	for road in map.roads:
		widths.append(float(road.get("width", 0.0)))
	return _median(widths)


## The side of a square with the same area as the footprint.
func _median_house_width(map: MapDefinition) -> float:
	var widths: Array[float] = []
	for building in map.buildings:
		var area: float = MapGeometry.polygon_area(building["polygon"])
		if area > 0.0:
			widths.append(sqrt(area))
	return _median(widths)


## For every junction, how far it is along the roads to the nearest OTHER
## junction; the median of those. Measured along the roads rather than straight,
## because that is the distance the truck drives.
func _median_junction_spacing(graph: RoadGraph) -> float:
	var junctions: Array[int] = graph.junction_nodes()
	var spacings: Array[float] = []
	for node in junctions:
		var nearest: float = INF
		for other in junctions:
			if other == node:
				continue
			var distance: float = graph.route_length(
				graph.positions[node], graph.positions[other]
			)
			nearest = minf(nearest, distance)
		if nearest < INF:
			spacings.append(nearest)
	return _median(spacings)


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	var middle: int = values.size() / 2
	if values.size() % 2 == 1:
		return values[middle]
	return (values[middle - 1] + values[middle]) / 2.0
