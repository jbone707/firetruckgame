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

The land between the roads is a concrete sidewalk band around a garden, with
houses on lots facing the streets. The sidewalk is drivable: you can mount the
kerb to get round something, or to pull level with a hydrant, and in this build
it costs nothing at all, no speed penalty and no damage. The gardens behind
their fences are not drivable, and neither are the houses on them, so the
fence, not the kerb, is the line the engine cannot cross. Blocks tile the whole
neighbourhood, verges at the boundary included, so there is no unclaimed ground
anywhere. The gardens' collision sits on its own physics layer, which the truck
collides with and the water stream passes through, because a stream clears a
fence and a front lawn and does not clear a house.

The map's layout is stored as data (`MapDefinition`, saved as
`resources/neighbourhood.tres`) separately from the code that draws and
simulates it (`MapBuilder`): positions, road centerlines and widths,
building polygons, station spawn, hydrant locations and incident-candidate
markers, all with stable ids and all in local world coordinates. A future
real-world importer only needs to produce another `MapDefinition` in this
same shape; nothing else in the game would need to change. `MapBuilder` builds
the whole thing: the road network as one continuous dark asphalt surface with
no seam at any junction, kerb lines and a dashed centre line, the blocks with
their sidewalks and gardens, the houses with contrasting roofs, and the four
map-edge walls.

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
