extends RigidBody3D
class_name EnemyInstanceBase

var _state_revision := 0
var _assigned_target_peer_id := -1


func _register_enemy_groups(additional_groups: PackedStringArray = PackedStringArray()) -> void:
	add_to_group("enemy_instances")
	add_to_group("replicated_persistent_objects")
	for group_name in additional_groups:
		if group_name.is_empty():
			continue
		add_to_group(group_name)


func _bump_state_revision() -> void:
	_state_revision += 1


func set_assigned_target_peer_id(peer_id: int) -> void:
	_bump_state_revision()
	_assigned_target_peer_id = peer_id


func get_assigned_target_peer_id() -> int:
	return _assigned_target_peer_id


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
