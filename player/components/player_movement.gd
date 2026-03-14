extends RefCounted
class_name PlayerMovementComponent


func setup(player) -> void:
	# Stronger snap reduces visual hovering/bouncing on steep slopes.
	player.floor_snap_length = player.slope_floor_snap_length


func physics_process_authority(player, delta: float) -> void:
	if player.is_inventory_mode_open():
		player._move_direction = Vector3.ZERO
		player.velocity.x = 0.0
		player.velocity.z = 0.0
		player.set_sync_properties()
		return
	update_ground_height(player)

	# Gather input state for this physics tick.
	var is_just_attacking: bool = Input.is_action_just_pressed("attack")
	if is_just_attacking and player._interactions.try_toggle_pull_cube(player):
		# When clicking a pullable cube, interaction takes priority over punch.
		is_just_attacking = false
	var is_just_jumping: bool = Input.is_action_just_pressed("jump") and player.is_on_floor()
	var is_air_boosting: bool = Input.is_action_pressed("jump") and not player.is_on_floor() and player.velocity.y > 0.0

	player._move_direction = get_camera_oriented_input(player)
	apply_slope_rules_to_input(player)

	if EditMode.is_enabled:
		is_just_jumping = false
		is_air_boosting = false
		player._move_direction = Vector3.ZERO

	update_orientation(player, delta)
	apply_horizontal_velocity(player, delta)
	apply_combat_and_vertical_forces(player, is_just_attacking, is_just_jumping, is_air_boosting, delta)
	update_character_animation(player, is_just_jumping)
	move_and_unstuck_if_needed(player, is_just_jumping)

	player.set_sync_properties()
	player._combat.process_rigidbody_push_collisions(player)


func update_ground_height(player) -> void:
	# Calculate ground height for camera controller.
	if player._ground_shapecast.get_collision_count() > 0:
		for collision_result in player._ground_shapecast.collision_result:
			player._ground_height = max(player._ground_height, collision_result.point.y)
	else:
		player._ground_height = player.global_position.y + player._ground_shapecast.target_position.y
	if player.global_position.y < player._ground_height:
		player._ground_height = player.global_position.y


func update_orientation(player, delta: float) -> void:
	# Save last meaningful direction for stable visual orientation.
	if player._move_direction.length() > 0.2:
		player._last_strong_direction = player._move_direction.normalized()
	orient_character_to_direction(player, player._last_strong_direction, delta)


func orient_character_to_direction(player, direction: Vector3, delta: float) -> void:
	var left_axis: Vector3 = Vector3.UP.cross(direction)
	var rotation_basis: Quaternion = Basis(left_axis, Vector3.UP, direction).get_rotation_quaternion()
	var target_basis: Basis = Basis(rotation_basis)
	var target_slide_factor: float = 1.0 if player._is_sliding else 0.0
	player._slide_visual_factor = move_toward(player._slide_visual_factor, target_slide_factor, delta * player.slide_visual_lerp_speed)
	if player._slide_visual_factor > 0.001:
		var tilt_rad: float = deg_to_rad(player.slide_visual_tilt_deg * player._slide_visual_factor)
		target_basis = target_basis * Basis(Vector3.RIGHT, tilt_rad)
	var model_scale: Vector3 = player._rotation_root.transform.basis.get_scale()
	player._rotation_root.transform.basis = Basis(
		player._rotation_root.transform.basis.get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), delta * player.rotation_speed)
	).scaled(model_scale)


func apply_horizontal_velocity(player, delta: float) -> void:
	# Interpolate horizontal speed while preserving vertical velocity.
	var y_velocity: float = player.velocity.y
	player.velocity.y = 0.0
	player.velocity = player.velocity.lerp(player._move_direction * player.move_speed, player.acceleration * delta)
	apply_slope_sliding(player, delta)
	if player._move_direction.length() == 0 and player.velocity.length() < player.stopping_speed:
		player.velocity = Vector3.ZERO
	player.velocity.y = y_velocity


func apply_combat_and_vertical_forces(player, is_just_attacking: bool, is_just_jumping: bool, is_air_boosting: bool, delta: float) -> void:
	if is_just_attacking and not player._attack_animation_player.is_playing():
		player._combat.attack(player)
	player.velocity.y += player._gravity * delta
	if is_just_jumping:
		player.velocity.y += player.jump_initial_impulse
	elif is_air_boosting:
		player.velocity.y += player.jump_additional_force * delta


func update_character_animation(player, is_just_jumping: bool) -> void:
	if is_just_jumping:
		set_sliding_state(player, false)
		player._character_skin.jump.rpc()
	elif not player.is_on_floor() and player.velocity.y < 0:
		set_sliding_state(player, false)
		player._character_skin.fall.rpc()
	elif player.is_on_floor() and player._is_sliding:
		# While sliding, keep locomotion active so the character no longer looks frozen.
		var downhill_speed: float = get_downhill_speed(player)
		var blend_speed: float = clampf(downhill_speed / maxf(0.01, player.slope_downhill_speed), 0.35, 1.0)
		player._character_skin.set_moving.rpc(true)
		player._character_skin.set_moving_speed.rpc(blend_speed)
	elif player.is_on_floor():
		var xz_velocity := Vector3(player.velocity.x, 0, player.velocity.z)
		if xz_velocity.length() > player.stopping_speed:
			player._character_skin.set_moving.rpc(true)
			player._character_skin.set_moving_speed.rpc(inverse_lerp(0.0, player.move_speed, xz_velocity.length()))
		else:
			player._character_skin.set_moving.rpc(false)


func move_and_unstuck_if_needed(player, is_just_jumping: bool) -> void:
	var position_before: Vector3 = player.global_position
	# Keep ground contact while descending slopes (except during jump takeoff).
	if not is_just_jumping and player.velocity.y <= 0.0:
		player.apply_floor_snap()
	player.move_and_slide()
	var position_after: Vector3 = player.global_position

	# If motion is blocked despite non-zero velocity, nudge away from wall.
	var delta_position: Vector3 = position_after - position_before
	var epsilon := 0.001
	if delta_position.length() < epsilon and player.velocity.length() > epsilon:
		player.global_position += player.get_wall_normal() * 0.1


func get_camera_oriented_input(player) -> Vector3:
	var raw_input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var input := Vector3.ZERO
	# This is to ensure that diagonal input isn't stronger than axis aligned input.
	input.x = -raw_input.x * sqrt(1.0 - raw_input.y * raw_input.y / 2.0)
	input.z = -raw_input.y * sqrt(1.0 - raw_input.x * raw_input.x / 2.0)

	input = player._camera_controller.global_transform.basis * input
	input.y = 0.0
	return input


func apply_slope_rules_to_input(player) -> void:
	# Keep normal controls on flat terrain; only alter input on steep floors.
	if not player.is_on_floor():
		return

	var floor_normal: Vector3 = player.get_floor_normal()
	var slope_angle: float = get_slope_angle_deg(floor_normal)
	if slope_angle < player.slide_start_angle_deg:
		return

	var downhill: Vector3 = get_downhill_direction(player, floor_normal)
	if downhill.is_zero_approx():
		return

	# Only reduce the uphill component so side/downhill control remains responsive.
	var uphill_component: float = player._move_direction.dot(-downhill)
	if uphill_component <= 0.0:
		return

	var block_t: float = inverse_lerp(player.slide_start_angle_deg, player.slide_block_angle_deg, slope_angle)
	block_t = clampf(block_t, 0.0, 1.0)
	var removed_uphill: Vector3 = (-downhill) * uphill_component * block_t
	player._move_direction -= removed_uphill


func apply_slope_sliding(player, delta: float) -> void:
	# Apply a gravity-tangent drift on steep slopes to create natural sliding.
	if not player.is_on_floor():
		set_sliding_state(player, false)
		return

	var floor_normal: Vector3 = player.get_floor_normal()
	var slope_angle: float = get_slope_angle_deg(floor_normal)
	if slope_angle < player.slide_start_angle_deg:
		set_sliding_state(player, false)
		return

	var downhill: Vector3 = get_downhill_direction(player, floor_normal)
	if downhill.is_zero_approx():
		set_sliding_state(player, false)
		return

	var slide_t: float = inverse_lerp(player.slide_start_angle_deg, player.slide_block_angle_deg, slope_angle)
	slide_t = clampf(slide_t, 0.0, 1.0)
	var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var downhill_speed: float = horizontal.dot(downhill)
	var target_downhill_speed: float = player.slope_downhill_speed * slide_t
	if downhill_speed < target_downhill_speed:
		var speed_gap: float = target_downhill_speed - downhill_speed
		var accel_step: float = player.slope_slide_accel * slide_t * delta
		horizontal += downhill * minf(speed_gap, accel_step)

	# Dampen only lateral drift; keep downhill momentum responsive.
	var lateral: Vector3 = horizontal - downhill * horizontal.dot(downhill)
	lateral = lateral.move_toward(Vector3.ZERO, player.slope_lateral_damping * delta)
	horizontal = downhill * horizontal.dot(downhill) + lateral
	player.velocity.x = horizontal.x
	player.velocity.z = horizontal.z
	set_sliding_state(player, horizontal.dot(downhill) > player.slide_visual_speed_threshold)


func get_slope_angle_deg(floor_normal: Vector3) -> float:
	return rad_to_deg(acos(clampf(floor_normal.dot(Vector3.UP), -1.0, 1.0)))


func get_downhill_direction(player, floor_normal: Vector3) -> Vector3:
	var gravity_vector := Vector3(0.0, player._gravity, 0.0)
	var tangent := gravity_vector.slide(floor_normal)
	return tangent.normalized() if not tangent.is_zero_approx() else Vector3.ZERO


func set_sliding_state(player, value: bool) -> void:
	if player._is_sliding == value:
		return
	player._is_sliding = value
	# Animation state changes are driven by authority and mirrored to remotes.
	player._character_skin.set_sliding.rpc(value)


func get_downhill_speed(player) -> float:
	if not player.is_on_floor():
		return 0.0
	var downhill := get_downhill_direction(player, player.get_floor_normal())
	if downhill.is_zero_approx():
		return 0.0
	return Vector3(player.velocity.x, 0.0, player.velocity.z).dot(downhill)
