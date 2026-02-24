extends RefCounted
class_name PlayerLifecycleComponent


func setup(player) -> void:
	player._lives_overlay.visible = player.is_multiplayer_authority()
	_update_lives_label(player)
	player._death_overlay.visible = false


func respawn(player, spawn_position: Vector3) -> void:
	player.global_position = spawn_position
	player.velocity = Vector3.ZERO


func set_dead_state(player, dead: bool) -> void:
	player._is_dead = dead
	player.velocity = Vector3.ZERO
	player._move_direction = Vector3.ZERO
	player._character_collision_shape.disabled = dead
	player.collision_layer = 0 if dead else player._default_collision_layer
	player.collision_mask = 0 if dead else player._default_collision_mask
	# Keep the avatar visible while downed so teammates can locate and revive it.
	player._rotation_root.visible = true
	player._nickname.visible = true
	if dead and player.is_in_group("players"):
		player.remove_from_group("players")
	elif not dead and not player.is_in_group("players"):
		player.add_to_group("players")
	if dead and not player.is_in_group("downed_players"):
		player.add_to_group("downed_players")
	elif not dead and player.is_in_group("downed_players"):
		player.remove_from_group("downed_players")
	if is_instance_valid(player._nickname) and player._nickname.has_method("set_downed_state"):
		player._nickname.call("set_downed_state", dead)
	if player.is_multiplayer_authority():
		# Spectator mode is local-only UX; dead state itself is replicated.
		player._camera_controller.set_spectator_mode(dead)
		if not dead:
			player._camera_controller.exit_spectator(player)
		player._death_overlay.visible = dead


func set_lives(player, lives: int) -> void:
	player._lives = maxi(0, lives)
	if player.is_multiplayer_authority():
		_update_lives_label(player)


func get_lives(player) -> int:
	# Expose authoritative lives value for server-side game systems.
	return player._lives


func is_targetable(player) -> bool:
	return not player._is_dead


func can_be_revived(player) -> bool:
	return player._is_dead


func try_revive_with_coin(player) -> bool:
	# Coin-triggered revive is server-authoritative to keep state deterministic.
	if not player.multiplayer.is_server():
		return false
	if not player._is_dead:
		return false
	var owner_peer_id: int = player.get_multiplayer_authority()
	var next_lives: int = 1
	var director: Node = player.get_tree().get_first_node_in_group("match_director")
	if is_instance_valid(director) and director.has_method("set_player_lives"):
		next_lives = int(director.set_player_lives(owner_peer_id, 1, "coin_revive"))
	player._lives = next_lives
	sync_lives_to_owner(player, next_lives)
	player.set_dead_state.rpc(false)
	return true


func sync_lives_with_match_director(player) -> void:
	# Keep MatchDirector as the single source of truth for life/death counters.
	if not player.multiplayer.is_server():
		return
	var director: Node = player.get_tree().get_first_node_in_group("match_director")
	if is_instance_valid(director) and director.has_method("set_player_lives"):
		director.set_player_lives(player.get_multiplayer_authority(), player._lives, "enemy_hit")


func sync_lives_to_owner(player, lives: int) -> void:
	# Send updated lives to the owning peer; host/local authority updates directly.
	var owner_peer_id: int = player.get_multiplayer_authority()
	if owner_peer_id == player.multiplayer.get_unique_id():
		set_lives(player, lives)
	elif player.multiplayer.get_peers().has(owner_peer_id):
		player.set_lives.rpc_id(owner_peer_id, lives)
	else:
		# Offline/unit-test fallback where authority peer may not be connected.
		set_lives(player, lives)


func _update_lives_label(player) -> void:
	player._lives_label.text = "Vies: %d" % player._lives
