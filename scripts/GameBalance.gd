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
## Measured against the real thing rather than guessed: a flat-out crash into a
## wall registers about 200 units/second into the normal, so this deals roughly
## 42 of the 100 starting condition. A top speed crash is meant to hurt badly
## without ending the shift outright. At the first draft's 0.6 a single wall
## strike took 85 condition, which made one mistake effectively fatal.
var collision_damage_scale: float = 0.3 # invented default, not from handoff

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

## Seconds from dispatch to incident loss if not extinguished in time.
## Specified by handoff §5.
var fire_escalation_duration: float = 120.0

# ---------------------------------------------------------------------------
# Hydrants (handoff §6)
# ---------------------------------------------------------------------------

## Seconds a held hookup takes before refilling begins. Handoff §6 specified 2.0;
## halved after James playtested the first build and found filling the tank slow
## enough to be dead time rather than a decision. See hydrant_refill_rate.
var hydrant_hookup_time: float = 1.0

## Refill rate once hooked up, water units/second, up to tank capacity. Handoff
## §6 specified 25.0, which took four seconds on top of the hookup to fill a
## 100 unit tank. Doubled for the same playtest reason: one second of hookup
## plus two seconds of filling is about three seconds for a full tank, which is
## long enough to be a choice and short enough not to be a wait. The rules
## around it are untouched: nearly stationary to hook up, any movement cancels,
## and refilling still wins over spraying.
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
