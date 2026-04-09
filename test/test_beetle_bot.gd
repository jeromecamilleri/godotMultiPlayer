extends GutTest

const MATCH_DIRECTOR_SCRIPT := preload("res://main/match_director.gd")

func test_beetle_bot_scene_loads_and_exposes_damage() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")
	assert_not_null(beetle_scene, "La scene beetle_bot.tscn doit exister")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: Node = beetle_scene.instantiate()
	test_root.add_child(beetle)
	await wait_process_frames(2)

	assert_true(beetle.has_method("damage"), "Le beetle bot doit exposer damage(...)")
	assert_not_null(beetle.get_node_or_null("BeetlebotSkin"), "La skin du beetle bot doit etre instanciee")


func test_beetle_bot_damage_accepts_optional_attacker_peer_id() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: Node = beetle_scene.instantiate()
	test_root.add_child(beetle)
	await wait_process_frames(2)

	beetle.set("coins_count", 0)
	beetle.call("damage", Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 42)
	await wait_process_frames(1)

	assert_eq(true, beetle.get("_alive"), "Le beetle bot doit survivre a un faible impact isole")


func test_beetle_bot_requires_multiple_strong_hits_to_die() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: Node = beetle_scene.instantiate()
	test_root.add_child(beetle)
	await wait_process_frames(2)

	beetle.set("coins_count", 0)
	beetle.call("damage", Vector3.ZERO, Vector3(9.0, 0.0, 0.0), 42)
	await wait_process_frames(1)
	assert_eq(true, beetle.get("_alive"), "Une seule bombe ne doit plus tuer le beetle bot")

	beetle.call("damage", Vector3.ZERO, Vector3(9.0, 0.0, 0.0), 42)
	await wait_process_frames(1)
	assert_eq(false, beetle.get("_alive"), "Deux forts impacts doivent suffire a tuer le beetle bot")


func test_beetle_bot_kill_reports_score_to_match_director() -> void:
	var test_root := Node3D.new()
	add_child_autofree(test_root)

	var director := MATCH_DIRECTOR_SCRIPT.new()
	director.force_server_mode = true
	director.auto_start_match = false
	test_root.add_child(director)
	await wait_process_frames(1)

	director.register_peer(42)

	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")
	var beetle: Node = beetle_scene.instantiate()
	test_root.add_child(beetle)
	await wait_process_frames(2)

	beetle.set("coins_count", 0)
	beetle.call("damage", Vector3.ZERO, Vector3(9.0, 0.0, 0.0), 42)
	await wait_process_frames(1)
	beetle.call("damage", Vector3.ZERO, Vector3(9.0, 0.0, 0.0), 42)
	await wait_process_frames(1)

	assert_true(director.get_snapshot_text().find("peer_42: 1") >= 0, "Beetle kill should grant +1 score to attacker")


func test_beetle_bot_moves_toward_target_without_navigation_path() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: RigidBody3D = beetle_scene.instantiate()
	test_root.add_child(beetle)

	var target := Node3D.new()
	target.position = Vector3(4.0, 0.0, 0.0)
	test_root.add_child(target)
	await wait_process_frames(2)

	beetle.set("_target", target)
	var start_x: float = beetle.global_position.x
	await wait_seconds(0.6)

	assert_gt(beetle.global_position.x, start_x + 0.2, "Le beetle bot doit avancer vers sa cible meme sans path de navigation")


func test_beetle_bot_acquires_target_from_detection_area_without_signal_dependency() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: RigidBody3D = beetle_scene.instantiate()
	test_root.add_child(beetle)

	var target := Node3D.new()
	target.add_to_group("players")
	target.set_multiplayer_authority(2)
	target.position = Vector3(3.0, 0.0, 0.0)
	test_root.add_child(target)
	await wait_process_frames(3)

	var start_x: float = beetle.global_position.x
	await wait_seconds(0.7)

	assert_eq(2, beetle.call("get_current_target_peer_id"), "Le beetle bot doit reacquerir un joueur present dans sa zone meme sans signal body_entered exploitable.")
	assert_gt(beetle.global_position.x, start_x + 0.15, "Le beetle bot doit reprendre sa poursuite une fois le joueur detecte dans sa zone.")


func test_beetle_bot_keeps_walk_state_while_shoving_close_target() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)
	var beetle: RigidBody3D = beetle_scene.instantiate()
	test_root.add_child(beetle)

	var target := CharacterBody3D.new()
	target.position = Vector3(0.6, 0.0, 0.0)
	test_root.add_child(target)
	await wait_process_frames(2)

	beetle.set("_target", target)
	await wait_seconds(0.12)

	assert_eq("Walk", beetle.get("_visual_state"), "Au contact proche d'un joueur, le beetle doit continuer a marcher pour garder un push fluide.")


func test_beetle_bot_returns_to_ground_after_being_lifted() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)

	var ground := StaticBody3D.new()
	test_root.add_child(ground)
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var beetle: RigidBody3D = beetle_scene.instantiate()
	test_root.add_child(beetle)
	beetle.global_position = Vector3(0.0, 2.2, 0.0)
	await wait_process_frames(3)

	var start_y: float = beetle.global_position.y
	await wait_seconds(0.9)

	assert_lt(beetle.global_position.y, start_y - 0.4, "Le beetle bot doit redescendre vers le sol s'il est souleve")
	assert_lt(beetle.global_position.y, 0.5, "Le beetle bot doit se recoller rapidement au sol")


func test_beetle_bot_stays_in_guard_zone_and_returns_home() -> void:
	var beetle_scene: PackedScene = preload("res://enemies/beetle_bot.tscn")

	var test_root := Node3D.new()
	add_child_autofree(test_root)

	var ground := StaticBody3D.new()
	test_root.add_child(ground)
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	ground_shape.shape = box
	ground.add_child(ground_shape)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var beetle: RigidBody3D = beetle_scene.instantiate()
	test_root.add_child(beetle)
	await wait_process_frames(2)

	beetle.set("guard_chase_radius", 5.0)
	beetle.set("guard_return_radius", 6.0)
	beetle.set("return_home_stop_distance", 0.3)
	beetle.set("move_speed", 2.0)
	beetle.set("_home_position", Vector3.ZERO)

	var far_target := Node3D.new()
	far_target.add_to_group("players")
	far_target.set_multiplayer_authority(2)
	far_target.position = Vector3(20.0, 0.0, 0.0)
	test_root.add_child(far_target)
	await wait_process_frames(2)

	beetle.set("_target", far_target)
	var start_position: Vector3 = beetle.global_position
	await wait_seconds(0.35)

	var horizontal_delta_after_far_target := beetle.global_position - start_position
	horizontal_delta_after_far_target.y = 0.0
	assert_lt(horizontal_delta_after_far_target.length(), 0.35, "Le beetle ne doit pas poursuivre un joueur loin hors de sa zone de garde.")
	assert_false(beetle.call("_should_keep_target", far_target), "Le leash doit refuser une cible trop loin de la zone de defense.")
	assert_false(beetle.call("_is_valid_player_target", far_target), "Une cible hors de la zone Activator ne doit pas etre consideree comme valide.")
