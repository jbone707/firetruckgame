extends Control
class_name Minimap
## The minimap panel in the bottom right of the HUD.
##
## Three layers, because three different things change at three different rates.
##
##  - The ROAD NETWORK is baked once per map into a texture by a SubViewport and
##    then drawn as one textured rectangle. Windsor's network is 42 polylines and
##    the panel is redrawn every frame while the minimap is zoomed in and
##    following the engine; re-stroking those polylines sixty times a second
##    would be the most expensive thing on the HUD, on a project whose next
##    target is a phone. Baked, it is one draw call at any zoom.
##  - THIS node draws that texture and nothing else.
##  - A child Control on top of it carries everything that moves: the hydrants,
##    the engine, the active call, and the rectangle showing what the camera can
##    see.
##
## North up, always. The camera is north up, the off-screen call arrow is
## reasoned about in world space for the same reason, and a minimap that turned
## with the truck would be the only rotating thing in the game.
##
## THE MINIMAP'S ZOOM IS NOT THE CAMERA'S. Nothing in this file touches
## FollowCamera, and nothing here reads the camera's zoom: the panel is given
## the camera's visible rectangle to draw and that is the entire relationship.

## The panel, in the 1280x720 canvas the whole UI is laid out in. The window
## stretch mode is canvas_items with an expand aspect, so at 960x540 this is the
## same 200x150 box drawn at three quarters scale rather than a different layout
## to reason about.
const PANEL_SIZE: Vector2 = Vector2(200.0, 150.0)

const PANEL_COLOR: Color = Color(0.05, 0.07, 0.10, 0.72)
const PANEL_EDGE: Color = Color(0.55, 0.62, 0.70, 0.35)

## Clear space kept between the map drawing and the panel's own edge, so a road
## running along the boundary is not drawn on top of the border.
const PANEL_PADDING: float = 6.0

## How much finer the baked network is than the panel it is drawn into. Four,
## so the deepest zoom level draws the bake at one texel per pixel rather than
## magnifying it. Windsor's bake is 752 by 588 at this factor.
const BAKE_SUPERSAMPLE: float = 4.0

## Road line widths by class, in BAKE pixels, so they come out at
## width / BAKE_SUPERSAMPLE on the panel at the whole-map zoom. Deliberately
## thin: this is a diagram of the network, not a small copy of the map, and at
## this size anything thicker turns a junction into a blob.
const ROAD_WIDTH_MINOR: float = 4.0
const ROAD_WIDTH_MAJOR: float = 8.0
const ROAD_COLOR: Color = Color(0.62, 0.66, 0.70, 0.85)

## Classes drawn thick. Everything else is drawn thin, including a road with no
## class at all, which is what the fictional map's roads are.
const MAJOR_CLASSES: Array = ["primary", "secondary", "tertiary", "trunk", "motorway"]

const HYDRANT_COLOR: Color = Color(0.85, 0.35, 0.28, 0.9)
const HYDRANT_RADIUS: float = 1.6

const TRUCK_COLOR: Color = Color(1.0, 0.94, 0.88)
const TRUCK_EDGE: Color = Color(0.12, 0.10, 0.10, 0.9)
const TRUCK_LENGTH: float = 9.0
const TRUCK_WIDTH: float = 6.5

const CALL_COLOR: Color = Color(1.0, 0.58, 0.20)
const CALL_RADIUS: float = 3.4
## How far the call marker's ring swells and how fast, so it reads as the one
## thing on the panel asking to be looked at.
const CALL_PULSE_RADIUS: float = 4.0
const CALL_PULSE_RATE: float = 3.4
## The marker drawn at the panel's edge when the call is outside what the panel
## is showing, which the whole-map zoom can never need and the closer ones can.
const CALL_EDGE_SIZE: float = 5.0
const CALL_EDGE_INSET: float = 3.0

## The camera's own view, drawn as an outline so the player can see which piece
## of the network is the piece they are looking at.
const VIEW_COLOR: Color = Color(0.95, 0.97, 1.0, 0.28)
const VIEW_WIDTH: float = 1.0

## The zoom button in the panel's corner. Small, because it is a corner of a
## corner of the screen, and it says which level it is on rather than only
## carrying an icon: "2x" is a state as well as a control.
const BUTTON_SIZE: Vector2 = Vector2(26.0, 18.0)
const BUTTON_MARGIN: float = 4.0
const BUTTON_FONT_SIZE: int = 11

var balance: Node = null

## Set from MapDefinition at load. Empty until configure() is called, and
## everything that maps a world point checks it, so a minimap on a scene that
## never got a map draws its panel and nothing else rather than dividing by zero.
var _world_bounds: Rect2 = Rect2()

## The letterboxed box inside the panel the map is actually drawn in. The map's
## aspect is preserved, so Windsor's 7,820 by 6,140 does not come out stretched
## to the panel's 4:3. Fixed for a map: the ZOOM changes which piece of the world
## is shown in this box, never the box.
var _content: Rect2 = Rect2()

## The piece of the world the panel is currently showing. The whole map at zoom
## level 1.0; a window centred on the engine and clamped to the map above that.
var _view: Rect2 = Rect2()

var _zoom_index: int = 0

var _truck_position: Vector2 = Vector2.ZERO
var _truck_rotation: float = 0.0
var _call_position: Vector2 = Vector2.ZERO
var _call_active: bool = false
var _camera_rect: Rect2 = Rect2()
var _hydrants: PackedVector2Array = PackedVector2Array()
var _pulse: float = 0.0

var _overlay: Control
var _button: Button
var _bake_viewport: SubViewport
var _bake_canvas: Node2D
var _bake_roads: Array[Dictionary] = []


func resolve_balance() -> void:
	if balance != null:
		return
	balance = get_node_or_null("/root/GameBalance")
	if balance == null:
		balance = load("res://scripts/GameBalance.gd").new()


func _ready() -> void:
	resolve_balance()
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_overlay = Control.new()
	_overlay.name = "MinimapOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	# The one thing on the HUD a player can click. It has to STOP the mouse, or
	# it is a picture of a button; Main separately refuses to spray while the
	# pointer is over this panel, because the spray action is polled from Input
	# and does not care what the GUI did with the click.
	_button = Button.new()
	_button.name = "MinimapZoomButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.size = BUTTON_SIZE
	_button.custom_minimum_size = BUTTON_SIZE
	_button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	# Positioned outright, with no anchor preset. PRESET_TOP_RIGHT makes
	# position relative to the parent's right edge, so setting it to
	# "size.x - width - margin" as well put the button a whole panel width
	# outside the panel, in the middle of the screen.
	_button.position = Vector2(size.x - BUTTON_SIZE.x - BUTTON_MARGIN, BUTTON_MARGIN)
	# Styled to the HUD rather than left on Godot's default, which on a dark
	# panel reads as an editor widget somebody forgot to take out. Flat, dark,
	# the same corner radius as the top-right HUD backing.
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.10, 0.13, 0.17, 0.85)
		if state == "hover":
			box.bg_color = Color(0.16, 0.21, 0.27, 0.92)
		elif state == "pressed":
			box.bg_color = Color(0.24, 0.31, 0.38, 0.95)
		box.border_color = PANEL_EDGE
		box.set_border_width_all(1)
		box.set_corner_radius_all(4)
		_button.add_theme_stylebox_override(state, box)
	_button.add_theme_color_override("font_color", Color(0.86, 0.90, 0.94))
	_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	_button.pressed.connect(cycle_zoom)
	add_child(_button)
	_update_button_text()


## Everything that comes off the map, taken once at load.
##
## The road classes come from the same "highway" key the importer writes, and a
## road without one is drawn thin. That is the fictional map's whole network, by
## design: it has no classes, and a grid of equal streets is what it is.
func configure(definition: MapDefinition, hydrants: Array) -> void:
	resolve_balance()
	_world_bounds = definition.world_bounds

	_bake_roads.clear()
	for road in definition.roads:
		var points: PackedVector2Array = road["points"]
		if points.size() < 2:
			continue
		_bake_roads.append({
			"points": points,
			"width": (
				ROAD_WIDTH_MAJOR
				if MAJOR_CLASSES.has(String(road.get("highway", "")))
				else ROAD_WIDTH_MINOR
			),
		})

	_hydrants = PackedVector2Array()
	for hydrant in hydrants:
		_hydrants.append(Vector2(hydrant["position"]))

	_recompute_content()
	_rebake()
	_recompute_view()
	queue_redraw()


## The letterbox. Called on configure and whenever the panel is resized, because
## a Control's size is not final until the containers above it have laid out.
func _recompute_content() -> void:
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		_content = Rect2()
		return
	var inner := Vector2(
		maxf(size.x - PANEL_PADDING * 2.0, 1.0), maxf(size.y - PANEL_PADDING * 2.0, 1.0)
	)
	var fit: float = minf(inner.x / _world_bounds.size.x, inner.y / _world_bounds.size.y)
	var drawn: Vector2 = _world_bounds.size * fit
	_content = Rect2(Vector2(PANEL_PADDING, PANEL_PADDING) + (inner - drawn) / 2.0, drawn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recompute_content()
		_recompute_view()
		if _button != null:
			_button.position = Vector2(size.x - BUTTON_SIZE.x - BUTTON_MARGIN, BUTTON_MARGIN)
		queue_redraw()


# ---------------------------------------------------------------------------
# Zoom. The minimap's own, and nothing else's.
# ---------------------------------------------------------------------------

func get_zoom_levels() -> Array:
	resolve_balance()
	if balance == null or balance.minimap_zoom_levels.is_empty():
		return [1.0]
	return balance.minimap_zoom_levels


func get_zoom() -> float:
	var levels: Array = get_zoom_levels()
	return float(levels[_zoom_index % levels.size()])


func get_zoom_index() -> int:
	return _zoom_index


## Moves to the next level and returns it. Touches nothing but this panel.
func cycle_zoom() -> float:
	var levels: Array = get_zoom_levels()
	_zoom_index = (_zoom_index + 1) % levels.size()
	_update_button_text()
	_recompute_view()
	queue_redraw()
	return get_zoom()


func set_zoom_index(index: int) -> void:
	var levels: Array = get_zoom_levels()
	_zoom_index = index % levels.size()
	_update_button_text()
	_recompute_view()
	queue_redraw()


func _update_button_text() -> void:
	if _button == null:
		return
	_button.text = "%sx" % String.num(get_zoom(), 0 if is_equal_approx(get_zoom(), roundf(get_zoom())) else 1)


## Which piece of the world the panel shows.
##
## At the whole-map level it is the map. Above that it is a window 1/level of
## the map's size, centred on the engine, then pushed back inside the map's own
## bounds, so a truck in a corner sees the corner rather than half a panel of
## nothing. That clamp is why the engine is NOT always at the panel's centre,
## and the unit check says so in those words.
func _recompute_view() -> void:
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		_view = Rect2()
		return
	var zoom: float = maxf(get_zoom(), 1.0)
	if is_equal_approx(zoom, 1.0):
		_view = _world_bounds
		return
	var window: Vector2 = _world_bounds.size / zoom
	var top_left: Vector2 = _truck_position - window / 2.0
	top_left.x = clampf(top_left.x, _world_bounds.position.x, _world_bounds.end.x - window.x)
	top_left.y = clampf(top_left.y, _world_bounds.position.y, _world_bounds.end.y - window.y)
	_view = Rect2(top_left, window)


## Where a world point lands on the panel, in this Control's own coordinates.
##
## The one function everything drawn here goes through, and the one the unit
## checks assert against: at the whole-map zoom the map's four corners land on
## the four corners of the letterboxed box, and at the deepest zoom the engine
## lands at the box's centre except where the clamp above has pushed the view
## against a map edge.
func world_to_panel(world: Vector2) -> Vector2:
	if _view.size.x <= 0.0 or _view.size.y <= 0.0:
		return _content.get_center()
	var unit: Vector2 = (world - _view.position) / _view.size
	return _content.position + unit * _content.size


## The letterboxed box the map is drawn in, for the checks and for the layout.
func get_content_rect() -> Rect2:
	return _content


## The piece of the world currently on the panel.
func get_view_rect() -> Rect2:
	return _view


func get_zoom_button() -> Button:
	return _button


func set_truck(world_position: Vector2, rotation_radians: float) -> void:
	_truck_position = world_position
	_truck_rotation = rotation_radians
	# Above the whole-map level the panel follows the engine, so the view has to
	# be recomputed with it.
	if not is_equal_approx(get_zoom(), 1.0):
		_recompute_view()
		queue_redraw()


func set_call(world_position: Vector2, active: bool) -> void:
	_call_position = world_position
	_call_active = active


## The rectangle of world the camera can currently see, so the player can place
## what is on screen inside what is on the map.
func set_view_rect(world_rect: Rect2) -> void:
	_camera_rect = world_rect


## Only the overlay is redrawn per frame. The road texture is one rectangle and
## is redrawn only when the view moves under it.
func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	if _overlay != null:
		_overlay.queue_redraw()


# ---------------------------------------------------------------------------
# The baked road network
# ---------------------------------------------------------------------------

## Strokes the whole network once, into a SubViewport, at BAKE_SUPERSAMPLE times
## the panel's own resolution. Everything after this is one textured rectangle.
##
## A headless run has no real rasteriser, so the texture comes back empty there.
## Nothing asserts on its pixels for that reason; what the checks assert is the
## mapping, which is arithmetic and is the same in both.
func _rebake() -> void:
	if _bake_viewport == null:
		_bake_viewport = SubViewport.new()
		_bake_viewport.name = "MinimapBake"
		_bake_viewport.transparent_bg = true
		_bake_viewport.disable_3d = true
		_bake_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(_bake_viewport)
		_bake_canvas = Node2D.new()
		_bake_canvas.name = "MinimapBakeCanvas"
		_bake_canvas.draw.connect(_draw_bake)
		_bake_viewport.add_child(_bake_canvas)

	if _content.size.x <= 0.0 or _content.size.y <= 0.0:
		return
	_bake_viewport.size = Vector2i(
		maxi(int(round(_content.size.x * BAKE_SUPERSAMPLE)), 1),
		maxi(int(round(_content.size.y * BAKE_SUPERSAMPLE)), 1)
	)
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_bake_canvas.queue_redraw()


## World to BAKE texel. The bake always covers the WHOLE map, whatever the zoom
## is: zoom is applied when the texture is sampled, not when it is drawn.
func _world_to_bake(world: Vector2) -> Vector2:
	var unit: Vector2 = (world - _world_bounds.position) / _world_bounds.size
	return unit * Vector2(_bake_viewport.size)


func _draw_bake() -> void:
	if _world_bounds.size.x <= 0.0 or _world_bounds.size.y <= 0.0:
		return
	for road in _bake_roads:
		var mapped := PackedVector2Array()
		for point in road["points"]:
			mapped.append(_world_to_bake(point))
		if mapped.size() >= 2:
			_bake_canvas.draw_polyline(mapped, ROAD_COLOR, float(road["width"]), true)


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, PANEL_COLOR, true)
	draw_rect(panel, PANEL_EDGE, false, 1.0)

	if _content.size.x <= 0.0 or _bake_viewport == null:
		return
	var texture: Texture2D = _bake_viewport.get_texture()
	if texture == null:
		return

	# The piece of the bake the current view is looking at. At the whole-map
	# zoom that is all of it; higher up it is a window that pans with the engine.
	var texture_size := Vector2(_bake_viewport.size)
	var origin: Vector2 = (_view.position - _world_bounds.position) / _world_bounds.size
	var extent: Vector2 = _view.size / _world_bounds.size
	draw_texture_rect_region(
		texture, _content, Rect2(origin * texture_size, extent * texture_size)
	)


func _draw_overlay() -> void:
	if _view.size.x <= 0.0:
		return

	# Hydrants. Drawn here rather than baked so the dots stay the same size on
	# the panel at every zoom instead of swelling with it.
	for hydrant in _hydrants:
		if _view.has_point(hydrant):
			_overlay.draw_circle(world_to_panel(hydrant), HYDRANT_RADIUS, HYDRANT_COLOR)

	# What the camera can see. Drawn before the engine and the call so they sit
	# on top of it rather than being crossed by its lines. Clipped to the map, so
	# a camera overscanning past the world edge does not draw out over the border.
	if _camera_rect.size.x > 0.0 and _camera_rect.size.y > 0.0:
		var top_left: Vector2 = world_to_panel(_camera_rect.position)
		var bottom_right: Vector2 = world_to_panel(_camera_rect.end)
		var drawn := Rect2(top_left, bottom_right - top_left).intersection(_content)
		if drawn.size.x > 0.0 and drawn.size.y > 0.0:
			_overlay.draw_rect(drawn, VIEW_COLOR, false, VIEW_WIDTH)

	if _call_active:
		if _view.has_point(_call_position):
			_draw_call_marker(world_to_panel(_call_position))
		else:
			_draw_call_at_the_edge()

	# The engine: a triangle pointing where it is pointing, which is the one
	# thing a dot cannot say.
	var at: Vector2 = world_to_panel(_truck_position)
	var forward: Vector2 = Vector2.RIGHT.rotated(_truck_rotation)
	var side := Vector2(-forward.y, forward.x)
	var nose: Vector2 = at + forward * (TRUCK_LENGTH * 0.62)
	var tail: Vector2 = at - forward * (TRUCK_LENGTH * 0.38)
	var triangle := PackedVector2Array([
		nose, tail + side * (TRUCK_WIDTH * 0.5), tail - side * (TRUCK_WIDTH * 0.5),
	])
	_overlay.draw_colored_polygon(triangle, TRUCK_COLOR)
	_overlay.draw_polyline(
		PackedVector2Array([triangle[0], triangle[1], triangle[2], triangle[0]]),
		TRUCK_EDGE, 1.0, true
	)


func _draw_call_marker(at: Vector2) -> void:
	var swell: float = sin(_pulse * CALL_PULSE_RATE) * 0.5 + 0.5
	_overlay.draw_arc(
		at, CALL_RADIUS + CALL_PULSE_RADIUS * swell, 0.0, TAU, 20,
		Color(CALL_COLOR, 0.85 * (1.0 - swell * 0.6)), 1.4, true
	)
	_overlay.draw_circle(at, CALL_RADIUS, CALL_COLOR)


## The call is off the panel, which only the zoomed-in levels can manage. A
## triangle on the border, pointing out of the panel the way the call lies, in
## the same orange as the marker it stands in for.
func _draw_call_at_the_edge() -> void:
	var inner: Rect2 = _content.grow(-CALL_EDGE_INSET)
	var centre: Vector2 = _content.get_center()
	var direction: Vector2 = (_call_position - _view.get_center()).normalized()
	if direction == Vector2.ZERO:
		return

	# How far along that direction the panel's own border is: the smaller of the
	# two axis crossings, which is the box's edge in that direction.
	var half: Vector2 = inner.size / 2.0
	var reach: float = INF
	if absf(direction.x) > 0.0001:
		reach = minf(reach, half.x / absf(direction.x))
	if absf(direction.y) > 0.0001:
		reach = minf(reach, half.y / absf(direction.y))
	if is_inf(reach):
		return

	var at: Vector2 = centre + direction * reach
	var side := Vector2(-direction.y, direction.x)
	_overlay.draw_colored_polygon(
		PackedVector2Array([
			at + direction * CALL_EDGE_SIZE * 0.6,
			at - direction * CALL_EDGE_SIZE * 0.5 + side * CALL_EDGE_SIZE * 0.5,
			at - direction * CALL_EDGE_SIZE * 0.5 - side * CALL_EDGE_SIZE * 0.5,
		]),
		CALL_COLOR
	)
