extends Node2D
## Scene orchestration and the desktop input layer.
##
## This node is the only place that reads keyboard and mouse actions. It
## translates them into intent calls on the systems below it, so a later touch
## or gamepad layer replaces this file and nothing else (handoff section 8).

const MAP_RESOURCE_PATH: String = "res://resources/neighbourhood.tres"

@onready var _map_builder: MapBuilder = %MapBuilder
@onready var _truck: TruckController = %Truck
@onready var _camera: FollowCamera = %Camera
@onready var _pause_menu: PauseMenu = %PauseMenu
@onready var _hydrants_root: Node2D = %Hydrants
@onready var _incidents_root: Node2D = %Incidents

## Fetched by path rather than by unique name. The % shorthand resolves against
## the scene that OWNS the node, and WaterSystem's unique name belongs to
## Truck.tscn, so %WaterSystem does not exist from here.
@onready var _water: WaterSystem = %Truck/WaterSystem

var _map_definition: MapDefinition = null
var _hydrants: Array[Hydrant] = []

## The prompt the hydrant rules produced this frame, and its progress, read by
## the HUD in Part 5. Held here rather than pushed, so nothing has to exist yet.
var hydrant_prompt: int = Hydrant.Prompt.NONE
var hydrant_prompt_progress: float = 0.0


func _ready() -> void:
	print(
		"Fire Truck Game: Main scene loaded. Running Godot %s"
		% Engine.get_version_info()["string"]
	)

	_map_definition = load(MAP_RESOURCE_PATH)
	_map_builder.build(_map_definition)
	_build_hydrants()

	_truck.global_position = _map_builder.get_station_spawn_position()
	_truck.rotation = _map_builder.get_station_spawn_heading()

	_camera.target = _truck
	_camera.apply_world_bounds(_map_builder.get_world_bounds())
	_camera.snap_to_target()
	_camera.make_current()

	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.return_to_station_requested.connect(_on_return_to_station_requested)


func _build_hydrants() -> void:
	for child in _hydrants_root.get_children():
		child.queue_free()
	_hydrants.clear()

	for definition in _map_builder.get_hydrant_definitions():
		var hydrant: Hydrant = Hydrant.new()
		hydrant.name = "Hydrant_%s" % String(definition["id"])
		_hydrants_root.add_child(hydrant)
		hydrant.setup(String(definition["id"]), definition["position"])
		_hydrants.append(hydrant)


## Lights a fire on one of the map's incident candidate buildings and returns it.
## Part 5's DispatchManager calls this; nothing calls it yet.
func spawn_incident(candidate: Dictionary) -> FireIncident:
	var building_id: String = String(candidate["building_id"])
	var polygon: PackedVector2Array = _map_builder.get_building_polygon(building_id)
	if polygon.is_empty():
		push_error("no building polygon for incident candidate %s" % candidate.get("id", "?"))
		return null

	var incident: FireIncident = FireIncident.new()
	incident.name = "Incident_%s" % String(candidate["id"])
	_incidents_root.add_child(incident)
	incident.setup(String(candidate["id"]), building_id, polygon)
	return incident


## Clears every incident and its signal connections. A new shift must not
## inherit a lost incident's timer or a stale connection (handoff section 9).
func clear_incidents() -> void:
	for child in _incidents_root.get_children():
		_incidents_root.remove_child(child)
		child.queue_free()


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

	var throttle: float = (
		Input.get_action_strength("drive_throttle") - Input.get_action_strength("drive_brake")
	)
	var steering: float = (
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	)
	_truck.set_drive_intent(throttle, steering, Input.is_action_pressed("handbrake"))

	# get_global_mouse_position() on a CanvasItem already accounts for the
	# canvas transform, so this is the world point under the cursor with the
	# camera wherever it currently is. Reading the raw viewport mouse position
	# instead would aim at a fixed screen point as soon as the truck moved.
	_water.set_aim_world_position(get_global_mouse_position())

	_update_hydrants()

	# Refill wins over spray, which is enforced inside WaterSystem as well; this
	# just avoids asking for a stream that would be refused anyway.
	_water.set_spray_requested(
		Input.is_action_pressed("spray") and _water.is_spray_allowed()
	)


func _update_hydrants() -> void:
	var truck_position: Vector2 = _truck.global_position
	var truck_speed: float = _truck.get_forward_speed()
	var hookup_held: bool = Input.is_action_pressed("hydrant_hookup")
	var tank_is_full: bool = _water.water_remaining >= _water.tank_capacity
	var refilling: bool = _water.refill_state != WaterSystem.RefillState.IDLE

	var best_prompt: int = Hydrant.Prompt.NONE
	var wants_refill: bool = false

	for hydrant in _hydrants:
		var outcome: Dictionary = hydrant.evaluate(
			truck_position,
			truck_speed,
			hookup_held,
			tank_is_full,
			refilling,
			_water.get_hookup_progress()
		)
		var prompt: int = outcome["prompt"]
		if prompt != Hydrant.Prompt.NONE and best_prompt == Hydrant.Prompt.NONE:
			best_prompt = prompt
		if outcome["should_refill"]:
			wants_refill = true

	hydrant_prompt = best_prompt
	hydrant_prompt_progress = _water.get_hookup_progress()

	# Leaving range, releasing E, moving off, or filling up all land here as
	# wants_refill going false, which is the single cancel path.
	if wants_refill and _water.refill_state == WaterSystem.RefillState.IDLE:
		_water.begin_hookup()
	elif not wants_refill and _water.refill_state != WaterSystem.RefillState.IDLE:
		_water.cancel_refill()


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if paused:
		_pause_menu.show_menu()
	else:
		_pause_menu.hide_menu()
		# Drop any intent held at the moment of pausing, so releasing the key
		# while paused does not leave the truck accelerating on resume.
		_truck.set_drive_intent(0.0, 0.0, false)
		_water.set_spray_requested(false)


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
	_water.cancel_refill()
	_camera.snap_to_target()
	_set_paused(false)
