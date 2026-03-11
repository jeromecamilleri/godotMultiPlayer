extends RefCounted
class_name PlayerInteractionsComponent

const BOMB_SCENE := preload("res://main/static_body_3d_bomb.tscn")


func setup(player) -> void:
	if is_instance_valid(player._pull_ray):
		player._pull_ray.enabled = true
		player._pull_ray.collide_with_bodies = true
		player._pull_ray.collide_with_areas = true
		player._pull_ray.target_position = Vector3(0, 0, -player.pull_interaction_distance)
		player._pull_ray.add_exception(player)


func handle_unhandled_input(player, event: InputEvent) -> void:
	if player._is_dead:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		DebugLog.gameplay("place_bomb detectee (right mouse)")
		place_bomb(player)
		return
	if event.is_action_pressed("interact_pickup"):
		DebugLog.gameplay("inventory: interact_pickup pressed | peer=%d authority=%s" % [player.multiplayer.get_unique_id(), str(player.is_multiplayer_authority())])
		try_pickup_or_focus_target(player)
		return
	if event.is_action_pressed("inventory_drop"):
		DebugLog.gameplay("inventory: inventory_drop pressed")
		player.request_drop_inventory_slot(0)
		return
	if event.is_action_pressed("inventory_transfer"):
		DebugLog.gameplay("inventory: inventory_transfer pressed")
		player.request_transfer_to_target(0)
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


func try_pickup_or_focus_target(player) -> bool:
	var target := _get_interaction_target(player)
	if target == null:
		DebugLog.gameplay("inventory: no direct interaction target found")
	else:
		DebugLog.gameplay("inventory: interaction target=%s path=%s" % [target.name, str(target.get_path())])
		if target.has_method("can_be_picked_up") and bool(target.call("can_be_picked_up")):
			DebugLog.gameplay("inventory: target is pickable, sending pickup request")
			player.request_pickup_world_item(target.get_path())
			return true
		if target.has_method("get_inventory_component"):
			DebugLog.gameplay("inventory: target is an inventory container, focusing it")
			player.set_focused_inventory_target(target)
			return true
		DebugLog.gameplay("inventory: direct target is neither pickable nor inventory-enabled")
	var fallback_target := _find_nearest_pickable_target(player)
	if fallback_target != null:
		DebugLog.gameplay("inventory: fallback picked nearby target=%s path=%s" % [fallback_target.name, str(fallback_target.get_path())])
		player.request_pickup_world_item(fallback_target.get_path())
		return true
	DebugLog.gameplay("inventory: no fallback pickable target found")
	player.set_focused_inventory_target(null)
	return false


func _get_interaction_target(player) -> Node:
	if not is_instance_valid(player._pull_ray):
		DebugLog.gameplay("inventory: pull ray is missing")
		return null
	player._pull_ray.target_position = Vector3(0, 0, -player.pull_interaction_distance)
	player._pull_ray.force_raycast_update()
	var from: Vector3 = player._pull_ray.global_transform.origin
	var to: Vector3 = from + (player._pull_ray.global_transform.basis * player._pull_ray.target_position)
	DebugLog.gameplay("inventory: raycast from %s to %s" % [str(from), str(to)])
	if not player._pull_ray.is_colliding():
		DebugLog.gameplay("inventory: raycast did not collide")
		return null
	var collider: Variant = player._pull_ray.get_collider()
	DebugLog.gameplay("inventory: raycast collider=%s" % [str(collider)])
	if collider is Node:
		return collider as Node
	return null


func _find_nearest_pickable_target(player) -> Node:
	var best_target: Node = null
	var best_distance := INF
	var player_origin: Vector3 = player.global_position + Vector3(0.0, 1.0, 0.0)
	var forward: Vector3 = -player.global_transform.basis.z
	if is_instance_valid(player._camera_controller) and is_instance_valid(player._camera_controller.camera):
		forward = -player._camera_controller.camera.global_transform.basis.z
	if forward.length_squared() < 0.0001:
		forward = -player.global_transform.basis.z
	forward = forward.normalized()
	for candidate in player.get_tree().get_nodes_in_group("world_items"):
		if not (candidate is Node3D):
			continue
		if not candidate.has_method("can_be_picked_up") or not bool(candidate.call("can_be_picked_up")):
			continue
		var candidate_node := candidate as Node3D
		var to_item: Vector3 = candidate_node.global_position - player_origin
		var distance: float = to_item.length()
		if distance > player.pull_interaction_distance + 1.5:
			continue
		if distance < 0.001:
			distance = 0.001
		var facing: float = forward.dot(to_item / distance)
		if facing < 0.15:
			continue
		if distance < best_distance:
			best_distance = distance
			best_target = candidate
	if best_target != null:
		DebugLog.gameplay("inventory: nearest fallback target distance=%.3f" % best_distance)
	return best_target
