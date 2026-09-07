extends CanvasLayer
class_name GameUI
## The HUD, the start screen, the results screen and the shop.
##
## Built in code rather than hand-written into a .tscn so every anchor and
## container is explicit and reviewable in one place. Everything is anchored or
## in a container, nothing is positioned at a fixed pixel, so the layout holds
## at both wide and narrow landscape sizes (handoff section 8).
##
## Colour is never the only carrier of meaning: every bar has a label beside it
## and every state has a sentence (handoff section 6).

signal start_shift_pressed
signal open_shop_pressed
signal close_shop_pressed
signal buy_upgrade_pressed

const PANEL_WIDTH: float = 460.0
const BAR_SIZE: Vector2 = Vector2(190.0, 18.0)
const EDGE_MARGIN: float = 18.0

## Seconds of margin below which the countdown starts shouting.
const URGENT_SECONDS: float = 30.0


var _hud: Control
var _condition_bar: ProgressBar
var _condition_label: Label
var _water_bar: ProgressBar
var _water_label: Label
var _call_label: Label
var _margin_label: Label
var _credits_label: Label
var _prompt_label: Label
var _siren_label: Label

var _menu_panel: Control
var _menu_start_button: Button
var _results_panel: Control
var _results_title: Label
var _results_detail: Label
var _shop_panel: Control
var _shop_status: Label
var _shop_owned: Label
var _buy_button: Button
var _results_shop_button: Button
var _shop_back_button: Button

var _arrow: Control
var _arrow_direction: Vector2 = Vector2.ZERO
var _arrow_position: Vector2 = Vector2.ZERO
var _arrow_visible: bool = false
var _margin_urgent: bool = false


func _ready() -> void:
	layer = 5
	_build_hud()
	_build_menu_panel()
	_build_results_panel()
	_build_shop_panel()
	show_menu()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _full_rect(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_label(text: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


## The small all-caps eyebrow used above each readout.
func _make_eyebrow(text: String) -> Label:
	var label := _make_label(text.to_upper(), 11)
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.85))
	return label


func _make_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	return bar


func _build_hud() -> void:
	_hud = Control.new()
	_hud.name = "Hud"
	_full_rect(_hud)
	add_child(_hud)

	# Top left: condition and water, each a bar with its own readable value.
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.position = Vector2(EDGE_MARGIN, EDGE_MARGIN)
	left.add_theme_constant_override("separation", 6)
	_hud.add_child(left)

	left.add_child(_make_eyebrow("Engine condition"))
	var condition_row := HBoxContainer.new()
	condition_row.add_theme_constant_override("separation", 10)
	_condition_bar = _make_bar()
	_condition_label = _make_label("100")
	condition_row.add_child(_condition_bar)
	condition_row.add_child(_condition_label)
	left.add_child(condition_row)

	left.add_child(_make_eyebrow("Water"))
	var water_row := HBoxContainer.new()
	water_row.add_theme_constant_override("separation", 10)
	_water_bar = _make_bar()
	_water_label = _make_label("100")
	water_row.add_child(_water_bar)
	water_row.add_child(_water_label)
	left.add_child(water_row)

	# Top right: the call, the margin left on it, and the bank.
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position = Vector2(-EDGE_MARGIN, EDGE_MARGIN)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 4)
	_hud.add_child(right)

	_call_label = _make_label("Call 1 of 3", 18)
	_call_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_margin_label = _make_label("Time left 2:00")
	_margin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label = _make_label("Credits 0")
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_siren_label = _make_label("Siren off")
	_siren_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_call_label)
	right.add_child(_margin_label)
	right.add_child(_credits_label)
	right.add_child(_siren_label)

	# Bottom centre: the one contextual prompt line.
	_prompt_label = _make_label("", 18)
	_prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_label.position = Vector2(0.0, -70.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_prompt_label)

	# The off-screen incident indicator draws itself over the whole HUD.
	_arrow = Control.new()
	_arrow.name = "IncidentArrow"
	_full_rect(_arrow)
	_arrow.draw.connect(_draw_arrow)
	_hud.add_child(_arrow)


func _make_panel(title_text: String) -> Array:
	var root := Control.new()
	_full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.05, 0.08, 0.82)
	root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var panel := PanelContainer.new()
	centre.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 34)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 26)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)

	var title := _make_label(title_text, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	return [root, rows, title]


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	return button


func _build_menu_panel() -> void:
	var built: Array = _make_panel("Fire Truck Game")
	_menu_panel = built[0]
	var rows: VBoxContainer = built[1]

	var blurb := _make_label(
		"Drive to each call, put the fire out before it gets away, and refill at a hydrant"
		+ " when the tank runs low. Three calls to a shift."
	)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(blurb)

	_menu_start_button = _make_button("Start shift")
	_menu_start_button.pressed.connect(func() -> void: start_shift_pressed.emit())
	rows.add_child(_menu_start_button)

	var controls := _make_label(
		"W or up drives, S or down brakes then reverses, A and D steer."
		+ " Space is a harder brake, Q toggles the lights, left mouse sprays,"
		+ " hold E at a hydrant to refill, Escape pauses.",
		13
	)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(controls)


func _build_results_panel() -> void:
	var built: Array = _make_panel("Shift Over")
	_results_panel = built[0]
	var rows: VBoxContainer = built[1]
	_results_title = built[2]

	_results_detail = _make_label("")
	_results_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_results_detail)

	_results_shop_button = _make_button("Open the shop")
	_results_shop_button.pressed.connect(func() -> void: open_shop_pressed.emit())
	rows.add_child(_results_shop_button)

	var again_button: Button = _make_button("Start another shift")
	again_button.pressed.connect(func() -> void: start_shift_pressed.emit())
	rows.add_child(again_button)


func _build_shop_panel() -> void:
	var built: Array = _make_panel("Shop")
	_shop_panel = built[0]
	var rows: VBoxContainer = built[1]

	var description := _make_label(
		"Bigger tank. Adds 25 percent to your water capacity, permanently."
		+ " It applies from your next shift."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(description)

	_shop_owned = _make_label("")
	rows.add_child(_shop_owned)

	_buy_button = _make_button("Buy bigger tank")
	_buy_button.pressed.connect(func() -> void: buy_upgrade_pressed.emit())
	rows.add_child(_buy_button)

	_shop_status = _make_label("")
	_shop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_shop_status)

	_shop_back_button = _make_button("Back")
	_shop_back_button.pressed.connect(func() -> void: close_shop_pressed.emit())
	rows.add_child(_shop_back_button)


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

func show_menu() -> void:
	_hud.visible = false
	_menu_panel.visible = true
	_results_panel.visible = false
	_shop_panel.visible = false
	_focus(_menu_start_button)


func show_playing() -> void:
	_hud.visible = true
	_menu_panel.visible = false
	_results_panel.visible = false
	_shop_panel.visible = false


func show_results(succeeded: bool, reason: String, earned: int, total: int) -> void:
	_hud.visible = false
	_menu_panel.visible = false
	_results_panel.visible = true
	_shop_panel.visible = false
	_results_title.text = "Shift Complete" if succeeded else "Shift Over"
	_results_detail.text = "%s. You earned %d credits this shift, and have %d." % [
		reason, earned, total
	]
	_focus(_results_shop_button)


func show_shop(credits: int, owned: bool, cost: int, status: String) -> void:
	_hud.visible = false
	_menu_panel.visible = false
	_results_panel.visible = false
	_shop_panel.visible = true
	_shop_owned.text = (
		"Owned. Your tank is already the bigger one." if owned
		else "Cost %d credits. You have %d." % [cost, credits]
	)
	_buy_button.disabled = owned or credits < cost
	_shop_status.text = status
	_focus(_shop_back_button if _buy_button.disabled else _buy_button)


# ---------------------------------------------------------------------------
# HUD updates
# ---------------------------------------------------------------------------

func set_condition(condition: float, max_condition: float) -> void:
	_condition_bar.value = 0.0 if max_condition <= 0.0 else condition / max_condition
	_condition_label.text = str(int(round(condition)))


func set_water(remaining: float, capacity: float) -> void:
	_water_bar.value = 0.0 if capacity <= 0.0 else remaining / capacity
	_water_label.text = str(int(round(remaining)))


func set_call(call_number: int, total_calls: int) -> void:
	_call_label.text = "Call %d of %d" % [call_number, total_calls]


## The escalation countdown. Under URGENT_SECONDS it says so in words and grows,
## because a player watching the road is not reading a colour, and colour alone
## is never the carrier of state in this HUD (handoff section 6).
func set_margin_seconds(seconds: float) -> void:
	if seconds <= 0.0:
		_margin_label.text = "Time left none"
		_set_margin_urgent(true)
		return
	var clock: String = "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]
	var urgent: bool = seconds < URGENT_SECONDS
	_margin_label.text = "Time left %s, running out" % clock if urgent else "Time left %s" % clock
	_set_margin_urgent(urgent)


func _set_margin_urgent(urgent: bool) -> void:
	if _margin_urgent == urgent:
		return
	_margin_urgent = urgent
	_margin_label.add_theme_font_size_override("font_size", 20 if urgent else 15)


func set_credits(credits: int) -> void:
	_credits_label.text = "Credits %d" % credits


func set_siren(active: bool) -> void:
	_siren_label.text = "Siren on" if active else "Siren off"


func set_prompt(text: String) -> void:
	_prompt_label.text = text


## Takes an IncidentIndicator.evaluate() result: whether to show the arrow, the
## screen-space unit vector it points along, and the screen position it sits at.
## The HUD does no geometry of its own; it only draws what it is handed.
func set_incident_indicator(state: Dictionary) -> void:
	_arrow_visible = bool(state.get("shown", false))
	_arrow_direction = state.get("direction", Vector2.ZERO)
	_arrow_position = state.get("position", Vector2.ZERO)
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	if not _arrow_visible or not _hud.visible:
		return
	var tip: Vector2 = _arrow_position
	var angle: float = _arrow_direction.angle()
	var points := PackedVector2Array([
		tip + Vector2(20.0, 0.0).rotated(angle),
		tip + Vector2(-14.0, 12.0).rotated(angle),
		tip + Vector2(-14.0, -12.0).rotated(angle),
	])
	_arrow.draw_colored_polygon(points, Color(1.0, 0.55, 0.2, 0.95))
	_arrow.draw_string(
		ThemeDB.fallback_font,
		tip + Vector2(-18.0, 30.0),
		"Call",
		HORIZONTAL_ALIGNMENT_CENTER,
		36.0,
		13
	)


## Moves keyboard focus to the first thing a panel wants pressed, so every
## screen is operable without a mouse and Tab starts somewhere sensible. Focus
## can only be grabbed once a control is inside the tree, which is why this is
## guarded rather than called during construction.
func _focus(control: Control) -> void:
	if control == null or not control.is_inside_tree():
		return
	control.grab_focus()
