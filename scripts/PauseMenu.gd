extends CanvasLayer
class_name PauseMenu
## The pause overlay.
##
## Its process_mode is set to PROCESS_MODE_ALWAYS in the scene, which is what
## lets its buttons and focus keep working while the tree is paused (handoff
## section 8: "Ensure pause UI still processes input"). Everything that
## simulates the world stays PAUSABLE and therefore stops.

signal resume_requested
signal return_to_station_requested

@onready var _resume_button: Button = %ResumeButton
@onready var _return_button: Button = %ReturnToStationButton


func _ready() -> void:
	hide_menu()
	_resume_button.pressed.connect(func() -> void: resume_requested.emit())
	_return_button.pressed.connect(func() -> void: return_to_station_requested.emit())


func show_menu() -> void:
	visible = true
	# Focus moves to the first control in whatever opens, so the menu is
	# immediately keyboard operable.
	_resume_button.grab_focus()


func hide_menu() -> void:
	visible = false
