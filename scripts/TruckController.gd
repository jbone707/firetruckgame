extends CharacterBody2D
class_name TruckController
## Arcade driving, heading-relative steering, and impact damage for the engine.
##
## Orientation convention, used consistently across the project: the truck's
## local +X axis is forward, so rotation 0 points right, which is Godot's own
## 2D convention. Forward is Vector2.RIGHT.rotated(rotation). Nothing in this
## project steers relative to screen axes.
##
## Input never reaches this script directly. Main reads the actions and calls
## set_drive_intent(), so a later touch or gamepad layer can drive the same
## logic without this file knowing anything about a keyboard (handoff section 8).

signal condition_changed(condition: float, max_condition: float)
signal truck_damaged(amount: float, impact_speed: float)
signal truck_destroyed

## Speed at which steering reaches full authority. Below this the truck turns
## proportionally less, so it cannot pirouette on the spot (handoff section 4).
const STEERING_AUTHORITY_SPEED: float = 40.0

## Forward speed below which the brake input becomes reverse instead, per
## handoff section 4: brake while moving forward, reverse after slowing.
const REVERSE_ENGAGE_SPEED: float = 12.0

## Tuning source. Normally the GameBalance autoload, but assignable so a
## headless test can supply its own instance: a --script run has no autoloads,
## so referring to the global GameBalance identifier here would fail outside
## the running game.
var balance: Node = null

var condition: float = 0.0
var max_condition: float = 0.0
var siren_active: bool = false

var _throttle: float = 0.0
var _steering: float = 0.0
var _brake: bool = false
var _contact_cooldown: float = 0.0
var _destroyed_emitted: bool = false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	resolve_balance()
	max_condition = balance.truck_starting_condition
	condition = max_condition
	condition_changed.emit(condition, max_condition)


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		# Headless or test context with no autoloads. Load the same script
		# directly rather than duplicating any tuning number here.
		balance = load("res://scripts/GameBalance.gd").new()


## The intent boundary from handoff section 8. throttle and steering are in
## the range -1 to 1; brake is the stronger handbrake, not the S key.
func set_drive_intent(throttle: float, steering: float, brake: bool) -> void:
	_throttle = clampf(throttle, -1.0, 1.0)
	_steering = clampf(steering, -1.0, 1.0)
	_brake = brake


func set_siren_active(active: bool) -> void:
	siren_active = active


## Development reset from handoff section 4. Position and motion only: it must
## not repair, refill, reset an incident timer, or award anything.
func return_to_station(spawn_position: Vector2, spawn_heading: float) -> void:
	global_position = spawn_position
	rotation = spawn_heading
	velocity = Vector2.ZERO
	_contact_cooldown = 0.0


func get_forward() -> Vector2:
	return Vector2.RIGHT.rotated(rotation)


## Half the truck's collision rectangle, read from the shape itself rather than
## restated as a constant, so a change to Truck.tscn cannot leave this lying.
## Falls back to the shipped 90 x 40 if the shape is missing, which is the only
## thing a caller could sensibly do with no shape to measure.
func get_collision_half_extents() -> Vector2:
	var collision: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if collision != null and collision.shape is RectangleShape2D:
		return (collision.shape as RectangleShape2D).size * 0.5
	return Vector2(45.0, 20.0)


func get_forward_speed() -> float:
	return velocity.dot(get_forward())


func _physics_process(delta: float) -> void:
	_apply_steering(delta)
	_apply_drive(delta)

	var pre_move_velocity: Vector2 = velocity
	move_and_slide()

	tick_contact_cooldown(delta)
	var impact_speed: float = _strongest_impact_speed(pre_move_velocity)
	if impact_speed > 0.0:
		register_wall_contact(impact_speed)

	# Adopt the motion that actually happened as this body's velocity.
	#
	# This line is load-bearing and was written after watching the bug it fixes.
	# move_and_slide() does not reliably write the blocked result back into
	# velocity here: driving flat out into a wall left velocity sitting at
	# 250 units/second frame after frame while get_real_velocity() correctly
	# read zero. _apply_drive() reads velocity back at the top of the next
	# frame, so the truck believed it was still doing 250 into a wall it had
	# already stopped against, and the crash re-fired every time the contact
	# cooldown expired: ten full-speed impacts and a destroyed engine from one
	# collision. Reconciling against the real motion is what makes "speed lost
	# into the normal" mean anything, and the automated 60 frame check cannot
	# see this because it never runs Godot's physics.
	#
	# Clamped, though, because adopting the real motion wholesale also adopts
	# depenetration. A truck that starts a frame overlapping a building is shoved
	# clear hard, and taking that shove as velocity launched it across the map
	# under its own steam. A move can never leave the truck faster than it
	# entered, so being pushed out of geometry stops the truck instead of firing
	# it away.
	var real_velocity: Vector2 = get_real_velocity()
	var entry_speed: float = pre_move_velocity.length()
	if real_velocity.length() > entry_speed:
		real_velocity = real_velocity.normalized() * entry_speed
	velocity = real_velocity


func _apply_steering(delta: float) -> void:
	if is_zero_approx(_steering):
		return
	var forward_speed: float = get_forward_speed()
	var speed_magnitude: float = absf(forward_speed)

	# No authority at a standstill, ramping to full by STEERING_AUTHORITY_SPEED.
	var authority: float = clampf(speed_magnitude / STEERING_AUTHORITY_SPEED, 0.0, 1.0)
	# And reduced again at speed, so the truck feels weighted rather than twitchy.
	var speed_ratio: float = clampf(speed_magnitude / balance.forward_max_speed, 0.0, 1.0)
	var weight: float = lerpf(1.0, balance.high_speed_steering_factor, speed_ratio)
	# Reversing swings the nose the other way, which is how a real vehicle backs up.
	var direction: float = -1.0 if forward_speed < 0.0 else 1.0

	rotation += _steering * balance.steering_rate * authority * weight * direction * delta
	# Keep momentum aligned with the new heading. This is a deliberate arcade
	# choice: no lateral slip, so the truck goes where it is pointed.
	velocity = get_forward() * forward_speed


func _apply_drive(delta: float) -> void:
	var forward: Vector2 = get_forward()
	var forward_speed: float = velocity.dot(forward)

	if _brake:
		forward_speed = move_toward(forward_speed, 0.0, balance.handbrake_deceleration * delta)
	elif _throttle > 0.0:
		forward_speed = move_toward(
			forward_speed, balance.forward_max_speed * _throttle, balance.acceleration * delta
		)
	elif _throttle < 0.0:
		if forward_speed > REVERSE_ENGAGE_SPEED:
			forward_speed = move_toward(forward_speed, 0.0, balance.brake_deceleration * delta)
		else:
			forward_speed = move_toward(
				forward_speed,
				balance.reverse_max_speed * _throttle,
				balance.reverse_acceleration * delta
			)
	else:
		forward_speed = move_toward(forward_speed, 0.0, balance.drag * delta)

	velocity = forward * forward_speed


## How fast the truck was closing on a wall as it hit it, across every slide
## contact: the speed it arrived at, measured into the contact normal.
##
## This used to be the speed LOST into the normal on the contact frame, which
## sounded more careful and was wrong. A crash at speed is not resolved in one
## physics frame: the solver takes two, and the 0.5 second contact cooldown then
## swallows the second. Which fraction of the stop landed inside the first frame
## depended on exactly where the truck was when it touched, so the same 250
## unit/second head-on cost 42.9 condition after a 140 unit run-up and 12.2
## after a 400 unit one. Cost tracked sub-frame alignment rather than severity,
## and the long run-up, which is the common case on a map of long straights, was
## the cheap one. Both figures were measured.
##
## Reading the arrival speed instead makes a crash cost what the crash was worth.
## Resting against a wall afterwards is still free: the velocity reconciliation
## at the end of _physics_process zeroes the truck against the wall, so the next
## frame arrives carrying only the acceleration gained since, a few units per
## second, far under the damage threshold. A glancing blow is still cheap too,
## because only the component into the normal counts.
func _strongest_impact_speed(pre_move_velocity: Vector2) -> float:
	var strongest: float = 0.0
	for index in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(index)
		var normal: Vector2 = collision.get_normal()
		strongest = maxf(strongest, maxf(-pre_move_velocity.dot(normal), 0.0))
	return strongest


## Ticked every physics frame whether or not anything was touched, so the
## cooldown cannot be held open by simply not colliding.
func tick_contact_cooldown(delta: float) -> void:
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)


## Applies damage for one frame's worth of contact and returns the amount dealt.
## Returns 0.0 when under the impact threshold or still inside the cooldown.
func register_wall_contact(impact_speed: float) -> float:
	if impact_speed < balance.collision_damage_threshold:
		return 0.0
	if _contact_cooldown > 0.0:
		return 0.0

	var damage: float = (
		(impact_speed - balance.collision_damage_threshold) * balance.collision_damage_scale
	)
	if damage <= 0.0:
		return 0.0

	condition = maxf(condition - damage, 0.0)
	_contact_cooldown = balance.collision_contact_cooldown
	truck_damaged.emit(damage, impact_speed)
	condition_changed.emit(condition, max_condition)

	if condition <= 0.0 and not _destroyed_emitted:
		_destroyed_emitted = true
		truck_destroyed.emit()
	return damage


## Called by GameSession when a new shift begins, so a restart does not carry a
## cooldown or a spent destroyed-guard over from the last one.
func reset_for_new_shift(spawn_position: Vector2, spawn_heading: float) -> void:
	resolve_balance()
	max_condition = balance.truck_starting_condition
	condition = max_condition
	_contact_cooldown = 0.0
	_destroyed_emitted = false
	_throttle = 0.0
	_steering = 0.0
	_brake = false
	siren_active = false
	return_to_station(spawn_position, spawn_heading)
	condition_changed.emit(condition, max_condition)
