extends SceneTree
## Rewrites resources/neighbourhood.tres from
## MapDefinition.create_fictional_neighbourhood().
##
## Run with:
##   godot --headless --path . --script res://tools/regenerate_map.gd
##
## The .tres file, not the factory method, is the contract the game and the
## tests read. This exists so a change to the layout is a change to one function
## rather than to a hundred hand-edited coordinates, and so the resource can be
## rebuilt if it is ever lost. It writes to the repository, so it is a tool and
## deliberately not part of either test runner.

func _initialize() -> void:
	var definition: MapDefinition = MapDefinition.create_fictional_neighbourhood()
	var error: int = ResourceSaver.save(definition, "res://resources/neighbourhood.tres")
	if error != OK:
		print("could not save the map: error %d" % error)
		quit(1)
		return
	print("wrote resources/neighbourhood.tres: %d roads, %d blocks, %d buildings, %d hydrants, %d incident candidates" % [
		definition.roads.size(), definition.blocks.size(), definition.buildings.size(),
		definition.hydrants.size(), definition.incident_candidates.size(),
	])
	quit(0)
