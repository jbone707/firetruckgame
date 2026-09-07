# Fire Truck Game: First Playable Build

## Instruction to Claude Code

Implement the first playable Godot game described below in the local project folder. Work through implementation and verification rather than stopping at a plan. Inspect the workspace and any AGENTS.md or CLAUDE.md instructions first. Preserve unrelated files. If this folder contains an unrelated project, create an isolated child folder named FireTruckGame. Do not overwrite another game.

The user, James, is a firefighter and a first-time game creator. ChatGPT and James developed this concept together. You are the local implementation agent. Make routine engineering decisions autonomously, explain consequential deviations, and provide simple launch instructions. Do not require James to manually create scenes, attach scripts, or configure input actions that you can create in project files.

These values are proposed first-build tuning defaults, not settled long-term design decisions. Keep them centralized and easy to change after playtesting. Working title: Fire Truck Game. Do not spend time naming or branding it.

## 1. Product direction

A top-down arcade firefighting roguelite for Windows and eventually native iPhone in landscape orientation. Drive an engine through a city, reach dispatched fires, extinguish them with a roof-mounted water stream, and refill the limited tank at hydrants. Collisions damage the engine. Completed calls earn credits that survive failed shifts and fund permanent upgrades.

The defining long-term feature is selecting a real geographic area and generating a playable city that preserves recognizable streets and available building footprints. Windsor, California is the first intended real location. This milestone uses an explicitly fictional test neighborhood. Never label synthetic geography as an accurate Windsor map.

The user wants working traffic signals, moving traffic, and later upgrades improving traffic yielding. Keep these in the roadmap, not this first implementation. Do not expand into multiplayer, backend accounts, monetization, crew simulation, interior firefighting, or a whole-city simulation.

## 2. Environment and delivery

- Identify the installed Godot executable and exact version. Use local help and installed documentation first, official documentation for that version when needed. Do not assume the newest release or install/upgrade the editor unnecessarily.
- Target Godot 4 with typed GDScript and a simple 2D renderer suitable for later mobile testing. If only Godot 3 is installed, report the compatibility issue before making system changes.
- Use built-in drawing, original simple assets, and built-in fonts. No paid assets or plugins are required.
- Produce project.godot, a configured main scene, all required resources/scripts, README.md, DESIGN.md, and DEVELOPMENT_STATUS.md.
- The game must open and play with Godot's Run Project action. A Windows export is optional if matching export templates are already installed. Do not block editor play on export setup.
- No Apple credentials, iOS signing, or Mac access is required for this milestone. Do not claim iPhone compatibility has been tested.

## 3. Required playable loop

Start screen -> new shift -> three sequential calls -> success or failure -> results and upgrade shop -> another shift.

Start the engine at a station, at full condition and water. Dispatch one active fire at a time. Extinguish three fires to finish a shift. Lose when truck condition reaches zero or an active incident's escalation reaches its limit. There is no overall shift countdown in this milestone. Target roughly five minutes per shift after tuning, but do not prioritize exact duration over playability.

Each completed call earns 100 credits. Those credits are banked immediately, including if the shift later fails. No currency for merely spraying. A successful shift awards another 50 credits. Event handling must prevent duplicate call rewards or duplicate completion bonuses.

One permanent upgrade: +25% tank capacity, costs 200 credits, one purchase only. Show its effect and owned state. Apply it to the next shift. A new shift restores condition and fills the upgraded tank. Failure does not remove previously earned credits or upgrades.

## 4. Driving and camera

- W/up: throttle. S/down: brake while moving forward, reverse after slowing. A/D or left/right: steering. Space: stronger brake. Q: toggle siren/lights. Left mouse button: spray. E held: hydrant hookup/refill. Escape: pause.
- Use one consistent top-down orientation convention. The engine steers relative to its heading, not screen axes. Reverse steering should feel natural. Avoid a truck that rotates freely in place.
- Prefer CharacterBody2D with explicit acceleration, drag, steering and collision response for predictable arcade control. Equivalent implementations are acceptable if justified.
- Start with forward speed around 250 world units/second and reverse around 90. Tune scale and turning radius to fit the road geometry, not vice versa.
- Use physics delta for movement and all rate-based systems. Slow down turning at very high speed enough to feel weighted without making the engine frustrating.
- Smooth follow camera with fixed north-up orientation, bounded to the neighborhood. Keep reasonable forward visibility.
- Buildings and map edges block the engine. Decorative marks do not. Provide a station recovery/reset action from pause for development; it must not refill, repair, reset incident timers, or award credits.
- Collision damage is based on pre-collision velocity into the collision normal. A gentle bump causes little or no damage. A significant crash hurts. Do not repeatedly deduct damage every physics frame while resting against a wall. Use a short contact cooldown and an impact threshold.

## 5. Fire and water

Use abstract water units, not claims of realistic gallon usage. Proposed defaults: 100-unit tank, 10 units/second spray, 120-unit stream range, 20 fire health/second direct hit, 100 starting fire health per call. This should require at least one refill across three calls while allowing the first call to be completed from a full tank.

The roof turret aims independently toward the mouse's world position. Render a readable animated stream and impact splash, with a clear nozzle origin. Use a ray or shape query to find the nearest valid hit; obstacles occlude the stream. A burning building must be hittable at its exterior instead of having its own wall incorrectly block extinguishment. Damage only the first valid fire target hit, not every target along the aim direction.

Water is consumed while spraying even when missing. Scale extinguishment by water actually consumed during the tick, including the final partial tick. At empty, the stream stops immediately and the HUD indicates refill required. Stopping is useful for aiming, but moving is allowed and has no hidden effectiveness penalty in this version.

Fire health and escalation are separate values. Fire health decreases when hit and reaches zero on extinguishment. Escalation advances from dispatch to incident loss over an initial 120 seconds. Display the remaining margin clearly. Pause stops both. Later balancing may slow escalation during effective suppression, but do not add hidden rules now.

Visual fire effects stay within a limited particle/draw budget. Smoke cannot obscure the controls or make the target unreadable. Fire extinguishment is a one-time transition that stops its effects, grants its reward once, and dispatches the next call after a brief readable confirmation.

## 6. Hydrants

Place at least three hydrants next to drivable roads, including one near the station. Each has a visible interaction radius. The engine must be within range and nearly stationary. Holding E initiates a two-second hookup and then fills at 25 units/second up to tank capacity. Leaving range, releasing E, or moving cancels hookup/refill. Spraying and refilling cannot occur together. Give refill priority and communicate the state.

Show contextual prompts for moving too fast, hookup progress, refilling, and tank full. Do not depend only on color. A player who runs dry must always have a reachable refill option.

## 7. Map and visual direction

Create one compact neighborhood with several blocks, a station, intersections, three reachable incident buildings, hydrants, and multiple route choices. Roads need enough clearance for the full engine and forgiving turns. Use clean retro-inspired shapes rather than investing in complex pixel art. Include a recognizable red engine, cab/windows, wheels, roof equipment, turret, warning lights, sidewalks, contrasting roofs, and visible hydrants.

Provide a simple minimap or a clear off-screen incident direction indicator plus destination marker. Make it possible to navigate without memorizing the map. Give fictional streets readable names if helpful.

Store the neighborhood definition separately from rendering and gameplay. A minimal versioned data resource or JSON should describe road centerlines and widths, building polygons, station spawn, hydrants and incident candidates, using stable IDs. All positions use local world coordinates.

Future importers should output this same map definition. Preserve optional fields for source metadata and geographic bounds. Do not build an elaborate generic GIS system now. Real-data roads later need intersection handling, bridges/layers, missing-data fallbacks, and reachability validation. Never substitute a downloaded map image for actual drivable geometry. Later map ingestion should use a suitable geographic dataset/provider with verified attribution and usage conditions, not scraping public map tiles.

## 8. Suggested architecture and interfaces

Keep responsibilities separate without excessive framework code:

- Main/GameSession: shift state, scene orchestration, completion and loss.
- TruckController: driving and collision condition.
- WaterSystem: tank, turret targeting, suppression and refill coordination.
- FireIncident: health, escalation, incident terminal state.
- Hydrant: range and refill availability.
- DispatchManager: sequential call selection and markers.
- SaveManager: credits, upgrade ownership, validated local persistence.
- HUD: displays and player-facing prompts.
- MapDefinition/MapBuilder: map data and constructed geometry.
- GameBalance: centralized tuning values.

Useful interfaces, adapt names to the final architecture:

```gdscript
# Intent boundary allows later touch/controller inputs to use the same logic.
func set_drive_intent(throttle: float, steering: float, brake: bool) -> void:
    pass

func set_aim_world_position(target: Vector2) -> void:
    pass

# Returns actual amount consumed, clamped to available water.
func consume_water(requested: float) -> float:
    var used: float = minf(maxf(requested, 0.0), water_remaining)
    water_remaining -= used
    return used
```

Water application should follow this pattern, with targeting resolved separately:

```gdscript
var consumed := consume_water(flow_per_second * delta)
if target_fire != null and consumed > 0.0:
    target_fire.apply_suppression(consumed * suppression_per_water_unit)
```

Use signals such as incident_extinguished(incident_id), incident_lost(incident_id), and truck_destroyed. Guard terminal transitions. Session states should include MENU, PLAYING, RESULTS, and SHOP; pause may use the engine pause mechanism. Ensure pause UI still processes input and physics/timers stop correctly.

Separate desktop input from simulation. UI should use anchors/containers and scale across wide and narrow landscape windows. Actual touch controls are next-stage work; do not add nonfunctional decorative controls or claim mobile completion.

## 9. Saves and restart correctness

Persist a schema version, nonnegative integer credits, and the tank-upgrade flag under user://. Treat missing or malformed saves as recoverable, with safe defaults and a brief diagnostic. Use a temporary file and suitable replace/backup strategy to reduce corruption risk. Validate loaded values. Persist after rewards and purchases.

Starting another shift must clear old fires, markers, signal connections, contact cooldowns and per-run reward guards. Do not duplicate nodes or retain a lost incident's timer. Prevent repeat purchases and spending below zero. No cloud account or shared PC/iPhone progression in this build.

## 10. Verification and required self-review

Run an editor import/parse check and a brief headless startup using commands appropriate to the installed Godot executable. Check actual errors and exit codes. A headless launch is not a gameplay test.

Add focused automated checks where practical for these consequential rules: water cannot become negative, partial tank use scales suppression, each reward occurs once, upgrades cannot be purchased twice or without funds, and earned credits survive a failure and reload. Avoid large tests that simply mirror implementation.

Visually run the project if your tools allow it. Otherwise state exactly what could not be observed and give James a short manual checklist:

1. Drive around a block, brake/reverse, then hit a building gently and hard.
2. Spray a fire, miss deliberately, and verify both fire health and water behavior.
3. Run empty, reach a hydrant, refill, and interrupt hookup by moving.
4. Complete three calls, receive one completion bonus, and buy the tank upgrade.
5. Start again, confirm larger capacity, deliberately fail after earning a call reward, and restart the application to verify persistence.
6. Pause during spraying/escalation and resize the window to confirm usable HUD layout.

Before delivery, review input focus, mouse-to-world conversion under the moving camera, collision masks, obstacle occlusion, terminal-state reward guards, restart cleanup, save validation, and refill/spray exclusivity. Fix defects you find instead of listing avoidable bugs as future work.

Do not claim tests, visuals, exports, or device compatibility you did not verify. Keep an honest distinction between automated validation and user playtesting.

## 11. Delivery response

Give James the project location, detected Godot version, exact steps to import/open project.godot and run it, a short controls list, completed features, checks performed, and material limitations. Update DEVELOPMENT_STATUS.md with current files, known issues, balance values, and the next milestone. Keep DESIGN.md aligned with implemented behavior and clearly label future features.

Next milestone after playtest feedback: import a small real Windsor neighborhood through MapDefinition, validate drivable connectivity and hydrant access, then add basic traffic and signals. Native iPhone controls/testing follow early enough to shape performance and interface choices. Do not begin those later milestones automatically in this task.

Proceed with the implementation now.
