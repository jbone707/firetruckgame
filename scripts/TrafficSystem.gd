extends Node2D
class_name TrafficSystem
## The traffic: how many cars there are, where they appear and vanish, and the
## rules of the road every one of them drives by.
##
## The cars themselves know how to follow a lane and what their driver thinks
## about the siren. This node owns everything that needs to look at more than one
## car at once: the gap to the vehicle in front, whether a junction can be
## entered, who has to give way to whom, and the population.
##
## SEEDED PER SHIFT. Every per-driver number, every turn taken at a junction and
## every spawn comes out of one RandomNumberGenerator seeded when the shift
## starts, so a shift is the same shift twice given the same seed and a check can
## drive the same traffic every time it runs. A different seed each shift is what
## makes the flawed drivers a different set of drivers each shift.

## How close to the junction a car starts asking whether it may enter, world
## units. Far enough out that it can still stop at the line from cruising speed
## on a residential street.
const JUNCTION_LOOK: float = 240.0

## How far into the junction a car counts as occupying it, world units past the
## junction's own radius. "Never enter a junction it cannot clear" is this
## number: a car already inside one is a reason for the next car to wait.
const JUNCTION_OCCUPANCY_MARGIN: float = 40.0

## How wide a corridor counts as "in front of me" when looking for the car
## ahead, world units either side of the centreline. Half a lane: a car in the
## next lane over, going the other way, is not something to brake for.
const AHEAD_CORRIDOR: float = 34.0

## How far ahead a driver looks for the car in front, world units.
const AHEAD_LOOK: float = 320.0

## How far away a car on the right has to be before it stops being a reason to
## wait at an uncontrolled junction, world units.
const YIELD_RIGHT_DISTANCE: float = 260.0

## How far a car must be from the engine's line of travel before it stops
## counting as "in the way", world units. Used only to decide whether the engine
## has passed a yielding car.
const PASSED_MARGIN: float = 60.0

var balance: Node = null

var _lanes: LaneGraph = null
var _signals: TrafficSignals = null
var _cars: Array[TrafficCar] = []
var _rng := RandomNumberGenerator.new()

## The engine, pushed in by Main each frame exactly as it is to TrafficSignals.
var _engine_position: Vector2 = Vector2.ZERO
var _engine_forward: Vector2 = Vector2.RIGHT
var _engine_siren: bool = false

## Half the screen's height in world units, which everything about spawning and
## despawning is measured in. Set by Main from the camera, because the camera is
## the only node that knows the zoom.
var _screen_height: float = 800.0

## Lanes whose midpoint could hold a car worth spawning, rebuilt per map.
var _lane_targets: Array[float] = []

var _enabled: bool = false

## Whether the density rule is allowed to put cars on the road by itself. Off
## only in checks, which place the two or three cars the scenario is about and
## would otherwise be measuring them among a dozen others.
var ambient_spawning: bool = true


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


func _ready() -> void:
	resolve_balance()


## Called on every map load. Everything the last map's traffic left behind goes
## first, for the same reason the incidents and the hydrants do.
func configure(lane_graph: LaneGraph, signal_node: TrafficSignals) -> void:
	resolve_balance()
	clear_traffic()
	_lanes = lane_graph
	_signals = signal_node
	_lane_targets.clear()
	if _lanes == null:
		return
	# How many cars each lane is worth, at its own class's density. Cached
	# because it is a property of the map and asking it per frame per lane would
	# be the same arithmetic 226 times a second for no new answer.
	for lane in _lanes.lanes:
		_lane_targets.append(
			float(lane["length"]) * _density_for_class(String(lane["highway"])) / 1000.0
		)


func _density_for_class(highway: String) -> float:
	if LaneGraph.MAJOR_CLASSES.has(highway):
		return balance.traffic_density_major
	if highway == "service" or highway == "track" or highway == "living_street":
		return balance.traffic_density_court
	return balance.traffic_density_residential


func clear_traffic() -> void:
	for car in _cars:
		if is_instance_valid(car):
			car.queue_free()
	_cars.clear()


func get_cars() -> Array[TrafficCar]:
	return _cars


func car_count() -> int:
	return _cars.size()


## Traffic runs during a shift and not on the menus. Called by Main from the
## session's own state, so cars are not driving round behind the home screen.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		clear_traffic()


func is_enabled() -> bool:
	return _enabled


## One seed for the whole shift. Given the same one, the same drivers with the
## same flaws take the same turns.
func start_shift(seed_value: int) -> void:
	clear_traffic()
	_rng.seed = seed_value
	_enabled = true


func set_engine_state(position: Vector2, forward: Vector2, siren_active: bool) -> void:
	_engine_position = position
	if forward.length_squared() > 0.0:
		_engine_forward = forward.normalized()
	_engine_siren = siren_active


func set_screen_height(height: float) -> void:
	_screen_height = maxf(height, 1.0)


func spawn_distance() -> float:
	return _screen_height * balance.traffic_spawn_screens


func despawn_distance() -> float:
	return spawn_distance() * balance.traffic_despawn_factor


# ---------------------------------------------------------------------------
# The frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _enabled or _lanes == null:
		return
	_retire_distant_cars()
	_fill_to_target()
	_drive(delta)


## Cars that have gone too far from the engine to matter. Freed rather than
## parked: a car nobody can see is memory and frame time and nothing else.
##
## The reach is bigger than the spawn reach by traffic_despawn_factor, so the
## boundary a car is created outside of is not the boundary it is destroyed at
## and an engine sitting still cannot flicker cars in and out.
func _retire_distant_cars() -> void:
	var reach: float = despawn_distance()
	var kept: Array[TrafficCar] = []
	for car in _cars:
		if not is_instance_valid(car):
			continue
		if car.global_position.distance_to(_engine_position) > reach:
			car.queue_free()
			continue
		kept.append(car)
	_cars = kept


## How many cars the roads around the engine are worth right now, capped.
func target_population() -> int:
	if _lanes == null:
		return 0
	var reach: float = spawn_distance()
	var wanted: float = 0.0
	for index in range(_lanes.lanes.size()):
		var lane: Dictionary = _lanes.lanes[index]
		var midpoint: Vector2 = (Vector2(lane["entry"]) + Vector2(lane["exit"])) * 0.5
		if midpoint.distance_to(_engine_position) > reach:
			continue
		wanted += _lane_targets[index]
	return mini(int(round(wanted)), balance.traffic_max_vehicles)


## Brings the population up to target, one car per frame at most.
##
## One per frame on purpose: a burst of eight cars appearing on the same frame
## is a burst of eight cars appearing, and at 60 frames a second a shortfall is
## made up inside a fifth of a second anyway.
func _fill_to_target() -> void:
	if not ambient_spawning:
		return
	if _cars.size() >= target_population():
		return
	var spot: Dictionary = _find_spawn_spot()
	if spot.is_empty():
		return
	spawn_car_on(int(spot["lane"]), float(spot["travelled"]))


## Puts one car on one lane at one point along it. The only way a car is ever
## created, so a car placed by a check is the same object driven by the same
## rules as a car the density put there.
func spawn_car_on(lane_index: int, travelled: float) -> TrafficCar:
	resolve_balance()
	if _lanes == null or lane_index < 0 or lane_index >= _lanes.lanes.size():
		return null
	var car := TrafficCar.new()
	add_child(car)
	car.setup(balance, _lanes, _signals, lane_index, travelled, _rng)
	_cars.append(car)
	return car


## A place on a lane that is outside the view, inside the spawn reach, and not
## on top of another car.
##
## Tried a few times rather than solved. The lane list is hundreds long and the
## rejection rate is low, so a handful of random draws finds a spot whenever one
## exists, and returning empty when it does not simply means no car this frame.
func _find_spawn_spot() -> Dictionary:
	var inner: float = _screen_height * 0.62
	var outer: float = spawn_distance()
	for _attempt in range(12):
		var lane_index: int = _rng.randi_range(0, _lanes.lanes.size() - 1)
		var lane: Dictionary = _lanes.lanes[lane_index]
		var length: float = float(lane["length"])
		if length < TrafficCar.LENGTH * 2.0:
			continue
		var travelled: float = _rng.randf_range(0.0, length)
		var at: Vector2 = Vector2(lane["entry"]).lerp(Vector2(lane["exit"]), travelled / length)
		var distance: float = at.distance_to(_engine_position)
		if distance < inner or distance > outer:
			continue
		var clear: bool = true
		for car in _cars:
			if car.global_position.distance_to(at) < TrafficCar.LENGTH * 2.5:
				clear = false
				break
		if not clear:
			continue
		return {"lane": lane_index, "travelled": travelled}
	return {}


func _drive(delta: float) -> void:
	# Which junctions are occupied, worked out once for the whole frame rather
	# than once per car asking about the same junction.
	var occupied: Dictionary = _occupied_junctions()

	for car in _cars:
		if not is_instance_valid(car):
			continue
		var perceives: bool = _driver_perceives(car)
		var passed: bool = _engine_has_passed(car)
		car.update_yield(delta, perceives, passed)

		var gap: float = _gap_ahead(car)
		var may_enter: bool = _may_enter_junction(car, occupied, delta)
		var target: float = car.desired_speed(gap, may_enter)
		car.advance(delta, target, _rng)


## Whether this driver can hear the siren, now.
##
## The plain rule is the siren on and the engine inside traffic_perceive_distance,
## which covers all three cases the design asks for: ahead of the engine, behind
## it, and waiting at a junction the engine is coming to. Two exceptions, both
## deliberate. A driver with the late-notice flaw hears nothing until the engine
## is much closer. And a courteous driver pulls over for an engine that is close
## behind them even with the siren off, which is the one in five that makes a
## silent run through traffic not quite predictable either.
func _driver_perceives(car: TrafficCar) -> bool:
	var to_car: Vector2 = car.global_position - _engine_position
	var distance: float = to_car.length()
	if _engine_siren:
		if car.flaw == TrafficCar.Flaw.LATE_NOTICE:
			return distance <= balance.traffic_late_notice_distance
		return distance <= balance.traffic_perceive_distance
	if not car.courteous:
		return false
	# Close behind: the engine is within the late-notice distance and the car is
	# ahead of it, going the same way.
	if distance > balance.traffic_late_notice_distance:
		return false
	return _engine_forward.dot(to_car) > 0.0 and _engine_forward.dot(car.get_heading()) > 0.3


## Whether the engine is behind this car and going away from it, which is what
## ends the wait. Measured against the ENGINE's heading, not the car's, so a car
## that pulled over facing the other way is released by the same rule.
func _engine_has_passed(car: TrafficCar) -> bool:
	var to_car: Vector2 = car.global_position - _engine_position
	if _engine_forward.dot(to_car) > 0.0:
		return false
	return to_car.length() > PASSED_MARGIN


## The distance to the nearest vehicle in front of this car, or INF.
##
## Geometric rather than topological: anything inside a narrow corridor along
## this car's own heading counts, whether it is on the same lane, on the turn
## across the junction ahead, or on the lane past it. That is what lets a queue
## form through a junction without anything having to know the queue exists.
##
## The engine counts too. A driver does not drive into the back of a fire engine
## that has stopped in front of them.
func _gap_ahead(car: TrafficCar) -> float:
	var heading: Vector2 = car.get_heading()
	var nearest: float = INF
	for other in _cars:
		if other == car or not is_instance_valid(other):
			continue
		nearest = minf(nearest, _forward_gap(car.global_position, heading, other.global_position))
	nearest = minf(nearest, _forward_gap(car.global_position, heading, _engine_position))
	return nearest


func _forward_gap(from: Vector2, heading: Vector2, to: Vector2) -> float:
	var offset: Vector2 = to - from
	var ahead: float = offset.dot(heading)
	if ahead <= 0.0 or ahead > AHEAD_LOOK:
		return INF
	if absf(offset.dot(LaneGraph.right_of(heading))) > AHEAD_CORRIDOR:
		return INF
	# Bumper to bumper rather than centre to centre, so the following gap means
	# the gap a person would see.
	return maxf(ahead - TrafficCar.LENGTH, 0.0)


## Every junction with a vehicle inside it, so nothing follows another car into
## a box it cannot get out of.
func _occupied_junctions() -> Dictionary:
	var occupied: Dictionary = {}
	for car in _cars:
		if not is_instance_valid(car) or not car.is_in_junction():
			continue
		var turn: Dictionary = _lanes.turns[car.turn_id]
		occupied[int(turn["node"])] = true
	return occupied


## The whole of the rules of the road at a junction, for one car.
##
## In order, because the order is the rule: a red stops a car whatever else is
## true, then an amber unless it is too late to stop, then a stop sign's own
## halt and wait, then whether the box is clear, then who has priority.
func _may_enter_junction(car: TrafficCar, occupied: Dictionary, delta: float) -> bool:
	if car.is_in_junction():
		return true
	var node: int = car.target_junction()
	if node < 0:
		return true
	var to_line: float = car.distance_to_stop_line()
	if to_line > JUNCTION_LOOK:
		return true

	var lane: Dictionary = _lanes.lanes[car.lane_id]
	var edge_index: int = int(lane["edge_index"])
	var control: int = _lanes.get_control(node)
	var stop_signed: bool = _lanes.arm_has_stop_sign(node, edge_index)

	if control == LaneGraph.JunctionControl.SIGNAL and _signals != null:
		match _signals.light_for_arm(node, edge_index):
			TrafficSignals.Light.RED:
				return false
			TrafficSignals.Light.AMBER:
				# Stop, unless stopping would mean stopping in the junction.
				if to_line > car.braking_distance():
					return false
	elif stop_signed:
		# Come to a real halt at the line, wait, look, then go. Both halves are
		# latched: the halt is a thing that happened, not a thing that is still
		# true, and without the latch the "are you stopped" test fires again the
		# moment the car is moving and strands it across the junction mouth.
		if not car.has_stopped_at_sign:
			# A HALT, not a slow roll. Two units a second is a car that has
			# stopped; six is a car that has thought about it.
			if to_line > 2.0 and car.speed > 2.0:
				return false
			car.stop_sign_waited += delta
			if car.stop_sign_waited < balance.traffic_stop_sign_wait:
				return false
			car.has_stopped_at_sign = true
		if not car.cleared_the_stop:
			if not _cross_traffic_is_clear(car, node):
				return false
			car.cleared_the_stop = true

	# Nothing enters a junction another vehicle is already in.
	if occupied.get(node, false) and to_line < TrafficCar.LENGTH:
		return false

	# Uncontrolled: give way to the right. A signalled arm and the through arm
	# of a stop junction both have priority and do not ask.
	#
	# "Uncontrolled" means a real junction with no control on it. A two-arm bend
	# and a dead end are not junctions at all and are not in the junction table:
	# there is nothing to give way to at either, which is the same reason
	# LaneGraph does not classify them.
	if control == LaneGraph.JunctionControl.NONE and _lanes.junctions.has(node):
		if not _nothing_coming_from_the_right(car, node):
			return false
	return true


## Whether anything with priority is coming through the junction this car is
## stopped at. Used by a stop sign, which has to wait for the road it is joining.
func _cross_traffic_is_clear(car: TrafficCar, node: int) -> bool:
	var here: Vector2 = _lanes.junctions[node]["position"]
	var radius: float = float(_lanes.junctions[node]["widest_width"]) * 0.5
	for other in _cars:
		if other == car or not is_instance_valid(other):
			continue
		if other.is_in_junction():
			var turn: Dictionary = _lanes.turns[other.turn_id]
			if int(turn["node"]) == node:
				return false
			continue
		if other.target_junction() != node:
			continue
		if _lanes.arm_has_stop_sign(node, int(_lanes.lanes[other.lane_id]["edge_index"])):
			# Another car at another stop sign has no priority over this one.
			continue
		if other.distance_to_stop_line() < radius + YIELD_RIGHT_DISTANCE and other.speed > 4.0:
			return false
	# The engine has priority over everything, and it is never stopped by a sign.
	if _engine_position.distance_to(here) < radius + YIELD_RIGHT_DISTANCE:
		return false
	return true


## Give way to the right: nothing approaching from the driver's right side of
## the junction, close enough and moving.
func _nothing_coming_from_the_right(car: TrafficCar, node: int) -> bool:
	var here: Vector2 = _lanes.junctions[node]["position"]
	var to_the_right: Vector2 = LaneGraph.right_of(car.get_heading())
	for other in _cars:
		if other == car or not is_instance_valid(other):
			continue
		if other.is_in_junction():
			if int(_lanes.turns[other.turn_id]["node"]) == node:
				return false
			continue
		if other.target_junction() != node:
			continue
		if other.speed <= 4.0:
			continue
		if other.distance_to_stop_line() > YIELD_RIGHT_DISTANCE:
			continue
		# On my right if it is approaching from the side my right hand points to.
		if (other.global_position - here).dot(to_the_right) > 0.0:
			return false
	return true
