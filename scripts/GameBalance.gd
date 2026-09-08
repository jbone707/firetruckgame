extends Node
## Centralized tuning values for Fire Truck Game.
##
## Every number a system needs to balance should live here rather than being
## hardcoded in a controller script. Values taken directly from the handoff
## spec are commented with the section they came from. Values not given by
## the handoff are invented arcade defaults and are each marked with a
## trailing "# invented default, not from handoff" comment so later readers
## can see at a glance which numbers are specified and which are guesses.
##
## Registered as an autoload singleton named "GameBalance" in project.godot.

# ---------------------------------------------------------------------------
# Driving (handoff §4)
# ---------------------------------------------------------------------------

## Top forward speed, world units/second. Specified by handoff §4.
var forward_max_speed: float = 250.0

## Top reverse speed, world units/second. Specified by handoff §4.
var reverse_max_speed: float = 90.0

## Forward acceleration, world units/second^2.
var acceleration: float = 220.0 # invented default, not from handoff

## Reverse acceleration, world units/second^2.
var reverse_acceleration: float = 140.0 # invented default, not from handoff

## Braking deceleration applied while the brake input is held, world units/second^2.
var brake_deceleration: float = 320.0 # invented default, not from handoff

## Stronger braking deceleration applied by the handbrake action, world units/second^2.
var handbrake_deceleration: float = 500.0 # invented default, not from handoff

## Passive drag applied when no throttle/brake input is present, world units/second^2.
var drag: float = 80.0 # invented default, not from handoff

## Steering rate at low speed, radians/second.
var steering_rate: float = 2.4 # invented default, not from handoff

## Fraction steering_rate is multiplied by at forward_max_speed, easing turn-in
## at high speed so the truck feels weighted rather than twitchy. 1.0 would
## mean no reduction at all; this scales linearly between 1.0 at zero speed
## and this value at forward_max_speed.
var high_speed_steering_factor: float = 0.45 # invented default, not from handoff

# ---------------------------------------------------------------------------
# Collision (handoff §4)
# ---------------------------------------------------------------------------

## Impact speed (world units/second, measured into the collision normal)
## below which no damage is dealt at all. A gentle bump should not scratch
## the paint.
var collision_damage_threshold: float = 60.0 # invented default, not from handoff

## Damage dealt per world unit/second of impact speed above the threshold.
##
## Measured against the real thing rather than guessed, twice. At the first
## draft's 0.6 a single wall strike took 85 condition and one mistake was
## effectively fatal. 0.3 was then set against an impact figure that turned out
## to be understated, because the old measurement charged one frame of a
## two-frame stop (see TruckController._strongest_impact_speed). With the impact
## speed read correctly, a flat-out head-on registers the full 250 units/second
## and 0.3 would cost 57 of the 100 starting condition, so two of them would end
## a shift. 0.25 costs 47.5, which leaves a player who has crashed badly twice
## with 5 condition and a shift they can still finish, and a third crash does
## end it. That is the intended shape: punishing, survivable, not endless.
var collision_damage_scale: float = 0.25 # invented default, not from handoff

## Minimum time, in seconds, between damage applications from the same
## resting contact so leaning on a wall does not deduct damage every frame.
var collision_contact_cooldown: float = 0.5 # invented default, not from handoff

# ---------------------------------------------------------------------------
# Water (handoff §5)
# ---------------------------------------------------------------------------

## Base tank capacity, abstract water units. Specified by handoff §5.
var tank_capacity: float = 100.0

## Spray flow rate, water units/second. Specified by handoff §5.
var spray_flow_rate: float = 10.0

## Maximum stream range, world units. Specified by handoff §5.
var stream_range: float = 120.0

## Fire health lost per second of direct hit. Specified by handoff §5.
var fire_damage_per_second: float = 20.0

## Starting fire health per call. Specified by handoff §5.
var fire_starting_health: float = 100.0

## Suppression applied per water unit actually consumed, derived so that
## spray_flow_rate (10 units/s) consumed for one second produces
## fire_damage_per_second (20 health/s) of suppression:
## suppression_per_water_unit = fire_damage_per_second / spray_flow_rate = 2.0.
## Handoff §8's water-application pattern scales suppression by water
## actually consumed during the tick, not by time elapsed, so this ratio
## (rather than a flat per-second rate) is what WaterSystem should use.
var suppression_per_water_unit: float = fire_damage_per_second / spray_flow_rate

# ---------------------------------------------------------------------------
# Fire (handoff §5)
# ---------------------------------------------------------------------------

## Seconds every call gets before it is lost, BEFORE the travel allowance below
## is added to it. Handoff §5 specified 120 as a flat figure for the original
## 1400x1000 map. On the 4000x3000 map a call needs about 8 seconds of
## suppression and at most 3 more for a refill, so 45 is a comfortable margin
## for the fighting itself, and the distance to the fire is paid for separately
## rather than being buried in one number that has to cover the worst case
## everywhere. See DEVELOPMENT_STATUS.md for the measured drive times.
## Handoff §5 specified this value as 120; retuned here with the reason above.
var fire_escalation_duration: float = 45.0

# ---------------------------------------------------------------------------
# Hydrants (handoff §6)
# ---------------------------------------------------------------------------

## THE HOOKUP IS AUTOMATIC (Milestone 9 Part 0). There is no hydrant key any
## more. Rolling into a hydrant's radius under hydrant_max_hookup_speed shoots
## the hose out and connects it; driving away pulls it tight and snaps it.
## James's rule, in his words: "refilling is automatic when you're slowed down
## enough in the zone; the hose shoots out and hooks up; it gets pulled tight as
## you drive away, then snaps and disappears." This supersedes handoff §6's
## held-E hookup and its "spraying and refilling cannot occur together".

## Seconds the hose takes to fly from the hydrant to the truck, which is the
## whole of the hookup: no water arrives until it lands. Replaces the old
## hydrant_hookup_time of 1.0. Shorter because it is no longer a cost the player
## pays for pressing a key, it is an animation of a thing happening to them, and
## 0.6 is long enough to read as a hose being thrown and short enough not to be
## a wait. See hydrant_refill_rate.
var hydrant_hose_launch_time: float = 0.6

## How far, in world units, the truck can be from the hydrant before the hose
## stops hanging slack and starts being dragged. Below this it is drawn with the
## sag a laid hose has; above it the sag is gone, the line is thinner, and it
## trembles. Deliberately above hydrant_interaction_radius (160): the range rule
## decides where a hookup can START, and once the hose is on, the truck is free
## to pull away from the hydrant until the hose says otherwise.
var hydrant_hose_slack_distance: float = 200.0 # invented default, not from handoff

## The distance the hose gives out at, world units, measured hydrant to
## bodywork, the same measurement the range rule uses. Refilling stops on the
## frame this is crossed. 100 units of taut hose past the slack distance is
## about a third of a truck length of warning: enough to see the line go thin
## and shake before it goes.
var hydrant_hose_snap_distance: float = 260.0 # invented default, not from handoff

## Seconds of settled behaviour a hydrant needs before it will throw a second
## hose, after one has snapped or been retracted.
##
## "Settled" means the truck was never both in range AND moving faster than a
## creep. Any frame that is both resets the clock. Without it a truck sitting on
## the edge of the radius rocking back and forth re-hooks on every crossing, and
## the hose animation flaps. Written from James's rule "no re-hook until the
## truck has left range or stayed under creep speed for 1.5 s", read with the
## 1.5 s attached to both halves, which is the only reading that actually stops
## the flapping the rule exists to stop.
var hydrant_rehook_delay: float = 1.5 # invented default, not from handoff

## How long "Hose snapped" stays on the prompt line after a snap, seconds.
var hydrant_snap_message_time: float = 1.0 # invented default, not from handoff

## Refill rate once hooked up, water units/second, up to tank capacity. Handoff
## §6 specified 25.0, which took four seconds on top of the hookup to fill a
## 100 unit tank. Doubled after a playtest: the hookup plus about two seconds of
## filling is roughly three seconds for a full tank, which is long enough to be
## a choice and short enough not to be a wait.
##
## Spraying no longer stops it. The two flows simply net out at 50 in and
## spray_flow_rate out, so a player can stand at a hydrant and fight a fire on
## the other side of the street at 40 units/second of gain.
var hydrant_refill_rate: float = 50.0

## Speed, world units/second, at or below which the truck counts as "nearly
## stationary" for hookup purposes. Raised from 15 to 25 after a playtest: a
## player rolling to a halt with E already held was watching the prompt flicker
## between "Slow down to hook up" and "Hold E to hook up" over the last stretch
## of the stop. 25 is a slow creep, well under a tenth of top speed, and still
## nowhere near "driving past" (handoff §6 asks for nearly stationary, which a
## creep is).
var hydrant_max_hookup_speed: float = 25.0 # invented default, not from handoff

## Radius, world units, within which a hydrant's hookup interaction is
## available, measured from the hydrant to the NEAREST POINT OF THE TRUCK'S
## BODY, not to its centre. The distinction is the whole fix: the truck is 90
## long and 40 wide, so a nose-in stop puts its centre 45 further away than a
## stop alongside does, and the old 48 unit centre rule made a perfectly sane
## nose-in park (measured at 55 from the centre, 10 from the bumper) simply
## fail with no explanation.
##
## 160 comes from the measurements in DEVELOPMENT_STATUS.md rather than from
## taste. Against a hydrant on the kerb face: alongside 0, nose in 0, a sloppy
## 45 degree angle about 30, stopping a truck length short 46, overshooting by
## 160 units of street 115. All well inside. Stopping in the FAR lane of a 280
## unit road is 200 and stays outside, which is the one thing this rule should
## still ask for: pull over to the hydrant's side of the street.
var hydrant_interaction_radius: float = 160.0 # invented default, not from handoff

# ---------------------------------------------------------------------------
# Session (handoff §3)
# ---------------------------------------------------------------------------

## Number of sequential calls per shift. Specified by handoff §3.
var calls_per_shift: int = 3

## Credits earned per completed call. Specified by handoff §3.
var credits_per_call: int = 100

## Bonus credits for completing an entire shift. Specified by handoff §3.
var shift_completion_bonus: int = 50

## Credit cost of the one-time tank capacity upgrade. Specified by handoff §3.
var tank_upgrade_cost: int = 200

## Multiplier applied to tank_capacity once the upgrade is purchased
## (+25% capacity). Specified by handoff §3.
var tank_upgrade_multiplier: float = 1.25

## Truck condition (health) at the start of each shift, on a 0-100 scale.
var truck_starting_condition: float = 100.0 # invented default, not from handoff

## How far, in route units along the roads, the FIRST call of a shift must be
## from the station. Every later call keeps the spacing the candidates were
## imported with and nothing else.
##
## The first call is the one the player has no warm-up for: it arrives the
## instant the shift starts, from a standing start at the station, and a
## candidate a few hundred units up the road is over before the player has
## finished reading the radio line. 2000 route units is about nine seconds at
## the measured door-to-door speed of 220 units/second, which is a drive rather
## than a hop, and is well inside the escalation allowance that same distance
## earns (2000 / escalation_travel_speed is 18 seconds on top of the base 45).
##
## Applied as a preference, not a requirement: if no candidate on a map is that
## far from the station, the farthest one is used rather than the shift failing
## to start. See DispatchManager.order_first_call.
var first_call_min_route: float = 2000.0 # invented default, not from handoff

# ---------------------------------------------------------------------------
# Camera (handoff §4, §7)
# ---------------------------------------------------------------------------

## The zoom levels the development Z key cycles through, wide to wider. Below
## 1.0 means the view takes in MORE world, not less.
##
## THREE LEVELS ON PURPOSE, AND NONE OF THEM IS THE ANSWER YET. James asked to
## be able to cycle them while playing rather than have a number guessed for
## him: the question is whether the view feels like "the area you selected", and
## that is a thing you know by looking, not by arithmetic. The first entry is
## the current behaviour, so nothing changes until a key is pressed. He picks
## after playing; the next milestone pins the choice here and removes the key.
##
## At the 1280 unit design viewport these take in 1422, 1829 and 2327 units of
## world across: about one street, about two, and about a third of Windsor's
## width.
var camera_zoom_levels: Array[float] = [0.9, 0.7, 0.55] # invented default, not from handoff

## The minimap's own zoom levels, cycled by N and by the button in the panel's
## corner. ENTIRELY SEPARATE FROM camera_zoom_levels ABOVE: this changes how
## much of the neighbourhood the little panel shows and never touches the game
## camera, which is the whole point of it having its own control.
##
## 1.0 means the whole map, letterboxed into the panel. Above 1.0 the panel
## shows 1/level of the map's width and height, centred on the engine and
## clamped to the map's own bounds so the panel never shows ground that is not
## there. 4.0 on Windsor is about 1,950 by 1,535 units, which is a couple of
## blocks: close enough to pick the next turning off.
var minimap_zoom_levels: Array[float] = [1.0, 2.0, 4.0] # invented default, not from handoff


# ---------------------------------------------------------------------------
# Traffic signals (handoff §1: "working traffic signals, moving traffic")
# ---------------------------------------------------------------------------

## The fixed signal cycle, seconds. Opposing arms of a junction share a phase,
## so a whole cycle is two of each of these: green, amber, then a moment with
## every arm red before the other phase goes.
##
## Twelve seconds of green is long enough that arriving on a red is a wait a
## player notices and short enough that it is never a wait they resent, and the
## all-red is the ordinary American intergreen: it exists so a junction is never
## green both ways for even a frame.
##
## NOTHING HERE EVER STOPS THE PLAYER. Signals govern traffic; the engine drives
## through a red the way an engine does.
var signal_green_time: float = 12.0 # invented default, not from handoff
var signal_amber_time: float = 3.0 # invented default, not from handoff
var signal_all_red_time: float = 1.0 # invented default, not from handoff


# ---------------------------------------------------------------------------
# Escalation travel allowance (handoff §5, sized in Milestone 4 Part 1)
# ---------------------------------------------------------------------------

## Expected speed, world units/second, used ONLY to turn the distance to a call
## into the extra seconds that call is given before it escalates. Deliberately
## about half the measured driving speed: routes across this map were driven in
## the physics runner at an effective 220 units/second door to door, so dividing
## by 110 hands the player twice the time the drive actually takes.
##
## This is not a speed the truck ever moves at, and nothing simulates it. It is
## the exchange rate between "how far away is this fire" and "how long you get".
var escalation_travel_speed: float = 110.0 # invented default, not from handoff

## Ceiling on that allowance, seconds, so a pathological route on some future
## map cannot hand out an escalation limit measured in minutes.
##
## Raised 90 to 150 in Milestone 5 Part 1. 90 was sized against a 4000 by 3000
## map whose longest call was a 3345 unit drive, so it never bound. The Windsor
## map is 12499 by 9500, and its longer routes run well past the old ceiling,
## which meant the cap and not the drive decided the clock on those calls: every
## distant call got the same number and the rule stopped being proportionate to
## the journey, which is the whole point of it. 150 clears the longest route
## either map actually produces, so the ceiling is once again a guard against a
## future pathological map rather than something today's maps run into.
var escalation_travel_allowance_max: float = 150.0 # invented default, not from handoff
