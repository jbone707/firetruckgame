# Fire Truck Game Development Status

## Godot Version

`4.7.2.stable.official.ed1daf0bf`, confirmed by running the console
executable with `--version`.

## Current File Inventory

- `project.godot`: project configuration. Compatibility renderer, 1280x720
  default viewport, `canvas_items` stretch mode with `expand` aspect, main
  scene set to `scenes/Main.tscn`, `GameBalance` autoload, and every input
  action from handoff §4.
- `.gitignore`: ignores the `.godot/` import cache, `*.tmp` files, and
  `export_presets.cfg`.
- `README.md`: launch steps and controls for James.
- `DESIGN.md`: what the game is and how it plays, with a "Future, not
  implemented" section.
- `DEVELOPMENT_STATUS.md`: this file.
- `scripts/GameBalance.gd`: autoload singleton holding every tuning value
  from handoff §4, §5, §6 and §3.
- `scenes/Main.tscn` and `scripts/Main.gd`: placeholder main scene. Prints a
  confirmation line and the running Godot version on `_ready()`. Nothing
  else. Later parts replace this with the real Main/GameSession
  orchestrator.
- `scenes/`, `scripts/systems/`, `resources/`, `tests/`: empty folders for
  later parts, each holding a `.gitkeep` placeholder so git tracks the
  directory.

## GameBalance Values

| Value | Section | Source |
|---|---|---|
| `forward_max_speed` = 250.0 | §4 Driving | Specified |
| `reverse_max_speed` = 90.0 | §4 Driving | Specified |
| `acceleration` = 220.0 | §4 Driving | Invented |
| `reverse_acceleration` = 140.0 | §4 Driving | Invented |
| `brake_deceleration` = 320.0 | §4 Driving | Invented |
| `handbrake_deceleration` = 500.0 | §4 Driving | Invented |
| `drag` = 80.0 | §4 Driving | Invented |
| `steering_rate` = 2.4 | §4 Driving | Invented |
| `high_speed_steering_factor` = 0.45 | §4 Driving | Invented |
| `collision_damage_threshold` = 60.0 | §4 Collision | Invented |
| `collision_damage_scale` = 0.6 | §4 Collision | Invented |
| `collision_contact_cooldown` = 0.5 | §4 Collision | Invented |
| `tank_capacity` = 100.0 | §5 Water | Specified |
| `spray_flow_rate` = 10.0 | §5 Water | Specified |
| `stream_range` = 120.0 | §5 Water | Specified |
| `fire_damage_per_second` = 20.0 | §5 Water | Specified |
| `fire_starting_health` = 100.0 | §5 Water | Specified |
| `suppression_per_water_unit` = 2.0 | §5 Water | Derived from specified values (`fire_damage_per_second / spray_flow_rate`) |
| `fire_escalation_duration` = 120.0 | §5 Fire | Specified |
| `hydrant_hookup_time` = 2.0 | §6 Hydrants | Specified |
| `hydrant_refill_rate` = 25.0 | §6 Hydrants | Specified |
| `hydrant_max_hookup_speed` = 15.0 | §6 Hydrants | Invented |
| `hydrant_interaction_radius` = 48.0 | §6 Hydrants | Invented |
| `calls_per_shift` = 3 | §3 Session | Specified |
| `credits_per_call` = 100 | §3 Session | Specified |
| `shift_completion_bonus` = 50 | §3 Session | Specified |
| `tank_upgrade_cost` = 200 | §3 Session | Specified |
| `tank_upgrade_multiplier` = 1.25 | §3 Session | Specified |
| `truck_starting_condition` = 100.0 | §3 Session | Invented |

## Deviations and Choices

- **`return_to_station` key binding.** Handoff §4 asks for a station
  recovery/reset action for development but does not name a key for it. R
  was chosen (not in use by any other action) and is documented in the
  README as a development aid, and explicitly not a repair/refill/reset
  action for a live incident.
- **Stretch aspect set to `expand`, not `keep`.** Handoff §8 asks for the UI
  to scale across wide and narrow landscape windows. `canvas_items` stretch
  mode with `expand` aspect lets HUD anchors reflow to fill the window
  instead of letterboxing with black bars, which is what that requirement
  calls for. `keep` would preserve the aspect ratio exactly but would add
  bars on window shapes that do not match 1280x720, which is not what a
  "scale across wide and narrow" HUD needs.
- **Default viewport size 1280x720.** Not specified by the handoff beyond
  "landscape orientation"; chosen as a common, easy-to-test landscape
  default.

## Known Issues

- No gameplay exists yet. The main scene is a placeholder that only confirms
  the project boots.
- None of the systems listed in handoff §8 (TruckController, WaterSystem,
  FireIncident, Hydrant, DispatchManager, SaveManager, HUD,
  MapDefinition/MapBuilder) have been built. That is intentional: this part
  is scaffolding only.

## Verification Performed

All three commands were run from the project root using the console
executable and exited 0 with no script or parse errors:

- `--headless --path . --import`
- `--headless --path . --quit` (printed the `Main.gd` `_ready()` confirmation
  line, including the running Godot version)
- `--headless --check-only --script res://scripts/GameBalance.gd` and the
  same for `res://scripts/Main.gd`

No gameplay exists yet, so there is nothing to visually playtest in this
part.

## Part 2: Map Data and Construction

Adds the neighborhood's data and the code that builds it into a scene, per
handoff §7 and §8. Part 1's placeholder main scene is unchanged; nothing in
this part wires the map into it, since that is Part 3's job.

### Files Added

- `scripts/MapDefinition.gd`: `Resource` subclass (`class_name MapDefinition`)
  describing a neighborhood: `schema_version`, `map_id`, `display_name`,
  empty `source_metadata`/`geographic_bounds` placeholders for a future
  real-map importer, `world_bounds`, station spawn position/heading, and
  typed `Array[Dictionary]` lists of roads, buildings, hydrants and incident
  candidates, each with stable string ids. Also holds
  `create_fictional_neighbourhood()`, the static factory that builds this
  milestone's one map.
- `scripts/MapBuilder.gd`: `Node2D` subclass (`class_name MapBuilder`) that
  reads a `MapDefinition` and constructs the scene: road surfaces and
  flanking sidewalks as `Line2D`, street name labels, buildings as
  `Polygon2D` body + inset `Polygon2D` roof + `StaticBody2D`/
  `CollisionPolygon2D` on layer 1 mask 0, decorative (collision-free)
  hydrant and incident markers, and four `StaticBody2D` edge walls (layer 1
  mask 0, 40-unit thick) around `world_bounds`. Exposes
  `get_station_spawn_position()`, `get_station_spawn_heading()`,
  `get_world_bounds()`, `get_hydrant_definitions()`,
  `get_incident_candidates()` and `get_building_polygon(id)` for Parts 3-5.
- `resources/neighbourhood.tres`: the serialized `MapDefinition` produced by
  `MapDefinition.create_fictional_neighbourhood()`. This is the actual data
  file the game and its tests load; the factory method exists so it can be
  regenerated if it is ever lost, but the `.tres` file, not the method, is
  the contract other parts and the tests read.
- `tests/run_tests.gd`: the shared headless test harness (`extends
  SceneTree`), run as `--headless --path . --script res://tests/run_tests.gd`.
  Discovers every `res://tests/test_*.gd` file except the shared base class
  by scanning the directory with `DirAccess`, instantiates each, calls every
  `test_*` method, prints one `PASS`/`FAIL` line per method, then a summary
  line, and exits 0 only when every assertion in every method passed
  (nonzero otherwise). All later parts add test files here; none should
  need to change this file.
- `tests/test_case.gd`: shared base class (`extends RefCounted`, no
  `class_name`; test files `extends "res://tests/test_case.gd"`) providing
  `assert_true`, `assert_false`, `assert_eq`, `assert_almost_eq`. Each
  helper records a `{passed, message}` entry rather than raising, so one
  failing assertion does not hide the rest of a test method's checks.
- `tests/test_map_definition.gd`: 6 test methods covering every hydrant and
  incident candidate being within its nearest road's half-width plus a
  20-unit kerb allowance; every road reachable from whichever road the
  station spawn sits on, via a flood fill over a road-touches-road graph
  built from `Geometry2D.segment_intersects_segment` plus a closest-points
  fallback for T-junctions; every id (roads, buildings, hydrants, incident
  candidates) unique and non-empty; every incident candidate's `building_id`
  naming a real building; and the minimum counts (>=3 hydrants, >=3 incident
  candidates, one hydrant within 300 units of the station spawn).

### Map Dimensions and Road Width

`world_bounds` is `Rect2(0, 0, 1400, 1000)`. The neighborhood is a 3x3 grid
of named streets (Ash/Birch/Cedar Streets running east-west at y=150/500/850,
Elm/Fir/Grove Avenues running north-south at x=200/700/1200), each spanning
the full grid so every horizontal road crosses every vertical one and the
whole network is one connected graph with real intersections and multiple
routes between any two points. Four interior blocks each hold two buildings,
for 8 buildings total, 4 of them marked as incident candidates (`b_a1`,
`b_b2`, `b_c2`, `b_d1`) - above the minimum of 3. 4 hydrants are placed near
roads, one (`h_station`, at distance ~130 units) close to the station spawn.

**Road width is 140 world units (kerb to kerb).** GameBalance's truck is
roughly 90 long and 40 wide with a top forward speed of 250 units/second.
140 gives 100 units of clearance beyond the truck's own width (140 - 40),
i.e. the truck could sit sideways across the road and still have room on
both sides, which is deliberately generous: at arcade top-down speeds a
player correcting a bad line into a turn needs room to be sloppy without
clipping a kerb, and the handoff is explicit that road geometry should be
tuned to fit the truck, not the other way round. Buildings are set back at
least 90 units from every road centerline they face (70 for the road's own
half-width plus a 20-unit sidewalk margin), which was the single most
error-prone part of laying the map out by hand: an early draft set the
setback to exactly 90 and then put building edges (not a separate sidewalk
gap) at that distance, which left every incident candidate's marker over 90
units from its road and failing the adjacency test until the markers were
moved into the gap between the sidewalk and the building instead of onto
the building's own wall.

At 250 units/second the map's ~1720-unit diagonal is crossable in well
under 10 seconds in a straight line, and a realistic multi-turn drive across
several blocks is still well under a minute, comfortably inside the "three
calls in roughly five minutes" target.

### Verification Performed

All commands run from the project root with the console executable; exit
codes are real, captured immediately after each command:

- `--headless --path . --import` -> exit 0, no parse errors.
- `--headless --path . --quit` -> exit 0, printed Part 1's confirmation line.
- `--headless --path . --check-only --script res://scripts/MapDefinition.gd`,
  same for `MapBuilder.gd`, `tests/test_case.gd`, `tests/test_map_definition.gd`
  and `tests/run_tests.gd` -> all exit 0, no parse errors (global class names
  only resolve after an `--import` pass has populated the class cache; a
  `--check-only` run before the first `--import` fails with "Identifier not
  found: MapDefinition" even inside MapDefinition.gd's own file, which is
  worth knowing if this comes up again).
- `--headless --path . --script res://tests/run_tests.gd` -> exit 0, all 6
  test methods (29 assertions) PASS.
- A temporary test file with one deliberately-false assertion was added,
  the runner was rerun (exit 1, that one method printed FAIL with its
  message, summary line read "6 passed, 1 failed"), then the file was
  removed and the runner rerun again (back to exit 0, "6 passed, 0 failed").
- The neighborhood was temporarily regenerated with one extra road far from
  the grid (no shared intersection with anything). The connectivity test
  failed by name ("road r_orphan is not reachable from the station..."),
  the runner exited 1, and the map was then regenerated clean again and
  reverified at exit 0. This is the same mechanism the checklist relies on:
  a checker that cannot be observed to fail is not trusted here.
- A one-off runtime smoke test instantiated a real `MapBuilder`, called
  `build()` with the neighborhood, and checked its scene tree directly:
  8 building `StaticBody2D` nodes on layer 1/mask 0, 4 edge wall bodies on
  layer 1/mask 0, and all six public getters returning data matching the
  source `MapDefinition`, including `get_building_polygon` for a known id
  and an empty result for an unknown one. Exit 0. This script was temporary
  and was deleted after use; it is not part of the delivered file set.

### Known Issues / Not Done in This Part

- Nothing wires `MapDefinition`/`MapBuilder` into `scenes/Main.tscn` yet.
  The map can be built and inspected via a script, but the game does not
  yet show it when run. That is explicitly Part 3's job (truck, camera,
  and the real Main/GameSession orchestration).
- Hydrant and incident-candidate markers are decorative only (no
  `Area2D`/collision), by design: Part 4 owns hydrant (layer 4) and fire
  target (layer 3) interaction areas and will build its own nodes for
  those, using `get_hydrant_definitions()`, `get_incident_candidates()` and
  `get_building_polygon()` from `MapBuilder`.
- No minimap or off-screen incident indicator exists yet (handoff §7 asks
  for one); that belongs with Part 3/4's HUD and dispatch work, since it
  needs the truck and the active incident to point at, neither of which
  exist yet.

## Next Milestone

Part 3: TruckController and the real Main/GameSession scene, per handoff
§4 and §8. Spawn the truck at `MapBuilder.get_station_spawn_position()`/
`get_station_spawn_heading()`, drive it against the layer-1 collision this
part built, and bound the camera to `get_world_bounds()`.

## Part 3: Truck, Camera, Collision

Added `scripts/TruckController.gd`, `scripts/TruckBody.gd`, `scripts/FollowCamera.gd`,
`scripts/PauseMenu.gd`, `scenes/Truck.tscn`, `scenes/PauseMenu.tscn`, a rewritten
`scenes/Main.tscn` and `scripts/Main.gd`, plus `tests/test_truck_damage.gd` and a second
runner, `tests/run_physics_tests.gd`.

Orientation convention: local +X is forward, so `rotation` 0 points right. Steering is
heading relative, has no authority at a standstill, reaches full authority at 40 units/s,
is reduced again toward top speed, and reverses its sense when the truck is backing up.
There is no lateral slip: the truck goes where it is pointed, which is a deliberate arcade
choice for predictability.

The camera is a sibling of the truck, not a child of it. Parenting it would inherit the
truck's rotation and spin the world, so following by position is what keeps it north up.
It is bounded to the map's world bounds and leads slightly in the direction of travel.

### The bug the unit tests could not see

The first version of `TruckController` trusted `move_and_slide()` to write the blocked
result back into `velocity`. In this build it does not. Driving flat out into a wall left
`velocity` reading 250 units/second frame after frame while `get_real_velocity()` correctly
read zero, so the drive code believed the truck was still doing 250 into a wall it had
already stopped against, and the crash re-fired every time the 0.5 second contact cooldown
expired. Ten full speed impacts, engine destroyed, from one collision. Every unit test
passed throughout, because they exercise the damage rule and never step Godot's physics.

The fix is one line: `velocity = get_real_velocity()` after `move_and_slide()`, so the
controller adopts the motion that actually happened. `tests/run_physics_tests.gd` exists to
cover this class of defect and was proven by removing the fix again: it reports "got 10"
and exits 1, while `tests/run_tests.gd` stays green at exit 0.

`collision_damage_scale` was lowered from 0.6 to 0.3 after measuring a real crash. A wall
strike at top speed registers about 200 units/second into the normal, which at 0.6 cost 85
of the 100 starting condition and made a single mistake effectively fatal. At 0.3 it costs
about 42.

### Two runners, two commands

    godot --headless --path . --script res://tests/run_tests.gd
    godot --headless --path . --script res://tests/run_physics_tests.gd

The first is fast and covers rules. The second boots the real main scene and steps physics,
so it is slower and covers integration. Both exit nonzero on any failure.

Next milestone: Part 4, water, fire and hydrants.
