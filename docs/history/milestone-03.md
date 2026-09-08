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

