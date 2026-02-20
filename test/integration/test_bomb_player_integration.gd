extends GutTest

const BOMB_SCENE: PackedScene = preload("res://main/static_body_3d_bomb.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

class MockPlayerSpawner:
	extends PlayerSpawner

	func _ready() -> void:
		# Disable MultiplayerSpawner wiring in integration test context.
		pass


func _spawn_world() -> Node3D:
	# Isolated world to run an integration-like interaction between real scenes.
	var world := Node3D.new()
	add_child_autofree(world)
	await wait_process_frames(2)
	return world


func test_bomb_explosion_damages_player_without_signature_errors() -> void:
	var world: Node3D = await _spawn_world()
	var players_root := Node3D.new()
	players_root.name = "Players"
	world.add_child(players_root)

	var mock_spawner := MockPlayerSpawner.new()
	world.add_child(mock_spawner)

	var director := MatchDirector.new()
	director.force_server_mode = true
	director.auto_start_match = false
	director.player_spawner = mock_spawner
	world.add_child(director)

	var fall_checker := FallChecker.new()
	fall_checker.player_spawner = mock_spawner
	fall_checker.match_director = director
	fall_checker.fall_height = -11.0
	fall_checker.debug_respawn = false
	world.add_child(fall_checker)
	await wait_process_frames(2)

	var player: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(player)
	var peer_id: int = multiplayer.get_unique_id()
	player.set_multiplayer_authority(peer_id)
	players_root.add_child(player)
	player.global_position = Vector3(0.7, 0.0, 0.0)
	await wait_process_frames(2)
	fall_checker.player_spawned(peer_id, player)
	await wait_process_frames(1)

	# Precondition sanity check.
	assert_eq(5, player.get_lives(), "Player should start with 5 lives")
	assert_eq(5, director.get_lives(peer_id), "Director should track initial player lives")

	var bomb: Bomb = BOMB_SCENE.instantiate() as Bomb
	assert_not_null(bomb)
	bomb.owner_peer_id = multiplayer.get_unique_id()
	bomb.explosion_radius = 4.0
	bomb.explosion_force = 10.0
	world.add_child(bomb)
	bomb.global_position = Vector3.ZERO
	await wait_process_frames(1)

	# Direct call keeps test deterministic and still exercises damage signature path.
	bomb._apply_explosion_damage()
	await wait_process_frames(2)

	assert_eq(4, player.get_lives(), "Bomb explosion should reduce player lives by one")
	assert_eq(4, director.get_lives(peer_id), "Director must also be updated to avoid life rebound")

	# If director remained stale, FallChecker would overwrite player lives back to 5.
	player.global_position = Vector3(0.0, 0.0, 0.0)
	fall_checker.check_fallen()
	await wait_process_frames(1)
	assert_eq(4, player.get_lives(), "Lives should not bounce back after FallChecker sync")
