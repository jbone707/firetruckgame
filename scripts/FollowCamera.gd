extends Camera2D
class_name FollowCamera
## North-up follow camera, bounded to the neighbourhood.
##
## The camera is a sibling of the truck rather than a child of it, which is what
## keeps it north-up: parenting it to the truck would inherit the truck's
## rotation and spin the whole world when the player turns. Godot's own
## ignore_rotation would also work, but following by position is explicit and
## leaves nothing to inherit by accident.

## Camera zoom. Below 1.0 means the view takes in MORE world, not less. Chosen
## with the road width: a 280 unit road at 0.9 spans 252 of the 1280 unit design
## viewport, a little under a fifth of the screen, and the player can see about
## 700 units up the road ahead, which is roughly three seconds at top speed.
const ZOOM: float = 0.9

## How far ahead of the truck the camera leads, in world units at full speed.
## Handoff section 4 asks for reasonable forward visibility.
const LOOK_AHEAD_DISTANCE: float = 220.0

var target: Node2D = null

var _look_ahead: Vector2 = Vector2.ZERO


func _ready() -> void:
	rotation = 0.0
	ignore_rotation = true
	zoom = Vector2(ZOOM, ZOOM)
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	limit_smoothed = true


## Clamps the view to the playable extent so the player never sees past the
## edge walls. Called once by Main after the map is built.
func apply_world_bounds(bounds: Rect2) -> void:
	limit_enabled = true
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.position.x + bounds.size.x)
	limit_bottom = int(bounds.position.y + bounds.size.y)


func snap_to_target() -> void:
	if target == null:
		return
	_look_ahead = Vector2.ZERO
	global_position = target.global_position
	reset_smoothing()


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired_look_ahead: Vector2 = Vector2.ZERO
	if target is TruckController:
		var truck: TruckController = target
		var speed_ratio: float = clampf(
			truck.get_forward_speed() / truck.balance.forward_max_speed, -1.0, 1.0
		)
		desired_look_ahead = truck.get_forward() * LOOK_AHEAD_DISTANCE * speed_ratio

	# Ease the lead in rather than snapping it, so a hard turn does not whip
	# the view across the screen.
	_look_ahead = _look_ahead.lerp(desired_look_ahead, clampf(delta * 3.0, 0.0, 1.0))
	global_position = target.global_position + _look_ahead
