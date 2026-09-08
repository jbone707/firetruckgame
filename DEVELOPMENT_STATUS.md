# Fire Truck Game Development Status

## Godot Version

`4.7.2.stable.official.ed1daf0bf`, confirmed by running the console
executable with `--version`.

## Current File Inventory

Rewritten from the actual tree in Milestone 8 Part 4. It had said `Main.tscn`
was a placeholder that printed a version line and nothing else, which stopped
being true in Milestone 2 and had been carried, wrong, through six milestones.
Line counts are given because they are the honest measure of where the weight
of this project sits, and two files carrying a third of it is a fact a reader
should have before they open one.

### Project and documents

- `project.godot`: Compatibility renderer, 1280x720 default viewport,
  `canvas_items` stretch with `expand`, main scene `scenes/Main.tscn`,
  `GameBalance` autoload, and the input map: drive, steer, handbrake, spray,
  siren, hydrant hookup, pause, return to station, and `cycle_zoom` on Z.
- `README.md`: how James launches it, the controls, and the two test commands.
- `DESIGN.md`: what the game is and how it plays, including the rules for how a
  house looks, how a street is named, and how the map meets its edge.
- `DEVELOPMENT_STATUS.md`: this file. One section per milestone, each ending in
  what was verified and what is known to be wrong.
- `ATTRIBUTION.md`: the OpenStreetMap credit and licence, and what in the
  Windsor map is real and what is invented.
- `.gitattributes`, `.gitignore`.

### Game scripts (`scripts/`, 6,372 lines)

The map, which is over half of it:

- `MapBuilder.gd` (1,151): builds the whole playable scene from a
  `MapDefinition`. Roads, sidewalks, kerbs, fences, yards, the one building
  renderer, driveways, street labels, the map-edge barricades and dead end
  signs, the ground outside the map, and the boundary walls. Owns the draw
  order.
- `MapValidator.gd` (492): the eight rules any map must satisfy. Connectivity
  from the spawn, features at a reachable kerb, minimum road width, roads
  overlapping only at junctions, buildings off the road, no two buildings
  overlapping, nothing running off the map, and land that derives as solid.
- `MapGeometry.gd` (364): the polygon regions everything is drawn and collided
  from, derived from the road network alone. Road slabs, junction fills, and
  the hole-safe subtraction that gives the kerb and fence lines.
- `MapDefinition.gd` (359): the data-only description of a neighbourhood, plus
  the hand-built fictional one.
- `RoadGraph.gd` (316): the road network as an actual graph, with route lengths
  along the pavement.
- `MapCatalogue.gd` (70): which maps exist and where they live.

The game:

- `Main.gd` (536): scene orchestration and the only place that reads the
  keyboard and mouse.
- `GameUI.gd` (694): the HUD, home menu, map select, Data and Credits, results
  and shop, all built in code.
- `FireIncident.gd` (302), `WaterSystem.gd` (315), `Hydrant.gd` (245): the fire,
  the tank and turret, and refilling.
- `TruckController.gd` (257), `TruckBody.gd` (104): driving and damage.
- `GameSession.gd` (217), `SaveManager.gd` (212), `DispatchManager.gd` (206):
  the shift, the save file, and sequential calls.
- `FollowCamera.gd` (177): north-up follow camera, zoom levels, overscan, shake.
- `GameBalance.gd` (244): every tuning value, each marked as specified by the
  handoff or invented.
- `IncidentIndicator.gd` (80), `PauseMenu.gd` (31).

### Scenes (`scenes/`)

`Main.tscn` (the real orchestrator, not a placeholder), `Truck.tscn`,
`PauseMenu.tscn`.

### Resources and data

- `resources/neighbourhood.tres`: Elm Grove, the fictional map. 4,000 x 3,000.
- `resources/windsor_shadetree.tres`: the Windsor import. 7,820 x 6,140.
- `data/source/`: the one-time Overpass response and the query that produced it,
  committed verbatim. The game never reads these.

### Tests (`tests/`, 4,562 lines)

- `run_tests.gd` (128): the fast headless runner. Discovers `test_*.gd`.
- `run_physics_tests.gd` (1,474): the slow runner. Boots the real scene and
  drives it. 112 checks.
- Eleven test files: water and hydrants (650), session and save (620), osm
  import (386), map definition (329), street labels (185), map geometry (174),
  building style (164), first call (148), truck damage (145), incident
  indicator (125), and the shared base class (34).

### Tools (`tools/`)

- `import_osm.gd` (1,609): turns the committed extract into
  `windsor_shadetree.tres`. Deterministic; two runs give a byte-identical file.
- `validate_map.gd` (76): runs `MapValidator` over both maps.
- `measure_scale.gd` (121): reports road width, house width and junction spacing
  in truck lengths, which is how the scale was chosen.
- `regenerate_map.gd` (25): rewrites the fictional map from `MapDefinition`.

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
| `collision_damage_scale` = 0.25 | §4 Collision | Invented; 0.6 to 0.3 in Part 3, then to 0.25 in Milestone 4 Part 2 once the impact speed was read correctly |
| `collision_contact_cooldown` = 0.5 | §4 Collision | Invented |
| `tank_capacity` = 100.0 | §5 Water | Specified |
| `spray_flow_rate` = 10.0 | §5 Water | Specified |
| `stream_range` = 120.0 | §5 Water | Specified |
| `fire_damage_per_second` = 20.0 | §5 Water | Specified |
| `fire_starting_health` = 100.0 | §5 Water | Specified |
| `suppression_per_water_unit` = 2.0 | §5 Water | Derived from specified values (`fire_damage_per_second / spray_flow_rate`) |
| `fire_escalation_duration` = 45.0 | §5 Fire | Specified as 120 for the old map; now the BASE, with travel paid separately (Milestone 4 Part 1) |
| `escalation_travel_speed` = 110.0 | §5 Fire | Invented in Milestone 4 Part 1; half the measured 220 u/s driving speed |
| `escalation_travel_allowance_max` = 150.0 | §5 Fire | Invented in Milestone 4 Part 1 at 90.0; raised to 150.0 in Milestone 5 Part 1 for the far bigger Windsor map |
| `hydrant_hookup_time` = 1.0 | §6 Hydrants | Specified as 2.0; halved in Milestone 2 Part 4 after James's playtest |
| `hydrant_refill_rate` = 50.0 | §6 Hydrants | Specified as 25.0; doubled in Milestone 2 Part 4 after James's playtest |
| `hydrant_max_hookup_speed` = 25.0 | §6 Hydrants | Invented; raised from 15 in Milestone 3 Part 1 so a slow creep counts as stopped |
| `hydrant_interaction_radius` = 160.0 | §6 Hydrants | Invented; raised from 48 in Milestone 3 Part 1 AND re-measured to the truck's bodywork rather than its centre |
| `calls_per_shift` = 3 | §3 Session | Specified |
| `credits_per_call` = 100 | §3 Session | Specified |
| `shift_completion_bonus` = 50 | §3 Session | Specified |
| `tank_upgrade_cost` = 200 | §3 Session | Specified |
| `tank_upgrade_multiplier` = 1.25 | §3 Session | Specified |
| `truck_starting_condition` = 100.0 | §3 Session | Invented |

This table is kept current rather than left as a record of what Part 1 first
wrote, so `GameBalance.gd` and this table agree. Where a value has moved, the
Source column says when and why. `GameBalance.gd` itself is the authority.

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

## Part 4: Water, Fire, Hydrants

Added `scripts/WaterSystem.gd`, `scripts/FireIncident.gd`, `scripts/Hydrant.gd`,
`tests/test_water_and_hydrant.gd`, and three targeting checks in
`tests/run_physics_tests.gd`. `MapBuilder` no longer draws its own hydrant and incident
dots, because hydrants are now real nodes with an interaction radius and only the
dispatched call should be marked.

The turret is mounted on the truck and aims by world position, set from Main with
`get_global_mouse_position()`, which already accounts for the canvas transform and so
stays correct under the moving camera.

A burning building would normally shield the fire inside it, since the building's own
collision is on the same layer that occludes the stream. `FireIncident` grows its hittable
area 14 units past the building outline, so the fire's edge sits in front of the wall and
the call can actually be cleared from the street. `run_physics_tests.gd` covers this, plus
occlusion by an obstacle and the stream's range limit, all against real physics.

### Two more bugs that only physics could show

Parking the truck exactly on an incident marker put its 90x40 body inside the building
wall. The depenetration shove that followed was being adopted wholesale by Part 3's
`velocity = get_real_velocity()` line, and the truck flew off across the map under its own
steam. `TruckController` now clamps the adopted velocity so a move can never leave the
truck faster than it entered: being pushed out of geometry stops it instead of firing it
away.

The occlusion check itself was wrong before the code was. Its blocker wall is a tall thin
box whose long axis is local Y, so rotating it by the aim angle plus ninety degrees, which
is the intuitive thing to write, left it parallel to the stream and blocking nothing. The
rotation is the aim angle itself.

Both checkers were proven by deliberate failure: removing the world_static bit from the
stream's query mask makes the occlusion check report health 80.0 and exit 1.

Next milestone: Part 5, session, dispatch, HUD, shop and save.

## Part 5: Session, Dispatch, HUD, Shop, Save

Added `scripts/GameSession.gd`, `scripts/DispatchManager.gd`, `scripts/SaveManager.gd`,
`scripts/GameUI.gd` and `tests/test_session_and_save.gd`, and wired all of it through
`scripts/Main.gd`.

`GameSession` runs MENU to PLAYING to RESULTS to SHOP. Pause is deliberately not a state:
it is the engine's own pause, so pausing cannot desync the state machine. Rewards are
guarded twice over. `FireIncident` guards its terminal transition, and `GameSession` keeps
a set of incident ids it has already paid for plus a one-shot bonus flag, both cleared only
by `start_shift()`. Credits are written to disk the moment they are earned, so a shift that
later fails cannot take them back.

`SaveManager` writes to a temporary file and renames it over the real one, so a crash
mid-write leaves the previous save intact. On load it validates the schema version, that
credits are a whole nonnegative number, and that the upgrade flag is a boolean; anything
else falls back to defaults with a diagnostic rather than an error. JSON has no integer
type, so a fractional credit balance is rejected rather than silently truncated.

The HUD is built in code so every anchor and container is explicit in one file. Nothing is
placed at a fixed pixel, and no state is carried by colour alone: every bar has a value
beside it and every prompt is a sentence.

### A hole in the test harness, found by falling into it

`test_session_and_save.gd` first shipped with a parse error. The suite printed the error
and still exited 0, because a file that fails to parse comes back from `load()` as a
GDScript object that simply cannot be instantiated, and the runner skipped it in silence. A
whole file of checks could stop existing with nothing to say so, which is the one thing a
runner must never do. `run_tests.gd` now fails on a script it cannot instantiate.

Next milestone: Part 6, verification, self-review and documents.

## Part 6: Verification and Self-Review

### What was run, and what it returned

    godot --headless --path . --import                              exit 0
    godot --headless --path . --quit-after 300                      exit 0
    godot --headless --path . --script res://tests/run_tests.gd     exit 0
        4 test files, 28 test methods, 255 assertions, 0 failed, no leaks
    godot --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        16 checks, 0 failed

### Checkers proven by deliberate failure

A check that has never failed is a hope, not a check. Three were broken on purpose
and watched to fail, then restored:

1. **The velocity reconciliation in `TruckController`.** Commenting out
   `velocity = get_real_velocity()` makes the physics runner report "got 10" damage
   events for one wall crash and exit 1. The unit suite stays green at exit 0
   throughout, which is the honest measure of what each runner covers.
2. **Stream occlusion.** Dropping the world_static bit from the query mask in
   `WaterSystem._query_stream()` makes the obstacle check report health 80.0 and
   exit 1.
3. **The reward guard.** Removing the `_rewarded_incidents` check in `GameSession`
   makes one call pay 350 instead of 100 and the shift advance three calls instead
   of one, and the unit suite exits 1.

### Handoff section 10 self-review

- **Input focus.** The pause menu and all three UI panels move focus to their first
  control when shown, so every screen is keyboard operable. Fixed in this part; the
  panels had no focus handling before.
- **Mouse to world under a moving camera.** Aim uses `get_global_mouse_position()`,
  which accounts for the canvas transform. Reading the raw viewport position would
  have aimed at a fixed screen point the moment the truck moved.
- **Collision masks.** Layer 1 world_static (buildings and edge walls, blocks the
  truck and occludes the stream), layer 2 truck, layer 3 fire_target, layer 4
  hydrant. Roads, sidewalks and labels carry no collision shape at all.
- **Obstacle occlusion.** Covered by a physics check and proven by deliberate
  failure.
- **Terminal state reward guards.** Guarded in two places and proven by deliberate
  failure.
- **Restart cleanup.** `start_shift()` clears incidents, connections, cooldowns,
  the destroyed guard, the reward set and the bonus flag, and resets the truck and
  tank in place rather than making new ones. Covered by a test.
- **Save validation.** Six malformed cases are each rejected with a diagnostic and
  safe defaults.
- **Refill and spray exclusivity.** Refill wins, enforced inside `WaterSystem` and
  again at the input layer.

### What could NOT be observed, and is James's playtest list

There is no way to watch this run from here. The headless checks prove rules and
integration, not feel, and no screenshot of the game was ever taken. These six are
from handoff section 10 and are yours:

1. Drive around a block, brake and reverse, then hit a building gently and hard.
2. Spray a fire, miss deliberately, and watch both fire health and water.
3. Run dry, reach a hydrant, refill, and interrupt the hookup by driving off.
4. Complete three calls, get one completion bonus, and buy the tank upgrade.
5. Start again, confirm the bigger tank, fail deliberately after banking a call,
   then restart the application and confirm the credits survived.
6. Pause during spraying and escalation, and resize the window to check the HUD.

### Windows export

Skipped, as instructed. There is no `export_templates` directory under
`%APPDATA%\Godot`, so no 4.7.2 templates are installed and nothing was installed to
change that. Editor play is unaffected.

### Known issues and open questions

- Driving feel is untested by a human. The invented values in `GameBalance.gd` are
  first guesses and are the first thing to change after a playtest.
- There is no audio at all. The siren toggles the warning lights and a HUD line;
  no sound is produced, because no audio assets are permitted in this build and
  synthesising a siren was out of scope.
- Escalation is a flat 120 seconds and is not slowed by effective suppression,
  which handoff section 5 asks for deliberately: no hidden rules in this version.
- The off-screen call arrow is a direction indicator, not a minimap. Handoff
  section 7 allows either.

Next milestone, not started and not to be started automatically: importing a small
real Windsor neighbourhood through `MapDefinition`, validating drivable
connectivity and hydrant access, then basic traffic and signals.

## Milestone 2: Playtest Fixes (Arrow, Scale, Roads, Feedback, Hydrants)

James played the first build. The loop worked end to end: three calls cleared,
shift bonus paid, tank upgrade bought and applied, driving feel acceptable for
now. Six problems came back, and this milestone is those six. Its parts are
numbered 0 to 5 and are separate from the Parts 1 to 6 above, which built the
first playable.

### Part 0: The call arrow was pointing at the corner of the map

Root cause, and it was none of the three that were suspected. The truck to
incident vector was never rotated by anything, the arrow is a child of the HUD
and not of the truck, and the glyph's forward and the code's forward already
agreed. What was wrong was the incident's own position: `FireIncident.setup()`
took the burning building's outline in WORLD coordinates and hung it off the node
as a child `CollisionPolygon2D`, while `_draw()` converted its world-space flame
seeds back with `to_local()`. The fire therefore drew and collided in exactly the
right place while the node itself stood at `(0, 0)`, for every call on the map.
Everything that asked the incident where it was got the neighbourhood's
north-west corner, so the arrow pointed there and, because that corner is off
screen nearly everywhere, it never hid either. Both symptoms, one cause.

The incident node now stands at its own centroid with a local-space shape. Screen
geometry moved out into `scripts/IncidentIndicator.gd`, which takes no rotation of
any kind and says so in its own comments. The arrow shows only when the incident
is outside the visible rect by a 24 unit margin, and sits on the screen edge along
the line from the middle of the screen to the fire. On screen, a chevron over the
building is the only indicator.

### Part 1: Scale

Measured before anything was changed: at zoom 1 the 1280x720 viewport showed 91%
of the old 1400x1000 map's width and 72% of its height, and a 140 unit road was
11% of the screen. The player was looking at nearly the whole neighbourhood at
once, which is what made the streets read as lines.

| | Before | After |
|---|---|---|
| World bounds | 1400 x 1000 | 4000 x 3000 |
| Road width, kerb to kerb | 140 | 280 |
| Camera zoom | 1.0 | 0.9 |
| Road as a share of screen width | 10.9% | 19.7% |
| Map width visible at once | 91.4% | 35.6% |
| Roads / blocks / houses / hydrants / candidates | 6 / 0 / 8 / 4 / 4 | 8 / 25 / 36 / 7 / 6 |

`FollowCamera.LOOK_AHEAD_DISTANCE` went from 90 to 220 to match, which is a camera
value, not a physics one. **No `GameBalance.gd` driving value was changed by
Part 1.** The wider road makes the existing turning radius easier to live with
rather than harder, and driving feel is deliberately untouched until James has
played the rescaled map.

### Part 1: Blocks, and a new physics layer

Every block is filled and solid, so the only drivable surface is road. Blocks tile
the entire map, edge verges included: the roads now run to the boundary, so the
land is exactly the rectangles between them and there is no ragged strip to escape
onto. The layout is generated from the road grid in
`MapDefinition.create_fictional_neighbourhood()` rather than typed coordinate by
coordinate, and `tools/regenerate_map.gd` rewrites `resources/neighbourhood.tres`
from it. The `.tres` file, not the factory, is still the contract everything reads.

Block collision sits on **layer 5, `world_lot`**, and the truck's mask became
`0b10001`, layers 1 and 5. Layer 5 is deliberately absent from `WaterSystem`'s
stream mask. Without that split, filling the blocks in would have made every fire
on the map unreachable from the street it faces, because the sidewalk in front of
a house would have blocked the stream exactly as the house does.

Physics layers now: 1 `world_static`, 2 `truck`, 3 `fire_target`, 4 `hydrant`,
5 `world_lot`. They are named in `project.godot` as of this milestone.

`MapDefinition.schema_version` is 2, and the resource has a new `blocks` field:
each entry `{id, rect, yard_color}`, running kerb to kerb.

### Part 2: Road rendering

The optical illusion at every intersection came from each road being its own
`Line2D` with round joints and caps: two of them crossing put a second, subtly
different tone over the junction, so crossings read as raised or sunken boxes.
Roads are now opaque `Polygon2D` slabs in one warm near-black asphalt, with the
overlap of every pair of road rectangles filled again in the identical colour and
added last, so the sixteen junctions are one flat surface with nothing to see a
seam in. Junctions are found from the geometry rather than from the grid
constants, so a change to the layout does not need a change here.

Draw order, bottom to top, every drawn node setting exactly one: `Z_ROAD` 0,
`Z_ROAD_MARKING` 1, `Z_SIDEWALK` 2, `Z_YARD` 3, `Z_KERB` 4, `Z_BUILDING_BODY` 5,
`Z_BUILDING_ROOF` 6, `Z_LABEL` 7, `Z_MARKER` 8.

Colours: asphalt `(0.14, 0.13, 0.125)`, kerb `(0.90, 0.87, 0.79)`, centre line
`(0.82, 0.77, 0.52)`, sidewalk `(0.74, 0.72, 0.67)`, yards from the map data. Kerb
lines are the blocks' own outlines and so are already broken at junctions; the
dashed centre line is broken there explicitly. Crosswalk bars and corner street
labels were offered as optional and skipped.

### Part 3: Suppression feedback

`WaterSystem.is_suppressing()` is true only on a tick that actually took health
off a fire. It reads the amount the fire says it absorbed, not the amount the
stream requested, so it is false on a miss, false against a wall, false at an
empty tank, and false against a fire that is already out. All three signals hang
off it: the steam burst instead of the plain splash, the flames going out one at
a time as health falls, with a health bar and percentage over the active call,
and the HUD line "Knocking it down". No audio in this build.

### Part 4: Hydrant timing

| Value | Was | Now |
|---|---|---|
| `hydrant_hookup_time` | 2.0 | 1.0 |
| `hydrant_refill_rate` | 25.0 | 50.0 |

A full 100 unit tank is now about three seconds from hookup instead of six. Both
values are in `GameBalance.gd` and nowhere else. The nearly-stationary rule, the
cancel-on-move rule and refill's priority over spraying are untouched, and the
tests that cover them read their counts from `GameBalance`, so they went on
proving the rules across the change.

### Verification Performed

Every command below was run from the project root with the console executable and
the exit code captured immediately after it:

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 300                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        5 test files, 37 test methods, 356 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        47 checks, 0 failed

New checks: `tests/test_incident_indicator.gd`, 5 methods on the arrow geometry;
three methods in `tests/test_water_and_hydrant.gd` on the suppression flag and one
on the refill timing target; and three physics checks, two on the arrow in the
real scene and one on the block fill.

Checkers proven by deliberate failure in this milestone:

1. **The arrow.** Reintroducing a truck-rotation term, in `IncidentIndicator` for
   the unit path and in `Main._incident_indicator_state` for the scene path, fails
   1 unit method and 12 physics checks; both runners exit 1.
2. **The block fill.** Dropping layer 5 from the truck's collision mask lets four
   seconds of throttle carry the truck 720 units into the block opposite the
   station instead of stopping it at the kerb, and the physics runner exits 1.
   Re-proven at the end of the milestone as well as when it was written.
3. **The suppression flag.** Setting it from the request rather than from the
   fire's answer makes the already-out case FAIL and the unit runner exit 1.
4. **The refill timing.** Putting 2.0 and 25.0 back makes the timing test FAIL
   with "calculated 6.00" and the unit runner exit 1.

One existing check had to be corrected rather than merely re-run: the wall crash
check used to aim due east from the station at the map edge, which at the new
scale meets a kerb 95 units away. It drives north up Elm Avenue to the real edge
wall now.

### Known Issues

- Driving feel is still untested by a human, and the map is three times larger, so
  crossing it takes proportionally longer. That is the first thing to judge in the
  next playtest, and the reason no driving value was touched here.
- Escalation is still a flat 120 seconds and is not slowed by suppression, per
  handoff section 5. A call at the far corner of the bigger map is a longer drive
  against the same clock, and nothing has measured whether 120 seconds is still
  comfortable.
- No audio at all, as instructed.
- Nothing in this milestone was ever seen running. Every claim above comes from a
  headless exit code; the look of the roads, the steam and the arrow is James's to
  judge.
- ~~A hydrant sits 10 units inside the kerb, and the sidewalk is now solid, so
  the truck's nearest approach is about 30 units driving alongside it,
  comfortably inside the 48 unit interaction radius. A head-on approach would be
  about 55 and would not register.~~ Fixed in Milestone 3 Part 1, and it was
  exactly as predicted: a nose-in stop measured 55.0 from the centre against a
  48 unit radius. Kept here struck through rather than deleted, because it is
  the one Known Issue in this file that was written from arithmetic before
  anyone hit it in play, and it was right.
- `MapBuilder._build_hydrant_marker` and `_build_incident_marker` are still unused
  by `build()`, as they have been since Part 4 of the first build.

### What James Should Look At Next

1. Drive a full block at speed. Does the new scale read, and does the truck still
   feel right at 250 units/second on a 280 unit road, or does it now feel slow?
2. Take a corner hard. The turning radius is unchanged and the road is twice as
   wide, so this should be easier, not harder.
3. Try to leave the road anywhere: between two houses, across a back garden, onto
   the verge at the map's edge. Nothing should let you off the asphalt.
4. Stand at an intersection and look for the old illusion. Then follow a kerb line
   and a centre line up to a junction and watch where they stop.
5. Get sent to a call across the map. Watch the arrow the whole way in, and watch
   the moment it hands over to the marker over the building.
6. Spray the fire, then deliberately spray the wall beside it. The steam, the
   flames going out, the bar and the HUD line should all agree, and all four
   should stop the instant you miss.
7. Run dry and refill. Three seconds should feel like a decision, not a wait.

## Milestone 3: Hydrant Tolerance and Driveable Sidewalks

James's second playtest of the rescaled map. Speed of 250 feels right, the call
arrow works, the engine-to-street scale is right and the road art is fine. Two
things came back: hydrants had too tight a tolerance and filling up was not fun,
and sidewalks should be driveable. Its parts are numbered 1 to 3.

### Part 1: The hydrant approach, measured

Taken against the real map before anything was changed, with the station hydrant
10 units inside the kerb and the rule measuring from the hydrant to the truck's
CENTRE with a 48 unit radius. "Bodywork" is the distance to the nearest point of
the truck's 90 x 40 collision rectangle.

| Approach | To the centre | To the bodywork | Old rule |
|---|---|---|---|
| Nose in, square to the kerb | 55.0 | 10.0 | out of range |
| Angled 45 degrees | 62.8 | 39.7 | out of range |
| Alongside, hard against the kerb | 30.1 | 10.1 | in range |
| Alongside, a truck length short | 95.1 | 46.3 | out of range |
| Alongside, 160 units of street past it | 162.9 | 115.4 | out of range |
| Stopped in the far lane of a 280 unit road | 220.0 | 200.0 | out of range |

Exactly one way of parking worked, and which one it was depended entirely on
which way the truck happened to be pointing. The same bumper in the same place
reads 45 units further from the centre nose in than alongside, because the truck
is 90 long and 40 wide. That is the whole of it.

Three changes, all in `GameBalance.gd`:

| Value | Was | Now |
|---|---|---|
| Range measured from | the truck's centre | the nearest point of its body |
| `hydrant_interaction_radius` | 48.0 | 160.0 |
| `hydrant_max_hookup_speed` | 15.0 | 25.0 |

160 comes from the table above rather than from taste. Against a hydrant moved
out to the kerb face, alongside is 0, nose in 0, a 45 degree sprawl about 30,
stopping a truck length short 46, and overshooting by 160 units of street 115:
all comfortably inside. The far lane is 200 and deliberately stays outside,
which is the one thing this rule should still ask for, namely pull over to the
hydrant's own side of the street.

Hydrants also moved out to the kerb face. `MapDefinition` grew a separate
`HYDRANT_STANDOFF` of 0, leaving the incident markers' `KERB_STANDOFF` at 10, so
the two are no longer tied together, and the map resource was regenerated.

`Hydrant.distance_to_box()` is the geometry: nearest point of an oriented
rectangle to a point, static and free of node state, so the rule is checkable
with arithmetic rather than by standing up a physics space. `evaluate()` now
takes the truck's transform and half extents instead of a position, and
`TruckController.get_collision_half_extents()` reads the shape off `Truck.tscn`
rather than restating 90 x 40 as a constant that could quietly go stale.

Readability, all in `Hydrant._draw()`: the interaction ring is drawn on the
ground and carries its state in line style as well as in colour, dashed while
the truck's bodywork is outside it and solid the moment it is inside, so the
player can see they are close enough before touching E. While hooked up, a hose
runs from the hydrant to the nearest point of the truck's bodywork, which is the
same point the range rule measures to, so the line drawn on screen is literally
the distance the rule used. Holding E is still the trigger, per handoff section
6; nothing auto-hooks.

### Part 2: Driveable sidewalks

A block's collision polygon is its garden rectangle now, not the whole block, so
the 34 unit concrete band around every block is driveable ground. Mounting the
kerb costs nothing in this build: no speed penalty, no damage. The gardens
behind their fences stay solid on `world_lot`, and the houses on `world_static`.

The `world_lot` layer split from Milestone 2 is untouched: the stream still
passes over a lot and is still stopped by a house, which is what keeps every
fire reachable from the street it faces. Only the sidewalk came back out of it.

A fence line is drawn on the garden boundary. Without it the kerb would be the
only edge drawn on a block, and the kerb is no longer where anything stops, so
the player would have had to find the real edge by hitting it.

Draw order gains `Z_FENCE` at 5, between the kerb and the buildings: `Z_ROAD` 0,
`Z_ROAD_MARKING` 1, `Z_SIDEWALK` 2, `Z_YARD` 3, `Z_KERB` 4, `Z_FENCE` 5,
`Z_BUILDING_BODY` 6, `Z_BUILDING_ROOF` 7, `Z_LABEL` 8, `Z_MARKER` 9.

### Verification Performed

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 300                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        5 test files, 41 test methods, 373 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        54 checks, 0 failed

New checks: four unit methods on the edge-distance rule, the five approaches,
the creep allowance and the hose; and one physics check that drives at the
station hydrant nose in, alongside, a truck length short and at a sloppy angle,
and confirms holding E there actually starts the refill.

Checkers proven by deliberate failure:

1. **The hydrant approach.** Restoring the whole original condition, the centre
   rule and the 48 unit radius and the hydrant back inside the kerb, fails the
   nose-in check at "10.0 from the bodywork, 55.0 from the centre" along with
   three of the other approaches, and the runner exits 1.
   Worth recording honestly: restoring ONLY the 48 unit centre rule does not
   fail the nose-in check, because moving the hydrant out to the kerb face
   brings a nose-in stop to 45.0 from the centre, three units inside the old
   radius. The move alone would have scraped that one approach through; it is
   the edge-distance rule that makes the other four work.
2. **The driveable sidewalk.** Putting the block's collision polygon back to the
   whole block stops the truck's nose dead on 540.0, the kerb line, the
   kerb-mounting check FAILs, and the runner exits 1.

The empty-lot check was rewritten rather than renumbered. It measured the
truck's CENTRE against the kerb, and with a driveable sidewalk that assertion
still passed for the wrong reason: the centre stops at 529, short of the 540
kerb, because the nose is against the fence. It measures at the bumper now and
makes two claims instead of one, that the nose crosses the kerb at 540 and that
it stops at the fence at 574. Measured: nose 574.0 exactly, centre 529.0.

### Known Issues

- Nothing in this milestone was ever seen running. Every claim above is a
  headless exit code or a measured number. Whether pulling up to a hydrant now
  FEELS forgiving is James's to judge, and it is the specific thing to test.
- Driving on the sidewalk is free, which is only reasonable while there is
  nobody on it. Pedestrians are on the roadmap in `DESIGN.md`, and the note
  there says plainly that the free ride ends when they arrive.
- The truck can now circle a whole block on its sidewalk without touching the
  road. Nothing stops that and nothing punishes it. It may turn out to be a
  shortcut worth closing later; it is not a bug today.
- Escalation is still a flat 120 seconds and is not slowed by suppression, per
  handoff section 5.
- No audio at all, as instructed.

## Milestone 4: Pacing, Damage and Screen Finish

A polish pass on the things James had not hit yet but would on a full shift.
Driving, scale, roads, the arrow, hydrants and sidewalks were all passing after
Milestone 3. Parts are numbered 0 to 4.

### Part 0: The repository has a remote

`origin` is `https://github.com/jbone707/firetruckgame.git`, and `master` tracks
`origin/master`. Before the first push: `.gitignore` still excludes `.godot/`,
`*.tmp` and `export_presets.cfg`; every tracked file is source, documentation or
map data; and the save file lives at `user://fire_truck_game_save.json`, outside
the repository, so no player data can be committed. The push was accepted with
no conflict, so nothing had to be merged or forced.

### Part 1: Shift pacing, measured

Route lengths come from a graph of the road network, Dijkstra between the
sixteen junctions, not straight lines. The times were then DRIVEN in the physics
runner by a waypoint follower rather than estimated from a speed.

| Call | Road route | Driven | Plus the fight |
|---|---|---|---|
| `ic_20_0` | 1705 u | 7.7 s | 15.7 s |
| `ic_02_2` | 3075 u | 13.3 s | 21.3 s |
| `ic_00_1` | 2805 u | 15.2 s | 23.2 s |
| `ic_12_2` | 3905 u | 16.6 s | 24.6 s |
| `ic_11_3` | 3905 u | 18.0 s | 26.0 s |
| `ic_22_1` | 5005 u | 22.4 s | 30.4 s |

Effective door-to-door speed was a consistent 220 units/second. Candidate to
candidate averages 3012 units, about 19 s, worst pair 4850 units. A knock-down
takes 5.0 s with every drop on target and about 8 s realistically, and needs 50
of the tank's 100 units, so one call fits in a tank and a three-call shift needs
exactly one refill, which costs 3.0 s plus the detour (305 to 1865 units to the
nearest hydrant, depending on the call).

**The worst call on the map needs about 30 seconds against a clock of 120.** The
escalation timer could not be lost by anyone who drove towards the fire, and on
a near call it was four times what was needed.

The rule now prices the journey separately:

    escalation limit = fire_escalation_duration + grid distance / escalation_travel_speed

| Value | Was | Now |
|---|---|---|
| `fire_escalation_duration` | 120.0 | 45.0 |
| `escalation_travel_speed` | n/a | 110.0 |
| `escalation_travel_allowance_max` | n/a | 90.0 |

45 covers the fighting: 8 s of suppression, up to 3 s of refill, and margin.
110 is half the measured 220, so the allowance is twice the drive actually being
asked for. The nearest call now gets 60.5 s against 15.7 needed and the furthest
90.5 s against 30.4: tighter than 120 everywhere, still about three times what
the call costs, and proportionate to the journey instead of sized for the worst
case and applied to all. Distance is measured along the grid rather than as a
straight line, because every road here is axis aligned and a driver cannot cut
the corner, and it is measured at dispatch from wherever the truck is.

Nothing is hidden. The HUD still shows a plain countdown; it simply starts
higher for a call further away. Under 30 seconds it grows and reads "Time left
0:28, running out", because colour is never the carrier of state in this HUD and
a player watching the road is not reading a colour anyway.

**A finding that is James's to decide, not CC's.** A whole shift now measures
roughly 90 to 110 seconds of driving and fighting, plus two 2 s confirmation
pauses. The handoff targets "roughly five minutes per shift" while saying not to
prioritise duration over playability. Closing that gap means more calls per
shift, a bigger map, or a slower engine, all of which are mechanics or
difficulty rather than polish, so nothing here attempts it.

### Part 2: Crash damage, and the defect the audit found

Measured by driving into the map's edge wall under throttle from varying run-ups:

| Run-up | Speed | Into normal | Cost |
|---|---|---|---|
| 140 units | 238 | 203.1 | 42.9 |
| 400 units | 250 | 100.6 | 12.2 |
| 2000 units | 250 | 100.6 | 12.2 |

A full-speed head-on cost a third of what a slower crash did. A crash at speed
is not resolved in one physics frame: the solver takes two, the impact figure
was the speed LOST into the normal on the contact frame alone, and the 0.5
second contact cooldown then swallowed the second frame. Which fraction of the
stop fell inside the first frame depended on exactly where the truck was when it
touched, so cost tracked sub-frame alignment rather than severity, and the long
run-up, the common case on a map of long straights, was the cheap one.

`TruckController._strongest_impact_speed` now reads the speed the truck ARRIVED
at, measured into the contact normal. Resting against a wall is still free
(the velocity reconciliation zeroes the truck against it, so the next frame
carries only the acceleration gained since, far under the threshold), and a
glancing blow is still cheap (only the component into the normal counts).

`collision_damage_scale` 0.3 -> 0.25. With the impact read correctly a head-on
registers the full 250 and 0.3 would cost 57, so two bad crashes would end a
shift. 0.25 costs 47.5, leaving a player who has crashed badly twice with 5
condition and a shift they can still finish; a third does end it.
`collision_damage_threshold` stays at 60, which the measurements put in the
right place.

After:

| Crash | Speed | Into normal | Cost |
|---|---|---|---|
| Gentle nudge (4 unit run-up) | 38 | 0.0 | 0.0 |
| Slow bump (12 unit run-up) | 70 | 73.3 | 3.3 |
| Brisk bump (30 unit run-up) | 110 | 113.7 | 13.4 |
| Moderate (60 unit run-up) | 158 | 161.3 | 25.3 |
| Fast (140 unit run-up) | 246 | 249.3 | 47.3 |
| Full speed (400 unit run-up) | 250 | 250.0 | 47.5 |
| Full speed (2000 unit run-up) | 250 | 250.0 | 47.5 |

Monotonic in speed, and the two full-speed cases finally agree. A crash also
shakes the camera now, scaled by impact speed and capped, 0.28 seconds and
positional only: it never rotates, because keeping the world north up is the
whole reason the camera is a sibling of the truck rather than a child.

### Part 3: Results, shop and HUD

The results screen itemises the takings rather than summarising them in a
sentence: calls cleared and what they paid, the shift bonus on its own line
(labelled "not earned" and showing 0 credits when it was not), a rule, then the
total banked. One primary action, "Start another shift", which takes focus.

The shop states its effect in numbers ("Tank capacity 100 to 125 units"), its
price and the player's balance, and has exactly three button states in words:
"Buy bigger tank", "Owned", "Not enough credits". Disabled in the last two,
never hidden. Owned beats broke, so an owner who is short of credits is told
they own it.

Escape now backs out of the shop to the results screen. It previously only
paused a running game, so from the shop it did nothing at all; there is no path
from it into a running game, because the shop is only reachable once a shift is
over.

One formatter for money, `GameUI.format_credits`, so "350 credits" reads the
same on the HUD and both panels and "1 credit" is singular. Two stale initial
labels were fixed and `GameSession`'s underfunded message no longer shows a bare
number.

**A conflict, named rather than silently resolved.** The prompt asked for Title
Case buttons; `AGENTS.md` section 10 puts buttons in sentence case and says the
decision is settled and not to be reopened. The instruction was to hold the
panels to `AGENTS.md`'s rules, so `AGENTS.md` won and the buttons are sentence
case. Panel titles are Title Case with no terminal period, and no internal
identifier reaches a screen.

**Layout was not seen.** Nothing here was rendered at 1280x720 or at 960x540.
The anchors were read instead: every HUD element is anchored to a corner or sits
in a container with no fixed pixel positions, the panels are a CenterContainer
around a PanelContainer that sizes to its content, and `project.godot` stretches
`canvas_items` with an `expand` aspect. That is a reading of the code, not an
observation of the screen, and overlap at a narrow size remains James's to check.

### Part 4: Cleanup

`MapBuilder._build_hydrant_marker`, `_build_incident_marker` and `_circle_polygon`
are deleted, along with the two colours only they used. They were kept for a map
preview tool that never arrived and had been unused since the first build's Part
4. The `Markers` layer they would return to is still built and still empty.

### Verification Performed

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 300                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        5 test files, 45 test methods, 416 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        54 checks, 0 failed

New checks: escalation determinism, the base floor, the grid distance rule, the
exchange rate and the cap; the shop's three button states against the session's
own purchase rule; and the money formatter.

Re-proved by deliberate failure: dropping the base from
`FireIncident.escalation_limit_for` so the clock is the travel allowance alone
fails seven assertions in the escalation method, including "a call underfoot
gets the base alone (actual=0.0, expected=45.0)", and the unit runner exits 1.

### Known Issues

- Nothing in this milestone was seen running. Every number above is a headless
  measurement or an exit code. The pacing, the crash feel and both screens are
  James's to judge.
- A shift is roughly 90 to 110 seconds against a handoff target of about five
  minutes. Recorded in Part 1 above as a decision, not fixed here.
- Escalation is still not slowed by effective suppression, per handoff section 5.
- Driving on the sidewalk is still free, pending pedestrians.
- The truck can still circle a block on its sidewalk without touching the road.
- No audio at all.

## Milestone 5: A Real Map, and Choosing Between Maps

Godot 4.7.2. Five parts across two sessions. Parts 0 to 2 (the OpenStreetMap
data, the importer and the map validator) landed in the first session and are
recorded here for the first time; the rest is the second session's work.

### New files

- `data/source/windsor_shadetree_smoketree.overpassql` and `.json`: the exact
  Overpass query and the response it returned, downloaded once on 2026-09-07.
- `ATTRIBUTION.md`: where the data came from, what the licence says, and what
  this project does with it.
- `tools/import_osm.gd`: turns that response into a `MapDefinition`.
- `tools/validate_map.gd` and `scripts/MapValidator.gd`: the rules any map has
  to satisfy to be playable.
- `resources/windsor_shadetree.tres`: the imported map.
- `scripts/RoadGraph.gd`: the road network as a graph.
- `scripts/MapGeometry.gd`: the polygon regions a map is drawn and collided from.
- `scripts/MapCatalogue.gd`: the maps the menu offers and the honest lines that
  travel with each one.

### Parts 0 to 2: the data, the importer and the validator

A 500 by 380 metre box around Shadetree Drive and Smoketree Street, Windsor,
California, at 25 world units per metre: 12,499 by 9,500 units, 42 road
segments, 103 graph nodes, 19 junctions, 19 dead ends, 238 real building
footprints plus 17 synthetic lots, and 12 synthetic hydrants. The box started at
250 by 180 metres and was grown because the network inside it held one
intersection, no loop and two disconnected pieces. Every feature carries
`source: "osm"` or `source: "synthetic"`.

`MapValidator` runs six rules over every map in `resources/`, from the unit
suite and separately as a tool. Both maps pass all six.

### Part 1: Rendering and gameplay on angled roads

`MapBuilder` treated every road as a straight axis-aligned rectangle and read
the land between roads out of `MapDefinition.blocks`, which are rectangles too.
An imported road bends, meets another at whatever angle the ground gives, and
stops dead in a cul-de-sac, and the land between roads like that is not a set of
rectangles. Both assumptions are gone.

`MapGeometry` derives everything from the road network: a slab per segment, a
convex fill at every node where two or more segments meet, and then two regions
found by cutting those slabs out of the map rectangle, once at road width to
give the kerb line and once grown by the sidewalk to give the fence line. Yards,
fences, kerbs and lot collision all come from those two, so the kerb and the
fence cannot disagree about where a road is.

**Subtraction rather than a union of the roads**, which is worth writing down
because the obvious approach does not work. Godot's `Geometry2D` merges two
polygons at a time; a road network that encloses a block unions into a ring, and
a ring is a polygon with a hole, which the next merge cannot take as input.
Clipping the map rectangle by one slab at a time never builds a ring. That holds
only while the road network reaches the edge of the map, so `MapValidator`
gained a sixth rule that checks the derived land really does come out as solid
pieces. Elm Grove yields 25, Windsor 37.

`MapDefinition.blocks` is now read by nothing. It is kept, and labelled dead in
its own docstring, rather than removed: dropping it means a schema version 4, a
regenerated `neighbourhood.tres` and a migration, for a field nobody has a stale
copy of. That is James's call, not a tidy-up.

**Escalation is priced along the roads.** The old rule added the x and y gaps,
which is right only while every road is axis aligned and is not any journey a
truck could make on one that bends. It now uses `RoadGraph.route_length`,
measured at dispatch from wherever the truck actually is.
`escalation_travel_allowance_max` 90 to 150.

The clock every candidate gets, measured from the station spawn:

| Map | Nearest call | Furthest call |
|---|---|---|
| Elm Grove | 1,597 units, 59.5 s | 4,897 units, 89.5 s |
| Windsor | 8,207 units, 119.6 s | 25,472 units, 195.0 s |

**The cap still binds on Windsor, and that is a finding rather than a fix.** At
150 seconds, four of Windsor's six candidates are capped: the furthest wants a
276.6 second limit and gets 195.0. Windsor's routes are genuinely long, not an
artefact of how they are measured. The straight line to the furthest candidate
is 11,610 units and the drive is 25,472, because a suburb of loops and courts
makes you go out to the collector road and back; the approach term, the hop from
a point onto the network, is a few hundred units at most. In playing terms Elm
Grove gives about three times the time the drive needs and Windsor about 1.5 to
1.7 times. It is playable and it is tighter. A cap of 240 would stop it binding
on either map. Not done, because 150 was the number decided.

### Part 2: Home menu, map select and Data and Credits

The game opened straight onto one hard-coded map. It now opens on a home menu:
Start shift, which asks which map; Data and credits; Quit.

Each map's honest lines live in `MapCatalogue` beside the map, not in the
layout, so they cannot be separated from it by an edit to a screen. The Windsor
entry carries both required lines and a unit test asserts them word for word.

The Data and Credits screen reads the credit line, the licence and the copyright
URL out of the map resource's own `source_metadata`, so the notice travels with
the data. `GameUI.credit_lines()` is static, so the unit suite reads exactly what
a player is shown rather than a second copy of it.

The credit line is now the copyright symbol rather than "(c)", in the importer,
the resource, `ATTRIBUTION.md` and on screen. Re-running the importer over the
committed source changed that one line and nothing else, which also re-proved
that the importer reproduces the committed resource from the committed data.

**Save schema 1 to 2**, adding `map_id`. A version 1 save is migrated, not
rejected. The previous rule started fresh on any version it did not recognise,
which would have taken the credits and the upgrade off every existing player in
exchange for adding a field with an obvious default; rejection is for a file
that cannot be trusted, not one that is merely old. A version 2 save naming a
map this build does not ship falls back to the default map and keeps the
credits.

Escape backs out exactly one level and cannot reach a running game, decided in
one place, `GameSession.back_out()`.

**Two defects found by the new checks, both fixed.** Starting a shift left the
camera to glide to the station from wherever the last one ended, which on a map
12,499 units across is a long uncontrollable pan over the player's first
seconds, and it briefly pointed the off-screen call arrow somewhere the fire was
not. And the physics runner was writing to the player's own save file: it drives
the real `GameSession`, so every run banked 350 credits to disk, and once maps
became choosable it would have changed which map their game opened on.

### Verification Performed

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 200                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        6 test files, 59 test methods, 1669 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        86 checks, 0 failed
    --headless --path . --script res://tools/validate_map.gd       exit 0
        2 maps checked, 0 failed

Physics checks went from 56 to 86, and several now run on both maps: a whole
shift on Windsor, driving off a Windsor road on both sides, and the menu walk.

### Checkers proven by deliberate failure

- **The new map rule.** Growing the fictional map's bounds past its roads makes
  the land one ring: "1 of 57 piece(s) came out as holes, which means the road
  network does not reach the edge of the map". Exits 1.
- **Connectivity, on the real imported map.** Deleting one road from
  `windsor_shadetree.tres`, Planetree Drive `way/7707901`, and running the
  validator: "16 of 102 node(s) unreachable, first at (1850.606, 6413.694)",
  plus the hydrant and candidate rule naming `h_syn_1` and
  `ic_b_osm_1021193724` as beside road the truck cannot reach. Exits 1. The file
  was restored from git and both maps validate again.
- **The Escape rule.** Adding `PLAYING` to `GameSession.back_out()` fails
  "Escape in a running game backs out of nothing" and "and leaves the shift
  running". Exits 1.
- **The credit line.** Changing it in the importer failed the existing
  `test_osm_import.gd` assertion before that expectation was updated, which is
  the check catching a real change rather than being written to pass.

### Known Issues

- **Nothing in this milestone was seen running.** Every number above is a
  headless measurement or an exit code. How the Windsor map READS, whether its
  junctions look right, whether the street labels are legible against 42 roads
  and whether the clocks feel fair are James's to judge.
- The escalation cap binds on four of six Windsor candidates, described in
  Part 1 above. A decision, not a defect.
- `MapDefinition.blocks` is dead data, kept deliberately, described in Part 1.
- The "Current File Inventory" section at the top of this file dates from the
  first milestone and still describes `Main.tscn` as a placeholder. It has been
  stale for four milestones and is not corrected here.
- `--headless --quit-after` exits 0 even when the main script fails to parse, so
  it is only a real check when its output is read. Every run above was read.
- Escalation is still not slowed by effective suppression, per handoff §5.
- Driving on the sidewalk is still free, pending pedestrians.
- No audio at all.

## Milestone 6: The Junctions, and the Size of the World

Godot 4.7.2. Five parts in one session, after James played the Windsor map for
the first time and reported two things: the map "is just one long road and the
two connections are broken", and the scale "feels off".

Both were real. They are unrelated to each other and one of them had been
invisible to every check in the project.

### Part 0: what was actually wrong

**The junctions.** The land between the roads is found by cutting the road slabs
out of the map rectangle one at a time, and Milestone 5 recorded, in
`MapGeometry`'s own docstring, that this "never builds a ring: as long as the
road network reaches the edge of the map, every piece it leaves behind is a
simple polygon". That is false, and Windsor is where it shows. At 10 of
Windsor's 189 cuts the cut enclosed part of what was left. Godot hands an
enclosure back as a separate polygon wound clockwise, the loop appended it to
the region like any other piece, and the next cut took that hole as its subject
and treated a void as solid ground.

What came out was eight pieces of "land" lying inside the road, out of 25: two
whole road segments and six wedges, three of them across the mouths of the side
streets James was looking at. Each was drawn with a kerb line around it. That is
the "sidewalk strip and kerb line across the mouth" in the screenshots, and it is
why a junction the truck could drive straight through read as sealed.

`MapValidator`'s sixth rule asks whether the FINAL region contains a hole. By
then every hole had been cut open again, so it passed. The rule was not wrong;
it was asking about the end of a process whose middle was the problem.

Three things it was NOT, all checked before anything was changed:

- The side streets do meet Hembree Lane at shared graph nodes. Every arm's slab
  reaches the junction centre; nothing stops short.
- Nothing solid sits in a junction mouth. The wedges are in the kerb region,
  which carries no collision, so the truck was never blocked by one.
- The sidewalk fill is not painted over anything. Every per-slab concrete ring
  is drawn at `Z_SIDEWALK`, below `Z_ROAD`, so the asphalt covers it, and the
  union of the rings minus the union of the slabs is exactly the sidewalk band
  the rule asks for. It was left as it is, and the reason is written down.

**The condition bar.** James finished the first call of a shift with condition at
10 and asked whether the menu path starts a shift broken. It does not. A Windsor
shift begun the way the menu begins one is on 100 of 100 and a full tank at its
first physics frame, and still is ten seconds later with the controls untouched
and no damage event. There is now a check that says so. The 10 was crashes.

**And a third thing, found by trying to get a green baseline.** The physics
runner was testing whichever map James last played. `Main` reads the real save in
`_ready` and builds that map before the runner can redirect the save, so a suite
that never said which map it wanted inherited one. On a save naming Windsor,
eight of the 86 checks failed on an unchanged tree, including the Elm Grove fence
at 574, a number Windsor has no reason to produce. Every world the runner builds
now names its map.

### Part 1: the fix, and two checks

`MapGeometry` never produces a hole. A cut that would enclose part of its subject
splits the subject in half through the enclosure and cuts the halves instead,
which is the same region written as simple polygons. The docstring that made the
false claim now records what happened.

Two new checks in the unit suite, because either alone can pass while a map is
wrong:

- every junction arm on both maps is asphalt 20 units inside the widest kerb at
  that junction, and in neither the kerb region nor the lot region
- no piece of either region sits inside the road anywhere

Both are needed, and the deliberate-failure runs prove it: with the old cut put
back, at 25 units per metre 4 arms and 8 pieces fail, and at the scale chosen in
Part 2 no arm fails and 4 pieces still do. A junction probe only finds a wedge
that happens to lie on an arm.

Two new physics checks: a Windsor shift started from the menu is whole, and the
truck drives off Hembree Lane through the junction and 475 units onto the road
that joins it, in 7.2 of a possible 12 seconds, with no damage event. The second
is honest about what it proves: the wedges were drawn, not solid, so it would
have passed while the map looked shut.

### Part 2: the scale

The roads were the width James liked and everything else was three or four times
too big for the truck. Measured with `tools/measure_scale.gd`, in truck lengths
(the truck is 90 units long):

| | road width | house width | junction spacing |
|---|---|---|---|
| Elm Grove | 3.11 | 2.63 | 9.22 |
| Windsor at 25 units/metre | 3.06 | 3.76 | 19.52 |
| Windsor at 14, roads pinned | 3.11 | 2.11 | 10.93 |
| Windsor as a share of Elm Grove, before | 0.98 | 1.43 | 2.12 |
| Windsor as a share of Elm Grove, after | 1.00 | 0.80 | 1.19 |

House width is the side of a square of the same area, because a real footprint
is not a rectangle and its bounding box overstates anything built at an angle.
Junction spacing is the distance along the roads from each junction to the
nearest other one.

**14 units per metre**, and road widths pinned in world units rather than derived
from metres. 14 is where the two ratios that were wrong come closest to Elm
Grove's together: below it the houses shrink further to bring the blocks in,
above it the blocks stay long. The world goes from 12,499 by 9,500 units to
7,000 by 5,320.

The rule this establishes, now in `DESIGN.md`: **the roads are exaggerated and
the land is real.** A residential street is 280 units wide on both maps because
that is the width the truck's speed, turning circle, stream range, hydrant radius
and camera zoom were tuned against. Hembree Lane, tagged tertiary, is 313. A way
that carries its own `width` or `lanes` tag is converted at a separate constant
that does not move with the land; no way in this extract carries either.

Consequences, all handled and none hidden:

- A road drawn wider than it is reaches into ground the survey calls a garden.
  A real footprint standing there is shrunk about its own centre until it clears
  the pavement and carries `adjusted_for_road: true`; one that cannot clear it at
  half its size is dropped rather than drawn as a hut. One set back, one dropped,
  out of 237 kept.
- Two synthetic lots, each laid out against one road at a setback from that
  road's kerb, ran across the next street along once the roads were exaggerated.
  The validator caught them. A lot nobody surveyed costs nothing to give up, so
  any that lands on pavement is dropped. 18 remain, from 20.
- Sidewalk width, hydrant standoff and incident marker standoff were already in
  world units and did not move.

**Escalation clocks, recomputed:**

| Map | Nearest call | Furthest call |
|---|---|---|
| Elm Grove | 1,597 units, 59.5 s | 4,897 units, 89.5 s |
| Windsor, before | 8,207 units, 119.6 s | 25,472 units, 195.0 s |
| Windsor, after | 447 units, 49.1 s | 14,302 units, 175.0 s |

The cap that bound on four of six Windsor candidates now binds on none: the
furthest wants 130.0 seconds of travel allowance and the cap is 150.0. Nothing
in `GameBalance` was touched to achieve that; the drives are simply shorter.

The nearest candidate is now 447 units from the station spawn, which is five
truck lengths. That is a finding rather than a fix. Candidate spacing is measured
between candidates and never from the station, which was true before and only
now produces a call this close.

### Part 3: labels and copy

A way with no OSM `name` gets no name and `MapBuilder` draws no label for it. A
link (`highway=*_link`) never gets one even when the data names it, because a
slip road carries the name of the road it joins. The importer used to invent a
name from the highway class, which is how "Unnamed secondary link" came to be
printed across a slip road as though that were a street. Three segments carry no
name now.

Labels were already drawn once per street NAME rather than once per way, so the
optional part of this was already done and nothing changed.

The player-facing accuracy note loses its last sentence, "Every feature carries
its own `source` field". It is true and it is why the rest of the note can be
trusted, and it is a sentence about a data schema shown to someone who came to
drive a fire truck. It is kept in `ATTRIBUTION.md`.

James's save was reset at his request, through `SaveManager`'s own load and write
path so the file left behind is the file the game writes. It held 23,800 credits,
the tank upgrade owned, and Windsor selected. It now holds 0, no upgrade, and the
default map, so the first Start shift will ask and open on Elm Grove unless
Windsor is picked.

### Verification Performed

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 200                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        7 test files, 63 test methods, 1961 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        92 checks, 0 failed
    --headless --path . --script res://tools/validate_map.gd       exit 0
        2 maps checked, 0 failed
    --headless --path . --script res://tools/import_osm.gd, twice
        byte-identical resource both times

Physics checks went from 86 to 92. Unit tests went from 59 methods to 63.

### Checkers proven by deliberate failure

- **The junction checks.** Putting the old cut back in `MapGeometry._clip_region`
  fails `test_no_piece_of_either_region_lies_inside_the_road` with "4 pieces,
  first at (166.5, 5073.1) (area 1415)" at the new scale, and at the old scale
  failed both new checks with 4 arms and 8 pieces. Restored from the copy taken
  before the change and the suite is green again.
- **The map the physics runner builds.** This one was proven by reality rather
  than by an experiment: the suite failed eight checks on an unchanged tree
  because James's save named Windsor, and the same tree passes all of them once
  each world names its map.
- **The scale.** `test_the_land_is_drawn_at_the_chosen_scale_and_the_roads_are_not`
  asserts 14 units per metre, a 7,000 by 5,320 world and 280 unit residential
  streets, so changing either half of the rule is a deliberate edit. Proved by
  putting the pre-rescale resource back from git and running the suite: it fails
  on 25 units per metre, a 12,499 unit world and 275 unit streets, and
  test_every_real_building_says_whether_it_was_moved_off_the_road fails on all
  238 of its footprints for carrying no such flag. Restored, and green again.

### Known Issues

- **Still nothing seen running.** Every number here is headless. Whether Windsor
  now READS at the right size, and whether the junctions look open, is James's to
  judge. The geometry says they are open; how they look is not something a check
  in this project can answer.
- The nearest Windsor call is 447 units from the station, described in Part 2.
- `MapGeometry`'s hole-safe cut has a depth cap of 8 splits. Nothing on either
  map goes past one, and a map that somehow exhausted it would fail the
  validator's no-holes rule rather than draw wrongly.
- Elm Grove is untouched by any of this: its own numbers, including the fence at
  574, are identical before and after.
- `MapDefinition.blocks` is still dead data, kept deliberately.
- The "Current File Inventory" section at the top of this file is still stale,
  now for five milestones.
- Escalation is still not slowed by effective suppression, per handoff §5.
- Driving on the sidewalk is still free, pending pedestrians.
- No audio at all.

## Milestone 7: How the Neighbourhood Looks

James played the rescaled Windsor map and reported three things, all
presentation: "the houses are really ugly", "the street names are weirdly
placed", and "maybe we need to zoom out more to make it feel more like the area
you select". Nothing about gameplay except one small dispatch rule, added in
Part 3 because the same playtest exposed it.

### Part 1: one building renderer, for both maps

The old renderer drew the building polygon in a `body_color` and an inset copy
of it at 62 per cent in a `roof_color`. Both colours came out of the map DATA,
and the two maps had two different generators inventing them: `MapDefinition`
picked Elm Grove's from one list of saturated colours and `tools/import_osm.gd`
picked Windsor's from another. So the two maps did not look like the same game,
a street could carry a purple roof beside a red one, and at the current scale
the un-inset body showed as a 30 unit beige ring around every house in a colour
unrelated to its roof. That ring is what James was seeing as a doubled outline.

Now `MapBuilder` decides, the same way on every map:

- **Roof.** One fill from `ROOF_PALETTE`: five muted, related tones, warm grey,
  slate, terracotta, olive and taupe. The entry is chosen by hashing the
  building's own `id` with FNV-1a, written out in `stable_hash` rather than
  calling `String.hash()`, because the engine's hash is an implementation detail
  and the houses must not change colour when Godot changes it.
- **Outline and ridge,** both derived from that roof tone rather than from a
  shared constant, so a slate house is outlined in slate. The ridge runs along
  the footprint's own longest EDGE, not a world axis, so a house standing at 20
  degrees to the street gets a ridge at 20 degrees; its extent is measured by
  projecting every vertex onto that axis, because an imported footprint is
  rarely a tidy rectangle.
- **Eave shadow.** The footprint drawn once more, five units down and right, in
  a translucent dark tone, so a band shows on the two sides away from the light
  and nothing at all on the two facing it. The light is north west on every map.
- **Driveways.** A strip of concrete from the fence line in to the wall, square
  to the road, drawn under the fence so it reads as a drive up to a gate.
  Skipped where the gap is under 50 units or over 260, and where the strip would
  cross another footprint.

Draw order, bottom to top: sidewalk, road, dashes, yard, driveway, kerb, fence,
eave shadow, roof, outline and ridge, label, marker.

**Two defects were found by looking rather than by a check**, on PNGs rendered
from the real `MapBuilder` output:

1. The first draft ran the driveway to the NEAREST point of the footprint, which
   on a real import is nearly always a corner. Every drive came off its house at
   its own angle and read as a paving slab dropped on the lawn. Running it
   square to the road, into whatever wall the perpendicular meets, fixed it and
   took Windsor from 164 driveways to 85 by dropping the ones that were never
   fronting a road in the first place.
2. Elm Grove gets no driveways at all, and correctly: its houses stand 6 units
   from the sidewalk, so there is no room for one and nothing is missing. That
   is map data, not the renderer.

`body_color` and `roof_color` are still written into both resources and are
simply no longer read, exactly as `MapDefinition.blocks` is not. Removing them
means a schema version 4, a regenerated Windsor import and a migration, for
fields nothing reads. Both are now marked as dead in `MapDefinition`.

### Part 2: street names on the road

A label sat horizontally on the sidewalk beside the point half way along a road,
so "Shadetree Drive" read across the kerb of the street it named. On a road that
bends it is worse than badly rotated: the midpoint of a whole polyline is not on
any particular stretch, so there is no direction to turn it to.

`MapBuilder.street_label_placements` is now a pure function of the road list,
which is what the unit suite checks, and the drawing does nothing but place what
it is handed. One label per street NAME, on the middle of that street's longest
STRAIGHT segment, offset 52 units off the centreline so it clears the dashes,
rotated to the segment and flipped so nothing reads upside down: every rotation
comes back in (-90, 90]. A segment shorter than its name plus a margin carries
nothing. Unnamed ways and links still get nothing, and nothing here has to know
about links, because the importer already drops the name from anything whose
highway tag ends in `_link`.

Two things the first draft got wrong, both caught:

1. **The second label.** A street over 2,600 units long is named twice. The
   first draft put both on the longest segment, at a third and two thirds of it;
   on Windsor the longest straight run of a long street is a few hundred units,
   so six streets printed their name twice about a hundred units apart. The
   separation check in the new test file failed on exactly those six. The second
   label now goes on the longest OTHER segment at least a screen width away, and
   only shares a segment with the first where that is the only segment there is,
   which is Elm Grove's case.
2. **The size.** Font size 15 is a sensible HUD size and is unreadably small
   painted on a 280 unit road. Sized against the road instead: 34, with a 6 unit
   dark outline.

Labels placed: **12 on Elm Grove** (8 named streets; the four 4,000 unit streets
carry two each, the four 3,000 unit avenues one each, because a third of 3,000
is under the 1,200 unit separation rule) and **23 on Windsor** (17 named
streets).

### Part 3: a zoom key, and no doorstep first call

`GameBalance.camera_zoom_levels` is `[0.9, 0.7, 0.55]` and a development key,
`Z`, cycles them during play with a one second HUD line, "Zoom 0.7". **The
default is unchanged**: 0.9 is the first entry, so nothing moves until the key
is pressed. This is deliberately not a guess at the right number. James picks by
looking, and the next milestone pins his choice as the only level and deletes
the key, the `_dev_message` pair in `Main` and the branch in `_compose_prompt`
that carries it. The key is a raw physical keycode, absent from
`project.godot`'s input map, so removing it is deleting code and nothing else.

The camera's lead and its impact shake now scale with the zoom, because both are
written as world distances but are meant as fractions of the screen: 220 units
of lead is a sixth of the way to the edge of the view at 0.9 and would be a
fifteenth at 0.55. Godot's limit clamping is already expressed in world units
and accounts for zoom, so the edge walls stay off screen at all three levels
without the limits being recomputed, and the off-screen call arrow reads the
real canvas transform, so it stays correct too. Measured at all three: lead 220,
283, 360.

`GameBalance.first_call_min_route` is 2,000, and the FIRST call of a shift must
now be at least that far from the station along the roads. This answers the
known issue recorded in Milestone 6: the nearest Windsor candidate is 447 route
units from the station, and a shift could open with a call that was over before
the radio line had been read. The first call is the one the player has no
warm-up for. Every later call keeps the spacing the candidates were imported
with; this is one rule about one call, not a second opinion about candidate
spacing.

`DispatchManager.order_first_call` swaps rather than filters, so a shift is still
the same three calls in the same number, and where no candidate on a map is far
enough the farthest is used rather than the shift failing to start. The routes
are measured once, in `Main`, at map load, and handed in: they are a property of
the map and the station and do not change between shifts, unlike
`travel_distance_to`, which measures from wherever the truck actually is and
prices the escalation clock.

### Verification Performed

    --headless --path . --script res://tests/run_tests.gd          exit 0
        10 test files, 77 test methods, 2450 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        92 checks, 0 failed, including a whole shift paying exactly
        350 credits on BOTH maps, through the new dispatch ordering

Unit tests went from 63 methods to 77 and from 1,961 assertions to 2,450, in
three new files: `test_building_style.gd`, `test_street_labels.gd` and
`test_first_call.gd`. Physics checks are unchanged at 92; the full-shift checks
drive the real `Main`, so they exercise the new first-call rule end to end
without needing a new check of their own.

Both maps were also built headless and rendered to PNG and looked at, at all
three zoom levels. That is how both Part 1 defects and both Part 2 defects above
were found; none of them would have failed a check.

### Checkers proven by deliberate failure

- **The label-in-road check.** Moving `LABEL_CENTRELINE_OFFSET` from 52 to 165,
  which is past the 140 unit half-width of a road and so out onto the kerb,
  fails `test_every_label_sits_on_the_asphalt_and_reads_the_right_way_up` on all
  31 labels across both maps, naming each with its coordinates: "Ash Street at
  (1333.333, 85.0)" and 7 more on Elm Grove, 23 on Windsor. Restored to 52 and
  the suite is green again.
- **The first-call rule cannot pass by being unsatisfiable.** The test asserts,
  before testing anything else, that each map actually HAS a candidate at least
  2,000 route units from its station. Without that, a map whose candidates were
  all close in would satisfy the rule vacuously through the farthest-candidate
  fallback.
- **The roof palette check is asked of the real ids.** All 291 buildings on both
  maps, whose ids are shaped differently on each ("b_00_1" against
  "w_b_240311707"), rather than of invented names a hash could behave on while
  collapsing on the real ones. It also asserts at least three of the five tones
  are actually used, which a hash returning one entry for everything would fail.

### Known Issues

- **The zoom is not chosen.** Three levels exist and the default is the old one.
  This is the open question for James's playtest, and it is the whole reason the
  key is there.
- **Whether the houses now read as a neighbourhood is James's judgement.** The
  checks say the palette is deterministic, the ridges lie on their roofs and the
  labels are on the asphalt. None of them can say it looks right.
- Elm Grove gets no driveways, because its houses stand 6 units from the
  sidewalk. That is the map's data, not the renderer, and it is not being
  changed here.
- `MapDefinition.blocks`, `body_color` and `roof_color` are all dead data now,
  all kept deliberately, all named as dead in the file.
- The "Current File Inventory" section at the top of this file is still stale,
  now for six milestones.
- Escalation is still not slowed by effective suppression, per handoff §5.
- Driving on the sidewalk is still free, pending pedestrians.
- No audio at all.

## Milestone 8: Overlapping Houses, and the Edge of the World

James played the widened Windsor map and found two defects in his screenshots,
plus one on the HUD. All three were real. The zoom key stays, as a control.

### Part 0: the audit, before anything was changed

Both maps rendered to PNG and every defect class counted. Elm Grove was clean on
all five. Windsor:

| What | Count | Notes |
| --- | --- | --- |
| Overlapping footprints | 12 pairs | ALL `osm` x `synthetic`. 0 osm/osm, 0 synthetic/synthetic. None wholly contained. Worst 22,450 square units |
| Junction fills touching the map edge | 9 | 5 real junctions (3 or 4 arms), 4 two-arm bends. All on the east and south sides |
| Road slabs running under the wall | 22 of 105 | 5 top, 9 bottom, 10 right, 0 left |
| Dead ends at the wall with no terminus | 16 | Nothing drawn to say the road stopped |
| Labels off the asphalt | 0 | Milestone 7's rule holds |
| Driveways onto a road | 0 | 9 of 85 overlap a footprint, all their own, by design |
| Synthetic lots straddling the wall | 12 | `b_syn_8` through `b_syn_19`, half of each outside the world |

**The overlap classification settled the root cause before a line was changed.**
Every overlapping pair was one synthetic lot on one or more real houses, and the
extract contains no `building:part` at all, so this was never OpenStreetMap
carrying overlapping parts. It was the importer.

**Shadetree.** The raw data has two ways: `way/7707873` "Shadetree Drive",
`highway=residential`, 16 nodes, latitude 38.540906 to 38.545114; and
`way/7716809` "Shadetree Lane", `highway=residential`, 3 nodes, 38.545114 to
38.545723. They are consecutive: the street changes name where one ends and the
other begins. Both labels are correct and neither is a bug. Windsor has a
Shadetree Drive and a Shadetree Lane, and the short one is at the north end.

**And the thing the audit found that the prompt did not anticipate.** Shadetree
Lane and Leafhaven Lane do not meet at a junction on the map at all. They meet
at OSM node `56129843`, 2.5 metres north of the download box, and the box cut
that junction off, leaving two dead ends 83 units apart at the top wall. There
was no junction there for a rule about junctions on the edge to find.

### Part 1: no house is drawn on top of another

`_synthesize_lots` decided whether a stretch of road frontage was empty by
testing ONE point, the centre of the band at half the lot depth from the kerb. A
real house set back further or nearer than that single sample was invisible to
it, so a full-depth lot went down on top of the house. The same one point
decided whether the lot was inside the world, which is why twelve lots straddled
the walls.

Fixed three ways: the band is sampled across its whole depth; every finished lot
is then tested as a polygon against the real footprints, the lots already
accepted, the road slabs and the world bounds with a 20 unit margin, and dropped
if it cannot meet that; and `building:part` ways are skipped, with two
overlapping real footprints resolving by keeping the larger. The last is a no-op
on this extract and is stated as one.

`MapValidator` gains rule 6, no two building polygons overlap. The unit suite
asks the same question and also that every footprint lies inside the world.

### Part 2: the map stops where it says it stops

Two separate problems with one visible symptom.

**The clip box, on James's decision.** Overpass was asked for ways intersecting
the download box and answered with `out geom`, which returns each matching way's
complete geometry, so the committed JSON has always held 226 m of road north of
the box and 133 m east. The map now reaches 30 m further north and east into
ground that was already in the file: no network call, no invented geography. 30
m is the smallest extension that brings the cut junctions inside. Not more,
because coverage past the download box is ragged by construction.

**The wall.** A centreline clipped to a boundary still carries a slab half a
road width either side of it. Pulling each centreline in by half its own width
was tried first and was wrong: three roads then stopped 140 units short and
landed their ends in the middle of a road running along the edge, which
`test_no_dead_end_is_a_missed_junction` caught. So the roads stay where the
survey puts them and the wall moves out. The world is the geographic box plus a
200 unit verge, 200 being half the widest road this importer can produce.

What the player sees at a road's end: a striped barricade across the asphalt,
and an American yellow diamond with a black T on the verge past it, turned so
the T reads the right way up to a driver coming down that road. It therefore
looks inverted in a screenshot read screen-up and is correct in the game. James
asked for the sign while this part was being written. A cul-de-sac in the middle
of the neighbourhood gets neither: it is a real place a real street ends.

**Camera.** The limits were the world bounds exactly, so the view stopped dead
at a wall and the truck slid to the edge of the frame. It may now overscan half
a screen past the bounds, measured in screen height at the zoom in use, and
`MapBuilder` draws a dark band outside the map so the overscan shows ground.

Two smaller things the change exposed: a hydrant placed by stepping out from its
junction's first arm by that arm's half width landed 215 units from the road
really nearest it against the 200 allowed, and is now placed against the road
the validator measures it against; and clipping put a new vertex a few units
from a surveyed one on three roads, leaving stubs `RoadGraph` could not weld,
each reading as a dead end standing in its own carriageway.

`MapValidator` gains rule 7: no junction fill touches the map edge and no road
slab passes the wall.

| | Before | After |
| --- | --- | --- |
| World | 7,000 x 5,320 | 7,820 x 6,140 |
| Buildings | 255 (237 real, 18 synthetic) | 272 (261 real, 11 synthetic) |
| Overlapping pairs | 12 | 0 |
| Junction fills on the edge | 9 | 0 |
| Road slabs under the wall | 22 | 0 |
| Roads with a terminus | 0 of 16 | every one |

### Part 3: the urgent line, and Z as a control

Under thirty seconds the escalation line grew from 15 point to 20. Measuring it
rather than assuming found that the rows never intersected: the column reflows,
so the growth pushed the rows below down by six pixels. That is worth stating
plainly, because the first version of the new check passed with the defect
deliberately put back.

What was really wrong was that the line grew into a four pixel gap and sat
touching the line under it, and that HUD text had nothing behind it so a pale
street name painted on the asphalt read through the numbers. The gap is eight
now, urgency is carried by the wording and by weight through a `FontVariation`,
which does not change a row's height, and the top-right column sits on its own
dark backing.

Z is a control: an input action, in the pause menu and in `README.md`, with the
HUD naming the level it moved to, and the chosen level kept for the session
across shifts and map changes.

### Verification Performed

    --headless --path . --script res://tests/run_tests.gd          exit 0
        10 test files, 79 test methods, 4012 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        112 checks, 0 failed
    --headless --path . --script res://tools/validate_map.gd       exit 0
        2 maps, 8 rules each, 0 failed
    --headless --path . --script res://tools/import_osm.gd, twice
        byte-identical resource both times

Physics checks went 92 to 112. Unit methods went 77 to 79 and assertions 2,450
to 4,012.

Both maps were rendered to PNG before and after every visual change and looked
at. That is how the overlap fix, the junction fix and the terminus were
confirmed, and it is how the first driveway and label defects in Milestone 7
were found. It is now the required method for any visual part.

### Checkers proven by deliberate failure

- **Rule 6, no two buildings overlap.** Putting the previous
  `windsor_shadetree.tres` back from git fails it and both new unit checks,
  naming the offenders, worst 22,450 square units (`b_osm_1021191705` over
  `b_syn_0`), and 12 footprints outside the world starting at `b_syn_8`. Also
  proven in memory by cloning a real footprint 20 units along, reported as
  29,249 square units shared.
- **Rule 7, nothing runs off the map.** Shrinking the Windsor bounds in memory
  passes at the true size; at 200 units in it reports five roads past the wall,
  worst 115; at 400 in it reports five junctions on the edge as well, worst 367.
- **The HUD gap check, which took two attempts to make real.** The first version
  measured the gap as `GameUI.HUD_ROW_SEPARATION / 2`, the constant it is meant
  to be policing, so setting that constant to zero lowered the bar with it and
  the check still passed. It asserts a literal six pixels now: at a separation
  of zero it fails on all three pairs of rows at both resolutions in both
  states, and passes at eight. This is the third time on this project that a
  checker's first version could not fail.

### Known Issues

- **Nothing here has been played.** Every number is headless or from a rendered
  still. Whether the Shadetree and Leafhaven corner now drives right, and
  whether that Hackberry block reads as a street, is James's to judge.
- Windsor's coverage past the original download box is ragged by construction:
  only ways that poked into the box are in the file, so the 30 m fringe has
  roads whose neighbours are missing. It is inside the map and it is thin.
- 9 of 81 driveways overlap a footprint by more than a quarter of the strip.
  Every one is its own house, which is what the strip is meant to do, but the
  threshold has not been tuned and a genuinely wrong one would not stand out.
- Four two-arm bends still have fills reaching the map edge. Rule 7 asks about
  junctions of three arms or more, because a road is allowed to bend as it
  approaches the edge it ends at.
- `MapDefinition.blocks`, `body_color` and `roof_color` are still dead data,
  kept deliberately and named as dead in the file.
- Escalation is still not slowed by effective suppression, per handoff §5.
- Driving on the sidewalk is still free, pending pedestrians.
- No audio at all.
