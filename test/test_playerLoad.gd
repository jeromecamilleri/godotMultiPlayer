extends GutTest

func test_player_scene_charge():
	# Basic resource load check to fail fast on missing/broken scene references.
	var scene: PackedScene = preload("res://player/player.tscn")
	assert_not_null(scene)

func test_player_instance():
	var scene: PackedScene = preload("res://player/player.tscn")
	var player: Player = scene.instantiate() as Player
	assert_not_null(player)
	assert_true(player is Player)
	# Free immediately to avoid orphan warnings in this minimal instantiation test.
	player.free()
