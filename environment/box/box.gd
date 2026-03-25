extends RigidBody3D

const COIN_SCENE := preload("res://player/coin/coin.tscn")
const DESTROYED_BOX_SCENE := preload("res://environment/box/destroyed_box.tscn")

const COINS_COUNT := 5

@onready var _destroy_sound: AudioStreamPlayer3D = $DestroySound
@onready var _collision_shape: CollisionShape3D = $CollisionShape3d
@onready var _crate_visual: Node3D = $CrateVisual

var _destroyed: bool = false


func _ready() -> void:
	if is_multiplayer_authority():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		call_deferred("_request_initial_state")


func damage(_impact_point: Vector3, _force: Vector3, _attacker_peer_id: int = -1) -> void:
	if _destroyed:
		return
	var authority: int = get_multiplayer_authority()
	if authority <= 0:
		return
	if multiplayer.get_unique_id() == authority:
		_apply_damage()
	else:
		_request_damage.rpc_id(authority, _impact_point, _force, _attacker_peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_damage(_impact_point: Vector3, _force: Vector3, _attacker_peer_id: int = -1) -> void:
	if not is_multiplayer_authority() or _destroyed:
		return
	_apply_damage()


@rpc("any_peer", "call_remote", "reliable")
func _request_current_state() -> void:
	if not is_multiplayer_authority():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_sync_destroy_snapshot.rpc_id(peer_id, _destroyed)


@rpc("authority", "call_remote", "reliable")
func _sync_destroy_snapshot(destroyed: bool) -> void:
	if destroyed:
		_apply_destroy_state(false, false)


@rpc("authority", "call_remote", "reliable")
func _sync_destroy_event() -> void:
	_apply_destroy_state(true, false)


func _request_initial_state() -> void:
	if not is_inside_tree() or is_multiplayer_authority():
		return
	var authority: int = get_multiplayer_authority()
	if authority <= 0 or authority == multiplayer.get_unique_id():
		return
	_request_current_state.rpc_id(authority)


func _on_peer_connected(peer_id: int) -> void:
	if not _destroyed:
		return
	_sync_destroy_snapshot.rpc_id(peer_id, true)


func _apply_damage() -> void:
	if _destroyed:
		return
	_apply_destroy_state(true, true)
	_sync_destroy_event.rpc()


func _apply_destroy_state(spawn_effects: bool, spawn_coins: bool) -> void:
	if _destroyed:
		return
	_destroyed = true
	sleeping = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(_collision_shape):
		_collision_shape.set_deferred("disabled", true)
	if is_instance_valid(_crate_visual):
		_crate_visual.visible = false
	if spawn_effects:
		_spawn_destroy_effects(spawn_coins)


func _spawn_destroy_effects(spawn_coins: bool) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var disable_crate_coins := OS.get_environment("UI_TEST_DISABLE_CRATE_COINS").strip_edges().to_lower()
	if spawn_coins and disable_crate_coins != "1" and disable_crate_coins != "true" and disable_crate_coins != "yes":
		for i in range(COINS_COUNT):
			var coin := COIN_SCENE.instantiate()
			parent.add_child(coin)
			coin.global_position = global_position
			coin.spawn()
	var destroyed_box_name := "%s_Destroyed" % name
	if parent.has_node(NodePath(destroyed_box_name)):
		return
	var destroyed_box := DESTROYED_BOX_SCENE.instantiate()
	destroyed_box.name = destroyed_box_name
	parent.add_child(destroyed_box)
	if destroyed_box is Node3D:
		(destroyed_box as Node3D).global_position = global_position
	if is_instance_valid(_destroy_sound):
		_destroy_sound.pitch_scale = randfn(1.0, 0.1)
		_destroy_sound.play()
