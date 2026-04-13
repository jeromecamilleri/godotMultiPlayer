extends MultiplayerSpawner
class_name PlayerSpawner

signal player_spawned(id: int, player: Player)
signal player_despawned(id: int)

@export var player_scene: PackedScene
@export var spawn_points: SpawnPoints


func _ready() -> void:
	# MultiplayerSpawner uses this callback to build instances from spawn payload.
	spawn_function = custom_spawn
	multiplayer.peer_connected.connect(create_player)
	multiplayer.peer_disconnected.connect(destroy_player)


func create_player(id: int):
	# Only server can create replicated player instances.
	if not multiplayer.is_server(): return

	var spawn_position = _get_spawn_position_for_player()
	spawn([id, spawn_position])
	call_deferred("_emit_spawned_if_present", id)
	DebugLog.gameplay("Player %d spawned at %s" % [id, str(spawn_position)])


func destroy_player(id: int):
	# Only server can despawn replicated player instances.
	if not multiplayer.is_server(): return
	var player := get_player_or_null(id)
	if player == null:
		return
	player_despawned.emit(id)
	player.queue_free()


func respawn_player(id: int) -> void:
	var player = get_node(spawn_path).get_node(str(id)) as Player
	var spawn_position = _get_spawn_position_for_player()
	# Keep server-side position tracking in sync immediately to avoid repeated
	# fall detections while waiting for authority state replication.
	player.global_position = spawn_position
	player.velocity = Vector3.ZERO
	player.respawn.rpc_id(id, spawn_position)
	DebugLog.gameplay("Respawn player %d at %s" % [id, str(spawn_position)])


## Retourne la position de spawn en tenant compte de DEV_SPAWN_ZONE.
## Si DEV_SPAWN_ZONE est définie et non vide, utilise le spawn de la zone ciblée.
func _get_spawn_position_for_player() -> Vector3:
	var dev_zone := OS.get_environment("DEV_SPAWN_ZONE").strip_edges().to_lower()
	if not dev_zone.is_empty() and dev_zone != "hub" and spawn_points.has_method("get_dev_zone_spawn_position"):
		return spawn_points.get_dev_zone_spawn_position(dev_zone)
	return spawn_points.get_spawn_position()


func custom_spawn(vars) -> Node:
	var id = vars[0]
	var pos = vars[1]
	
	var p: Player = player_scene.instantiate()
	# Player authority always matches peer id for input/gameplay ownership.
	p.set_multiplayer_authority(id)
	p.call_deferred("set_position", pos)
	p.name = str(id)
	return p


func get_player_or_null(id: int) -> Player:
	return get_node(spawn_path).get_node_or_null(str(id))


func _emit_spawned_if_present(id: int) -> void:
	var player := get_player_or_null(id)
	if player == null:
		return
	player_spawned.emit(id, player)


func on_spawned(node: Node) -> void:
	player_spawned.emit(node.get_multiplayer_authority(), node)


func on_despawned(node: Node) -> void:
	player_despawned.emit(node.get_multiplayer_authority())
