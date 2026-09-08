# Fire Truck Game

A top-down arcade firefighting game. Drive the engine to each call, put the fire
out with the roof turret before it gets away, refill at a hydrant when the tank
runs low, and spend what you earn on a bigger tank. Three calls to a shift.

This is the first playable build. It is a real, complete loop from the start
screen through three calls to the results screen and the shop.

## How to Open and Run It

1. Open the Godot 4.7.2 editor. On this machine that is:
   `C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
2. In the Project Manager window, click Import.
3. Browse to this folder and select the `project.godot` file inside it, then
   click Import & Edit.
4. Once the editor opens, press F5, or click the Run Project button, the play
   arrow at the top right, to launch the game.
5. Click Start shift, then pick a map.

## The Two Maps

Start shift asks which neighbourhood to run the shift on. Your choice is
remembered for next time.

- **Elm Grove** is invented. It is not a real place.
- **Windsor test area** is built from OpenStreetMap data for a 500 by 380 metre
  box around Shadetree Drive and Smoketree Street in Windsor, California. The
  streets and most building outlines are real. **It is not an accurate map of
  Windsor**: some lots and every one of the twelve hydrants are invented,
  because the source data does not contain them.

Map data © OpenStreetMap contributors, available under the Open Data Commons
Open Database License (ODbL). See https://www.openstreetmap.org/copyright, the
Data and Credits screen on the home menu, and `ATTRIBUTION.md` for the terms and
what was done with the data. The game makes no network calls and uses no map
images.

You do not need to create any scenes, attach any scripts, or set up any controls
yourself. All of that is already in the project files.

## Controls

- **W** or **Up Arrow**: drive forward
- **S** or **Down Arrow**: brake, then reverse once you have slowed
- **A** or **Left Arrow**: steer left
- **D** or **Right Arrow**: steer right
- **Space**: handbrake, a stronger brake
- **Q**: toggle the siren and lights
- **Left Mouse Button**: spray water at wherever the cursor is
- **M**: turn the minimap in the bottom right corner off and on
- **N**: zoom the minimap, through three levels. This changes the minimap only
  and never moves the game camera. The button in the minimap's own corner does
  the same thing. Both this and **M** are kept for the rest of the session
- **Z**: zoom the camera out or in, through three levels. The level you pick is
  kept for the rest of the session
- **Escape**: pause
- **R**: return to station. A development aid only. It moves the engine back and
  stops it, and does nothing else: it does not refill the tank, repair the
  engine, reset a fire's timer, or award credits

## A Few Things Worth Knowing

- Water is spent whether or not the stream connects, so aiming matters. When the
  stream is actually taking health off the fire it flashes into white steam, the
  flames start going out, and the HUD says "Knocking it down". Plain water and no
  line means you are missing.
- A wall between the nozzle and the fire blocks the stream.
- Roads and sidewalks are where you can drive. Mounting the kerb is allowed and
  costs nothing. Garden fences and houses are not: the fence line, not the kerb,
  is where the engine stops.
- **Hydrants hook themselves up.** There is no key. Roll into a hydrant's ring
  at a creep and the hose shoots out on its own, takes about half a second to
  reach you, and then fills the tank at 50 units a second. Nose in, alongside or
  at an angle all work; you just have to be on the hydrant's side of the street.
  Every hydrant draws its reach on the ground, dashed when you are too far away
  and solid once you are close enough for the hose to go out.
- **Driving off is how you unhook.** The hose hangs slack for the first stretch,
  then pulls straight and starts to shake, and at about 260 units from the
  hydrant it snaps, flicks back and disappears. That is the only way off a
  hydrant, and you do not have to do anything but drive. A full tank shuts the
  water off and keeps the hose, so the engine is never quietly untethered while
  you are deciding where to go.
- You can spray while you are hooked up. Water comes in faster than the stream
  takes it out, so the tank still climbs.
- When the call is off screen an arrow at the edge of the screen points to it.
  When it is on screen the arrow goes and a marker hangs over the building.
- The minimap in the bottom right shows the whole neighbourhood, north up: the
  streets as thin lines, hydrants as red dots, the call as a pulsing orange
  marker, and the engine as a triangle pointing the way it is facing. The faint
  rectangle around it is the piece of the map you can currently see. The arrow
  tells you which way the call is; the minimap tells you where you are.
  Zoomed in, the minimap follows the engine, and if the call is off the edge of
  the panel a small orange triangle on the border points at it.
- **Crashing is a speed thing.** Nudging a fence while you place the engine, or
  scraping a kerb on the way round a corner, costs nothing at all. Damage starts
  at about half top speed and climbs steeply from there, so a flat-out head-on
  hurts a great deal and everything short of one hardly registers. The engine
  going out of service ends the shift; it takes three real crashes.
- The stream reaches about one road width, which is far enough to hit a house
  from the middle of the street outside it. Pulling over to the near side still
  helps, and from the far kerb of a wide road you will come up short.
- Each call you clear banks 100 credits immediately. If the shift later fails you
  keep them. Finishing all three adds 50 more.
- The bigger tank costs 200 credits, can be bought once, and applies from your
  next shift.

## Running the Checks

Two headless test runners, both of which exit nonzero if anything fails:

    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/run_physics_tests.gd

The first is fast and covers rules. The second boots the real scene and steps
physics, so it takes a little longer and covers integration; it runs several of
its checks on both maps. Neither touches your save file.

Every map in `resources/` also has to pass six structural rules. That runs
inside the unit suite, and separately as a tool that can be pointed at a map
that is not committed yet:

    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/validate_map.gd

Add `-- res://resources/windsor_shadetree.tres` to check one map instead of all
of them. It exits nonzero if any rule fails on any map.

One more tool measures rather than checks. It prints each map's road width,
house footprint width and junction spacing, in world units and in truck lengths,
which is how the Windsor map's scale was chosen:

    "C:UsersjamesDownloadsGodot_v4.7.2-stable_win64.exeGodot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/measure_scale.gd

## Rebuilding the Maps

Neither of these needs to be run to play the game. Both write into the
repository, so they are tools and are deliberately not part of either runner.

Elm Grove is generated from one function, so a change to the layout is a change
to `MapDefinition.create_fictional_neighbourhood()` rather than to a hundred
hand-edited coordinates:

    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/regenerate_map.gd

The Windsor map is rebuilt from the OpenStreetMap response already committed
under `data/source/`. It reads that file and nothing else, so it works offline
and produces the same resource every time:

    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/import_osm.gd

Run the validator afterwards either way. If you ever need to download the data
again rather than re-import it, the exact Overpass query is committed at
`data/source/windsor_shadetree_smoketree.overpassql` and `ATTRIBUTION.md`
records the API usage policy that applies.

## Project Status

See `DEVELOPMENT_STATUS.md` for what is built, the balance values, the known
issues, and the short manual checklist of things no automated check can observe.
`DESIGN.md` separates what exists from what is planned.
