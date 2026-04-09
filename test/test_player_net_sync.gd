extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


func _add_ground(root: Node3D) -> void:
	var ground := StaticBody3D.new()
	root.add_child(ground)
	var collision_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	collision_shape.shape = box
	ground.add_child(collision_shape)
	ground.global_position = Vector3(0.0, -0.5, 0.0)


func test_remote_player_brakes_horizontal_velocity_when_no_direction_is_replicated() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	_add_ground(root)

	var player: Player = PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	player.set_multiplayer_authority(2)
	player.global_position = Vector3(0.0, 0.7, 0.0)
	await wait_process_frames(3)

	player._gravity = 0.0
	player.velocity = Vector3(6.0, -1.0, 0.0)
	player._velocity = Vector3.ZERO
	player._direction = Vector3.ZERO
	player.position_before_sync = player.position

	for _step in range(8):
		player._net_sync.interpolate_client(player, 0.1)
		await wait_process_frames(1)

	assert_lt(absf(player.velocity.x), 1.0, "Un joueur distant sans direction répliquée doit freiner vite au lieu de glisser longtemps.")

