extends Area2D
class_name FireIncident
## One dispatched fire: its health, its escalation, and its terminal state.
##
## This is an Area2D on the fire_target layer so the water stream's query hits
## it directly. Its shape is the burning building's own polygon grown outward by
## FIRE_AREA_MARGIN, which is what makes the fire hittable at the exterior: the
## grown edge sits in front of the building's wall, so the stream reaches the
## fire instead of being blocked by the building the fire is inside
## (handoff section 5).
##
## Health and escalation are deliberately separate values. Spraying reduces
## health. Escalation advances on its own from dispatch to loss and is not
## slowed by suppression, because handoff section 5 asks for no hidden rules in
## this version.

signal incident_extinguished(incident_id: String)
signal incident_lost(incident_id: String)
signal state_changed

## How far beyond the building wall the hittable fire edge sits, in world units.
const FIRE_AREA_MARGIN: float = 14.0

## Flame glyphs drawn per fire. Kept small on purpose: handoff section 5 caps the
## effect budget and forbids smoke that obscures the target or the controls.
const FLAME_COUNT: int = 7

## How far above the fire's centre the destination marker hangs, world units.
const MARKER_HEIGHT: float = 62.0

## The destination marker's fill. Matches the off-screen arrow so the two read
## as the same indicator.
const MARKER_COLOR: Color = Color(1.0, 0.55, 0.2, 0.95)

## The fire health bar drawn over the active call, world units.
const BAR_SIZE: Vector2 = Vector2(84.0, 9.0)

var balance: Node = null

var incident_id: String = ""
var building_id: String = ""

var health: float = 0.0
var max_health: float = 0.0
var escalation: float = 0.0
var escalation_limit: float = 0.0

var _terminal: bool = false
var _is_active_call: bool = false
var _flame_phase: float = 0.0
var _flame_seeds: Array[Vector2] = []
var _center: Vector2 = Vector2.ZERO


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


## Builds the incident in place. polygon is the burning building's own outline
## in world coordinates.
func setup(
	id: String,
	from_building_id: String,
	polygon: PackedVector2Array,
	travel_distance: float = 0.0
) -> void:
	resolve_balance()
	incident_id = id
	building_id = from_building_id
	health = balance.fire_starting_health
	max_health = health
	escalation = 0.0
	escalation_limit = escalation_limit_for(balance, travel_distance)
	_terminal = false

	collision_layer = 0b0100  # layer 3, fire_target
	collision_mask = 0
	monitoring = false
	monitorable = true

	var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(polygon, FIRE_AREA_MARGIN)
	var shape_polygon: PackedVector2Array = polygon
	if not grown.is_empty():
		shape_polygon = grown[0]

	_center = Vector2.ZERO
	for point in shape_polygon:
		_center += point
	if shape_polygon.size() > 0:
		_center /= float(shape_polygon.size())

	# The node itself has to stand where the fire stands. It used to be left at
	# the world origin with the building's world-space outline hung off it as a
	# child collision shape, which drew and collided correctly but left
	# global_position reading (0, 0) for every incident on the map. Anything
	# that asked this node where it was, the off-screen arrow included, was
	# told "the north-west corner of the neighbourhood", forever.
	global_position = _center

	var collision_polygon := CollisionPolygon2D.new()
	var local_polygon := PackedVector2Array()
	for point in shape_polygon:
		local_polygon.append(point - _center)
	collision_polygon.polygon = local_polygon
	add_child(collision_polygon)

	_seed_flames(shape_polygon)
	queue_redraw()


## How long this call gets before it is lost: a fixed base for fighting the fire,
## plus an allowance for the distance the truck has to cover to reach it.
##
## The base alone had to cover the worst drive on the map when it was one flat
## number, which made every near call slack and told the player nothing. Paying
## for the distance separately means a far call is a longer drive rather than a
## harder fire, and the number on the HUD still counts down in plain seconds
## with nothing hidden behind it: it simply starts higher when the fire is
## further away.
##
## travel_distance is the length of the shortest route ALONG THE ROADS, which
## RoadGraph.route_length measures. It used to be a grid distance, |dx| + |dy|,
## which is the right answer only while every road is axis aligned: on a map
## whose roads bend and meet at real angles a grid distance is not any journey
## the truck could make, and it under-pays a call the roads have to reach the
## long way round. Nothing here computes the distance; Main measures it at
## dispatch, from wherever the truck actually is.
static func escalation_limit_for(tuning: Node, travel_distance: float) -> float:
	var base: float = tuning.fire_escalation_duration
	if tuning.escalation_travel_speed <= 0.0:
		return base
	var allowance: float = maxf(travel_distance, 0.0) / tuning.escalation_travel_speed
	return base + minf(allowance, tuning.escalation_travel_allowance_max)


func _seed_flames(polygon: PackedVector2Array) -> void:
	_flame_seeds.clear()
	if polygon.is_empty():
		return
	# Flames sit on the outline rather than filling the roof, so the building
	# underneath and the marker over it both stay readable.
	var step: float = float(polygon.size()) / float(FLAME_COUNT)
	for index in range(FLAME_COUNT):
		var point: Vector2 = polygon[int(index * step) % polygon.size()]
		_flame_seeds.append(point.lerp(_center, 0.18))


## Suppression already scaled by the water that paid for it. Returns the amount
## actually absorbed, which is less than requested on the hit that puts the fire
## out, so nothing over-credits the last tick.
func apply_suppression(amount: float) -> float:
	if _terminal or amount <= 0.0:
		return 0.0
	var absorbed: float = minf(amount, health)
	health -= absorbed
	state_changed.emit()
	if health <= 0.0:
		_finish(true)
	return absorbed


## Marks this incident as the call the player has been sent to. Only the active
## call carries a destination marker, so a cleared fire still on screen through
## the confirmation pause does not compete with the next one.
func set_active_call(active: bool) -> void:
	if _is_active_call == active:
		return
	_is_active_call = active
	queue_redraw()


func is_active_call() -> bool:
	return _is_active_call


func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(health / max_health, 0.0, 1.0)


## Seconds left before the incident is lost. This is the margin the HUD shows.
func get_escalation_remaining() -> float:
	return maxf(escalation_limit - escalation, 0.0)


func get_escalation_ratio() -> float:
	if escalation_limit <= 0.0:
		return 0.0
	return clampf(escalation / escalation_limit, 0.0, 1.0)


func is_terminal() -> bool:
	return _terminal


func _process(delta: float) -> void:
	# PAUSABLE, so pause stops escalation and the animation together.
	if _terminal:
		return
	escalation += delta
	_flame_phase += delta
	if escalation >= escalation_limit:
		_finish(false)
		return
	queue_redraw()


## The single terminal transition, guarded so extinguishment and loss can each
## happen once and cannot both happen. Everything downstream, credits included,
## hangs off these two signals firing exactly once.
func _finish(extinguished: bool) -> void:
	if _terminal:
		return
	_terminal = true
	set_process(false)
	monitorable = false
	queue_redraw()
	if extinguished:
		health = 0.0
		incident_extinguished.emit(incident_id)
	else:
		escalation = escalation_limit
		incident_lost.emit(incident_id)


func _draw() -> void:
	if _terminal:
		return

	# Flames shrink with remaining health, so progress is visible without
	# reading a bar, and grow more urgent as escalation climbs.
	var health_ratio: float = get_health_ratio()
	var urgency: float = get_escalation_ratio()
	var base_size: float = lerpf(6.0, 15.0, health_ratio)

	# Flames go out as well as shrink. A half extinguished fire showing all
	# seven flames at nine tenths the size reads as "nothing is happening";
	# losing flames one at a time is the difference a player can actually see
	# from the street. Never below one while the fire is alive, so a fire on its
	# last few points of health is still visibly a fire.
	var lit: int = maxi(1, int(ceil(float(_flame_seeds.size()) * health_ratio)))

	for index in range(lit):
		var seed_point: Vector2 = to_local(_flame_seeds[index])
		var flicker: float = sin(_flame_phase * 6.0 + float(index) * 1.7) * 0.18 + 1.0
		var size: float = base_size * flicker
		var outer: Color = Color(1.0, lerpf(0.55, 0.25, urgency), 0.15, 0.85)
		var inner: Color = Color(1.0, lerpf(0.9, 0.7, urgency), 0.45, 0.9)
		draw_circle(seed_point, size, outer)
		draw_circle(seed_point - Vector2(0.0, size * 0.35), size * 0.5, inner)

	if _is_active_call:
		_draw_destination_marker()
		_draw_health_bar(health_ratio)


## A chevron hanging over the burning building: the on-screen half of the pair
## the off-screen arrow completes. Drawn above the fire rather than over it so
## the flames and the building stay readable (handoff section 5's effect budget).
func _draw_destination_marker() -> void:
	var anchor := Vector2(0.0, -MARKER_HEIGHT + sin(_flame_phase * 2.4) * 3.0)
	var body := PackedVector2Array([
		anchor + Vector2(-13.0, -18.0),
		anchor + Vector2(13.0, -18.0),
		anchor,
	])
	draw_colored_polygon(body, MARKER_COLOR)
	draw_polyline(
		PackedVector2Array([body[0], body[1], body[2], body[0]]),
		Color(0.1, 0.06, 0.02, 0.9),
		2.0
	)


## How much fire is left, over the building, and only for the call the player
## has been sent to. Shown as a bar AND as a percentage, because a bar alone
## carries its meaning in length and colour and this game does not let colour be
## the only carrier (handoff section 6).
func _draw_health_bar(health_ratio: float) -> void:
	var origin := Vector2(-BAR_SIZE.x * 0.5, -MARKER_HEIGHT - 46.0)
	var full := Rect2(origin, BAR_SIZE)

	draw_rect(full.grow(2.0), Color(0.06, 0.05, 0.05, 0.75))
	draw_rect(full, Color(0.22, 0.20, 0.20, 0.9))
	draw_rect(
		Rect2(origin, Vector2(BAR_SIZE.x * health_ratio, BAR_SIZE.y)),
		Color(0.95, 0.45, 0.15, 0.95)
	)
	draw_string(
		ThemeDB.fallback_font,
		origin + Vector2(BAR_SIZE.x + 8.0, BAR_SIZE.y),
		"%d%%" % int(round(health_ratio * 100.0)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		Color(1.0, 0.92, 0.82, 0.95)
	)
