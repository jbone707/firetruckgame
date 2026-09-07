# Fire Truck Game

A top-down arcade firefighting game, in early scaffolding. This is Part 1: the
project opens and runs, but there is no gameplay yet. Later parts add the
truck, the map, the fires, and everything else.

## How to Open and Run It

1. Open the Godot 4.7.2 editor. On this machine that is:
   `C:\Users\james\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe`
2. In the Project Manager window, click Import.
3. Browse to this folder and select the `project.godot` file inside it, then
   click Import & Edit.
4. Once the editor opens, press F5 (or click the Run Project button, the play
   arrow in the top right) to launch the game.

You do not need to create any scenes, attach any scripts, or set up any
controls yourself. All of that is already in the project files.

Right now, running the project just opens a blank window and prints a line to
the console confirming it started. That is expected for this stage.

## Controls

These are wired up and ready for the driving, water, and hydrant systems that
later parts will build:

- **W** or **Up Arrow**: drive forward (throttle)
- **S** or **Down Arrow**: brake, then reverse
- **A** or **Left Arrow**: steer left
- **D** or **Right Arrow**: steer right
- **Space**: handbrake (stronger brake)
- **Q**: toggle siren and lights
- **Left Mouse Button**: spray water
- **E** (held): hook up to a hydrant and refill
- **Escape**: pause
- **R**: return to station (development aid only, for testing; it does not
  refill the tank, repair the truck, reset a fire's timer, or award credits)

## Project Status

See `DEVELOPMENT_STATUS.md` for exactly what has been built so far and what
comes next.
