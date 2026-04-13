extends "res://enemies/enemy_instance_base.gd"

const COIN_SCENE := preload("res://player/coin/coin.tscn")
const PUFF_SCENE := preload("res://enemies/smoke_puff/smoke_puff.tscn")

@export var coins_count := 5
@export var stopping_distance := 0.0
@export var move_speed := 2.2
@export var attack_range := 1.4
@export var attack_cooldown := 0.6
@export var direct_chase_distance_threshold := 0.2
@export var max_health := 3
@export var bomb_damage_multiplier := 0.6
@export var bullet_damage_multiplier := 0.8
@export var charge_speed_multiplier := 1.45
@export var charge_trigger_distance := 2.4
@export var charge_duration := 0.28
@export var charge_cooldown := 1.8
@export var close_stop_distance := 0.05
@export var ground_probe_height := 0.9
@export var ground_probe_depth := 8.0
@export var ground_offset := 0.05
@export var airborne_tolerance := 0.22
@export var ground_snap_distance := 0.08
@export var ground_return_speed := 8.5
@export var fallback_detection_radius := 8.0
@export var stuck_nudge_distance := 0.18
@export var guard_chase_radius := 10.0
@export var guard_return_radius := 12.5
@export var return_home_stop_distance := 0.45

@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _beetle_skin: Node3D = $BeetlebotSkin
@onready var _navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _death_collision_shape: CollisionShape3D = $DeathCollisionShape
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound
@onready var _default_collision_layer: int = collision_layer
@onready var _default_collision_mask: int = collision_mask

@onready var _target: Node3D = null
@onready var _alive: bool = true
@onready var _removed: bool = false
@onready var _remote_target_transform: Transform3D = global_transform
@onready var _health: int = max_health
@onready var _home_position: Vector3 = global_position
@onready var _guard_center: Vector3 = global_position
@onready var _is_network_proxy: bool = false
var _last_attack_time_sec := -100.0
var _charge_until_sec := -100.0
var _last_charge_time_sec := -100.0
var _visual_state := "Idle"


func _ready() -> void:
	_register_enemy_groups(PackedStringArray(["ground_enemies", "beetles"]))
	can_sleep = false
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)
	_detection_area.monitoring = true
	_detection_area.monitorable = true
	if _beetle_skin == null:
		push_error("BeetlebotSkin missing in beetle_bot.tscn")
		return
	_health = max_health
	_home_position = global_position
	_guard_center = global_position
	_set_visual_state("Idle")
	if is_multiplayer_authority():
		freeze = false
	else:
		_is_network_proxy = true
		freeze = true
		linear_velocity = Vector3.ZERO
		_request_alive_state_when_connected()


func _physics_process(delta: float) -> void:
	if _removed:
		return
	if not is_multiplayer_authority():
		linear_velocity = Vector3.ZERO
		var remote_origin: Vector3 = _remote_target_transform.origin
		if global_position.distance_to(remote_origin) > 4.0 or absf(global_position.y - remote_origin.y) > 1.5:
			global_transform = _remote_target_transform
		else:
			global_transform = global_transform.interpolate_with(_remote_target_transform, 0.35)
		return
	if not _alive:
		return

	_refresh_assigned_target()
	if _target == null or not is_instance_valid(_target):
		_refresh_target_from_detection_area()
	if _target != null and not _should_keep_target(_target):
		_target = null

	if _target == null or not is_instance_valid(_target):
		_return_to_guard_position(delta)
		return

	sleeping = false
	var position_before: Vector3 = global_position
	var target_look_position := _target.global_position
	target_look_position.y = global_position.y
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var chase_target_position: Vector3 = _get_chase_target_position(_target.global_position)
	var to_chase_target := chase_target_position - global_position
	to_chase_target.y = 0.0
	if to_target.length() > 0.01:
		look_at(target_look_position)

	_navigation_agent.target_position = chase_target_position
	var next_location := _navigation_agent.get_next_path_position()
	var direction := next_location - global_position
	direction.y = 0.0
	var navigation_has_useful_path := not _navigation_agent.is_navigation_finished() and direction.length() > direct_chase_distance_threshold
	if not navigation_has_useful_path and to_chase_target.length() > stopping_distance:
		direction = to_chase_target
	var now_sec := Time.get_ticks_msec() / 1000.0
	var is_charge_ready := now_sec - _last_charge_time_sec >= charge_cooldown
	if to_target.length() <= charge_trigger_distance and is_charge_ready:
		_charge_until_sec = now_sec + charge_duration
		_last_charge_time_sec = now_sec

	var stop_threshold: float = maxf(close_stop_distance, stopping_distance)
	if to_target.length() <= stop_threshold or direction.length() <= 0.001:
		linear_velocity = Vector3.ZERO
		_set_visual_state("Idle")
	else:
		var current_speed := move_speed
		if now_sec <= _charge_until_sec:
			current_speed *= charge_speed_multiplier
		direction = direction.normalized()
		linear_velocity.x = direction.x * current_speed
		linear_velocity.z = direction.z * current_speed
		_set_visual_state("Walk")

	_apply_ground_recovery(delta)
	_try_unstuck_toward_direction(position_before, direction, to_target, stop_threshold)

	if to_target.length() <= attack_range:
		_try_attack_target(_target)

	_sync_beetle_transform.rpc(global_transform)


func damage(impact_point: Vector3, force: Vector3, attacker_peer_id: int = -1) -> void:
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
	_health -= _compute_damage_amount(force)
	if _health > 0:
		sleeping = false
		apply_central_impulse(force.limit_length(2.5))
		return
	lock_rotation = false
	force = force.limit_length(3.0)
	_start_death_visuals.rpc(impact_point, force)
	_report_score_for_kill(attacker_peer_id)

	await get_tree().create_timer(2).timeout

	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position
	_spawn_puff_remote.rpc(global_position)
	await puff.full
	for i in range(coins_count):
		var coin := COIN_SCENE.instantiate()
		get_parent().add_child(coin)
		coin.global_position = global_position
		coin.spawn()
	_finalize_death.rpc()


func _on_body_entered(body: Node3D) -> void:
	if _assigned_target_peer_id > 0:
		return
	if body is Player:
		_target = body
		_reaction_animation_player.play("found_player")


func _on_body_exited(body: Node3D) -> void:
	if _assigned_target_peer_id > 0:
		return
	if body is Player:
		_target = null
		_reaction_animation_player.play("lost_player")
		_set_visual_state("Idle")


func _try_attack_target(target: Node3D) -> void:
	if not (target is Player):
		return
	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec - _last_attack_time_sec < attack_cooldown:
		return
	_last_attack_time_sec = now_sec
	var impact_point: Vector3 = global_position - target.global_position
	var force := -impact_point
	force.y = 0.5
	force *= 10.0
	target.damage(impact_point, force)
	_set_visual_state("Attack")


func _compute_damage_amount(force: Vector3) -> int:
	var magnitude := force.length()
	if magnitude >= 6.0:
		return maxi(1, int(round(magnitude * bomb_damage_multiplier / 3.0)))
	if magnitude >= 2.0:
		return maxi(1, int(round(magnitude * bullet_damage_multiplier / 2.5)))
	return 1


func _set_visual_state(state_name: String) -> void:
	if _visual_state == state_name:
		return
	_apply_visual_state_local(state_name)
	if is_multiplayer_authority():
		_sync_visual_state.rpc(state_name)


func _apply_visual_state_local(state_name: String) -> void:
	if _beetle_skin == null:
		return
	_visual_state = state_name
	match state_name:
		"Idle":
			_beetle_skin.idle()
		"Walk":
			_beetle_skin.walk()
		"Attack":
			_beetle_skin.attack()
		"PowerOff":
			_beetle_skin.power_off()


@rpc("authority", "call_remote", "reliable")
func _sync_visual_state(state_name: String) -> void:
	_apply_visual_state_local(state_name)


func _apply_ground_recovery(delta: float) -> void:
	var ground_y: float = _find_ground_y_below()
	if is_inf(ground_y):
		linear_velocity.y = minf(linear_velocity.y, -ground_return_speed)
		return
	var desired_y: float = ground_y + ground_offset
	var vertical_gap: float = global_position.y - desired_y
	if vertical_gap > airborne_tolerance:
		var recovery_speed := ground_return_speed + minf(6.0, vertical_gap * 5.0)
		linear_velocity.y = minf(linear_velocity.y, -recovery_speed)
		return
	if absf(vertical_gap) <= ground_snap_distance:
		global_position.y = desired_y
		linear_velocity.y = 0.0
		return
	if vertical_gap < -ground_snap_distance:
		global_position.y = lerpf(global_position.y, desired_y, minf(1.0, delta * 10.0))
		linear_velocity.y = 0.0
		return
	linear_velocity.y = 0.0


func _find_ground_y_below() -> float:
	if get_world_3d() == null:
		return INF
	var from: Vector3 = global_position + Vector3.UP * ground_probe_height
	var to: Vector3 = global_position + Vector3.DOWN * ground_probe_depth
	var exclude: Array[Variant] = [self]
	for _attempt in range(8):
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = exclude
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return INF
		var collider: Variant = hit.get("collider")
		if collider is RigidBody3D or (collider is Node and ((collider as Node).is_in_group("players") or (collider as Node).is_in_group("ground_enemies"))):
			exclude.append(collider)
			continue
		var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
		return hit_position.y
	return INF


func _report_score_for_kill(attacker_peer_id: int) -> void:
	var director := get_tree().get_first_node_in_group("match_director")
	if not is_instance_valid(director):
		return
	if director.has_method("report_enemy_killed"):
		director.report_enemy_killed("beetle_bot", attacker_peer_id)


@rpc("authority", "call_local", "reliable")
func _start_death_visuals(impact_point: Vector3, clamped_force: Vector3) -> void:
	if not _alive or _removed:
		return
	_alive = false
	_target = null
	_defeat_sound.play()
	_set_visual_state("PowerOff")
	if _detection_area.body_entered.is_connected(_on_body_entered):
		_detection_area.body_entered.disconnect(_on_body_entered)
	if _detection_area.body_exited.is_connected(_on_body_exited):
		_detection_area.body_exited.disconnect(_on_body_exited)
	_detection_area.monitoring = false
	_detection_area.monitorable = false
	_death_collision_shape.set_deferred("disabled", false)
	axis_lock_angular_x = false
	axis_lock_angular_y = false
	axis_lock_angular_z = false
	gravity_scale = 1.0
	if is_multiplayer_authority():
		sleeping = false
		apply_impulse(clamped_force, impact_point)


@rpc("authority", "call_remote", "reliable")
func _spawn_puff_remote(world_position: Vector3) -> void:
	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = world_position


@rpc("authority", "call_local", "reliable")
func _finalize_death() -> void:
	if _removed:
		return
	_bump_state_revision()
	_removed = true
	visible = false
	set_process(false)
	set_physics_process(false)
	_detection_area.monitoring = false
	_detection_area.monitorable = false
	_death_collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	sleeping = true
	linear_velocity = Vector3.ZERO


func set_director_active(active: bool) -> void:
	_bump_state_revision()
	if _removed:
		visible = false
		return
	visible = active
	sleeping = not active
	if active:
		collision_layer = _default_collision_layer
		collision_mask = _default_collision_mask
		_detection_area.monitoring = true
		_detection_area.monitorable = true
		_home_position = global_position
		if _guard_center == Vector3.ZERO:
			_guard_center = global_position
		if not _is_network_proxy:
			freeze = false
	else:
		collision_layer = 0
		collision_mask = 0
		_detection_area.monitoring = false
		_detection_area.monitorable = false
		linear_velocity = Vector3.ZERO
		if _is_network_proxy:
			freeze = true
	if not active:
		_target = null
		_set_visual_state("Idle")


func set_assigned_target_peer_id(peer_id: int) -> void:
	_bump_state_revision()
	_assigned_target_peer_id = peer_id
	if peer_id <= 0:
		_target = null
		return
	_refresh_assigned_target()


func set_guard_center(world_position: Vector3) -> void:
	_guard_center = world_position


func apply_director_config(config: Dictionary) -> void:
	_bump_state_revision()
	if config.has("move_speed"):
		move_speed = float(config["move_speed"])
	if config.has("charge_speed_multiplier"):
		charge_speed_multiplier = float(config["charge_speed_multiplier"])
	if config.has("guard_chase_radius"):
		guard_chase_radius = float(config["guard_chase_radius"])
	if config.has("guard_return_radius"):
		guard_return_radius = float(config["guard_return_radius"])
	if config.has("guard_center"):
		set_guard_center(config["guard_center"])


func get_guard_center() -> Vector3:
	return _guard_center


func get_assigned_target_peer_id() -> int:
	return _assigned_target_peer_id


func get_current_target_peer_id() -> int:
	if _target == null or not is_instance_valid(_target):
		return -1
	return _target.get_multiplayer_authority()


func _request_current_state_from_server_impl() -> void:
	_request_alive_state_when_connected()


func _push_current_state_to_peer_impl(peer_id: int) -> void:
	if peer_id <= 0 or not is_multiplayer_authority():
		return
	_sync_alive_state.rpc_id(peer_id, _alive, _removed)
	_sync_visual_state.rpc_id(peer_id, _visual_state)
	_sync_beetle_transform.rpc_id(peer_id, global_transform)


func _get_debug_sync_summary_impl() -> String:
	return "scarabee=%s alive=%s cible_assignee=J%s cible=J%s rev=%d" % [
		String(name),
		str(_alive and not _removed),
		"-" if _assigned_target_peer_id <= 0 else str(_assigned_target_peer_id),
		"-" if get_current_target_peer_id() <= 0 else str(get_current_target_peer_id()),
		_state_revision,
	]


func _refresh_assigned_target() -> void:
	if _assigned_target_peer_id <= 0:
		return
	var assigned_player := _find_player_by_peer(_assigned_target_peer_id)
	if assigned_player == null:
		_target = null
		return
	if assigned_player.has_method("is_dead") and bool(assigned_player.call("is_dead")):
		_target = null
		return
	if _target == assigned_player:
		return
	_target = assigned_player
	if _reaction_animation_player != null:
		_reaction_animation_player.play("found_player")


func _refresh_target_from_detection_area() -> void:
	var closest_target: Node3D = null
	var closest_distance_sq: float = INF
	for body in _detection_area.get_overlapping_bodies():
		if not (body is Node3D):
			continue
		var body_3d: Node3D = body as Node3D
		if not _is_valid_player_target(body_3d):
			continue
		var distance_sq: float = global_position.distance_squared_to(body_3d.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_target = body_3d
	if closest_target == null:
		closest_target = _find_nearest_player_by_distance()
	if closest_target == null:
		return
	if _target == closest_target:
		return
	_target = closest_target
	if _reaction_animation_player != null:
		_reaction_animation_player.play("found_player")


func _find_player_by_peer(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		if node.get_multiplayer_authority() == peer_id:
			var player: Node3D = node as Node3D
			if _is_valid_player_target(player):
				return player
			return null
	return null


func _is_valid_player_target(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_dead") and bool(candidate.call("is_dead")):
		return false
	if not _is_within_guard_radius(candidate.global_position, guard_chase_radius):
		return false
	return true


func _find_nearest_player_by_distance() -> Node3D:
	var radius: float = _get_detection_radius()
	var max_distance_sq: float = radius * radius
	var closest_target: Node3D = null
	var closest_distance_sq: float = INF
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		var candidate: Node3D = node as Node3D
		if not _is_valid_player_target(candidate):
			continue
		var distance_sq: float = global_position.distance_squared_to(candidate.global_position)
		if distance_sq > max_distance_sq:
			continue
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_target = candidate
	return closest_target


func _get_detection_radius() -> float:
	var collision_shape: CollisionShape3D = _detection_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape != null and collision_shape.shape is SphereShape3D:
		return minf(maxf(0.1, (collision_shape.shape as SphereShape3D).radius), fallback_detection_radius)
	return maxf(0.1, fallback_detection_radius)


func _should_keep_target(target: Node3D) -> bool:
	if not _is_valid_player_target(target):
		return false
	if not _is_within_guard_radius(target.global_position, guard_return_radius):
		return false
	if not _is_within_guard_radius(global_position, guard_return_radius * 1.15):
		return false
	return true


func _is_within_guard_radius(world_position: Vector3, radius: float) -> bool:
	var horizontal_offset := world_position - _guard_center
	horizontal_offset.y = 0.0
	return horizontal_offset.length() <= maxf(0.1, radius)


func _return_to_guard_position(delta: float) -> void:
	sleeping = false
	# Retourner vers _guard_center (l'Activator) et non vers le spawn d'origine
	var to_home := _guard_center - global_position
	to_home.y = 0.0
	var distance_to_home: float = to_home.length()
	if distance_to_home <= return_home_stop_distance:
		linear_velocity.x = 0.0
		linear_velocity.z = 0.0
		_apply_ground_recovery(delta)
		_set_visual_state("Idle")
		_sync_beetle_transform.rpc(global_transform)
		return
	var direction := to_home.normalized()
	var look_target := _guard_center
	look_target.y = global_position.y
	look_at(look_target)
	linear_velocity.x = direction.x * move_speed
	linear_velocity.z = direction.z * move_speed
	_apply_ground_recovery(delta)
	_set_visual_state("Walk")
	_sync_beetle_transform.rpc(global_transform)


func _try_unstuck_toward_direction(position_before: Vector3, direction: Vector3, to_target: Vector3, stop_threshold: float) -> void:
	if direction.length() <= 0.001 or to_target.length() <= stop_threshold:
		return
	if to_target.length() <= maxf(stop_threshold, attack_range + 0.25):
		return
	var horizontal_delta := global_position - position_before
	horizontal_delta.y = 0.0
	if horizontal_delta.length() > 0.01:
		return
	var nudge_direction := direction.normalized()
	global_position += Vector3(nudge_direction.x, 0.0, nudge_direction.z) * stuck_nudge_distance


func _get_chase_target_position(target_position: Vector3) -> Vector3:
	var waypoint: Vector3 = _find_open_door_waypoint(target_position)
	return waypoint if not waypoint.is_equal_approx(Vector3.INF) else target_position


func _find_open_door_waypoint(target_position: Vector3) -> Vector3:
	var open_doors: Array[Node3D] = []
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for candidate in get_tree().get_nodes_in_group("bomb_reactives"):
		if not (candidate is Node3D):
			continue
		if not candidate.has_method("is_open") or not bool(candidate.call("is_open")):
			continue
		var door: Node3D = candidate as Node3D
		open_doors.append(door)
		min_x = minf(min_x, door.global_position.x)
		max_x = maxf(max_x, door.global_position.x)
		min_z = minf(min_z, door.global_position.z)
		max_z = maxf(max_z, door.global_position.z)
	if open_doors.is_empty():
		return Vector3.INF
	var best_door: Node3D = open_doors[0]
	var best_distance_to_target: float = best_door.global_position.distance_squared_to(target_position)
	for index in range(1, open_doors.size()):
		var candidate_door: Node3D = open_doors[index]
		var candidate_distance: float = candidate_door.global_position.distance_squared_to(target_position)
		if candidate_distance >= best_distance_to_target:
			continue
		best_door = candidate_door
		best_distance_to_target = candidate_distance
	var span_x: float = max_x - min_x
	var span_z: float = max_z - min_z
	var use_z_axis: bool = span_x >= span_z
	var beetle_axis_delta: float = global_position.z - best_door.global_position.z if use_z_axis else global_position.x - best_door.global_position.x
	var target_axis_delta: float = target_position.z - best_door.global_position.z if use_z_axis else target_position.x - best_door.global_position.x
	if absf(beetle_axis_delta) < 0.9 or absf(target_axis_delta) < 0.9:
		return Vector3.INF
	if signf(beetle_axis_delta) == signf(target_axis_delta):
		return Vector3.INF
	var waypoint := best_door.global_position
	waypoint.y = global_position.y
	return waypoint


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_beetle_transform(authority_transform: Transform3D) -> void:
	_remote_target_transform = authority_transform


@rpc("any_peer", "call_local", "reliable")
func _request_alive_state() -> void:
	if not is_multiplayer_authority():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_sync_alive_state.rpc_id(peer_id, _alive, _removed)


@rpc("authority", "call_remote", "reliable")
func _sync_alive_state(is_alive: bool, is_removed: bool) -> void:
	_alive = is_alive
	if is_removed:
		_finalize_death()


func _request_alive_state_when_connected() -> void:
	var authority_id := get_multiplayer_authority()
	if authority_id <= 0 or authority_id == multiplayer.get_unique_id():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_alive_state")):
		return
	call_deferred("_request_alive_state_from_authority")


func _on_connected_to_server_request_alive_state() -> void:
	_request_alive_state_from_authority()


func _request_alive_state_from_authority() -> void:
	var authority_id := get_multiplayer_authority()
	if authority_id <= 0 or authority_id == multiplayer.get_unique_id():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_alive_state")):
		return
	_request_alive_state.rpc_id(authority_id)
