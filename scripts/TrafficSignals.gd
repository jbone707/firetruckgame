extends Node2D
class_name TrafficSignals
## The signal heads and stop signs at every controlled junction, and the clock
## that drives them.
##
## One clock for the whole map, not one per junction. Every signalled junction
## runs the same fixed cycle in step, which is what a small town's signals
## actually do on a timer and is also the only version a player can learn: a
## junction whose phase depended on when it happened to come on screen would be
## a coin toss every time.
##
## Opposing arms share a phase. A crossroads runs two phases; a signalled T runs
## two as well, the road going through and the stem. The phase an arm belongs to
## is decided once, at load, from the same opposed-pair geometry LaneGraph uses
## to decide which arm of a T carries the stop sign.
##
## NOTHING HERE STOPS THE PLAYER. The engine is not traffic. These exist to be
## obeyed by the cars Part 3 adds, and to be looked at.
##
## Pauses with the game: this node is PROCESS_MODE_PAUSABLE, so the clock stops
## when the tree does and the phase a junction was on is the phase it resumes on.

enum Light { GREEN, AMBER, RED }

## The head: a dark housing with three lamps down it, drawn on the far corner of
## each approach so a driver reads the light for the arm they are on.
##
## Sized to be legible at the widest zoom the game offers. At 0.55 the view is
## about 2,330 world units across a 1,280 pixel screen, so a world unit is a bit
## over half a pixel and this housing is 24 pixels tall: small, and clearly a
## signal rather than a smudge, which is what the three lamps in a column buy.
const HEAD_SIZE: Vector2 = Vector2(17.0, 44.0)
const HEAD_HOUSING: Color = Color(0.13, 0.14, 0.16, 0.96)
## A LIGHT outline, not a dark one. The housing is nearly the asphalt's own
## colour, which is right for a signal and wrong for finding it: at 0.55 the
## first version drew a dark box on a dark road and the head read as a coloured
## dot floating over nothing.
const HEAD_EDGE: Color = Color(0.72, 0.76, 0.80, 0.85)
const LAMP_RADIUS: float = 5.6
## The lit lamp is drawn larger than its socket with a halo behind it, because at
## 0.55 the difference between a lit lamp and a dark one has to survive being
## three pixels across.
const LAMP_LIT_RADIUS: float = 7.4
const LAMP_HALO_RADIUS: float = 12.0

const LAMP_RED: Color = Color(0.92, 0.24, 0.19)
const LAMP_AMBER: Color = Color(0.96, 0.70, 0.16)
const LAMP_GREEN: Color = Color(0.32, 0.86, 0.36)
## An unlit lamp is nearly the housing's own colour: dark, but still a circle,
## so the head reads as three lamps with one of them on.
const LAMP_DARK: Color = Color(0.09, 0.10, 0.11)

## How far past the junction the head stands, on top of the junction's own
## radius, and how far to the side of the approach's centreline. Both push the
## head off the asphalt onto the corner, which is where it has to be: a signal
## drawn over the road would hide the road.
const HEAD_STANDOFF: float = 26.0
const HEAD_SIDE_CLEARANCE: float = 30.0

## The stop sign: the American red octagon, on the verge on the driver's right,
## BEFORE the junction rather than past it.
const STOP_RADIUS: float = 22.0
const STOP_FACE: Color = Color(0.78, 0.16, 0.14)
const STOP_EDGE: Color = Color(0.97, 0.96, 0.94)
const STOP_STANDOFF: float = 20.0
const STOP_SIDE_CLEARANCE: float = 26.0
const STOP_FONT_SIZE: int = 13

var balance: Node = null

## Seconds since the shift started. The only state the whole system has.
var clock: float = 0.0

## One entry per signalled junction:
##   {node, position, heads: [{position, heading, phase, edge_index}]}
var _signals: Array[Dictionary] = []

## One entry per stop sign: {position, heading, edge_index, node}
var _stop_signs: Array[Dictionary] = []

var _lane_graph: LaneGraph = null


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


func _ready() -> void:
	resolve_balance()


## One whole cycle: both phases, each green then amber, with an all-red between.
func cycle_length() -> float:
	resolve_balance()
	return 2.0 * (
		balance.signal_green_time + balance.signal_amber_time + balance.signal_all_red_time
	)


## Builds the heads and the signs for a map. Called on every map load, so
## everything the last map put down goes first.
func configure(lane_graph: LaneGraph) -> void:
	resolve_balance()
	_lane_graph = lane_graph
	_signals.clear()
	_stop_signs.clear()
	clock = 0.0

	if lane_graph == null:
		queue_redraw()
		return

	for node in lane_graph.junctions:
		var junction: Dictionary = lane_graph.junctions[node]
		if int(junction["control"]) == LaneGraph.JunctionControl.SIGNAL:
			_build_signal(junction)
		else:
			_build_stop_signs(junction)

	queue_redraw()


## Which arms share a phase.
##
## The two arms pointing most nearly away from one another are the road going
## through, and they are phase 0; everything else is phase 1. On a crossroads
## that splits four arms into two opposed pairs. On a signalled T it puts the
## through road on one phase and the stem on the other, which is what such a
## junction really does.
static func phase_of_each_arm(arms: Array) -> Array[int]:
	var phases: Array[int] = []
	for _arm in arms:
		phases.append(1)
	if arms.size() < 2:
		return phases

	var best_a: int = 0
	var best_b: int = 1
	var most_opposed: float = 2.0
	for i in range(arms.size()):
		for j in range(i + 1, arms.size()):
			var dot: float = Vector2(arms[i]["heading"]).dot(Vector2(arms[j]["heading"]))
			if dot < most_opposed:
				most_opposed = dot
				best_a = i
				best_b = j
	phases[best_a] = 0
	phases[best_b] = 0

	# On a crossroads the remaining two are the other road and are opposed to
	# each other; they are already phase 1 and nothing more is needed. On a T the
	# single remaining arm is phase 1 on its own.
	return phases


## What an arm's light is showing at a given time. Static and free of node state
## so a test can ask the question with arithmetic.
static func light_at(
	phase: int, time: float, green: float, amber: float, all_red: float
) -> int:
	var leg: float = green + amber + all_red
	var cycle: float = leg * 2.0
	if cycle <= 0.0:
		return Light.RED
	var t: float = fposmod(time, cycle)
	var start: float = float(phase) * leg
	var since: float = fposmod(t - start, cycle)
	if since < green:
		return Light.GREEN
	if since < green + amber:
		return Light.AMBER
	return Light.RED


func light_for_phase(phase: int) -> int:
	resolve_balance()
	return light_at(
		phase, clock,
		balance.signal_green_time, balance.signal_amber_time, balance.signal_all_red_time
	)


## What a car arriving at this junction down this arm is being shown. RED for an
## arm with a stop sign on it, and GREEN at anything uncontrolled, so one call
## answers the question at every junction on the map.
func light_for_arm(node: int, edge_index: int) -> int:
	for entry in _signals:
		if int(entry["node"]) != node:
			continue
		for head in entry["heads"]:
			if int(head["edge_index"]) == edge_index:
				return light_for_phase(int(head["phase"]))
		return Light.GREEN
	if _lane_graph != null and _lane_graph.arm_has_stop_sign(node, edge_index):
		return Light.RED
	return Light.GREEN


func get_signal_count() -> int:
	return _signals.size()


func get_stop_sign_count() -> int:
	return _stop_signs.size()


## Called by Main when a shift starts, so every shift opens on the same phase
## rather than on wherever the last one left the clock.
func reset_for_new_shift() -> void:
	clock = 0.0
	queue_redraw()


func _build_signal(junction: Dictionary) -> void:
	var here: Vector2 = junction["position"]
	var arms: Array = junction["arms"]
	var phases: Array[int] = phase_of_each_arm(arms)
	var radius: float = float(junction["widest_width"]) / 2.0

	var heads: Array[Dictionary] = []
	for index in range(arms.size()):
		var arm: Dictionary = arms[index]
		# The arm's heading points AWAY from the junction, so a car approaching
		# on it travels along the reverse. The head goes on the far corner: past
		# the junction, on that driver's right.
		var approach: Vector2 = -Vector2(arm["heading"])
		var to_the_right: Vector2 = LaneGraph.right_of(approach)
		heads.append({
			"edge_index": int(arm["edge_index"]),
			"phase": phases[index],
			"heading": approach,
			"position": (
				here
				+ approach * (radius + HEAD_STANDOFF)
				+ to_the_right * (float(arm["width"]) / 2.0 + HEAD_SIDE_CLEARANCE)
			),
		})

	_signals.append({
		"node": int(junction["node"]),
		"position": here,
		"heads": heads,
	})


func _build_stop_signs(junction: Dictionary) -> void:
	var here: Vector2 = junction["position"]
	var radius: float = float(junction["widest_width"]) / 2.0
	for arm in junction["arms"]:
		if not junction["stop_arms"].has(int(arm["edge_index"])):
			continue
		# A stop sign stands BEFORE the junction, on the near side, on the
		# driver's right. The arm's heading points away from the junction, which
		# is the direction the sign is set out along.
		var out: Vector2 = Vector2(arm["heading"])
		var to_the_right: Vector2 = LaneGraph.right_of(-out)
		_stop_signs.append({
			"node": int(junction["node"]),
			"edge_index": int(arm["edge_index"]),
			"heading": -out,
			"position": (
				here
				+ out * (radius + STOP_STANDOFF)
				+ to_the_right * (float(arm["width"]) / 2.0 + STOP_SIDE_CLEARANCE)
			),
		})


## The clock, and only the clock. PROCESS_MODE_PAUSABLE, set in Main.tscn, is
## what makes the signals stop with the game rather than running on behind a
## pause menu and jumping when it closes.
func _process(delta: float) -> void:
	if _signals.is_empty():
		return
	clock = fposmod(clock + delta, cycle_length())
	queue_redraw()


func _draw() -> void:
	for entry in _signals:
		for head in entry["heads"]:
			_draw_head(head)
	for sign_entry in _stop_signs:
		_draw_stop_sign(sign_entry)


## One head, laid ACROSS the road it governs, with the lamps in a row and red on
## the approaching driver's left.
##
## A real head is a column on a pole and from directly overhead you would see
## the top of it and nothing else, so every top-down game cheats. The first
## version of this cheat laid the column along the road, pointing back at the
## driver, and in plan view that reads as a dark bar lying in the gutter with a
## coloured dot at one end: the lamp moved to a different end of the housing
## depending on which way the road ran. A bar ACROSS the road cannot be mistaken
## for anything the road already has, and the row of lamps stays in the same
## order for every approach on the map. It is also a real configuration: the
## horizontal signal head is ordinary across the American south.
func _draw_head(head: Dictionary) -> void:
	var at: Vector2 = head["position"]
	var approach: Vector2 = Vector2(head["heading"])
	# "up" faces the driver; "side" is then that driver's left, which is where
	# red goes on a horizontal head.
	var up: Vector2 = -approach
	var side: Vector2 = LaneGraph.right_of(up)

	var across: float = HEAD_SIZE.y / 2.0
	var deep: float = HEAD_SIZE.x / 2.0
	var housing := PackedVector2Array([
		at + side * across + up * deep,
		at - side * across + up * deep,
		at - side * across - up * deep,
		at + side * across - up * deep,
	])
	draw_colored_polygon(housing, HEAD_HOUSING)
	draw_polyline(
		PackedVector2Array([housing[0], housing[1], housing[2], housing[3], housing[0]]),
		HEAD_EDGE, 2.0
	)

	var lit: int = light_for_phase(int(head["phase"]))
	var lamps: Array = [
		[Light.RED, LAMP_RED, across * 0.58],
		[Light.AMBER, LAMP_AMBER, 0.0],
		[Light.GREEN, LAMP_GREEN, -across * 0.58],
	]
	for lamp in lamps:
		var centre: Vector2 = at + side * float(lamp[2])
		if int(lamp[0]) == lit:
			draw_circle(centre, LAMP_HALO_RADIUS, Color(lamp[1], 0.28))
			draw_circle(centre, LAMP_LIT_RADIUS, lamp[1])
		else:
			draw_circle(centre, LAMP_RADIUS, LAMP_DARK)


func _draw_stop_sign(sign_entry: Dictionary) -> void:
	var at: Vector2 = sign_entry["position"]
	var up: Vector2 = -Vector2(sign_entry["heading"])
	var side: Vector2 = LaneGraph.right_of(up)

	var octagon := PackedVector2Array()
	for step in range(8):
		# Turned an eighth of a turn so the octagon sits on a flat edge rather
		# than on a point, which is what makes it read as a stop sign.
		var angle: float = TAU * (float(step) + 0.5) / 8.0
		octagon.append(at + (up * cos(angle) + side * sin(angle)) * STOP_RADIUS)
	draw_colored_polygon(octagon, STOP_FACE)

	var outline := PackedVector2Array(octagon)
	outline.append(octagon[0])
	draw_polyline(outline, STOP_EDGE, 2.4)

	# The word, drawn small. It is not readable at 0.55 and is not meant to be:
	# a red octagon on a verge is already the sign, and the word is what makes it
	# unmistakable when the player is close enough to have to obey it.
	var font: Font = ThemeDB.fallback_font
	var text: String = "STOP"
	var measured: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, STOP_FONT_SIZE)
	draw_set_transform(at, up.angle() + PI / 2.0, Vector2.ONE)
	draw_string(
		font, Vector2(-measured.x / 2.0, measured.y * 0.32), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, STOP_FONT_SIZE, STOP_EDGE
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
