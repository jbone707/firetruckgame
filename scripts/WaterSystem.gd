extends Node2D
class_name WaterSystem
## The tank, the roof turret, stream targeting, suppression and refill state.
##
## Mounted on the truck so the nozzle origin moves with it, but the turret aims
## independently of the truck's heading (handoff section 5). Aim comes in as a
## world position through set_aim_world_position(), so the mouse-to-world
## conversion happens once, in Main, where the camera is known.

signal water_changed(remaining: float, capacity: float)
signal refill_required
signal refill_started
signal refill_finished

enum RefillState { IDLE, HOOKING_UP, REFILLING }

## How wide a shape the stream sweeps, in world units. A ray alone is fiddly to
## aim at this scale, so the query is a short circle swept along the aim line.
const STREAM_QUERY_RADIUS: float = 6.0

## Circles drawn in the steam burst when the stream is landing on a fire.
## Deliberately few: handoff section 5 caps the effect budget and forbids
## anything that obscures the target.
const STEAM_PUFFS: int = 8

var balance: Node = null

var water_remaining: float = 0.0
var tank_capacity: float = 0.0

var spray_requested: bool = false
var refill_state: RefillState = RefillState.IDLE

## Set by Main each frame from the mouse. World coordinates, not screen.
var aim_world_position: Vector2 = Vector2.ZERO

## The body the stream is currently hitting, for drawing the splash. Null when
## the stream reaches its full range without hitting anything.
var _impact_point: Vector2 = Vector2.ZERO
var _has_impact: bool = false
var _stream_active: bool = false

## Whether the tick just processed actually put suppression into a fire. False
## on a miss, false against a wall, false at an empty tank, and false against a
## fire that is already out. Everything the player sees that says "this is
## working" hangs off this one flag (handoff section 5).
var _suppressing: bool = false

var _empty_announced: bool = false
var _hookup_elapsed: float = 0.0
var _steam_phase: float = 0.0

@onready var _truck: TruckController = get_parent() as TruckController


func _ready() -> void:
	resolve_balance()
	tank_capacity = balance.tank_capacity
	water_remaining = tank_capacity
	water_changed.emit(water_remaining, tank_capacity)


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


## Capacity including any purchased upgrade. Called by GameSession at the start
## of a shift, per handoff section 3: an upgrade applies to the next shift.
func configure_capacity(upgraded: bool) -> void:
	resolve_balance()
	tank_capacity = balance.tank_capacity
	if upgraded:
		tank_capacity *= balance.tank_upgrade_multiplier
	water_remaining = minf(water_remaining, tank_capacity)
	water_changed.emit(water_remaining, tank_capacity)


func fill_tank() -> void:
	water_remaining = tank_capacity
	_empty_announced = false
	water_changed.emit(water_remaining, tank_capacity)


func is_empty() -> bool:
	return water_remaining <= 0.0


## The interface from handoff section 8. Returns the amount actually consumed,
## clamped to what is in the tank, so a caller asking for more than remains
## gets the last partial tick rather than an overdraw.
func consume_water(requested: float) -> float:
	var used: float = minf(maxf(requested, 0.0), water_remaining)
	water_remaining -= used
	if used > 0.0:
		water_changed.emit(water_remaining, tank_capacity)
	return used


func add_water(amount: float) -> float:
	var added: float = minf(maxf(amount, 0.0), tank_capacity - water_remaining)
	water_remaining += added
	if added > 0.0:
		_empty_announced = false
		water_changed.emit(water_remaining, tank_capacity)
	return added


func set_aim_world_position(target: Vector2) -> void:
	aim_world_position = target


func set_spray_requested(active: bool) -> void:
	spray_requested = active


## Refilling and spraying cannot happen together, and refilling wins
## (handoff section 6).
func is_spray_allowed() -> bool:
	return refill_state == RefillState.IDLE


func is_stream_active() -> bool:
	return _stream_active


## True only while the stream is landing on a fire and taking health off it.
func is_suppressing() -> bool:
	return _suppressing


## One tick of spraying. Consumes water first, then applies suppression scaled
## by what was actually consumed, so the final partial tick before the tank runs
## dry does a proportionally smaller amount of work rather than a full tick's
## worth. Returns the water consumed.
func apply_spray_tick(delta: float, target: Object) -> float:
	_suppressing = false
	var consumed: float = consume_water(balance.spray_flow_rate * delta)
	if consumed <= 0.0:
		if not _empty_announced:
			_empty_announced = true
			refill_required.emit()
		return 0.0
	if target != null and target.has_method("apply_suppression"):
		# The fire's own answer, not the request: it returns what it actually
		# absorbed, which is zero once it is out or already terminal. Reading
		# the answer rather than assuming it is what makes "hitting" mean
		# hitting, so the steam and the HUD line cannot appear over a fire that
		# is doing nothing.
		var absorbed: float = target.apply_suppression(
			consumed * balance.suppression_per_water_unit
		)
		_suppressing = absorbed > 0.0
	return consumed


func get_nozzle_global_position() -> Vector2:
	return global_position


func _physics_process(delta: float) -> void:
	_update_turret_aim()
	_update_refill(delta)

	_steam_phase += delta

	var wants_stream: bool = spray_requested and is_spray_allowed() and not is_empty()
	if not wants_stream:
		if spray_requested and is_empty() and not _empty_announced:
			_empty_announced = true
			refill_required.emit()
		_suppressing = false
		if _stream_active:
			_stream_active = false
			queue_redraw()
		return

	var hit: Dictionary = _query_stream()
	var target: Object = hit.get("fire", null)
	_has_impact = hit.has("point")
	_impact_point = hit.get("point", Vector2.ZERO)

	apply_spray_tick(delta, target)

	_stream_active = true
	queue_redraw()


func _update_turret_aim() -> void:
	# global_rotation, not rotation: the turret must ignore the truck's heading.
	var to_target: Vector2 = aim_world_position - global_position
	if to_target.length_squared() > 1.0:
		global_rotation = to_target.angle()


## Finds what the stream hits first.
##
## The query mask covers world_static (layer 1) and fire_target (layer 3), so a
## wall between the nozzle and the fire blocks the stream. A burning building's
## fire area is deliberately grown a little beyond its own collision polygon by
## FireIncident, which is what stops the building the fire is inside from
## shielding it. Only the first hit is returned, so a second fire behind the
## first is not damaged through it.
func _query_stream() -> Dictionary:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var origin: Vector2 = global_position
	var direction: Vector2 = Vector2.RIGHT.rotated(global_rotation)
	var destination: Vector2 = origin + direction * balance.stream_range

	var query := PhysicsRayQueryParameters2D.create(origin, destination)
	query.collision_mask = 0b0101  # layer 1 world_static, layer 3 fire_target
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if _truck != null:
		query.exclude = [_truck.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return {}

	var collider: Object = result.get("collider", null)
	var hit: Dictionary = {"point": result["position"]}
	if collider != null and collider.has_method("apply_suppression"):
		hit["fire"] = collider
	elif collider != null and collider.get_parent() != null \
			and collider.get_parent().has_method("apply_suppression"):
		hit["fire"] = collider.get_parent()
	return hit


func begin_hookup() -> void:
	if refill_state != RefillState.IDLE:
		return
	refill_state = RefillState.HOOKING_UP
	_hookup_elapsed = 0.0
	refill_started.emit()


func cancel_refill() -> void:
	if refill_state == RefillState.IDLE:
		return
	refill_state = RefillState.IDLE
	_hookup_elapsed = 0.0
	refill_finished.emit()


func get_hookup_progress() -> float:
	if refill_state != RefillState.HOOKING_UP:
		return 0.0
	return clampf(_hookup_elapsed / balance.hydrant_hookup_time, 0.0, 1.0)


func _update_refill(delta: float) -> void:
	match refill_state:
		RefillState.HOOKING_UP:
			_hookup_elapsed += delta
			if _hookup_elapsed >= balance.hydrant_hookup_time:
				refill_state = RefillState.REFILLING
		RefillState.REFILLING:
			add_water(balance.hydrant_refill_rate * delta)
		_:
			pass


func reset_for_new_shift(upgraded: bool) -> void:
	resolve_balance()
	cancel_refill()
	configure_capacity(upgraded)
	fill_tank()
	spray_requested = false
	_stream_active = false
	_empty_announced = false
	queue_redraw()


func _draw() -> void:
	# The turret itself, always drawn, pointing wherever it is aimed.
	draw_circle(Vector2.ZERO, 9.0, Color("#4a5a68"))
	draw_rect(Rect2(Vector2(4.0, -3.0), Vector2(16.0, 6.0)), Color("#8fa3b0"))

	if not _stream_active:
		return

	var length: float = balance.stream_range
	if _has_impact:
		length = minf(length, to_local(_impact_point).length())

	# A tapering stream drawn in local space, since this node is rotated to aim.
	var tip: Vector2 = Vector2(length, 0.0)
	draw_line(Vector2(18.0, 0.0), tip, Color(0.55, 0.8, 1.0, 0.85), 7.0)
	draw_line(Vector2(18.0, 0.0), tip, Color(0.9, 0.97, 1.0, 0.7), 3.0)
	if not _has_impact:
		return

	if not _suppressing:
		# A miss, or a wall: water, and only water.
		draw_circle(tip, 9.0, Color(0.8, 0.93, 1.0, 0.5))
		draw_circle(tip, 4.0, Color(1.0, 1.0, 1.0, 0.7))
		return

	# Landing on a fire: the water flashes off as steam. Dense, white and
	# clearly bigger than the plain splash, because this is the one moment the
	# player needs to be sure the stream is doing something. Kept to eight
	# circles and no smoke, inside handoff section 5's effect budget, and
	# nowhere near the HUD: it is drawn at the nozzle's target in the world.
	for index in range(STEAM_PUFFS):
		var swirl: float = _steam_phase * 3.2 + float(index) * (TAU / float(STEAM_PUFFS))
		var spread: float = 7.0 + fmod(_steam_phase * 26.0 + float(index) * 5.0, 20.0)
		var puff: Vector2 = tip + Vector2(cos(swirl), sin(swirl)) * spread
		var fade: float = 1.0 - spread / 34.0
		draw_circle(puff, 5.0 + spread * 0.32, Color(1.0, 1.0, 1.0, 0.36 * fade))
	draw_circle(tip, 10.0, Color(1.0, 1.0, 1.0, 0.85))
