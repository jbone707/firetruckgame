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

## How many SECONDS of travel the camera tries to lead by (Milestone 10 Part 5).
##
## The lead is a time and not a distance, because what a driver needs is the
## road they are about to be on: 220 units of lead is a second of warning at 220
## units/second and four seconds of warning at 55, and the first of those is the
## one that matters. At the engine's top speed of 250 this asks for 500 units.
const LOOK_AHEAD_SECONDS: float = 2.0

## How far the lead may push the engine from the middle of the frame, as a
## fraction of the screen's HEIGHT at the zoom in use.
##
## A third, which puts the engine five sixths of the way down the screen at full
## speed: inside the lower third, with a third of a screen still behind it and
## no possibility of it reaching the edge. THIS CLAMP IS WHAT ACTUALLY DECIDES
## THE LEAD at every zoom the game ships, and that is deliberate rather than a
## disappointment. Two seconds of travel is 500 world units and half the screen
## at the default zoom is 400, so an uncapped two second lead would put the
## engine off the bottom of its own view. What the player gets instead is the
## engine low in the frame with about 670 units of road ahead of it at 0.9, and
## more at the wider levels, which is between two and a half and four seconds of
## warning depending on how far out they have chosen to look.
##
## In screens rather than world units for the same reason the overscan is: the
## question is where the engine sits in the FRAME, and the same world distance is
## a different fraction of the frame at each of the three zoom levels.
const MAX_LEAD_SCREENS: float = 1.0 / 3.0

## Impact shake: how far the view is thrown at a full speed crash, world units,
## and how long it takes to settle. Small and short on purpose, since the player
## is steering while it happens.
const MAX_SHAKE: float = 16.0
const SHAKE_SECONDS: float = 0.28

## How far past the map's own bounds the view may reach, as a fraction of the
## screen's HEIGHT at the zoom in use (Milestone 8 Part 2). Half a screen.
##
## In screens rather than world units on purpose: the whole point is where the
## truck sits in the FRAME, and the same world distance is a different fraction
## of the frame at each of the three zoom levels.
const OVERSCAN_SCREENS: float = 0.5

var target: Node2D = null

var _bounds: Rect2 = Rect2()
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


## Changes how much world the view takes in, and re-derives everything measured
## against the screen rather than against the world: the limits, because the
## overscan is half a screen, and the lead, which is read live.
func set_zoom_level(level: float) -> void:
	_zoom_level = maxf(level, 0.01)
	zoom = Vector2(_zoom_level, _zoom_level)
	_apply_limits()


func get_zoom_level() -> float:
	return _zoom_level


## The furthest the camera may lead at the zoom currently in use, in world units.
## Public because the off-screen call arrow and the physics runner both need to
## know what the view is doing, and neither should be re-deriving it.
func get_look_ahead_distance() -> float:
	return _screen_height() * MAX_LEAD_SCREENS


## How much world the screen's height takes in at the zoom currently in use.
func _screen_height() -> float:
	var view: Vector2 = Vector2(get_viewport_rect().size)
	if view == Vector2.ZERO:
		view = Vector2(1280.0, 720.0)
	return view.y / _zoom_level


## What the lead WANTS to be at this speed, before the clamp: two seconds of
## travel, signed, so reversing pulls the view back the other way.
func desired_lead_for_speed(forward_speed: float) -> float:
	return forward_speed * LOOK_AHEAD_SECONDS


## The lead the camera is currently applying, in world units. Public so a check
## can watch it ease rather than having to infer smoothness from where the engine
## is drawn, which also carries the camera's own position smoothing.
func get_look_ahead() -> Vector2:
	return _look_ahead


## Clamps the view to the playable extent, plus an overscan (Milestone 8
## Part 2). Called by Main after the map is built, and again whenever the zoom
## changes, because the overscan is measured in SCREEN height and so is a
## different number of world units at every zoom level.
##
## Before the overscan the limits were the world bounds exactly, which meant the
## camera stopped dead as the truck approached a wall and the truck slid to the
## edge of the screen and sat there, half a truck from the frame. At the top
## edge of Windsor, where a road ran right up to the wall, the player drove the
## last stretch pinned to the top of the view with nothing ahead of them. Half a
## screen of overscan keeps the truck near the middle of the frame everywhere,
## and MapBuilder draws a dark band outside the map so the overscan shows ground
## rather than the viewport's clear colour.
func apply_world_bounds(bounds: Rect2) -> void:
	_bounds = bounds
	_apply_limits()


func _apply_limits() -> void:
	if _bounds.size == Vector2.ZERO:
		return
	var overscan: Vector2 = _overscan()
	limit_enabled = true
	limit_left = int(_bounds.position.x - overscan.x)
	limit_top = int(_bounds.position.y - overscan.y)
	limit_right = int(_bounds.end.x + overscan.x)
	limit_bottom = int(_bounds.end.y + overscan.y)


## How far past the world the view may reach, in world units: half the screen's
## height at the zoom in use, on both axes. Half a SCREEN rather than a fixed
## distance, so the truck sits the same way in the frame at every zoom level.
func _overscan() -> Vector2:
	var view: Vector2 = Vector2(get_viewport_rect().size)
	if view == Vector2.ZERO:
		view = Vector2(1280.0, 720.0)
	var half_height: float = (view.y / _zoom_level) * 0.5
	return Vector2(half_height, half_height) * OVERSCAN_SCREENS


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
		# Two seconds of travel, clamped so the engine cannot be pushed out of
		# the lower third of its own view. The clamp is what binds at every
		# shipped zoom; see MAX_LEAD_SCREENS.
		var most: float = get_look_ahead_distance()
		var lead: float = clampf(
			desired_lead_for_speed(truck.get_forward_speed()), -most, most
		)
		desired_look_ahead = truck.get_forward() * lead

	# Ease the lead in rather than snapping it, so a hard turn does not whip the
	# view across the screen and lifting off the throttle does not jerk it back.
	# The rate is the whole of "smooth, no snapping at throttle changes": at
	# three per second the view takes about a second to answer a change of speed,
	# which is slower than the engine can change its mind.
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
