extends Node2D
## Placeholder main scene for Part 1 scaffolding.
##
## Confirms the project boots and prints the running Godot version. Later
## parts replace this with the real Main/GameSession orchestrator described
## in the handoff (§8). Nothing else is stubbed out here on purpose.

func _ready() -> void:
	var version_info: Dictionary = Engine.get_version_info()
	print("Fire Truck Game: Main scene loaded. Running Godot %s" % version_info.get("string", "unknown"))
