extends RigidBody3D
class_name PullableCube

@export var server_peer_id := 1

@export var base_mass := 2.0
@export var mass_per_player := 2.0
@export var min_players := 1
## Per-attached-player traction contribution. Opposed directions cancel naturally.
@export var pull_force_per_player := 16.0
## Maximum horizontal distance where a player can stay attached.
@export var max_attach_distance := 7.0
## Cube-to-reactor distance required to mark this objective as complete.
@export var reactor_goal_radius := 2.2
## Optional explicit path to the reactor node.
@export var reactor_path: NodePath

@export var auto_move_speed := 4.5
@export var auto_move_force := 28.0
@export var auto_move_alignment_threshold := 0.0
@export var auto_move_min_players := 2
@export var auto_move_glow_boost := 0.9

## Replicated pull state for remote color feedback.
@export var _pull_state_sync := 0

const PULL_STATE_IDLE := 0
const PULL_STATE_ATTACHED := 1
const PULL_STATE_COOP := 2
const PULL_STATE_GOAL := 3

var _attached_peers: Dictionary = {}
var _reactor_node: Node3D
var _goal_reached := false
var _mesh_instance: MeshInstance3D
var _runtime_material: StandardMaterial3D
var _auto_move_active := false
var _goal_direction := Vector3.ZERO

func _on_player_count_changed(_id: int) -> void:
	_update_mass_for_player_count()

func _update_mass_for_player_count() -> void:
	var players: int = max(min_players, multiplayer.get_peers().size() + 1) # + 1 for server/host peer
	mass = base_mass + mass_per_player * float(players - 1)


func _ready() -> void:
	# Only the authority simulates physics; clients receive replicated state.
	set_multiplayer_authority(server_peer_id)
	freeze = not is_multiplayer_authority()
	sleeping = not is_multiplayer_authority()
	add_to_group("pullable_cubes")
	_mesh_instance = get_node_or_null("MeshInstance3D")
	_setup_runtime_material()
	_resolve_reactor_node()
	if is_multiplayer_authority():
		_update_mass_for_player_count()
		multiplayer.peer_connected.connect(_on_player_count_changed)
		multiplayer.peer_disconnected.connect(_on_player_count_changed)
	_apply_visual_state()


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# Prevent local physics from fighting replicated transform updates.
		sleeping = true
		_apply_visual_state()
		return
	_cleanup_invalid_attached_peers()
	_apply_pull_forces()
	_apply_auto_move(_delta)
	_update_goal_state()
	_apply_visual_state()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_push(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_central_impulse(impulse)


@rpc("any_peer", "call_remote", "reliable")
func request_toggle_pull() -> void:
	if not is_multiplayer_authority():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		peer_id = multiplayer.get_unique_id()
	if _goal_reached:
		return
	if _attached_peers.has(peer_id):
		_attached_peers.erase(peer_id)
		return
	if _is_peer_attachable(peer_id):
		_attached_peers[peer_id] = true


func compute_pull_vector_from_points(relative_points: Array[Vector3]) -> Vector3:
	# Summed normalized vectors provide natural cooperation/cancellation.
	var net := Vector3.ZERO
	for point in relative_points:
		var horizontal := Vector3(point.x, 0.0, point.z)
		if horizontal.length_squared() < 0.0001:
			continue
		net += horizontal.normalized()
	return net


func evaluate_goal_reached() -> bool:
	if not is_instance_valid(_reactor_node):
		return false
	return global_position.distance_to(_reactor_node.global_position) <= reactor_goal_radius


func _get_goal_direction() -> Vector3:
	if not is_instance_valid(_reactor_node):
		return Vector3.ZERO
	var to_goal := _reactor_node.global_position - global_position
	if to_goal.is_zero_approx():
		return Vector3.ZERO
	return to_goal.normalized()


func _should_auto_move(net_pull: Vector3) -> bool:
	if _goal_reached:
		return false
	if net_pull.length_squared() < 0.0001:
		return false
	if _attached_peers.size() < auto_move_min_players:
		return false
	var goal_dir := _get_goal_direction()
	if goal_dir.is_zero_approx():
		return false
	#return net_pull.normalized().dot(goal_dir) >= auto_move_alignment_threshold
	return net_pull.normalized().dot(goal_dir) >= auto_move_alignment_threshold


func should_auto_move(net_pull: Vector3) -> bool:
	return _should_auto_move(net_pull)


func _apply_auto_move(delta: float) -> void:
	if not _auto_move_active:
		return
	var goal_dir := _get_goal_direction()
	if goal_dir.is_zero_approx():
		return
	var desired := goal_dir * auto_move_speed
	linear_velocity = linear_velocity.move_toward(desired, auto_move_speed * 4.0 * delta)
	apply_central_force(goal_dir * auto_move_force)


func _apply_pull_forces() -> void:
	if _goal_reached:
		_pull_state_sync = PULL_STATE_GOAL
		return
	if _attached_peers.is_empty():
		_pull_state_sync = PULL_STATE_IDLE
		return

	var relative_points: Array[Vector3] = []
	for peer_id in _attached_peers.keys():
		var player := _get_player_for_peer(int(peer_id))
		if not is_instance_valid(player):
			continue
		relative_points.append(player.global_position - global_position)

	var net_pull: Vector3 = compute_pull_vector_from_points(relative_points)
	_auto_move_active = _should_auto_move(net_pull)
	if net_pull.length_squared() < 0.0001:
		_pull_state_sync = PULL_STATE_ATTACHED
		return

	# Force scales with number of attached players and alignment quality.
	var world_force: Vector3 = net_pull * pull_force_per_player
	apply_central_force(world_force)
	_pull_state_sync = PULL_STATE_COOP if _attached_peers.size() >= 2 else PULL_STATE_ATTACHED

func _cleanup_invalid_attached_peers() -> void:
	var to_remove: Array[int] = []
	for peer_id in _attached_peers.keys():
		var id: int = int(peer_id)
		if not _is_peer_attachable(id):
			to_remove.append(id)
	for id in to_remove:
		_attached_peers.erase(id)


func _is_peer_attachable(peer_id: int) -> bool:
	var player := _get_player_for_peer(peer_id)
	if not is_instance_valid(player):
		return false
	if player.has_method("is_dead") and player.is_dead():
		return false
	var dist: float = player.global_position.distance_to(global_position)
	return dist <= max_attach_distance


func _get_player_for_peer(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Node3D and node.get_multiplayer_authority() == peer_id:
			return node as Node3D
	return null


func _resolve_reactor_node() -> void:
	if not reactor_path.is_empty():
		_reactor_node = get_node_or_null(reactor_path) as Node3D
	if not is_instance_valid(_reactor_node):
		_reactor_node = get_tree().root.find_child("reactor", true, false) as Node3D


func _update_goal_state() -> void:
	if _goal_reached:
		return
	if not evaluate_goal_reached():
		return
	_goal_reached = true
	_attached_peers.clear()
	_pull_state_sync = PULL_STATE_GOAL
	# Freeze so the cube remains clearly parked in the reactor.
	freeze = true

func _setup_runtime_material() -> void:
	if not is_instance_valid(_mesh_instance):
		return
	var current: Material = _mesh_instance.get_active_material(0)
	if current is StandardMaterial3D:
		_runtime_material = (current as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		_runtime_material = StandardMaterial3D.new()
	_mesh_instance.set_surface_override_material(0, _runtime_material)


func _apply_visual_state() -> void:
	if not is_instance_valid(_runtime_material):
		return
	var emission_base := 0.0
	match _pull_state_sync:
		PULL_STATE_IDLE:
			_runtime_material.albedo_color = Color(0.26, 1.0, 0.0, 1.0)
			_runtime_material.emission_enabled = false
			emission_base = 0.0
		PULL_STATE_ATTACHED:
			_runtime_material.albedo_color = Color(1.0, 0.85, 0.2, 1.0)
			_runtime_material.emission_enabled = true
			_runtime_material.emission = Color(1.0, 0.75, 0.1, 1.0)
			emission_base = 0.7
		PULL_STATE_COOP:
			_runtime_material.albedo_color = Color(1.0, 0.02, 0.149, 1.0)
			_runtime_material.emission_enabled = true
			_runtime_material.emission = Color(1.0, 0.02, 0.149, 1.0)
			emission_base = 1.3
		PULL_STATE_GOAL:
			_runtime_material.albedo_color = Color(0.2, 0.75, 1.0, 1.0)
			_runtime_material.emission_enabled = true
			_runtime_material.emission = Color(0.2, 0.75, 1.0, 1.0)
			emission_base = 1.8
	var extra := 0.0
	if _auto_move_active:
		extra = auto_move_glow_boost
	if _runtime_material.emission_enabled:
		_runtime_material.emission_energy_multiplier = emission_base + extra
	else:
		_runtime_material.emission_energy_multiplier = 0.0
