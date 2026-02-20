class_name Coin
extends RigidBody3D

const MIN_LAUNCH_RANGE := 2.0
const MAX_LAUNCH_RANGE := 4.0
const MIN_LAUNCH_HEIGHT := 1.0
const MAX_LAUNCH_HEIGHT := 3.0

const SPAWN_TWEEN_DURATION := 1.0
const FOLLOW_TWEEN_DURATION := 0.5
const DOWNED_SCAN_RADIUS := 5.0

@onready var _collect_audio: AudioStreamPlayer3D = $CollectAudio
@onready var _player_detection_area: Area3D = $PlayerDetectionArea
@onready var _initial_tween_position := Vector3.ZERO
@onready var _target: Node3D = null
var _consumed := false


func spawn(coin_delay: float = 0.5) -> void:
	var rand_height := MIN_LAUNCH_HEIGHT + (randf() * MAX_LAUNCH_HEIGHT)
	var rand_dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * 2 * PI)
	var rand_pos := rand_dir * (MIN_LAUNCH_RANGE + (randf() * MAX_LAUNCH_RANGE))
	rand_pos.y = rand_height
	apply_central_impulse(rand_pos)

	# Delay time for player to be able to collect it
	get_tree().create_timer(coin_delay).timeout.connect(set_collision_layer_value.bind(3, true))
	_player_detection_area.body_entered.connect(_on_body_entered)


func set_target(new_target: PhysicsBody3D) -> void:
	if _consumed:
		return
	PhysicsServer3D.body_add_collision_exception(get_rid(), new_target.get_rid())

	if _target == null:
		sleeping = true
		freeze = true

		_initial_tween_position = global_position
		_target = new_target
		var tween := create_tween()
		tween.tween_method(_follow, 0.0, 1.0, FOLLOW_TWEEN_DURATION)
		tween.tween_callback(_collect)


func _physics_process(_delta: float) -> void:
	# Coin revive logic is authoritative; clients only render synced transforms.
	if not multiplayer.is_server():
		return
	if _consumed:
		return
	if _target != null:
		return
	var downed := _find_nearby_downed_player()
	if downed != null:
		set_target(downed)


func _follow(offset: float) -> void:
	global_position = lerp(_initial_tween_position, _target.global_position, offset)


func _on_body_entered(body: PhysicsBody3D) -> void:
	if not multiplayer.is_server():
		return
	if _consumed:
		return
	if body is Player:
		var player := body as Player
		if player.can_be_revived():
			set_target(player)
			return
		# When someone is downed, keep coins for revive instead of normal pickup.
		if _has_any_downed_player():
			return
		set_target(player)


func _collect() -> void:
	if _consumed:
		return
	_collect_audio.pitch_scale = randfn(1.0, 0.1)
	var consumed_for_revive := false
	if _target is Player:
		var player := _target as Player
		if player.can_be_revived():
			consumed_for_revive = player.try_revive_with_coin()
	if not consumed_for_revive:
		_target.collect_coin()
	_consume_coin.rpc()


@rpc("authority", "call_local", "reliable")
func _consume_coin() -> void:
	if _consumed:
		return
	_consumed = true
	# Make coin instantly unavailable and invisible on every peer.
	_player_detection_area.monitoring = false
	set_collision_layer(0)
	set_collision_mask(0)
	sleeping = true
	freeze = true
	hide()
	# Play consume sound for everyone at usage time.
	_collect_audio.play()
	await _collect_audio.finished
	queue_free()


func _find_nearby_downed_player() -> Player:
	var nearest: Player = null
	var nearest_dist_sq := DOWNED_SCAN_RADIUS * DOWNED_SCAN_RADIUS
	for node in get_tree().get_nodes_in_group("downed_players"):
		if not (node is Player):
			continue
		var player := node as Player
		var dist_sq := global_position.distance_squared_to(player.global_position)
		if dist_sq > nearest_dist_sq:
			continue
		nearest = player
		nearest_dist_sq = dist_sq
	return nearest


func _has_any_downed_player() -> bool:
	return not get_tree().get_nodes_in_group("downed_players").is_empty()
