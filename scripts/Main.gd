extends Node2D
## Scene orchestration and the desktop input layer.
##
## This node is the only place that reads keyboard and mouse actions. It
## translates them into intent calls on the systems below it, so a later touch
## or gamepad layer replaces this file and nothing else (handoff section 8).
## It also owns the wiring between GameSession, DispatchManager and the UI.

const MAP_RESOURCE_PATH: String = "res://resources/neighbourhood.tres"

@onready var _map_builder: MapBuilder = %MapBuilder
@onready var _truck: TruckController = %Truck
@onready var _camera: FollowCamera = %Camera
@onready var _pause_menu: PauseMenu = %PauseMenu
@onready var _hydrants_root: Node2D = %Hydrants
@onready var _incidents_root: Node2D = %Incidents
@onready var _dispatch: DispatchManager = %Dispatch
@onready var _session: GameSession = %Session
@onready var _ui: GameUI = %GameUI

## Fetched by path rather than by unique name. The % shorthand resolves against
## the scene that OWNS the node, and WaterSystem's unique name belongs to
## Truck.tscn, so %WaterSystem does not exist from here.
@onready var _water: WaterSystem = %Truck/WaterSystem

var _map_definition: MapDefinition = null
var _hydrants: Array[Hydrant] = []
var _save: SaveManager = null
var _shop_status: String = ""


func _ready() -> void:
	print(
		"Fire Truck Game: Main scene loaded. Running Godot %s"
		% Engine.get_version_info()["string"]
	)

	_map_definition = load(MAP_RESOURCE_PATH)
	_map_builder.build(_map_definition)
	_build_hydrants()

	_truck.global_position = get_station_spawn_position()
	_truck.rotation = get_station_spawn_heading()

	_camera.target = _truck
	_camera.apply_world_bounds(_map_builder.get_world_bounds())
	_camera.snap_to_target()
	_camera.make_current()

	_save = SaveManager.new()
	_save.load_game()
	if _save.last_load_diagnostic != "":
		print("Fire Truck Game: %s" % _save.last_load_diagnostic)

	_dispatch.setup(self, _map_builder.get_incident_candidates())
	_session.setup(self, _dispatch, _truck, _water, _save)

	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.return_to_station_requested.connect(_on_return_to_station_requested)

	_ui.start_shift_pressed.connect(_on_start_shift_pressed)
	_ui.open_shop_pressed.connect(_on_open_shop_pressed)
	_ui.close_shop_pressed.connect(_on_close_shop_pressed)
	_ui.buy_upgrade_pressed.connect(_on_buy_upgrade_pressed)

	_session.state_changed.connect(_on_session_state_changed)
	_session.credits_changed.connect(_ui.set_credits)
	_dispatch.call_dispatched.connect(_on_call_dispatched)
	_truck.condition_changed.connect(_ui.set_condition)
	_water.water_changed.connect(_ui.set_water)

	_ui.set_credits(_session.get_credits())
	_ui.show_menu()


# ---------------------------------------------------------------------------
# Map access, used by GameSession and DispatchManager
# ---------------------------------------------------------------------------

func get_station_spawn_position() -> Vector2:
	return _map_builder.get_station_spawn_position()


func get_station_spawn_heading() -> float:
	return _map_builder.get_station_spawn_heading()


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


## Lights a fire on one of the map's incident candidate buildings.
func spawn_incident(candidate: Dictionary) -> FireIncident:
	var building_id: String = String(candidate["building_id"])
	var polygon: PackedVector2Array = _map_builder.get_building_polygon(building_id)
	if polygon.is_empty():
		push_error("no building polygon for incident candidate %s" % candidate.get("id", "?"))
		return null

	# Measured at dispatch, from wherever the truck actually is, so the clock a
	# player is given matches the drive they are actually being asked to make.
	# Main is the only node that knows both the truck and the candidate.
	var travel: float = FireIncident.travel_distance_between(
		_truck.global_position, Vector2(candidate["position"])
	)

	var incident: FireIncident = FireIncident.new()
	incident.name = "Incident_%s" % String(candidate["id"])
	_incidents_root.add_child(incident)
	incident.setup(String(candidate["id"]), building_id, polygon, travel)
	return incident


## Frees every incident and, with them, every connection made to one. A new
## shift must not inherit a lost incident's timer or a stale connection
## (handoff section 9). remove_child before queue_free so the node is out of the
## group immediately rather than at the end of the frame, which is what stops a
## just-cleared incident from being counted by anything later in this frame.
func clear_incidents() -> void:
	for child in _incidents_root.get_children():
		_incidents_root.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Pause only means anything during a shift. On the menus, Escape does
	# nothing rather than opening a pause overlay over a menu.
	if event.is_action_pressed("pause") and _session.state == GameSession.State.PLAYING:
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
		return

	if get_tree().paused or _session.state != GameSession.State.PLAYING:
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
	if get_tree().paused or _session.state != GameSession.State.PLAYING:
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

	_update_hud()


func _update_hydrants() -> void:
	# The hydrant rule measures to the truck's bodywork, not to its centre, so
	# it needs the shape's placement and size rather than a position.
	var truck_transform: Transform2D = _truck.global_transform
	var truck_half_extents: Vector2 = _truck.get_collision_half_extents()
	var truck_speed: float = _truck.get_forward_speed()
	var hookup_held: bool = Input.is_action_pressed("hydrant_hookup")
	var tank_is_full: bool = _water.water_remaining >= _water.tank_capacity
	var refilling: bool = _water.refill_state != WaterSystem.RefillState.IDLE

	var best_prompt: int = Hydrant.Prompt.NONE
	var wants_refill: bool = false

	for hydrant in _hydrants:
		var outcome: Dictionary = hydrant.evaluate(
			truck_transform,
			truck_half_extents,
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

	# Leaving range, releasing E, moving off, or filling up all land here as
	# wants_refill going false, which is the single cancel path.
	if wants_refill and _water.refill_state == WaterSystem.RefillState.IDLE:
		_water.begin_hookup()
	elif not wants_refill and _water.refill_state != WaterSystem.RefillState.IDLE:
		_water.cancel_refill()

	_ui.set_prompt(_compose_prompt(best_prompt))


## One prompt line, chosen by priority. An empty tank is the most urgent thing
## the player can be told, so it wins over a hydrant prompt.
func _compose_prompt(hydrant_prompt: int) -> String:
	if _water.is_empty() and _water.refill_state == WaterSystem.RefillState.IDLE:
		return "Out of water. Find a hydrant and hold E to refill"
	var text: String = Hydrant.prompt_text(hydrant_prompt, _water.get_hookup_progress())
	if text != "":
		return text
	# Below the two refill messages, above nothing: confirmation that the stream
	# is actually taking health off the fire rather than washing a wall. Driven
	# by the same flag the steam burst is, so the line and the picture can never
	# disagree.
	if _water.is_suppressing():
		return "Knocking it down"
	return ""


func _update_hud() -> void:
	var incident: FireIncident = _dispatch.active_incident
	if incident != null and is_instance_valid(incident) and not incident.is_terminal():
		_ui.set_margin_seconds(incident.get_escalation_remaining())
		_ui.set_incident_indicator(_incident_indicator_state(incident.global_position))
	else:
		_ui.set_margin_seconds(0.0)
		_ui.set_incident_indicator(IncidentIndicator.hidden())


## Whether the off-screen arrow is shown for a world position, and where on the
## screen edge it sits. The camera is north up, so the world-space offset is
## already the screen-space offset and no truck or camera rotation belongs
## anywhere in this path. The engine's own canvas transform does the mapping, so
## camera lead and the map edge clamp are accounted for automatically.
func _incident_indicator_state(world_position: Vector2) -> Dictionary:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	return IncidentIndicator.evaluate(canvas * world_position, get_viewport_rect())


# ---------------------------------------------------------------------------
# Session and UI wiring
# ---------------------------------------------------------------------------

func _on_start_shift_pressed() -> void:
	_shop_status = ""
	_set_paused(false)
	_session.start_shift()


func _on_open_shop_pressed() -> void:
	_shop_status = ""
	_session.open_shop()


func _on_close_shop_pressed() -> void:
	_session.close_shop()


func _on_buy_upgrade_pressed() -> void:
	_shop_status = _session.purchase_tank_upgrade()
	_refresh_shop()


func _refresh_shop() -> void:
	_ui.show_shop(
		_session.get_credits(),
		_session.has_tank_upgrade(),
		_session.balance.tank_upgrade_cost,
		_shop_status
	)


func _on_session_state_changed(state: int) -> void:
	match state:
		GameSession.State.MENU:
			_ui.show_menu()
		GameSession.State.PLAYING:
			_ui.show_playing()
			_ui.set_condition(_truck.condition, _truck.max_condition)
			_ui.set_water(_water.water_remaining, _water.tank_capacity)
			_ui.set_credits(_session.get_credits())
			_ui.set_siren(_truck.siren_active)
			_ui.set_prompt("")
		GameSession.State.RESULTS:
			_set_paused(false)
			_ui.show_results(
				_session.last_shift_succeeded,
				_session.last_shift_reason,
				_session.credits_earned_this_shift,
				_session.get_credits()
			)
		GameSession.State.SHOP:
			_refresh_shop()


func _on_call_dispatched(call_number: int, total_calls: int, _incident: FireIncident) -> void:
	_ui.set_call(call_number, total_calls)


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
	_ui.set_siren(active)


func _on_return_to_station_requested() -> void:
	# Development aid from handoff section 4. Position and motion only: it does
	# not repair, refill, reset an incident timer, or award credits.
	_truck.return_to_station(get_station_spawn_position(), get_station_spawn_heading())
	_water.cancel_refill()
	_camera.snap_to_target()
	_set_paused(false)
