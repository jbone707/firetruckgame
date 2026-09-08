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

