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
bump does little or nothing.

## Water Model

Water is tracked in abstract units, not gallons: a 100-unit tank, a
10-unit-per-second spray, drained only while actively spraying. The roof
turret aims at wherever the mouse is pointing in the world, and its stream
finds the nearest valid target within its range, so it hits a burning
building's exterior rather than being blocked by that building's own walls.
A fire has two separate values: its health, which drops while it is hit
directly and reaches zero when it is put out, and its escalation, which
climbs on its own from the moment it is dispatched until it either gets
extinguished or reaches the loss threshold. Running the tank dry stops the
stream immediately; hydrants refill it.

## The Map

The neighborhood, "Elm Grove", is a small, entirely fictional grid: three
named streets running east-west (Ash, Birch and Cedar Streets) crossed by
three running north-south (Elm, Fir and Grove Avenues), forming four blocks
with real intersections and more than one route between any two points. It
holds eight buildings, four of them marked as reachable incident candidates,
and four hydrants placed near the roads, including one close to the
station. Roads are 140 units wide, wide enough for the truck (about 90 long
and 40 wide, topping out at 250 units/second) to correct a bad line into a
turn without clipping a kerb.

The map's layout is stored as data (`MapDefinition`, saved as
`resources/neighbourhood.tres`) separately from the code that draws and
simulates it (`MapBuilder`): positions, road centerlines and widths,
building polygons, station spawn, hydrant locations and incident-candidate
markers, all with stable ids and all in local world coordinates. A future
real-world importer only needs to produce another `MapDefinition` in this
same shape; nothing else in the game would need to change. As of this part,
`MapBuilder` can construct the neighborhood's visuals and collision (roads
and sidewalks are decorative only; buildings and the four map-edge walls
block movement), but it is not yet wired into the playable scene, and there
is no truck, camera or HUD to view it with yet.

## What Is Actually Built

Everything above this line is implemented and running as of the final commit of
this first playable build: the neighbourhood and its collision, the truck, the
north up camera, impact damage, pause, the water tank and turret, fire incidents
with separate health and escalation, hydrants, sequential dispatch, the HUD, the
results screen, the shop and the save file. Earlier drafts of this document
called parts of it scaffolding, which was true when they were written and is not
true now.

Two things described above rest on judgement no automated check can make, so they
are on James's playtest list rather than claimed here: how the truck FEELS to
drive, and whether the fire effects stay readable in motion. The six item manual
checklist is in `DEVELOPMENT_STATUS.md`.

## Future, Not Implemented

The following are part of the long-term vision but are explicitly out of
scope for this build, and nothing here should be read as a claim that they
exist yet:

- **Real-map import.** Generating a playable neighborhood from an actual
  place, starting with Windsor, California, preserving real streets and
  building footprints. This build's neighborhood is entirely fictional and is
  not a stand-in for, or an approximation of, any real location.
- **Traffic and signals.** Moving traffic, working traffic signals, and later
  upgrades that improve how traffic yields to the engine.
- **iPhone and touch.** Native iPhone support and on-screen touch controls
  are planned but have not been built, and iPhone compatibility has not been
  tested on any device. Nothing in this build should be taken as a claim that
  it runs on, or has been tried on, an iPhone.
