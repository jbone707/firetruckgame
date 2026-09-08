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

