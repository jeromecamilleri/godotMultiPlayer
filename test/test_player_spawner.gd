extends GutTest

const PLAYER_SPAWNER_SCRIPT := preload("res://main/player_spawner.gd")
const PLAYER_SCENE := preload("res://player/player.tscn")

var _previous_dev_spawn_zone := ""


func before_each() -> void:
	_previous_dev_spawn_zone = OS.get_environment("DEV_SPAWN_ZONE")


func after_each() -> void:
	OS.set_environment("DEV_SPAWN_ZONE", _previous_dev_spawn_zone)


func test_custom_spawn_does_not_emit_player_spawned_before_node_is_spawned() -> void:
	var spawner := PLAYER_SPAWNER_SCRIPT.new()
	add_child_autofree(spawner)
	spawner.player_scene = PLAYER_SCENE

	var emitted_count := 0
	spawner.player_spawned.connect(func(_id: int, _player) -> void:
		emitted_count += 1
	)

	var node := spawner.custom_spawn([7, Vector3.ZERO])
	assert_not_null(node, "Le spawner doit retourner une instance de joueur.")
	assert_eq(0, emitted_count, "custom_spawn ne doit pas émettre player_spawned avant que le joueur soit réellement ajouté au MultiplayerSpawner.")


func test_on_spawned_emits_player_spawned_once() -> void:
	var spawner := PLAYER_SPAWNER_SCRIPT.new()
	add_child_autofree(spawner)
	spawner.player_scene = PLAYER_SCENE

	var emitted_ids: Array[int] = []
	spawner.player_spawned.connect(func(id: int, _player) -> void:
		emitted_ids.append(id)
	)

	var node := spawner.custom_spawn([9, Vector3.ZERO])
	node.set_multiplayer_authority(9)
	spawner.on_spawned(node)

	assert_eq([9], emitted_ids, "Le signal player_spawned doit être émis une seule fois via on_spawned.")


func test_destroy_player_event_is_emitted_only_via_on_despawned() -> void:
	var spawner := PLAYER_SPAWNER_SCRIPT.new()
	add_child_autofree(spawner)

	var emitted_ids: Array[int] = []
	spawner.player_despawned.connect(func(id: int) -> void:
		emitted_ids.append(id)
	)

	var node := Node3D.new()
	add_child_autofree(node)
	node.name = "11"
	node.set_multiplayer_authority(11)
	spawner.on_despawned(node)

	assert_eq([11], emitted_ids, "Le signal player_despawned doit être émis une seule fois via on_despawned.")


func test_get_spawn_position_uses_dev_zone_override_when_env_is_set() -> void:
	OS.set_environment("DEV_SPAWN_ZONE", "reactor")

	var spawner := PLAYER_SPAWNER_SCRIPT.new()
	add_child_autofree(spawner)

	var points := SpawnPoints.new()
	add_child_autofree(points)
	spawner.spawn_points = points

	var default_spawn := Node3D.new()
	default_spawn.name = "platform_default"
	default_spawn.position = Vector3(1.0, 0.0, 0.0)
	points.add_child(default_spawn)

	var reactor_spawn := Node3D.new()
	reactor_spawn.name = "zone_reactor"
	reactor_spawn.position = Vector3(99.0, 0.0, -5.0)
	points.add_child(reactor_spawn)

	await wait_process_frames(1)

	var chosen_position: Vector3 = spawner.call("_get_spawn_position_for_player")
	assert_eq(reactor_spawn.global_position, chosen_position, "DEV_SPAWN_ZONE=reactor doit forcer le spawn sur le point zone_reactor.")
