extends CharacterBody3D
class_name Player

const PlayerMovementComponentScript := preload("res://player/components/player_movement.gd")
const PlayerCombatComponentScript := preload("res://player/components/player_combat.gd")
const PlayerLifecycleComponentScript := preload("res://player/components/player_lifecycle.gd")
const PlayerNetSyncComponentScript := preload("res://player/components/player_net_sync.gd")
const PlayerInteractionsComponentScript := preload("res://player/components/player_interactions.gd")

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
## Slope angle (degrees) where sliding starts to be noticeable.
@export var slide_start_angle_deg := 25.0
## Slope angle (degrees) where uphill movement is fully blocked.
@export var slide_block_angle_deg := 40.0
## Tangential acceleration applied down steep slopes.
@export var slope_slide_accel := 12.0
## Target downhill speed reached on very steep slopes.
@export var slope_downhill_speed := 11.0
## Sideways damping while sliding to reduce drifting left/right.
@export var slope_lateral_damping := 4.0
## Extra floor snap distance to keep contact on steep slopes.
@export var slope_floor_snap_length := 0.55
## Visual forward tilt (degrees) applied while sliding.
@export var slide_visual_tilt_deg := 14.0
## How fast the visual tilt blends in/out.
@export var slide_visual_lerp_speed := 7.0
## Minimum downhill speed to display sliding visual state.
@export var slide_visual_speed_threshold := 0.9
## Horizontal distance in front of the player where bombs are spawned.
@export var bomb_spawn_forward_offset := 1.1
## Vertical spawn offset to avoid clipping bombs into the ground.
@export var bomb_spawn_up_offset := 1.2
## Initial throw speed applied when spawning a bomb.
@export var bomb_throw_speed := 12.0
## Upward boost so bombs arc a bit before rolling.
@export var bomb_throw_upward_boost := 2.0
## Max distance for left-click cube pull interaction.
@export var pull_interaction_distance := 6.5

@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _pull_ray: RayCast3D = $CameraController/PlayerCamera/PullRay
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
@export var _is_sliding_sync := false

var position_before_sync: Vector3
var last_sync_time_ms: int
var sync_delta: float
var _is_dead := false
var _lives := 5
var _coins := 0
var _last_hit_time_sec := -100.0
var _default_collision_layer := 1
var _default_collision_mask := 1
var _is_sliding := false
var _slide_visual_factor := 0.0

var _movement = PlayerMovementComponentScript.new()
var _combat = PlayerCombatComponentScript.new()
var _lifecycle = PlayerLifecycleComponentScript.new()
var _net_sync = PlayerNetSyncComponentScript.new()
var _interactions = PlayerInteractionsComponentScript.new()

const ENEMY_HIT_DAMAGE := 1
const ENEMY_HIT_COOLDOWN := 0.35
const ENEMY_HIT_KNOCKBACK := 4.5
const ENEMY_HIT_UPWARD_BONUS := 1.2


func _unhandled_input(event: InputEvent) -> void:
	_interactions.handle_unhandled_input(self, event)


func _ready() -> void:
	add_to_group("players")
	_movement.setup(self)
	_interactions.setup(self)
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	# Give each replicated player instance a deterministic, per-peer heart color.
	_character_skin.apply_heart_color_from_peer_id(get_multiplayer_authority())
	_lifecycle.setup(self)
	DebugLog.gameplay("Player ready | peer=%d authority=%s" % [multiplayer.get_unique_id(), str(is_multiplayer_authority())])
	# Only the authority owns camera/input simulation; remotes are interpolation-only.
	if is_multiplayer_authority():
		_camera_controller.setup(self)
	else:
		rotation_speed /= 1.5
		_synchronizer.delta_synchronized.connect(on_synchronized)
		_synchronizer.synchronized.connect(on_synchronized)
		on_synchronized()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_net_sync.interpolate_client(self, delta)
		return
	if _is_dead:
		_move_direction = Vector3.ZERO
		velocity = Vector3.ZERO
		_movement.set_sliding_state(self, false)
		set_sync_properties()
		return
	_movement.physics_process_authority(self, delta)


func place_bomb() -> void:
	_interactions.place_bomb(self)


@rpc("any_peer", "call_local", "reliable")
func spawn_bomb(pos: Vector3, throw_velocity: Vector3) -> void:
	_interactions.spawn_bomb(self, pos, throw_velocity)


func attack() -> void:
	_combat.attack(self)


func set_sync_properties() -> void:
	_net_sync.set_sync_properties(self)


func on_synchronized() -> void:
	_net_sync.on_synchronized(self)


func interpolate_client(delta: float) -> void:
	_net_sync.interpolate_client(self, delta)


@rpc("any_peer", "call_remote", "reliable")
func respawn(spawn_position: Vector3) -> void:
	_lifecycle.respawn(self, spawn_position)


@rpc("any_peer", "call_local", "reliable")
func set_dead_state(dead: bool) -> void:
	_lifecycle.set_dead_state(self, dead)


@rpc("any_peer", "call_remote", "reliable")
func set_lives(lives: int) -> void:
	_lifecycle.set_lives(self, lives)


func get_lives() -> int:
	return _lifecycle.get_lives(self)


func collect_coin() -> void:
	_interactions.collect_coin(self)


@rpc("any_peer", "call_local", "reliable")
func _collect_coin() -> void:
	_interactions.collect_coin_authority(self)


func damage(impact_point: Vector3, force: Vector3, attacker_peer_id: int = -1) -> void:
	_combat.damage(self, impact_point, force, attacker_peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_enemy_hit_on_server(force: Vector3) -> void:
	_combat.request_enemy_hit_on_server(self, force)


func is_targetable() -> bool:
	return _lifecycle.is_targetable(self)


func can_be_revived() -> bool:
	return _lifecycle.can_be_revived(self)


func try_revive_with_coin() -> bool:
	return _lifecycle.try_revive_with_coin(self)
