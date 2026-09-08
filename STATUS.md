# Tailboard: status

The one file that says where this project is. Read it first. The milestone
narratives that used to live here are in `docs/history/milestone-NN.md`,
unchanged; nothing in this file repeats them.

## Engine

Godot `4.7.2.stable.official.ed1daf0bf`. Compatibility renderer, 1280x720
default viewport, `canvas_items` stretch with `expand`. One autoload,
`GameBalance`.

## What is built

| System | State |
|---|---|
| Maps | Two: Elm Grove (fictional, 4000x3000) and Windsor Shadetree (OpenStreetMap, 7820x6140). `MapDefinition` data, `MapBuilder` draws, `MapGeometry` derives every shape from the roads alone. |
| Map validation | `MapValidator`, eight rules, both maps pass. `tools/validate_map.gd` runs it. |
| Lane network | `LaneGraph`: two directional lanes per segment, Bezier turns across junctions, U-turns only at dead ends. Both maps strongly connected. |
| Junction control | Signals where the widest arm is tertiary or above or the junction has four arms; stop signs on the minor arms otherwise. Windsor 6 signals / 14 stop junctions, Elm Grove 16 signals. |
| Signals | `TrafficSignals`: one clock for the whole map, opposing arms share a phase, green / amber / all-red. Pauses with the game. |
| Preemption | With the siren on inside 900 route units, a signalled junction ahead clears its cross arms and gives the engine's arm a green, four seconds later. Holds two seconds after the engine is past, then rejoins the cycle at the next phase. |
| Traffic | `TrafficCar` and `TrafficSystem`: cars on the lane network at a class speed with a following gap, obeying lights, stop signs, priority to the right and the box junction rule. Solid to the engine, never to each other. Pull over for the siren, with one driver in ten flawed and one in five courteous, all from a per-shift seed. |
| Driving | `TruckController`: arcade throttle and heading-relative steering, impact damage squared in the top of the speed range, camera shake on a hit. Hitting a car costs 0.4 of the wall rule and speed by how square the hit was. |
| Water and fire | `WaterSystem` (tank, AUTOMATIC turret, stream, refill), `FireIncident` (health and escalation kept separate). No aim and no spray key; water is spent only into a fire. |
| Hydrants | `Hydrant`: automatic hookup at a creep inside the ring, hose flies out, snaps when the truck drives away. No key. |
| Session | `GameSession`, `DispatchManager`, `SaveManager`: three calls a shift, sequential dispatch, credits banked per call, one tank upgrade, save file. |
| Screen | `GameUI` (HUD, home menu, map select, Data and Credits, results, shop, contact glyph), `Minimap` with its own zoom, `IncidentIndicator` off-screen arrow, `FollowCamera` north-up, leading two seconds of travel clamped to a third of the screen, with overscan. |
| Tools | `import_osm.gd` (deterministic), `regenerate_map.gd`, `measure_scale.gd`, `validate_map.gd`, `capture_screens.gd`. |

Not built: pedestrians, audio, any second real area, iPhone or touch, and any
upgrade that changes how traffic behaves.

## Checks

    godot --headless --path . --script res://tests/run_tests.gd
    godot --headless --path . --script res://tests/run_physics_tests.gd
    godot --headless --path . --script res://tools/validate_map.gd

Green on `task/traffic-and-turret`: 111 unit methods / 4,777 assertions, 288
physics checks, 2 maps validated. Godot on this machine is
`C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.

The screenshot pack must be run windowed, never headless:

    godot --path . --script res://tools/capture_screens.gd

## Active task

| | |
|---|---|
| Task | Traffic, signal preemption, automatic turret, handoff documents |
| Owner | Claude Code |
| Branch | `task/traffic-and-turret`, all six parts done, pull request open |
| Base | `master` at 9cd79b0 |
| Waiting on | James's playtest, then the merge |

## GameBalance values

`GameBalance.gd` is the authority and carries the reasoning for every number;
this is the list, kept in step with it. Values the handoff specified are marked
S, values invented here are marked I, and a value that has MOVED from what the
handoff said carries both.

| Group | Values |
|---|---|
| Driving | S `forward_max_speed` 250, `reverse_max_speed` 90. I `acceleration` 220, `reverse_acceleration` 140, `brake_deceleration` 320, `handbrake_deceleration` 500, `drag` 80, `steering_rate` 2.4, `high_speed_steering_factor` 0.45 |
| Collision | I `collision_damage_threshold` 120 (was 60, raised after the Milestone 9 playtest), `collision_damage_at_top_speed` 48 on a SQUARED curve, `collision_contact_cooldown` 0.5, `car_collision_damage_scale` 0.4, `car_shove_distance` 42 |
| Water | S `tank_capacity` 100, `spray_flow_rate` 10, `fire_damage_per_second` 20, `fire_starting_health` 100, derived `suppression_per_water_unit` 2.0. S/I `stream_range` 280 (specified 120, rescaled to one road width). I `turret_rotation_rate` 2.4 rad/s |
| Fire | S/I `fire_escalation_duration` 45 (specified 120, now the base with travel paid separately). I `escalation_travel_speed` 110, `escalation_travel_allowance_max` 150 |
| Hydrants | S/I `hydrant_refill_rate` 50 (specified 25). I `hydrant_hose_launch_time` 0.6, `hydrant_hose_slack_distance` 200, `hydrant_hose_snap_distance` 260, `hydrant_rehook_delay` 1.5, `hydrant_snap_message_time` 1.0, `hydrant_max_hookup_speed` 25, `hydrant_interaction_radius` 160 (measured to the bodywork, not the centre) |
| Session | S `calls_per_shift` 3, `credits_per_call` 100, `shift_completion_bonus` 50, `tank_upgrade_cost` 200, `tank_upgrade_multiplier` 1.25. I `truck_starting_condition` 100, `first_call_min_route` 2000 |
| Camera | I `camera_zoom_levels` [0.9, 0.7, 0.55], `minimap_zoom_levels` [1.0, 2.0, 4.0], `FollowCamera.LOOK_AHEAD_SECONDS` 2.0, `MAX_LEAD_SCREENS` 1/3 |
| Signals | I `signal_green_time` 12, `signal_amber_time` 3, `signal_all_red_time` 1, `signal_preempt_distance` 900 route units forward only, `signal_preempt_resume_hold` 2 |
| Traffic, how many | I `traffic_max_vehicles` 24, densities per 1,000 lane units 3.40 major / 1.15 residential / 0.40 court (set by measuring Windsor, not by arithmetic), `traffic_spawn_screens` 1.5, `traffic_despawn_factor` 1.35 |
| Traffic, how they drive | I speeds 165 / 125 / 85, `traffic_acceleration` 130, `traffic_braking` 260, `traffic_emergency_braking` 420, `traffic_following_gap` 42, `traffic_stop_sign_wait` 0.9 |
| Traffic, the siren | I `traffic_perceive_distance` 900, reaction 0.5 to 2.0 s and clear delay 1.0 to 2.0 s per driver from the shift seed, `traffic_yield_offset` 62 over `traffic_yield_move_time` 1.0, `traffic_imperfect_share` 0.1, `traffic_courtesy_share` 0.2, `traffic_late_notice_distance` 300 |

## Known issues

- **Nothing on this branch has been played.** Every number is headless or from a
  rendered still. Whether the traffic feels like traffic, whether the preempt
  delay makes arriving fast dangerous rather than merely annoying, and whether
  the automatic turret takes something away from the fighting are James's to
  judge.
- An engine parked next to a signalled junction with its siren left on holds
  that junction's green for as long as it stands there, and the cross traffic
  queues. That is what a real preemption does and it is self-inflicted, but no
  timeout exists and nobody has watched what a two minute one looks like.
- A yielding car pulls onto the sidewalk strip and nothing checks that the strip
  is there. On a road with houses hard against the kerb it will sit half in a
  fence. Neither shipped map has one, and nothing looks for one.
- Milestone 9 (lanes, signal heads, playtest fixes) has no narrative in
  `docs/history/`. Its record is its three commit messages: fef6575, 87dd983,
  9cd79b0. Milestone 10, this branch, has its record in its six commit messages
  and in the pull request.
- Nine of Windsor's 81 driveways overlap their own house footprint by more than
  a quarter of the strip. The threshold has not been tuned.
- Four two-arm bends on Windsor still have junction fills reaching the map edge.
  Rule 7 only asks about junctions of three arms or more.
- `MapDefinition.blocks`, `body_color` and `roof_color` are dead data, kept
  deliberately and named as dead in the file.
- Escalation is not slowed by effective suppression.
- Driving on the sidewalk is free, pending pedestrians.
- No audio at all.
- Windsor's coverage past the original download box is ragged by construction:
  the 30 m fringe holds roads whose neighbours are not in the extract.

## Next action

Playtest `task/traffic-and-turret` on Windsor, in this order: drive to a call
with the siren OFF and see what traffic does when it does not care about you;
turn it on and drive the same stretch; then arrive at a signalled junction flat
out and find out whether the four second preempt delay is a reason to slow down.
Then merge, or say what is wrong.
