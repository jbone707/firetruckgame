extends "res://tests/test_case.gd"
## The off-screen call arrow's geometry (handoff section 7).
##
## The bug these cover: the arrow pointed at the north-west corner of the map no
## matter where the fire was, and never hid once the fire was on screen, because
## every FireIncident node was left standing at the world origin while its
## outline was drawn in world coordinates by a child. See
## test_the_indicator_ignores_the_direction_it_is_looked_at_from for the part
## that pins the direction itself down.

const VIEW_SIZE: Vector2 = Vector2(1280.0, 720.0)
const CAMERA: Vector2 = Vector2(2000.0, 1500.0)

## Far enough out that the point is off screen in every case below.
const FAR: float = 4000.0

const COMPASS: Dictionary = {
	"east": Vector2(1.0, 0.0),
	"north": Vector2(0.0, -1.0),
	"west": Vector2(-1.0, 0.0),
	"south": Vector2(0.0, 1.0),
}


func _view_rect() -> Rect2:
	return Rect2(Vector2.ZERO, VIEW_SIZE)


## Screen-space direction is a property of the world and the camera, never of
## which way the truck happens to be facing. The camera is north up, so an
## incident due east is to the right of the screen whether the player is driving
## east, north or west at the time. The three headings below are the truck's;
## none of them may change a single answer.
func test_the_indicator_ignores_the_direction_it_is_looked_at_from() -> void:
	var first_answers: Dictionary = {}

	for heading in [0.0, PI * 0.5, PI]:
		for name in COMPASS:
			var compass: Vector2 = COMPASS[name]
			var world: Vector2 = CAMERA + compass * FAR
			var screen: Vector2 = IncidentIndicator.world_to_screen(world, CAMERA, VIEW_SIZE)
			var state: Dictionary = IncidentIndicator.evaluate(screen, _view_rect())

			assert_true(
				state["shown"],
				"%s at %d units is off screen and must show the arrow" % [name, FAR]
			)
			assert_almost_eq(
				state["direction"].x, compass.x, 0.0001,
				"%s arrow x at truck heading %.2f" % [name, heading]
			)
			assert_almost_eq(
				state["direction"].y, compass.y, 0.0001,
				"%s arrow y at truck heading %.2f" % [name, heading]
			)

			if not first_answers.has(name):
				first_answers[name] = state["direction"]
			assert_true(
				first_answers[name].is_equal_approx(state["direction"]),
				"%s must give the same arrow at heading %.2f as at heading 0" % [name, heading]
			)


func test_an_incident_on_screen_shows_no_arrow() -> void:
	var centre: Vector2 = VIEW_SIZE * 0.5
	for offset in [Vector2.ZERO, Vector2(300.0, 0.0), Vector2(0.0, -200.0), Vector2(-400.0, 150.0)]:
		var state: Dictionary = IncidentIndicator.evaluate(centre + offset, _view_rect())
		assert_false(
			state["shown"],
			"a point %s from the middle of the screen is on screen" % offset
		)
		assert_eq(state["direction"], Vector2.ZERO, "a hidden arrow has no direction")


func test_the_arrow_appears_just_outside_the_visible_rect() -> void:
	var margin: float = IncidentIndicator.VISIBILITY_MARGIN
	var view: Rect2 = _view_rect()
	var centre: Vector2 = VIEW_SIZE * 0.5

	var inside := Vector2(VIEW_SIZE.x - margin - 4.0, centre.y)
	assert_false(
		IncidentIndicator.evaluate(inside, view)["shown"],
		"a point inside the margin still counts as on screen"
	)

	var outside := Vector2(VIEW_SIZE.x - margin + 4.0, centre.y)
	var state: Dictionary = IncidentIndicator.evaluate(outside, view)
	assert_true(state["shown"], "a point outside the margin shows the arrow")
	assert_almost_eq(state["direction"].x, 1.0, 0.0001, "that point is due right")


## The arrow belongs on the screen edge along the line to the fire, not in a
## fixed HUD corner, so its position has to sit on the inset border and on the
## ray at the same time.
func test_the_arrow_sits_on_the_screen_edge_along_the_line_to_the_call() -> void:
	var view: Rect2 = _view_rect()
	var centre: Vector2 = VIEW_SIZE * 0.5
	var inset: float = IncidentIndicator.ARROW_INSET

	for direction in [
		Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0),
		Vector2(1.0, -1.0).normalized(), Vector2(-0.6, 0.8).normalized(),
	]:
		var state: Dictionary = IncidentIndicator.evaluate(centre + direction * FAR, view)
		var position: Vector2 = state["position"]

		assert_true(
			(position - centre).normalized().is_equal_approx(direction),
			"the arrow for %s must sit on the ray from the middle of the screen" % direction
		)

		var from_centre: Vector2 = position - centre
		var on_border: bool = (
			absf(absf(from_centre.x) - (VIEW_SIZE.x * 0.5 - inset)) < 0.01
			or absf(absf(from_centre.y) - (VIEW_SIZE.y * 0.5 - inset)) < 0.01
		)
		assert_true(on_border, "the arrow for %s must touch the inset screen edge" % direction)
		assert_true(view.has_point(position), "the arrow for %s must stay on screen" % direction)


func test_no_call_means_no_arrow() -> void:
	var state: Dictionary = IncidentIndicator.hidden()
	assert_false(state["shown"], "with no active call there is nothing to point at")
	assert_eq(state["direction"], Vector2.ZERO, "a hidden arrow has no direction")
