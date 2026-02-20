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
