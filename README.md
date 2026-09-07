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
5. Click Start shift.

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
- **E**, held: hook up to a hydrant and refill. You have to be close to it and
  nearly stopped. Driving off, or letting go of E, cancels it
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
- Roads are the only place you can drive. Sidewalks, gardens and lots all stop
  the engine, so getting there means taking the streets.
- Refilling takes about three seconds from the moment the hookup starts.
- When the call is off screen an arrow at the edge of the screen points to it.
  When it is on screen the arrow goes and a marker hangs over the building.
- Crashing hurts, and a flat-out crash hurts a lot. The engine going out of
  service ends the shift.
- Each call you clear banks 100 credits immediately. If the shift later fails you
  keep them. Finishing all three adds 50 more.
- The bigger tank costs 200 credits, can be bought once, and applies from your
  next shift.

## Running the Checks

Two headless test runners, both of which exit nonzero if anything fails:

    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
    "C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tests/run_physics_tests.gd

The first is fast and covers rules. The second boots the real scene and steps
physics, so it takes a little longer and covers integration.

## Project Status

See `DEVELOPMENT_STATUS.md` for what is built, the balance values, the known
issues, and the short manual checklist of things no automated check can observe.
`DESIGN.md` separates what exists from what is planned.
