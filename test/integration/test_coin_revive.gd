extends GutTest

const COIN_SCENE: PackedScene = preload("res://player/coin/coin.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


func _spawn_world() -> Node3D:
	# Isolated world to run revive flow with real scenes.
	var world := Node3D.new()
	add_child_autofree(world)
	await wait_process_frames(2)
	return world


func test_coin_revives_downed_player_with_one_life() -> void:
	var world: Node3D = await _spawn_world()
	var players_root := Node3D.new()
	players_root.name = "Players"
	world.add_child(players_root)

	var director := MatchDirector.new()
	director.force_server_mode = true
	director.auto_start_match = false
	world.add_child(director)
	await wait_process_frames(1)

	var player: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(player)
	# Avoid local camera-grab side effects in test runtime.
	var peer_id: int = 2
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.global_position = Vector3.ZERO
	await wait_process_frames(2)

	director.register_player_spawn(peer_id, 0)
	director.set_player_lives(peer_id, 0, "test_setup_downed")
	player.set_lives(0)
	player.set_dead_state(true)
	await wait_process_frames(1)

	assert_true(player.can_be_revived(), "Le player doit etre downed avant la revive")
	assert_true(player.is_in_group("downed_players"), "Le player downed doit etre dans le groupe revive")

	var coin: Coin = COIN_SCENE.instantiate() as Coin
	assert_not_null(coin)
	world.add_child(coin)
	coin.global_position = Vector3(0.5, 0.0, 0.0)
	await wait_process_frames(1)

	# Force deterministic targeting, then let tween + collect callback run.
	coin.set_target(player)
	await wait_seconds(0.65)
	await wait_process_frames(1)
	assert_true(bool(coin.get("_consumed")), "La coin doit etre marquee consommee des son utilisation")
	assert_false(coin.visible, "La coin doit disparaitre visuellement apres revive")
	await wait_seconds(0.8)
	await wait_process_frames(2)

	assert_eq(1, director.get_lives(peer_id), "La revive via coin doit redonner exactement 1 vie")
	assert_eq(1, player.get_lives(), "Le player doit etre synchronise a 1 vie apres revive")
	assert_false(player.can_be_revived(), "Le player ne doit plus etre downed apres revive")
	assert_false(player.is_in_group("downed_players"), "Le groupe downed doit etre nettoye apres revive")
