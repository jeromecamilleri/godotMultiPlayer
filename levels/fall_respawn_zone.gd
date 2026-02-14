extends Area3D

@export var player_spawner_path: NodePath = NodePath("../../PlayerSpawner")
@export var debug_respawn := true

var player_spawner: PlayerSpawner


func _ready() -> void:
	monitoring = true
	monitorable = true
	if has_node(player_spawner_path):
		player_spawner = get_node(player_spawner_path) as PlayerSpawner
	if player_spawner == null:
		player_spawner = get_tree().root.find_child("PlayerSpawner", true, false) as PlayerSpawner
	if player_spawner == null:
		push_warning("FallRespawnZone: PlayerSpawner not found, respawn disabled.")
	body_entered.connect(_on_body_entered)
	if debug_respawn:
		DebugLog.gameplay("[FallRespawnZone] ready | monitoring=%s mask=%s spawner_found=%s" % [str(monitoring), str(collision_mask), str(player_spawner != null)])


func _on_body_entered(body: Node) -> void:
	if debug_respawn:
		DebugLog.gameplay("[FallRespawnZone] body_entered=%s class=%s multiplayer.is_server=%s" % [body.name, body.get_class(), str(multiplayer.is_server())])
	if not multiplayer.is_server():
		return
	if player_spawner == null:
		if debug_respawn:
			DebugLog.gameplay("[FallRespawnZone] missing PlayerSpawner, skip respawn")
		return
	if body is Player:
		var player := body as Player
		if debug_respawn:
			DebugLog.gameplay("[FallRespawnZone] respawn trigger | player_authority=%d" % player.get_multiplayer_authority())
		player_spawner.respawn_player(player.get_multiplayer_authority())
