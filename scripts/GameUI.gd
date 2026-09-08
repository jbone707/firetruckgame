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
signal open_map_select_pressed
signal open_credits_pressed
signal map_chosen(map_id: String)
signal back_pressed
signal quit_pressed

const PANEL_WIDTH: float = 460.0
const BAR_SIZE: Vector2 = Vector2(190.0, 18.0)
const EDGE_MARGIN: float = 18.0

## Backing behind the top-right HUD column, so a street name painted on the
## asphalt can never tangle with the numbers drawn over it. Dark and mostly
## opaque: the HUD has to win against whatever the map puts behind it.
const HUD_BACKING_COLOR: Color = Color(0.05, 0.07, 0.10, 0.72)

## Clear space between the rows of that column, world pixels. Four was too tight
## for the urgent line to breathe in even before it grew.
const HUD_ROW_SEPARATION: int = 8

## Seconds of margin below which the countdown starts shouting.
const URGENT_SECONDS: float = 30.0

## How far the prompt line's band is pulled in from each side, so it can never
## run under the minimap in the bottom right corner. The minimap's own width
## plus both margins, applied to both sides so the line stays centred.
const PROMPT_SIDE_INSET: float = Minimap.PANEL_SIZE.x + EDGE_MARGIN * 2.0

## Where the bottom of the prompt band sits above the bottom of the screen, and
## how tall it is. Two lines' worth at font size 18, so the longest prompt has
## somewhere to wrap to rather than being clipped by its own band.
const PROMPT_BOTTOM_MARGIN: float = 70.0
const PROMPT_BAND_HEIGHT: float = 52.0


var _hud: Control
var _condition_bar: ProgressBar
var _condition_label: Label
var _water_bar: ProgressBar
var _water_label: Label
var _call_label: Label
var _margin_label: Label
var _credits_label: Label
var _prompt_label: Label
var _minimap: Minimap
var _siren_label: Label

var _menu_panel: Control
var _menu_start_button: Button
var _map_panel: Control
var _map_buttons: Dictionary = {}
var _map_back_button: Button
var _credits_panel: Control
var _credits_back_button: Button
var _results_panel: Control
var _results_title: Label
var _results_detail: Label
var _shop_panel: Control
var _shop_status: Label
var _shop_effect: Label
var _shop_price: Label
var _buy_button: Button
var _results_shop_button: Button
var _results_again_button: Button
var _results_calls_row: Array
var _results_bonus_row: Array
var _results_banked_row: Array
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
	_build_map_panel()
	_build_credits_panel()
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
	#
	# On its own backing, and with a real gap between the rows (Milestone 8
	# Part 3). Both come from James reading "Time left 0:04, running out" over a
	# street label: HUD text with nothing behind it is drawn straight onto the
	# map, and a pale street name painted on the asphalt is exactly the kind of
	# thing it lands on. The rows never actually intersected each other, which
	# the physics runner now asserts, but at four seconds the old rule grew the
	# line into a 4 pixel gap and left it touching the line below.
	var right_backing := PanelContainer.new()
	right_backing.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_backing.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_backing.position = Vector2(-EDGE_MARGIN, EDGE_MARGIN)
	right_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backing_style := StyleBoxFlat.new()
	backing_style.bg_color = HUD_BACKING_COLOR
	backing_style.set_corner_radius_all(6)
	for side in ["left", "right"]:
		backing_style.set("content_margin_%s" % side, 12.0)
	for side in ["top", "bottom"]:
		backing_style.set("content_margin_%s" % side, 8.0)
	right_backing.add_theme_stylebox_override("panel", backing_style)
	_hud.add_child(right_backing)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", HUD_ROW_SEPARATION)
	right_backing.add_child(right)

	_call_label = _make_label("Call 1 of 3", 18)
	_call_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_margin_label = _make_label("Time left 0:00")
	_margin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_credits_label = _make_label(format_credits(0))
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_siren_label = _make_label("Siren off")
	_siren_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_call_label)
	right.add_child(_margin_label)
	right.add_child(_credits_label)
	right.add_child(_siren_label)

	# Bottom right: the minimap.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap.position = Vector2(-EDGE_MARGIN, -EDGE_MARGIN) - Minimap.PANEL_SIZE
	_hud.add_child(_minimap)

	# Bottom centre: the one contextual prompt line.
	#
	# THE BAND IS INSET BY THE MINIMAP'S WIDTH ON BOTH SIDES (Milestone 9 Part
	# 0c). The label used to be PRESET_BOTTOM_WIDE, so its rect ran the whole
	# width of the screen and passed straight under the minimap; the text is
	# centred and would usually have missed it, but "Out of water. Pull up
	# slowly at a hydrant to refill" is wide enough to reach it. Inset on BOTH
	# sides rather than only on the right, so the line stays centred on the
	# screen rather than sitting visibly off to the left, and it wraps rather
	# than overflowing if a future prompt is longer than the band.
	# All four offsets set outright, and no write to position afterwards.
	# Assigning position on an anchored Control rewrites the offsets to preserve
	# the size it had at that moment, which silently undid offset_right and left
	# the band the full width of the screen again.
	_prompt_label = _make_label("", 18)
	_prompt_label.anchor_left = 0.0
	_prompt_label.anchor_right = 1.0
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = PROMPT_SIDE_INSET
	_prompt_label.offset_right = -PROMPT_SIDE_INSET
	_prompt_label.offset_bottom = -PROMPT_BOTTOM_MARGIN
	_prompt_label.offset_top = -PROMPT_BOTTOM_MARGIN - PROMPT_BAND_HEIGHT
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Bottom aligned, so one line sits exactly where the prompt line has always
	# sat and a wrapped one grows upward into empty screen rather than downward.
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


## The home screen: three things a player can do, the first of which takes
## focus so Enter starts a shift without touching the mouse.
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
	_menu_start_button.pressed.connect(func() -> void: open_map_select_pressed.emit())
	rows.add_child(_menu_start_button)

	var credits_button := _make_button("Data and credits")
	credits_button.pressed.connect(func() -> void: open_credits_pressed.emit())
	rows.add_child(credits_button)

	var quit_button := _make_button("Quit")
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	rows.add_child(quit_button)

	var controls := _make_label(
		"W or up drives, S or down brakes then reverses, A and D steer."
		+ " Space is a harder brake, Q toggles the lights, left mouse sprays,"
		+ " Escape pauses, M turns the minimap off and on, N zooms it."
		+ " Roll up to a hydrant slowly and it hooks itself up.",
		13
	)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(controls)


## The map choice. Each map is a button with its own honest lines under it,
## taken from MapCatalogue rather than typed here, so a map's warnings travel
## with the map and cannot be dropped by an edit to this layout.
##
## The lines are set in smaller type but they are not fine print: they say the
## streets are real and the hydrants are not, which is the single thing a player
## could otherwise reasonably misunderstand about this map.
func _build_map_panel() -> void:
	var built: Array = _make_panel("Choose a Map")
	_map_panel = built[0]
	var rows: VBoxContainer = built[1]

	var blurb := _make_label("Where tonight's shift runs. Your last choice is ready to go.")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(blurb)

	for entry in MapCatalogue.entries():
		var map_id: String = String(entry["id"])
		var button := _make_button(String(entry["title"]))
		button.pressed.connect(func() -> void: map_chosen.emit(map_id))
		rows.add_child(button)
		_map_buttons[map_id] = button

		for note in entry["notes"]:
			var line := _make_label(String(note), 13)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92, 0.9))
			rows.add_child(line)

	_map_back_button = _make_button("Back")
	_map_back_button.pressed.connect(func() -> void: back_pressed.emit())
	rows.add_child(_map_back_button)


## Where the data came from and what its licence asks for. Reachable from the
## home menu, which is what makes the credit line something the game displays
## rather than something a file in the repository claims it displays.
##
## The credit line, the licence and the URL are read off the map resource's own
## source_metadata, so they arrive with the data. A screen that hard-coded them
## would keep saying the same thing after the data underneath it changed.
func _build_credits_panel() -> void:
	var built: Array = _make_panel("Data and Credits")
	_credits_panel = built[0]
	var rows: VBoxContainer = built[1]

	for line in credit_lines():
		var label := _make_label(line, 15 if line.begins_with("©") else 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(label)

	_credits_back_button = _make_button("Back")
	_credits_back_button.pressed.connect(func() -> void: back_pressed.emit())
	rows.add_child(_credits_back_button)


## The body of the Data and Credits screen, in order, as plain sentences.
##
## Static and free of any node so the unit suite can read exactly what a player
## is shown, which is the only way "the credit line is displayed" can be
## something a check knows rather than something a person remembers to look at.
static func credit_lines() -> Array[String]:
	var lines: Array[String] = [
		"The Windsor test area is built from OpenStreetMap data.",
	]

	var metadata: Dictionary = {}
	for entry in MapCatalogue.entries():
		var map: MapDefinition = load(String(entry["path"])) as MapDefinition
		if map != null and not map.source_metadata.is_empty():
			metadata = map.source_metadata
			break

	lines.append(String(metadata.get("attribution", "© OpenStreetMap contributors")))
	lines.append(
		"The data is available under the %s."
		% String(metadata.get("licence", "Open Data Commons Open Database License (ODbL)"))
	)
	lines.append(String(metadata.get(
		"copyright_url", "https://www.openstreetmap.org/copyright"
	)))
	lines.append(String(metadata.get("accuracy_note", "")))
	lines.append(
		"Hydrant locations are placeholders, not real. No map images are used,"
		+ " and the game makes no network calls."
	)
	lines.append("Elm Grove is invented. It is not a real place.")

	var kept: Array[String] = []
	for line in lines:
		if line.strip_edges() != "":
			kept.append(line)
	return kept


func _build_results_panel() -> void:
	var built: Array = _make_panel("Shift Over")
	_results_panel = built[0]
	var rows: VBoxContainer = built[1]
	_results_title = built[2]

	_results_detail = _make_label("")
	_results_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_results_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_results_detail)

	# The takings, itemised. One line each, label left and figure right, so the
	# bonus is visibly a separate thing that was or was not earned rather than a
	# number folded into a total the player has to take on trust.
	_results_calls_row = _make_figure_row()
	_results_bonus_row = _make_figure_row()
	_results_banked_row = _make_figure_row()
	rows.add_child(_results_calls_row[0])
	rows.add_child(_results_bonus_row[0])
	rows.add_child(_make_rule())
	rows.add_child(_results_banked_row[0])

	# One clear next action. Starting another shift is what a player almost
	# always wants, so it is the primary and it takes focus; the shop is the
	# considered choice and sits below it.
	_results_again_button = _make_button("Start another shift")
	_results_again_button.pressed.connect(func() -> void: start_shift_pressed.emit())
	rows.add_child(_results_again_button)

	_results_shop_button = _make_button("Open the shop")
	_results_shop_button.pressed.connect(func() -> void: open_shop_pressed.emit())
	rows.add_child(_results_shop_button)


## A label on the left and a figure on the right, the pattern every money line
## on the results screen uses so the numbers form a column.
func _make_figure_row() -> Array:
	var row := HBoxContainer.new()
	var label := _make_label("")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var figure := _make_label("")
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(label)
	row.add_child(figure)
	return [row, label, figure]


func _make_rule() -> Control:
	var rule := ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.18)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	return rule


func _build_shop_panel() -> void:
	var built: Array = _make_panel("Shop")
	_shop_panel = built[0]
	var rows: VBoxContainer = built[1]

	var description := _make_label(
		"A bigger water tank, bought once and kept. It applies from your next shift."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(description)

	# What it does and what it costs, in numbers, above the button that does it.
	_shop_effect = _make_label("", 18)
	rows.add_child(_shop_effect)
	_shop_price = _make_label("")
	rows.add_child(_shop_price)

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

## Exactly one panel is visible at a time, and every screen sets every panel, so
## a new screen can never leave an old one showing underneath it.
func _show_only(panel: Control, hud: bool = false) -> void:
	_hud.visible = hud
	for candidate in [_menu_panel, _map_panel, _credits_panel, _results_panel, _shop_panel]:
		candidate.visible = candidate == panel


func show_menu() -> void:
	_show_only(_menu_panel)
	_focus(_menu_start_button)


## The map choice, with the map the player last used taking focus, so Enter
## repeats the last shift's map and nobody has to re-read the list to do the
## ordinary thing.
func show_map_select(current_map_id: String) -> void:
	_show_only(_map_panel)
	var button: Button = _map_buttons.get(current_map_id, null)
	_focus(button if button != null else _map_back_button)


func show_credits() -> void:
	_show_only(_credits_panel)
	_focus(_credits_back_button)


func show_playing() -> void:
	_show_only(null, true)


## reason is a sentence from GameSession saying how the shift ended. calls_pay
## and bonus_pay are shown separately because they are earned separately: a
## player who cleared two calls and then lost the third keeps the call money and
## not the bonus, and the screen should make that obvious rather than arithmetic.
func show_results(
	succeeded: bool,
	reason: String,
	calls_completed: int,
	total_calls: int,
	calls_pay: int,
	bonus_pay: int,
	banked: int
) -> void:
	_show_only(_results_panel)

	_results_title.text = "Shift Complete" if succeeded else "Shift Over"
	_results_detail.text = "%s. You cleared %d of %d calls." % [
		reason, calls_completed, total_calls
	]

	_results_calls_row[1].text = "Calls cleared (%d)" % calls_completed
	_results_calls_row[2].text = format_credits(calls_pay)
	_results_bonus_row[1].text = (
		"Shift bonus" if bonus_pay > 0 else "Shift bonus (not earned)"
	)
	_results_bonus_row[2].text = format_credits(bonus_pay)
	_results_banked_row[1].text = "Banked in total"
	_results_banked_row[2].text = format_credits(banked)

	_focus(_results_again_button)


## The shop has exactly three states and each one is a word on the button, never
## a colour and never a hidden control: a button that disappears when you cannot
## afford it leaves the player wondering whether they missed something.
func show_shop(
	credits: int, owned: bool, cost: int, status: String, capacity: float, multiplier: float
) -> void:
	_show_only(_shop_panel)

	_shop_effect.text = "Tank capacity %d to %d units" % [
		int(round(capacity)), int(round(capacity * multiplier))
	]
	_shop_price.text = "Price %s. You have %s." % [
		format_credits(cost), format_credits(credits)
	]

	var button: Dictionary = upgrade_button_state(owned, credits, cost)
	_buy_button.text = button["text"]
	_buy_button.disabled = button["disabled"]

	_shop_status.text = status
	_focus(_shop_back_button if _buy_button.disabled else _buy_button)


## The shop button's three states, as a rule rather than as branches buried in a
## layout function, so what the player is allowed to do can be checked without
## building a scene. Returns { "text": String, "disabled": bool }.
##
## Owned wins over affordability: a player who already owns the upgrade and
## happens to be short of credits should be told they own it, not that they
## cannot afford something they already have.
static func upgrade_button_state(owned: bool, credits: int, cost: int) -> Dictionary:
	if owned:
		return {"text": "Owned", "disabled": true}
	if credits < cost:
		return {"text": "Not enough credits", "disabled": true}
	return {"text": "Buy bigger tank", "disabled": false}


## The one place credits are turned into words. Everything that shows money
## calls this, so "350 credits" reads the same on every screen.
static func format_credits(amount: int) -> String:
	return "1 credit" if amount == 1 else "%d credits" % amount


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


## Urgency is carried by the WORDING and the WEIGHT, and never by the size
## (Milestone 8 Part 3).
##
## It used to grow the line from 15 to 20, which made the row taller than the
## space the top-right column had laid out for it: at four seconds left, "Time
## left 0:04, running out" overlapped the credits line under it and read across
## a street label behind it. A HUD element that becomes unreadable exactly when
## it matters most is worse than one that never shouted.
##
## Emboldening changes nothing about the layout, because a FontVariation of the
## same size occupies the same row height, so the panel is laid out identically
## in both states and the two cannot collide. The words are still the carrier:
## the line says "running out" and a player who never notices the weight has
## already been told in English (handoff section 6, colour and styling are never
## the only carrier of state).
func _set_margin_urgent(urgent: bool) -> void:
	if _margin_urgent == urgent:
		return
	_margin_urgent = urgent
	if not urgent:
		_margin_label.remove_theme_font_override("font")
		return
	var bold := FontVariation.new()
	bold.base_font = _margin_label.get_theme_font("font")
	bold.variation_embolden = 0.6
	_margin_label.add_theme_font_override("font", bold)


func set_credits(credits: int) -> void:
	_credits_label.text = format_credits(credits)


func set_siren(active: bool) -> void:
	_siren_label.text = "Siren on" if active else "Siren off"


func set_prompt(text: String) -> void:
	_prompt_label.text = text


# ---------------------------------------------------------------------------
# The minimap (Milestone 9 Part 0c)
#
# GameUI owns the panel and forwards to it, so Main talks to one HUD object
# rather than reaching through it into a child.
# ---------------------------------------------------------------------------

func get_minimap() -> Minimap:
	return _minimap


## Called once per map load with everything the panel draws statically.
func configure_minimap(definition: MapDefinition, hydrants: Array) -> void:
	_minimap.configure(definition, hydrants)


func update_minimap(
	truck_position: Vector2, truck_rotation: float,
	call_position: Vector2, call_active: bool, view_rect: Rect2
) -> void:
	_minimap.set_truck(truck_position, truck_rotation)
	_minimap.set_call(call_position, call_active)
	_minimap.set_view_rect(view_rect)


func is_minimap_shown() -> bool:
	return _minimap.visible


## M. Returns the state it moved to, so the caller can say so on the prompt
## line: a key that is obeyed silently is indistinguishable from one that did
## nothing, which is the reason Z answers as well.
func toggle_minimap() -> bool:
	_minimap.visible = not _minimap.visible
	return _minimap.visible


func set_minimap_shown(shown: bool) -> void:
	_minimap.visible = shown


## N, and the button in the panel's own corner. Returns the level index it moved
## to, so Main can keep it for the session the way it keeps the camera's.
func cycle_minimap_zoom() -> int:
	_minimap.cycle_zoom()
	return _minimap.get_zoom_index()


func set_minimap_zoom_index(index: int) -> void:
	_minimap.set_zoom_index(index)


## Whether the mouse is over the minimap panel.
##
## Main asks before it sprays. The zoom button consumes the click as far as the
## GUI is concerned, but the spray action is POLLED from Input rather than read
## from the event, so it does not care what the GUI did with it: without this,
## clicking the minimap's own button would also fire the water cannon. Spraying
## through a HUD panel is wrong even where there is no button under the cursor,
## so the test is the whole panel rather than just the button.
func is_pointer_over_minimap() -> bool:
	if _minimap == null or not _minimap.visible:
		return false
	return _minimap.get_global_rect().has_point(_minimap.get_global_mouse_position())


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
