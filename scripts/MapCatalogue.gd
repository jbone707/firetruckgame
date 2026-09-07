extends RefCounted
class_name MapCatalogue
## The maps the player can choose between, and the honest sentences that have to
## travel with each one (Milestone 5 Part 2).
##
## One list, in one place, because three things need to agree about it: the menu
## that offers the maps, the save file that remembers which was picked, and Main
## which loads it. A second list anywhere would be the thing that goes stale.
##
## The notes are not decoration. A map built from OpenStreetMap data may not be
## presented as an accurate map of the place it is named after, and this game's
## hydrants are invented outright, so the screen that offers the map is the
## screen that has to say so (handoff §1, §7 and ATTRIBUTION.md). Putting the
## notes in the catalogue rather than in the UI means the map and its warnings
## cannot be separated by an edit to a layout.

## The map a new player gets, and the map anything unrecognised falls back to.
## Deliberately the invented one: it is the map that claims nothing.
const DEFAULT_ID: String = "fictional_neighbourhood_v2"


## Every choosable map, in the order the menu offers them. Each entry:
## {id, path, title, notes: Array[String]}.
##
## "title" is what the button says, so it is sentence case beyond the proper
## noun, per AGENTS.md §10. "notes" are body lines shown under that button.
static func entries() -> Array[Dictionary]:
	return [
		{
			"id": DEFAULT_ID,
			"path": "res://resources/neighbourhood.tres",
			"title": "Elm Grove",
			"notes": [
				"A made-up neighbourhood. Not a real place.",
			],
		},
		{
			"id": "windsor_shadetree_v1",
			"path": "res://resources/windsor_shadetree.tres",
			"title": "Windsor test area",
			"notes": [
				"Streets from OpenStreetMap; buildings partly synthetic",
				"Hydrant locations are placeholders, not real",
			],
		},
	]


static func is_known(map_id: String) -> bool:
	for entry in entries():
		if String(entry["id"]) == map_id:
			return true
	return false


## The resource path for a map id, or the default map's path if the id is not
## one this build ships. A save naming a map that no longer exists must put the
## player on a map, not on a black screen.
static func path_for(map_id: String) -> String:
	for entry in entries():
		if String(entry["id"]) == map_id:
			return String(entry["path"])
	return path_for(DEFAULT_ID) if map_id != DEFAULT_ID else "res://resources/neighbourhood.tres"


static func title_for(map_id: String) -> String:
	for entry in entries():
		if String(entry["id"]) == map_id:
			return String(entry["title"])
	return ""
