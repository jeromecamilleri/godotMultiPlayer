@tool
extends RefCounted
class_name VergerOverrideApplier

const MAIN_SCENE_PATH := "res://main/main.tscn"
const ZONE_VERGER_SCENE_PATH := "res://levels/zones/verger/zone_verger.tscn"
const VERGER_INTERACTIVES_SCENE_PATH := "res://levels/zones/verger/verger_interactives.tscn"
const VERGER_ENEMIES_SCENE_PATH := "res://levels/zones/verger/verger_enemies.tscn"

const ZONE_VERGER_NODE_PATHS := [
	NodePath("Ground"),
	NodePath("Env/Habitation"),
	NodePath("Interactives"),
	NodePath("Enemies"),
	NodePath("Portals"),
	NodePath("Portals/Portal_Verger_To_Hub"),
	NodePath("MissionMarkers"),
]

const VERGER_INTERACTIVES_NODE_PATHS := [
	NodePath("ApplePickup"),
]

const VERGER_ENEMIES_NODE_PATHS := [
	NodePath("bee_bot"),
	NodePath("bee_bot2"),
]


static func apply_from_zone_verger(zone_verger: Node3D, main_scene_path: String = MAIN_SCENE_PATH, scene_paths: Dictionary = {}) -> Dictionary:
	if zone_verger == null:
		return _result(ERR_INVALID_PARAMETER, "Selection invalide: aucun noeud ZoneVerger.")
	if zone_verger.name != "ZoneVerger":
		return _result(ERR_INVALID_PARAMETER, "Selection invalide: selectionne le noeud ZoneVerger dans main.tscn.")

	var zone_scene_path := String(scene_paths.get("zone_verger", ZONE_VERGER_SCENE_PATH))
	var interactives_scene_path := String(scene_paths.get("interactives", VERGER_INTERACTIVES_SCENE_PATH))
	var enemies_scene_path := String(scene_paths.get("enemies", VERGER_ENEMIES_SCENE_PATH))
	var result := _result(OK, "Overrides ZoneVerger appliques.")

	var zone_transforms := _collect_transforms(zone_verger, ZONE_VERGER_NODE_PATHS)
	var interactives := zone_verger.get_node_or_null("Interactives") as Node3D
	var interactive_transforms := _collect_transforms(interactives, VERGER_INTERACTIVES_NODE_PATHS)
	var enemies := zone_verger.get_node_or_null("Enemies") as Node3D
	var enemy_transforms := _collect_transforms(enemies, VERGER_ENEMIES_NODE_PATHS)

	var err := _apply_transforms_to_scene(zone_scene_path, zone_transforms)
	if err != OK:
		return _result(err, "Impossible de sauvegarder %s." % zone_scene_path)
	result["updated_transforms"] += zone_transforms.size()

	err = _apply_transforms_to_scene(interactives_scene_path, interactive_transforms)
	if err != OK:
		return _result(err, "Impossible de sauvegarder %s." % interactives_scene_path)
	result["updated_transforms"] += interactive_transforms.size()

	err = _apply_transforms_to_scene(enemies_scene_path, enemy_transforms)
	if err != OK:
		return _result(err, "Impossible de sauvegarder %s." % enemies_scene_path)
	result["updated_transforms"] += enemy_transforms.size()

	var clean_result := clean_zone_verger_child_overrides(main_scene_path)
	if int(clean_result["error"]) != OK:
		return clean_result
	result["removed_override_blocks"] = clean_result["removed_override_blocks"]
	return result


static func clean_zone_verger_child_overrides(main_scene_path: String = MAIN_SCENE_PATH) -> Dictionary:
	var scene_text := FileAccess.get_file_as_string(main_scene_path)
	if scene_text.is_empty() and FileAccess.get_open_error() != OK:
		return _result(FileAccess.get_open_error(), "Impossible de lire %s." % main_scene_path)

	var clean_result := strip_zone_verger_child_override_blocks(scene_text)
	if int(clean_result["removed_override_blocks"]) == 0:
		return clean_result

	var file := FileAccess.open(main_scene_path, FileAccess.WRITE)
	if file == null:
		return _result(FileAccess.get_open_error(), "Impossible d'ecrire %s." % main_scene_path)
	file.store_string(String(clean_result["text"]))
	file.close()
	return clean_result


static func strip_zone_verger_child_override_blocks(scene_text: String) -> Dictionary:
	var lines := scene_text.split("\n", false)
	var output_lines: Array[String] = []
	var removed_blocks := 0
	var skipping_zone_verger_override := false

	for line in lines:
		if line.begins_with("[node "):
			skipping_zone_verger_override = _is_zone_verger_child_override_header(line)
			if skipping_zone_verger_override:
				removed_blocks += 1
				continue
		elif line.begins_with("[") and skipping_zone_verger_override:
			skipping_zone_verger_override = false

		if not skipping_zone_verger_override:
			output_lines.append(line)

	return {
		"error": OK,
		"message": "Overrides ZoneVerger nettoyes.",
		"removed_override_blocks": removed_blocks,
		"text": "\n".join(output_lines) + "\n",
	}


static func _is_zone_verger_child_override_header(line: String) -> bool:
	return line.contains(" parent=\"ZoneVerger/")


static func _collect_transforms(root: Node3D, node_paths: Array) -> Dictionary:
	var transforms := {}
	if root == null:
		return transforms
	for node_path in node_paths:
		var node := root.get_node_or_null(node_path) as Node3D
		if node != null:
			transforms[node_path] = node.transform
	return transforms


static func _apply_transforms_to_scene(scene_path: String, transforms: Dictionary) -> Error:
	if transforms.is_empty():
		return OK

	var scene := load(scene_path) as PackedScene
	if scene == null:
		return ERR_CANT_OPEN

	var root := scene.instantiate()
	if root == null:
		return ERR_CANT_CREATE

	for node_path in transforms.keys():
		var node := root.get_node_or_null(node_path) as Node3D
		if node == null:
			root.free()
			return ERR_DOES_NOT_EXIST
		node.transform = transforms[node_path]

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		return pack_err
	return ResourceSaver.save(packed, scene_path)


static func _result(error: int, message: String) -> Dictionary:
	return {
		"error": error,
		"message": message,
		"updated_transforms": 0,
		"removed_override_blocks": 0,
	}
