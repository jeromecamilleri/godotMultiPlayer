extends Node3D
class_name BeeDirector

const BEE_SCENE := preload("res://enemies/bee_bot.tscn")

@export var min_bees := 0
@export var bees_per_player := 1
@export var extra_spawn_ring_radius := 4.5
@export var base_shoot_timer := 1.5
@export var min_shoot_timer := 0.7
@export var shoot_timer_step_per_extra_player := 0.18
@export var base_bullet_speed := 6.0
@export var bullet_speed_step_per_extra_player := 0.85

var _spawn_anchors: Array[Transform3D] = []
var _spawned_bee_names: Array[String] = []


func _ready() -> void:
	_capture_spawn_anchors_from_scene()
	_clear_scene_seed_bees()
	if multiplayer.is_server():
		if multiplayer.has_multiplayer_peer() and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		var spawner: Node = _find_player_spawner()
		if spawner != null:
			if spawner.has_signal("player_spawned") and not spawner.player_spawned.is_connected(_on_player_count_changed):
				spawner.player_spawned.connect(_on_player_count_changed)
			if spawner.has_signal("player_despawned") and not spawner.player_despawned.is_connected(_on_player_count_changed):
				spawner.player_despawned.connect(_on_player_count_changed)
		call_deferred("_refresh_bee_population")
	else:
		_request_current_bees_when_connected()


func _capture_spawn_anchors_from_scene() -> void:
	for child in get_children():
		if child is Node3D and String(child.name).begins_with("bee_bot"):
			_spawn_anchors.append((child as Node3D).transform)


func _clear_scene_seed_bees() -> void:
	for child in get_children():
		if String(child.name).begins_with("bee_bot"):
			child.queue_free()


func _find_player_spawner() -> Node:
	return get_tree().root.find_child("PlayerSpawner", true, false)


func _on_player_count_changed(_id: int, _player = null) -> void:
	_refresh_bee_population()


func _refresh_bee_population() -> void:
	if not multiplayer.is_server():
		return
	var desired_count := _get_desired_bee_count()
	while _spawned_bee_names.size() < desired_count:
		var bee_index := _spawned_bee_names.size()
		var bee_name := "DynamicBee_%d" % bee_index
		var bee_transform := _transform_for_bee_index(bee_index)
		_spawned_bee_names.append(bee_name)
		var config := _build_bee_config(desired_count)
		_rpc_spawn_bee.rpc(bee_name, bee_transform, config)
	while _spawned_bee_names.size() > desired_count:
		var bee_name: String = _spawned_bee_names.pop_back()
		_rpc_despawn_bee.rpc(bee_name)
	var current_config := _build_bee_config(desired_count)
	for bee_name in _spawned_bee_names:
		_rpc_configure_bee.rpc(bee_name, current_config)


func _get_desired_bee_count() -> int:
	if _is_ui_test_bee_disabled():
		return 0
	var player_count := 0
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node3D:
			player_count += 1
	return max(min_bees, player_count * bees_per_player)


func _transform_for_bee_index(index: int) -> Transform3D:
	if _spawn_anchors.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, 0.0))
	if index < _spawn_anchors.size():
		return _spawn_anchors[index]
	var base := _spawn_anchors[index % _spawn_anchors.size()]
	var ring_index := index - _spawn_anchors.size()
	var angle := float(ring_index) * (TAU / 6.0)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * extra_spawn_ring_radius
	return Transform3D(base.basis, base.origin + offset)


func _build_bee_config(player_scaled_bee_count: int) -> Dictionary:
	var baseline_players: int = max(1, min_bees) if min_bees > 0 else 1
	var extra_players: int = max(0, player_scaled_bee_count - baseline_players)
	var shoot_timer: float = max(min_shoot_timer, base_shoot_timer - (float(extra_players) * shoot_timer_step_per_extra_player))
	var bullet_speed: float = base_bullet_speed + (float(extra_players) * bullet_speed_step_per_extra_player)
	return {
		"shoot_timer": shoot_timer,
		"bullet_speed": bullet_speed,
	}


func _is_ui_test_bee_disabled() -> bool:
	var flag := OS.get_environment("UI_TEST_DISABLE_BEES").strip_edges().to_lower()
	return flag == "1" or flag == "true" or flag == "yes"


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_bee(bee_name: String, bee_transform: Transform3D, bee_config: Dictionary) -> void:
	var existing := get_node_or_null(bee_name)
	if existing != null:
		if existing is Node3D:
			(existing as Node3D).transform = bee_transform
		_apply_bee_config(existing, bee_config)
		return
	var bee := BEE_SCENE.instantiate()
	if bee == null:
		return
	bee.name = bee_name
	if bee is Node:
		bee.set_multiplayer_authority(1)
	add_child(bee)
	if bee is Node3D:
		(bee as Node3D).transform = bee_transform
	if "patrol_circle" in bee:
		bee.patrol_circle = true
	_apply_bee_config(bee, bee_config)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_bee(bee_name: String) -> void:
	var bee := get_node_or_null(bee_name)
	if bee != null:
		bee.queue_free()


@rpc("authority", "call_local", "reliable")
func _rpc_configure_bee(bee_name: String, bee_config: Dictionary) -> void:
	var bee := get_node_or_null(bee_name)
	if bee == null:
		return
	_apply_bee_config(bee, bee_config)


func _on_peer_connected(peer_id: int) -> void:
	call_deferred("_push_current_bees_to_peer", peer_id)


func _push_current_bees_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var config := _build_bee_config(_spawned_bee_names.size())
	for i in range(_spawned_bee_names.size()):
		var bee_name := _spawned_bee_names[i]
		var bee := get_node_or_null(bee_name) as Node3D
		if bee == null:
			continue
		_rpc_spawn_bee.rpc_id(peer_id, bee_name, bee.transform, config)


@rpc("any_peer", "call_remote", "reliable")
func _request_current_bees() -> void:
	if not multiplayer.is_server():
		return
	_push_current_bees_to_peer(multiplayer.get_remote_sender_id())


func _request_current_bees_when_connected() -> void:
	var authority_id := 1
	if multiplayer.multiplayer_peer == null:
		if not multiplayer.connected_to_server.is_connected(_on_connected_to_server_request_bees):
			multiplayer.connected_to_server.connect(_on_connected_to_server_request_bees, CONNECT_ONE_SHOT)
		return
	_request_current_bees.rpc_id(authority_id)


func _on_connected_to_server_request_bees() -> void:
	_request_current_bees.rpc_id(1)


func _apply_bee_config(bee: Node, bee_config: Dictionary) -> void:
	if bee == null:
		return
	if "shoot_timer" in bee and bee_config.has("shoot_timer"):
		bee.shoot_timer = float(bee_config["shoot_timer"])
	if "bullet_speed" in bee and bee_config.has("bullet_speed"):
		bee.bullet_speed = float(bee_config["bullet_speed"])
