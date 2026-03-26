extends RigidBody3D

const COIN_SCENE := preload("res://player/coin/coin.tscn")
const PUFF_SCENE := preload("res://enemies/smoke_puff/smoke_puff.tscn")

@export var coins_count := 5
@export var stopping_distance := 0.0
@export var move_speed := 3.0
@export var attack_range := 1.4
@export var attack_cooldown := 0.6
@export var direct_chase_distance_threshold := 0.2
@export var max_health := 3
@export var bomb_damage_multiplier := 0.6
@export var bullet_damage_multiplier := 0.8
@export var charge_speed_multiplier := 2.2
@export var charge_trigger_distance := 3.0
@export var charge_duration := 0.45
@export var charge_cooldown := 1.4

@onready var _reaction_animation_player: AnimationPlayer = $ReactionLabel/AnimationPlayer
@onready var _detection_area: Area3D = $PlayerDetectionArea
@onready var _beetle_skin: Node3D = $BeetlebotSkin
@onready var _navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _death_collision_shape: CollisionShape3D = $DeathCollisionShape
@onready var _defeat_sound: AudioStreamPlayer3D = $DefeatSound

@onready var _target: Node3D = null
@onready var _alive: bool = true
@onready var _removed: bool = false
@onready var _remote_target_transform: Transform3D = global_transform
@onready var _health: int = max_health
@onready var _last_visual_position: Vector3 = global_position
var _assigned_target_peer_id := -1
var _last_attack_time_sec := -100.0
var _charge_until_sec := -100.0
var _last_charge_time_sec := -100.0
var _visual_state := "Idle"


func _ready() -> void:
	add_to_group("ground_enemies")
	add_to_group("beetles")
	can_sleep = false
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)
	_detection_area.monitoring = true
	_detection_area.monitorable = true
	if _beetle_skin == null:
		push_error("BeetlebotSkin missing in beetle_bot.tscn")
		return
	_health = max_health
	_set_visual_state("Idle")
	if is_multiplayer_authority():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_request_alive_state_when_connected()


func _physics_process(delta: float) -> void:
	if _removed:
		return
	if not is_multiplayer_authority():
		global_transform = global_transform.interpolate_with(_remote_target_transform, 0.35)
		_update_remote_visual_animation()
		return
	if not _alive:
		return

	_refresh_assigned_target()

	if _target == null or not is_instance_valid(_target):
		sleeping = false
		linear_velocity = Vector3.ZERO
		_set_visual_state("Idle")
		return

	sleeping = false
	var target_look_position := _target.global_position
	target_look_position.y = global_position.y
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > 0.01:
		look_at(target_look_position)

	_navigation_agent.target_position = _target.global_position
	var next_location := _navigation_agent.get_next_path_position()
	var direction := next_location - global_position
	direction.y = 0.0
	var navigation_has_useful_path := not _navigation_agent.is_navigation_finished() and direction.length() > direct_chase_distance_threshold
	if not navigation_has_useful_path and to_target.length() > stopping_distance:
		direction = to_target
	var now_sec := Time.get_ticks_msec() / 1000.0
	var is_charge_ready := now_sec - _last_charge_time_sec >= charge_cooldown
	if to_target.length() <= charge_trigger_distance and is_charge_ready:
		_charge_until_sec = now_sec + charge_duration
		_last_charge_time_sec = now_sec

	if _navigation_agent.is_target_reached() or direction.length() <= stopping_distance:
		linear_velocity = Vector3.ZERO
		_set_visual_state("Idle")
	else:
		var current_speed := move_speed
		if now_sec <= _charge_until_sec:
			current_speed *= charge_speed_multiplier
		direction = direction.normalized()
		linear_velocity.x = direction.x * current_speed
		linear_velocity.z = direction.z * current_speed
		linear_velocity.y = 0.0
		_set_visual_state("Walk")

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
	if _beetle_skin == null or _visual_state == state_name:
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


func _update_remote_visual_animation() -> void:
	if not _alive or _removed:
		return
	var moved_distance := global_position.distance_to(_last_visual_position)
	_last_visual_position = global_position
	if moved_distance > 0.01:
		_set_visual_state("Walk")
	else:
		_set_visual_state("Idle")


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
	if _removed:
		visible = false
		return
	visible = active
	sleeping = not active
	if not active:
		_target = null
		_set_visual_state("Idle")


func set_assigned_target_peer_id(peer_id: int) -> void:
	_assigned_target_peer_id = peer_id
	if peer_id <= 0:
		_target = null
		return
	_refresh_assigned_target()


func get_assigned_target_peer_id() -> int:
	return _assigned_target_peer_id


func get_current_target_peer_id() -> int:
	if _target == null or not is_instance_valid(_target):
		return -1
	return _target.get_multiplayer_authority()


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


func _find_player_by_peer(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		if node.get_multiplayer_authority() == peer_id:
			return node as Node3D
	return null


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
	if multiplayer.multiplayer_peer == null:
		if not multiplayer.connected_to_server.is_connected(_on_connected_to_server_request_alive_state):
			multiplayer.connected_to_server.connect(_on_connected_to_server_request_alive_state, CONNECT_ONE_SHOT)
		return
	call_deferred("_request_alive_state_from_authority")


func _on_connected_to_server_request_alive_state() -> void:
	_request_alive_state_from_authority()


func _request_alive_state_from_authority() -> void:
	var authority_id := get_multiplayer_authority()
	if authority_id <= 0 or authority_id == multiplayer.get_unique_id():
		return
	_request_alive_state.rpc_id(authority_id)


func _on_peer_connected(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	_sync_alive_state.rpc_id(peer_id, _alive, _removed)
