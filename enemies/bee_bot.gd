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
@onready var _patrol_center: Vector3 = global_position
@onready var _patrol_angle := 0.0
@onready var _remote_target_transform: Transform3D = global_transform


func _ready() -> void:
	_detection_area.monitoring = true
	_detection_area.monitorable = true
	_patrol_center = global_position
	_patrol_angle = randf() * TAU
	_bee_root.play_idle()


func _physics_process(delta: float) -> void:
	if not _alive:
		return

	if not is_multiplayer_authority():
		# Clients only render replicated movement from authority.
		global_transform = global_transform.interpolate_with(_remote_target_transform, 0.35)
		return

	_update_target_from_overlaps()
	if patrol_circle and _target == null:
		_update_patrol_circle(delta)

	if _target != null:
		if sleeping:
			sleeping = false
		var target_transform := transform.looking_at(_target.global_position)
		transform = transform.interpolate_with(target_transform, 0.1)

		_shoot_count += delta
		if _shoot_count > shoot_timer:
			_bee_root.play_spit_attack()
			_shoot_count -= shoot_timer

			var origin := global_position
			var target := _target.global_position + Vector3.UP
			var aim_direction := (target - global_position).normalized()
			_spawn_bee_bullet.rpc(origin, aim_direction)

	_sync_bee_transform.rpc(global_transform)


func damage(impact_point: Vector3, force: Vector3) -> void:
	force = force.limit_length(3.0)
	apply_impulse(force, impact_point)

	if not _alive:
		return

	_defeat_sound.play()
	_alive = false

	_flying_animation_player.stop()
	_flying_animation_player.seek(0.0, true)
	_target = null
	_death_mesh_collider.set_deferred("disabled", false)

	gravity_scale = 1.0
	_bee_root.play_poweroff()

	await get_tree().create_timer(2).timeout

	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position
	await puff.full
	for i in range(coins_count):
		var coin := COIN_SCENE.instantiate()
		get_parent().add_child(coin)
		coin.global_position = global_position
		coin.spawn()
	queue_free()


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
