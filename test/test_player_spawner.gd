extends GutTest

const PLAYER_SPAWNER_SCRIPT := preload("res://main/player_spawner.gd")
const PLAYER_SCENE := preload("res://player/player.tscn")


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
