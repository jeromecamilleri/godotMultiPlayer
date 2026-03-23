extends StaticBody3D
class_name BombDoor

enum OpenBehavior {
	LIFT,
	DISINTEGRATE,
}

const PUFF_SCENE := preload("res://enemies/smoke_puff/smoke_puff.tscn")

@export var required_bombs := 1
@export var trigger_radius := 5.0
@export var open_behavior: OpenBehavior = OpenBehavior.DISINTEGRATE
@export var open_height := 3.0
@export var open_tween_duration := 0.35
@export var disintegrate_duration := 0.45
@export var disintegrate_scale := 0.05
@export var objective_id := ""

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D

var _bomb_hits := 0
var _is_open := false
var _closed_position := Vector3.ZERO
var _closed_scale := Vector3.ONE
var _last_open_server_ms := -1
var _last_open_replication_delay_ms := -1


func _ready() -> void:
	# Bomb reactives listen to utility explosions through a shared group.
	add_to_group("bomb_reactives")
	_closed_position = global_position
	_closed_scale = _mesh_instance.scale
	if multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_request_current_state.rpc_id(1)


func on_bomb_exploded(world_pos: Vector3, explosion_radius: float, _owner_peer_id: int) -> void:
	# Server decides door progression/opening to keep deterministic multiplayer state.
	if not multiplayer.is_server():
		return
	if _is_open:
		return
	var max_distance := trigger_radius + explosion_radius
	if global_position.distance_to(world_pos) > max_distance:
		return

	_bomb_hits += 1
	if _bomb_hits < required_bombs:
		return

	_last_open_server_ms = Time.get_ticks_msec()
	_apply_open_state(true)
	_set_open_state.rpc(true, _last_open_server_ms)
	if objective_id.strip_edges() != "":
		var director := get_tree().get_first_node_in_group("match_director")
		if is_instance_valid(director) and director.has_method("report_objective_progress"):
			director.report_objective_progress(objective_id, 1)


@rpc("any_peer", "reliable")
func _set_open_state(open: bool, server_event_ms: int = -1) -> void:
	if open and server_event_ms >= 0 and not multiplayer.is_server():
		_last_open_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_last_open_server_ms = server_event_ms
	_apply_open_state(open)


@rpc("any_peer", "reliable")
func _request_current_state() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_set_open_state.rpc_id(peer_id, _is_open, _last_open_server_ms if _is_open else -1)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	call_deferred("_push_current_state_to_peer", peer_id)


func _push_current_state_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	_set_open_state.rpc_id(peer_id, _is_open, _last_open_server_ms if _is_open else -1)


func _apply_open_state(open: bool) -> void:
	if _is_open == open:
		return
	_is_open = open
	_collision_shape.disabled = open
	if open:
		if open_behavior == OpenBehavior.DISINTEGRATE:
			_play_disintegrate_open_effect()
			return
		var target_position := _closed_position + Vector3.UP * open_height
		var tween := create_tween()
		tween.tween_property(self, "global_position", target_position, open_tween_duration)
		return

	# Reset path (currently only useful for editor/manual testing).
	_mesh_instance.visible = true
	_mesh_instance.scale = _closed_scale
	_mesh_instance.transparency = 0.0
	global_position = _closed_position


func _play_disintegrate_open_effect() -> void:
	_spawn_puff()
	var tween := create_tween()
	tween.parallel().tween_property(_mesh_instance, "scale", _closed_scale * disintegrate_scale, disintegrate_duration)
	tween.parallel().tween_property(_mesh_instance, "transparency", 1.0, disintegrate_duration)
	tween.tween_callback(_mesh_instance.hide)


func _spawn_puff() -> void:
	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position


func is_open() -> bool:
	return _is_open


func get_last_open_replication_delay_ms() -> int:
	return _last_open_replication_delay_ms
