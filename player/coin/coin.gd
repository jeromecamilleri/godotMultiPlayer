class_name Coin
extends RigidBody3D

const MIN_LAUNCH_RANGE := 2.0
const MAX_LAUNCH_RANGE := 4.0
const MIN_LAUNCH_HEIGHT := 1.0
const MAX_LAUNCH_HEIGHT := 3.0

const SPAWN_TWEEN_DURATION := 1.0
const FOLLOW_TWEEN_DURATION := 0.5
const DOWNED_SCAN_RADIUS := 5.0
const NO_TARGET_PEER_ID := -1

@onready var _collect_audio: AudioStreamPlayer3D = $CollectAudio
@onready var _player_detection_area: Area3D = $PlayerDetectionArea

var _initial_tween_position: Vector3 = Vector3.ZERO
var _target: Node3D = null
var _follow_tween: Tween = null
var _consumed := false
var _target_peer_id := NO_TARGET_PEER_ID
var _last_state_server_ms := -1
var _last_state_replication_delay_ms := -1
var _default_collision_layer := 0
var _default_collision_mask := 0
var _state_revision := 0


func _ready() -> void:
	add_to_group("revive_coins")
	add_to_group("replicated_persistent_objects")
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	if is_instance_valid(_player_detection_area) and not _player_detection_area.body_entered.is_connected(_on_body_entered):
		_player_detection_area.body_entered.connect(_on_body_entered)
	if _is_server_instance():
		if multiplayer.multiplayer_peer != null and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_apply_proxy_idle_state()
		call_deferred("_request_current_state_when_connected")


func spawn(coin_delay: float = 0.5) -> void:
	var rand_height := MIN_LAUNCH_HEIGHT + (randf() * MAX_LAUNCH_HEIGHT)
	var rand_dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * 2.0 * PI)
	var rand_pos := rand_dir * (MIN_LAUNCH_RANGE + (randf() * MAX_LAUNCH_RANGE))
	rand_pos.y = rand_height
	apply_central_impulse(rand_pos)

	# Delay time for player to be able to collect it.
	get_tree().create_timer(coin_delay).timeout.connect(set_collision_layer_value.bind(3, true))


func set_target(new_target: PhysicsBody3D) -> void:
	if _consumed or not _is_server_instance() or new_target == null:
		return
	PhysicsServer3D.body_add_collision_exception(get_rid(), new_target.get_rid())
	_initial_tween_position = global_position
	_target = new_target
	_target_peer_id = _extract_target_peer_id(new_target)
	_last_state_server_ms = Time.get_ticks_msec()
	_record_sync_event("coin", "cible J%s" % ("-" if _target_peer_id <= 0 else str(_target_peer_id)))
	_restart_follow_tween()
	_sync_coin_state.rpc(false, _target_peer_id, global_position, _last_state_server_ms, false)


func _physics_process(_delta: float) -> void:
	if not _is_server_instance():
		_try_resolve_remote_target()
		return
	if _consumed:
		return
	if _target != null:
		return
	var downed := _find_nearby_downed_player()
	if downed != null:
		set_target(downed)


func _follow(offset: float) -> void:
	if not is_instance_valid(_target):
		return
	global_position = lerp(_initial_tween_position, _target.global_position, offset)


func _on_body_entered(body: PhysicsBody3D) -> void:
	if not _is_server_instance() or _consumed:
		return
	if body is Player:
		var player := body as Player
		if player.can_be_revived():
			set_target(player)
			return
		# When someone is downed, keep coins for revive instead of normal pickup.
		if _has_any_downed_player():
			return
		set_target(player)


func _collect() -> void:
	if _consumed or not _is_server_instance():
		return
	var consumed_for_revive := false
	if _target is Player:
		var player := _target as Player
		if player.can_be_revived():
			consumed_for_revive = player.try_revive_with_coin()
	if not consumed_for_revive and _target is Player:
		(_target as Player).collect_coin()
	_consume_on_server(consumed_for_revive)


@rpc("authority", "call_local", "reliable")
func _sync_coin_state(consumed: bool, target_peer_id: int = NO_TARGET_PEER_ID, coin_position: Vector3 = Vector3.ZERO, server_event_ms: int = -1, play_feedback: bool = false) -> void:
	_apply_coin_state(consumed, target_peer_id, coin_position, server_event_ms, play_feedback)


@rpc("any_peer", "call_remote", "reliable")
func _request_current_state() -> void:
	if not _is_server_instance():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_record_sync_event("coin", "etat -> J%d consomme=%s cible=J%s" % [
		peer_id,
		str(_consumed),
		"-" if _target_peer_id <= 0 else str(_target_peer_id),
	])
	_sync_coin_state.rpc_id(peer_id, _consumed, _target_peer_id, global_position, _last_state_server_ms, false)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_server_instance():
		return
	call_deferred("_push_current_state_to_peer", peer_id)


func _push_current_state_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	_record_sync_event("coin", "push etat -> J%d consomme=%s" % [peer_id, str(_consumed)])
	_sync_coin_state.rpc_id(peer_id, _consumed, _target_peer_id, global_position, _last_state_server_ms, false)


func _apply_coin_state(consumed: bool, target_peer_id: int, coin_position: Vector3, server_event_ms: int, play_feedback: bool) -> void:
	var was_consumed := _consumed
	var previous_target_peer_id := _target_peer_id
	_consume_follow_tween()
	_consumed = consumed
	_target_peer_id = target_peer_id
	if was_consumed != consumed or previous_target_peer_id != target_peer_id:
		_state_revision += 1
	_last_state_server_ms = server_event_ms
	if server_event_ms >= 0 and not _is_server_instance():
		_last_state_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	global_position = coin_position
	if _consumed:
		_target = null
		_apply_unavailable_state(play_feedback and not was_consumed)
		return
	_target = _find_player_by_peer_id(_target_peer_id)
	if _is_server_instance():
		_apply_server_state()
	else:
		_apply_proxy_state()


func _consume_on_server(consumed_for_revive: bool) -> void:
	if _consumed or not _is_server_instance():
		return
	_last_state_server_ms = Time.get_ticks_msec()
	_record_sync_event("coin", "consomme (%s)" % ("revive" if consumed_for_revive else "pickup"))
	_sync_coin_state.rpc(true, _target_peer_id, global_position, _last_state_server_ms, true)


func _apply_unavailable_state(play_feedback: bool) -> void:
	_target = null
	_target_peer_id = NO_TARGET_PEER_ID
	visible = false
	_set_detection_area_state(false, false)
	set_collision_layer(0)
	set_collision_mask(0)
	sleeping = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if play_feedback and is_instance_valid(_collect_audio):
		_collect_audio.pitch_scale = randfn(1.0, 0.1)
		_collect_audio.play()


func _apply_server_state() -> void:
	visible = true
	_set_detection_area_state(false, true)
	set_collision_layer(_default_collision_layer)
	set_collision_mask(_default_collision_mask)
	if _target_peer_id > 0:
		sleeping = true
		freeze = true
		_restart_follow_tween()
		return
	_set_detection_area_state(true, true)
	sleeping = false
	freeze = false


func _apply_proxy_state() -> void:
	visible = true
	_set_detection_area_state(false, false)
	set_collision_layer(0)
	set_collision_mask(0)
	sleeping = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if _target_peer_id > 0:
		_restart_follow_tween()


func _apply_proxy_idle_state() -> void:
	_set_detection_area_state(false, false)
	sleeping = true
	freeze = true


func _set_detection_area_state(next_monitoring: bool, next_monitorable: bool) -> void:
	if not is_instance_valid(_player_detection_area):
		return
	_player_detection_area.set_deferred("monitoring", next_monitoring)
	_player_detection_area.set_deferred("monitorable", next_monitorable)


func _restart_follow_tween() -> void:
	_consume_follow_tween()
	sleeping = true
	freeze = true
	if not is_instance_valid(_target):
		return
	_initial_tween_position = global_position
	_follow_tween = create_tween()
	_follow_tween.tween_method(_follow, 0.0, 1.0, FOLLOW_TWEEN_DURATION)
	if _is_server_instance():
		_follow_tween.tween_callback(_collect)


func _consume_follow_tween() -> void:
	if is_instance_valid(_follow_tween):
		_follow_tween.kill()
	_follow_tween = null


func _try_resolve_remote_target() -> void:
	if _consumed or _target_peer_id <= 0 or is_instance_valid(_target):
		return
	_target = _find_player_by_peer_id(_target_peer_id)
	if is_instance_valid(_target):
		_restart_follow_tween()


func _find_nearby_downed_player() -> Player:
	var nearest: Player = null
	var nearest_dist_sq := DOWNED_SCAN_RADIUS * DOWNED_SCAN_RADIUS
	for node in get_tree().get_nodes_in_group("downed_players"):
		if not (node is Player):
			continue
		var player := node as Player
		var dist_sq := global_position.distance_squared_to(player.global_position)
		if dist_sq > nearest_dist_sq:
			continue
		nearest = player
		nearest_dist_sq = dist_sq
	return nearest


func _find_player_by_peer_id(peer_id: int) -> Player:
	if peer_id <= 0:
		return null
	for group_name in ["players", "downed_players"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not (node is Player):
				continue
			var player := node as Player
			if player.get_multiplayer_authority() == peer_id:
				return player
	return null


func _extract_target_peer_id(new_target: PhysicsBody3D) -> int:
	if new_target is Player:
		return (new_target as Player).get_multiplayer_authority()
	return NO_TARGET_PEER_ID


func _has_any_downed_player() -> bool:
	return not get_tree().get_nodes_in_group("downed_players").is_empty()


func _is_server_instance() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func is_consumed_state() -> bool:
	return _consumed


func get_target_peer_id() -> int:
	return _target_peer_id


func get_last_state_replication_delay_ms() -> int:
	return _last_state_replication_delay_ms


func get_debug_sync_summary() -> String:
	var target_text := "-"
	if _target_peer_id > 0:
		target_text = "J%d" % _target_peer_id
	return "coin=%s cible=%s rep=%s" % [
		"consomme" if _consumed else "actif",
		target_text,
		"-" if _last_state_replication_delay_ms < 0 else "%d ms" % _last_state_replication_delay_ms,
	]


func request_current_state_from_server() -> void:
	_request_current_state_when_connected()


func push_current_state_to_peer(peer_id: int) -> void:
	_push_current_state_to_peer(peer_id)


func get_state_revision() -> int:
	return _state_revision


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)


func _request_current_state_when_connected() -> void:
	if _is_server_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_state")):
		return
	_request_current_state.rpc_id(1)


func _on_connected_to_server_request_state() -> void:
	_request_current_state_when_connected()
