extends Node
class_name FallChecker

signal lives_status_changed(status_text: String)

@export var initial_lives := 5
@export var fall_height: float
@export var player_spawner: PlayerSpawner
@export var debug_respawn := true

var timer : Timer
var players = {} # {Peer ID: Player}
var lives_by_player: Dictionary = {} # {Peer ID: lives}
var last_fall_ms_by_player: Dictionary = {} # {Peer ID: timestamp}


func _ready() -> void:
	timer = Timer.new()
	add_child(timer)
	timer.start(0.25)
	timer.timeout.connect(check_fallen)
	
	player_spawner.player_spawned.connect(player_spawned)
	player_spawner.player_despawned.connect(player_despawned)
	_emit_lives_status()
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] ready | multiplayer.is_server=%s fall_height=%s" % [str(multiplayer.is_server()), str(fall_height)])


func player_spawned(id: int, player: Player) -> void:
	players[id] = player
	if not lives_by_player.has(id):
		lives_by_player[id] = initial_lives
	_sync_lives_to_player(player, id, int(lives_by_player[id]))
	_sync_dead_state_to_player(player, id, false)
	_emit_lives_status()
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] tracked player=%d y=%s lives=%d" % [id, str(player.global_position.y), int(lives_by_player[id])])


func player_despawned(id: int) -> void:
	players.erase(id)
	lives_by_player.erase(id)
	last_fall_ms_by_player.erase(id)
	_emit_lives_status()
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] untracked player=%d" % id)


func check_fallen() -> void:
	if not multiplayer.is_server():
		return
	var now_ms: int = Time.get_ticks_msec()
	for id in players.keys():
		var player = players[id] as Player
		if player.global_position.y >= fall_height:
			continue
		var last_fall_ms: int = int(last_fall_ms_by_player.get(id, 0))
		if now_ms - last_fall_ms < 800:
			continue
		last_fall_ms_by_player[id] = now_ms
		var current_lives: int = int(lives_by_player.get(id, initial_lives))
		if current_lives <= 0:
			continue
		var next_lives: int = maxi(0, current_lives - 1)
		lives_by_player[id] = next_lives
		_sync_lives_to_player(player, id, next_lives)
		_emit_lives_status()
		if debug_respawn:
			DebugLog.gameplay("[FallChecker] respawn trigger | player=%d y=%s threshold=%s lives=%d" % [id, str(player.global_position.y), str(fall_height), next_lives])
		player_spawner.respawn_player(id)
		if next_lives == 0:
			_sync_dead_state_to_player(player, id, true)


func _emit_lives_status() -> void:
	if not multiplayer.is_server():
		return
	var ids := PackedInt32Array(lives_by_player.keys())
	ids.sort()
	var lines: PackedStringArray = []
	lines.append("LIVES")
	for id in ids:
		var lives: int = int(lives_by_player[id])
		var state := "DEAD" if lives == 0 else "ALIVE"
		lines.append("player_%d: %d (%s)" % [id, lives, state])
	lives_status_changed.emit("\n".join(lines))


func _sync_lives_to_player(player: Player, id: int, lives: int) -> void:
	if id == multiplayer.get_unique_id():
		player.set_lives(lives)
	else:
		player.set_lives.rpc_id(id, lives)


func _sync_dead_state_to_player(player: Player, id: int, is_dead: bool) -> void:
	player.set_dead_state.rpc(is_dead)
