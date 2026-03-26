extends Node3D
class_name BeetleDirector

const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")

@export var min_beetles := 1
@export var beetles_participant_offset := -1
@export var extra_spawn_radius := 5.0
@export var base_move_speed := 3.0
@export var move_speed_step_per_extra_player := 0.25
@export var base_charge_speed_multiplier := 2.2
@export var charge_speed_step_per_extra_player := 0.15
@export var target_rebalance_interval_sec := 0.5

var _spawn_anchors: Array[Transform3D] = []
var _seed_beetle_paths: Array[NodePath] = []
var _spawned_dynamic_names: Array[String] = []
var _active_seed_count := 0
var _client_resync_timer: Timer
var _client_resync_attempts_remaining := 5
var _target_rebalance_timer: Timer


func _ready() -> void:
	_capture_spawn_anchors()
	if multiplayer.is_server():
		if multiplayer.has_multiplayer_peer() and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		var spawner: Node = _find_player_spawner()
		if spawner != null:
			if spawner.has_signal("player_spawned") and not spawner.player_spawned.is_connected(_on_player_count_changed):
				spawner.player_spawned.connect(_on_player_count_changed)
			if spawner.has_signal("player_despawned") and not spawner.player_despawned.is_connected(_on_player_count_changed):
				spawner.player_despawned.connect(_on_player_count_changed)
		_start_target_rebalance_timer()
		call_deferred("_initialize_server_population")
	else:
		call_deferred("_request_current_beetles_when_connected")


func _initialize_server_population() -> void:
	_capture_seed_beetles_from_scene()
	_refresh_beetle_population()


func _capture_spawn_anchors() -> void:
	_spawn_anchors.clear()
	for child in get_children():
		if child is Node3D and String(child.name).begins_with("beetle_anchor"):
			_spawn_anchors.append((child as Node3D).global_transform)


func _capture_seed_beetles_from_scene() -> void:
	_seed_beetle_paths.clear()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	for candidate in get_tree().get_nodes_in_group("beetles"):
		if not (candidate is Node3D):
			continue
		if self.is_ancestor_of(candidate):
			continue
		_seed_beetle_paths.append(scene_root.get_path_to(candidate))
	_seed_beetle_paths.sort_custom(func(a: NodePath, b: NodePath) -> bool:
		return String(a) < String(b)
	)


func _find_player_spawner() -> Node:
	return get_tree().root.find_child("PlayerSpawner", true, false)


func _refresh_beetle_population() -> void:
	if not multiplayer.is_server():
		return
	var desired_total: int = _get_desired_beetle_count()
	var config: Dictionary = _build_beetle_config(desired_total)
	_active_seed_count = mini(_seed_beetle_paths.size(), desired_total)
	for seed_index in range(_seed_beetle_paths.size()):
		var seed_path: NodePath = _seed_beetle_paths[seed_index]
		_rpc_set_seed_beetle_state.rpc(seed_path, seed_index < _active_seed_count, config)
	var desired_dynamic_count: int = maxi(0, desired_total - _active_seed_count)
	var next_dynamic_names: Array[String] = []
	for idx in range(desired_dynamic_count):
		var name: String = _dynamic_beetle_name_for_index(idx)
		var transform: Transform3D = _transform_for_index(idx + _seed_beetle_paths.size())
		next_dynamic_names.append(name)
		_rpc_spawn_beetle.rpc(name, transform, config)
	for name in _spawned_dynamic_names:
		if name in next_dynamic_names:
			continue
		_rpc_despawn_beetle.rpc(name)
	_spawned_dynamic_names = next_dynamic_names
	for name in _spawned_dynamic_names:
		_rpc_configure_beetle.rpc(name, config)
	_rebalance_beetle_targets()


func _get_desired_beetle_count() -> int:
	if _is_ui_test_beetle_disabled():
		return 0
	var participant_count: int = _get_session_participant_count()
	if participant_count <= 0:
		return min_beetles
	return max(min_beetles, participant_count + beetles_participant_offset)


func _get_session_participant_count() -> int:
	var count := multiplayer.get_peers().size() + 1
	if count <= 1:
		count = max(count, _get_active_player_peer_ids().size())
	return max(1, count)


func _get_active_player_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		var peer_id: int = node.get_multiplayer_authority()
		if peer_id <= 0 or ids.has(peer_id):
			continue
		ids.append(peer_id)
	ids.sort()
	return ids


func _build_target_assignments(beetle_count: int, player_peer_ids: Array[int]) -> Array[int]:
	var assignments: Array[int] = []
	if beetle_count <= 0 or player_peer_ids.is_empty():
		return assignments
	for index in range(beetle_count):
		assignments.append(player_peer_ids[index % player_peer_ids.size()])
	return assignments


func _transform_for_index(index: int) -> Transform3D:
	if _spawn_anchors.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
	var base: Transform3D = _spawn_anchors[index % _spawn_anchors.size()]
	if index < _spawn_anchors.size():
		return base
	var ring_idx: int = index - _spawn_anchors.size()
	var angle: float = float(ring_idx) * (TAU / 4.0)
	var offset := Vector3(cos(angle), 0, sin(angle)) * extra_spawn_radius
	return Transform3D(base.basis, base.origin + offset)


func _dynamic_beetle_name_for_index(index: int) -> String:
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


func _build_managed_beetle_refs() -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	for seed_index in range(_active_seed_count):
		if seed_index >= _seed_beetle_paths.size():
			break
		refs.append({
			"kind": "seed",
			"path": _seed_beetle_paths[seed_index],
			"sort_key": "seed:%s" % String(_seed_beetle_paths[seed_index]),
		})
	for name in _spawned_dynamic_names:
		refs.append({
			"kind": "dynamic",
			"name": name,
			"sort_key": "dynamic:%s" % name,
		})
	refs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("sort_key", "")) < String(b.get("sort_key", ""))
	)
	return refs


func _rebalance_beetle_targets() -> void:
	if not multiplayer.is_server():
		return
	var player_peer_ids: Array[int] = _get_active_player_peer_ids()
	var managed_refs: Array[Dictionary] = _build_managed_beetle_refs()
	var assignments: Array[int] = _build_target_assignments(managed_refs.size(), player_peer_ids)
	for index in range(managed_refs.size()):
		var assigned_peer_id := -1
		if index < assignments.size():
			assigned_peer_id = assignments[index]
		var ref: Dictionary = managed_refs[index]
		match String(ref.get("kind", "")):
			"seed":
				_rpc_assign_seed_beetle_target.rpc(ref["path"], assigned_peer_id)
			"dynamic":
				_rpc_assign_dynamic_beetle_target.rpc(String(ref["name"]), assigned_peer_id)


func _start_target_rebalance_timer() -> void:
	if _target_rebalance_timer != null:
		return
	_target_rebalance_timer = Timer.new()
	_target_rebalance_timer.wait_time = max(0.2, target_rebalance_interval_sec)
	_target_rebalance_timer.autostart = true
	_target_rebalance_timer.one_shot = false
	_target_rebalance_timer.timeout.connect(_on_target_rebalance_timeout)
	add_child(_target_rebalance_timer)


func _on_target_rebalance_timeout() -> void:
	_rebalance_beetle_targets()


@rpc("authority", "call_local", "reliable")
func _rpc_set_seed_beetle_state(seed_path: NodePath, active: bool, config: Dictionary) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var beetle := scene_root.get_node_or_null(seed_path)
	if beetle == null:
		return
	if beetle.has_method("set_director_active"):
		beetle.call("set_director_active", active)
	_apply_beetle_config(beetle, config)


@rpc("authority", "call_local", "reliable")
func _rpc_assign_seed_beetle_target(seed_path: NodePath, assigned_peer_id: int) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var beetle := scene_root.get_node_or_null(seed_path)
	if beetle == null:
		return
	if beetle.has_method("set_assigned_target_peer_id"):
		beetle.call("set_assigned_target_peer_id", assigned_peer_id)


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


@rpc("authority", "call_local", "reliable")
func _rpc_assign_dynamic_beetle_target(name: String, assigned_peer_id: int) -> void:
	var beetle := get_node_or_null(name)
	if beetle == null:
		return
	if beetle.has_method("set_assigned_target_peer_id"):
		beetle.call("set_assigned_target_peer_id", assigned_peer_id)


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
	var desired_total: int = _get_desired_beetle_count()
	var config: Dictionary = _build_beetle_config(desired_total)
	for seed_index in range(_seed_beetle_paths.size()):
		var seed_path: NodePath = _seed_beetle_paths[seed_index]
		_rpc_set_seed_beetle_state.rpc_id(peer_id, seed_path, seed_index < _active_seed_count, config)
	for name in _spawned_dynamic_names:
		var beetle := get_node_or_null(name) as Node3D
		if beetle == null:
			continue
		_rpc_spawn_beetle.rpc_id(peer_id, name, beetle.global_transform, config)
	var player_peer_ids: Array[int] = _get_active_player_peer_ids()
	var managed_refs: Array[Dictionary] = _build_managed_beetle_refs()
	var assignments: Array[int] = _build_target_assignments(managed_refs.size(), player_peer_ids)
	for index in range(managed_refs.size()):
		var assigned_peer_id := -1
		if index < assignments.size():
			assigned_peer_id = assignments[index]
		var ref: Dictionary = managed_refs[index]
		match String(ref.get("kind", "")):
			"seed":
				_rpc_assign_seed_beetle_target.rpc_id(peer_id, ref["path"], assigned_peer_id)
			"dynamic":
				_rpc_assign_dynamic_beetle_target.rpc_id(peer_id, String(ref["name"]), assigned_peer_id)


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
