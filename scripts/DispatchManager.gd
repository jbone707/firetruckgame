extends Node2D
class_name DispatchManager
## Sequential calls: one active incident at a time, with a destination marker
## and an off-screen direction indicator (handoff sections 3 and 7).

signal call_dispatched(call_number: int, total_calls: int, incident: FireIncident)
signal call_extinguished(incident_id: String)
signal call_lost(incident_id: String)

## Pause between one fire going out and the next call arriving, so the player
## gets a readable confirmation rather than an instant hand-off.
const CONFIRMATION_SECONDS: float = 2.0

var balance: Node = null

var active_incident: FireIncident = null
var call_number: int = 0
var total_calls: int = 0

var _candidates: Array[Dictionary] = []
var _queue: Array[Dictionary] = []
var _spawner: Node = null
var _confirmation_remaining: float = 0.0
var _running: bool = false


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


## spawner is anything with spawn_incident(candidate) -> FireIncident, which in
## the game is Main. Injected rather than reached for, so this is testable.
func setup(spawner: Node, candidates: Array[Dictionary]) -> void:
	resolve_balance()
	_spawner = spawner
	_candidates = candidates.duplicate()


## Clears everything a previous shift left behind. Signal connections go with
## the incident nodes themselves, which Main frees, so nothing survives to fire
## twice (handoff section 9).
func reset() -> void:
	_disconnect_active()
	active_incident = null
	call_number = 0
	total_calls = 0
	_queue.clear()
	_confirmation_remaining = 0.0
	_running = false


func start_shift() -> void:
	reset()
	resolve_balance()

	total_calls = balance.calls_per_shift
	_queue = _candidates.duplicate()
	_queue.shuffle()
	# Fewer candidates than calls would otherwise cut the shift short, so the
	# list wraps rather than running out.
	while _queue.size() < total_calls:
		_queue.append_array(_candidates)
	_queue.resize(total_calls)

	_running = true
	_dispatch_next()


func is_running() -> bool:
	return _running


func get_active_marker_position() -> Vector2:
	if active_incident == null:
		return Vector2.ZERO
	return active_incident.global_position


func _dispatch_next() -> void:
	if not _running:
		return
	if _queue.is_empty():
		return

	var candidate: Dictionary = _queue.pop_front()
	var incident: FireIncident = _spawner.spawn_incident(candidate)
	if incident == null:
		push_error("dispatch could not spawn an incident for %s" % candidate.get("id", "?"))
		return

	active_incident = incident
	call_number += 1
	incident.set_active_call(true)
	incident.incident_extinguished.connect(_on_incident_extinguished)
	incident.incident_lost.connect(_on_incident_lost)
	call_dispatched.emit(call_number, total_calls, incident)


func _disconnect_active() -> void:
	if active_incident == null or not is_instance_valid(active_incident):
		return
	active_incident.set_active_call(false)
	if active_incident.incident_extinguished.is_connected(_on_incident_extinguished):
		active_incident.incident_extinguished.disconnect(_on_incident_extinguished)
	if active_incident.incident_lost.is_connected(_on_incident_lost):
		active_incident.incident_lost.disconnect(_on_incident_lost)


func _on_incident_extinguished(incident_id: String) -> void:
	_disconnect_active()
	call_extinguished.emit(incident_id)
	# The incident stays on screen, terminal and inert, through the confirmation
	# pause. GameSession clears it when the shift ends or the next call arrives.
	if call_number < total_calls:
		_confirmation_remaining = CONFIRMATION_SECONDS
	else:
		_running = false


func _on_incident_lost(incident_id: String) -> void:
	_disconnect_active()
	_running = false
	call_lost.emit(incident_id)


func _process(delta: float) -> void:
	if _confirmation_remaining <= 0.0:
		return
	_confirmation_remaining -= delta
	if _confirmation_remaining <= 0.0:
		_confirmation_remaining = 0.0
		_dispatch_next()
