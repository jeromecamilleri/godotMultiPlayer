extends Node
class_name UiTestScenarioServerPilot

const GROUP_MISSION_CUBE_BEETLE_DIRECTORS := "mission_cube_beetle_directors"
const GROUP_MISSION_CUBE_BOMB_DOORS := "mission_cube_bomb_doors"
const GROUP_MISSION_HUB_CHESTS := "mission_hub_chests"
const GROUP_MISSION_ZONE_SCIERIE := "mission_zone_scierie"
const GROUP_MISSION_ZONE_VERGER := "mission_zone_verger"
const GROUP_MISSION_WOOD_PICKUPS := "mission_wood_pickups"
const GROUP_MISSION_APPLE_PICKUPS := "mission_apple_pickups"
const GROUP_PORTAL_HUB_SCIERIE := "mission_portal_hub_scierie"
const GROUP_PORTAL_HUB_VERGER := "mission_portal_hub_verger"
const GROUP_PORTAL_HUB_BRECHE := "mission_portal_hub_breche"
const GROUP_PORTAL_HUB_REACTOR := "mission_portal_hub_reactor"
const BEETLE_TARGETING_CLIENT_OFFSETS: Array[Vector3] = [
	Vector3(-3.0, 0.0, 2.2),
	Vector3(3.0, 0.0, 2.2),
	Vector3(0.0, 0.0, -2.2),
]
const BEETLE_DOOR_CHARGE_OPERATOR_OFFSET := Vector3(0.0, 0.0, -2.4)
const BEETLE_DOOR_CHARGE_OBSERVER_OFFSET := Vector3(-6.0, 0.0, -5.0)

@export var match_director_path: NodePath = NodePath("../MatchDirector")
@export var reactor_activator_path: NodePath = NodePath("../ZoneReactor/Interactives/Activator/CubeActivator")

var _scenario_name := ""
var _instance_role := ""
var _beetle_targeting_state := ""
var _beetle_targeting_started_ms := 0
var _beetle_targeting_pending_positions_by_peer: Dictionary = {}
var _beetle_targeting_pending_ack_peer_ids: Array[int] = []
var _beetle_targeting_server_result_written := false
var _beetle_targeting_state_push_retries_remaining := 0
var _beetle_targeting_last_state_push_ms := 0
var _client_beetle_targeting_setup_pending := false
var _client_beetle_targeting_position := Vector3.ZERO
var _client_beetle_targeting_look_at := Vector3.ZERO
var _beetle_door_charge_state := ""
var _beetle_door_charge_started_ms := 0
var _beetle_door_charge_pending_positions_by_peer: Dictionary = {}
var _beetle_door_charge_pending_look_at_by_peer: Dictionary = {}
var _beetle_door_charge_pending_ack_peer_ids: Array[int] = []
var _beetle_door_charge_server_result_written := false
var _beetle_door_charge_state_push_retries_remaining := 0
var _beetle_door_charge_last_state_push_ms := 0
var _client_beetle_door_charge_setup_pending := false
var _client_beetle_door_charge_position := Vector3.ZERO
var _client_beetle_door_charge_look_at := Vector3.ZERO
var _portal_unlock_state := ""
var _portal_unlock_started_ms := 0
var _portal_unlock_pending_positions_by_peer: Dictionary = {}
var _portal_unlock_pending_look_at_by_peer: Dictionary = {}
var _portal_unlock_pending_ack_peer_ids: Array[int] = []
var _client_portal_unlock_setup_pending := false
var _client_portal_unlock_position := Vector3.ZERO
var _client_portal_unlock_look_at := Vector3.ZERO
var _registered_roles_by_peer_id: Dictionary = {}
var _local_role_registered := false
var _portal_progression := {
	"initialized": false,
	"breche_phase_written": false,
	"reactor_phase_written": false,
	"written": false,
	"initial_scierie_active": false,
	"initial_verger_active": false,
	"initial_breche_active": false,
	"initial_reactor_active": false,
}


func _ready() -> void:
	_scenario_name = OS.get_environment("UI_TEST_SCENARIO").strip_edges().to_lower()
	_instance_role = OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().to_lower()
	set_process(
		_scenario_name == "beetle_targeting"
		or _scenario_name == "beetle_door_charge"
		or _scenario_name == "portal_unlock"
		or (_scenario_name == "portal_progression" and multiplayer.is_server())
	)
	match _scenario_name:
		"beetle_targeting":
			if multiplayer.is_server():
				_beetle_targeting_state = "await_players"
				_beetle_targeting_started_ms = Time.get_ticks_msec()
				_record_sync_event("ui_test", "beetle_targeting pilote serveur pret")
			else:
				_record_sync_event("ui_test", "%s pilote client pret" % _scenario_name)
				_register_local_ui_test_role_if_needed()
		"beetle_door_charge":
			if multiplayer.is_server():
				_beetle_door_charge_state = "await_players"
				_beetle_door_charge_started_ms = Time.get_ticks_msec()
				_record_sync_event("ui_test", "beetle_door_charge pilote serveur pret")
			else:
				_record_sync_event("ui_test", "%s pilote client pret" % _scenario_name)
				_register_local_ui_test_role_if_needed()
		"portal_unlock":
			if multiplayer.is_server():
				_portal_unlock_state = "await_players"
				_portal_unlock_started_ms = Time.get_ticks_msec()
				_record_sync_event("ui_test", "portal_unlock pilote serveur pret")
			else:
				_record_sync_event("ui_test", "%s pilote client pret" % _scenario_name)
				_register_local_ui_test_role_if_needed()
		"portal_progression":
			if multiplayer.is_server():
				_record_sync_event("ui_test", "portal_progression pilote serveur pret")


func _process(_delta: float) -> void:
	match _scenario_name:
		"beetle_targeting":
			if multiplayer.is_server():
				_update_beetle_targeting_server()
			else:
				_register_local_ui_test_role_if_needed()
				_process_pending_client_beetle_targeting_setup()
		"beetle_door_charge":
			if multiplayer.is_server():
				_update_beetle_door_charge_server()
			else:
				_register_local_ui_test_role_if_needed()
				_process_pending_client_beetle_door_charge_setup()
		"portal_unlock":
			if multiplayer.is_server():
				_update_portal_unlock_server_setup()
			else:
				_register_local_ui_test_role_if_needed()
				_process_pending_client_portal_unlock_setup()
		"portal_progression":
			if multiplayer.is_server():
				_update_portal_progression_server()


func _update_beetle_targeting_server() -> void:
	match _beetle_targeting_state:
		"await_players":
			_try_prepare_beetle_targeting_server()
		"await_client_ack":
			_stabilize_beetle_targeting_positions_on_server()
			if _beetle_targeting_pending_ack_peer_ids.is_empty():
				_finalize_beetle_targeting_server_setup()
			elif Time.get_ticks_msec() - _beetle_targeting_started_ms > 2500:
				_record_sync_event("ui_test", "beetle_targeting timeout ack clients=%s" % str(_beetle_targeting_pending_ack_peer_ids))
				_finalize_beetle_targeting_server_setup()
		"running":
			_retry_beetle_targeting_state_push_if_needed()
			_write_beetle_targeting_server_result_if_ready()


func _update_beetle_door_charge_server() -> void:
	match _beetle_door_charge_state:
		"await_players":
			_try_prepare_beetle_door_charge_server()
		"await_client_ack":
			_stabilize_beetle_door_charge_positions_on_server()
			if _beetle_door_charge_pending_ack_peer_ids.is_empty():
				_finalize_beetle_door_charge_server_setup()
			elif Time.get_ticks_msec() - _beetle_door_charge_started_ms > 2500:
				_record_sync_event("ui_test", "beetle_door_charge timeout ack clients=%s" % str(_beetle_door_charge_pending_ack_peer_ids))
				_finalize_beetle_door_charge_server_setup()
		"running":
			_stabilize_beetle_door_charge_positions_on_server()
			_retry_beetle_door_charge_state_push_if_needed()
			_write_beetle_door_charge_server_result_if_ready()


func _update_portal_unlock_server_setup() -> void:
	match _portal_unlock_state:
		"await_players":
			_try_prepare_portal_unlock_server()
		"await_client_ack":
			_stabilize_portal_unlock_positions_on_server()
			if _portal_unlock_pending_ack_peer_ids.is_empty():
				_finalize_portal_unlock_server_setup()
			elif Time.get_ticks_msec() - _portal_unlock_started_ms > 2500:
				_record_sync_event("ui_test", "portal_unlock timeout ack clients=%s" % str(_portal_unlock_pending_ack_peer_ids))
				_finalize_portal_unlock_server_setup()
		"running":
			_stabilize_portal_unlock_positions_on_server()


func _try_prepare_beetle_targeting_server() -> void:
	var activator: Node3D = _get_reactor_activator()
	var beetle_director: Node = _get_reactor_beetle_director()
	if activator == null or beetle_director == null:
		return
	var players: Array[Node3D] = _get_players_by_ui_test_roles(["client_1", "client_2", "client_3"])
	if players.size() < 3:
		players = _get_active_players_sorted()
	if players.size() < 3:
		return
	_start_match_if_needed()
	var slot_positions: Array[Vector3] = _build_beetle_targeting_slots(activator.global_position, players.size())
	_beetle_targeting_pending_positions_by_peer.clear()
	_beetle_targeting_pending_ack_peer_ids.clear()
	for index in range(mini(players.size(), slot_positions.size())):
		var player: Node3D = players[index]
		var peer_id: int = player.get_multiplayer_authority()
		var slot_position: Vector3 = slot_positions[index]
		_beetle_targeting_pending_positions_by_peer[peer_id] = slot_position
		_place_player_for_beetle_targeting(player, slot_position, activator.global_position)
		_beetle_targeting_pending_ack_peer_ids.append(peer_id)
		_rpc_prepare_beetle_targeting_player.rpc_id(peer_id, slot_position, activator.global_position)
	_beetle_targeting_started_ms = Time.get_ticks_msec()
	_beetle_targeting_state = "await_client_ack"
	_record_sync_event("ui_test", "beetle_targeting joueurs prepares=%s" % str(_beetle_targeting_pending_ack_peer_ids))


func _finalize_beetle_targeting_server_setup() -> void:
	var activator: Node3D = _get_reactor_activator()
	var beetle_director: Node = _get_reactor_beetle_director()
	if activator == null or beetle_director == null:
		return
	_stabilize_beetle_targeting_positions_on_server()
	if beetle_director.has_method("_refresh_beetle_population"):
		beetle_director.call("_refresh_beetle_population")
	for peer_id in multiplayer.get_peers():
		if beetle_director.has_method("push_current_state_to_peer"):
			beetle_director.call("push_current_state_to_peer", peer_id)
	_beetle_targeting_state_push_retries_remaining = 4
	_beetle_targeting_last_state_push_ms = Time.get_ticks_msec()
	_beetle_targeting_state = "running"
	_beetle_targeting_started_ms = Time.get_ticks_msec()
	_record_sync_event("ui_test", "beetle_targeting directeur active")
	_write_beetle_targeting_server_result_if_ready()


func _try_prepare_beetle_door_charge_server() -> void:
	var activator: Node3D = _get_reactor_activator()
	var beetle_director: Node = _get_reactor_beetle_director()
	var bomb_doors: Array[Node3D] = _get_cube_mission_bomb_doors()
	if activator == null or beetle_director == null or bomb_doors.is_empty():
		return
	var players: Array[Node3D] = _get_players_by_ui_test_roles(["client_1", "client_2"])
	if players.size() < 2:
		players = _get_active_players_sorted()
	if players.size() < 2:
		return
	_start_match_if_needed()
	var door_anchor: Vector3 = _get_cube_mission_door_anchor(bomb_doors)
	_beetle_door_charge_pending_positions_by_peer.clear()
	_beetle_door_charge_pending_look_at_by_peer.clear()
	_beetle_door_charge_pending_ack_peer_ids.clear()
	for player in players:
		var peer_id: int = player.get_multiplayer_authority()
		var slot_position := activator.global_position + BEETLE_DOOR_CHARGE_OBSERVER_OFFSET
		var look_at_position := activator.global_position
		var role_name: String = String(_registered_roles_by_peer_id.get(peer_id, ""))
		if role_name == "client_1":
			slot_position = door_anchor + BEETLE_DOOR_CHARGE_OPERATOR_OFFSET
			look_at_position = door_anchor
		slot_position.y = player.global_position.y
		_beetle_door_charge_pending_positions_by_peer[peer_id] = slot_position
		_beetle_door_charge_pending_look_at_by_peer[peer_id] = look_at_position
		_place_player_for_beetle_targeting(player, slot_position, look_at_position)
		_beetle_door_charge_pending_ack_peer_ids.append(peer_id)
		_rpc_prepare_beetle_door_charge_player.rpc_id(peer_id, slot_position, look_at_position)
	_beetle_door_charge_started_ms = Time.get_ticks_msec()
	_beetle_door_charge_state = "await_client_ack"
	_record_sync_event("ui_test", "beetle_door_charge joueurs prepares=%s" % str(_beetle_door_charge_pending_ack_peer_ids))


func _finalize_beetle_door_charge_server_setup() -> void:
	var beetle_director: Node = _get_reactor_beetle_director()
	if beetle_director == null:
		return
	_stabilize_beetle_door_charge_positions_on_server()
	if beetle_director.has_method("_refresh_beetle_population"):
		beetle_director.call("_refresh_beetle_population")
	for peer_id in multiplayer.get_peers():
		if beetle_director.has_method("push_current_state_to_peer"):
			beetle_director.call("push_current_state_to_peer", peer_id)
	_beetle_door_charge_state_push_retries_remaining = 4
	_beetle_door_charge_last_state_push_ms = Time.get_ticks_msec()
	_beetle_door_charge_state = "running"
	_beetle_door_charge_started_ms = Time.get_ticks_msec()
	_record_sync_event("ui_test", "beetle_door_charge directeur active")
	_write_beetle_door_charge_server_result_if_ready()


func _try_prepare_portal_unlock_server() -> void:
	var chest := get_tree().get_first_node_in_group(GROUP_MISSION_HUB_CHESTS)
	var scierie_zone := get_tree().get_first_node_in_group(GROUP_MISSION_ZONE_SCIERIE)
	var verger_zone := get_tree().get_first_node_in_group(GROUP_MISSION_ZONE_VERGER)
	if not is_instance_valid(chest) or not is_instance_valid(scierie_zone) or not is_instance_valid(verger_zone):
		return
	var wood := _find_first_available_pickup_in_group_near_position(GROUP_MISSION_WOOD_PICKUPS, (scierie_zone as Node3D).global_position)
	var apple := _find_first_available_pickup_in_group_near_position(GROUP_MISSION_APPLE_PICKUPS, (verger_zone as Node3D).global_position)
	if wood == null or apple == null:
		return
	var players: Array[Node3D] = _get_players_by_ui_test_roles(["client_a", "client_b"])
	if players.size() < 2:
		players = _get_active_players_sorted()
	if players.size() < 2:
		return
	_start_match_if_needed()
	_portal_unlock_pending_positions_by_peer.clear()
	_portal_unlock_pending_look_at_by_peer.clear()
	_portal_unlock_pending_ack_peer_ids.clear()
	for player in players:
		var peer_id: int = player.get_multiplayer_authority()
		var role_name: String = String(_registered_roles_by_peer_id.get(peer_id, ""))
		var slot_position: Vector3 = (wood as Node3D).global_position + Vector3(0.6, 0.0, 2.0)
		var look_at_position: Vector3 = (wood as Node3D).global_position
		if role_name == "client_b":
			slot_position = (apple as Node3D).global_position + Vector3(0.6, 0.0, 2.0)
			look_at_position = (apple as Node3D).global_position
		slot_position.y = player.global_position.y
		_portal_unlock_pending_positions_by_peer[peer_id] = slot_position
		_portal_unlock_pending_look_at_by_peer[peer_id] = look_at_position
		_place_player_for_beetle_targeting(player, slot_position, look_at_position)
		_portal_unlock_pending_ack_peer_ids.append(peer_id)
		_rpc_prepare_portal_unlock_player.rpc_id(peer_id, slot_position, look_at_position)
	_portal_unlock_started_ms = Time.get_ticks_msec()
	_portal_unlock_state = "await_client_ack"
	_record_sync_event("ui_test", "portal_unlock joueurs prepares=%s" % str(_portal_unlock_pending_ack_peer_ids))


func _finalize_portal_unlock_server_setup() -> void:
	_stabilize_portal_unlock_positions_on_server()
	_portal_unlock_state = "running"
	_portal_unlock_started_ms = Time.get_ticks_msec()
	_record_sync_event("ui_test", "portal_unlock setup actif")


func _stabilize_beetle_targeting_positions_on_server() -> void:
	var activator: Node3D = _get_reactor_activator()
	if activator == null:
		return
	for player in _get_active_players_sorted():
		var peer_id: int = player.get_multiplayer_authority()
		if not _beetle_targeting_pending_positions_by_peer.has(peer_id):
			continue
		var slot_position: Vector3 = _beetle_targeting_pending_positions_by_peer[peer_id]
		_place_player_for_beetle_targeting(player, slot_position, activator.global_position)


func _stabilize_beetle_door_charge_positions_on_server() -> void:
	for player in _get_active_players_sorted():
		var peer_id: int = player.get_multiplayer_authority()
		if not _beetle_door_charge_pending_positions_by_peer.has(peer_id):
			continue
		var slot_position: Vector3 = _beetle_door_charge_pending_positions_by_peer[peer_id]
		var look_at_position: Vector3 = _beetle_door_charge_pending_look_at_by_peer.get(peer_id, slot_position)
		_place_player_for_beetle_targeting(player, slot_position, look_at_position)


func _stabilize_portal_unlock_positions_on_server() -> void:
	for player in _get_active_players_sorted():
		var peer_id: int = player.get_multiplayer_authority()
		if not _portal_unlock_pending_positions_by_peer.has(peer_id):
			continue
		var slot_position: Vector3 = _portal_unlock_pending_positions_by_peer[peer_id]
		var look_at_position: Vector3 = _portal_unlock_pending_look_at_by_peer.get(peer_id, slot_position)
		_place_player_for_beetle_targeting(player, slot_position, look_at_position)


func _place_player_for_beetle_targeting(player: Node3D, slot_position: Vector3, look_at_position: Vector3) -> void:
	player.global_position = slot_position
	player.set("velocity", Vector3.ZERO)
	if player.has_method("look_at"):
		var look_target := look_at_position
		look_target.y = player.global_position.y
		player.look_at(look_target, Vector3.UP, true)


func _process_pending_client_beetle_targeting_setup() -> void:
	if not _client_beetle_targeting_setup_pending:
		return
	var local_player := _find_local_authority_player()
	if local_player == null:
		return
	_place_player_for_beetle_targeting(local_player, _client_beetle_targeting_position, _client_beetle_targeting_look_at)
	_request_beetle_director_state_from_server()
	_client_beetle_targeting_setup_pending = false
	_rpc_ack_beetle_targeting_prepared.rpc_id(1, local_player.get_multiplayer_authority())


func _process_pending_client_beetle_door_charge_setup() -> void:
	if not _client_beetle_door_charge_setup_pending:
		return
	var local_player := _find_local_authority_player()
	if local_player == null:
		return
	_place_player_for_beetle_targeting(local_player, _client_beetle_door_charge_position, _client_beetle_door_charge_look_at)
	_request_beetle_director_state_from_server()
	_client_beetle_door_charge_setup_pending = false
	_rpc_ack_beetle_door_charge_prepared.rpc_id(1, local_player.get_multiplayer_authority())


func _process_pending_client_portal_unlock_setup() -> void:
	if not _client_portal_unlock_setup_pending:
		return
	var local_player := _find_local_authority_player()
	if local_player == null:
		return
	_place_player_for_beetle_targeting(local_player, _client_portal_unlock_position, _client_portal_unlock_look_at)
	_client_portal_unlock_setup_pending = false
	_rpc_ack_portal_unlock_prepared.rpc_id(1, local_player.get_multiplayer_authority())


func _write_beetle_targeting_server_result_if_ready() -> void:
	if _beetle_targeting_server_result_written:
		return
	var activator: Node3D = _get_reactor_activator()
	var beetle_director: Node = _get_reactor_beetle_director()
	if activator == null or beetle_director == null:
		return
	var beetles: Array[Node3D] = _find_beetles_near_position(activator.global_position, 18.0)
	if beetles.size() < 3 and Time.get_ticks_msec() - _beetle_targeting_started_ms < 4000:
		return
	var result := {
		"state": _beetle_targeting_state,
		"participant_count": multiplayer.get_peers().size() + 1,
		"player_count": _get_active_players_sorted().size(),
		"beetle_count": beetles.size(),
	}
	_write_sync_result("beetle_targeting_server.json", result)
	_beetle_targeting_server_result_written = true


func _write_beetle_door_charge_server_result_if_ready() -> void:
	if _beetle_door_charge_server_result_written:
		return
	var activator: Node3D = _get_reactor_activator()
	var beetle_director: Node = _get_reactor_beetle_director()
	var bomb_doors: Array[Node3D] = _get_cube_mission_bomb_doors()
	if activator == null or beetle_director == null or bomb_doors.is_empty():
		return
	var beetles: Array[Node3D] = _find_beetles_near_position(activator.global_position, 18.0)
	var expected_beetle_count := 0
	if beetle_director.has_method("_get_desired_beetle_count"):
		expected_beetle_count = int(beetle_director.call("_get_desired_beetle_count"))
	if beetles.size() < expected_beetle_count and Time.get_ticks_msec() - _beetle_door_charge_started_ms < 5000:
		return
	if not _are_cube_mission_doors_open(bomb_doors) and Time.get_ticks_msec() - _beetle_door_charge_started_ms < 15000:
		return
	var result := {
		"state": _beetle_door_charge_state,
		"participant_count": multiplayer.get_peers().size() + 1,
		"player_count": _get_active_players_sorted().size(),
		"beetle_count": beetles.size(),
		"door_open": _are_cube_mission_doors_open(bomb_doors),
	}
	_write_sync_result("beetle_door_charge_server.json", result)
	_beetle_door_charge_server_result_written = true


func _get_match_director() -> Node:
	return get_node_or_null(match_director_path)


func _get_reactor_activator() -> Node3D:
	var node := get_node_or_null(reactor_activator_path)
	if node is Node3D:
		return node as Node3D
	return null


func _get_reactor_beetle_director() -> Node:
	return get_tree().get_first_node_in_group(GROUP_MISSION_CUBE_BEETLE_DIRECTORS)


func _get_active_players_sorted() -> Array[Node3D]:
	var players: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is Node3D):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		players.append(node as Node3D)
	players.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.get_multiplayer_authority() < b.get_multiplayer_authority()
	)
	return players


func _get_players_by_ui_test_roles(expected_roles: Array[String]) -> Array[Node3D]:
	var players_by_peer_id: Dictionary = {}
	for player in _get_active_players_sorted():
		players_by_peer_id[player.get_multiplayer_authority()] = player
	var ordered_players: Array[Node3D] = []
	for role_name in expected_roles:
		var peer_id := -1
		for candidate_peer_id in _registered_roles_by_peer_id.keys():
			if String(_registered_roles_by_peer_id[candidate_peer_id]) == role_name:
				peer_id = int(candidate_peer_id)
				break
		if peer_id <= 0 or not players_by_peer_id.has(peer_id):
			return []
		ordered_players.append(players_by_peer_id[peer_id] as Node3D)
	return ordered_players


func _find_local_authority_player() -> Node3D:
	var local_peer_id: int = multiplayer.get_unique_id()
	for player in _get_active_players_sorted():
		if player.get_multiplayer_authority() == local_peer_id:
			return player
	return null


func _build_beetle_targeting_slots(center: Vector3, player_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for index in range(mini(player_count, BEETLE_TARGETING_CLIENT_OFFSETS.size())):
		positions.append(center + BEETLE_TARGETING_CLIENT_OFFSETS[index])
	return positions


func _find_beetles_near_position(center: Vector3, radius: float) -> Array[Node3D]:
	var beetles: Array[Node3D] = []
	var max_distance_sq: float = radius * radius
	for node in get_tree().get_nodes_in_group("beetles"):
		if not (node is Node3D):
			continue
		var beetle := node as Node3D
		if beetle.global_position.distance_squared_to(center) > max_distance_sq:
			continue
		if not beetle.visible:
			continue
		beetles.append(beetle)
	return beetles


func _find_first_available_pickup_in_group_near_position(group_name: String, center: Vector3) -> Node3D:
	var best_pickup: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(group_name):
		if not (node is Node3D):
			continue
		if node.has_method("can_be_picked_up") and not bool(node.call("can_be_picked_up")):
			continue
		var candidate := node as Node3D
		var distance: float = center.distance_to(candidate.global_position)
		if distance < best_distance:
			best_pickup = candidate
			best_distance = distance
	return best_pickup


func _get_cube_mission_bomb_doors() -> Array[Node3D]:
	var bomb_doors: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(GROUP_MISSION_CUBE_BOMB_DOORS):
		if node is Node3D:
			bomb_doors.append(node as Node3D)
	bomb_doors.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return String(a.get_path()) < String(b.get_path())
	)
	return bomb_doors


func _get_cube_mission_door_anchor(bomb_doors: Array[Node3D]) -> Vector3:
	var anchor := Vector3.ZERO
	for door in bomb_doors:
		anchor += door.global_position
	if bomb_doors.is_empty():
		return anchor
	return anchor / float(bomb_doors.size())


func _are_cube_mission_doors_open(bomb_doors: Array[Node3D]) -> bool:
	for bomb_door in bomb_doors:
		if bomb_door == null:
			continue
		if bomb_door.has_method("is_open") and not bool(bomb_door.call("is_open")):
			return false
	return not bomb_doors.is_empty()


func _start_match_if_needed() -> void:
	var director := _get_match_director()
	if director == null:
		return
	if not director.has_method("get_state_name") or not director.has_method("start_match"):
		return
	if String(director.call("get_state_name")) == "LOBBY" and multiplayer.get_peers().size() > 0:
		director.call("start_match")


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)


func _retry_beetle_targeting_state_push_if_needed() -> void:
	if _beetle_targeting_state_push_retries_remaining <= 0:
		return
	if Time.get_ticks_msec() - _beetle_targeting_last_state_push_ms < 900:
		return
	var beetle_director: Node = _get_reactor_beetle_director()
	if beetle_director == null or not beetle_director.has_method("push_current_state_to_peer"):
		return
	for peer_id in multiplayer.get_peers():
		beetle_director.call("push_current_state_to_peer", peer_id)
	_beetle_targeting_state_push_retries_remaining -= 1
	_beetle_targeting_last_state_push_ms = Time.get_ticks_msec()
	_record_sync_event("ui_test", "beetle_targeting repush etat restant=%d" % _beetle_targeting_state_push_retries_remaining)


func _retry_beetle_door_charge_state_push_if_needed() -> void:
	if _beetle_door_charge_state_push_retries_remaining <= 0:
		return
	if Time.get_ticks_msec() - _beetle_door_charge_last_state_push_ms < 900:
		return
	var beetle_director: Node = _get_reactor_beetle_director()
	if beetle_director == null or not beetle_director.has_method("push_current_state_to_peer"):
		return
	for peer_id in multiplayer.get_peers():
		beetle_director.call("push_current_state_to_peer", peer_id)
	_beetle_door_charge_state_push_retries_remaining -= 1
	_beetle_door_charge_last_state_push_ms = Time.get_ticks_msec()
	_record_sync_event("ui_test", "beetle_door_charge repush etat restant=%d" % _beetle_door_charge_state_push_retries_remaining)


func _request_beetle_director_state_from_server() -> void:
	var beetle_director: Node = _get_reactor_beetle_director()
	if beetle_director != null and beetle_director.has_method("request_current_state_from_server"):
		beetle_director.call("request_current_state_from_server")


func _update_portal_progression_server() -> void:
	var chest := get_tree().get_first_node_in_group(GROUP_MISSION_HUB_CHESTS)
	var hub_scierie := get_tree().get_first_node_in_group(GROUP_PORTAL_HUB_SCIERIE)
	var hub_verger := get_tree().get_first_node_in_group(GROUP_PORTAL_HUB_VERGER)
	var hub_breche := get_tree().get_first_node_in_group(GROUP_PORTAL_HUB_BRECHE)
	var hub_reactor := get_tree().get_first_node_in_group(GROUP_PORTAL_HUB_REACTOR)
	if not is_instance_valid(chest) or not is_instance_valid(hub_scierie) or not is_instance_valid(hub_verger) or not is_instance_valid(hub_breche) or not is_instance_valid(hub_reactor):
		return
	if not bool(_portal_progression["initialized"]):
		_portal_progression["initialized"] = true
		_portal_progression["initial_scierie_active"] = _portal_is_active(hub_scierie)
		_portal_progression["initial_verger_active"] = _portal_is_active(hub_verger)
		_portal_progression["initial_breche_active"] = _portal_is_active(hub_breche)
		_portal_progression["initial_reactor_active"] = _portal_is_active(hub_reactor)
	_start_match_if_needed()
	if _portal_is_active(hub_breche) and not bool(_portal_progression["breche_phase_written"]):
		_write_sync_result("portal_progression_phase_breche.json", _build_portal_progression_phase_result(chest, hub_breche, hub_reactor, "breche_unlocked"))
		_portal_progression["breche_phase_written"] = true
	if _portal_is_active(hub_reactor) and not bool(_portal_progression["reactor_phase_written"]):
		_write_sync_result("portal_progression_phase_reactor.json", _build_portal_progression_phase_result(chest, hub_breche, hub_reactor, "reactor_unlocked"))
		_portal_progression["reactor_phase_written"] = true
	if not _portal_is_active(hub_breche) or not _portal_is_active(hub_reactor) or bool(_portal_progression["written"]):
		return
	var inventory: Variant = chest.call("get_inventory_component")
	_write_sync_result("portal_progression_server.json", {
		"role": "server",
		"initial_scierie_active": bool(_portal_progression["initial_scierie_active"]),
		"initial_verger_active": bool(_portal_progression["initial_verger_active"]),
		"initial_breche_active": bool(_portal_progression["initial_breche_active"]),
		"initial_reactor_active": bool(_portal_progression["initial_reactor_active"]),
		"breche_unlocked": _portal_is_active(hub_breche),
		"reactor_unlocked": _portal_is_active(hub_reactor),
		"chest_wood": int(inventory.call("count_item", "wood")),
		"chest_apple": int(inventory.call("count_item", "apple")),
	})
	_portal_progression["written"] = true


func _build_portal_progression_phase_result(chest: Node, hub_breche: Node, hub_reactor: Node, phase_name: String) -> Dictionary:
	var inventory: Variant = chest.call("get_inventory_component")
	return {
		"role": "server",
		"phase": phase_name,
		"breche_active": _portal_is_active(hub_breche),
		"reactor_active": _portal_is_active(hub_reactor),
		"chest_wood": int(inventory.call("count_item", "wood")),
		"chest_apple": int(inventory.call("count_item", "apple")),
	}


func _portal_is_active(portal: Node) -> bool:
	return is_instance_valid(portal) and portal.has_method("is_portal_active") and bool(portal.call("is_portal_active"))


func _register_local_ui_test_role_if_needed() -> void:
	if _local_role_registered or _instance_role.is_empty() or _instance_role == "server":
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_register_local_ui_test_role_if_needed")):
		return
	_rpc_register_ui_test_role.rpc_id(1, _instance_role)
	_local_role_registered = true


func _write_sync_result(file_name: String, result: Dictionary) -> void:
	var dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if dir.is_empty():
		return
	var file := FileAccess.open("%s/%s" % [dir, file_name], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(result))
	file.close()


@rpc("authority", "call_remote", "reliable")
func _rpc_prepare_beetle_targeting_player(slot_position: Vector3, look_at_position: Vector3) -> void:
	_client_beetle_targeting_setup_pending = true
	_client_beetle_targeting_position = slot_position
	_client_beetle_targeting_look_at = look_at_position
	_process_pending_client_beetle_targeting_setup()


@rpc("authority", "call_remote", "reliable")
func _rpc_prepare_beetle_door_charge_player(slot_position: Vector3, look_at_position: Vector3) -> void:
	_client_beetle_door_charge_setup_pending = true
	_client_beetle_door_charge_position = slot_position
	_client_beetle_door_charge_look_at = look_at_position
	_process_pending_client_beetle_door_charge_setup()


@rpc("authority", "call_remote", "reliable")
func _rpc_prepare_portal_unlock_player(slot_position: Vector3, look_at_position: Vector3) -> void:
	_client_portal_unlock_setup_pending = true
	_client_portal_unlock_position = slot_position
	_client_portal_unlock_look_at = look_at_position
	_process_pending_client_portal_unlock_setup()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_ui_test_role(role_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0 or role_name.is_empty():
		return
	_registered_roles_by_peer_id[sender_id] = role_name
	_record_sync_event("ui_test", "role enregistree J%d=%s" % [sender_id, role_name])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_beetle_targeting_prepared(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_beetle_targeting_pending_ack_peer_ids.erase(peer_id)
	_record_sync_event("ui_test", "beetle_targeting ack J%d" % peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_beetle_door_charge_prepared(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_beetle_door_charge_pending_ack_peer_ids.erase(peer_id)
	_record_sync_event("ui_test", "beetle_door_charge ack J%d" % peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ack_portal_unlock_prepared(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_portal_unlock_pending_ack_peer_ids.erase(peer_id)
	_record_sync_event("ui_test", "portal_unlock ack J%d" % peer_id)
