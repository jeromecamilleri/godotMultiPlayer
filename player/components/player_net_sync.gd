extends RefCounted
class_name PlayerNetSyncComponent


func set_sync_properties(player) -> void:
	player._position = player.position
	player._velocity = player.velocity
	player._direction = player._move_direction
	player._strong_direction = player._last_strong_direction
	player._is_sliding_sync = player._is_sliding


func on_synchronized(player) -> void:
	player.velocity = player._velocity
	player.position_before_sync = player.position
	player._is_sliding = player._is_sliding_sync

	var sync_time_ms: int = Time.get_ticks_msec()
	player.sync_delta = clampf(float(sync_time_ms - player.last_sync_time_ms) / 1000, 0, player.sync_delta_max)
	player.last_sync_time_ms = sync_time_ms


func interpolate_client(player, delta: float) -> void:
	player._movement.orient_character_to_direction(player, player._strong_direction, delta)

	if player._direction.length() == 0:
		# Don't interpolate to avoid small jitter when stopping.
		if (player._position - player.position).length() > 1.0 and player._velocity.is_zero_approx():
			player.position = player._position
	else:
		# Interpolate between position_before_sync and _position
		# and add to ongoing movement to compensate misplacement.
		var t: float = 1.0 if is_zero_approx(player.sync_delta) else delta / player.sync_delta
		player.sync_delta = clampf(player.sync_delta - delta, 0, player.sync_delta_max)

		var less_misplacement: Vector3 = player.position_before_sync.move_toward(player._position, t)
		player.position += less_misplacement - player.position_before_sync
		player.position_before_sync = less_misplacement

	player.velocity.y += player._gravity * delta
	player.move_and_slide()
