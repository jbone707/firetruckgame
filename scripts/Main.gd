extends Node2D
## Scene orchestration and the desktop input layer.
##
## This node is the only place that reads keyboard and mouse actions. It
## translates them into intent calls on the systems below it, so a later touch
## or gamepad layer replaces this file and nothing else (handoff section 8).
## It also owns the wiring between GameSession, DispatchManager and the UI.


@onready var _map_builder: MapBuilder = %MapBuilder
@onready var _truck: TruckController = %Truck
@onready var _camera: FollowCamera = %Camera
@onready var _pause_menu: PauseMenu = %PauseMenu
@onready var _hydrants_root: Node2D = %Hydrants
@onready var _signals: TrafficSignals = %TrafficSignals
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

## The transient line the zoom key writes, and how long it stays up.
## Shown for a second so pressing Z is answered rather than merely obeyed.
const TRANSIENT_MESSAGE_SECONDS: float = 1.0
var _transient_message: String = ""
var _transient_message_remaining: float = 0.0
var _zoom_index: int = 0

## Whether the minimap is showing. Session state, like _zoom_index: not saved.
var _minimap_shown: bool = true

## Which of GameBalance.minimap_zoom_levels the panel is on. Session state too.
var _minimap_zoom_index: int = 0


func _ready() -> void:
	print(
		"Fire Truck Game: Main scene loaded. Running Godot %s"
		% Engine.get_version_info()["string"]
	)

	# The camera needs its target before load_map, which snaps it, and its
	# limits before it is made current, so it never spends a frame showing
	# past the edge of a map it has not been told the size of.
	_camera.target = _truck

	_save = SaveManager.new()
	_save.load_game()
	if _save.last_load_diagnostic != "":
		print("Fire Truck Game: %s" % _save.last_load_diagnostic)

	load_map(MapCatalogue.path_for(_save.map_id))
	_camera.make_current()
	_session.setup(self, _dispatch, _truck, _water, _save)

	_pause_menu.resume_requested.connect(_set_paused.bind(false))
	_pause_menu.return_to_station_requested.connect(_on_return_to_station_requested)

	_ui.start_shift_pressed.connect(_on_start_shift_pressed)
	_ui.open_shop_pressed.connect(_on_open_shop_pressed)
	_ui.close_shop_pressed.connect(_on_close_shop_pressed)
	_ui.buy_upgrade_pressed.connect(_on_buy_upgrade_pressed)
	_ui.open_map_select_pressed.connect(_session.open_map_select)
	_ui.open_credits_pressed.connect(_session.open_credits)
	_ui.map_chosen.connect(_on_map_chosen)
	_ui.back_pressed.connect(_on_back_pressed)
	_ui.quit_pressed.connect(_on_quit_pressed)

	_session.state_changed.connect(_on_session_state_changed)
	_session.credits_changed.connect(_ui.set_credits)
	_dispatch.call_dispatched.connect(_on_call_dispatched)
	_truck.condition_changed.connect(_ui.set_condition)
	# A crash should be something the player sees, not only something the
	# condition bar reports after the fact.
	_truck.truck_damaged.connect(_on_truck_damaged)
	_water.water_changed.connect(_ui.set_water)

	_ui.set_credits(_session.get_credits())
	_ui.show_menu()


# ---------------------------------------------------------------------------
# Map access, used by GameSession and DispatchManager
# ---------------------------------------------------------------------------

## Swaps the whole neighbourhood: geometry, hydrants, camera limits, the truck's
## place on it, and the pool of buildings that can catch fire.
##
## Everything the previous map left behind goes first. A fire still burning on a
## building that no longer exists, or a dispatch queue full of candidate ids
## from another map, is exactly the kind of thing that survives a switch and
## then fails three calls later somewhere unrelated (handoff §9).
func load_map(path: String) -> void:
	var loaded: MapDefinition = load(path) as MapDefinition
	if loaded == null:
		push_error("%s is not a MapDefinition, keeping the map already loaded" % path)
		return

	_dispatch.reset()
	clear_incidents()

	_map_definition = loaded
	_map_builder.build(_map_definition)
	_build_hydrants()

	_truck.global_position = get_station_spawn_position()
	_truck.rotation = get_station_spawn_heading()
	_truck.velocity = Vector2.ZERO

	_camera.apply_world_bounds(_map_builder.get_world_bounds())
	# The zoom the player chose survives a change of map: a view setting that
	# reset itself every time a shift started would have to be set again every
	# time. apply_world_bounds has just recomputed the limits, which depend on it.
	_camera.set_zoom_level(_zoom_levels()[_zoom_index])
	_camera.snap_to_target()

	_dispatch.setup(
		self, _map_builder.get_incident_candidates(), _routes_from_station()
	)

	# The signal heads and the stop signs, from the lane model the builder just
	# derived. Rebuilt per map, like everything else the map owns.
	_signals.configure(_map_builder.get_lane_graph())

	# The minimap's static half is built once per map, here, from the same
	# definition and the same hydrant list everything else on the map came from.
	_ui.configure_minimap(_map_definition, _map_builder.get_hydrant_definitions())
	_ui.set_minimap_shown(_minimap_shown)
	_ui.set_minimap_zoom_index(_minimap_zoom_index)


## How far every incident candidate is from the station along the roads, by
## candidate id. Measured once here, at map load, because it is a property of
## the map and the station and does not change between shifts; DispatchManager
## uses it to keep the first call of a shift off the station's doorstep.
##
## Not to be confused with travel_distance_to, which measures from wherever the
## truck IS at the moment a call is dispatched. That is the number the
## escalation clock is priced from and it has to be live; this one must not be,
## or the queue for a shift would depend on where the last shift ended.
func _routes_from_station() -> Dictionary:
	var graph: RoadGraph = _map_builder.get_road_graph()
	if graph == null:
		return {}
	var station: Vector2 = get_station_spawn_position()
	var routes: Dictionary = {}
	for candidate in _map_builder.get_incident_candidates():
		var route: float = graph.route_length(station, Vector2(candidate["position"]))
		routes[String(candidate["id"])] = 0.0 if is_inf(route) else route
	return routes


func get_map_definition() -> MapDefinition:
	return _map_definition


func get_station_spawn_position() -> Vector2:
	return _map_builder.get_station_spawn_position()


func get_station_spawn_heading() -> float:
	return _map_builder.get_station_spawn_heading()


## How far the truck has to drive to reach a point, along the roads. This is
## what the escalation allowance is priced from, so a call the roads only reach
## the long way round is paid for as the long way round.
##
## Falls back to the straight line if the network cannot reach the point at all.
## MapValidator proves every candidate is on a reachable kerb on both shipped
## maps, so that fallback is a guard rather than a path anything takes; a fire
## with no route would otherwise be handed an infinite clock.
func travel_distance_to(target: Vector2) -> float:
	var graph: RoadGraph = _map_builder.get_road_graph()
	if graph == null:
		return _truck.global_position.distance_to(target)
	var route: float = graph.route_length(_truck.global_position, target)
	if is_inf(route):
		push_warning("no road route to %s, pricing the call as the straight line" % target)
		return _truck.global_position.distance_to(target)
	return route


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


## Puts every hydrant back to idle: no hose out, no settling clock, no snap
## message. Called when a shift starts and when the development reset teleports
## the truck, both of which move the truck without the hose being able to see it
## happen, which would otherwise leave a hose drawn across the map (handoff §9:
## starting a shift clears the per-run state).
func _reset_hydrants() -> void:
	for hydrant in _hydrants:
		hydrant.reset_for_new_shift()


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
	var travel: float = travel_distance_to(Vector2(candidate["position"]))

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

	# Escape backs out one level: the map choice and the credits screen to the
	# home menu, the shop to the results screen it was opened from. It must
	# never drop the player into a running game, which is a property of
	# GameSession.back_out() rather than of this branch: every arrow it can
	# follow points at a menu.
	if event.is_action_pressed("pause") and _session.back_out():
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
		return

	if event.is_action_pressed("cycle_zoom"):
		_cycle_camera_zoom()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("toggle_minimap"):
		_toggle_minimap()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("cycle_minimap_zoom"):
		_cycle_minimap_zoom()
		get_viewport().set_input_as_handled()


## M. The minimap is on by default and can be turned off by anyone who would
## rather have the corner back. Kept for the rest of the session, across shifts
## and across a change of map, for the same reason the zoom level is: a view
## setting that reset itself every time a shift started would have to be set
## again every time. Not saved to disk, which is where the zoom's own rule stops
## too.
func _toggle_minimap() -> void:
	_minimap_shown = _ui.toggle_minimap()
	_transient_message = "Minimap on" if _minimap_shown else "Minimap off"
	_transient_message_remaining = TRANSIENT_MESSAGE_SECONDS


## N, and the button in the panel's corner, which call the same thing.
##
## THIS IS NOT THE CAMERA'S ZOOM. It changes how much of the neighbourhood the
## little panel shows and nothing else; Z still does what Z has always done, and
## a physics check asserts that cycling one leaves the other where it was.
func _cycle_minimap_zoom() -> void:
	_minimap_zoom_index = _ui.cycle_minimap_zoom()
	_transient_message = "Minimap zoom %sx" % String.num(_ui.get_minimap().get_zoom(), 0)
	_transient_message_remaining = TRANSIENT_MESSAGE_SECONDS


## Z, a real control since Milestone 8 Part 3.
##
## It arrived in Milestone 6 as a development key so James could choose one zoom
## level by looking rather than have a number guessed for him. He played all
## three and wanted to keep all three, so it is a control now: in the input map,
## in the pause menu and in README.md, with a HUD line that names the level it
## just moved to. The level is kept for the rest of the session, across shifts
## and across a change of map, because a view setting that reset itself every
## time a shift started would have to be set again every time.
func _cycle_camera_zoom() -> void:
	var levels: Array[float] = _zoom_levels()
	if levels.is_empty():
		return
	_zoom_index = (_zoom_index + 1) % levels.size()
	_camera.set_zoom_level(levels[_zoom_index])
	_transient_message = "Zoom %s" % String.num(levels[_zoom_index], 2)
	_transient_message_remaining = TRANSIENT_MESSAGE_SECONDS


func _physics_process(delta: float) -> void:
	# This node is PROCESS_MODE_ALWAYS so that Escape still reaches it while
	# paused, which means this callback also keeps running. The truck itself is
	# PAUSABLE and frozen, but holding a key while paused must not queue up an
	# intent that fires the instant the game resumes.
	if get_tree().paused or _session.state != GameSession.State.PLAYING:
		return

	# The zoom line ages out on its own.
	if _transient_message_remaining > 0.0:
		_transient_message_remaining = maxf(_transient_message_remaining - delta, 0.0)

	var throttle: float = (
		Input.get_action_strength("drive_throttle") - Input.get_action_strength("drive_brake")
	)
	var steering: float = (
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	)
	_truck.set_drive_intent(throttle, steering, Input.is_action_pressed("handbrake"))

	# Where the engine is and whether its siren is on, for signal preemption.
	# Pushed rather than pulled: TrafficSignals is not given the truck, because
	# this node is the one that knows about both of them.
	_signals.set_engine_state(
		_truck.global_position, _truck.get_forward(), _truck.siren_active
	)

	# get_global_mouse_position() on a CanvasItem already accounts for the
	# canvas transform, so this is the world point under the cursor with the
	# camera wherever it currently is. Reading the raw viewport mouse position
	# instead would aim at a fixed screen point as soon as the truck moved.
	_water.set_aim_world_position(get_global_mouse_position())

	_update_hydrants(delta)

	# Spraying is no longer refused while hooked up (Milestone 9 Part 0): the
	# flows net out. is_spray_allowed() is still asked, so a later rule that
	# does refuse the stream only has to be written in one place.
	_water.set_spray_requested(
		Input.is_action_pressed("spray")
		and _water.is_spray_allowed()
		and not _ui.is_pointer_over_minimap()
	)

	_update_hud()


## Every hydrant on the map gets one frame, and the answer is the prompt line
## and whether water is arriving. NOTHING HERE READS THE KEYBOARD: the hookup is
## automatic (Milestone 9 Part 0), and this loop is the only reason the hydrant
## needs a frame at all.
func _update_hydrants(delta: float) -> void:
	# The hydrant rule measures to the truck's bodywork, not to its centre, so
	# it needs the shape's placement and size rather than a position.
	var truck_transform: Transform2D = _truck.global_transform
	var truck_half_extents: Vector2 = _truck.get_collision_half_extents()
	var truck_speed: float = _truck.get_forward_speed()

	var best_prompt: int = Hydrant.Prompt.NONE
	var best_is_connected: bool = false
	var wants_refill: bool = false

	for hydrant in _hydrants:
		var outcome: Dictionary = hydrant.evaluate(
			delta, truck_transform, truck_half_extents, truck_speed,
			_water.water_remaining, _water.tank_capacity
		)
		var prompt: int = outcome["prompt"]
		# A hydrant with a hose out beats one that is merely nearby. Two are
		# never in range of the same truck on either shipped map, but "the first
		# one in the array wins" is an accident waiting for a map that puts two
		# on one corner, and this is one line.
		var connected: bool = int(outcome["state"]) != Hydrant.State.IDLE
		if prompt != Hydrant.Prompt.NONE:
			if best_prompt == Hydrant.Prompt.NONE or (connected and not best_is_connected):
				best_prompt = prompt
				best_is_connected = connected
		if outcome["should_refill"]:
			wants_refill = true

	# Leaving range, snapping the hose, or filling up all land here as
	# wants_refill going false, which is the single stop path.
	if wants_refill:
		_water.begin_refill()
	else:
		_water.cancel_refill()

	_ui.set_prompt(_compose_prompt(best_prompt))


## One prompt line, chosen by priority. An empty tank is the most urgent thing
## the player can be told, so it wins over a hydrant prompt.
func _compose_prompt(hydrant_prompt: int) -> String:
	# The zoom line sits above everything because it is an answer to something
	# the player just pressed, and a reply to a keypress that a hydrant prompt
	# can swallow is not a reply.
	if _transient_message_remaining > 0.0:
		return _transient_message
	# A hydrant with something to say outranks the empty-tank line. It has to:
	# the empty-tank line tells the player to go and find a hydrant, and saying
	# it over "Hooking up" at the hydrant they have just pulled up to would be
	# telling them to do the thing they are already doing.
	var text: String = Hydrant.prompt_text(
		hydrant_prompt, _water.water_remaining, _water.tank_capacity
	)
	if text != "":
		return text
	if _water.is_empty():
		return "Out of water. Pull up slowly at a hydrant to refill"
	# Below the two refill messages, above nothing: confirmation that the stream
	# is actually taking health off the fire rather than washing a wall. Driven
	# by the same flag the steam burst is, so the line and the picture can never
	# disagree.
	if _water.is_suppressing():
		return "Knocking it down"
	return ""


func _on_truck_damaged(_amount: float, impact_speed: float) -> void:
	_camera.shake(impact_speed)


func _update_hud() -> void:
	var incident: FireIncident = _dispatch.active_incident
	var live: bool = (
		incident != null and is_instance_valid(incident) and not incident.is_terminal()
	)
	if live:
		_ui.set_margin_seconds(incident.get_escalation_remaining())
		_ui.set_incident_indicator(_incident_indicator_state(incident.global_position))
	else:
		_ui.set_margin_seconds(0.0)
		_ui.set_incident_indicator(IncidentIndicator.hidden())

	# The off-screen arrow stays exactly as it was: it answers "which way is the
	# call from here", which is a different question from "where am I on this
	# neighbourhood", and neither replaces the other.
	_ui.update_minimap(
		_truck.global_position,
		_truck.rotation,
		incident.global_position if live else Vector2.ZERO,
		live,
		_camera_world_rect()
	)


## The rectangle of world the camera can currently see, derived from the
## viewport's own canvas transform rather than from the camera's position and
## zoom. The transform already accounts for the camera's lead, its smoothing and
## its clamp to the map edge, so the rectangle on the minimap is what is on the
## screen rather than what the camera was asked for.
func _camera_world_rect() -> Rect2:
	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var to_world: Transform2D = canvas.affine_inverse()
	var view: Rect2 = get_viewport_rect()
	return Rect2(to_world * view.position, to_world.basis_xform(view.size))


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

	# Everything per-run that has to start over. Here rather than on the
	# session's PLAYING transition, because that transition does not fire when a
	# shift starts from a shift that is already running, and here rather than on
	# a particular button, because every way a player asks for a shift arrives at
	# this one handler (handoff §9: starting a shift clears the old one).
	_reset_hydrants()
	_signals.reset_for_new_shift()
	# start_shift puts the truck back at the station. Without this the camera
	# glides there from wherever the last shift ended, which on a map 12,499
	# units across is a long, uncontrollable pan over the player's first
	# seconds. It is also what the off-screen call arrow measures from, so a
	# camera still in motion makes the arrow briefly point somewhere the fire
	# is not.
	_camera.snap_to_target()


## Picking a map both remembers it and plays it. The choice is written to the
## save first, so a player who picks a map and then crashes out still opens on
## the map they chose; loading it before saving would leave the two disagreeing
## in exactly that case.
func _on_map_chosen(map_id: String) -> void:
	_save.set_map(map_id)
	if _map_definition == null or _map_definition.map_id != map_id:
		load_map(MapCatalogue.path_for(map_id))
	_on_start_shift_pressed()


func _on_back_pressed() -> void:
	_session.back_out()


func _on_quit_pressed() -> void:
	get_tree().quit()


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
		_shop_status,
		_session.balance.tank_capacity,
		_session.balance.tank_upgrade_multiplier
	)


func _on_session_state_changed(state: int) -> void:
	match state:
		GameSession.State.MENU:
			_ui.show_menu()
		GameSession.State.MAP_SELECT:
			_ui.show_map_select(_save.map_id)
		GameSession.State.CREDITS:
			_ui.show_credits()
		GameSession.State.PLAYING:
			_ui.show_playing()
			_ui.set_condition(_truck.condition, _truck.max_condition)
			_ui.set_water(_water.water_remaining, _water.tank_capacity)
			_ui.set_credits(_session.get_credits())
			_ui.set_siren(_truck.siren_active)
			_ui.set_prompt("")
		GameSession.State.RESULTS:
			_set_paused(false)
			var calls_pay: int = (
				_session.completed_calls * _session.balance.credits_per_call
			)
			_ui.show_results(
				_session.last_shift_succeeded,
				_session.last_shift_reason,
				_session.completed_calls,
				_session.balance.calls_per_shift,
				calls_pay,
				_session.credits_earned_this_shift - calls_pay,
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
	_reset_hydrants()
	_camera.snap_to_target()
	_set_paused(false)


## The camera zoom levels, resolved without going through GameSession.
##
## load_map runs from _ready BEFORE _session.setup, so _session.balance does not
## exist yet the first time the zoom has to be applied. Reading the autoload
## directly is the only ordering that works for both callers, and the fallback
## keeps a headless test that never registered the autoload out of a crash.
func _zoom_levels() -> Array[float]:
	var balance: Node = get_node_or_null("/root/GameBalance")
	if balance == null or balance.camera_zoom_levels.is_empty():
		return [FollowCamera.ZOOM] as Array[float]
	return balance.camera_zoom_levels
