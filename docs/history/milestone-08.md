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
