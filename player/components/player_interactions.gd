extends RefCounted
class_name PlayerInteractionsComponent

const BOMB_SCENE := preload("res://main/static_body_3d_bomb.tscn")


func setup(player) -> void:
	if is_instance_valid(player._pull_ray):
		player._pull_ray.enabled = true
		player._pull_ray.target_position = Vector3(0, 0, -player.pull_interaction_distance)
		player._pull_ray.add_exception(player)


func handle_unhandled_input(player, event: InputEvent) -> void:
	if player._is_dead:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		DebugLog.gameplay("place_bomb detectee (right mouse)")
		place_bomb(player)
		return
	# Keep keyboard fallback for quick testing in editor.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		DebugLog.gameplay("place_bomb detectee (key B)")
		place_bomb(player)


func place_bomb(player) -> void:
	DebugLog.gameplay("place_bomb called, authority=%s" % str(player.is_multiplayer_authority()))
	if not player.is_multiplayer_authority():
		return
	DebugLog.gameplay("spawning bomb via RPC")
	# Use camera forward and a chest-height spawn to avoid clipping near walls/floors.
	var throw_forward: Vector3 = -player._camera_controller.camera.global_transform.basis.z
	if throw_forward.length_squared() < 0.0001:
		throw_forward = -player.global_transform.basis.z
	throw_forward = throw_forward.normalized()
	var bomb_pos: Vector3 = player.global_position + (Vector3.UP * player.bomb_spawn_up_offset) + (throw_forward * player.bomb_spawn_forward_offset)
	var throw_velocity: Vector3 = (throw_forward * player.bomb_throw_speed) + (Vector3.UP * player.bomb_throw_upward_boost)
	player.spawn_bomb.rpc(bomb_pos, throw_velocity)


func spawn_bomb(player, pos: Vector3, throw_velocity: Vector3) -> void:
	DebugLog.gameplay("Bomb creating")
	var bomb = BOMB_SCENE.instantiate()
	player.get_parent().add_child(bomb)
	# Bomb physics should stay server-authoritative when synchronizer is present.
	if bomb is Node:
		bomb.set_multiplayer_authority(1)
	# Carry owner id so explosion kills can be attributed in match scoring.
	if "owner_peer_id" in bomb:
		bomb.owner_peer_id = player.get_multiplayer_authority()
	bomb.global_position = pos
	if bomb is RigidBody3D:
		bomb.linear_velocity = throw_velocity
	DebugLog.gameplay("Bomb spawned at %s" % str(bomb.global_position))


func try_toggle_pull_cube(player) -> bool:
	if not is_instance_valid(player._pull_ray):
		return false
	player._pull_ray.target_position = Vector3(0, 0, -player.pull_interaction_distance)
	player._pull_ray.force_raycast_update()
	var from: Vector3 = player._pull_ray.global_transform.origin
	var to: Vector3 = from + (player._pull_ray.global_transform.basis * player._pull_ray.target_position)
	DebugLog.gameplay("pull cube raycast from %s to %s" % [from, to])
	if not player._pull_ray.is_colliding():
		return false
	var collider: Variant = player._pull_ray.get_collider()
	if not (collider is RigidBody3D):
		return false
	var cube := collider as RigidBody3D
	if not cube.is_in_group("pullable_cubes") or not cube.has_method("request_toggle_pull"):
		return false

	var cube_authority: int = cube.get_multiplayer_authority()
	if cube_authority == player.multiplayer.get_unique_id():
		cube.request_toggle_pull()
	else:
		cube.request_toggle_pull.rpc_id(cube_authority)
	return true


func collect_coin(player) -> void:
	var authority_id: int = player.get_multiplayer_authority()
	if player.multiplayer.get_unique_id() == authority_id:
		player._coins += 1
	else:
		player._collect_coin.rpc_id(authority_id)


func collect_coin_authority(player) -> void:
	if not player.is_multiplayer_authority():
		return
	player._coins += 1
