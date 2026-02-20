extends Node
class_name FallChecker

@export var initial_lives := 5
@export var fall_height: float
@export var player_spawner: PlayerSpawner
@export var match_director: Node
@export var debug_respawn := true

var timer : Timer
var players = {} # {Peer ID: Player}
var last_fall_ms_by_player: Dictionary = {} # {Peer ID: timestamp}


func _ready() -> void:
	timer = Timer.new()
	add_child(timer)
	# Polling-based check is enough here and keeps fall handling centralized.
	timer.start(0.25)
	timer.timeout.connect(check_fallen)
	
	player_spawner.player_spawned.connect(player_spawned)
	player_spawner.player_despawned.connect(player_despawned)
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] ready | multiplayer.is_server=%s fall_height=%s" % [str(multiplayer.is_server()), str(fall_height)])


func player_spawned(id: int, player: Player) -> void:
	players[id] = player
	if _has_match_director():
		match_director.register_player_spawn(id, initial_lives)
	_sync_lives_to_player(player, id, _get_lives_for_player(id))
	_sync_dead_state_to_player(player, id, false)
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] tracked player=%d y=%s lives=%d" % [id, str(player.global_position.y), _get_lives_for_player(id)])


func player_despawned(id: int) -> void:
	players.erase(id)
	last_fall_ms_by_player.erase(id)
	if _has_match_director():
		match_director.unregister_player(id)
	if debug_respawn:
		DebugLog.gameplay("[FallChecker] untracked player=%d" % id)


func check_fallen() -> void:
	# Server is the single source of truth for lives/respawn state.
	if not multiplayer.is_server():
		return
	var now_ms: int = Time.get_ticks_msec()
	for id in players.keys():
		var player = players[id] as Player
		var current_lives: int = _get_lives_for_player(id)
		_sync_lives_to_player(player, id, current_lives)
		if player.global_position.y >= fall_height:
			continue
		var last_fall_ms: int = int(last_fall_ms_by_player.get(id, 0))
		# Cooldown avoids multiple life losses before respawn settles.
		if now_ms - last_fall_ms < 800:
			continue
		last_fall_ms_by_player[id] = now_ms
		if current_lives <= 0:
			continue
		var next_lives: int = _report_fall_and_get_next_lives(id, current_lives)
		_sync_lives_to_player(player, id, next_lives)
		if debug_respawn:
			DebugLog.gameplay("[FallChecker] respawn trigger | player=%d y=%s threshold=%s lives=%d" % [id, str(player.global_position.y), str(fall_height), next_lives])
		if _has_match_director():
			if next_lives > 0:
				match_director.request_respawn(id)
			else:
				# Keep downed players on-map so teammates can bring a revive coin.
				player_spawner.respawn_player(id)
		else:
			player_spawner.respawn_player(id)
		if next_lives == 0:
			_sync_dead_state_to_player(player, id, true)
			if _all_players_dead() and _has_match_director():
				# Match result is server-authoritative and centralized in MatchDirector.
				match_director.report_team_lost("all_players_dead")


func _sync_lives_to_player(player: Player, id: int, lives: int) -> void:
	# Update local peer directly, remote peers through targeted RPC.
	if id == multiplayer.get_unique_id():
		player.set_lives(lives)
	else:
		player.set_lives.rpc_id(id, lives)


func _sync_dead_state_to_player(player: Player, id: int, is_dead: bool) -> void:
	player.set_dead_state.rpc(is_dead)


func _all_players_dead() -> bool:
	if players.is_empty():
		return false
	for id in players.keys():
		if _get_lives_for_player(id) > 0:
			return false
	return true


func _get_lives_for_player(id: int) -> int:
	if _has_match_director():
		return int(match_director.get_lives(id))
	return initial_lives


func _report_fall_and_get_next_lives(id: int, current_lives: int) -> int:
	if _has_match_director():
		return int(match_director.report_player_fell(id))
	return maxi(0, current_lives - 1)


func _has_match_director() -> bool:
	return (
		is_instance_valid(match_director)
		and match_director.has_method("register_player_spawn")
		and match_director.has_method("report_player_fell")
		and match_director.has_method("request_respawn")
		and match_director.has_method("get_lives")
	)
