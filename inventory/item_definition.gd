extends Resource
class_name ItemDefinition

@export var item_id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var max_stack := 99
@export var world_item_scene: PackedScene
@export var icon: Texture2D


func to_inventory_payload(quantity: int = 1, metadata: Dictionary = {}) -> Dictionary:
	var clamped_quantity := maxi(1, quantity)
	var payload := {
		"item_id": String(item_id),
		"display_name": display_name,
		"description": description,
		"quantity": clamped_quantity,
		"max_stack": maxi(1, max_stack),
		"world_item_scene": _get_world_item_scene_path(),
		"icon_path": _get_icon_path(),
		"metadata": metadata.duplicate(true),
	}
	return payload


func _get_world_item_scene_path() -> String:
	if world_item_scene == null:
		return ""
	return world_item_scene.resource_path


func _get_icon_path() -> String:
	if icon == null:
		return ""
	return icon.resource_path
