extends Node
class_name MatchDirector

signal snapshot_changed(status_text: String)
signal state_changed(state_name: String)
signal respawn_requested(peer_id: int)

enum MatchState {
	LOBBY,
	RUNNING,
	WON,
	LOST,
	RESETTING,
}

@export var match_duration_sec: float = 180.0
@export var min_players_to_start: int = 1
@export var tick_interval_sec: float = 0.25
@export var auto_start_match: bool = true
@export var initial_lives_per_player: int = 5
@export var player_spawner: Node
@export var force_server_mode := false
@export var portal_unlock_base_wood := 4
@export var portal_unlock_wood_step_per_extra_player := 2
@export var portal_unlock_base_apples := 2
@export var portal_unlock_apples_step_per_extra_player := 1
@export var hub_chest_seed_wood := 6
@export var hub_chest_seed_apples := 2

var _state: int = MatchState.LOBBY
var _time_left_sec: float = 0.0
var _score_by_peer: Dictionary = {} # {Peer ID: score}
var _lives_by_peer: Dictionary = {} # {Peer ID: lives}
var _deaths_by_peer: Dictionary = {} # {Peer ID: deaths}
var _connected_peers: Dictionary = {} # {Peer ID: true}
var _team_progress: Dictionary = { # Shared cooperative objectives/progress.
	"relays_activated": 0,
	"players_alive": 0,
	"bees_killed": 0,
}
var _tick_timer: Timer
var _remote_snapshot_text := ""
var _snapshot_revision := 0
var _portal_breche_unlocked := false
var _portal_reactor_unlocked := false


func _ready() -> void:
	# Expose a single lookup point for gameplay systems that report score/progress.
	add_to_group("match_director")
	add_to_group("replicated_persistent_objects")
	if not _is_server_instance():
		# Clients only consume snapshots pushed by the server.
		snapshot_changed.emit(_remote_snapshot_text)
		_request_current_snapshot_when_connected()
		return

	if multiplayer.has_multiplayer_peer():
		multiplayer.peer_connected.connect(_on_peer_connected)

	if is_instance_valid(player_spawner):
		player_spawner.player_spawned.connect(_on_player_spawned)
		player_spawner.player_despawned.connect(_on_player_despawned)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = tick_interval_sec
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)

	_emit_snapshot()


func _request_current_snapshot_when_connected() -> void:
	if _is_server_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_snapshot")):
		return
	call_deferred("_request_current_snapshot_from_authority")


func _on_connected_to_server_request_snapshot() -> void:
	_request_current_snapshot_from_authority()


func _request_current_snapshot_from_authority() -> void:
	if _is_server_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_snapshot")):
		return
	_request_current_snapshot.rpc_id(1)


func start_match() -> void:
	if not _is_server_instance():
		return
	_state = MatchState.RUNNING
	_time_left_sec = maxf(0.0, match_duration_sec)
	_record_sync_event("match", "etat RUNNING")
	_apply_dev_spawn_zone_portals()
	_emit_snapshot()


func reset_to_lobby() -> void:
	if not _is_server_instance():
		return
	_state = MatchState.RESETTING
	_emit_snapshot()
	_state = MatchState.LOBBY
	_time_left_sec = 0.0
	for peer_id in _lives_by_peer.keys():
		_lives_by_peer[peer_id] = initial_lives_per_player
	for peer_id in _deaths_by_peer.keys():
		_deaths_by_peer[peer_id] = 0
	for peer_id in _score_by_peer.keys():
		_score_by_peer[peer_id] = 0
	_team_progress["relays_activated"] = 0
	_team_progress["bees_killed"] = 0
	_team_progress["players_alive"] = _connected_peers.size()
	_team_progress["chest_wood_delivered"] = 0
	_team_progress["chest_apples_delivered"] = 0
	_team_progress["required_wood"] = portal_unlock_base_wood
	_team_progress["required_apples"] = portal_unlock_base_apples
	_team_progress["required_bomb_doors"] = 0
	_team_progress["bomb_door_opened"] = 0
	_team_progress["portal_breche_unlocked"] = 0
	_team_progress["portal_reactor_unlocked"] = 0
	_team_progress["mission_phase"] = 1
	_portal_breche_unlocked = false
	_portal_reactor_unlocked = false
	_emit_snapshot()


func report_team_won(reason: String = "objective_complete") -> void:
	if not _is_server_instance():
		return
	if _state != MatchState.RUNNING:
		return
	_state = MatchState.WON
	DebugLog.gameplay("[MatchDirector] state=WON reason=%s" % reason)
	_record_sync_event("match", "etat WON (%s)" % reason)
	_emit_snapshot()


func report_team_lost(reason: String = "team_eliminated") -> void:
	if not _is_server_instance():
		return
	if _state != MatchState.RUNNING:
		return
	_state = MatchState.LOST
	DebugLog.gameplay("[MatchDirector] state=LOST reason=%s" % reason)
	_record_sync_event("match", "etat LOST (%s)" % reason)
	_emit_snapshot()


func add_score_for_peer(peer_id: int, delta: int = 1) -> void:
	if not _is_server_instance():
		return
	if not _score_by_peer.has(peer_id):
		_score_by_peer[peer_id] = 0
	_score_by_peer[peer_id] = int(_score_by_peer[peer_id]) + delta
	_emit_snapshot()


func register_player_spawn(peer_id: int, initial_lives: int = -1) -> void:
	if not _is_server_instance():
		return
	_connected_peers[peer_id] = true
	if not _score_by_peer.has(peer_id):
		_score_by_peer[peer_id] = 0
	if not _deaths_by_peer.has(peer_id):
		_deaths_by_peer[peer_id] = 0
	var spawn_lives: int = initial_lives_per_player if initial_lives < 0 else initial_lives
	if not _lives_by_peer.has(peer_id):
		_lives_by_peer[peer_id] = max(0, spawn_lives)
	_team_progress["players_alive"] = _count_alive_players()

	# Start automatically once enough players are present in lobby.
	if auto_start_match and _state == MatchState.LOBBY and _connected_peers.size() >= min_players_to_start:
		start_match()
		return
	_emit_snapshot()


func register_peer(peer_id: int) -> void:
	# Backward-compatible alias kept for existing callers/tests.
	register_player_spawn(peer_id)


func unregister_player(peer_id: int) -> void:
	if not _is_server_instance():
		return
	_connected_peers.erase(peer_id)
	_score_by_peer.erase(peer_id)
	_lives_by_peer.erase(peer_id)
	_deaths_by_peer.erase(peer_id)
	_team_progress["players_alive"] = _count_alive_players()

	# A running match with no players is considered lost/aborted.
	if _state == MatchState.RUNNING and _connected_peers.is_empty():
		report_team_lost("no_players_connected")
		return
	_emit_snapshot()


func unregister_peer(peer_id: int) -> void:
	unregister_player(peer_id)


func report_player_fell(peer_id: int) -> int:
	# Centralized life/death accounting for fall-related eliminations.
	if not _is_server_instance():
		return -1
	if not _lives_by_peer.has(peer_id):
		register_player_spawn(peer_id)
	var current_lives: int = int(_lives_by_peer.get(peer_id, initial_lives_per_player))
	if current_lives <= 0:
		return 0
	return set_player_lives(peer_id, current_lives - 1, "fell")


func request_respawn(peer_id: int) -> bool:
	# MatchDirector decides whether a respawn is currently allowed.
	if not _is_server_instance():
		return false
	var lives: int = int(_lives_by_peer.get(peer_id, 0))
	if lives <= 0:
		return false
	if is_instance_valid(player_spawner) and player_spawner.has_method("respawn_player"):
		player_spawner.respawn_player(peer_id)
	respawn_requested.emit(peer_id)
	return true


func report_enemy_killed(enemy_type: String, killer_id: int = -1) -> void:
	if not _is_server_instance():
		return
	if enemy_type == "bee_bot":
		_team_progress["bees_killed"] = int(_team_progress.get("bees_killed", 0)) + 1
	if killer_id > 0:
		add_score_for_peer(killer_id, 1)
		return
	_emit_snapshot()


func report_objective_progress(objective_id: String, delta: int = 1) -> void:
	if not _is_server_instance():
		return
	if not _team_progress.has(objective_id):
		_team_progress[objective_id] = 0
	_team_progress[objective_id] = int(_team_progress[objective_id]) + delta
	_record_sync_event("match", "objectif %s=%d" % [objective_id, int(_team_progress[objective_id])])
	_emit_snapshot()


func set_player_lives(peer_id: int, lives: int, _reason: String = "") -> int:
	# Single entrypoint for all life changes to keep counters coherent.
	if not _is_server_instance():
		return -1
	if not _connected_peers.has(peer_id):
		_connected_peers[peer_id] = true
	var clamped_lives: int = max(0, lives)
	var previous := int(_lives_by_peer.get(peer_id, clamped_lives))
	_lives_by_peer[peer_id] = clamped_lives
	if clamped_lives < previous:
		_deaths_by_peer[peer_id] = int(_deaths_by_peer.get(peer_id, 0)) + (previous - clamped_lives)
	_team_progress["players_alive"] = _count_alive_players()
	if clamped_lives == 0 and _state == MatchState.RUNNING and int(_team_progress.get("players_alive", 0)) == 0:
		report_team_lost("all_players_dead")
	else:
		_emit_snapshot()
	return clamped_lives


func update_lives_from_authority(peer_id: int, lives: int) -> void:
	# Backward-compatible alias for existing callers.
	set_player_lives(peer_id, lives, "external_sync")


func get_lives(peer_id: int) -> int:
	return int(_lives_by_peer.get(peer_id, initial_lives_per_player))


func get_state_name() -> String:
	return _state_to_string(_state)


func get_time_left_sec() -> float:
	return _time_left_sec


func get_snapshot_text() -> String:
	if not _is_server_instance():
		return _remote_snapshot_text

	var state_name := _state_to_string(_state)
	var lines: PackedStringArray = []
	lines.append("MATCH")
	lines.append("state: %s" % state_name)
	lines.append("time_left: %.1fs" % _time_left_sec)
	lines.append("players: %d" % _connected_peers.size())
	lines.append("score:")

	var ids := PackedInt32Array(_score_by_peer.keys())
	ids.sort()
	for id in ids:
		lines.append("peer_%d: %d" % [id, int(_score_by_peer[id])])
	lines.append("lives:")
	for id in ids:
		lines.append("peer_%d: %d" % [id, int(_lives_by_peer.get(id, initial_lives_per_player))])
	lines.append("deaths:")
	for id in ids:
		lines.append("peer_%d: %d" % [id, int(_deaths_by_peer.get(id, 0))])
	lines.append("objectives:")
	var objective_ids := PackedStringArray(_team_progress.keys())
	objective_ids.sort()
	for objective_id in objective_ids:
		lines.append("%s: %d" % [objective_id, int(_team_progress[objective_id])])

	return "\n".join(lines)


func _on_player_spawned(peer_id: int, _player: Node) -> void:
	register_player_spawn(peer_id)


func _on_player_despawned(peer_id: int) -> void:
	unregister_player(peer_id)


func _on_tick() -> void:
	if not _is_server_instance():
		return
	if _state != MatchState.RUNNING:
		return

	_time_left_sec = maxf(0.0, _time_left_sec - tick_interval_sec)
	if _time_left_sec <= 0.0:
		# Minimal cooperative objective for now: survive until timer reaches zero.
		report_team_won("timer_completed")
		return
	_update_zone_progression()
	_emit_snapshot()


func _emit_snapshot() -> void:
	var snapshot_text := get_snapshot_text()
	_snapshot_revision += 1
	snapshot_changed.emit(snapshot_text)
	state_changed.emit(_state_to_string(_state))
	if _is_server_instance():
		_receive_snapshot.rpc(snapshot_text)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_server_instance():
		return
	call_deferred("_push_current_snapshot_to_peer", peer_id)


func _push_current_snapshot_to_peer(peer_id: int) -> void:
	if not _is_server_instance():
		return
	_receive_snapshot.rpc_id(peer_id, get_snapshot_text())


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(snapshot_text: String) -> void:
	# Clients receive a single authoritative text snapshot for all match UI.
	_remote_snapshot_text = snapshot_text
	snapshot_changed.emit(snapshot_text)


@rpc("any_peer", "call_remote", "reliable")
func _request_current_snapshot() -> void:
	if not _is_server_instance():
		return
	_receive_snapshot.rpc_id(multiplayer.get_remote_sender_id(), get_snapshot_text())


func _state_to_string(value: int) -> String:
	match value:
		MatchState.LOBBY:
			return "LOBBY"
		MatchState.RUNNING:
			return "RUNNING"
		MatchState.WON:
			return "WON"
		MatchState.LOST:
			return "LOST"
		MatchState.RESETTING:
			return "RESETTING"
		_:
			return "UNKNOWN"


func _is_server_instance() -> bool:
	return force_server_mode or multiplayer.is_server()


func _count_alive_players() -> int:
	var alive := 0
	for peer_id in _connected_peers.keys():
		if int(_lives_by_peer.get(peer_id, initial_lives_per_player)) > 0:
			alive += 1
	return alive


func _update_zone_progression() -> void:
	if not _is_server_instance():
		return
	# Authoritative mission progression contract:
	# 1) compute delivered resources from hub chest,
	# 2) unlock portals from those durable conditions,
	# 3) publish coarse mission_phase for client HUD/readability.
	var chest_inventory: Variant = _find_hub_chest_inventory()
	var delivered_wood: int = 0
	var delivered_apples: int = 0
	if chest_inventory != null:
		delivered_wood = maxi(0, int(chest_inventory.call("count_item", "wood")) - hub_chest_seed_wood)
		delivered_apples = maxi(0, int(chest_inventory.call("count_item", "apple")) - hub_chest_seed_apples)
	var participant_count: int = maxi(1, _connected_peers.size())
	var required_wood: int = portal_unlock_base_wood + (portal_unlock_wood_step_per_extra_player * maxi(0, participant_count - 1))
	var required_apples: int = portal_unlock_base_apples + (portal_unlock_apples_step_per_extra_player * maxi(0, participant_count - 1))
	_team_progress["required_wood"] = required_wood
	_team_progress["required_apples"] = required_apples
	_team_progress["chest_wood_delivered"] = delivered_wood
	_team_progress["chest_apples_delivered"] = delivered_apples
	var total_bomb_doors: int = _count_total_cube_bomb_doors()
	var opened_bomb_doors: int = _count_open_cube_bomb_doors()
	_team_progress["required_bomb_doors"] = total_bomb_doors
	_team_progress["bomb_door_opened"] = opened_bomb_doors
	var should_unlock_breche: bool = delivered_wood >= required_wood and delivered_apples >= required_apples
	var should_unlock_reactor: bool = should_unlock_breche and _are_all_cube_bomb_doors_open()
	if should_unlock_breche != _portal_breche_unlocked:
		_portal_breche_unlocked = should_unlock_breche
		_record_sync_event("match", "portal breche=%s" % ("on" if should_unlock_breche else "off"))
	_set_portal_group_active("mission_portal_hub_breche", should_unlock_breche)
	_team_progress["portal_breche_unlocked"] = 1 if _portal_breche_unlocked else 0
	if should_unlock_reactor != _portal_reactor_unlocked:
		_portal_reactor_unlocked = should_unlock_reactor
		_record_sync_event("match", "portal reactor=%s" % ("on" if should_unlock_reactor else "off"))
	_set_portal_group_active("mission_portal_hub_reactor", should_unlock_reactor)
	_team_progress["portal_reactor_unlocked"] = 1 if _portal_reactor_unlocked else 0
	# Mission HUD only depends on this phase value, not on local client inference.
	var mission_phase := 1
	if _portal_breche_unlocked:
		mission_phase = 2
	if _portal_reactor_unlocked:
		mission_phase = 3
	if int(_team_progress.get("cube_activator_reached", 0)) > 0 or _state == MatchState.WON:
		mission_phase = 4
	_team_progress["mission_phase"] = mission_phase


func _find_hub_chest_inventory():
	var chest := get_tree().get_first_node_in_group("mission_hub_chests")
	if not is_instance_valid(chest) or not chest.has_method("get_inventory_component"):
		return null
	return chest.call("get_inventory_component")


func _are_all_cube_bomb_doors_open() -> bool:
	var doors := get_tree().get_nodes_in_group("mission_cube_bomb_doors")
	if doors.is_empty():
		return false
	for door in doors:
		if not is_instance_valid(door) or not door.has_method("is_open") or not bool(door.call("is_open")):
			return false
	return true


func _count_total_cube_bomb_doors() -> int:
	return get_tree().get_nodes_in_group("mission_cube_bomb_doors").size()


func _count_open_cube_bomb_doors() -> int:
	var opened := 0
	for door in get_tree().get_nodes_in_group("mission_cube_bomb_doors"):
		if not is_instance_valid(door) or not door.has_method("is_open"):
			continue
		if bool(door.call("is_open")):
			opened += 1
	return opened


func _set_portal_group_active(group_name: String, active: bool) -> void:
	for portal in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(portal) or not portal.has_method("set_portal_active"):
			continue
		portal.call("set_portal_active", active)


## Déverrouille immédiatement les portails nécessaires si DEV_SPAWN_ZONE est définie.
## N'a aucun effet en dehors du serveur ou si la variable n'est pas renseignée.
func _apply_dev_spawn_zone_portals() -> void:
	if not _is_server_instance():
		return
	var dev_zone := OS.get_environment("DEV_SPAWN_ZONE").strip_edges().to_lower()
	if dev_zone.is_empty() or dev_zone == "hub":
		return
	DebugLog.gameplay("[DEV] DEV_SPAWN_ZONE=%s : déverrouillage des portails en mode test" % dev_zone)
	# La breche et le reactor nécessitent les deux portails en cascade
	var unlock_breche := dev_zone in ["breche", "reactor"]
	var unlock_reactor := dev_zone == "reactor"
	if unlock_breche:
		_portal_breche_unlocked = true
		_team_progress["portal_breche_unlocked"] = 1
		_team_progress["mission_phase"] = maxi(2, int(_team_progress.get("mission_phase", 1)))
		_set_portal_group_active("mission_portal_hub_breche", true)
	if unlock_reactor:
		_portal_reactor_unlocked = true
		_team_progress["portal_reactor_unlocked"] = 1
		_team_progress["mission_phase"] = maxi(3, int(_team_progress.get("mission_phase", 1)))
		_set_portal_group_active("mission_portal_hub_reactor", true)


func request_current_state_from_server() -> void:
	if _is_server_instance():
		return
	_request_current_snapshot_when_connected()


func push_current_state_to_peer(peer_id: int) -> void:
	_push_current_snapshot_to_peer(peer_id)


func get_state_revision() -> int:
	return _snapshot_revision


func get_debug_sync_summary() -> String:
	return "match etat=%s rev=%d joueurs=%d" % [_state_to_string(_state), _snapshot_revision, _connected_peers.size()]


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)
