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

var balance: Node = null

var incident_id: String = ""
var building_id: String = ""

var health: float = 0.0
var max_health: float = 0.0
var escalation: float = 0.0
var escalation_limit: float = 0.0

var _terminal: bool = false
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
func setup(id: String, from_building_id: String, polygon: PackedVector2Array) -> void:
	resolve_balance()
	incident_id = id
	building_id = from_building_id
	health = balance.fire_starting_health
	max_health = health
	escalation = 0.0
	escalation_limit = balance.fire_escalation_duration
	_terminal = false

	collision_layer = 0b0100  # layer 3, fire_target
	collision_mask = 0
	monitoring = false
	monitorable = true

	var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(polygon, FIRE_AREA_MARGIN)
	var shape_polygon: PackedVector2Array = polygon
	if not grown.is_empty():
		shape_polygon = grown[0]

	var collision_polygon := CollisionPolygon2D.new()
	collision_polygon.polygon = shape_polygon
	add_child(collision_polygon)

	_center = Vector2.ZERO
	for point in shape_polygon:
		_center += point
	if shape_polygon.size() > 0:
		_center /= float(shape_polygon.size())

	_seed_flames(shape_polygon)
	queue_redraw()


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

	for index in range(_flame_seeds.size()):
		var seed_point: Vector2 = to_local(_flame_seeds[index])
		var flicker: float = sin(_flame_phase * 6.0 + float(index) * 1.7) * 0.18 + 1.0
		var size: float = base_size * flicker
		var outer: Color = Color(1.0, lerpf(0.55, 0.25, urgency), 0.15, 0.85)
		var inner: Color = Color(1.0, lerpf(0.9, 0.7, urgency), 0.45, 0.9)
		draw_circle(seed_point, size, outer)
		draw_circle(seed_point - Vector2(0.0, size * 0.35), size * 0.5, inner)
