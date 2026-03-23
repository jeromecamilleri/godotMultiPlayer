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
var _last_collected_server_ms := -1
var _last_collected_replication_delay_ms := -1


func _ready() -> void:
	add_to_group("world_items")
	_refresh_visuals()
	if _is_server_instance():
		if multiplayer.multiplayer_peer != null and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_request_current_state.rpc_id(1)


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
func set_collected_state(collected: bool, server_event_ms: int = -1) -> void:
	if collected and server_event_ms >= 0 and not _is_server_instance():
		_last_collected_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_last_collected_server_ms = server_event_ms
	_apply_collected_state(collected)


@rpc("any_peer", "call_remote", "reliable")
func _request_current_state() -> void:
	if not _is_server_instance():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	set_collected_state.rpc_id(peer_id, _is_collected, _last_collected_server_ms if _is_collected else -1)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_server_instance():
		return
	call_deferred("_push_current_state_to_peer", peer_id)


func _push_current_state_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	set_collected_state.rpc_id(peer_id, _is_collected, _last_collected_server_ms if _is_collected else -1)


func _apply_collected_state(collected: bool) -> void:
	_is_collected = collected
	visible = not collected
	monitorable = not collected
	monitoring = not collected
	if is_instance_valid(_collision_shape):
		_collision_shape.disabled = collected


func _is_server_instance() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _refresh_visuals() -> void:
	if not is_instance_valid(_label):
		return
	var label_text := get_display_name()
	if quantity > 1:
		label_text += " x%d" % quantity
	if not is_pickable:
		label_text += " (fixe)"
	_label.text = label_text


func mark_collected_on_server() -> void:
	if not _is_server_instance():
		return
	_last_collected_server_ms = Time.get_ticks_msec()
	set_collected_state.rpc(true, _last_collected_server_ms)


func get_last_collected_replication_delay_ms() -> int:
	return _last_collected_replication_delay_ms
