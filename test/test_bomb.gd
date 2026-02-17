extends GutTest

const BOMB_SCENE: PackedScene = preload("res://main/static_body_3d_bomb.tscn")
const BEE_SCENE: PackedScene = preload("res://enemies/bee_bot.tscn")


func _spawn_test_world() -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	await wait_process_frames(2)
	return world


func test_bomb_explodes_after_fuse_timer() -> void:
	var world: Node3D = await _spawn_test_world()
	var bomb: Bomb = BOMB_SCENE.instantiate() as Bomb
	assert_not_null(bomb)

	bomb.fuse_seconds = 0.2
	world.add_child(bomb)
	bomb.global_position = Vector3.ZERO
	await wait_process_frames(1)

	var countdown_label: Label3D = bomb.get_node("CountdownLabel3D") as Label3D
	assert_not_null(countdown_label)
	assert_eq("1", countdown_label.text, "Le compte a rebours doit etre visible")

	await wait_seconds(0.4)
	await wait_process_frames(2)
	assert_false(is_instance_valid(bomb), "La bombe doit disparaitre apres l'explosion")


func test_bomb_explosion_damage_kills_bee() -> void:
	var world: Node3D = await _spawn_test_world()

	var bee: RigidBody3D = BEE_SCENE.instantiate() as RigidBody3D
	assert_not_null(bee)
	world.add_child(bee)
	bee.global_position = Vector3(0.5, 0.0, 0.0)
	await wait_process_frames(2)

	var bomb: Bomb = BOMB_SCENE.instantiate() as Bomb
	assert_not_null(bomb)
	bomb.explosion_radius = 6.0
	bomb.explosion_force = 16.0
	world.add_child(bomb)
	bomb.global_position = Vector3.ZERO
	await wait_process_frames(1)

	# In GUT offline context, we call damage directly to validate collision logic.
	bomb._apply_explosion_damage()
	await wait_seconds(2.4)
	await wait_process_frames(2)

	assert_false(bee.visible, "L'abeille doit etre finalisee en etat mort")
	assert_false(bee.is_physics_processing(), "L'abeille morte ne doit plus etre simulee")
