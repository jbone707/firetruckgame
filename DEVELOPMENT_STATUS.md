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

## Next Milestone

Part 2: map data and construction, per handoff §6 and §7. MapDefinition,
MapBuilder, and a versioned data resource describing road centerlines,
building polygons, station spawn, hydrants, and incident candidates.
