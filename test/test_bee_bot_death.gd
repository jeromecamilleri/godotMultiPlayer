extends GutTest


func test_bee_bot_scene_loads_and_exposes_damage() -> void:
	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	assert_not_null(bee_scene, "La scene bee_bot.tscn doit exister")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var bee: Node = bee_scene.instantiate()
	test_root.add_child(bee)
	await wait_process_frames(1)

	assert_true(bee.has_method("damage"), "Le bee bot doit exposer damage(...)")


func test_bee_bot_damage_marks_dead_then_frees_instance() -> void:
	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var bee: Node = bee_scene.instantiate()
	test_root.add_child(bee)
	await wait_process_frames(2)

	# Keep test focused on death flow and avoid coin-related side effects.
	bee.set("coins_count", 0)
	bee.call("damage", Vector3.ZERO, Vector3(1.0, 0.0, 0.0))

	assert_eq(false, bee.get("_alive"), "damage() doit marquer _alive a false")

	var has_freed := false
	for _i in range(480): # ~8s @60fps max for death timer + puff animation
		await wait_process_frames(1)
		if not is_instance_valid(bee):
			has_freed = true
			break

	assert_true(has_freed, "Le bee bot devrait etre queue_free apres sa sequence de mort")
