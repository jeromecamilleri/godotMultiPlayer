extends Node3D
class_name EnemyDirectorBase

@export var activation_center_path: NodePath
@export var activation_radius := 0.0
@export var activation_portal_group := ""
@export var activation_requires_player_presence := false

var _state_revision := 0


func _register_director_groups(specific_group: String = "") -> void:
	add_to_group("enemy_directors")
	add_to_group("replicated_persistent_objects")
	if not specific_group.is_empty():
		add_to_group(specific_group)


func _bump_state_revision() -> void:
	_state_revision += 1


func get_state_revision() -> int:
	return _state_revision


func request_current_state_from_server() -> void:
	_request_current_state_from_server_impl()


func push_current_state_to_peer(peer_id: int) -> void:
	_push_current_state_to_peer_impl(peer_id)


func get_debug_sync_summary() -> String:
	return _get_debug_sync_summary_impl()


func _request_current_state_from_server_impl() -> void:
	pass


func _push_current_state_to_peer_impl(_peer_id: int) -> void:
	pass


func _get_debug_sync_summary_impl() -> String:
	return "rev=%d" % _state_revision


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)


func _get_scene_root() -> Node:
	if get_tree() == null:
		return null
	if get_tree().current_scene != null:
		return get_tree().current_scene
	return get_tree().root


func _resolve_reference_node(path: NodePath) -> Node3D:
	if path.is_empty():
		return null
	var local_candidate := get_node_or_null(path)
	if local_candidate is Node3D:
		return local_candidate as Node3D
	var scene_root: Node = _get_scene_root()
	if scene_root != null:
		var candidate := scene_root.get_node_or_null(path)
		if candidate is Node3D:
			return candidate as Node3D
	return null


func _resolve_activation_center() -> Vector3:
	var activation_center_node := _resolve_reference_node(activation_center_path)
	if activation_center_node != null:
		return activation_center_node.global_position
	return global_position


func _is_activation_portal_ready() -> bool:
	if activation_portal_group.is_empty():
		return true
	var portal := get_tree().get_first_node_in_group(activation_portal_group)
	if not is_instance_valid(portal):
		return true
	if portal.has_method("is_portal_active"):
		return bool(portal.call("is_portal_active"))
	return true


func _has_active_player_in_activation_zone() -> bool:
	if activation_radius <= 0.0:
		return true
	var center: Vector3 = _resolve_activation_center()
	var max_distance_sq: float = activation_radius * activation_radius
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		var player := node as Node3D
		if player.global_position.distance_squared_to(center) <= max_distance_sq:
			return true
	return false


func _is_runtime_activation_allowed() -> bool:
	if not _is_activation_portal_ready():
		return false
	if activation_requires_player_presence and not _has_active_player_in_activation_zone():
		return false
	return true


func _get_activation_debug_summary() -> String:
	return "zone=%s joueurs=%s rayon=%.1f" % [
		"on" if _is_activation_portal_ready() else "off",
		"on" if _has_active_player_in_activation_zone() else "off",
		activation_radius,
	]
