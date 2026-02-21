extends GutTest

const BOMB_DOOR_SCRIPT := preload("res://main/bomb_door.gd")


func test_bomb_door_opens_when_bomb_is_in_range() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	await wait_process_frames(1)

	var door: BombDoor = BOMB_DOOR_SCRIPT.new()
	assert_not_null(door)

	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = BoxMesh.new()
	door.add_child(mesh)

	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = BoxShape3D.new()
	door.add_child(collider)
	world.add_child(door)
	await wait_process_frames(2)

	door.required_bombs = 1
	door.trigger_radius = 4.0
	door.open_behavior = BombDoor.OpenBehavior.DISINTEGRATE
	door.on_bomb_exploded(door.global_position + Vector3(0.5, 0.0, 0.0), 2.0, 1)
	await wait_process_frames(1)

	assert_true(door.is_open(), "La porte utilitaire doit s'ouvrir apres explosion proche")
	assert_true(collider.disabled, "La collision doit etre desactivee apres ouverture")
