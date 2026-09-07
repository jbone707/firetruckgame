extends Node2D
## Scene orchestration and the desktop input layer.
##
## This node is the only place that reads keyboard and mouse actions. It
## translates them into intent calls on the systems below it, so a later touch
## or gamepad layer replaces this file and nothing else (handoff section 8).
##
## GameSession, dispatch, water, fire and the HUD arrive in later parts. What is
## here now is the map, the truck, the camera and pause.

const MAP_RESOURCE_PATH: String = "res://resources/neighbourhood.tres"

@onready var _map_builder: MapBuilder = %MapBuilder
@onready var _truck: TruckController = %Truck
@onready var _camera: FollowCamera = %Camera
@onready var _pause_menu: PauseMenu = %PauseMenu

var _map_definition: MapDefinition = null


func _ready() -> void:
	print(
		"Fire Truck Game: Main scene loaded. Running Godot %s"
		% Engine.get_version_info()["string"]
	)

	_map_definition = load(MAP_RESOURCE_PATH)
	_map_builder.build(_map_definition)

	_truck.global_position = _map_builder.get_station_spawn_position()
	_truck.rotation = _map_builder.get_station_spawn_heading()

	_camera.target = _truck
	_camera.apply_world_bounds(_map_builder.get_world_bounds())
	_camera.snap_to_target()
	_camera.make_current()

	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.return_to_station_requested.connect(_on_return_to_station_requested)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return

	# Everything below is gameplay input and must not fire while paused.
	if get_tree().paused:
		return

	if event.is_action_pressed("toggle_siren"):
		_set_siren(not _truck.siren_active)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("return_to_station"):
		_on_return_to_station_requested()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	# This node is PROCESS_MODE_ALWAYS so that Escape still reaches it while
	# paused, which means this callback also keeps running. The truck itself is
	# PAUSABLE and frozen, but holding a key while paused must not queue up an
	# intent that fires the instant the game resumes.
	if get_tree().paused:
		return

	# Polled continuously rather than event-driven, because throttle and
	# steering are held states rather than presses.
	var throttle: float = (
		Input.get_action_strength("drive_throttle") - Input.get_action_strength("drive_brake")
	)
	var steering: float = (
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	)
	var handbrake: bool = Input.is_action_pressed("handbrake")
	_truck.set_drive_intent(throttle, steering, handbrake)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		_pause_menu.show_menu()
	else:
		_pause_menu.hide_menu()
		# Drop any intent held at the moment of pausing, so releasing the key
		# while paused does not leave the truck accelerating on resume.
		_truck.set_drive_intent(0.0, 0.0, false)


func _set_siren(active: bool) -> void:
	_truck.set_siren_active(active)
	var body: TruckBody = _truck.get_node("Body")
	body.set_siren_active(active)


func _on_return_to_station_requested() -> void:
	# Development aid from handoff section 4. Position and motion only: it does
	# not repair, refill, reset an incident timer, or award credits.
	_truck.return_to_station(
		_map_builder.get_station_spawn_position(), _map_builder.get_station_spawn_heading()
	)
	_camera.snap_to_target()
	_set_paused(false)
