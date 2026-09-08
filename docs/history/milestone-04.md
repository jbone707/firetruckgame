## Milestone 4: Pacing, Damage and Screen Finish

A polish pass on the things James had not hit yet but would on a full shift.
Driving, scale, roads, the arrow, hydrants and sidewalks were all passing after
Milestone 3. Parts are numbered 0 to 4.

### Part 0: The repository has a remote

`origin` is `https://github.com/jbone707/firetruckgame.git`, and `master` tracks
`origin/master`. Before the first push: `.gitignore` still excludes `.godot/`,
`*.tmp` and `export_presets.cfg`; every tracked file is source, documentation or
map data; and the save file lives at `user://fire_truck_game_save.json`, outside
the repository, so no player data can be committed. The push was accepted with
no conflict, so nothing had to be merged or forced.

### Part 1: Shift pacing, measured

Route lengths come from a graph of the road network, Dijkstra between the
sixteen junctions, not straight lines. The times were then DRIVEN in the physics
runner by a waypoint follower rather than estimated from a speed.

| Call | Road route | Driven | Plus the fight |
|---|---|---|---|
| `ic_20_0` | 1705 u | 7.7 s | 15.7 s |
| `ic_02_2` | 3075 u | 13.3 s | 21.3 s |
| `ic_00_1` | 2805 u | 15.2 s | 23.2 s |
| `ic_12_2` | 3905 u | 16.6 s | 24.6 s |
| `ic_11_3` | 3905 u | 18.0 s | 26.0 s |
| `ic_22_1` | 5005 u | 22.4 s | 30.4 s |

Effective door-to-door speed was a consistent 220 units/second. Candidate to
candidate averages 3012 units, about 19 s, worst pair 4850 units. A knock-down
takes 5.0 s with every drop on target and about 8 s realistically, and needs 50
of the tank's 100 units, so one call fits in a tank and a three-call shift needs
exactly one refill, which costs 3.0 s plus the detour (305 to 1865 units to the
nearest hydrant, depending on the call).

**The worst call on the map needs about 30 seconds against a clock of 120.** The
escalation timer could not be lost by anyone who drove towards the fire, and on
a near call it was four times what was needed.

The rule now prices the journey separately:

    escalation limit = fire_escalation_duration + grid distance / escalation_travel_speed

| Value | Was | Now |
|---|---|---|
| `fire_escalation_duration` | 120.0 | 45.0 |
| `escalation_travel_speed` | n/a | 110.0 |
| `escalation_travel_allowance_max` | n/a | 90.0 |

45 covers the fighting: 8 s of suppression, up to 3 s of refill, and margin.
110 is half the measured 220, so the allowance is twice the drive actually being
asked for. The nearest call now gets 60.5 s against 15.7 needed and the furthest
90.5 s against 30.4: tighter than 120 everywhere, still about three times what
the call costs, and proportionate to the journey instead of sized for the worst
case and applied to all. Distance is measured along the grid rather than as a
straight line, because every road here is axis aligned and a driver cannot cut
the corner, and it is measured at dispatch from wherever the truck is.

Nothing is hidden. The HUD still shows a plain countdown; it simply starts
higher for a call further away. Under 30 seconds it grows and reads "Time left
0:28, running out", because colour is never the carrier of state in this HUD and
a player watching the road is not reading a colour anyway.

**A finding that is James's to decide, not CC's.** A whole shift now measures
roughly 90 to 110 seconds of driving and fighting, plus two 2 s confirmation
pauses. The handoff targets "roughly five minutes per shift" while saying not to
prioritise duration over playability. Closing that gap means more calls per
shift, a bigger map, or a slower engine, all of which are mechanics or
difficulty rather than polish, so nothing here attempts it.

### Part 2: Crash damage, and the defect the audit found

Measured by driving into the map's edge wall under throttle from varying run-ups:

| Run-up | Speed | Into normal | Cost |
|---|---|---|---|
| 140 units | 238 | 203.1 | 42.9 |
| 400 units | 250 | 100.6 | 12.2 |
| 2000 units | 250 | 100.6 | 12.2 |

A full-speed head-on cost a third of what a slower crash did. A crash at speed
is not resolved in one physics frame: the solver takes two, the impact figure
was the speed LOST into the normal on the contact frame alone, and the 0.5
second contact cooldown then swallowed the second frame. Which fraction of the
stop fell inside the first frame depended on exactly where the truck was when it
touched, so cost tracked sub-frame alignment rather than severity, and the long
run-up, the common case on a map of long straights, was the cheap one.

`TruckController._strongest_impact_speed` now reads the speed the truck ARRIVED
at, measured into the contact normal. Resting against a wall is still free
(the velocity reconciliation zeroes the truck against it, so the next frame
carries only the acceleration gained since, far under the threshold), and a
glancing blow is still cheap (only the component into the normal counts).

`collision_damage_scale` 0.3 -> 0.25. With the impact read correctly a head-on
registers the full 250 and 0.3 would cost 57, so two bad crashes would end a
shift. 0.25 costs 47.5, leaving a player who has crashed badly twice with 5
condition and a shift they can still finish; a third does end it.
`collision_damage_threshold` stays at 60, which the measurements put in the
right place.

After:

| Crash | Speed | Into normal | Cost |
|---|---|---|---|
| Gentle nudge (4 unit run-up) | 38 | 0.0 | 0.0 |
| Slow bump (12 unit run-up) | 70 | 73.3 | 3.3 |
| Brisk bump (30 unit run-up) | 110 | 113.7 | 13.4 |
| Moderate (60 unit run-up) | 158 | 161.3 | 25.3 |
| Fast (140 unit run-up) | 246 | 249.3 | 47.3 |
| Full speed (400 unit run-up) | 250 | 250.0 | 47.5 |
| Full speed (2000 unit run-up) | 250 | 250.0 | 47.5 |

Monotonic in speed, and the two full-speed cases finally agree. A crash also
shakes the camera now, scaled by impact speed and capped, 0.28 seconds and
positional only: it never rotates, because keeping the world north up is the
whole reason the camera is a sibling of the truck rather than a child.

### Part 3: Results, shop and HUD

The results screen itemises the takings rather than summarising them in a
sentence: calls cleared and what they paid, the shift bonus on its own line
(labelled "not earned" and showing 0 credits when it was not), a rule, then the
total banked. One primary action, "Start another shift", which takes focus.

The shop states its effect in numbers ("Tank capacity 100 to 125 units"), its
price and the player's balance, and has exactly three button states in words:
"Buy bigger tank", "Owned", "Not enough credits". Disabled in the last two,
never hidden. Owned beats broke, so an owner who is short of credits is told
they own it.

Escape now backs out of the shop to the results screen. It previously only
paused a running game, so from the shop it did nothing at all; there is no path
from it into a running game, because the shop is only reachable once a shift is
over.

One formatter for money, `GameUI.format_credits`, so "350 credits" reads the
same on the HUD and both panels and "1 credit" is singular. Two stale initial
labels were fixed and `GameSession`'s underfunded message no longer shows a bare
number.

**A conflict, named rather than silently resolved.** The prompt asked for Title
Case buttons; `AGENTS.md` section 10 puts buttons in sentence case and says the
decision is settled and not to be reopened. The instruction was to hold the
panels to `AGENTS.md`'s rules, so `AGENTS.md` won and the buttons are sentence
case. Panel titles are Title Case with no terminal period, and no internal
identifier reaches a screen.

**Layout was not seen.** Nothing here was rendered at 1280x720 or at 960x540.
The anchors were read instead: every HUD element is anchored to a corner or sits
in a container with no fixed pixel positions, the panels are a CenterContainer
around a PanelContainer that sizes to its content, and `project.godot` stretches
`canvas_items` with an `expand` aspect. That is a reading of the code, not an
observation of the screen, and overlap at a narrow size remains James's to check.

### Part 4: Cleanup

`MapBuilder._build_hydrant_marker`, `_build_incident_marker` and `_circle_polygon`
are deleted, along with the two colours only they used. They were kept for a map
preview tool that never arrived and had been unused since the first build's Part
4. The `Markers` layer they would return to is still built and still empty.

### Verification Performed

    --headless --path . --import                                   exit 0
    --headless --path . --quit-after 300                           exit 0
    --headless --path . --script res://tests/run_tests.gd          exit 0
        5 test files, 45 test methods, 416 assertions, 0 failed
    --headless --path . --script res://tests/run_physics_tests.gd  exit 0
        54 checks, 0 failed

New checks: escalation determinism, the base floor, the grid distance rule, the
exchange rate and the cap; the shop's three button states against the session's
own purchase rule; and the money formatter.

Re-proved by deliberate failure: dropping the base from
`FireIncident.escalation_limit_for` so the clock is the travel allowance alone
fails seven assertions in the escalation method, including "a call underfoot
gets the base alone (actual=0.0, expected=45.0)", and the unit runner exits 1.

### Known Issues

- Nothing in this milestone was seen running. Every number above is a headless
  measurement or an exit code. The pacing, the crash feel and both screens are
  James's to judge.
- A shift is roughly 90 to 110 seconds against a handoff target of about five
  minutes. Recorded in Part 1 above as a decision, not fixed here.
- Escalation is still not slowed by effective suppression, per handoff section 5.
- Driving on the sidewalk is still free, pending pedestrians.
- The truck can still circle a block on its sidewalk without touching the road.
- No audio at all.

