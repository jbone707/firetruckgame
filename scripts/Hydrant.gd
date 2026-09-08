extends Node2D
class_name Hydrant
## A hydrant, its interaction radius, and the automatic hookup.
##
## Range is a plain distance check against the truck rather than an Area2D. The
## rule is "within range and moving no faster than a creep", both of which are
## one line of arithmetic, and a distance check is testable without standing up
## physics.
##
## THE HOOKUP IS AUTOMATIC AND THE HOSE IS THE HOOKUP (Milestone 9 Part 0).
## Handoff §6 had the player hold E for two seconds and forbade spraying while
## refilling. James replaced both: rolling into the radius slowly enough throws
## the hose out on its own, refilling starts when it lands, spraying is allowed
## throughout and the two flows net out, and driving away pulls the hose tight
## until it snaps. There is no hydrant key any more.
##
## The whole of that lives here, in one state machine, so the rules that end a
## refill cannot drift apart from the rules that start one. Main calls
## evaluate() once per physics frame per hydrant and does what it is told.

## Three states, not four. There was a RETRACTING that reeled the hose in when
## the tank filled; it is gone, because a fill finishes long before a truck has
## driven far enough to pull the hose tight, so it ran every single time and the
## snap never happened. See _tick_refilling.
enum State { IDLE, LAUNCHING, REFILLING }

enum Prompt { NONE, TOO_FAST, HOOKING_UP, REFILLING, TANK_FULL, SNAPPED }

## The interaction ring on the ground. Dashed means out of reach, solid means
## the truck is close enough for the hose to go out.
const RING_SEGMENTS: int = 64
const RING_DASHES: int = 24
const RING_DASH_FRACTION: float = 0.55
const RING_IN_RANGE: Color = Color(0.35, 0.85, 1.0, 0.6)
const RING_IN_RANGE_INNER: Color = Color(0.35, 0.85, 1.0, 0.25)
const RING_OUT_OF_RANGE: Color = Color(0.62, 0.76, 0.86, 0.3)

## The hose drawn from the hydrant to the truck.
const HOSE_SEGMENTS: int = 14
const HOSE_COLOR: Color = Color(0.92, 0.94, 0.85, 0.95)
const HOSE_CASING: Color = Color(0.30, 0.33, 0.30, 0.9)

## How far a taut hose shakes, world units, and how fast. Small on purpose: this
## is a line under strain, not a wobbling rope, and at the zooms this game is
## played at anything larger reads as an animation glitch.
const HOSE_TREMBLE_AMPLITUDE: float = 3.5
const HOSE_TREMBLE_RATE: float = 34.0

## Seconds the snap flick and its splash are drawn for. Shorter than the
## "Hose snapped" prompt (hydrant_snap_message_time), because the picture is a
## thing that happened and the words are the explanation of it.
const SNAP_EFFECT_TIME: float = 0.35

## How far back toward the hydrant the loose end whips, as a fraction of the
## span it snapped at, and the size of the splash left at the truck end.
const SNAP_RECOIL_FRACTION: float = 0.35
const SNAP_SPLASH_RADIUS: float = 16.0

var balance: Node = null
var hydrant_id: String = ""

var _active: bool = false
var _state: State = State.IDLE

## Seconds spent in LAUNCHING, which is what drives how much of the hose is out.
var _state_elapsed: float = 0.0

## Counts down after a snap. See GameBalance.hydrant_rehook_delay:
## it only counts while the truck is NOT both in range and moving.
var _rehook_lock: float = 0.0

var _snap_message_remaining: float = 0.0
var _snap_effect_remaining: float = 0.0
var _snap_span: Vector2 = Vector2.ZERO

var _tremble_phase: float = 0.0

## Where the hose ends, in this hydrant's local space, and how much of it is
## out: 0 while it is still coiled, 1 once it has reached the truck.
var _hose_target: Vector2 = Vector2.ZERO
var _hose_extension: float = 0.0

## Whether last frame drew anything that moves, so the frame that stops moving
## still gets one redraw to clear itself.
var _was_animating: bool = false


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


func get_state() -> State:
	return _state


## True while a hose is out at all. Main uses
## it to decide which hydrant's prompt wins when two are somehow both in play.
func has_hose_out() -> bool:
	return _state != State.IDLE


## How long the hose currently is, world units, or 0 when there is none out.
func get_hose_length() -> float:
	return _hose_target.length() if _hose_extension > 0.0 else 0.0


## Whether the hose is being dragged rather than lying slack: the thin, shaking
## line. A query rather than a drawing detail so a test can ask the question the
## player is being shown the answer to.
func is_hose_taut() -> bool:
	resolve_balance()
	return _hose_extension > 0.0 and _hose_target.length() > balance.hydrant_hose_slack_distance


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


## How far the hydrant is from the truck's bodywork. This one number is the
## range rule, the hose's length, the slack test and the snap test, so the line
## the player sees going tight is literally the distance the rules are using.
func distance_to_truck(truck_transform: Transform2D, truck_half_extents: Vector2) -> float:
	return distance_to_box(global_position, truck_transform, truck_half_extents)


## Range is measured to the truck's nearest edge, never to its centre. Measuring
## to the centre made the rule depend on which way the truck happened to be
## pointing: nose in at a kerb put the centre 45 units further out than
## alongside did, for the same bumper in the same place.
func is_truck_in_range(truck_transform: Transform2D, truck_half_extents: Vector2) -> bool:
	return distance_to_truck(truck_transform, truck_half_extents) <= get_interaction_radius()


func is_truck_slow_enough(truck_speed: float) -> bool:
	resolve_balance()
	return absf(truck_speed) <= balance.hydrant_max_hookup_speed


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


## One physics frame of this hydrant. Returns the prompt to show and whether
## water should be flowing this frame; the caller applies the second to the
## water system and picks one of the first to display.
##
## Everything that can start, sustain or end a refill is in here. Nothing about
## it reads the keyboard.
func evaluate(
	delta: float,
	truck_transform: Transform2D,
	truck_half_extents: Vector2,
	truck_speed: float,
	water_remaining: float,
	tank_capacity: float
) -> Dictionary:
	resolve_balance()

	_tremble_phase += delta
	_snap_message_remaining = maxf(_snap_message_remaining - delta, 0.0)
	_snap_effect_remaining = maxf(_snap_effect_remaining - delta, 0.0)

	var distance: float = distance_to_truck(truck_transform, truck_half_extents)
	var in_range: bool = distance <= get_interaction_radius()
	var slow: bool = is_truck_slow_enough(truck_speed)
	var tank_full: bool = water_remaining >= tank_capacity

	# The lock runs down through any frame in which the truck was not both in
	# range and moving. A truck rocking across the edge of the radius is exactly
	# the case that never satisfies it, which is the point of it.
	if in_range and not slow:
		_rehook_lock = balance.hydrant_rehook_delay if _rehook_lock > 0.0 else 0.0
	else:
		_rehook_lock = maxf(_rehook_lock - delta, 0.0)

	_set_active(in_range)

	var prompt: int = Prompt.NONE
	var should_refill: bool = false

	match _state:
		State.IDLE:
			prompt = _tick_idle(in_range, slow, tank_full)
		State.LAUNCHING:
			var launched: Dictionary = _tick_launching(delta, distance, truck_transform, truck_half_extents)
			prompt = launched["prompt"]
		State.REFILLING:
			var filling: Dictionary = _tick_refilling(distance, tank_full, truck_transform, truck_half_extents)
			prompt = filling["prompt"]
			should_refill = filling["should_refill"]

	# A snap outranks whatever the state machine settled on, for as long as the
	# message lasts: it is the answer to something that just happened to the
	# player, and "Slow down to hook up" underneath a hose that has just let go
	# is not an answer.
	if _snap_message_remaining > 0.0:
		prompt = Prompt.SNAPPED

	# Only the hose and the snap animate, and only one hydrant on the map is
	# ever doing either. Redrawing the other eight every frame for a ring that
	# has not changed is a cost this project cannot justify with a phone next.
	var animating: bool = _hose_extension > 0.0 or _snap_effect_remaining > 0.0
	if animating or _was_animating:
		queue_redraw()
	_was_animating = animating

	return {"prompt": prompt, "should_refill": should_refill, "state": _state}


func _tick_idle(in_range: bool, slow: bool, tank_full: bool) -> int:
	_clear_hose()
	if not in_range:
		return Prompt.NONE
	if tank_full:
		return Prompt.TANK_FULL
	if not slow:
		return Prompt.TOO_FAST
	if _rehook_lock > 0.0:
		# In range, stopped, wanting water, and the hydrant is still settling.
		# Deliberately silent: the snap message covers the first second of this,
		# and inventing a line for the rest would be telling the player about
		# the implementation.
		return Prompt.NONE
	_state = State.LAUNCHING
	_state_elapsed = 0.0
	return Prompt.HOOKING_UP


func _tick_launching(
	delta: float, distance: float, truck_transform: Transform2D, truck_half_extents: Vector2
) -> Dictionary:
	_state_elapsed += delta
	if _snap_if_stretched(distance, truck_transform, truck_half_extents):
		return {"prompt": Prompt.SNAPPED}
	_set_hose(
		nearest_point_on_truck(truck_transform, truck_half_extents),
		clampf(_state_elapsed / balance.hydrant_hose_launch_time, 0.0, 1.0)
	)
	if _state_elapsed >= balance.hydrant_hose_launch_time:
		_state = State.REFILLING
		_state_elapsed = 0.0
	return {"prompt": Prompt.HOOKING_UP}


## Hooked up. A full tank stops the water and nothing else: THE HOSE STAYS ON
## UNTIL IT IS PULLED OFF.
##
## It used to reel itself in when the tank filled, which is what the milestone
## prompt asked for and is what stole the feature. A fill is two seconds, and a
## player leaving a hydrant is barely moving for the first of them, so the tank
## was always full and the hose always retracted before the truck had gone the
## 200 units that make it go tight. James played it and reported exactly that:
## "the hose doesnt go taught and snap. it does automatic refill." Measured
## afterwards, from a nearly empty tank and flat out: full at 143 units from the
## hydrant, which is inside the slack distance, so the retract had already
## started every time.
##
## Now there is one way off a hydrant and it is the one he described: you drive,
## it goes tight, it snaps. Which also makes the taut hose worth drawing.
func _tick_refilling(
	distance: float, tank_full: bool, truck_transform: Transform2D, truck_half_extents: Vector2
) -> Dictionary:
	if _snap_if_stretched(distance, truck_transform, truck_half_extents):
		return {"prompt": Prompt.SNAPPED, "should_refill": false}
	_set_hose(nearest_point_on_truck(truck_transform, truck_half_extents), 1.0)
	if tank_full:
		return {"prompt": Prompt.TANK_FULL, "should_refill": false}
	return {"prompt": Prompt.REFILLING, "should_refill": true}




## Snaps the hose if the truck has pulled past the snap distance, and reports
## whether it did. Refilling stops on this frame, not the next one, because the
## caller reads should_refill from the same return.
func _snap_if_stretched(
	distance: float, truck_transform: Transform2D, truck_half_extents: Vector2
) -> bool:
	if distance < balance.hydrant_hose_snap_distance:
		return false
	_snap_span = to_local(nearest_point_on_truck(truck_transform, truck_half_extents))
	_snap_effect_remaining = SNAP_EFFECT_TIME
	_snap_message_remaining = balance.hydrant_snap_message_time
	_release()
	return true


## Back to idle, with the settling clock started. Only a snap gets here now.
func _release() -> void:
	_state = State.IDLE
	_state_elapsed = 0.0
	_rehook_lock = balance.hydrant_rehook_delay
	_clear_hose()


## Prompt text. Words, not colour alone, per handoff section 6. The refill line
## carries the numbers because it is the one prompt a player is watching to
## decide when to leave.
static func prompt_text(prompt: int, water_remaining: float, tank_capacity: float) -> String:
	match prompt:
		Prompt.TOO_FAST:
			return "Slow down to hook up"
		Prompt.HOOKING_UP:
			return "Hooking up"
		Prompt.REFILLING:
			return "Refilling, %d/%d units" % [
				int(floor(water_remaining)), int(round(tank_capacity))
			]
		Prompt.TANK_FULL:
			return "Tank full"
		Prompt.SNAPPED:
			return "Hose snapped"
		_:
			return ""


func reset_for_new_shift() -> void:
	resolve_balance()
	_state = State.IDLE
	_state_elapsed = 0.0
	_rehook_lock = 0.0
	_snap_message_remaining = 0.0
	_snap_effect_remaining = 0.0
	_clear_hose()
	_was_animating = false
	_set_active(false)
	queue_redraw()


func _set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	queue_redraw()


func _set_hose(world_target: Vector2, extension: float) -> void:
	_hose_target = to_local(world_target)
	_hose_extension = extension


func _clear_hose() -> void:
	_hose_target = Vector2.ZERO
	_hose_extension = 0.0


func _draw() -> void:
	_draw_interaction_ring()
	if _hose_extension > 0.0:
		_draw_hose()
	if _snap_effect_remaining > 0.0:
		_draw_snap()

	# The hydrant: a squat body, a bonnet cap and two side outlets.
	draw_rect(Rect2(Vector2(-5.0, -8.0), Vector2(10.0, 18.0)), Color("#d94b3a"))
	draw_rect(Rect2(Vector2(-8.0, 8.0), Vector2(16.0, 4.0)), Color("#a8382a"))
	draw_circle(Vector2(0.0, -9.0), 5.0, Color("#e8624f"))
	draw_rect(Rect2(Vector2(-9.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))
	draw_rect(Rect2(Vector2(5.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))


## The reach of the hookup, drawn on the ground so the player can see whether
## they are close enough BEFORE the hose goes out rather than by trying it.
##
## Line style carries the state as well as colour does: dashed while the truck's
## bodywork is outside the ring, solid the moment it is inside. The ring is drawn
## at the interaction radius, and the rule measures to the truck's nearest edge,
## so "the ring touches the truck" and "the hose will go out" are the same
## picture. Note the ring is where a hookup STARTS: a connected hose reaches
## well past it, out to hydrant_hose_snap_distance.
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


## The hose, from the hydrant to the nearest point of the truck's bodywork.
##
## Three looks, and they are the whole of the feedback: a hose lying slack, a
## hose being dragged, and a hose that has let go. Slack it sags, because two
## straight lines between two objects on a flat plan view read as a laser and a
## hose does not. Dragged it goes straight, thin and shaky, which is the warning
## that the next few units of street will cost the refill. The tip travels the
## span while it is launching or coming back in, so the throw and the retract
## are the same drawing at a different extension.
func _draw_hose() -> void:
	var span: Vector2 = _hose_target * _hose_extension
	if span.length_squared() < 1.0:
		return

	var full_length: float = _hose_target.length()
	var taut: bool = full_length > balance.hydrant_hose_slack_distance

	var points := PackedVector2Array()
	if taut:
		# Straight, with a shake whose size does not grow with the span: a hose
		# under strain vibrates, it does not swing.
		var perpendicular: Vector2 = Vector2(-span.y, span.x).normalized()
		for step in range(HOSE_SEGMENTS + 1):
			var t: float = float(step) / float(HOSE_SEGMENTS)
			var shake: float = sin(_tremble_phase * HOSE_TREMBLE_RATE + t * 9.0)
			# Pinned at both ends, loosest in the middle, like a plucked string.
			points.append(
				span * t
				+ perpendicular * shake * HOSE_TREMBLE_AMPLITUDE * sin(t * PI)
			)
		draw_polyline(points, HOSE_CASING, 4.0)
		draw_polyline(points, HOSE_COLOR, 2.0)
	else:
		var perpendicular: Vector2 = Vector2(-span.y, span.x).normalized()
		var sag: float = minf(span.length() * 0.14, 22.0)
		for step in range(HOSE_SEGMENTS + 1):
			var t: float = float(step) / float(HOSE_SEGMENTS)
			# A parabola, zero at both ends and widest in the middle.
			points.append(span * t + perpendicular * sag * (4.0 * t * (1.0 - t)))
		draw_polyline(points, HOSE_CASING, 7.0)
		draw_polyline(points, HOSE_COLOR, 4.0)

	# The couplings at each end, so it reads as connected rather than as a line
	# that happens to touch. Only the truck end while the hose is still in the
	# air: there is nothing to couple to yet.
	draw_circle(Vector2.ZERO, 5.0, HOSE_CASING)
	if _hose_extension >= 1.0:
		draw_circle(span, 5.0, HOSE_CASING)


## The moment it lets go: the loose end whips back toward the hydrant while it
## fades, and the water still in the line lands where the coupling was.
func _draw_snap() -> void:
	var progress: float = 1.0 - _snap_effect_remaining / SNAP_EFFECT_TIME
	var fade: float = 1.0 - progress

	var recoil: Vector2 = _snap_span * lerpf(1.0, SNAP_RECOIL_FRACTION, progress)
	var perpendicular: Vector2 = Vector2(-recoil.y, recoil.x).normalized()
	var whip: float = 26.0 * progress * fade

	var points := PackedVector2Array()
	for step in range(HOSE_SEGMENTS + 1):
		var t: float = float(step) / float(HOSE_SEGMENTS)
		points.append(recoil * t + perpendicular * whip * sin(t * PI))
	draw_polyline(points, Color(HOSE_COLOR, 0.85 * fade), 3.0)

	# The splash at the truck end, where the coupling was when it went.
	draw_circle(_snap_span, SNAP_SPLASH_RADIUS * (0.4 + progress), Color(0.8, 0.93, 1.0, 0.55 * fade))
	draw_circle(_snap_span, SNAP_SPLASH_RADIUS * 0.45, Color(1.0, 1.0, 1.0, 0.7 * fade))
