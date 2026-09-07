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
| `collision_damage_scale` = 0.3 | §4 Collision | Invented; lowered from 0.6 in Part 3 after measuring a real crash |
| `collision_contact_cooldown` = 0.5 | §4 Collision | Invented |
| `tank_capacity` = 100.0 | §5 Water | Specified |
| `spray_flow_rate` = 10.0 | §5 Water | Specified |
| `stream_range` = 120.0 | §5 Water | Specified |
| `fire_damage_per_second` = 20.0 | §5 Water | Specified |
| `fire_starting_health` = 100.0 | §5 Water | Specified |
| `suppression_per_water_unit` = 2.0 | §5 Water | Derived from specified values (`fire_damage_per_second / spray_flow_rate`) |
| `fire_escalation_duration` = 120.0 | §5 Fire | Specified |
| `hydrant_hookup_time` = 1.0 | §6 Hydrants | Specified as 2.0; halved in Milestone 2 Part 4 after James's playtest |
| `hydrant_refill_rate` = 50.0 | §6 Hydrants | Specified as 25.0; doubled in Milestone 2 Part 4 after James's playtest |
| `hydrant_max_hookup_speed` = 15.0 | §6 Hydrants | Invented |
| `hydrant_interaction_radius` = 48.0 | §6 Hydrants | Invented |
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
- A hydrant sits 10 units inside the kerb, and the sidewalk is now solid, so the
  truck's nearest approach is about 30 units driving alongside it, comfortably
  inside the 48 unit interaction radius. A head-on approach would be about 55 and
  would not register. Nobody has hit that in play yet.
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
