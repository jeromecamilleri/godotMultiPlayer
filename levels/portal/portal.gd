extends Node3D

@export var url: String
@export var linked_portal_path: NodePath
@export var exit_distance := 2.0
@export var teleport_cooldown_ms := 600

var _last_teleport_by_authority: Dictionary = {}

func _on_portal_entered(body):
	if not body is Player: return
	if body.get_multiplayer_authority() != multiplayer.get_unique_id(): return

	var authority_id: int = body.get_multiplayer_authority()
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_last_teleport_by_authority.get(authority_id, 0))
	if now_ms - last_ms < teleport_cooldown_ms:
		return

	var target: Node3D = get_node_or_null(linked_portal_path) as Node3D
	if target != null:
		_last_teleport_by_authority[authority_id] = now_ms
		if target.has_method("set_last_teleport_for"):
			target.set_last_teleport_for(authority_id, now_ms)

		var target_exit_distance: float = exit_distance
		if "exit_distance" in target:
			target_exit_distance = float(target.get("exit_distance"))
		var exit_pos: Vector3 = target.global_position + target.global_transform.basis.z * target_exit_distance + Vector3.UP * 0.5
		body.global_position = exit_pos
		if "velocity" in body:
			body.velocity = Vector3.ZERO
		return

	DebugLog.gameplay("Portal_entered: " + url)
	await get_tree().create_timer(0.2).timeout

	if get_tree().has_method("open_gate"):
		get_tree().open_gate(url)
	else:
		push_warning("Tree doesn't have method open_gate. Do nothing")


func set_last_teleport_for(authority_id: int, timestamp_ms: int) -> void:
	_last_teleport_by_authority[authority_id] = timestamp_ms
