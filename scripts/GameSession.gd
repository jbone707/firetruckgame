extends Node
class_name GameSession
## Shift state, rewards and the shop (handoff sections 3, 8 and 9).
##
## MENU to PLAYING to RESULTS to SHOP, with pause handled separately by the
## engine's own pause rather than by a state here, so pausing cannot desync the
## state machine.
##
## Every reward passes through this node, and every reward is guarded. A call
## pays once however many times its signal arrives, and the shift bonus pays
## once per shift. FireIncident guards its own terminal transition too; these
## guards are the second layer, because a duplicate credit is the kind of bug
## that is invisible until a player notices they are rich.

signal state_changed(state: State)
signal credits_changed(credits: int)
signal shift_progress_changed(completed_calls: int, total_calls: int)
signal shift_ended(succeeded: bool, reason: String)

## MAP_SELECT and CREDITS are appended rather than inserted in menu order, so
## the numbers every existing check and save already uses do not shift under
## them. They are menu screens, not phases of a shift: nothing in either can
## reward, spend or start anything.
enum State { MENU, PLAYING, RESULTS, SHOP, MAP_SELECT, CREDITS }

var balance: Node = null
var save_manager: SaveManager = null

var state: State = State.MENU
var completed_calls: int = 0
var credits_earned_this_shift: int = 0
var last_shift_succeeded: bool = false
var last_shift_reason: String = ""

var _dispatch: DispatchManager = null
var _truck: TruckController = null
var _water: WaterSystem = null
var _spawner: Node = null

## Incident ids already paid for during this shift, and whether the completion
## bonus has been paid. Both cleared only by start_shift().
var _rewarded_incidents: Dictionary = {}
var _bonus_paid: bool = false
var _shift_over: bool = false


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


func setup(
	spawner: Node,
	dispatch: DispatchManager,
	truck: TruckController,
	water: WaterSystem,
	save: SaveManager
) -> void:
	resolve_balance()
	_spawner = spawner
	_dispatch = dispatch
	_truck = truck
	_water = water
	save_manager = save

	_dispatch.call_extinguished.connect(_on_call_extinguished)
	_dispatch.call_lost.connect(_on_call_lost)
	_truck.truck_destroyed.connect(_on_truck_destroyed)

	_set_state(State.MENU)
	credits_changed.emit(save_manager.credits)


func get_credits() -> int:
	return save_manager.credits


func has_tank_upgrade() -> bool:
	return save_manager.tank_upgrade_owned


## Clears every fire, marker, signal connection, cooldown and reward guard from
## the previous shift, then starts a new one (handoff section 9). Nothing here
## creates a second copy of anything: the truck and the water system are the
## same nodes reset in place, and incidents are freed by the spawner.
func start_shift() -> void:
	resolve_balance()

	_rewarded_incidents.clear()
	_bonus_paid = false
	_shift_over = false
	completed_calls = 0
	credits_earned_this_shift = 0

	_dispatch.reset()
	_spawner.clear_incidents()

	_truck.reset_for_new_shift(
		_spawner.get_station_spawn_position(), _spawner.get_station_spawn_heading()
	)
	# The upgrade bought at the end of the last shift takes effect here, which is
	# what handoff section 3 means by applying to the next shift.
	_water.reset_for_new_shift(save_manager.tank_upgrade_owned)

	_set_state(State.PLAYING)
	shift_progress_changed.emit(completed_calls, balance.calls_per_shift)
	_dispatch.start_shift()


func _on_call_extinguished(incident_id: String) -> void:
	if _shift_over:
		return
	# The reward guard. A second arrival for the same incident pays nothing.
	if _rewarded_incidents.has(incident_id):
		return
	_rewarded_incidents[incident_id] = true

	completed_calls += 1
	_award(balance.credits_per_call)
	shift_progress_changed.emit(completed_calls, balance.calls_per_shift)

	if completed_calls >= balance.calls_per_shift:
		_end_shift(true, "Shift complete")


func _on_call_lost(_incident_id: String) -> void:
	_end_shift(false, "The fire got away")


func _on_truck_destroyed() -> void:
	_end_shift(false, "The engine is out of service")


## Credits are banked the moment they are earned and written to disk there and
## then, so a shift that later fails cannot take them back (handoff section 3).
func _award(amount: int) -> void:
	if amount <= 0:
		return
	credits_earned_this_shift += amount
	save_manager.add_credits(amount)
	credits_changed.emit(save_manager.credits)


func _end_shift(succeeded: bool, reason: String) -> void:
	if _shift_over:
		return
	_shift_over = true

	if succeeded and not _bonus_paid:
		_bonus_paid = true
		_award(balance.shift_completion_bonus)

	last_shift_succeeded = succeeded
	last_shift_reason = reason
	_dispatch.reset()
	_set_state(State.RESULTS)
	shift_ended.emit(succeeded, reason)


func open_shop() -> void:
	_set_state(State.SHOP)


func close_shop() -> void:
	_set_state(State.RESULTS)


func return_to_menu() -> void:
	_set_state(State.MENU)


func open_map_select() -> void:
	_set_state(State.MAP_SELECT)


func open_credits() -> void:
	_set_state(State.CREDITS)


## The one Escape rule, in one place. Escape backs out exactly one level and
## never lands in a running game: the shop and the results screen are only
## reachable once a shift is over, and the two menu screens sit above the home
## menu, so no arrow here points at PLAYING. Returns false when there is
## nowhere to back out to, which is the home menu and the game itself.
func back_out() -> bool:
	match state:
		State.MAP_SELECT, State.CREDITS:
			_set_state(State.MENU)
			return true
		State.SHOP:
			_set_state(State.RESULTS)
			return true
		_:
			return false


## Returns a short sentence saying what happened, which is what the shop shows.
func purchase_tank_upgrade() -> String:
	resolve_balance()
	if save_manager.tank_upgrade_owned:
		return "You already own this upgrade"
	if save_manager.credits < balance.tank_upgrade_cost:
		return "Not enough credits, this costs %d credits" % balance.tank_upgrade_cost
	if not save_manager.purchase_tank_upgrade(balance.tank_upgrade_cost):
		return "The purchase could not be completed"
	credits_changed.emit(save_manager.credits)
	return "Bought. The bigger tank is ready for your next shift"


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
