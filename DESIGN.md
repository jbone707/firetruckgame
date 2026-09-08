# Fire Truck Game Design

## What the Game Is

Fire Truck Game is a top-down arcade firefighting roguelite. You drive a fire
engine through a city, respond to dispatched fires, put them out with a
roof-mounted water stream, and refill your tank at hydrants along the way.
Crashing into things damages the truck. Finishing a call earns credits, and
those credits survive even a failed shift, so they can fund permanent
upgrades over time.

The long-term goal is to let the game generate a playable city from a real
place, starting with Windsor, California, while keeping recognizable streets
and building footprints. That is a future milestone. This build uses a small,
entirely made-up test neighborhood, and it is not, and is not meant to be, an
accurate map of Windsor or anywhere else.

## The Playable Loop

Start screen, then a new shift begins. A shift is three calls, handled one at
a time. The engine starts each shift at the station, at full condition and a
full tank. Each call dispatches one active fire; reach it, put it out, and
the next call comes in. Finish all three calls and the shift succeeds. The
shift fails if the truck's condition reaches zero, or if a fire's escalation
timer runs out before it is extinguished.

Each completed call banks 100 credits immediately, whether or not the shift
is later lost. A completed shift adds a 50 credit bonus on top. Credits fund
one permanent upgrade: +25% tank capacity, a one-time 200 credit purchase
that applies to every shift after it is bought.

## Driving Model

The truck is controlled with an arcade-style forward/reverse throttle and
left/right steering, relative to the truck's own heading rather than the
screen. Speed builds up and bleeds off smoothly under acceleration, braking,
and drag rather than snapping to a target speed, and turning tightens up at
higher speed so the truck feels weighted instead of twitchy. Buildings and
map edges block the truck; hitting them hard enough damages it, but a light
bump does little or nothing. What a crash costs follows the speed you hit at:
walking pace is free, and a flat-out head-on takes about half the engine's
condition, so you can crash badly twice in a shift and still finish, but not
three times. Every impact shakes the camera briefly, so a hit is something you
see rather than something you notice later in the corner of the screen.

## Water Model

Water is tracked in abstract units, not gallons: a 100-unit tank, a
10-unit-per-second spray, drained only while actively spraying. The roof
turret aims at wherever the mouse is pointing in the world, and its stream
finds the nearest valid target within its range, so it hits a burning
building's exterior rather than being blocked by that building's own walls.
A fire has two separate values: its health, which drops while it is hit
directly and reaches zero when it is put out, and its escalation, which
climbs on its own from the moment it is dispatched until it either gets
extinguished or reaches the loss threshold.

How long a call gets is a fixed allowance for fighting the fire plus an
allowance for the distance you have to cover to reach it, worked out from the
road distance the moment you are dispatched. A call across the neighbourhood is
a longer drive rather than a harder fire. The countdown on the HUD is still a
plain number of seconds with nothing hidden behind it; it simply starts higher
when the fire is further away, and it grows and says it is running out when it
drops under thirty seconds. Running the tank dry stops the
stream immediately; a hydrant takes a second to hook up and then fills at 50
units a second, so a full tank is about three seconds from the moment the
hookup begins.

Pulling up to a hydrant is meant to be easy. Its reach is drawn on the ground
as a ring, dashed while you are still too far away and solid the moment you are
close enough, so you can see whether you have parked well enough before you
touch anything. Reach is measured from the hydrant to the nearest part of the
engine's body rather than to its centre, so nose in, alongside and at a sloppy
angle all work, and stopping a truck length short or overshooting by two still
works. Rolling to a halt counts as stopped. What is still asked of you is to
pull over to the hydrant's own side of the street. Holding E is what starts the
hookup; nothing connects on its own, and while it is connected a hose runs from
the hydrant to the side of the engine.

You can see the stream working. While it is actually taking health off a fire
the impact turns into a dense white steam burst, the flames go out one at a
time as the fire's health falls, a health bar with its percentage sits over
the building, and the HUD says "Knocking it down". Miss, or hit a wall, and it
is plain water and no line: the feedback follows what the fire absorbed, not
what the trigger asked for.

Away from the call, an arrow at the edge of the screen points at the fire
along the line from the middle of the screen, and disappears the moment the
fire itself is on screen, where a marker hangs over the burning building
instead.

## The Map

There are two maps, and the home menu asks which one before every shift. The
choice is remembered in the save file, and a save that names no map, or names
one this build does not ship, opens on the fictional neighbourhood.

### Elm Grove, the fictional neighbourhood

The neighbourhood, "Elm Grove", is an entirely fictional grid 4000 by 3000
units across: four named streets running east-west (Ash, Birch, Cedar and
Dogwood Streets) crossed by four running north-south (Elm, Fir, Grove and
Hazel Avenues), forming sixteen real intersections and nine blocks, with more
than one route between any two points. It holds 36 houses, six of them marked
as reachable incident candidates, and seven hydrants at the kerb, including
one outside the station.

Roads are 280 units wide, kerb to kerb: two lanes and shoulders, a little over
three lengths of the truck (about 90 long and 40 wide, topping out at 250
units/second). At the camera's zoom a road spans about a fifth of the screen
and the player sees roughly a third of the map's width at a time, so a street
reads as a street rather than as a line drawn on a field.

### Windsor test area, imported from OpenStreetMap

The second map is built from OpenStreetMap data downloaded once for a 500 by 380
metre box around Shadetree Drive and Smoketree Street in Windsor, California.
The playable map covers 530 by 410 metres of that data: Overpass returns each
matching way's complete geometry, so the file holds ground beyond the box it was
asked for, and the map reaches 30 metres further north and east into it to bring
two junctions inside that the box had cut in half. At 14 units per metre, plus a
200 unit verge between the last road and the boundary wall, that is a world
7,820 by 6,140 units holding 42 road segments with their real names, 20
junctions, 18 dead ends and 261 real building footprints.

**The roads are exaggerated and the land is not. That is the rule.** A road's
drawn width comes from a table in world units, not from its real width in
metres: a residential street is 280 units wide on this map because that is what
it is on Elm Grove, which is the width the truck's speed, turning circle,
stream range, hydrant radius and camera zoom were all tuned against. Everything
else on the map is the real place at 14 units per metre. So a metre of Windsor
and a metre of its roads are deliberately not the same length, and a street is
about twice as wide against its houses as it is in life.

The alternative was tried first and played wrong. Milestone 5 projected
everything at one scale, 25 units per metre, chosen to make a real residential
street come out at the width Elm Grove used. The roads were right and nothing
else was: measured in truck lengths, Windsor's houses came out half again
bigger than Elm Grove's and its blocks more than twice as long, so the truck
read as a toy and every straight felt long. The three ratios, in truck lengths
(`tools/measure_scale.gd` takes them again):

| | road width | house width | junction spacing |
|---|---|---|---|
| Elm Grove | 3.11 | 2.63 | 9.22 |
| Windsor at 25 units/metre | 3.06 | 3.76 | 19.52 |
| Windsor at 14, roads pinned | 3.11 | 2.11 | 10.93 |

One real consequence, handled rather than hidden: a road drawn wider than it is
reaches into ground the survey says is a garden, and a few real footprints
stand there. Those are shrunk about their own centre until they clear the
pavement and carry `adjusted_for_road: true` in the data; one that cannot clear
it at half its size is dropped instead of drawn as a hut. On today's import one
footprint was set back and one was dropped.

**It is not an accurate map of Windsor and is never presented as one.** The
streets and the building outlines are real; 18 lots, all 12 hydrants and every
colour are invented, because the source data does not contain them. Every
feature in the resource carries a `source` of `osm` or `synthetic` so the two
can never be confused, and the map select screen says both things before the
player picks it: "Streets from OpenStreetMap; buildings partly synthetic" and
"Hydrant locations are placeholders, not real".

The data was downloaded once, on 2026-09-07, through the Overpass API. The
response, the exact query, the importer and the generated map are all committed.
The game makes no network call at any time and uses no map tiles or rendered map
images from any provider. `ATTRIBUTION.md` records the licence and the terms;
the credit line and the OpenStreetMap copyright URL are shown in-game on the
Data and Credits screen, reachable from the home menu.

### How both maps are drawn and collided

The land between the roads is a concrete sidewalk band around the lots, with
houses on them. The sidewalk is drivable: you can mount the kerb to get round
something, or to pull level with a hydrant, and in this build it costs nothing
at all, no speed penalty and no damage. The land behind the fences is not
drivable, and neither are the houses on it, so the fence, not the kerb, is the
line the engine cannot cross. The lots' collision sits on its own physics layer,
which the truck collides with and the water stream passes through, because a
stream clears a fence and a front lawn and does not clear a house.

None of that assumes a road is straight or axis-aligned. `MapGeometry` derives
every shape on the ground from the road network alone: a slab per road segment,
a convex fill at every junction, and then the land found by cutting those slabs
out of the map rectangle, once without the sidewalk to give the kerb line and
once with it to give the fence line. A cul-de-sac, a bend and two streets
meeting at 30 degrees are drawn by the same code that draws a grid, and the
fictional map's fence comes out at exactly the coordinate its hand-built
rectangles used to specify, which is how the rewrite was checked.

A cut that encloses part of what is left would hand back a hole, and Godot
returns a hole as a separate polygon that the next cut would then treat as
solid ground. Milestone 5 assumed that could not happen, because the road
network reaches the edge of the map. It does happen, at 10 of Windsor's 189
cuts, and what came out was eight pieces of "land" lying inside the road: two
whole road segments and six wedges across the mouths of side streets, each one
drawn with a kerb line around it, which is why Windsor read as one long road
with its turnings painted shut. `MapGeometry` now splits a piece in half
through any enclosure a cut would make and cuts the halves instead, so no hole
is ever produced.

`MapValidator` still asks every map whether a hole survived, along with
connectivity from the spawn, every hydrant and incident candidate standing at a
reachable kerb, a minimum road width, roads only overlapping at junctions, and
no building on the pavement. Both maps pass all six rules. Two checks in the
unit suite ask the question the validator cannot: every junction arm on both
maps is asphalt just inside the kerb, and no piece of either region sits inside
the road anywhere.

### How a house looks, and how a street is named

One renderer draws every building on every map, so Elm Grove and Windsor look
like the same game. A house is a roof filled from a fixed palette of five muted,
related tones (warm grey, slate, terracotta, olive, taupe), a ridge along the
footprint's longest axis, a thin outline, and an eave shadow on the two sides
away from the light. The tone is chosen by hashing the building's own stable id,
so it is the same on every machine and every run, and never a saturated primary:
a street is thirty houses seen at once and any one loud roof on it is the only
thing the eye goes to. A house that fronts a street also gets a driveway, a
short strip of concrete running square to the road from the fence line in to the
wall, skipped where the house does not really front that road or where the strip
would run through a neighbour. The map data no longer decides what a house looks
like; `body_color` and `roof_color` are still written into both resources and
are no longer read.

A building that is about to catch fire looks exactly like its neighbours until
it is dispatched. The active call is marked by `FireIncident` and by nothing
else, so the player reads the radio rather than the map.

Street names are painted on the asphalt, along the road. Each name sits on the
middle of that street's longest straight segment, just off the centreline so it
clears the dashes, turned to the segment and flipped where it would otherwise
read upside down, so every label's rotation is in (-90, 90]. One label per
street NAME, not per way, because an imported street arrives as several ways
split at its junctions. A segment too short for its name carries nothing rather
than a name overhanging both junctions; a street over about two screen widths
long is named twice, on two segments at least a screen width apart. Unnamed ways
and slip roads get nothing.

### The camera, and the first call of a shift

The camera is north up and follows the truck, leading it a little at speed.
**Z cycles three zoom levels**, and all three are kept because all three are
useful: one street, two streets, and about a third of the map. It began as a
development key so the right number could be chosen by looking rather than
guessed; the answer turned out to be that the player should choose, per moment,
so it is a control. The level is kept for the rest of the session. The lead and
the impact shake scale with whatever level is in use, because both are written
as world distances but are meant as fractions of the screen.

The first call of a shift must be at least `first_call_min_route` route units
from the station, along the roads. It is the one call the player has no warm-up
for, arriving the instant the shift starts from a standing start, and a
candidate a few hundred units up the road is over before the radio line has been
read. Every later call keeps the spacing the candidates were imported with.

### One roof to a piece of ground

No two buildings overlap. A house drawn on top of a house is the clearest
possible sign that a map was generated rather than surveyed, and Windsor shipped
with twelve of them: the importer decided a stretch of road frontage was empty
by testing a single point in the middle of it, so a real house set back further
or nearer than that one point was invisible and an invented lot went down on top
of it. The invented lots now have to clear every real footprint, every other
lot, every road and the map's own bounds by a margin, and are simply not placed
where they cannot. `MapValidator` asks the finished map rather than trusting the
generator.

Where the two disagree, the real footprint wins and the invented one is dropped.
An invented lot exists only so that an empty frontage does not read as waste
ground, and it costs nothing to give up.

### Where the map ends

Two rules, because a map that stops has to stop honestly.

**No junction sits on the boundary.** A junction cut in half by the edge of the
box is half a turn the player can see and cannot take. Where the data has a
junction just outside, the box is widened to bring it in, using geometry the
extract already contains; where it cannot be brought in, the roads end and are
marked as ending. Windsor's Shadetree Lane and Leafhaven Lane met 2.5 metres
outside the downloaded box, which is exactly this defect.

**No asphalt passes the wall.** The world is the geographic box plus a verge
wide enough that no road slab can reach the boundary, so the truck never sees
road drawn past the thing that stops it. Every road that reaches the verge ends
in a striped barricade across the carriageway and an American dead end sign on
the grass beyond it, turned to face the driver coming down that road. A
cul-de-sac in the middle of the neighbourhood gets neither: it is a real place a
real street ends, and barricading it would be a lie about the map's own edge.

The camera may look half a screen past the world's bounds, so the truck is never
pinned against the edge of the frame while driving at a wall, and the ground
outside the map is drawn so that overscan shows ground rather than void.

A map's layout is stored as data (`MapDefinition`, saved as a `.tres`)
separately from the code that draws and simulates it (`MapBuilder`): road
centrelines and widths, building polygons, station spawn, hydrant locations and
incident-candidate markers, all with stable ids and all in local world
coordinates. Adding a third map means producing another `MapDefinition` and
listing it in `MapCatalogue`; nothing else in the game changes.

## What Is Actually Built

Everything above this line is implemented and running as of the final commit of
this build: both maps and their collision, the home menu and map choice, the
Data and Credits screen, the truck, the
north up camera, impact damage, pause, the water tank and turret, fire incidents
with separate health and escalation, hydrants, sequential dispatch, the HUD, the
results screen, the shop and the save file. Earlier drafts of this document
called parts of it scaffolding, which was true when they were written and is not
true now.

Two things described above rest on judgement no automated check can make, so
they are on James's playtest list rather than claimed here: how the truck FEELS
to drive, and whether the fire effects stay readable in motion. The manual
checklist is in `DEVELOPMENT_STATUS.md`.

## Future, Not Implemented

The following are part of the long-term vision but are explicitly out of
scope for this build, and nothing here should be read as a claim that they
exist yet:

- **More real areas.** The pipeline exists and one area is imported, described
  under "The Map" above. What is not built is a second real area, any way to
  import one without running the tool by hand, or real hydrant locations: the
  twelve on the Windsor map are invented and the game says so wherever it
  offers that map.
- **Traffic and signals.** Moving traffic, working traffic signals, and later
  upgrades that improve how traffic yields to the engine.
- **Pedestrians.** People walking the neighbourhood, on the sidewalks and
  across the streets. None exist in this build; nothing walks anywhere. The
  reason it matters to write down now is that it changes a rule that is
  currently free: driving on the sidewalk costs nothing today precisely
  because there is nobody on it. Once there is, mounting the kerb has to have
  a consequence, and the free ride ends. That is deliberate sequencing, not an
  oversight, and this note exists so the next person to read the sidewalk rule
  knows it is temporary.
- **iPhone and touch.** Native iPhone support and on-screen touch controls
  are planned but have not been built, and iPhone compatibility has not been
  tested on any device. Nothing in this build should be taken as a claim that
  it runs on, or has been tried on, an iPhone.
