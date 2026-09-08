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

