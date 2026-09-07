extends Node2D
class_name Hydrant
## A hydrant, its interaction radius, and the hookup rules from handoff section 6.
##
## Range is a plain distance check against the truck rather than an Area2D. The
## rule is "within range and nearly stationary", both of which are one line of
## arithmetic, and a distance check is testable without standing up physics.

enum Prompt { NONE, TOO_FAST, HOLD_TO_HOOK_UP, HOOKING_UP, REFILLING, TANK_FULL }

var balance: Node = null
var hydrant_id: String = ""

var _active: bool = false


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


func is_truck_in_range(truck_position: Vector2) -> bool:
	return global_position.distance_to(truck_position) <= get_interaction_radius()


func is_truck_slow_enough(truck_speed: float) -> bool:
	return absf(truck_speed) <= balance.hydrant_max_hookup_speed


## The whole hookup decision for one frame, kept in one place so the rules that
## cancel a refill cannot drift apart from the rules that start one.
##
## Returns the prompt to show. The caller starts or cancels the refill on the
## water system according to should_refill.
func evaluate(
	truck_position: Vector2,
	truck_speed: float,
	hookup_held: bool,
	tank_is_full: bool,
	currently_refilling: bool,
	hookup_progress: float
) -> Dictionary:
	resolve_balance()

	if not is_truck_in_range(truck_position):
		_set_active(false)
		return {"prompt": Prompt.NONE, "should_refill": false}

	_set_active(true)

	if tank_is_full:
		# The prompt is still shown while parked at the hydrant, so a player who
		# tops off sees why the fill stopped rather than it silently ending.
		return {"prompt": Prompt.TANK_FULL, "should_refill": false}

	if not is_truck_slow_enough(truck_speed):
		return {"prompt": Prompt.TOO_FAST, "should_refill": false}

	if not hookup_held:
		return {"prompt": Prompt.HOLD_TO_HOOK_UP, "should_refill": false}

	if currently_refilling and hookup_progress >= 1.0:
		return {"prompt": Prompt.REFILLING, "should_refill": true}

	return {"prompt": Prompt.HOOKING_UP, "should_refill": true}


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


func _draw() -> void:
	var radius: float = get_interaction_radius()

	# The interaction radius, drawn brighter when the truck is inside it.
	var ring_color: Color = (
		Color(0.35, 0.85, 1.0, 0.55) if _active else Color(0.6, 0.75, 0.85, 0.22)
	)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ring_color, 2.0)

	# The hydrant: a squat body, a bonnet cap and two side outlets.
	draw_rect(Rect2(Vector2(-5.0, -8.0), Vector2(10.0, 18.0)), Color("#d94b3a"))
	draw_rect(Rect2(Vector2(-8.0, 8.0), Vector2(16.0, 4.0)), Color("#a8382a"))
	draw_circle(Vector2(0.0, -9.0), 5.0, Color("#e8624f"))
	draw_rect(Rect2(Vector2(-9.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))
	draw_rect(Rect2(Vector2(5.0, -3.0), Vector2(4.0, 5.0)), Color("#a8382a"))
