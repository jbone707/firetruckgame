extends Node2D
class_name TruckBody
## Draws the engine: red body, cab and windows, wheels, roof equipment and the
## warning lights. Built-in drawing only, no external assets (handoff section 2).
##
## Local +X is forward, matching TruckController, so the cab is drawn at
## positive X and the rear step at negative X.

const LENGTH: float = 90.0
const WIDTH: float = 40.0

const BODY_COLOR: Color = Color("#c0392b")
const BODY_DARK_COLOR: Color = Color("#8e2b20")
const CAB_COLOR: Color = Color("#e05a49")
const WINDOW_COLOR: Color = Color("#2b3a4a")
const TRIM_COLOR: Color = Color("#e8e8e8")
const WHEEL_COLOR: Color = Color("#1c1c1c")
const EQUIPMENT_COLOR: Color = Color("#7f8c8d")
const LIGHT_RED: Color = Color("#ff3b30")
const LIGHT_BLUE: Color = Color("#3b7bff")
const LIGHT_OFF: Color = Color("#5a5a5a")

var siren_active: bool = false

var _flash_timer: float = 0.0
var _flash_on_left: bool = true


func _process(delta: float) -> void:
	if not siren_active:
		if _flash_timer != 0.0:
			_flash_timer = 0.0
			queue_redraw()
		return
	_flash_timer += delta
	if _flash_timer >= 0.25:
		_flash_timer = 0.0
		_flash_on_left = not _flash_on_left
	queue_redraw()


func set_siren_active(active: bool) -> void:
	if siren_active == active:
		return
	siren_active = active
	queue_redraw()


func _draw() -> void:
	var half_length: float = LENGTH * 0.5
	var half_width: float = WIDTH * 0.5

	# Wheels first, so the body sits over them.
	var wheel_size: Vector2 = Vector2(18.0, 8.0)
	for wheel_x in [half_length - 22.0, -half_length + 30.0, -half_length + 12.0]:
		for side in [-1.0, 1.0]:
			var wheel_center: Vector2 = Vector2(wheel_x, side * (half_width - 1.0))
			draw_rect(Rect2(wheel_center - wheel_size * 0.5, wheel_size), WHEEL_COLOR)

	# Hose bed and pump body.
	draw_rect(Rect2(Vector2(-half_length, -half_width), Vector2(LENGTH, WIDTH)), BODY_COLOR)
	draw_rect(
		Rect2(Vector2(-half_length + 4.0, -half_width + 6.0), Vector2(LENGTH * 0.45, WIDTH - 12.0)),
		BODY_DARK_COLOR
	)

	# Cab at the front, with a windscreen and side windows.
	draw_rect(Rect2(Vector2(half_length - 30.0, -half_width), Vector2(30.0, WIDTH)), CAB_COLOR)
	draw_rect(
		Rect2(Vector2(half_length - 13.0, -half_width + 5.0), Vector2(9.0, WIDTH - 10.0)),
		WINDOW_COLOR
	)
	draw_rect(
		Rect2(Vector2(half_length - 26.0, -half_width + 3.0), Vector2(10.0, 6.0)), WINDOW_COLOR
	)
	draw_rect(
		Rect2(Vector2(half_length - 26.0, half_width - 9.0), Vector2(10.0, 6.0)), WINDOW_COLOR
	)

	# Front bumper and a reflective stripe down the side.
	draw_rect(Rect2(Vector2(half_length - 3.0, -half_width), Vector2(3.0, WIDTH)), TRIM_COLOR)
	draw_rect(Rect2(Vector2(-half_length, -2.0), Vector2(LENGTH - 30.0, 4.0)), TRIM_COLOR)

	# Roof equipment: a ladder along the top and the pump panel behind the cab.
	var ladder_x_start: float = -half_length + 10.0
	var ladder_x_end: float = half_length - 34.0
	for offset in [-8.0, 8.0]:
		draw_line(
			Vector2(ladder_x_start, offset), Vector2(ladder_x_end, offset), EQUIPMENT_COLOR, 3.0
		)
	var rung_x: float = ladder_x_start + 6.0
	while rung_x < ladder_x_end:
		draw_line(Vector2(rung_x, -8.0), Vector2(rung_x, 8.0), EQUIPMENT_COLOR, 2.0)
		rung_x += 10.0

	# Warning lights on the cab roof. They alternate rather than both flashing,
	# which reads as a light bar even at this size.
	var left_color: Color = LIGHT_OFF
	var right_color: Color = LIGHT_OFF
	if siren_active:
		left_color = LIGHT_RED if _flash_on_left else LIGHT_OFF
		right_color = LIGHT_OFF if _flash_on_left else LIGHT_BLUE
	draw_rect(Rect2(Vector2(half_length - 24.0, -half_width + 1.0), Vector2(8.0, 7.0)), left_color)
	draw_rect(Rect2(Vector2(half_length - 24.0, half_width - 8.0), Vector2(8.0, 7.0)), right_color)
