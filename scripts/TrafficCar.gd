extends CharacterBody2D
class_name TrafficCar
## One car: where it is on the lane network, what its driver is thinking, and
## what it looks like from above.
##
## SOLID TO THE ENGINE AND TO NOTHING ELSE. The body sits on the vehicle layer
## with an empty mask, so the truck's own mask stops the truck against it while
## the car itself collides with nothing at all. Car versus car is handled by the
## following rule, not by physics: two cars that touch would need contact
## resolution, wake-up rules and a way to get unstuck, and none of that is worth
## having when the alternative is a driver who simply does not drive into the
## back of the car in front.
##
## The car does not use move_and_slide. Its position is written each frame from
## its progress along the lane network, which is what makes "stop at the line"
## and "queue without overlapping" statements about distance rather than about
## forces.

## Which piece of the lane network the car is on. A lane is the straight run
## between two junctions; a turn is the curve across one.
enum Piece { LANE, TURN }

## What the driver is doing about the engine.
##
## NONE is an ordinary drive. HEARD is the reaction delay running. MOVING is the
## second or so of drifting to the side. STOPPED is waiting for the engine.
## CLEARING is the pause after it has passed, before pulling out again.
enum Yield { NONE, HEARD, MOVING, STOPPED, CLEARING }

## The one thing wrong with an imperfect driver. About one driver in ten has
## exactly one of these, drawn from the shift's seed.
##
## LATE_NOTICE hears nothing until the engine is close. FREEZES stops dead in
## the lane instead of pulling over. PULLS_LEFT goes the wrong way. LEFT_TURN is
## committed and takes up the left turn position regardless.
enum Flaw { NONE, LATE_NOTICE, FREEZES, PULLS_LEFT, LEFT_TURN }

## The body, in world units. A car is smaller than the 90 by 40 engine on
## purpose: the engine should look like the biggest thing on the road.
const LENGTH: float = 62.0
const WIDTH: float = 27.0

## The four shapes, by outline rather than by decoration. At the widest zoom a
## car is about fifteen pixels long, so the difference between them has to be in
## the silhouette: where the cabin sits and how much of the body it takes.
enum Shape { SALOON, HATCHBACK, PICKUP, VAN }

## Muted, related, and never a saturated primary, for the same reason the roofs
## are: a street is a dozen cars seen at once and any one loud car on it is the
## only thing the eye goes to. The engine is the red thing on this map.
const BODY_COLORS: Array[Color] = [
	Color(0.40, 0.44, 0.49),
	Color(0.55, 0.56, 0.54),
	Color(0.31, 0.36, 0.42),
	Color(0.46, 0.42, 0.38),
	Color(0.35, 0.42, 0.39),
	Color(0.58, 0.53, 0.47),
	Color(0.27, 0.30, 0.34),
	Color(0.50, 0.46, 0.52),
]

const OUTLINE: Color = Color(0.12, 0.13, 0.15, 0.85)
const GLASS: Color = Color(0.20, 0.24, 0.29, 0.9)
const INDICATOR: Color = Color(1.0, 0.66, 0.15)
const INDICATOR_DARK: Color = Color(0.45, 0.33, 0.12, 0.7)

## How fast the indicator and the hazards blink, cycles/second.
const BLINK_RATE: float = 2.2

var balance: Node = null
var lanes: LaneGraph = null
var signals: TrafficSignals = null

## Where on the network. piece_kind says which of the two ids is live.
var piece_kind: int = Piece.LANE
var lane_id: int = -1
var turn_id: int = -1
## Distance travelled along the current piece, world units.
var travelled: float = 0.0

var speed: float = 0.0
var cruise_speed: float = 120.0

## Sideways offset from the lane's own line, world units, positive to the
## driver's right. Everything about yielding is written into this one number.
var lateral: float = 0.0
var _lateral_target: float = 0.0

var yield_state: int = Yield.NONE
var flaw: int = Flaw.NONE
var courteous: bool = false
var reaction_delay: float = 1.0
var clear_delay: float = 1.5
var _yield_elapsed: float = 0.0

## Set while the car has been shoved by the engine. It stops, its hazards go on,
## and it stays that way: a car that has been hit is out of the traffic.
var struck: bool = false

var shape: int = Shape.SALOON
var body_color: Color = BODY_COLORS[0]

var _points: PackedVector2Array = PackedVector2Array()
var _piece_length: float = 0.0
var _heading: Vector2 = Vector2.RIGHT
var _blink: float = 0.0
## What the lamps were last actually drawn as, so a redraw only happens when the
## picture would change. See _process.
var _drawn_side: int = -99
var _drawn_lit: bool = false
## The stop sign, latched. A driver stops once, waits once, looks once, and then
## goes: without the latch the "have you stopped" test fires again the moment the
## car is moving into the junction and stops it in the middle of it.
var stop_sign_waited: float = 0.0
var has_stopped_at_sign: bool = false
var cleared_the_stop: bool = false


func _ready() -> void:
	# Layer 6, vehicle. Mask zero: nothing on this body ever collides with
	# anything. The truck's own mask is what makes a car solid.
	collision_layer = 0b100000
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


## Everything a car needs to exist, in one call, so the system that spawns them
## has one place to look. seeded_random supplies every per-driver number, so a
## shift's traffic is the same traffic given the same seed.
func setup(
	balance_node: Node,
	lane_graph: LaneGraph,
	signal_node: TrafficSignals,
	start_lane: int,
	start_travelled: float,
	rng: RandomNumberGenerator
) -> void:
	balance = balance_node
	lanes = lane_graph
	signals = signal_node

	shape = rng.randi_range(0, Shape.size() - 1)
	body_color = BODY_COLORS[rng.randi_range(0, BODY_COLORS.size() - 1)]
	reaction_delay = rng.randf_range(balance.traffic_reaction_min, balance.traffic_reaction_max)
	clear_delay = rng.randf_range(balance.traffic_clear_delay_min, balance.traffic_clear_delay_max)

	if rng.randf() < balance.traffic_imperfect_share:
		flaw = rng.randi_range(Flaw.LATE_NOTICE, Flaw.LEFT_TURN)
	else:
		courteous = rng.randf() < balance.traffic_courtesy_share

	_enter_lane(start_lane, start_travelled)
	cruise_speed = speed_for_class(balance, String(lanes.lanes[start_lane]["highway"]))
	speed = cruise_speed
	_place()

	# Set here rather than in _ready, because the layer is the whole of what
	# makes a car solid to the engine and nothing should depend on which of the
	# two ran first.
	collision_layer = 0b100000
	collision_mask = 0
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(LENGTH, WIDTH)
	collision.shape = rectangle
	add_child(collision)


## What a car does on a road of this class. Static, so the density rule and the
## tests can ask the same question without a car in hand.
static func speed_for_class(balance_node: Node, highway: String) -> float:
	if LaneGraph.MAJOR_CLASSES.has(highway):
		return balance_node.traffic_speed_major
	if highway == "service" or highway == "track" or highway == "living_street":
		return balance_node.traffic_speed_court
	return balance_node.traffic_speed_residential


func get_heading() -> Vector2:
	return _heading


func is_in_junction() -> bool:
	return piece_kind == Piece.TURN


## The point on the road the car is following, before its sideways offset.
func _line_position() -> Vector2:
	if _points.size() < 2:
		return global_position
	var remaining: float = travelled
	for index in range(_points.size() - 1):
		var span: float = _points[index].distance_to(_points[index + 1])
		if remaining <= span or index == _points.size() - 2:
			var t: float = 0.0 if span <= 0.0 else clampf(remaining / span, 0.0, 1.0)
			_heading = (_points[index + 1] - _points[index]).normalized()
			return _points[index].lerp(_points[index + 1], t)
		remaining -= span
	return _points[_points.size() - 1]


func _place() -> void:
	var on_line: Vector2 = _line_position()
	global_position = on_line + LaneGraph.right_of(_heading) * lateral
	rotation = _heading.angle()


func _enter_lane(id: int, start_travelled: float) -> void:
	piece_kind = Piece.LANE
	lane_id = id
	turn_id = -1
	var lane: Dictionary = lanes.lanes[id]
	_points = PackedVector2Array([Vector2(lane["entry"]), Vector2(lane["exit"])])
	_piece_length = float(lane["length"])
	travelled = clampf(start_travelled, 0.0, _piece_length)
	has_stopped_at_sign = false
	cleared_the_stop = false
	stop_sign_waited = 0.0
	cruise_speed = speed_for_class(balance, String(lane["highway"]))


func _enter_turn(id: int) -> void:
	piece_kind = Piece.TURN
	turn_id = id
	var turn: Dictionary = lanes.turns[id]
	_points = PackedVector2Array(turn["points"])
	_piece_length = 0.0
	for index in range(_points.size() - 1):
		_piece_length += _points[index].distance_to(_points[index + 1])
	travelled = 0.0


## The junction the car is driving towards, and the arm it is on. Only
## meaningful on a lane; a car already in a junction has passed the question.
func target_junction() -> int:
	if piece_kind != Piece.LANE or lane_id < 0:
		return -1
	return int(lanes.lanes[lane_id]["to_node"])


func distance_to_stop_line() -> float:
	if piece_kind != Piece.LANE:
		return INF
	return maxf(_piece_length - travelled, 0.0)


## How far the car needs to come to a stop from its current speed, plus a little,
## which is what "too close to stop" means at an amber.
func braking_distance() -> float:
	return (speed * speed) / (2.0 * balance.traffic_braking) + LENGTH * 0.5


## What the driver decides this frame, given the road ahead. gap is the distance
## to the nearest thing in front, or INF; junction_clear says whether the
## junction ahead can be entered.
##
## Returns the speed the car is trying to reach. Everything that stops a car is
## a target of zero and a braking rate; nothing here teleports a speed.
func desired_speed(gap: float, may_enter_junction: bool) -> float:
	if struck:
		return 0.0

	var target: float = cruise_speed

	# The car in front. Full stop at the following gap, and a speed proportional
	# to the room beyond it, which is what keeps a queue apart without anything
	# needing to know it is a queue.
	if gap < INF:
		var room: float = gap - balance.traffic_following_gap
		if room <= 0.0:
			return 0.0
		target = minf(target, room * 1.6)

	# The junction. A car may never enter one it has not been cleared for, and
	# yielding never overrides this: a car stopped at a red stays stopped.
	if piece_kind == Piece.LANE and not may_enter_junction:
		var room: float = distance_to_stop_line()
		if room <= 1.0:
			return 0.0
		target = minf(target, room * 1.8)

	# The siren. A car already in a junction clears through it rather than
	# stopping across the mouth, whatever its driver would rather do.
	if not is_in_junction() and _yield_wants_a_stop():
		return 0.0

	return maxf(target, 0.0)


func _yield_wants_a_stop() -> bool:
	if yield_state != Yield.STOPPED and yield_state != Yield.MOVING:
		return false
	# The driver committed to a left turn does not stop; that is the flaw.
	if flaw == Flaw.LEFT_TURN:
		return false
	return true


## One frame of the driver's mind about the engine.
##
## perceives is whether this driver can hear the siren right now; passed is
## whether the engine is behind them and going away.
func update_yield(delta: float, perceives: bool, passed: bool) -> void:
	_yield_elapsed += delta
	match yield_state:
		Yield.NONE:
			if perceives:
				yield_state = Yield.HEARD
				_yield_elapsed = 0.0
		Yield.HEARD:
			if not perceives:
				yield_state = Yield.NONE
				_yield_elapsed = 0.0
			elif _yield_elapsed >= reaction_delay:
				yield_state = Yield.MOVING
				_yield_elapsed = 0.0
				_lateral_target = _yield_lateral()
		Yield.MOVING:
			if _yield_elapsed >= balance.traffic_yield_move_time:
				yield_state = Yield.STOPPED
				_yield_elapsed = 0.0
		Yield.STOPPED:
			if passed or not perceives:
				yield_state = Yield.CLEARING
				_yield_elapsed = 0.0
		Yield.CLEARING:
			if perceives and not passed:
				yield_state = Yield.STOPPED
				_yield_elapsed = 0.0
			elif _yield_elapsed >= clear_delay:
				yield_state = Yield.NONE
				_yield_elapsed = 0.0
				_lateral_target = 0.0

	if yield_state == Yield.NONE:
		_lateral_target = 0.0

	# The move to the side, in world units per second, so a car that is going to
	# pull over takes about traffic_yield_move_time to do it whatever else is
	# happening to it.
	var rate: float = balance.traffic_yield_offset / maxf(balance.traffic_yield_move_time, 0.01)
	lateral = move_toward(lateral, _lateral_target, rate * delta)


## Which way, and how far, this driver pulls over.
func _yield_lateral() -> float:
	match flaw:
		Flaw.FREEZES:
			# Stops dead where it is. No drift at all, which is the flaw: the
			# lane is blocked rather than cleared.
			return 0.0
		Flaw.PULLS_LEFT:
			return -balance.traffic_yield_offset
		Flaw.LEFT_TURN:
			# Takes up the left turn position and keeps going.
			return -balance.traffic_yield_offset * 0.6
	return balance.traffic_yield_offset


## Whether the indicator is showing, and on which side.
func indicator_side() -> int:
	if struck:
		return 0  # hazards, both sides
	if yield_state == Yield.MOVING or yield_state == Yield.STOPPED:
		return -1 if _lateral_target < 0.0 else 1
	return 2  # nothing


## Moves the car along the network by one frame, choosing a turn at the end of a
## lane and a lane at the end of a turn. rng picks the turn, so a shift's
## traffic takes the same route given the same seed.
func advance(delta: float, target_speed: float, rng: RandomNumberGenerator) -> void:
	var rate: float = balance.traffic_acceleration
	if target_speed < speed:
		rate = balance.traffic_braking
		# A driver braking for the engine or for a car that has stopped dead
		# uses the pedal harder than one easing off for a queue.
		if target_speed <= 0.0 and speed > cruise_speed * 0.5:
			rate = balance.traffic_emergency_braking
	speed = move_toward(speed, target_speed, rate * delta)

	travelled += speed * delta
	while travelled >= _piece_length:
		var overshoot: float = travelled - _piece_length
		if piece_kind == Piece.LANE:
			var options: Array = lanes.turns_from_lane.get(lane_id, [] as Array[int])
			if options.is_empty():
				# Nowhere to go. Only possible on a lane network that is not
				# strongly connected, which both shipped maps are checked not to
				# be, so this is a guard rather than a path.
				travelled = _piece_length
				speed = 0.0
				break
			_enter_turn(int(options[rng.randi_range(0, options.size() - 1)]))
		else:
			_enter_lane(int(lanes.turns[turn_id]["to_lane"]), 0.0)
		travelled = overshoot
		if _piece_length <= 0.0:
			break

	_place()


## The engine has hit this car. It is shoved a short way, it stops, and its
## hazards come on. It stays out of the traffic from here: a struck car that
## drove away as if nothing had happened would make hitting one free.
func knock(direction: Vector2, distance: float) -> void:
	struck = true
	speed = 0.0
	_lateral_target = lateral
	yield_state = Yield.NONE
	# Shoved along the road rather than off it: the offset is sideways and the
	# travel is forward, so the car cannot be knocked through a fence.
	var forward: float = direction.dot(_heading) * distance
	var sideways: float = direction.dot(LaneGraph.right_of(_heading)) * distance
	travelled = clampf(travelled + forward, 0.0, _piece_length)
	lateral += sideways
	_lateral_target = lateral
	_place()
	queue_redraw()


## THE BLINK IS THE ONLY THING THAT NEEDS REDRAWING, and it needs it about four
## times a second rather than sixty.
##
## A car's body is drawn in its own local space, so moving and turning it costs
## nothing to redraw: Godot keeps the canvas item and changes its transform.
## Calling queue_redraw() every frame for every car, which the first version did,
## re-issued twenty-four cars' worth of polygons sixty times a second for no
## visible difference at all. It was 1.4 ms of the 2.0 ms traffic added to the
## frame on this machine.
func _process(delta: float) -> void:
	_blink += delta
	var side: int = indicator_side()
	var lit: bool = side != 2 and fmod(_blink * BLINK_RATE, 1.0) < 0.55
	if side == _drawn_side and lit == _drawn_lit:
		return
	_drawn_side = side
	_drawn_lit = lit
	queue_redraw()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var half := Vector2(LENGTH, WIDTH) * 0.5
	var body := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	draw_colored_polygon(body, body_color)
	var outline := PackedVector2Array(body)
	outline.append(body[0])
	draw_polyline(outline, OUTLINE, 1.6)

	# The cabin is the silhouette. Where it sits and how much of the body it
	# takes is the whole difference between the four shapes at this scale.
	var cabin: Rect2 = _cabin_rect(half)
	draw_rect(cabin, GLASS)

	if shape == Shape.PICKUP:
		# The bed: a darker panel behind the cabin, so a pickup reads as a cab
		# and a tray rather than as a short car.
		draw_rect(
			Rect2(Vector2(-half.x + 2.0, -half.y + 4.0), Vector2(half.x * 0.7, WIDTH - 8.0)),
			body_color.darkened(0.22)
		)

	_draw_lights(half)


func _cabin_rect(half: Vector2) -> Rect2:
	match shape:
		Shape.HATCHBACK:
			return Rect2(Vector2(-half.x * 0.55, -half.y + 3.0), Vector2(LENGTH * 0.5, WIDTH - 6.0))
		Shape.PICKUP:
			return Rect2(Vector2(half.x * 0.05, -half.y + 3.0), Vector2(LENGTH * 0.36, WIDTH - 6.0))
		Shape.VAN:
			return Rect2(Vector2(-half.x * 0.7, -half.y + 2.5), Vector2(LENGTH * 0.72, WIDTH - 5.0))
	return Rect2(Vector2(-half.x * 0.34, -half.y + 3.5), Vector2(LENGTH * 0.44, WIDTH - 7.0))


## The indicator, or the hazards on a car that has been hit. Amber, blinking,
## at the corner it belongs to, and drawn as a real lamp rather than a tint on
## the body: at the widest zoom the body is fifteen pixels long and a tinted
## panel would be invisible.
func _draw_lights(half: Vector2) -> void:
	var side: int = indicator_side()
	if side == 2:
		return
	var color: Color = INDICATOR if _drawn_lit else INDICATOR_DARK
	var corners: Array[Vector2] = []
	if side == 0:
		corners = [
			Vector2(half.x - 3.0, -half.y + 3.0), Vector2(half.x - 3.0, half.y - 3.0),
			Vector2(-half.x + 3.0, -half.y + 3.0), Vector2(-half.x + 3.0, half.y - 3.0),
		]
	else:
		var y: float = half.y - 3.0 if side > 0 else -half.y + 3.0
		corners = [Vector2(half.x - 3.0, y), Vector2(-half.x + 3.0, y)]
	for corner in corners:
		draw_circle(corner, 3.4, color)
