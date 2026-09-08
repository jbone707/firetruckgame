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

