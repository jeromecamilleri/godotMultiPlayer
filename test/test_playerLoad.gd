extends GutTest

const PLAYER_SCENE := preload("res://player/player.tscn")


func _assert_no_no_peer_errors(context: String) -> void:
	for err in get_errors():
		if err.is_engine_error() and err.contains_text("No multiplayer peer is assigned. Unable to get unique ID."):
			err.handled = true
			fail_test("%s ne doit pas appeler get_unique_id sans peer assigne." % context)

func test_player_scene_charge():
	# Basic resource load check to fail fast on missing/broken scene references.
	assert_not_null(PLAYER_SCENE)

func test_player_instance():
	var player: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(player)
	assert_true(player is Player)
	# Free immediately to avoid orphan warnings in this minimal instantiation test.
	player.free()


func test_player_ready_and_physics_without_peer_do_not_raise_unique_id_errors() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await wait_process_frames(2)

	player._physics_process(0.016)
	await wait_process_frames(1)

	_assert_no_no_peer_errors("player sans peer")
	assert_true(player.is_inside_tree(), "Le joueur doit rester instanciable meme sans peer actif.")
