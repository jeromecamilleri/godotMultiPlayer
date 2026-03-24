extends CharacterBody3D
class_name Player

const PlayerMovementComponentScript := preload("res://player/components/player_movement.gd")
const PlayerCombatComponentScript := preload("res://player/components/player_combat.gd")
const PlayerLifecycleComponentScript := preload("res://player/components/player_lifecycle.gd")
const PlayerNetSyncComponentScript := preload("res://player/components/player_net_sync.gd")
const PlayerInteractionsComponentScript := preload("res://player/components/player_interactions.gd")
const PlayerUiTestDriverScript := preload("res://player/components/player_ui_test_driver.gd")
const InventoryComponentScript := preload("res://inventory/inventory_component.gd")
const WorldItemScene: PackedScene = preload("res://inventory/world_item.tscn")

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
## Forward distance where dropped inventory items appear.
@export var inventory_drop_forward_offset := 1.4
## Vertical offset when dropping an inventory item.
@export var inventory_drop_up_offset := 1.0

@onready var _rotation_root: Node3D = $CharacterRotationRoot
@onready var _camera_controller: CameraController = $CameraController
@onready var _pull_ray: RayCast3D = $CameraController/PlayerCamera/PullRay
@onready var _attack_animation_player: AnimationPlayer = $CharacterRotationRoot/MeleeAnchor/AnimationPlayer
@onready var _ground_shapecast: ShapeCast3D = $GroundShapeCast
@onready var _interaction_area: Area3D = $InteractionArea
@onready var _character_skin: CharacterSkin = $CharacterRotationRoot/CharacterSkin
@onready var _synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var _character_collision_shape: CollisionShape3D = $CharacterCollisionShape
@onready var _nickname: Control = $Nickname
@onready var _lives_overlay: CanvasLayer = $LivesOverlay
@onready var _lives_label: Label = $LivesOverlay/LivesLabel
@onready var _death_overlay: CanvasLayer = $DeathOverlay
@onready var _hit_sound: AudioStreamPlayer3D = $HitSound
@onready var inventory = $Inventory

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
var _inventory_snapshot_json := "[]"
var _inventory_target_path := NodePath("")
var _is_loading_inventory_snapshot := false
var _dropped_item_sequence := 0
var _inventory_mode_open := false
var _inventory_snapshot_revision := 0
var _pending_inventory_snapshot_broadcast := false
var _last_target_snapshot_request_ms := -100000
var _last_target_snapshot_request_path := NodePath("")
var _debug_position_lock_enabled := false
var _debug_position_lock_remote_state := false
var _debug_locked_position := Vector3.ZERO

var _movement = PlayerMovementComponentScript.new()
var _combat = PlayerCombatComponentScript.new()
var _lifecycle = PlayerLifecycleComponentScript.new()
var _net_sync = PlayerNetSyncComponentScript.new()
var _interactions = PlayerInteractionsComponentScript.new()
var _ui_test_driver = PlayerUiTestDriverScript.new()

const ENEMY_HIT_DAMAGE := 1
const ENEMY_HIT_COOLDOWN := 0.35
const ENEMY_HIT_KNOCKBACK := 4.5
const ENEMY_HIT_UPWARD_BONUS := 1.2


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_lock_player"):
		toggle_debug_position_lock()
		return
	if event.is_action_pressed("inventory_toggle"):
		toggle_inventory_mode()
		return
	if _inventory_mode_open:
		return
	_interactions.handle_unhandled_input(self, event)


func _ready() -> void:
	add_to_group("players")
	_ui_test_driver.setup()
	_movement.setup(self)
	_interactions.setup(self)
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	# Give each replicated player instance a deterministic, per-peer heart color.
	_character_skin.apply_heart_color_from_peer_id(get_multiplayer_authority())
	_lifecycle.setup(self)
	if is_instance_valid(inventory):
		inventory.inventory_name = "Sac"
		inventory.contents_changed.connect(_on_inventory_contents_changed)
	DebugLog.gameplay("Player ready | peer=%d authority=%s" % [multiplayer.get_unique_id(), str(is_multiplayer_authority())])
	# Only the authority owns camera/input simulation; remotes are interpolation-only.
	if is_multiplayer_authority():
		_camera_controller.setup(self)
	else:
		rotation_speed /= 1.5
		_synchronizer.delta_synchronized.connect(on_synchronized)
		_synchronizer.synchronized.connect(on_synchronized)
		on_synchronized()
	if multiplayer.is_server():
		call_deferred("_queue_inventory_snapshot_broadcast", true)
	if _ui_test_driver.is_enabled():
		call_deferred("_begin_ui_test_driver")


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_ui_test_driver.process(self)


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


func get_inventory_component():
	return inventory


func get_inventory_contents() -> Array[Dictionary]:
	if not is_instance_valid(inventory):
		return []
	return inventory.get_contents()


func get_inventory_display_name() -> String:
	return "Sac"


func is_inventory_mode_open() -> bool:
	return _inventory_mode_open


func set_inventory_mode_open(open: bool) -> void:
	_inventory_mode_open = open


func is_debug_position_locked() -> bool:
	return _debug_position_lock_enabled or _debug_position_lock_remote_state


func get_debug_locked_position() -> Vector3:
	return _debug_locked_position


func toggle_debug_position_lock() -> void:
	set_debug_position_lock(not _debug_position_lock_enabled)


func set_debug_position_lock(enabled: bool) -> void:
	_debug_position_lock_enabled = enabled
	if is_multiplayer_authority():
		if multiplayer.is_server():
			_debug_position_lock_remote_state = enabled
		else:
			_server_set_debug_position_lock_state.rpc_id(1, enabled)
	if enabled:
		_debug_locked_position = global_position
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		if is_instance_valid(_character_collision_shape):
			_character_collision_shape.disabled = true
		if _interactions.has_active_pull_session():
			_interactions.latch_active_pull_session(self)
	else:
		collision_layer = _default_collision_layer
		collision_mask = _default_collision_mask
		if is_instance_valid(_character_collision_shape):
			_character_collision_shape.disabled = false
		_interactions.clear_debug_pull_latched(self)


@rpc("any_peer", "call_remote", "reliable")
func _server_set_debug_position_lock_state(enabled: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != get_multiplayer_authority():
		return
	_debug_position_lock_remote_state = enabled


func toggle_inventory_mode() -> void:
	if _inventory_mode_open:
		_inventory_mode_open = false
		return
	var interacted := _interactions.try_pickup_or_focus_target(self)
	if not interacted:
		_interactions.refresh_inventory_focus(self)
	_inventory_mode_open = true
	_request_focused_inventory_snapshot()


func has_focused_inventory_target() -> bool:
	return get_focused_inventory_target() != null


func get_focused_inventory_target() -> Node:
	if String(_inventory_target_path).is_empty():
		return null
	return get_node_or_null(_inventory_target_path)


func set_focused_inventory_target(target: Node) -> void:
	if target == self:
		return
	if target == null:
		_inventory_target_path = NodePath("")
		_last_target_snapshot_request_path = NodePath("")
		return
	if not target.has_method("get_inventory_component"):
		_inventory_target_path = NodePath("")
		_last_target_snapshot_request_path = NodePath("")
		return
	_inventory_target_path = target.get_path()
	_request_focused_inventory_snapshot()


func _begin_ui_test_driver() -> void:
	_ui_test_driver.begin(self)


func get_target_inventory_display_name() -> String:
	var target := get_focused_inventory_target()
	if target == null or not target.has_method("get_inventory_display_name"):
		return ""
	return String(target.call("get_inventory_display_name"))


func get_target_inventory_contents() -> Array[Dictionary]:
	var target := get_focused_inventory_target()
	if target == null or not target.has_method("get_inventory_contents"):
		return []
	var contents: Variant = target.call("get_inventory_contents")
	if contents is Array:
		return contents
	return []


func request_pickup_world_item(target_path: NodePath) -> void:
	DebugLog.gameplay("inventory: request_pickup_world_item path=%s server=%s" % [str(target_path), str(multiplayer.is_server())])
	if multiplayer.is_server():
		_server_pickup_world_item(target_path)
		return
	_server_pickup_world_item.rpc_id(1, target_path)


func request_drop_inventory_slot(slot_index: int, quantity: int = 1) -> void:
	DebugLog.gameplay("inventory: request_drop_inventory_slot slot=%d quantity=%d server=%s" % [slot_index, quantity, str(multiplayer.is_server())])
	if multiplayer.is_server():
		_server_drop_inventory_slot(slot_index, quantity)
		return
	_server_drop_inventory_slot.rpc_id(1, slot_index, quantity)


func request_transfer_to_target(slot_index: int, quantity: int = 1) -> void:
	var target := get_focused_inventory_target()
	if target == null:
		DebugLog.gameplay("inventory: transfer requested but no target inventory is focused")
		return
	DebugLog.gameplay("inventory: request_transfer_to_target target=%s slot=%d quantity=%d" % [str(target.get_path()), slot_index, quantity])
	if multiplayer.is_server():
		_server_transfer_inventory_to_target(target.get_path(), slot_index, quantity)
		return
	_server_transfer_inventory_to_target.rpc_id(1, target.get_path(), slot_index, quantity)


func request_transfer_from_target(slot_index: int, quantity: int = 1) -> void:
	var target := get_focused_inventory_target()
	if target == null:
		DebugLog.gameplay("inventory: transfer_from requested but no target inventory is focused")
		return
	DebugLog.gameplay("inventory: request_transfer_from_target target=%s slot=%d quantity=%d" % [str(target.get_path()), slot_index, quantity])
	if multiplayer.is_server():
		_server_transfer_inventory_from_target(target.get_path(), slot_index, quantity)
		return
	_server_transfer_inventory_from_target.rpc_id(1, target.get_path(), slot_index, quantity)


@rpc("any_peer", "call_remote", "reliable")
func _server_pickup_world_item(target_path: NodePath) -> void:
	DebugLog.gameplay("inventory: _server_pickup_world_item target=%s sender=%d authority=%d" % [str(target_path), multiplayer.get_remote_sender_id(), get_multiplayer_authority()])
	if not multiplayer.is_server():
		DebugLog.gameplay("inventory: pickup rejected because current peer is not server")
		return
	if not _is_inventory_request_authorized():
		DebugLog.gameplay("inventory: pickup rejected because sender is not authority")
		return
	var target := get_node_or_null(target_path)
	if target == null:
		DebugLog.gameplay("inventory: pickup rejected because target node was not found")
		return
	if not target.has_method("can_be_picked_up"):
		DebugLog.gameplay("inventory: pickup rejected because target has no can_be_picked_up()")
		return
	if not target.call("can_be_picked_up"):
		DebugLog.gameplay("inventory: pickup rejected because target reports can_be_picked_up=false")
		return
	if not target.has_method("to_inventory_payload"):
		DebugLog.gameplay("inventory: pickup rejected because target has no to_inventory_payload()")
		return
	var payload: Variant = target.call("to_inventory_payload")
	if not (payload is Dictionary):
		DebugLog.gameplay("inventory: pickup rejected because payload is invalid")
		return
	var remaining: int = inventory.add_payload(payload as Dictionary)
	if remaining != 0:
		DebugLog.gameplay("inventory: pickup rejected because inventory is full | remaining=%d" % remaining)
		return
	DebugLog.gameplay("inventory: pickup accepted, object collected")
	if target.has_method("mark_collected_on_server"):
		target.call("mark_collected_on_server")
	else:
		target.rpc("set_collected_state", true, Time.get_ticks_msec())
	if target == get_focused_inventory_target():
		set_focused_inventory_target(null)


@rpc("any_peer", "call_remote", "reliable")
func _server_drop_inventory_slot(slot_index: int, quantity: int = 1) -> void:
	DebugLog.gameplay("inventory: _server_drop_inventory_slot slot=%d quantity=%d sender=%d" % [slot_index, quantity, multiplayer.get_remote_sender_id()])
	if not multiplayer.is_server():
		DebugLog.gameplay("inventory: drop rejected because current peer is not server")
		return
	if not _is_inventory_request_authorized():
		DebugLog.gameplay("inventory: drop rejected because sender is not authority")
		return
	var removed: Dictionary = inventory.remove_from_slot(slot_index, quantity)
	if removed.is_empty():
		DebugLog.gameplay("inventory: drop rejected because slot is empty or invalid")
		return
	var drop_position := _get_inventory_drop_position()
	_dropped_item_sequence += 1
	var dropped_item_name := "DroppedItem_%d_%d" % [get_multiplayer_authority(), _dropped_item_sequence]
	DebugLog.gameplay("inventory: dropping payload=%s at %s" % [str(removed), str(drop_position)])
	spawn_dropped_world_item.rpc(removed, drop_position, dropped_item_name)


@rpc("any_peer", "call_remote", "reliable")
func _server_transfer_inventory_to_target(target_path: NodePath, slot_index: int, quantity: int = 1) -> void:
	DebugLog.gameplay("inventory: _server_transfer_inventory_to_target target=%s slot=%d quantity=%d" % [str(target_path), slot_index, quantity])
	if not multiplayer.is_server():
		DebugLog.gameplay("inventory: transfer_to rejected because current peer is not server")
		return
	if not _is_inventory_request_authorized():
		DebugLog.gameplay("inventory: transfer_to rejected because sender is not authority")
		return
	var target_inventory = _get_inventory_component_from_path(target_path)
	if target_inventory == null:
		DebugLog.gameplay("inventory: transfer_to rejected because target inventory was not found")
		return
	var transferred: bool = inventory.transfer_to(target_inventory, slot_index, quantity)
	DebugLog.gameplay("inventory: transfer_to result=%s" % str(transferred))


@rpc("any_peer", "call_remote", "reliable")
func _server_transfer_inventory_from_target(target_path: NodePath, slot_index: int, quantity: int = 1) -> void:
	DebugLog.gameplay("inventory: _server_transfer_inventory_from_target target=%s slot=%d quantity=%d" % [str(target_path), slot_index, quantity])
	if not multiplayer.is_server():
		DebugLog.gameplay("inventory: transfer_from rejected because current peer is not server")
		return
	if not _is_inventory_request_authorized():
		DebugLog.gameplay("inventory: transfer_from rejected because sender is not authority")
		return
	var target_inventory = _get_inventory_component_from_path(target_path)
	if target_inventory == null:
		DebugLog.gameplay("inventory: transfer_from rejected because target inventory was not found")
		return
	var transferred: bool = target_inventory.transfer_to(inventory, slot_index, quantity)
	DebugLog.gameplay("inventory: transfer_from result=%s" % str(transferred))


@rpc("any_peer", "call_local", "reliable")
func spawn_dropped_world_item(payload: Dictionary, world_position: Vector3, node_name: String = "") -> void:
	DebugLog.gameplay("inventory: spawn_dropped_world_item payload=%s world_position=%s node_name=%s" % [str(payload), str(world_position), node_name])
	var scene_path := String(payload.get("world_item_scene", ""))
	var world_item_scene: PackedScene = WorldItemScene
	if not scene_path.is_empty():
		var loaded_scene := load(scene_path)
		if loaded_scene is PackedScene:
			world_item_scene = loaded_scene as PackedScene
	var world_item := world_item_scene.instantiate()
	if world_item == null:
		return
	var spawn_parent := _find_world_item_parent()
	if not node_name.is_empty():
		world_item.name = node_name
		var existing := spawn_parent.get_node_or_null(node_name)
		if existing != null:
			existing.queue_free()
	spawn_parent.add_child(world_item)
	if world_item is Node3D:
		(world_item as Node3D).global_position = world_position
	if world_item.has_method("configure_from_payload"):
		world_item.call("configure_from_payload", payload)


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_snapshot(snapshot_json: String) -> void:
	_inventory_snapshot_json = snapshot_json
	_inventory_snapshot_revision += 1
	var parsed: Variant = JSON.parse_string(snapshot_json)
	if not (parsed is Array):
		return
	_is_loading_inventory_snapshot = true
	inventory.load_contents(parsed as Array)
	_is_loading_inventory_snapshot = false


func _on_inventory_contents_changed(_contents: Array[Dictionary]) -> void:
	if _is_loading_inventory_snapshot:
		return
	if multiplayer.is_server():
		_queue_inventory_snapshot_broadcast()


func _queue_inventory_snapshot_broadcast(force: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if force:
		_pending_inventory_snapshot_broadcast = false
		_broadcast_inventory_snapshot()
		return
	if _pending_inventory_snapshot_broadcast:
		return
	_pending_inventory_snapshot_broadcast = true
	call_deferred("_broadcast_inventory_snapshot")


func _broadcast_inventory_snapshot() -> void:
	_pending_inventory_snapshot_broadcast = false
	_inventory_snapshot_json = JSON.stringify(inventory.serialize_contents())
	sync_inventory_snapshot.rpc(_inventory_snapshot_json)


func _request_focused_inventory_snapshot(force: bool = false) -> void:
	if multiplayer.is_server():
		return
	var target := get_focused_inventory_target()
	if target == null or not target.has_method("request_chest_snapshot"):
		return
	var now_ms := Time.get_ticks_msec()
	var target_path := target.get_path()
	if not force and target_path == _last_target_snapshot_request_path and now_ms - _last_target_snapshot_request_ms < 300:
		return
	_last_target_snapshot_request_ms = now_ms
	_last_target_snapshot_request_path = target_path
	var known_revision := -1
	if target.has_method("get_snapshot_revision"):
		known_revision = int(target.call("get_snapshot_revision"))
	target.request_chest_snapshot.rpc_id(1, known_revision, force)


func _is_inventory_request_authorized() -> bool:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return true
	return sender_id == get_multiplayer_authority()


func _get_inventory_component_from_path(target_path: NodePath):
	var target := get_node_or_null(target_path)
	if target == null or not target.has_method("get_inventory_component"):
		return null
	var component: Variant = target.call("get_inventory_component")
	if component is Node:
		return component
	return null


func _get_inventory_drop_position() -> Vector3:
	var drop_forward: Vector3 = -global_transform.basis.z
	if is_instance_valid(_camera_controller) and is_instance_valid(_camera_controller.camera):
		drop_forward = -_camera_controller.camera.global_transform.basis.z
	if drop_forward.length_squared() < 0.0001:
		drop_forward = Vector3.FORWARD
	return global_position + (Vector3.UP * inventory_drop_up_offset) + (drop_forward.normalized() * inventory_drop_forward_offset)


func _find_world_item_parent() -> Node:
	var current_scene := get_tree().current_scene
	if current_scene != null:
		var interactives := current_scene.find_child("Interactives", true, false)
		if interactives != null:
			return interactives
	var root := get_tree().root
	if root != null:
		var interactives_from_root := root.find_child("Interactives", true, false)
		if interactives_from_root != null:
			return interactives_from_root
	if get_parent() != null:
		return get_parent()
	return self


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
