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
##
## This is the DEFAULT only. set_zoom below changes it during play, from the
## list in GameBalance.camera_zoom_levels, so James can pick the one that feels
## like the area he selected rather than have a number guessed for him.
const ZOOM: float = 0.9

## How far ahead of the truck the camera leads, in world units at full speed, at
## the DEFAULT zoom. Handoff section 4 asks for reasonable forward visibility.
##
## Scaled by the zoom actually in use, because the lead is a fraction of the
## screen and not a distance in the world: 220 units at 0.9 is a sixth of the
## way to the edge of the view, and holding it at 220 while the view took in
## two and a half times as much world would quietly turn the lead off.
const LOOK_AHEAD_DISTANCE: float = 220.0

## Impact shake: how far the view is thrown at a full speed crash, world units,
## and how long it takes to settle. Small and short on purpose, since the player
## is steering while it happens.
const MAX_SHAKE: float = 16.0
const SHAKE_SECONDS: float = 0.28

var target: Node2D = null

var _zoom_level: float = ZOOM
var _look_ahead: Vector2 = Vector2.ZERO
var _shake_remaining: float = 0.0
var _shake_strength: float = 0.0


func _ready() -> void:
	rotation = 0.0
	ignore_rotation = true
	set_zoom_level(_zoom_level)
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	limit_smoothed = true


## Changes how much world the view takes in. Godot's own limit clamping is
## expressed in world units and already accounts for the zoom, so the edge walls
## stay off screen at every level without the limits being recomputed; the lead
## is not, and is scaled here.
func set_zoom_level(level: float) -> void:
	_zoom_level = maxf(level, 0.01)
	zoom = Vector2(_zoom_level, _zoom_level)


func get_zoom_level() -> float:
	return _zoom_level


## The camera lead at the zoom currently in use. Public because the off-screen
## call arrow and the physics runner both need to know what the view is doing,
## and neither should be re-deriving it.
func get_look_ahead_distance() -> float:
	return LOOK_AHEAD_DISTANCE * (ZOOM / _zoom_level)


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
	_shake_remaining = 0.0
	_shake_strength = 0.0
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
		desired_look_ahead = truck.get_forward() * get_look_ahead_distance() * speed_ratio

	# Ease the lead in rather than snapping it, so a hard turn does not whip
	# the view across the screen.
	_look_ahead = _look_ahead.lerp(desired_look_ahead, clampf(delta * 3.0, 0.0, 1.0))

	var offset_shake: Vector2 = Vector2.ZERO
	if _shake_remaining > 0.0:
		_shake_remaining = maxf(_shake_remaining - delta, 0.0)
		var fade: float = _shake_remaining / SHAKE_SECONDS
		offset_shake = Vector2(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		) * _shake_strength * fade
		if _shake_remaining <= 0.0:
			_shake_strength = 0.0
	global_position = target.global_position + _look_ahead + offset_shake


## A short shake, so a crash is something the player sees happen rather than
## something they infer from a bar moving in the corner. Amount is the impact
## speed; the shake is scaled from it and capped, so a scrape is a twitch and a
## head-on is a jolt.
##
## Deliberately brief and positional only. It never rotates the camera, because
## the whole reason this camera is a sibling of the truck rather than a child is
## to keep the world north up, and a rotating shake would undo that for as long
## as it lasted.
func shake(impact_speed: float) -> void:
	# Scaled by the zoom for the same reason the lead is: MAX_SHAKE is written
	# as a world distance but is meant as a fraction of the screen, and a jolt
	# that is barely a pixel at the widest zoom is not a jolt.
	var strength: float = (
		clampf(impact_speed / 250.0, 0.0, 1.0) * MAX_SHAKE * (ZOOM / _zoom_level)
	)
	_shake_remaining = SHAKE_SECONDS
	_shake_strength = maxf(_shake_strength, strength)
