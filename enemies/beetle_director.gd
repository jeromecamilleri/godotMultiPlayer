extends Node3D
class_name BeetleDirector

const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")

@export var min_beetles := 1
@export var beets_per_player := 1
@export var extra_spawn_radius := 5.0
@export var base_move_speed := 3.0
@export var move_speed_step_per_extra_player := 0.25
@export var base_charge_speed_multiplier := 2.2
@export var charge_speed_step_per_extra_player := 0.15

var _spawn_anchors: Array[Transform3D] = []
var _spawned_beetle_names: Array[String] = []
var _client_resync_timer: Timer
var _client_resync_attempts_remaining := 5

func _ready() -> void:
	_capture_spawn_anchors()
	if multiplayer.is_server():
		if multiplayer.has_multiplayer_peer() and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		var spawner := _find_player_spawner()
		if spawner != null:
			if spawner.has_signal("player_spawned") and not spawner.player_spawned.is_connected(_on_player_count_changed):
				spawner.player_spawned.connect(_on_player_count_changed)
			if spawner.has_signal("player_despawned") and not spawner.player_despawned.is_connected(_on_player_count_changed):
				spawner.player_despawned.connect(_on_player_count_changed)
		call_deferred("_refresh_beetle_population")
	else:
		_request_current_beetles_when_connected()

func _capture_spawn_anchors() -> void:
	_spawn_anchors.clear()
	for child in get_children():
		if child is Node3D and String(child.name).begins_with("beetle_anchor"):
			_spawn_anchors.append((child as Node3D).global_transform)

func _find_player_spawner() -> Node:
	return get_tree().root.find_child("PlayerSpawner", true, false)

func _refresh_beetle_population() -> void:
	if not multiplayer.is_server():
		return
	var desired := _get_desired_beetle_count()
	var next_names: Array[String] = []
	var config: Dictionary = _build_beetle_config(desired)
	for idx in range(desired):
		var name := _beetle_name_for_index(idx)
		var transform := _transform_for_index(idx)
		next_names.append(name)
		_rpc_spawn_beetle.rpc(name, transform, config)
	for name in _spawned_beetle_names:
		if name in next_names:
			continue
		_rpc_despawn_beetle.rpc(name)
	_spawned_beetle_names = next_names
	for name in _spawned_beetle_names:
		_rpc_configure_beetle.rpc(name, config)

func _get_desired_beetle_count() -> int:
	if _is_ui_test_beetle_disabled():
		return 0
	var player_count := 0
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node3D:
			player_count += 1
	return max(min_beetles, player_count + beets_per_player)

func _transform_for_index(index: int) -> Transform3D:
	if _spawn_anchors.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
	var base := _spawn_anchors[index % _spawn_anchors.size()]
	if index < _spawn_anchors.size():
		return base
	var ring_idx := index - _spawn_anchors.size()
	var angle := float(ring_idx) * (TAU / 4.0)
	var offset := Vector3(cos(angle), 0, sin(angle)) * extra_spawn_radius
	return Transform3D(base.basis, base.origin + offset)

func _beetle_name_for_index(index: int) -> String:
	return "DynamicBeetle_%d" % index

func _build_beetle_config(count: int) -> Dictionary:
	var baseline: int = max(1, min_beetles)
	var extra: int = max(0, count - baseline)
	return {
		"move_speed": base_move_speed + (extra * move_speed_step_per_extra_player),
		"charge_speed_multiplier": base_charge_speed_multiplier + (extra * charge_speed_step_per_extra_player),
	}

func _is_ui_test_beetle_disabled() -> bool:
	var flag := OS.get_environment("UI_TEST_DISABLE_BEETLES").strip_edges().to_lower()
	return flag == "1" or flag == "true" or flag == "yes"

@rpc("authority", "call_local", "reliable")
func _rpc_spawn_beetle(name: String, transform: Transform3D, config: Dictionary) -> void:
	var beetle := get_node_or_null(name) as Node3D
	if beetle == null:
		beetle = BEETLE_SCENE.instantiate()
		add_child(beetle)
		beetle.name = name
	if beetle is Node3D:
		beetle.global_transform = transform
		_apply_beetle_config(beetle, config)
		if beetle.has_method("set_director_active"):
			beetle.call("set_director_active", true)

@rpc("authority", "call_local", "reliable")
func _rpc_despawn_beetle(name: String) -> void:
	var beetle := get_node_or_null(name)
	if beetle != null:
		beetle.queue_free()

@rpc("authority", "call_local", "reliable")
func _rpc_configure_beetle(name: String, config: Dictionary) -> void:
	var beetle := get_node_or_null(name)
	if beetle == null:
		return
	_apply_beetle_config(beetle, config)

func _apply_beetle_config(beetle: Node, config: Dictionary) -> void:
	if not is_instance_valid(beetle):
		return
	if config.has("move_speed"):
		beetle.set("move_speed", config["move_speed"])
	if config.has("charge_speed_multiplier"):
		beetle.set("charge_speed_multiplier", config["charge_speed_multiplier"])

func _on_peer_connected(peer_id: int) -> void:
	call_deferred("_push_state_to_peer", peer_id)

func _push_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var config := _build_beetle_config(_spawned_beetle_names.size())
	for i in range(_spawned_beetle_names.size()):
		var name := _spawned_beetle_names[i]
		var beetle := get_node_or_null(name) as Node3D
		if beetle == null:
			continue
		_rpc_spawn_beetle.rpc_id(peer_id, name, beetle.global_transform, config)

@rpc("any_peer", "call_remote", "reliable")
func _request_current_beetles() -> void:
	if not multiplayer.is_server():
		return
	_push_state_to_peer(multiplayer.get_remote_sender_id())

func _request_current_beetles_when_connected() -> void:
	var authority := 1
	if multiplayer.multiplayer_peer == null:
		if not multiplayer.connected_to_server.is_connected(_on_connected_to_server_request_beetles):
			multiplayer.connected_to_server.connect(_on_connected_to_server_request_beetles, CONNECT_ONE_SHOT)
		return
	_start_client_resync_watchdog()
	_request_current_beetles.rpc_id(authority)

func _on_connected_to_server_request_beetles() -> void:
	_start_client_resync_watchdog()
	_request_current_beetles.rpc_id(1)

func _start_client_resync_watchdog() -> void:
	if multiplayer.is_server():
		return
	if _client_resync_timer != null:
		return
	_client_resync_attempts_remaining = 5
	_client_resync_timer = Timer.new()
	_client_resync_timer.wait_time = 1.0
	_client_resync_timer.autostart = true
	_client_resync_timer.one_shot = false
	_client_resync_timer.timeout.connect(_on_client_resync_timeout)
	add_child(_client_resync_timer)

func _on_client_resync_timeout() -> void:
	if _client_resync_attempts_remaining <= 0:
		_client_resync_timer.queue_free()
		_client_resync_timer = null
		return
	_client_resync_attempts_remaining -= 1
	_request_current_beetles.rpc_id(1)

func _on_player_count_changed(_id: int, _player = null) -> void:
	_refresh_beetle_population()
