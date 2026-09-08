extends Node2D
class_name MapBuilder
## Constructs the playable scene from a MapDefinition (handoff §7, §8).
##
## Roads, sidewalks, street name labels and hydrant/incident markers are purely
## visual and carry no collision shape at all. Buildings and the four map-edge
## walls get collision on physics layer 1 ("world_static"), mask 0, which both
## stops the truck and blocks the water stream. The LOTS, the land behind the
## fences, get collision on layer 5 ("world_lot"): solid to the truck,
## transparent to the stream. Clean retro-inspired shapes, built-in drawing
## (Polygon2D/Line2D) and built-in fonts only, no external assets.
##
## Drivable: road, and the sidewalk band around it. Not drivable: the land
## behind the fences, and the houses on it. The kerb is a line the player can
## cross; the fence is the one they cannot.
##
## Nothing here assumes a road is straight, axis-aligned or rectangular
## (Milestone 5 Part 1). Every shape on the ground is derived by MapGeometry
## from the road network, so a cul-de-sac, a bend and two streets meeting at 63
## degrees are drawn and collided by the same code that draws a grid. The
## MapDefinition.blocks rectangles are no longer read at all: they cannot
## describe the land between roads that are not axis-aligned, and keeping a
## second path for the maps where they can would mean the fictional map was
## never proving anything about the real one.

## Warm, near-black asphalt (Part 2). Every road slab, and every junction fill,
## is filled with this exact colour and nothing else, which is what makes the
## network read as one continuous surface: two overlapping opaque fills of an
## identical colour cannot show a seam.
const ASPHALT_COLOR: Color = Color(0.14, 0.13, 0.125)

## Concrete band around every road. Kept clearly lighter than ASPHALT_COLOR so
## "road" and "sidewalk" are never a lighting judgement call.
const SIDEWALK_COLOR: Color = Color(0.74, 0.72, 0.67)

## The line where concrete meets asphalt, lighter again than the sidewalk
## itself so the boundary reads as a drawn edge rather than a shade difference
## the player has to infer.
const KERB_COLOR: Color = Color(0.90, 0.87, 0.79)

## Dashed lane marking down the middle of every road. Muted pale yellow, kept
## dimmer than KERB_COLOR so the two kinds of line do not compete.
const CENTERLINE_COLOR: Color = Color(0.82, 0.77, 0.52)

## Width of the concrete band outside the kerb, world units. This is the one
## number that turns the road region into the drivable region.
const SIDEWALK_WIDTH: float = 34.0
const KERB_WIDTH: float = 5.0
const CENTERLINE_WIDTH: float = 6.0

## The garden fence: where the land stops being drivable. Since sidewalks became
## drivable this, and not the kerb, is the edge that stops the truck.
const FENCE_WIDTH: float = 4.0
const FENCE_COLOR: Color = Color(0.42, 0.36, 0.28, 0.95)

## Dash pattern for the centreline, world units along the road.
const DASH_LENGTH: float = 44.0
const DASH_GAP: float = 32.0

## The physics layer the lots sit on, behind their fences. They stop the truck,
## exactly as a building does, but they are deliberately absent from
## WaterSystem's stream mask, because a stream clears a fence and a front lawn
## and does not clear a house. Without that split, filling the land in would
## have made every fire unreachable from the street it faces.
const LOT_LAYER: int = 0b10000  # layer 5, world_lot
const WALL_THICKNESS: float = 40.0

# ---------------------------------------------------------------------------
# Map-edge terminus (Milestone 8 Part 2)
# ---------------------------------------------------------------------------

## A road that reaches the edge of the map now STOPS, visibly, rather than
## running under the boundary wall and out of the world. The importer pulls
## every centreline in by half its own width so no asphalt passes the wall; this
## is what the player sees at the end of it.
##
## Two things, because they say different things. The barricade says "the road
## stops here", and is on the asphalt where the truck will hit it. The sign says
## "this is the edge of the map, not a route", and is readable from far enough
## back to turn around before arriving. James asked for the sign specifically.

## How close a dead end must be to the boundary to count as the map running out
## rather than as a cul-de-sac. One road width: a genuine cul-de-sac in the
## middle of the neighbourhood gets nothing, because it is a real place a real
## street ends, and barricading it would be a lie about the map's own edge.
const TERMINUS_EDGE_REACH_WIDTHS: float = 1.0

## The barricade: a bar across the asphalt at the road's end, in alternating
## stripes. Drawn on the road, not across the wall, so it reads as the end of
## the carriageway.
const BARRICADE_DEPTH: float = 26.0
const BARRICADE_STRIPE_WIDTH: float = 46.0
const BARRICADE_LIGHT: Color = Color(0.88, 0.86, 0.82)
const BARRICADE_DARK: Color = Color(0.70, 0.24, 0.18)

## The dead end sign: a yellow diamond reading DEAD END in black. Placed past
## the barricade, in the land between the road's end and the wall, turned so the
## driver reads it square on coming down the road.
##
## IT USED TO CARRY A BLACK T, WHICH SAYS SOMETHING ELSE. The yellow diamond
## with a T on it is the American warning for a T intersection ahead: a road
## that ends in another road you can turn onto either way. This road ends in a
## barricade and a wall. James spotted it in the screenshot pack.
##
## The diamond grew from 88 to 140 with the words, because two lines of legible
## text do not fit in an 88 unit diamond: a rectangle W by H fits a diamond of
## full diagonal S only while W + H is under S, and DEAD over END at a size that
## survives the 0.9 zoom is about 62 by 58. The standoff grew with it so the
## near corner still clears the barricade, and the far corner sits at 170 units
## past the road's end, inside the 200 unit verge.
const SIGN_SIZE: float = 140.0
## How far past the road's end the sign's centre stands. Half the diamond's own
## diagonal plus clearance, so its near corner is past the barricade.
##
## MEASURED AGAINST BOTH MAPS. Windsor's roads stop 200 units inside the wall,
## so its far corner lands at 170 with 30 to spare. Elm Grove's roads end
## exactly ON its boundary, room 0.0 at every one of its sixteen termini, so its
## barricades and signs stand outside the map in the overscan band and always
## have: that is Milestone 8's geometry, not this sign's placement, and it is
## recorded in DEVELOPMENT_STATUS.md rather than fixed here.
const SIGN_STANDOFF: float = 100.0
const SIGN_FACE: Color = Color(0.92, 0.78, 0.16)
const SIGN_EDGE: Color = Color(0.16, 0.14, 0.10)
const SIGN_TEXT: String = "DEAD\nEND"
const SIGN_FONT_SIZE: int = 25
## Pulls the two lines together: the default gap is set for paragraphs, and on a
## sign it reads as two separate words rather than one legend.
const SIGN_LINE_SPACING: int = -5

## The land outside the map, drawn so the camera's overscan shows ground rather
## than void. Deliberately flat and dark: it is not somewhere to go.
const OUTSIDE_COLOR: Color = Color(0.13, 0.16, 0.12)
const OUTSIDE_MARGIN: float = 3000.0

# ---------------------------------------------------------------------------
# Buildings (Milestone 6 Part 1)
# ---------------------------------------------------------------------------

## Roof tones. Five muted, related colours: warm grey, slate, terracotta, olive
## and taupe. Nothing saturated, nothing primary, and every pair of them sits
## happily side by side, because a street is 30 houses seen at once and any one
## loud roof on it is the only thing the eye goes to.
##
## This replaces the per-map colour pairs in the resources. Those were drawn
## from different palettes by MapDefinition and by tools/import_osm.gd, so the
## fictional map and the imported one did not look like the same game, and both
## picked from saturated primaries. The "body_color" and "roof_color" fields
## are still written into the resources and are simply no longer read, exactly
## as MapDefinition.blocks is: removing them means a schema version and a
## regenerated Windsor import for no gain today.
const ROOF_PALETTE: Array = [
	Color(0.52, 0.50, 0.46), # warm grey
	Color(0.40, 0.44, 0.50), # slate
	Color(0.56, 0.40, 0.33), # terracotta
	Color(0.45, 0.47, 0.36), # olive
	Color(0.49, 0.43, 0.37), # taupe
]

## How much darker than its roof a building's outline and its ridge are drawn.
## Both come from the roof colour rather than from a constant so a slate house
## is outlined in slate and a terracotta one in terracotta: one shared outline
## colour is what makes a row of houses read as stickers on the grass.
const ROOF_OUTLINE_DARKEN: float = 0.62
const ROOF_RIDGE_DARKEN: float = 0.80
const ROOF_OUTLINE_WIDTH: float = 3.0
const ROOF_RIDGE_WIDTH: float = 3.0

## How far the ridge stops short of each end of the roof, as a fraction of the
## roof's length along its own longest axis. A ridge drawn wall to wall reads as
## the roof being cut in half.
const RIDGE_END_INSET: float = 0.16

## The eave shadow: the footprint drawn once in a translucent dark tone, offset
## by this much, so a band of it shows on the two sides away from the light and
## nothing at all on the two sides facing it. The light is treated as coming
## from the north west on every map, so the band falls south and east.
##
## This is what replaced the old renderer's ring. That ring was the building
## BODY polygon with the roof inset to 62% of it drawn on top, which at this
## scale put a 30-unit beige band right around every house in a colour unrelated
## to its roof: it read as a doubled outline rather than as a wall.
const EAVE_SHADOW_OFFSET: Vector2 = Vector2(5.0, 5.0)
const EAVE_SHADOW_COLOR: Color = Color(0.08, 0.07, 0.06, 0.32)

## Driveways: a strip of concrete from the house to the sidewalk in front of it.
## Drawn only where the house genuinely fronts the street, which is what the gap
## threshold decides. 260 units is a little under three truck lengths of front
## garden; past that the house is not on that road in any sense a driveway would
## express, and drawing one would just paint a path across a back garden.
const DRIVEWAY_WIDTH: float = 46.0
const DRIVEWAY_MIN_GAP: float = 50.0
const DRIVEWAY_MAX_GAP: float = 260.0
const DRIVEWAY_COLOR: Color = Color(0.67, 0.66, 0.62)

## How far out from a house other footprints are considered when checking that
## its driveway does not run through a neighbour. The strip is at most
## DRIVEWAY_MAX_GAP long and a house is at most a few hundred units across, so
## anything further away than this cannot be in the way.
const DRIVEWAY_CLEARANCE_RADIUS: float = 600.0

# ---------------------------------------------------------------------------
# Street labels (Milestone 6 Part 2)
# ---------------------------------------------------------------------------

const LABEL_COLOR: Color = Color(0.95, 0.95, 0.90)
const LABEL_OUTLINE_COLOR: Color = Color(0.06, 0.05, 0.05)
const LABEL_FONT_SIZE: int = 34
const LABEL_OUTLINE_SIZE: int = 6

## Roughly how wide one character of the label font is, world units, at
## LABEL_FONT_SIZE. Used only to decide whether a segment is long enough to
## carry its own name; the drawing centres the text on the font's own
## measurement, so this is an estimate and is allowed to be one. Measured from
## the rendered label rather than assumed: the default font at size 34 averages
## a little over 18 units per character on these street names.
##
## The size itself is set against the ROAD rather than against the screen: a 280
## unit road carries text about an eighth of its width, which stays legible at
## every zoom in GameBalance.camera_zoom_levels. The first draft used 15, which
## is a sensible size for a HUD and is unreadably small painted on a road.
const LABEL_CHAR_WIDTH: float = 18.5

## Clear road either side of the text before a segment may carry a label, world
## units. A name that runs to within a few units of a junction reads as
## belonging to the junction rather than to the street.
const LABEL_END_MARGIN: float = 100.0

## How far off the centreline the text sits, world units. Enough that it clears
## the dashes rather than sitting on them, and well inside a 280 unit road.
const LABEL_CENTRELINE_OFFSET: float = 52.0

## A street longer than this carries a second label, so a long road is named
## again rather than the player driving a screen and a half without ever seeing
## what they are on. Two screen widths at the widest zoom the game offers.
const LABEL_REPEAT_LENGTH: float = 2600.0

## How far apart a street's two labels must be, world units, or the second one
## is not worth drawing. The first draft put both on the longest segment, at a
## third and two thirds of it; on the imported map the longest straight run of a
## long street is a few hundred units, so the two names landed a hundred units
## apart and read as one name printed twice. About a screen width.
const LABEL_MIN_SEPARATION: float = 1200.0

## Draw order, bottom to top. Every drawn node sets exactly one of these.
##
## The sidewalk is the whole drivable region, road included, and the asphalt is
## drawn ON TOP of it rather than beside it. That is what removes the seam at
## the kerb: there is no shared edge between two fills to alias along, only one
## fill ending on another, with the kerb line drawn last over the join. The
## yards sit above the sidewalk for the same reason on the far side.
const Z_OUTSIDE: int = -1
const Z_SIDEWALK: int = 0
const Z_ROAD: int = 1
const Z_ROAD_MARKING: int = 2
const Z_YARD: int = 3
const Z_DRIVEWAY: int = 4
const Z_KERB: int = 5
const Z_FENCE: int = 6
const Z_BUILDING_SHADOW: int = 7
const Z_BUILDING_ROOF: int = 8
const Z_BUILDING_EDGE: int = 9
const Z_TERMINUS: int = 10
const Z_LABEL: int = 11
const Z_MARKER: int = 12  # reserved: nothing draws at this level today

var _definition: MapDefinition = null
var _graph: RoadGraph = null
var _lot_region: Array[PackedVector2Array] = []
var _kerb_region: Array[PackedVector2Array] = []


func build(definition: MapDefinition) -> void:
	_definition = definition

	for child in get_children():
		child.queue_free()

	_graph = RoadGraph.build(definition)

	var bounds: Rect2 = definition.world_bounds
	var slabs: Array[PackedVector2Array] = MapGeometry.road_slabs(_graph)
	# The kerb region and the lot region are the same operation run twice, with
	# and without the sidewalk, so the two lines can never disagree about where
	# a road is.
	_kerb_region = MapGeometry.region_outside_roads(_graph, bounds, 0.0)
	_lot_region = MapGeometry.region_outside_roads(_graph, bounds, SIDEWALK_WIDTH)

	var roads_root := Node2D.new()
	roads_root.name = "Roads"
	add_child(roads_root)

	var blocks_root := Node2D.new()
	blocks_root.name = "Lots"
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

	_build_ground(roads_root, slabs)
	_build_centrelines(roads_root)
	_build_road_labels(roads_root)

	_build_lots(blocks_root, bounds)
	_build_kerbs(blocks_root, bounds)

	# Driveways before the houses, so a strip that turned out to be wrong is
	# visibly wrong on the grass rather than hidden under a roof.
	_build_driveways(blocks_root)

	for building in definition.buildings:
		_build_building(buildings_root, building)

	# Hydrants and incident candidates are not drawn here. Hydrant is a real node
	# with its own interaction ring, and only the dispatched call is marked, by
	# FireIncident. Markers above is the empty layer they would go back in.

	_build_outside_ground(roads_root, bounds)
	_build_edge_terminus(markers_root, bounds)
	_build_edge_walls(walls_root, bounds)


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


## The road network as a graph. Main prices a call's escalation allowance from
## this, because a route along real roads is the only honest measure of how far
## away a fire is once the roads stop being a grid.
func get_road_graph() -> RoadGraph:
	return _graph


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


## The land behind the fences, as the polygons the fences are drawn from. Read
## by the physics runner, which measures where the truck actually stops against
## where this says the fence is.
func get_lot_region() -> Array[PackedVector2Array]:
	return _lot_region


## The land the asphalt does not cover, as the polygons the kerbs are drawn
## from. Read by the physics runner, which needs to know where the kerb is in
## order to prove that the truck crossed it and was then stopped by something
## further in.
func get_kerb_region() -> Array[PackedVector2Array]:
	return _kerb_region


# ---------------------------------------------------------------------------
# The ground: concrete first, asphalt over it, dashes over that
# ---------------------------------------------------------------------------

## One concrete slab and one asphalt slab per road segment and per junction,
## every one of them opaque and the same colour as its neighbours. Overlapping
## identical opaque fills cannot show a seam, which is why the junctions are
## covered by drawing another fill over them rather than by merging polygons:
## the merge is only needed where a BOUNDARY has to be found, and that is done
## once, by MapGeometry, for the kerb and the fence.
func _build_ground(parent: Node2D, slabs: Array[PackedVector2Array]) -> void:
	for index in range(slabs.size()):
		for grown in Geometry2D.offset_polygon(
			slabs[index], SIDEWALK_WIDTH, Geometry2D.JOIN_SQUARE
		):
			var concrete := Polygon2D.new()
			concrete.name = "Sidewalk_%d" % index
			concrete.polygon = grown
			concrete.color = SIDEWALK_COLOR
			concrete.z_index = Z_SIDEWALK
			parent.add_child(concrete)

	for index in range(slabs.size()):
		var asphalt := Polygon2D.new()
		asphalt.name = "Road_%d" % index
		asphalt.polygon = slabs[index]
		asphalt.color = ASPHALT_COLOR
		asphalt.z_index = Z_ROAD
		parent.add_child(asphalt)


## The dashed centreline of every road, following the road's own bends and
## broken wherever it passes through a junction. A junction is filled solid
## precisely so it must never carry a lane marking across it.
func _build_centrelines(parent: Node2D) -> void:
	var period: float = DASH_LENGTH + DASH_GAP
	for road_index in range(_definition.roads.size()):
		var road: Dictionary = _definition.roads[road_index]
		var points: PackedVector2Array = road["points"]
		var blockers: Array[Dictionary] = _junctions_on_road(road_index)

		var dash_index: int = 0
		var phase: float = 0.0
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var length: float = a.distance_to(b)
			if length <= 0.0:
				continue
			var direction: Vector2 = (b - a) / length

			var travelled: float = 0.0
			while travelled < length:
				var cycle: float = fposmod(phase + travelled, period)
				if cycle >= DASH_LENGTH:
					travelled = minf(travelled + (period - cycle), length)
					continue
				var dash_end: float = minf(travelled + (DASH_LENGTH - cycle), length)
				var from: Vector2 = a + direction * travelled
				var to: Vector2 = a + direction * dash_end
				if dash_end - travelled > 1.0 and not _blocked(from, to, blockers):
					var dash := Polygon2D.new()
					dash.name = "Centreline_%s_%d" % [String(road["id"]), dash_index]
					dash.polygon = MapGeometry.oriented_slab(from, to, CENTERLINE_WIDTH)
					dash.color = CENTERLINE_COLOR
					dash.z_index = Z_ROAD_MARKING
					parent.add_child(dash)
					dash_index += 1
				travelled = dash_end
			phase = fposmod(phase + length, period)


## Every real crossing this road passes through, as a centre and the radius the
## junction fill reaches. Only nodes where three or more segments meet count: a
## node with two is a bend in one road, and breaking the dash at every bend
## would leave an imported road dashed almost nowhere.
func _junctions_on_road(road_index: int) -> Array[Dictionary]:
	var radii: Dictionary = {}
	for edge in _graph.edges:
		if int(edge["road_index"]) != road_index:
			continue
		for key in ["a", "b"]:
			var node: int = int(edge[key])
			if _graph.incident_edges.get(node, []).size() < 3:
				continue
			var radius: float = 0.0
			for incident_index in _graph.incident_edges[node]:
				radius = maxf(radius, float(_graph.edges[int(incident_index)]["width"]) / 2.0)
			radii[node] = radius

	var found: Array[Dictionary] = []
	for node in radii:
		found.append({"centre": _graph.positions[int(node)], "radius": float(radii[node])})
	return found


static func _blocked(from: Vector2, to: Vector2, blockers: Array[Dictionary]) -> bool:
	for blocker in blockers:
		var centre: Vector2 = blocker["centre"]
		var radius: float = blocker["radius"]
		if Geometry2D.get_closest_point_to_segment(centre, from, to).distance_to(centre) <= radius:
			return true
	return false


## The street names, painted on the asphalt along the road they name.
##
## The placement is decided by street_label_placements below, which is a pure
## function of the road list and is what the unit suite checks. This does the
## drawing only: a Label centred on the point it was given, rotated to the
## road, with an outline dark enough to read against the asphalt.
##
## The text is centred using the font's OWN measurement of it rather than the
## estimate the placement rule uses, which is why the two are separate: the rule
## has to be answerable without a font, and the drawing has one to hand.
func _build_road_labels(parent: Node2D) -> void:
	for placement in street_label_placements(_definition.roads):
		var label := Label.new()
		label.name = "Label_%s_%d" % [String(placement["road_id"]), int(placement["index"])]
		label.text = String(placement["text"])
		label.add_theme_color_override("font_color", LABEL_COLOR)
		label.add_theme_color_override("font_outline_color", LABEL_OUTLINE_COLOR)
		label.add_theme_constant_override("outline_size", LABEL_OUTLINE_SIZE)
		label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		label.z_index = Z_LABEL

		label.size = label.get_combined_minimum_size()
		label.pivot_offset = label.size / 2.0
		label.position = Vector2(placement["position"]) - label.size / 2.0
		label.rotation = float(placement["rotation"])
		parent.add_child(label)


## Where every street name goes, as {text, position, rotation, road_id, index}.
##
## One label per street NAME, not per road. An imported street arrives as
## several ways split at its junctions, and labelling each of them would print
## "Shadetree Drive" five times down one street.
##
## The label sits on the ASPHALT, on the midpoint of that street's longest
## straight SEGMENT, turned to the road and pushed just off the centreline so it
## clears the dashes. Before Milestone 6 Part 2 it sat horizontally on the
## sidewalk beside the road's midpoint, which on a bending road put the name
## somewhere out on the kerb reading across the street it named rather than
## along it. Choosing the longest straight segment, rather than the point half
## way along the road, is what makes the rotation mean something: half way along
## a road can land on a bend, where there is no one direction to turn to.
##
## Rotation is always in (-90, 90] degrees, so text never reads upside down. A
## segment pointing west gives the same line as one pointing east, turned round.
##
## A street too short to carry its name gets nothing, rather than a name
## overhanging both junctions. A street long enough to run off the screen twice
## gets a second label, so the player is told what they are on again rather than
## driving a screen and a half without being told.
##
## Unnamed ways get nothing, and so do slip roads: tools/import_osm.gd already
## drops the name from anything whose highway tag ends in "_link", because a
## slip road carries the name of the road it joins and labelling it would print
## that name somewhere it does not belong. Nothing here has to know about links;
## they simply arrive nameless.
static func street_label_placements(roads: Array[Dictionary]) -> Array[Dictionary]:
	# name -> {segments: Array of {a, b, length, road_id}, total_length}
	var streets: Dictionary = {}
	for road in roads:
		var road_name: String = String(road.get("name", "")).strip_edges()
		if road_name == "":
			continue
		var points: PackedVector2Array = road["points"]
		if not streets.has(road_name):
			streets[road_name] = {"segments": [], "total_length": 0.0}
		var street: Dictionary = streets[road_name]
		street["total_length"] = float(street["total_length"]) + _polyline_length(points)
		for i in range(points.size() - 1):
			var length: float = points[i].distance_to(points[i + 1])
			if length <= 0.0:
				continue
			street["segments"].append({
				"a": points[i],
				"b": points[i + 1],
				"length": length,
				"road_id": String(road.get("id", "")),
			})

	var placements: Array[Dictionary] = []
	var names: Array = streets.keys()
	names.sort()
	for road_name in names:
		var street: Dictionary = streets[road_name]
		var needed: float = String(road_name).length() * LABEL_CHAR_WIDTH + LABEL_END_MARGIN * 2.0

		# Longest first, so the street's best stretch carries its name and the
		# second label, if there is one, gets the best stretch left.
		var segments: Array = street["segments"].duplicate()
		segments.sort_custom(func(x, y): return float(x["length"]) > float(y["length"]))

		var wanted: int = 2 if float(street["total_length"]) > LABEL_REPEAT_LENGTH else 1
		var placed: Array[Vector2] = []

		for segment in segments:
			if placed.size() >= wanted:
				break
			var length: float = float(segment["length"])
			if length < needed:
				# Sorted longest first, so nothing after this one fits either.
				break
			var direction: Vector2 = (Vector2(segment["b"]) - Vector2(segment["a"])) / length
			var rotation: float = readable_rotation(direction.angle())
			# Off the centreline in the TEXT's own frame, so the name always
			# sits on the same side of the dashes as the reader sees it,
			# whichever way round the segment happened to be stored.
			var offset: Vector2 = Vector2(0.0, -LABEL_CENTRELINE_OFFSET).rotated(rotation)

			# Where on this segment the labels would go: one in the middle, or
			# a third and two thirds along when this is the only segment long
			# enough to carry both.
			var alongs: Array[float] = [length / 2.0]
			if (
				placed.is_empty() and wanted == 2 and segments.size() == 1
				and length >= needed * 2.0 and length / 3.0 >= LABEL_MIN_SEPARATION
			):
				alongs = [length / 3.0, length * 2.0 / 3.0]

			for along in alongs:
				if placed.size() >= wanted:
					break
				var position: Vector2 = Vector2(segment["a"]) + direction * along + offset
				var too_close: bool = false
				for existing in placed:
					if existing.distance_to(position) < LABEL_MIN_SEPARATION:
						too_close = true
						break
				if too_close:
					continue
				placements.append({
					"text": String(road_name),
					"position": position,
					"rotation": rotation,
					"road_id": String(segment["road_id"]),
					"index": placed.size(),
				})
				placed.append(position)
	return placements


## An angle turned into the one that reads the right way up: anything pointing
## into the left half of the compass is flipped by 180 degrees, which draws the
## same line with the text running the other way. The result is always in
## (-90, 90] degrees.
static func readable_rotation(angle: float) -> float:
	var wrapped: float = wrapf(angle, -PI, PI)
	if wrapped > PI / 2.0 or wrapped <= -PI / 2.0:
		wrapped = wrapf(wrapped + PI, -PI, PI)
	return wrapped


static func _polyline_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total



# ---------------------------------------------------------------------------
# The lots: the land between the roads
# ---------------------------------------------------------------------------

## Every piece of land the roads and their sidewalks do not cover: drawn as a
## yard, outlined by the fence that stops the truck, and made solid on
## LOT_LAYER.
##
## The collision region has the buildings cut out of it, because a house is
## already solid on layer 1 and covering it a second time on layer 5 would say
## the same thing twice. Where a house stands clear of the fence line, which is
## every house on both of today's maps, that cut leaves the footprint as a hole
## rather than as part of the outline, and a hole is dropped: the house's own
## body is what stops the truck there. The yards and fences are drawn from the
## region WITHOUT that cut, so a fence runs along the street and not around
## every house on it.
func _build_lots(parent: Node2D, bounds: Rect2) -> void:
	for index in range(_lot_region.size()):
		var piece: PackedVector2Array = _lot_region[index]

		var yard := Polygon2D.new()
		yard.name = "Yard_%d" % index
		yard.polygon = piece
		yard.color = _yard_color(MapGeometry.polygon_centroid(piece))
		yard.z_index = Z_YARD
		parent.add_child(yard)

		for run in MapGeometry.boundary_runs(piece, bounds):
			var fence := Line2D.new()
			fence.name = "Fence_%d_%d" % [index, parent.get_child_count()]
			fence.points = run
			fence.width = FENCE_WIDTH
			fence.default_color = FENCE_COLOR
			fence.z_index = Z_FENCE
			parent.add_child(fence)

	var footprints: Array[PackedVector2Array] = []
	for building in _definition.buildings:
		footprints.append(building["polygon"])

	var solid: Array[PackedVector2Array] = MapGeometry.subtract_polygons(
		_lot_region, footprints
	)

	var body := StaticBody2D.new()
	body.name = "Lots"
	body.collision_layer = LOT_LAYER
	body.collision_mask = 0
	for piece in solid:
		if Geometry2D.is_polygon_clockwise(piece):
			continue
		var shape := CollisionPolygon2D.new()
		shape.polygon = piece
		body.add_child(shape)
	parent.add_child(body)


## The kerb, drawn from the road region rather than from the lot region, so it
## sits exactly on the asphalt edge at every angle. Both lines skip the map's
## own boundary: there is no kerb at the edge of the world, there is a wall.
func _build_kerbs(parent: Node2D, bounds: Rect2) -> void:
	for index in range(_kerb_region.size()):
		for run in MapGeometry.boundary_runs(_kerb_region[index], bounds):
			var kerb := Line2D.new()
			kerb.name = "Kerb_%d_%d" % [index, parent.get_child_count()]
			kerb.points = run
			kerb.width = KERB_WIDTH
			kerb.default_color = KERB_COLOR
			kerb.z_index = Z_KERB
			parent.add_child(kerb)


## Deterministic, quietly varied yard colours, taken from where the land is
## rather than from a block index, because derived lots have no index a map
## author ever chose.
static func _yard_color(centroid: Vector2) -> Color:
	var cell: int = int(absf(floorf(centroid.x / 400.0)) + absf(floorf(centroid.y / 400.0)) * 3.0)
	var shift: float = float(cell % 4) * 0.018
	return Color(0.30 + shift, 0.44 + shift * 0.6, 0.28 + shift * 0.4)


# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------

## One house, seen from above: an eave shadow, a roof filled from the shared
## palette, a ridge along its longest axis and an outline, all four colours
## derived from the one palette entry the building's ID picks.
##
## Nothing here consults the incident candidates, and nothing should: a house
## that is about to catch fire has to look exactly like its neighbours until it
## is dispatched, or the player learns to read the map instead of the radio.
## The dispatched call is marked by FireIncident and by nothing else.
func _build_building(parent: Node2D, building: Dictionary) -> void:
	var polygon: PackedVector2Array = building["polygon"]
	if polygon.size() < 3:
		return
	var id: String = String(building["id"])
	var roof_color: Color = roof_color_for(id)

	var shadow := Polygon2D.new()
	shadow.name = "Eave_%s" % id
	shadow.polygon = _translated(polygon, EAVE_SHADOW_OFFSET)
	shadow.color = EAVE_SHADOW_COLOR
	shadow.z_index = Z_BUILDING_SHADOW
	parent.add_child(shadow)

	var roof := Polygon2D.new()
	roof.name = "Roof_%s" % id
	roof.polygon = polygon
	roof.color = roof_color
	roof.z_index = Z_BUILDING_ROOF
	parent.add_child(roof)

	var outline := Line2D.new()
	outline.name = "Outline_%s" % id
	outline.points = polygon
	outline.closed = true
	outline.width = ROOF_OUTLINE_WIDTH
	outline.default_color = roof_color.darkened(1.0 - ROOF_OUTLINE_DARKEN)
	outline.z_index = Z_BUILDING_EDGE
	parent.add_child(outline)

	var ridge_points: PackedVector2Array = ridge_line(polygon)
	if ridge_points.size() == 2:
		var ridge := Line2D.new()
		ridge.name = "Ridge_%s" % id
		ridge.points = ridge_points
		ridge.width = ROOF_RIDGE_WIDTH
		ridge.default_color = roof_color.darkened(1.0 - ROOF_RIDGE_DARKEN)
		ridge.z_index = Z_BUILDING_EDGE
		parent.add_child(ridge)

	var static_body := StaticBody2D.new()
	static_body.name = "Collision_%s" % id
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	static_body.add_child(shape)
	parent.add_child(static_body)


## The roof colour for a building, from its ID alone. Deterministic across runs
## and across machines, which is why it hashes the ID itself rather than seeding
## a RandomNumberGenerator: two players on the same map see the same street.
static func roof_color_for(building_id: String) -> Color:
	return ROOF_PALETTE[stable_hash(building_id) % ROOF_PALETTE.size()]


## FNV-1a over the ID's bytes, masked to 32 bits. String.hash() would do as
## well today, but it is an engine implementation detail and this is not: the
## houses must not change colour because Godot changed its hash.
static func stable_hash(text: String) -> int:
	var value: int = 2166136261
	for byte in text.to_utf8_buffer():
		value = (value ^ int(byte)) & 0xFFFFFFFF
		value = (value * 16777619) & 0xFFFFFFFF
	return value


## The roof ridge: a line through the middle of the footprint along its longest
## axis, stopping short of both ends.
##
## The axis is taken from the footprint's own longest EDGE rather than from the
## world axes, so a house standing at 20 degrees to the street gets a ridge at
## 20 degrees too. An imported footprint is rarely a clean rectangle, so the
## extent is measured by projecting every vertex onto that axis instead of
## assuming the longest edge spans the building.
static func ridge_line(polygon: PackedVector2Array) -> PackedVector2Array:
	if polygon.size() < 3:
		return PackedVector2Array()

	var axis: Vector2 = Vector2.ZERO
	var longest: float = 0.0
	for i in range(polygon.size()):
		var edge: Vector2 = polygon[(i + 1) % polygon.size()] - polygon[i]
		if edge.length() > longest:
			longest = edge.length()
			axis = edge.normalized()
	if axis == Vector2.ZERO:
		return PackedVector2Array()

	var centre: Vector2 = MapGeometry.polygon_centroid(polygon)
	var low: float = INF
	var high: float = -INF
	for point in polygon:
		var along: float = (point - centre).dot(axis)
		low = minf(low, along)
		high = maxf(high, along)

	var inset: float = (high - low) * RIDGE_END_INSET
	if high - low - inset * 2.0 <= 1.0:
		return PackedVector2Array()
	return PackedVector2Array([
		centre + axis * (low + inset), centre + axis * (high - inset),
	])


static func _translated(polygon: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in polygon:
		moved.append(point + offset)
	return moved


# ---------------------------------------------------------------------------
# Driveways
# ---------------------------------------------------------------------------

## A short strip of concrete from each house that fronts a street out to the
## sidewalk in front of it. Drawn under the fence, so it reads as a drive up to
## a gate rather than as a path that has knocked the fence down.
##
## Skipped whenever the house does not really front that road (the gap to the
## sidewalk is over DRIVEWAY_MAX_GAP) or whenever the strip would run through
## another house, which happens where two rows back onto one another and the
## nearest road to a back garden is the next street over.
func _build_driveways(parent: Node2D) -> void:
	var footprints: Array[PackedVector2Array] = []
	var centroids: Array[Vector2] = []
	for building in _definition.buildings:
		footprints.append(building["polygon"])
		centroids.append(MapGeometry.polygon_centroid(building["polygon"]))

	for index in range(_definition.buildings.size()):
		var strip: PackedVector2Array = _driveway_strip(footprints[index], centroids[index])
		if strip.is_empty():
			continue
		if _crosses_another_footprint(strip, footprints, centroids, index):
			continue
		var drive := Polygon2D.new()
		drive.name = "Driveway_%s" % String(_definition.buildings[index]["id"])
		drive.polygon = strip
		drive.color = DRIVEWAY_COLOR
		drive.z_index = Z_DRIVEWAY
		parent.add_child(drive)


## The strip from a footprint to the sidewalk edge of the road nearest it, or an
## empty array when there should not be one.
##
## The strip runs SQUARE TO THE ROAD, from the fence line straight in to the
## wall it meets. The first draft ran it to the nearest point of the footprint
## instead, which on a real import is nearly always a corner, so every drive
## came off the house at its own angle and each one read as a paving slab
## dropped on the lawn rather than as a drive. Where the perpendicular misses
## the house altogether the house does not front that road square on, and gets
## nothing.
func _driveway_strip(polygon: PackedVector2Array, centroid: Vector2) -> PackedVector2Array:
	var nearest: Dictionary = _nearest_road_point(centroid)
	if nearest.is_empty():
		return PackedVector2Array()

	var outward: Vector2 = (centroid - Vector2(nearest["point"])).normalized()
	if outward == Vector2.ZERO:
		return PackedVector2Array()
	# The sidewalk's outer edge on the house's side of the road: this is where
	# the drivable surface stops and the fence line runs.
	var kerb_point: Vector2 = (
		Vector2(nearest["point"]) + outward * (float(nearest["width"]) / 2.0 + SIDEWALK_WIDTH)
	)

	var wall_point: Vector2 = _first_crossing(polygon, kerb_point, centroid)
	if wall_point == kerb_point:
		return PackedVector2Array()
	var gap: float = wall_point.distance_to(kerb_point)
	# A strip shorter than it is wide is a square of concrete, not a drive.
	if gap < DRIVEWAY_MIN_GAP or gap > DRIVEWAY_MAX_GAP:
		return PackedVector2Array()
	# Run a little INTO the house so the strip meets the wall rather than
	# stopping a hair short of it and leaving a line of grass between them.
	var into_house: Vector2 = wall_point + (wall_point - kerb_point).normalized() * 6.0
	return MapGeometry.oriented_slab(into_house, kerb_point, DRIVEWAY_WIDTH)


## Where the segment from "from" to "to" first crosses the polygon's boundary,
## or "from" itself when it never does.
static func _first_crossing(
	polygon: PackedVector2Array, from: Vector2, to: Vector2
) -> Vector2:
	var best: Vector2 = from
	var best_distance: float = INF
	for i in range(polygon.size()):
		var hit = Geometry2D.segment_intersects_segment(
			from, to, polygon[i], polygon[(i + 1) % polygon.size()]
		)
		if hit == null:
			continue
		var distance: float = Vector2(hit).distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = hit
	return best


func _crosses_another_footprint(
	strip: PackedVector2Array,
	footprints: Array[PackedVector2Array],
	centroids: Array[Vector2],
	skip: int
) -> bool:
	var here: Vector2 = centroids[skip]
	for other in range(footprints.size()):
		if other == skip:
			continue
		if centroids[other].distance_to(here) > DRIVEWAY_CLEARANCE_RADIUS:
			continue
		if not Geometry2D.intersect_polygons(strip, footprints[other]).is_empty():
			return true
	return false


## The closest point on the road network's centrelines to a point, with the
## width of the road it is on. Empty when there are no roads at all.
func _nearest_road_point(point: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for edge in _graph.edges:
		var a: Vector2 = _graph.positions[int(edge["a"])]
		var b: Vector2 = _graph.positions[int(edge["b"])]
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var distance: float = candidate.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = {"point": candidate, "width": float(edge["width"])}
	return best



# ---------------------------------------------------------------------------
# The map edge: what is beyond it, and what says so
# ---------------------------------------------------------------------------

## A plain dark band all the way round the outside of the map.
##
## The camera is now allowed to look past the world bounds (FollowCamera's
## overscan), so that the truck is never pinned against the screen edge when it
## drives up to the wall. Without something drawn out there the overscan would
## show the viewport's clear colour, which reads as a hole in the world rather
## than as the edge of it. One ring of four rectangles, below everything.
func _build_outside_ground(parent: Node2D, bounds: Rect2) -> void:
	var outer: Rect2 = bounds.grow(OUTSIDE_MARGIN)
	var bands: Array[Rect2] = [
		Rect2(outer.position.x, outer.position.y, outer.size.x, bounds.position.y - outer.position.y),
		Rect2(outer.position.x, bounds.end.y, outer.size.x, outer.end.y - bounds.end.y),
		Rect2(outer.position.x, bounds.position.y, bounds.position.x - outer.position.x, bounds.size.y),
		Rect2(bounds.end.x, bounds.position.y, outer.end.x - bounds.end.x, bounds.size.y),
	]
	for index in range(bands.size()):
		var band := Polygon2D.new()
		band.name = "Outside_%d" % index
		band.polygon = MapGeometry.rect_polygon(bands[index])
		band.color = OUTSIDE_COLOR
		band.z_index = Z_OUTSIDE
		parent.add_child(band)


## A barricade and a dead end sign at every road that runs out at the map edge.
##
## Which ends count is TERMINUS_EDGE_REACH_WIDTHS: a dead end within one road
## width of the boundary is the map running out, and a dead end further in is a
## cul-de-sac, which is a real place a real street ends and gets nothing.
func _build_edge_terminus(parent: Node2D, bounds: Rect2) -> void:
	if _graph == null:
		return
	for node in range(_graph.positions.size()):
		var incident: Array = _graph.incident_edges.get(node, [])
		if incident.size() != 1:
			continue
		var here: Vector2 = _graph.positions[node]
		var edge: Dictionary = _graph.edges[int(incident[0])]
		var width: float = float(edge["width"])
		if _distance_to_boundary(here, bounds) > width * TERMINUS_EDGE_REACH_WIDTHS:
			continue

		var other: int = int(edge["b"]) if int(edge["a"]) == node else int(edge["a"])
		var outward: Vector2 = (here - _graph.positions[other]).normalized()
		if outward == Vector2.ZERO:
			continue

		_build_barricade(parent, node, here, outward, width)
		_build_dead_end_sign(parent, node, here + outward * SIGN_STANDOFF, outward)


## The bar across the asphalt, in alternating stripes, at the very end of the
## carriageway. Built stripe by stripe across the road rather than as one
## striped texture, because this project draws with polygons and no assets.
func _build_barricade(
	parent: Node2D, node: int, at: Vector2, outward: Vector2, width: float
) -> void:
	var across := Vector2(-outward.y, outward.x)
	var stripes: int = maxi(2, int(round(width / BARRICADE_STRIPE_WIDTH)))
	var stripe: float = width / float(stripes)
	var back: Vector2 = at - outward * BARRICADE_DEPTH
	for i in range(stripes):
		var from: float = -width / 2.0 + stripe * float(i)
		var bar := Polygon2D.new()
		bar.name = "Barricade_%d_%d" % [node, i]
		bar.polygon = PackedVector2Array([
			back + across * from,
			back + across * (from + stripe),
			at + across * (from + stripe),
			at + across * from,
		])
		bar.color = BARRICADE_LIGHT if i % 2 == 0 else BARRICADE_DARK
		bar.z_index = Z_TERMINUS
		parent.add_child(bar)


## The sign: a yellow diamond reading DEAD END. Turned so that "up" on the sign
## points back down the road at the driver, which is the only orientation that
## reads from a car in a top-down view. It therefore looks turned round in a
## screenshot read screen-up, and is right in the game.
func _build_dead_end_sign(
	parent: Node2D, node: int, at: Vector2, outward: Vector2
) -> void:
	var up: Vector2 = -outward
	var right := Vector2(-up.y, up.x)
	var half: float = SIGN_SIZE / 2.0

	var face := Polygon2D.new()
	face.name = "DeadEndSign_%d" % node
	face.polygon = PackedVector2Array([
		at + up * half, at + right * half, at - up * half, at - right * half,
	])
	face.color = SIGN_FACE
	face.z_index = Z_TERMINUS
	parent.add_child(face)

	var border := Line2D.new()
	border.name = "DeadEndSignEdge_%d" % node
	border.points = face.polygon
	border.closed = true
	border.width = 5.0
	border.default_color = SIGN_EDGE
	border.z_index = Z_TERMINUS
	parent.add_child(border)

	# The words. Centred on the font's own measurement of them, the same way the
	# street names are, rather than on an estimate: the two have to agree with
	# what is actually drawn, and the font is the only thing that knows.
	var legend := Label.new()
	legend.name = "DeadEndSignText_%d" % node
	legend.text = SIGN_TEXT
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.add_theme_color_override("font_color", SIGN_EDGE)
	legend.add_theme_font_size_override("font_size", SIGN_FONT_SIZE)
	legend.add_theme_constant_override("line_spacing", SIGN_LINE_SPACING)
	legend.z_index = Z_TERMINUS
	legend.size = legend.get_combined_minimum_size()
	legend.pivot_offset = legend.size / 2.0
	legend.position = at - legend.size / 2.0
	# Reading direction is across the sign, so the text runs along "right"; the
	# whole sign is already turned to face the driver by "up".
	legend.rotation = right.angle()
	parent.add_child(legend)


static func _distance_to_boundary(point: Vector2, bounds: Rect2) -> float:
	return minf(
		minf(point.x - bounds.position.x, bounds.end.x - point.x),
		minf(point.y - bounds.position.y, bounds.end.y - point.y)
	)


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
