extends GutTest

class MockPlayerSpawner:
	extends PlayerSpawner

	var respawned_ids: Array[int] = []

	func _ready() -> void:
		# Disable MultiplayerSpawner wiring in unit/integration tests.
		pass

	func respawn_player(id: int) -> void:
		respawned_ids.append(id)


func _setup_fall_context() -> Dictionary:
	# Build a minimal scene graph for deterministic gameplay checks without
	# loading main.tscn (which can trigger intermittent PulseAudio teardown errors).
	var root := Node.new()
	add_child_autofree(root)
	var players_root := Node3D.new()
	players_root.name = "Players"
	root.add_child(players_root)

	var mock_spawner: MockPlayerSpawner = MockPlayerSpawner.new()
	mock_spawner.name = "MockSpawner"
	root.add_child(mock_spawner)

	var director := MatchDirector.new()
	director.force_server_mode = true
	director.auto_start_match = false
	director.player_spawner = mock_spawner
	root.add_child(director)

	var fall_checker := FallChecker.new()
	fall_checker.fall_height = -11.0
	fall_checker.debug_respawn = false
	fall_checker.player_spawner = mock_spawner
	fall_checker.match_director = director
	root.add_child(fall_checker)
	await wait_process_frames(2)

	assert_not_null(fall_checker)
	assert_not_null(players_root)

	var player_scene: PackedScene = preload("res://player/player.tscn")
	var player: Player = player_scene.instantiate() as Player
	assert_not_null(player)

	var player_id: int = 1
	player.name = str(player_id)
	# Avoid local-authority camera grab side effects ("NO GRAB") in test runtime.
	player.set_multiplayer_authority(2)
	players_root.add_child(player)
	await wait_process_frames(2)

	fall_checker.player_spawned(player_id, player)
	await wait_process_frames(1)
	return {
		"fall_checker": fall_checker,
		"player": player,
		"player_id": player_id,
		"mock_spawner": mock_spawner,
		"match_director": director,
	}


func _simulate_fall(fall_checker: FallChecker, player: Player) -> void:
	# Force player below threshold, then trigger the checker once.
	player.global_position = Vector3(0.0, fall_checker.fall_height - 5.0, 0.0)
	fall_checker.check_fallen()
	await wait_process_frames(1)


func _simulate_external_damage_sync(player: Player, new_lives: int) -> void:
	# Simulate authoritative damage (e.g. bomb hit) already synced to the player node.
	player.set_lives(new_lives)
	await wait_process_frames(1)


func test_fall_decrements_lives_by_one() -> void:
	var ctx: Dictionary = await _setup_fall_context()
	var fall_checker: FallChecker = ctx["fall_checker"] as FallChecker
	var player: Player = ctx["player"] as Player
	var player_id: int = int(ctx["player_id"])
	var mock_spawner: MockPlayerSpawner = ctx["mock_spawner"] as MockPlayerSpawner
	var director: MatchDirector = ctx["match_director"] as MatchDirector
	var lives_before: int = int(director.get_lives(player_id))
	await _simulate_fall(fall_checker, player)

	var lives_after: int = int(director.get_lives(player_id))
	assert_eq(lives_before - 1, lives_after, "Une chute doit retirer exactement 1 vie")
	assert_eq(1, mock_spawner.respawned_ids.size(), "Le respawn doit etre demande une fois")
	assert_eq(player_id, mock_spawner.respawned_ids[0], "Le respawn doit cibler le bon player")


func test_zero_lives_marks_dead_and_no_more_decrement() -> void:
	var ctx: Dictionary = await _setup_fall_context()
	var fall_checker: FallChecker = ctx["fall_checker"] as FallChecker
	var player: Player = ctx["player"] as Player
	var player_id: int = int(ctx["player_id"])
	var mock_spawner: MockPlayerSpawner = ctx["mock_spawner"] as MockPlayerSpawner
	var director: MatchDirector = ctx["match_director"] as MatchDirector

	director.set_player_lives(player_id, 1, "test_setup")
	await _simulate_fall(fall_checker, player)

	var lives_after_first_fall: int = int(director.get_lives(player_id))
	assert_eq(0, lives_after_first_fall, "Avec 1 vie restante, la chute doit mettre les vies a 0")
	assert_false(player.is_in_group("players"), "A 0 vie le player doit etre marque comme mort")
	assert_eq(0, mock_spawner.respawned_ids.size(), "A 0 vie, le MatchDirector doit refuser le respawn")

	# Reset cooldown to isolate the "already at zero lives" branch.
	fall_checker.last_fall_ms_by_player[player_id] = 0
	await _simulate_fall(fall_checker, player)

	var lives_after_second_fall: int = int(director.get_lives(player_id))
	assert_eq(0, lives_after_second_fall, "A 0 vie, une nouvelle chute ne doit plus decrementer")
	assert_eq(0, mock_spawner.respawned_ids.size(), "A 0 vie, aucune demande de respawn")


func test_bomb_damage_then_fall_uses_consistent_lives_counter() -> void:
	var ctx: Dictionary = await _setup_fall_context()
	var fall_checker: FallChecker = ctx["fall_checker"] as FallChecker
	var player: Player = ctx["player"] as Player
	var player_id: int = int(ctx["player_id"])
	var mock_spawner: MockPlayerSpawner = ctx["mock_spawner"] as MockPlayerSpawner
	var director: MatchDirector = ctx["match_director"] as MatchDirector

	# Emulate two bomb hits (5 -> 3) already applied on the authoritative player.
	director.set_player_lives(player_id, 3, "test_external_damage")
	await _simulate_external_damage_sync(player, 3)
	assert_eq(3, player.get_lives(), "Le player doit etre a 3 vies apres degats externes")

	# FallChecker now asks MatchDirector directly; it must apply 3 -> 2.
	await _simulate_fall(fall_checker, player)

	var lives_after_fall: int = int(director.get_lives(player_id))
	assert_eq(2, lives_after_fall, "Apres degats bombe puis chute, les vies doivent passer de 3 a 2")
	assert_eq(2, player.get_lives(), "Le compteur local player doit rester coherent avec FallChecker")
	assert_eq(1, mock_spawner.respawned_ids.size(), "Une seule demande de respawn est attendue")
