extends GutTest

class MockPlayerSpawner:
	extends PlayerSpawner

	var respawned_ids: Array[int] = []

	func respawn_player(id: int) -> void:
		respawned_ids.append(id)


func _setup_fall_context() -> Dictionary:
	var main_scene: PackedScene = preload("res://main/main.tscn")
	var main_instance: Node = main_scene.instantiate()
	add_child_autofree(main_instance)
	await wait_process_frames(2)

	var fall_checker: FallChecker = main_instance.get_node("FallChecker") as FallChecker
	var players_root: Node = main_instance.get_node("Players")
	assert_not_null(fall_checker)
	assert_not_null(players_root)

	# Use a mock spawner to avoid network RPCs in test context.
	var mock_spawner: MockPlayerSpawner = MockPlayerSpawner.new()
	autofree(mock_spawner)
	fall_checker.player_spawner = mock_spawner

	var player_scene: PackedScene = preload("res://player/player.tscn")
	var player: Player = player_scene.instantiate() as Player
	assert_not_null(player)

	var player_id: int = 1
	player.name = str(player_id)
	player.set_multiplayer_authority(player_id)
	players_root.add_child(player)
	await wait_process_frames(2)

	fall_checker.players[player_id] = player
	fall_checker.lives_by_player[player_id] = fall_checker.initial_lives
	return {
		"fall_checker": fall_checker,
		"player": player,
		"player_id": player_id,
		"mock_spawner": mock_spawner,
	}


func _simulate_fall(fall_checker: FallChecker, player: Player) -> void:
	player.global_position = Vector3(0.0, fall_checker.fall_height - 5.0, 0.0)
	fall_checker.check_fallen()
	await wait_process_frames(1)


func test_fall_decrements_lives_by_one() -> void:
	var ctx: Dictionary = await _setup_fall_context()
	var fall_checker: FallChecker = ctx["fall_checker"] as FallChecker
	var player: Player = ctx["player"] as Player
	var player_id: int = int(ctx["player_id"])
	var mock_spawner: MockPlayerSpawner = ctx["mock_spawner"] as MockPlayerSpawner
	var lives_before: int = int(fall_checker.lives_by_player[player_id])
	await _simulate_fall(fall_checker, player)

	var lives_after: int = int(fall_checker.lives_by_player[player_id])
	assert_eq(lives_before - 1, lives_after, "Une chute doit retirer exactement 1 vie")
	assert_eq(1, mock_spawner.respawned_ids.size(), "Le respawn doit etre demande une fois")
	assert_eq(player_id, mock_spawner.respawned_ids[0], "Le respawn doit cibler le bon player")


func test_zero_lives_marks_dead_and_no_more_decrement() -> void:
	var ctx: Dictionary = await _setup_fall_context()
	var fall_checker: FallChecker = ctx["fall_checker"] as FallChecker
	var player: Player = ctx["player"] as Player
	var player_id: int = int(ctx["player_id"])
	var mock_spawner: MockPlayerSpawner = ctx["mock_spawner"] as MockPlayerSpawner

	fall_checker.lives_by_player[player_id] = 1
	await _simulate_fall(fall_checker, player)

	var lives_after_first_fall: int = int(fall_checker.lives_by_player[player_id])
	assert_eq(0, lives_after_first_fall, "Avec 1 vie restante, la chute doit mettre les vies a 0")
	assert_false(player.is_in_group("players"), "A 0 vie le player doit etre marque comme mort")
	assert_eq(1, mock_spawner.respawned_ids.size(), "Un respawn doit etre demande en atteignant 0 vie")

	# Avoid cooldown side effects so we test only the zero-life branch.
	fall_checker.last_fall_ms_by_player[player_id] = 0
	await _simulate_fall(fall_checker, player)

	var lives_after_second_fall: int = int(fall_checker.lives_by_player[player_id])
	assert_eq(0, lives_after_second_fall, "A 0 vie, une nouvelle chute ne doit plus decrementer")
	assert_eq(1, mock_spawner.respawned_ids.size(), "A 0 vie, aucune nouvelle demande de respawn")
