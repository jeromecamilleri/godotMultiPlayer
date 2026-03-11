extends Area3D
class_name WorldItem

const FALLBACK_WORLD_ITEM_SCENE := "res://inventory/world_item.tscn"

@export var item_definition: Resource
@export var quantity := 1
@export var is_pickable := true

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D

var _is_collected := false
var _runtime_payload: Dictionary = {}


func _ready() -> void:
	add_to_group("world_items")
	_refresh_visuals()


func can_be_picked_up() -> bool:
	var has_item_data := item_definition != null or not _runtime_payload.is_empty()
	return is_pickable and not _is_collected and has_item_data and quantity > 0


func to_inventory_payload() -> Dictionary:
	if item_definition == null:
		if _runtime_payload.is_empty():
			return {}
		var payload_from_runtime := _runtime_payload.duplicate(true)
		payload_from_runtime["quantity"] = quantity
		return payload_from_runtime
	var payload: Dictionary = item_definition.call("to_inventory_payload", quantity)
	if String(payload.get("world_item_scene", "")).is_empty():
		payload["world_item_scene"] = FALLBACK_WORLD_ITEM_SCENE
	return payload


func configure_from_payload(payload: Dictionary) -> void:
	_runtime_payload = payload.duplicate(true)
	quantity = maxi(1, int(payload.get("quantity", 1)))
	is_pickable = bool(payload.get("is_pickable", true))
	if item_definition != null:
		_refresh_visuals()
		return
	var display_name := String(payload.get("display_name", payload.get("item_id", "Objet")))
	if is_instance_valid(_label):
		_label.text = "%s x%d" % [display_name, quantity]


func get_display_name() -> String:
	if item_definition != null and not item_definition.display_name.is_empty():
		return item_definition.display_name
	if not _runtime_payload.is_empty():
		return String(_runtime_payload.get("display_name", _runtime_payload.get("item_id", "Objet")))
	return "Objet"


@rpc("any_peer", "call_local", "reliable")
func set_collected_state(collected: bool) -> void:
	_is_collected = collected
	visible = not collected
	monitorable = not collected
	monitoring = not collected
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = collected


func _refresh_visuals() -> void:
	if not is_instance_valid(_label):
		return
	var label_text := get_display_name()
	if quantity > 1:
		label_text += " x%d" % quantity
	if not is_pickable:
		label_text += " (fixe)"
	_label.text = label_text
