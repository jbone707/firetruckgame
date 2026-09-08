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
| Driving | `TruckController`: arcade throttle and heading-relative steering, impact damage squared in the top of the speed range, camera shake on a hit. |
| Water and fire | `WaterSystem` (tank, turret, stream, refill), `FireIncident` (health and escalation kept separate). |
| Hydrants | `Hydrant`: automatic hookup at a creep inside the ring, hose flies out, snaps when the truck drives away. No key. |
| Session | `GameSession`, `DispatchManager`, `SaveManager`: three calls a shift, sequential dispatch, credits banked per call, one tank upgrade, save file. |
| Screen | `GameUI` (HUD, home menu, map select, Data and Credits, results, shop), `Minimap` with its own zoom, `IncidentIndicator` off-screen arrow, `FollowCamera` north-up with lead and overscan. |
| Tools | `import_osm.gd` (deterministic), `regenerate_map.gd`, `measure_scale.gd`, `validate_map.gd`, `capture_screens.gd`. |

Not built: traffic, pedestrians, audio, any second real area, iPhone or touch.

## Checks

    godot --headless --path . --script res://tests/run_tests.gd
    godot --headless --path . --script res://tests/run_physics_tests.gd
    godot --headless --path . --script res://tools/validate_map.gd

Green at 9cd79b0: 102 unit methods / 4,552 assertions, 211 physics checks,
2 maps validated. Godot on this machine is
`C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.

The screenshot pack must be run windowed, never headless:

    godot --path . --script res://tools/capture_screens.gd

## Active task

| | |
|---|---|
| Task | Traffic, signal preemption, automatic turret, handoff documents |
| Owner | Claude Code |
| Branch | `task/traffic-and-turret` |
| Base | `master` at 9cd79b0 |

## GameBalance values

`GameBalance.gd` is the authority; this table is kept in step with it.

| Value | Section | Source |
|---|---|---|
| `forward_max_speed` = 250.0 | Driving | Specified |
| `reverse_max_speed` = 90.0 | Driving | Specified |
| `acceleration` = 220.0 | Driving | Invented |
| `reverse_acceleration` = 140.0 | Driving | Invented |
| `brake_deceleration` = 320.0 | Driving | Invented |
| `handbrake_deceleration` = 500.0 | Driving | Invented |
| `drag` = 80.0 | Driving | Invented |
| `steering_rate` = 2.4 | Driving | Invented |
| `high_speed_steering_factor` = 0.45 | Driving | Invented |
| `collision_damage_threshold` = 120.0 | Collision | Invented; 60 to 120 after James's Milestone 9 playtest |
| `collision_damage_at_top_speed` = 48.0 | Collision | Invented; the cost curve is squared, not linear |
| `collision_contact_cooldown` = 0.5 | Collision | Invented |
| `tank_capacity` = 100.0 | Water | Specified |
| `spray_flow_rate` = 10.0 | Water | Specified |
| `stream_range` = 280.0 | Water | Specified as 120; rescaled to one road width after the playtest |
| `fire_damage_per_second` = 20.0 | Water | Specified |
| `fire_starting_health` = 100.0 | Water | Specified |
| `suppression_per_water_unit` = 2.0 | Water | Derived |
| `fire_escalation_duration` = 45.0 | Fire | Specified as 120; now the base, travel paid separately |
| `escalation_travel_speed` = 110.0 | Fire | Invented |
| `escalation_travel_allowance_max` = 150.0 | Fire | Invented |
| `hydrant_hose_launch_time` = 0.6 | Hydrants | Invented |
| `hydrant_hose_slack_distance` = 200.0 | Hydrants | Invented |
| `hydrant_hose_snap_distance` = 260.0 | Hydrants | Invented |
| `hydrant_rehook_delay` = 1.5 | Hydrants | Invented |
| `hydrant_snap_message_time` = 1.0 | Hydrants | Invented |
| `hydrant_refill_rate` = 50.0 | Hydrants | Specified as 25; doubled after a playtest |
| `hydrant_max_hookup_speed` = 25.0 | Hydrants | Invented |
| `hydrant_interaction_radius` = 160.0 | Hydrants | Invented; measured to the bodywork, not the centre |
| `calls_per_shift` = 3 | Session | Specified |
| `credits_per_call` = 100 | Session | Specified |
| `shift_completion_bonus` = 50 | Session | Specified |
| `tank_upgrade_cost` = 200 | Session | Specified |
| `tank_upgrade_multiplier` = 1.25 | Session | Specified |
| `truck_starting_condition` = 100.0 | Session | Invented |
| `first_call_min_route` = 2000.0 | Session | Invented |
| `camera_zoom_levels` = [0.9, 0.7, 0.55] | Camera | Invented; all three kept, Z cycles them |
| `minimap_zoom_levels` = [1.0, 2.0, 4.0] | Camera | Invented; never touches the camera |
| `signal_green_time` = 12.0 | Signals | Invented |
| `signal_amber_time` = 3.0 | Signals | Invented |
| `signal_all_red_time` = 1.0 | Signals | Invented |

## Known issues

- Milestone 9 (lanes, signal heads, playtest fixes) has no narrative in
  `docs/history/`. Its record is its three commit messages: fef6575, 87dd983,
  9cd79b0.
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

Playtest the branch build on Windsor: drive to a call with the siren on and
watch whether traffic yields and whether the preempt delay makes arriving fast
dangerous.
