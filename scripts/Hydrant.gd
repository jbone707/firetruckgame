extends Node2D
class_name Hydrant
## A hydrant, its interaction radius, and the hookup rules from handoff section 6.
##
## Range is a plain distance check against the truck rather than an Area2D. The
## rule is "within range and nearly stationary", both of which are one line of
## arithmetic, and a distance check is testable without standing up physics.

enum Prompt { NONE, TOO_FAST, HOLD_TO_HOOK_UP, HOOKING_UP, REFILLING, TANK_FULL }

## The interaction ring on the ground. Dashed means out of reach, solid means
## the truck can hook up from where it is standing.
const RING_SEGMENTS: int = 64
const RING_DASHES: int = 24
const RING_DASH_FRACTION: float = 0.55
const RING_IN_RANGE: Color = Color(0.35, 0.85, 1.0, 0.6)
const RING_IN_RANGE_INNER: Color = Color(0.35, 0.85, 1.0, 0.25)
const RING_OUT_OF_RANGE: Color = Color(0.62, 0.76, 0.86, 0.3)

## The hose drawn from the hydrant to the truck while hooked up.
const HOSE_SEGMENTS: int = 14
const HOSE_COLOR: Color = Color(0.92, 0.94, 0.85, 0.95)
const HOSE_CASING: Color = Color(0.30, 0.33, 0.30, 0.9)

var balance: Node = null
var hydrant_id: String = ""

var _active: bool = false
var _hose_connected: bool = false

## Where the hose ends, in this hydrant's local space.
var _hose_target: Vector2 = Vector2.ZERO


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


func setup(id: String, world_position: Vector2) -> void:
	resolve_balance()
	hydrant_id = id
	position = world_position
	queue_redraw()


func get_interaction_radius() -> float:
	resolve_balance()
	return balance.hydrant_interaction_radius


## Distance from a point to the nearest point of an oriented box: the truck's
## collision rectangle, given as the transform its shape sits at and the half
## extents of that shape.
##
## Static and free of any node state so the rule can be checked with arithmetic
## rather than by standing up a physics space. Zero when the point is inside the
## box, which is what a hydrant the truck has parked on top of should read as.
static func distance_to_box(
	point: Vector2, box_transform: Transform2D, half_extents: Vector2
) -> float:
	var local: Vector2 = box_transform.affine_inverse() * point
	var nearest := Vector2(
		clampf(local.x, -half_extents.x, half_extents.x),
		clampf(local.y, -half_extents.y, half_extents.y)
	)
	return local.distance_to(nearest)


## How far the hydrant is from the truck's bodywork.
func distance_to_truck(truck_transform: Transform2D, truck_half_extents: Vector2) -> float:
	return distance_to_box(global_position, truck_transform, truck_half_extents)


## Range is measured to the truck's nearest edge, never to its centre. Measuring
## to the centre made the rule depend on which way the truck happened to be
## pointing: nose in at a kerb put the centre 45 units further out than
## alongside did, for the same bumper in the same place.
func is_truck_in_range(truck_transform: Transform2D, truck_half_extents: Vector2) -> bool:
	return distance_to_truck(truck_transform, truck_half_extents) <= get_interaction_radius()


func is_truck_slow_enough(truck_speed: float) -> bool:
	return absf(truck_speed) <= balance.hydrant_max_hookup_speed


## The whole hookup decision for one frame, kept in one place so the rules that
## cancel a refill cannot drift apart from the rules that start one.
##
## Returns the prompt to show. The caller starts or cancels the refill on the
## water system according to should_refill.
func evaluate(
	truck_transform: Transform2D,
	truck_half_extents: Vector2,
	truck_speed: float,
	hookup_held: bool,
	tank_is_full: bool,
	currently_refilling: bool,
	hookup_progress: float
) -> Dictionary:
	resolve_balance()

	if not is_truck_in_range(truck_transform, truck_half_extents):
		_set_active(false)
		_set_hose(false, Vector2.ZERO)
		return {"prompt": Prompt.NONE, "should_refill": false}

	_set_active(true)

	if tank_is_full:
		# The prompt is still shown while parked at the hydrant, so a player who
		# tops off sees why the fill stopped rather than it silently ending.
		_set_hose(false, Vector2.ZERO)
		return {"prompt": Prompt.TANK_FULL, "should_refill": false}

	if not is_truck_slow_enough(truck_speed):
		_set_hose(false, Vector2.ZERO)
		return {"prompt": Prompt.TOO_FAST, "should_refill": false}

	if not hookup_held:
		_set_hose(false, Vector2.ZERO)
		return {"prompt": Prompt.HOLD_TO_HOOK_UP, "should_refill": false}

	# Hooked up or hooking up: the hose runs to the nearest point of the truck's
	# bodywork, which is the same point the range rule measures to, so the line
	# the player sees is literally the distance the rule used.
	_set_hose(true, nearest_point_on_truck(truck_transform, truck_half_extents))

	if currently_refilling and hookup_progress >= 1.0:
		return {"prompt": Prompt.REFILLING, "should_refill": true}

	return {"prompt": Prompt.HOOKING_UP, "should_refill": true}


## The point on the truck's bodywork closest to this hydrant, in world space.
func nearest_point_on_truck(
	truck_transform: Transform2D, truck_half_extents: Vector2
) -> Vector2:
	var local: Vector2 = truck_transform.affine_inverse() * global_position
	var nearest := Vector2(
		clampf(local.x, -truck_half_extents.x, truck_half_extents.x),
		clampf(local.y, -truck_half_extents.y, truck_half_extents.y)
	)
	return truck_transform * nearest


## Prompt text. Words, not colour alone, per handoff section 6.
static func prompt_text(prompt: int, hookup_progress: float) -> String:
	match prompt:
		Prompt.TOO_FAST:
			return "Slow down to hook up"
		Prompt.HOLD_TO_HOOK_UP:
			return "Hold E to hook up"
		Prompt.HOOKING_UP:
			return "Hooking up, %d%%" % int(round(hookup_progress * 100.0))
		Prompt.REFILLING:
			return "Refilling"
		Prompt.TANK_FULL:
			return "Tank full"
		_:
			return ""


func _set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	queue_redraw()


func _set_hose(connected: bool, world_target: Vector2) -> void:
	var target: Vector2 = to_local(world_target) if connected else Vector2.ZERO
	if _hose_connected == connected and _hose_target.is_equal_approx(target):
		return
	_hose_connected = connected
	_hose_target = target
	queue_redraw()


func _draw() -> void:
	_draw_interaction_ring()
	if _hose_connected:
		_draw_hose()

	# The hydrant: a squat body, a bonnet cap and two side outlets.
	draw_rect(Rect2(Vector2(-5.0, -8.0), Vector2(10.0, 18.0)), Color("#d94b3a"))
	draw_rect(Rect2(Vector2(-8.0, 8.0), Vector2(16.0, 4.0)), Color("#a8382a"))
	draw_circle(Vector2(0.0, -9.0), 5.0, Color("#e8624f"))
	draw_rect(Rect2(Vector2(-9.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))
	draw_rect(Rect2(Vector2(5.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))


## The reach of the hookup, drawn on the ground so the player can see whether
## they are close enough BEFORE they touch E rather than by trying it.
##
## Line style carries the state as well as colour does: dashed while the truck's
## bodywork is outside the ring, solid the moment it is inside. The ring is drawn
## at the interaction radius, and the rule measures to the truck's nearest edge,
## so "the ring touches the truck" and "you can hook up" are the same picture.
func _draw_interaction_ring() -> void:
	var radius: float = get_interaction_radius()

	if _active:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_SEGMENTS, RING_IN_RANGE, 3.0, true)
		# A second, fainter ring just inside it, so an in-range hydrant reads as
		# a filled target rather than as a slightly brighter circle.
		draw_arc(Vector2.ZERO, radius - 6.0, 0.0, TAU, RING_SEGMENTS, RING_IN_RANGE_INNER, 1.5, true)
		return

	# Out of range: the same circle, broken into dashes.
	var arc: float = TAU / float(RING_DASHES)
	for index in range(RING_DASHES):
		var start: float = float(index) * arc
		draw_arc(
			Vector2.ZERO, radius, start, start + arc * RING_DASH_FRACTION,
			6, RING_OUT_OF_RANGE, 2.0, true
		)


## The hose, from the hydrant to the nearest point of the truck's bodywork,
## drawn only while the hookup is actually held. It sags: two straight lines
## between two objects on a flat plan view read as a laser, and a hose does not.
func _draw_hose() -> void:
	var span: Vector2 = _hose_target
	if span.length_squared() < 1.0:
		return
	var perpendicular: Vector2 = Vector2(-span.y, span.x).normalized()
	var sag: float = minf(span.length() * 0.14, 22.0)

	var points := PackedVector2Array()
	for step in range(HOSE_SEGMENTS + 1):
		var t: float = float(step) / float(HOSE_SEGMENTS)
		var along: Vector2 = span * t
		# A parabola, zero at both ends and widest in the middle.
		points.append(along + perpendicular * sag * (4.0 * t * (1.0 - t)))

	draw_polyline(points, HOSE_CASING, 7.0)
	draw_polyline(points, HOSE_COLOR, 4.0)
	# The couplings at each end, so it reads as connected rather than as a line
	# that happens to touch.
	draw_circle(Vector2.ZERO, 5.0, HOSE_CASING)
	draw_circle(span, 5.0, HOSE_CASING)
