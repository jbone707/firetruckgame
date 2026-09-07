extends RefCounted
class_name IncidentIndicator
## Pure screen-space geometry for the off-screen call arrow (handoff section 7).
##
## Kept as static functions with no node dependencies so the maths can be tested
## by the fast unit runner as well as end to end by the physics runner.
##
## The camera is north up (FollowCamera keeps rotation at zero and sets
## ignore_rotation), so a world-space direction already IS the screen-space
## direction. Nothing here takes a truck or camera rotation, and nothing here
## should ever start taking one: the moment a rotation term appears in this
## file, the arrow points somewhere the player is not looking.

## How far inside the viewport edge the arrow is drawn, world pixels. Large
## enough that the whole glyph and its label stay on screen.
const ARROW_INSET: float = 54.0

## How far inside the viewport edge an incident still counts as on screen. Small
## on purpose: the arrow should hand over to the destination marker as soon as
## the fire is genuinely visible, not while it is still well inside the frame.
const VISIBILITY_MARGIN: float = 24.0


## Where a world point lands on screen under a north-up camera centred on
## camera_centre. This is the same mapping the engine's canvas transform
## performs; the game reads the real transform, and this exists so the unit
## suite can produce screen points without booting a scene.
static func world_to_screen(
	world_position: Vector2, camera_centre: Vector2, view_size: Vector2
) -> Vector2:
	return world_position - camera_centre + view_size * 0.5


## The "no arrow at all" answer, for when there is no active call to point at.
static func hidden() -> Dictionary:
	return {"shown": false, "direction": Vector2.ZERO, "position": Vector2.ZERO}


## Decides whether the arrow is shown, which way it points, and where it sits.
##
## Returns { "shown": bool, "direction": Vector2, "position": Vector2 }.
## direction is a unit vector from the middle of the screen toward the incident,
## and position is where the ray from the middle of the screen leaves the
## viewport, pulled in by ARROW_INSET. Both are meaningless when shown is false.
static func evaluate(
	screen_point: Vector2, view_rect: Rect2, margin: float = VISIBILITY_MARGIN
) -> Dictionary:
	var centre: Vector2 = view_rect.position + view_rect.size * 0.5
	var visible_rect: Rect2 = view_rect.grow(-margin)
	var from_centre: Vector2 = screen_point - centre

	if visible_rect.has_point(screen_point) or from_centre.length_squared() < 1.0:
		return {"shown": false, "direction": Vector2.ZERO, "position": centre}

	var direction: Vector2 = from_centre.normalized()
	return {
		"shown": true,
		"direction": direction,
		"position": _edge_position(centre, direction, view_rect, ARROW_INSET),
	}


## Walks out from centre along direction until the inset rectangle's border is
## reached, so the arrow sits on the edge of the screen on the line to the
## incident rather than at a fixed HUD corner.
static func _edge_position(
	centre: Vector2, direction: Vector2, view_rect: Rect2, inset: float
) -> Vector2:
	var half: Vector2 = view_rect.size * 0.5 - Vector2(inset, inset)
	half.x = maxf(half.x, 1.0)
	half.y = maxf(half.y, 1.0)

	var travel: float = INF
	if absf(direction.x) > 0.0001:
		travel = minf(travel, half.x / absf(direction.x))
	if absf(direction.y) > 0.0001:
		travel = minf(travel, half.y / absf(direction.y))
	if travel == INF:
		return centre
	return centre + direction * travel
