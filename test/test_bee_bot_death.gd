extends GutTest

const MATCH_DIRECTOR_SCRIPT := preload("res://main/match_director.gd")

func test_bee_bot_scene_loads_and_exposes_damage() -> void:
	# Smoke test: scene is loadable and exposes the common damage entry point.
	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	assert_not_null(bee_scene, "La scene bee_bot.tscn doit exister")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var bee: Node = bee_scene.instantiate()
	test_root.add_child(bee)
	await wait_process_frames(1)

	assert_true(bee.has_method("damage"), "Le bee bot doit exposer damage(...)")


func test_bee_bot_damage_marks_dead_then_finalizes_removed_state() -> void:
	# Integration-like check for the full death flow from damage to final dead state.
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

	var is_removed := false
	for _i in range(480): # ~8s @60fps max for death timer + puff animation
		await wait_process_frames(1)
		if not bee.visible:
			is_removed = true
			break

	assert_true(is_removed, "Le bee bot devrait etre finalise (cache/inactif) apres sa sequence de mort")
	assert_false(bee.is_physics_processing(), "Le bee bot finalise ne doit plus etre simule")


func test_bee_bot_kill_reports_score_to_match_director() -> void:
	# Validate integration between enemy death and centralized match score.
	var test_root := Node3D.new()
	add_child_autofree(test_root)

	var director := MATCH_DIRECTOR_SCRIPT.new()
	director.force_server_mode = true
	director.auto_start_match = false
	test_root.add_child(director)
	await wait_process_frames(1)

	director.register_peer(42)

	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	var bee: Node = bee_scene.instantiate()
	test_root.add_child(bee)
	await wait_process_frames(2)

	bee.set("coins_count", 0)
	bee.call("damage", Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 42)
	await wait_process_frames(1)

	assert_true(director.get_snapshot_text().find("peer_42: 1") >= 0, "Bee kill should grant +1 score to attacker")


func test_bee_bot_director_config_updates_patrol_center_and_height() -> void:
	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var bee: Node = bee_scene.instantiate()
	test_root.add_child(bee)
	await wait_process_frames(2)

	bee.call("apply_director_config", {
		"patrol_center": Vector3(3.0, 4.0, -6.0),
		"patrol_height_offset": 1.25,
	})

	assert_eq(Vector3(3.0, 4.0, -6.0), bee.get("_patrol_center"), "La config du directeur doit pouvoir ancrer la patrouille sur la pomme.")
	assert_eq(1.25, float(bee.get("patrol_height_offset")), "La config du directeur doit regler la hauteur de garde.")


func test_bee_bot_looks_toward_bullet_aim_point() -> void:
	var bee_scene: PackedScene = preload("res://enemies/bee_bot.tscn")
	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var bee := bee_scene.instantiate() as Node3D
	test_root.add_child(bee)
	await wait_process_frames(2)

	bee.global_position = Vector3.ZERO
	var aim_point := Vector3(5.0, 1.0, -8.0)
	bee.call("_look_toward_aim_point", aim_point, 1.0)

	var expected_direction := (aim_point - bee.global_position).normalized()
	var visual_forward := -bee.global_basis.z.normalized()
	assert_gt(visual_forward.dot(expected_direction), 0.98, "L'abeille doit regarder dans la meme direction que sa bullet.")
