extends RigidBody3D

const COIN_SCENE := preload("res://player/coin/coin.tscn")
const BULLET_SCENE := preload("res://player/bullet.tscn")
const PUFF_SCENE := preload("smoke_puff/smoke_puff.tscn")

@export var shoot_timer := 1.5
@export var bullet_speed := 6.0
@export var coins_count := 5
@export var patrol_circle := false
@export var patrol_radius := 2.5
@export var patrol_angular_speed := 1.2
@export var patrol_height_offset := 0.0

@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _flying_animation_player: AnimationPlayer = $MeshRoot/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _death_mesh_collider: CollisionShape3D = $DeathMeshCollider
@onready var _bee_root: Node3D = $MeshRoot/bee_root
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound

@onready var _shoot_count := 0.0
@onready var _target: Node3D = null
@onready var _alive: bool = true
@onready var _removed: bool = false
@onready var _patrol_center: Vector3 = global_position
@onready var _patrol_angle := 0.0
@onready var _remote_target_transform: Transform3D = global_transform


func _ready() -> void:
	add_to_group("bee_bots")
	_detection_area.monitoring = true
	_detection_area.monitorable = true
	_patrol_center = global_position
	_patrol_angle = randf() * TAU
	_bee_root.play_idle()
	# Authority pushes state to newcomers; non-authority requests state after connect.
	if is_multiplayer_authority():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_request_alive_state_when_connected()


func _physics_process(delta: float) -> void:
	if _removed:
		return

	if not is_multiplayer_authority():
		# Clients only render replicated movement from authority.
		global_transform = global_transform.interpolate_with(_remote_target_transform, 0.35)
		return

	if _alive:
		# AI behavior is authority-only: acquire target, patrol, rotate, and shoot.
		_update_target_from_overlaps()
		if patrol_circle and _target == null:
			_update_patrol_circle(delta)

		if _target != null:
			if sleeping:
				sleeping = false
			var target_transform := transform.looking_at(_target.global_position)
			transform = transform.interpolate_with(target_transform, 0.1)

			if not _is_ui_test_bee_fire_disabled():
				_shoot_count += delta
				if _shoot_count > shoot_timer:
					_bee_root.play_spit_attack()
					_shoot_count -= shoot_timer

					var origin := global_position
					var target := _target.global_position + Vector3.UP
					var aim_direction := (target - global_position).normalized()
					_spawn_bee_bullet.rpc(origin, aim_direction)

	_sync_bee_transform.rpc(global_transform)


func _is_ui_test_bee_fire_disabled() -> bool:
	var flag := OS.get_environment("UI_TEST_DISABLE_BEES").strip_edges().to_lower()
	return flag == "1" or flag == "true" or flag == "yes"


func damage(impact_point: Vector3, force: Vector3, attacker_peer_id: int = -1) -> void:
	# Route all gameplay damage decisions to the node authority (server).
	var authority_id: int = get_multiplayer_authority()
	if multiplayer.get_unique_id() == authority_id:
		_apply_damage(impact_point, force, attacker_peer_id)
	else:
		_request_damage.rpc_id(authority_id, impact_point, force, attacker_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _request_damage(impact_point: Vector3, force: Vector3, attacker_peer_id: int = -1) -> void:
	if not is_multiplayer_authority():
		return
	_apply_damage(impact_point, force, attacker_peer_id)


func _apply_damage(impact_point: Vector3, force: Vector3, attacker_peer_id: int = -1) -> void:
	if not is_multiplayer_authority():
		return
	if not _alive:
		return

	var clamped_force: Vector3 = force.limit_length(3.0)
	# Start visuals for everyone immediately; authority keeps gameplay ownership.
	_start_death_visuals.rpc(impact_point, clamped_force)
	_report_score_for_kill(attacker_peer_id)

	await get_tree().create_timer(2).timeout

	var death_position: Vector3 = global_position
	_spawn_puff_local(death_position)
	_spawn_puff_remote.rpc(death_position)
	await get_tree().create_timer(0.25).timeout
	for i in range(coins_count):
		var coin := COIN_SCENE.instantiate()
		get_parent().add_child(coin)
		coin.global_position = global_position
		coin.spawn()
	# Finalize dead state on all peers, including future late-join state sync.
	_finalize_death.rpc()


func _report_score_for_kill(attacker_peer_id: int) -> void:
	# Route enemy-death bookkeeping through MatchDirector's event API.
	var director := _get_match_director_or_null()
	if not is_instance_valid(director):
		return
	if director.has_method("report_enemy_killed"):
		director.report_enemy_killed("bee_bot", attacker_peer_id)


func _get_match_director_or_null() -> Node:
	return get_tree().get_first_node_in_group("match_director")


@rpc("authority", "call_local", "reliable")
func _finalize_death() -> void:
	if _removed:
		return
	# Keep node in scene as a replicated "dead state" for late-join consistency.
	_removed = true
	visible = false
	set_process(false)
	set_physics_process(false)
	_detection_area.monitoring = false
	_detection_area.monitorable = false
	_death_mesh_collider.disabled = true
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	sleeping = true


@rpc("authority", "call_local", "reliable")
func _start_death_visuals(impact_point: Vector3, clamped_force: Vector3) -> void:
	if not _alive or _removed:
		return
	_alive = false
	_target = null
	_death_mesh_collider.set_deferred("disabled", false)
	_flying_animation_player.stop()
	_flying_animation_player.seek(0.0, true)
	_bee_root.play_poweroff()
	_defeat_sound.play()

	# Physics impulse/fall are simulated only on authority.
	if is_multiplayer_authority():
		sleeping = false
		apply_impulse(clamped_force, impact_point)
		gravity_scale = 1.0


@rpc("authority", "call_remote", "reliable")
func _spawn_puff_remote(world_position: Vector3) -> void:
	_spawn_puff_local(world_position)


func _spawn_puff_local(world_position: Vector3) -> void:
	# Local helper used by both authority and remote RPC path.
	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = world_position


@rpc("any_peer", "call_local", "reliable")
func _request_alive_state() -> void:
	# Client asks authority for the current alive/removed state.
	if not is_multiplayer_authority():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_sync_alive_state.rpc_id(peer_id, _alive, _removed)


@rpc("authority", "call_remote", "reliable")
func _sync_alive_state(is_alive: bool, is_removed: bool) -> void:
	_alive = is_alive
	if is_removed:
		_finalize_death()


func _request_alive_state_when_connected() -> void:
	var authority_id: int = get_multiplayer_authority()
	if authority_id <= 0 or authority_id == multiplayer.get_unique_id():
		return

	if multiplayer.multiplayer_peer == null:
		if not multiplayer.connected_to_server.is_connected(_on_connected_to_server_request_alive_state):
			multiplayer.connected_to_server.connect(_on_connected_to_server_request_alive_state, CONNECT_ONE_SHOT)
		return

	# Wait one frame so RPC routing is stable after connection setup.
	call_deferred("_request_alive_state_from_authority")


func _on_connected_to_server_request_alive_state() -> void:
	_request_alive_state_from_authority()


func _request_alive_state_from_authority() -> void:
	var authority_id: int = get_multiplayer_authority()
	if authority_id <= 0 or authority_id == multiplayer.get_unique_id():
		return
	_request_alive_state.rpc_id(authority_id)


func _on_peer_connected(id: int) -> void:
	if not is_multiplayer_authority():
		return
	# Push current state to late joiners to avoid stale local bee instances.
	_sync_alive_state.rpc_id(id, _alive, _removed)


func _update_target_from_overlaps() -> void:
	var closest_target: Node3D = null
	var closest_distance_sq := INF
	for body in _detection_area.get_overlapping_bodies():
		if not (body is Node3D and _is_player_body(body)):
			continue
		var body_3d := body as Node3D
		var distance_sq := global_position.distance_squared_to(body_3d.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_target = body_3d

	if closest_target == _target:
		return

	if closest_target == null and _target != null:
		_target = null
		_reaction_animation_player.play("lost_player")
		return

	if closest_target != null:
		_shoot_count = 0.0
		_target = closest_target
		sleeping = false
		_reaction_animation_player.play("found_player")


func _is_player_body(body: Node) -> bool:
	if body.has_method("is_targetable") and not body.is_targetable():
		return false
	if body is Player:
		return true
	if body is Node and body.is_in_group("players"):
		return true
	return false


func _update_patrol_circle(delta: float) -> void:
	if patrol_radius <= 0.0:
		return
	_patrol_angle += patrol_angular_speed * delta
	var offset: Vector3 = Vector3(cos(_patrol_angle), 0.0, sin(_patrol_angle)) * patrol_radius
	var next_position: Vector3 = _patrol_center + offset
	next_position.y = _patrol_center.y + patrol_height_offset
	global_position = next_position


@rpc("authority", "call_local", "reliable")
func _spawn_bee_bullet(origin: Vector3, aim_direction: Vector3) -> void:
	var bullet := BULLET_SCENE.instantiate()
	bullet.shooter = self
	bullet.velocity = aim_direction * bullet_speed
	bullet.distance_limit = 14.0
	# Only the authority applies damage; clients keep projectile visuals synced.
	bullet.damage_enabled = is_multiplayer_authority()
	get_parent().add_child(bullet)
	bullet.global_position = origin


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_bee_transform(next_transform: Transform3D) -> void:
	_remote_target_transform = next_transform
