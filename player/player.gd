extends CharacterBody3D
class_name Player
var BombScene = preload("res://main/static_body_3d_bomb.tscn")

## Character maximum run speed on the ground.
@export var move_speed := 8.0
## Forward impulse after a melee attack.
@export var attack_impulse := 10.0
## Movement acceleration (how fast character achieve maximum speed)
@export var acceleration := 6.0
## Jump impulse
@export var jump_initial_impulse := 12.0
## Jump impulse when player keeps pressing jump
@export var jump_additional_force := 4.5
## Player model rotation speed
@export var rotation_speed := 12.0
## Minimum horizontal speed on the ground. This controls when the character's animation tree changes
## between the idle and running states.
@export var stopping_speed := 1.0
## Clamp sync delta for faster interpolation
@export var sync_delta_max := 0.2

@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _attack_animation_player: AnimationPlayer = $CharacterRotationRoot/MeleeAnchor/AnimationPlayer
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var _character_skin: CharacterSkin = $CharacterRotationRoot/CharacterSkin
@onready var _synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var _character_collision_shape: CollisionShape3D = $CharacterCollisionShape
@onready var _nickname: Control = $Nickname
@onready var _lives_overlay: CanvasLayer = $LivesOverlay
@onready var _lives_label: Label = $LivesOverlay/LivesLabel
@onready var _death_overlay: CanvasLayer = $DeathOverlay
@onready var _hit_sound: AudioStreamPlayer3D = $HitSound

@onready var _move_direction := Vector3.ZERO
@onready var _last_strong_direction := Vector3.FORWARD
@onready var _gravity: float = -30.0
@onready var _ground_height: float = 0.0

## Sync properties
@export var _position: Vector3
@export var _velocity: Vector3
@export var _direction: Vector3 = Vector3.ZERO
@export var _strong_direction: Vector3 = Vector3.FORWARD

var position_before_sync: Vector3

var last_sync_time_ms: int
var sync_delta: float
var _is_dead := false
var _lives := 5
var _coins := 0
var _last_hit_time_sec := -100.0
var _default_collision_layer := 1
var _default_collision_mask := 1

const ENEMY_HIT_DAMAGE := 1
const ENEMY_HIT_COOLDOWN := 0.35
const ENEMY_HIT_KNOCKBACK := 4.5
const ENEMY_HIT_UPWARD_BONUS := 1.2

func _unhandled_input(event: InputEvent) -> void:
	if _is_dead:
		return
	if event is InputEventKey and event.pressed:
		# Debug : quel code la touche renvoie
		#print("Key pressed: scancode =", event)

		# Exemple : KEY_1 ou remplace par le scancode correct
		if event.pressed and event.keycode == KEY_B:
			DebugLog.gameplay("place_bomb detectee")
			place_bomb()

func _ready() -> void:
	add_to_group("players")
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	DebugLog.gameplay("Player ready | peer=%d authority=%s" % [multiplayer.get_unique_id(), str(is_multiplayer_authority())])
	_lives_overlay.visible = is_multiplayer_authority()
	_update_lives_label()
	_death_overlay.visible = false
	# Only the authority owns camera/input simulation; remotes are interpolation-only.
	if is_multiplayer_authority():
		_camera_controller.setup(self)
	else:
		rotation_speed /= 1.5
		_synchronizer.delta_synchronized.connect(on_synchronized)
		_synchronizer.synchronized.connect(on_synchronized)
		on_synchronized()

func place_bomb() -> void:
	DebugLog.gameplay("place_bomb called, authority=%s" % str(is_multiplayer_authority()))
	if is_multiplayer_authority():
		DebugLog.gameplay("spawning bomb via RPC")
		# Compute once on authority so all peers spawn the bomb at the same position.
		var bomb_pos: Vector3 = global_position + transform.basis.z * 1.0
		spawn_bomb.rpc(bomb_pos)

@rpc("any_peer", "call_local", "reliable")
func spawn_bomb(pos: Vector3):
	DebugLog.gameplay("Bomb creating")
	var bomb = BombScene.instantiate()
	get_parent().add_child(bomb)
	bomb.global_position = pos
	DebugLog.gameplay("Bomb spawned at %s" % str(bomb.global_position))
	
func _physics_process(delta: float) -> void:
	# Remote players never run gameplay physics locally.
	if not is_multiplayer_authority(): interpolate_client(delta); return
	if _is_dead:
		_move_direction = Vector3.ZERO
		velocity = Vector3.ZERO
		set_sync_properties()
		return
	
	# Calculate ground height for camera controller
	if _ground_shapecast.get_collision_count() > 0:
		for collision_result in _ground_shapecast.collision_result:
			_ground_height = max(_ground_height, collision_result.point.y)
	else:
		_ground_height = global_position.y + _ground_shapecast.target_position.y
	if global_position.y < _ground_height:
		_ground_height = global_position.y
	
	# Get input and movement state
	var is_just_attacking := Input.is_action_just_pressed("attack")
	var is_just_jumping := Input.is_action_just_pressed("jump") and is_on_floor()
	var is_air_boosting := Input.is_action_pressed("jump") and not is_on_floor() and velocity.y > 0.0
	
	_move_direction = _get_camera_oriented_input()
	
	if EditMode.is_enabled:
		is_just_jumping = false
		is_air_boosting = false
		_move_direction = Vector3.ZERO
	
	# To not orient quickly to the last input, we save a last strong direction,
	# this also ensures a good normalized value for the rotation basis.
	if _move_direction.length() > 0.2:
		_last_strong_direction = _move_direction.normalized()
	
	_orient_character_to_direction(_last_strong_direction, delta)
	
	# We separate out the y velocity to not interpolate on the gravity
	var y_velocity := velocity.y
	velocity.y = 0.0
	velocity = velocity.lerp(_move_direction * move_speed, acceleration * delta)
	if _move_direction.length() == 0 and velocity.length() < stopping_speed:
		velocity = Vector3.ZERO
	velocity.y = y_velocity
	
	# Update position
	if is_just_attacking and not _attack_animation_player.is_playing():
		attack()
	
	velocity.y += _gravity * delta
	
	if is_just_jumping:
		velocity.y += jump_initial_impulse
	elif is_air_boosting:
		velocity.y += jump_additional_force * delta
	
	# Set character animation
	if is_just_jumping:
		_character_skin.jump.rpc()
	elif not is_on_floor() and velocity.y < 0:
		_character_skin.fall.rpc()
	elif is_on_floor():
		var xz_velocity := Vector3(velocity.x, 0, velocity.z)
		if xz_velocity.length() > stopping_speed:
			_character_skin.set_moving.rpc(true)
			_character_skin.set_moving_speed.rpc(inverse_lerp(0.0, move_speed, xz_velocity.length()))
		else:
			_character_skin.set_moving.rpc(false)
	
	var position_before := global_position
	move_and_slide()
	var position_after := global_position
	
	# If velocity is not 0 but the difference of positions after move_and_slide is,
	# character might be stuck somewhere!
	var delta_position := position_after - position_before
	var epsilon := 0.001
	if delta_position.length() < epsilon and velocity.length() > epsilon:
		global_position += get_wall_normal() * 0.1
	
	set_sync_properties()
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_collider() is RigidBody3D:
			var body := collision.get_collider() as RigidBody3D
			var push_dir: Vector3 = -collision.get_normal()
			var impulse: Vector3 = push_dir * 1.5
			var body_authority: int = body.get_multiplayer_authority()
			# Push requests must be executed by the rigidbody authority.
			if body.has_method("request_push"):
				if body_authority == multiplayer.get_unique_id():
					body.request_push(impulse)
				else:
					body.request_push.rpc_id(body_authority, impulse)
			elif body_authority == multiplayer.get_unique_id():
				body.apply_central_impulse(impulse)



func attack() -> void:
	_attack_animation_player.play("Attack")
	_character_skin.punch.rpc()
	velocity = _rotation_root.transform.basis * Vector3.BACK * attack_impulse


func set_sync_properties() -> void:
	_position = position
	_velocity = velocity
	_direction = _move_direction
	_strong_direction = _last_strong_direction


func on_synchronized() -> void:
	velocity = _velocity
	position_before_sync = position
	
	var sync_time_ms = Time.get_ticks_msec()
	sync_delta = clampf(float(sync_time_ms - last_sync_time_ms) / 1000, 0, sync_delta_max)
	last_sync_time_ms = sync_time_ms
	
func interpolate_client(delta: float) -> void:
	_orient_character_to_direction(_strong_direction, delta)
	
	if _direction.length() == 0:
		# Don't interpolate to avoid small jitter when stopping
		if (_position - position).length() > 1.0 and _velocity.is_zero_approx():
			position = _position # Fix misplacement
	else:
		# Interpolate between position_before_sync and _position
		# and add to ongoing movement to compensate misplacement
		var t = 1.0 if is_zero_approx(sync_delta) else delta / sync_delta
		sync_delta = clampf(sync_delta - delta, 0, sync_delta_max)
		
		var less_misplacement = position_before_sync.move_toward(_position, t)
		position += less_misplacement - position_before_sync
		position_before_sync = less_misplacement
	
	velocity.y += _gravity * delta
	move_and_slide()


func _get_camera_oriented_input() -> Vector3:
	var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	var input := Vector3.ZERO
	# This is to ensure that diagonal input isn't stronger than axis aligned input
	input.x = -raw_input.x * sqrt(1.0 - raw_input.y * raw_input.y / 2.0)
	input.z = -raw_input.y * sqrt(1.0 - raw_input.x * raw_input.x / 2.0)
	
	input = _camera_controller.global_transform.basis * input
	input.y = 0.0
	return input


func _orient_character_to_direction(direction: Vector3, delta: float) -> void:
	var left_axis := Vector3.UP.cross(direction)
	var rotation_basis := Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var model_scale := _rotation_root.transform.basis.get_scale()
	_rotation_root.transform.basis = Basis(_rotation_root.transform.basis.get_rotation_quaternion().slerp(rotation_basis, delta * rotation_speed)).scaled(
		model_scale
	)


@rpc("any_peer", "call_remote", "reliable")
func respawn(spawn_position: Vector3) -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	# Local authority reattaches gameplay camera when returning from dead/spectator.
	if is_multiplayer_authority() and _is_dead:
		_camera_controller.exit_spectator(self)


@rpc("any_peer", "call_local", "reliable")
func set_dead_state(dead: bool) -> void:
	_is_dead = dead
	velocity = Vector3.ZERO
	_move_direction = Vector3.ZERO
	_character_collision_shape.disabled = dead
	collision_layer = 0 if dead else _default_collision_layer
	collision_mask = 0 if dead else _default_collision_mask
	_rotation_root.visible = not dead
	_nickname.visible = not dead
	if dead and is_in_group("players"):
		remove_from_group("players")
	elif not dead and not is_in_group("players"):
		add_to_group("players")
	if is_multiplayer_authority():
		# Spectator mode is local-only UX; dead state itself is replicated.
		_camera_controller.set_spectator_mode(dead)
		if not dead:
			_camera_controller.exit_spectator(self)
		_death_overlay.visible = dead


@rpc("any_peer", "call_remote", "reliable")
func set_lives(lives: int) -> void:
	_lives = maxi(0, lives)
	if is_multiplayer_authority():
		_update_lives_label()


func _update_lives_label() -> void:
	_lives_label.text = "Vies: %d" % _lives


func collect_coin() -> void:
	var authority_id := get_multiplayer_authority()
	if multiplayer.get_unique_id() == authority_id:
		_coins += 1
	else:
		_collect_coin.rpc_id(authority_id)


@rpc("any_peer", "call_local", "reliable")
func _collect_coin() -> void:
	if not is_multiplayer_authority():
		return
	_coins += 1


func damage(_impact_point: Vector3, force: Vector3) -> void:
	# Enemy hit application is authority-owned to avoid double damage across peers.
	var authority_id := get_multiplayer_authority()
	if multiplayer.get_unique_id() == authority_id:
		_apply_enemy_hit(force)
	else:
		apply_enemy_hit.rpc_id(authority_id, force)


@rpc("any_peer", "call_local", "reliable")
func apply_enemy_hit(force: Vector3) -> void:
	_apply_enemy_hit(force)


func _apply_enemy_hit(force: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	if _is_dead:
		return

	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec - _last_hit_time_sec < ENEMY_HIT_COOLDOWN:
		return
	_last_hit_time_sec = now_sec

	var horizontal_push := Vector3(force.x, 0.0, force.z)
	if not horizontal_push.is_zero_approx():
		horizontal_push = horizontal_push.normalized() * ENEMY_HIT_KNOCKBACK
	velocity += horizontal_push
	velocity.y = maxf(velocity.y, ENEMY_HIT_UPWARD_BONUS)

	_hit_sound.pitch_scale = randfn(1.0, 0.06)
	_hit_sound.play()

	_lives = maxi(0, _lives - ENEMY_HIT_DAMAGE)
	_update_lives_label()
	set_lives.rpc(_lives)
	if _lives <= 0:
		set_dead_state.rpc(true)


func is_targetable() -> bool:
	return not _is_dead
