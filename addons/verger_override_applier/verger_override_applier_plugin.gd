@tool
extends EditorPlugin

const VergerOverrideApplierScript := preload("res://tools/verger_override_applier.gd")

var _button: Button


func _enter_tree() -> void:
	_button = Button.new()
	_button.text = "Appliquer overrides ZoneVerger vers scene source"
	_button.tooltip_text = "Selectionne ZoneVerger dans main.tscn, puis reporte ses transforms vers les scenes source et nettoie main.tscn."
	_button.pressed.connect(_on_apply_pressed)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _button)


func _exit_tree() -> void:
	if _button != null:
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _button)
		_button.queue_free()
		_button = null


func _on_apply_pressed() -> void:
	var selection := get_editor_interface().get_selection()
	var selected_nodes := selection.get_selected_nodes()
	if selected_nodes.size() != 1:
		push_error("Selectionne uniquement ZoneVerger dans main.tscn avant d'appliquer les overrides.")
		return

	var zone_verger := selected_nodes[0] as Node3D
	var current_scene := get_editor_interface().get_edited_scene_root()
	if current_scene == null or current_scene.scene_file_path != VergerOverrideApplierScript.MAIN_SCENE_PATH:
		push_error("Ouvre main.tscn avant d'appliquer les overrides ZoneVerger.")
		return

	var save_err := get_editor_interface().save_scene()
	if save_err != OK:
		push_error("Impossible de sauvegarder main.tscn avant application: %s" % error_string(save_err))
		return

	var result: Dictionary = VergerOverrideApplierScript.apply_from_zone_verger(zone_verger)
	if int(result["error"]) != OK:
		push_error(String(result["message"]))
		return

	get_editor_interface().reload_scene_from_path(VergerOverrideApplierScript.MAIN_SCENE_PATH)
	print("%s transforms=%s overrides_supprimes=%s" % [
		String(result["message"]),
		result["updated_transforms"],
		result["removed_override_blocks"],
	])
