extends RefCounted
class_name PlayerCombatComponent


func attack(player) -> void:
	player._attack_animation_player.play("Attack")
	player._character_skin.punch.rpc()
	player.velocity = player._rotation_root.transform.basis * Vector3.BACK * player.attack_impulse


func process_rigidbody_push_collisions(player) -> void:
	for i in player.get_slide_collision_count():
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		if collision.get_collider() is RigidBody3D:
			var body := collision.get_collider() as RigidBody3D
			var push_dir: Vector3 = -collision.get_normal()
			var impulse: Vector3 = push_dir * 1.5
			var body_authority: int = body.get_multiplayer_authority()
			# Push requests must be executed by the rigidbody authority.
			if body.has_method("request_push"):
				if body_authority == player.multiplayer.get_unique_id():
					body.request_push(impulse)
				else:
					body.request_push.rpc_id(body_authority, impulse)
			elif body_authority == player.multiplayer.get_unique_id():
				body.apply_central_impulse(impulse)


func damage(player, _impact_point: Vector3, force: Vector3, _attacker_peer_id: int = -1) -> void:
	# Enemy hit must be server-authoritative so MatchDirector stays in sync.
	if player.multiplayer.is_server():
		apply_enemy_hit_server(player, force)
	else:
		player._request_enemy_hit_on_server.rpc_id(1, force)


func request_enemy_hit_on_server(player, force: Vector3) -> void:
	if not player.multiplayer.is_server():
		return
	apply_enemy_hit_server(player, force)


func apply_enemy_hit_server(player, force: Vector3) -> void:
	if not player.multiplayer.is_server():
		return
	if player._is_dead:
		return

	var now_sec: float = Time.get_ticks_msec() / 1000.0
	if now_sec - player._last_hit_time_sec < player.ENEMY_HIT_COOLDOWN:
		return
	player._last_hit_time_sec = now_sec

	var horizontal_push: Vector3 = Vector3(force.x, 0.0, force.z)
	if not horizontal_push.is_zero_approx():
		horizontal_push = horizontal_push.normalized() * player.ENEMY_HIT_KNOCKBACK
	player.velocity += horizontal_push
	player.velocity.y = maxf(player.velocity.y, player.ENEMY_HIT_UPWARD_BONUS)

	player._hit_sound.pitch_scale = randfn(1.0, 0.06)
	player._hit_sound.play()

	player._lives = maxi(0, player._lives - player.ENEMY_HIT_DAMAGE)
	player._lifecycle.sync_lives_with_match_director(player)
	player._lifecycle.set_lives(player, player._lives)
	player._lifecycle.sync_lives_to_owner(player, player._lives)
	if player._lives <= 0:
		player.set_dead_state.rpc(true)
