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
