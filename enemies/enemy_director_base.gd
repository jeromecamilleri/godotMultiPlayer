extends Node3D
class_name EnemyDirectorBase

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
