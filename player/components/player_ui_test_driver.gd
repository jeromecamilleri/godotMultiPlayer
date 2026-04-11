extends RefCounted
class_name PlayerUiTestDriver

const GROUP_MISSION_HUB_CHESTS := "mission_hub_chests"
const GROUP_MISSION_ZONE_SCIERIE := "mission_zone_scierie"
const GROUP_MISSION_ZONE_VERGER := "mission_zone_verger"
const GROUP_MISSION_CUBE_BOMB_DOORS := "mission_cube_bomb_doors"
const GROUP_MISSION_CUBE_GOAL_ZONES := "mission_cube_goal_zones"
const GROUP_MISSION_CUBE_PRIMARY := "mission_cube_primary"
const GROUP_MISSION_CUBE_BEETLE_DIRECTORS := "mission_cube_beetle_directors"
const GROUP_MISSION_CUBE_BLOCKERS := "mission_cube_blockers"
const GROUP_PORTAL_HUB_BRECHE := "mission_portal_hub_breche"
const GROUP_PORTAL_HUB_REACTOR := "mission_portal_hub_reactor"
const GROUP_PORTAL_HUB_SCIERIE := "mission_portal_hub_scierie"
const GROUP_PORTAL_HUB_VERGER := "mission_portal_hub_verger"
const GROUP_PORTAL_SCIERIE_HUB := "mission_portal_scierie_hub"
const GROUP_PORTAL_VERGER_HUB := "mission_portal_verger_hub"
const GROUP_PORTAL_BRECHE_HUB := "mission_portal_breche_hub"
const GROUP_PORTAL_REACTOR_HUB := "mission_portal_reactor_hub"
const GROUP_MISSION_WOOD_PICKUPS := "mission_wood_pickups"
const GROUP_MISSION_APPLE_PICKUPS := "mission_apple_pickups"
const BEETLE_DOOR_CHARGE_OBSERVER_OFFSET := Vector3(-6.0, 0.0, -5.0)

var _scenario_name := ""
var _instance_role := ""
var _setup_done := false
var _transfer := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
}
var _late_join := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"written": false,
}
var _cube_mission := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"pull_started": false,
	"last_pull_start_ms": 0,
	"last_debug_write_ms": 0,
	"written": false,
	"anchor_offset": Vector3.ZERO,
	"win_requested": false,
	"lock_enabled": false,
	"locked_intent": Vector3.ZERO,
	"crate_index": 0,
	"crate_waiting": false,
	"crate_phase_started": 0,
}
var _proximity := {
	"state": "",
	"written": false,
	"near": {
		"has_target": false,
		"target_name": "",
		"distance": 0.0,
	},
	"far": {
		"has_target": false,
		"target_name": "",
		"distance": 0.0,
	},
}
var _replication_stress := {
	"state": "",
	"started_ms": 0,
	"events": {},
	"written": false,
	"initial_chest_wood": -1,
	"initial_chest_apple": -1,
	"did_pickup": false,
	"did_transfer": false,
	"requested_chest_snapshot": false,
}
var _beetle_targeting := {
	"state": "",
	"started_ms": 0,
	"written": false,
}
var _beetle_door_charge := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"written": false,
	"bomb_requested": false,
	"initial_distance": -1.0,
	"final_distance": -1.0,
	"closest_distance_seen": -1.0,
	"targeting_observed": false,
	"tracked_beetle_name": "",
	"target_peer_id": -1,
}
var _portal_unlock := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"written": false,
	"wood_stage": 0,
	"apple_done": false,
}
var _portal_logistics := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"written": false,
}
var _portal_progression := {
	"state": "",
	"started_ms": 0,
	"phase_started_ms": 0,
	"written": false,
	"wood_stage": 0,
	"bomb_requested": false,
	"initial_scierie_active": false,
	"initial_verger_active": false,
	"initial_breche_active": false,
	"initial_reactor_active": false,
	"breche_unlocked_observed": false,
	"reactor_unlocked_observed": false,
	"breche_phase_written": false,
	"reactor_phase_written": false,
}


func setup() -> void:
	_scenario_name = _read_scenario_name()
	_instance_role = OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().to_lower()


func is_enabled() -> bool:
	return not _scenario_name.is_empty()


func begin(player) -> void:
	match _scenario_name:
		"chest":
			_setup_chest_scenario(player)
		"transfer":
			_setup_transfer_scenario(player)
		"late_join_bomb_wood":
			_setup_late_join_bomb_wood_scenario(player)
		"cube_mission":
			_setup_cube_mission_scenario(player)
		"cube_mission_lock":
			_setup_cube_mission_scenario(player)
		"inventory_proximity":
			_setup_inventory_proximity_scenario(player)
		"replication_stress":
			_setup_replication_stress_scenario(player)
		"beetle_targeting":
			_setup_beetle_targeting_scenario(player)
		"beetle_door_charge":
			_setup_beetle_door_charge_scenario(player)
		"portal_unlock":
			_setup_portal_unlock_scenario(player)
		"portal_logistics":
			_setup_portal_logistics_scenario(player)
		"portal_progression":
			_setup_portal_progression_scenario(player)


func process(player) -> void:
	match _scenario_name:
		"transfer":
			_update_transfer_scenario(player)
		"late_join_bomb_wood":
			_update_late_join_bomb_wood_scenario(player)
		"cube_mission":
			_update_cube_mission_scenario(player)
		"cube_mission_lock":
			_update_cube_mission_scenario(player)
		"inventory_proximity":
			_update_inventory_proximity_scenario(player)
		"replication_stress":
			_update_replication_stress_scenario(player)
		"beetle_targeting":
			_update_beetle_targeting_scenario(player)
		"beetle_door_charge":
			_update_beetle_door_charge_scenario(player)
		"portal_unlock":
			_update_portal_unlock_scenario(player)
		"portal_logistics":
			_update_portal_logistics_scenario(player)
		"portal_progression":
			_update_portal_progression_scenario(player)


func _read_scenario_name() -> String:
	var scenario := OS.get_environment("UI_TEST_SCENARIO").strip_edges().to_lower()
	if not scenario.is_empty():
		return scenario
	var chest_flag := OS.get_environment("UI_TEST_CHEST_SCENARIO").strip_edges().to_lower()
	if chest_flag == "1" or chest_flag == "true" or chest_flag == "yes":
		return "chest"
	return ""


func _setup_chest_scenario(player) -> void:
	if _setup_done or not player.is_multiplayer_authority():
		return
	var chest: Node3D = await _await_chest(player)
	if chest == null:
		return
	_setup_done = true
	player.velocity = Vector3.ZERO
	player.global_position = chest.global_position + Vector3(0.6, 0.0, 2.2)
	_look_at_node(player, chest)
	player.set_focused_inventory_target(chest)
	player.set_inventory_mode_open(true)
	await player.get_tree().process_frame
	_refresh_chest_focus(player)


func _refresh_chest_focus(player) -> void:
	if _scenario_name != "chest":
		return
	var chest := _find_chest(player)
	if chest == null:
		return
	player.set_focused_inventory_target(chest)
	player.set_inventory_mode_open(true)


func _setup_transfer_scenario(player) -> void:
	if _setup_done or not player.is_multiplayer_authority():
		return
	var resolved := await _await_chest_and_item(player, "ApplePickup")
	var chest: Node3D = resolved.get("chest")
	var apple: Node3D = resolved.get("item")
	if chest == null or apple == null:
		return
	_setup_done = true
	player.velocity = Vector3.ZERO
	match _instance_role:
		"client_a":
			player.global_position = apple.global_position + Vector3(0.2, 0.0, 2.4)
			_look_at_node(player, apple)
			_transfer["state"] = "await_pickup"
			_transfer["started_ms"] = Time.get_ticks_msec()
		"client_b":
			player.global_position = chest.global_position + Vector3(-0.8, 0.0, 2.3)
			_look_at_node(player, chest)
			player.set_focused_inventory_target(chest)
			player.set_inventory_mode_open(true)
			_transfer["state"] = "watch_chest"
		_:
			_transfer["state"] = "idle"


func _update_transfer_scenario(player) -> void:
	var chest := _find_chest(player)
	var apple := _find_world_item(player, "ApplePickup")
	if chest == null:
		return
	match _instance_role:
		"client_a":
			if _transfer["state"] == "await_pickup" and apple != null and apple.call("can_be_picked_up"):
				if Time.get_ticks_msec() - int(_transfer["started_ms"]) > 800:
					player.request_pickup_world_item(apple.get_path())
					_transfer["state"] = "pickup_requested"
			if _transfer["state"] == "await_pickup" and player.inventory.count_item("apple") > 0:
				_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.3))
				_transfer["state"] = "ready_to_give"
			if _transfer["state"] == "pickup_requested" and player.inventory.count_item("apple") > 0:
				_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.3))
				_transfer["state"] = "ready_to_give"
				_transfer["phase_started_ms"] = Time.get_ticks_msec()
			if _transfer["state"] == "ready_to_give" and Time.get_ticks_msec() - int(_transfer["phase_started_ms"]) > 1200:
				player.request_transfer_to_target(0, 1)
				_transfer["state"] = "give_requested"
		"client_b":
			if _transfer["state"] == "watch_chest" and chest.get_inventory_component().count_item("apple") > 2:
				_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.3))
				_transfer["state"] = "ready_for_chest"


func _setup_inventory_proximity_scenario(player) -> void:
	if String(_proximity["state"]) != "" or not player.is_multiplayer_authority():
		return
	_proximity["state"] = "await_other_player"
	_proximity["written"] = false
	_proximity["near"] = {
		"has_target": false,
		"target_name": "",
		"distance": 0.0,
	}
	_proximity["far"] = {
		"has_target": false,
		"target_name": "",
		"distance": 0.0,
	}


func _update_inventory_proximity_scenario(player) -> void:
	if _instance_role != "client_a":
		return
	var other = _find_other_player(player)
	if other == null:
		return
	var chest := _find_chest(player)
	if chest == null:
		return
	match String(_proximity["state"]):
		"await_other_player":
			player.global_position = other.global_position + Vector3(0.7, 0.0, 0.2)
			player.velocity = Vector3.ZERO
			_look_at_node(player, other)
			player.set_inventory_mode_open(true)
			player.set_focused_inventory_target(other)
			_proximity["state"] = "near_checked"
		"near_checked":
			_store_proximity_snapshot(player, other, "near")
			player.global_position = other.global_position + Vector3(0.0, 0.0, 80.0)
			player.velocity = Vector3.ZERO
			_look_at_node(player, other)
			player.set_inventory_mode_open(true)
			player._interactions.refresh_inventory_focus(player)
			_proximity["state"] = "far_checked"
		"far_checked":
			_store_proximity_snapshot(player, other, "far")
			player.global_position = chest.global_position + Vector3(0.8, 0.0, 2.3)
			player.velocity = Vector3.ZERO
			_look_at_node(player, chest)
			player.set_focused_inventory_target(chest)
			player.set_inventory_mode_open(true)
			player._interactions.refresh_inventory_focus(player)
			_proximity["state"] = "chest_checked"
		"chest_checked":
			if bool(_proximity["written"]):
				return
			var near: Dictionary = _proximity["near"]
			var far: Dictionary = _proximity["far"]
			_write_proximity_result({
				"near_has_target": near["has_target"],
				"near_target_name": near["target_name"],
				"near_distance": near["distance"],
				"far_has_target": far["has_target"],
				"far_target_name": far["target_name"],
				"far_distance": far["distance"],
				"chest_has_target": player.has_focused_inventory_target(),
				"chest_target_name": player.get_target_inventory_display_name(),
			})


func _setup_replication_stress_scenario(player) -> void:
	if String(_replication_stress["state"]) != "" or not player.is_multiplayer_authority():
		return
	var resolved := await _await_replication_stress_nodes(player)
	var bomb_door: Node3D = resolved.get("bomb_door")
	var chest: Node3D = resolved.get("chest")
	var wood: Node3D = resolved.get("wood")
	var apple: Node3D = resolved.get("apple")
	if bomb_door == null or chest == null or wood == null or apple == null:
		return
	var role_index := _get_instance_role_index()
	_replication_stress["started_ms"] = Time.get_ticks_msec()
	_replication_stress["events"] = {}
	_replication_stress["written"] = false
	_replication_stress["did_pickup"] = false
	_replication_stress["did_transfer"] = false
	_replication_stress["requested_chest_snapshot"] = false
	var chest_inventory = chest.get_inventory_component()
	_replication_stress["initial_chest_wood"] = chest_inventory.count_item("wood")
	_replication_stress["initial_chest_apple"] = chest_inventory.count_item("apple")
	var connection := _find_connection(player)
	if connection != null and connection.has_method("reset_network_metrics"):
		connection.call("reset_network_metrics")
	player.velocity = Vector3.ZERO
	match _instance_role:
		"server":
			_replication_stress["state"] = "monitor"
		"client_1":
			player.global_position = bomb_door.global_position + Vector3(-2.0, 0.0, 0.8)
			_look_at_node(player, bomb_door)
			_replication_stress["state"] = "bomb"
		"client_2":
			player.global_position = wood.global_position + Vector3(0.4, 0.0, 2.0)
			_look_at_node(player, wood)
			_replication_stress["state"] = "pickup_wood"
		"client_3":
			player.global_position = apple.global_position + Vector3(0.4, 0.0, 2.0)
			_look_at_node(player, apple)
			_replication_stress["state"] = "pickup_apple"
		_:
			var ring_angle := float(maxi(0, role_index - 4)) * 0.55
			var observe_offset := Vector3(cos(ring_angle) * 2.3, 0.0, 2.1 + sin(ring_angle) * 1.4)
			player.global_position = chest.global_position + observe_offset
			_look_at_node(player, chest)
			_replication_stress["state"] = "observe"
	player.set_focused_inventory_target(chest)
	player.set_inventory_mode_open(true)
	if chest.has_method("request_chest_snapshot"):
		chest.request_chest_snapshot.rpc_id(1)
		_replication_stress["requested_chest_snapshot"] = true


func _update_replication_stress_scenario(player) -> void:
	var bomb_door := _find_bomb_door(player)
	var chest := _find_chest(player)
	var wood := _find_world_item(player, "WoodPickup")
	var apple := _find_world_item(player, "ApplePickup")
	if bomb_door == null or chest == null:
		return
	var chest_inventory = chest.get_inventory_component()
	var initial_wood := int(_replication_stress["initial_chest_wood"])
	var initial_apple := int(_replication_stress["initial_chest_apple"])
	var observed_events: Dictionary = _replication_stress["events"]
	if bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")):
		_record_replication_stress_event("door_open_seen")
	if wood != null and wood.has_method("can_be_picked_up") and not bool(wood.call("can_be_picked_up")):
		_record_replication_stress_event("wood_hidden_seen")
	if apple != null and apple.has_method("can_be_picked_up") and not bool(apple.call("can_be_picked_up")):
		_record_replication_stress_event("apple_hidden_seen")
	if chest_inventory.count_item("wood") > initial_wood:
		_record_replication_stress_event("chest_wood_seen")
	if chest_inventory.count_item("apple") > initial_apple:
		_record_replication_stress_event("chest_apple_seen")
	match String(_replication_stress["state"]):
		"bomb":
			if Time.get_ticks_msec() - int(_replication_stress["started_ms"]) > 900:
				player.place_bomb()
				_replication_stress["state"] = "observe"
		"pickup_wood":
			if observed_events.has("door_open_seen"):
				if wood != null and wood.has_method("can_be_picked_up") and bool(wood.call("can_be_picked_up")) and not bool(_replication_stress["did_pickup"]):
					player.global_position = wood.global_position + Vector3(0.25, 0.0, 1.8)
					player.velocity = Vector3.ZERO
					_look_at_node(player, wood)
					player.request_pickup_world_item(wood.get_path())
					_replication_stress["did_pickup"] = true
				if player.inventory.count_item("wood") > 0 and not bool(_replication_stress["did_transfer"]):
					_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.1))
					player.request_transfer_to_target(0, 1)
					_replication_stress["did_transfer"] = true
					_replication_stress["state"] = "observe"
		"pickup_apple":
			if Time.get_ticks_msec() - int(_replication_stress["started_ms"]) > 1200:
				if apple != null and apple.has_method("can_be_picked_up") and bool(apple.call("can_be_picked_up")) and not bool(_replication_stress["did_pickup"]):
					player.global_position = apple.global_position + Vector3(0.25, 0.0, 1.8)
					player.velocity = Vector3.ZERO
					_look_at_node(player, apple)
					player.request_pickup_world_item(apple.get_path())
					_replication_stress["did_pickup"] = true
				if player.inventory.count_item("apple") > 0 and not bool(_replication_stress["did_transfer"]):
					_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.1))
					player.request_transfer_to_target(0, 1)
					_replication_stress["did_transfer"] = true
					_replication_stress["state"] = "observe"
		"observe":
			if not bool(_replication_stress["requested_chest_snapshot"]) and chest.has_method("request_chest_snapshot"):
				chest.request_chest_snapshot.rpc_id(1)
				_replication_stress["requested_chest_snapshot"] = true
	if String(_instance_role).begins_with("client_"):
		if observed_events.has("door_open_seen") and observed_events.has("chest_wood_seen") and observed_events.has("chest_apple_seen"):
			_write_replication_stress_result(player, bomb_door, chest, wood, apple)
			_replication_stress["state"] = "done"
	elif _instance_role == "server":
		if bool(bomb_door.call("is_open")) and chest_inventory.count_item("wood") > initial_wood and chest_inventory.count_item("apple") > initial_apple:
			_write_replication_stress_result(player, bomb_door, chest, wood, apple)
			_replication_stress["state"] = "done"


func _record_replication_stress_event(event_name: String) -> void:
	var events: Dictionary = _replication_stress["events"]
	if events.has(event_name):
		return
	events[event_name] = Time.get_ticks_msec() - int(_replication_stress["started_ms"])
	_replication_stress["events"] = events


func _write_replication_stress_result(player, bomb_door: Node3D, chest: Node3D, wood: Node3D, apple: Node3D) -> void:
	if bool(_replication_stress["written"]):
		return
	var connection := _find_connection(player)
	var chest_inventory = chest.get_inventory_component()
	var result := {
		"role": _instance_role,
		"events_ms": (_replication_stress["events"] as Dictionary).duplicate(true),
		"door_open": bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")),
		"wood_pickable": wood != null and wood.has_method("can_be_picked_up") and bool(wood.call("can_be_picked_up")),
		"apple_pickable": apple != null and apple.has_method("can_be_picked_up") and bool(apple.call("can_be_picked_up")),
		"chest_wood": chest_inventory.count_item("wood"),
		"chest_apple": chest_inventory.count_item("apple"),
		"door_replication_delay_ms": bomb_door.call("get_last_open_replication_delay_ms") if bomb_door.has_method("get_last_open_replication_delay_ms") else -1,
		"wood_replication_delay_ms": wood.call("get_last_collected_replication_delay_ms") if wood != null and wood.has_method("get_last_collected_replication_delay_ms") else -1,
		"apple_replication_delay_ms": apple.call("get_last_collected_replication_delay_ms") if apple != null and apple.has_method("get_last_collected_replication_delay_ms") else -1,
		"chest_replication_delay_ms": chest.call("get_last_snapshot_replication_delay_ms") if chest.has_method("get_last_snapshot_replication_delay_ms") else -1,
		"network_rtt_ms": connection.get_network_rtt_ms() if connection != null and connection.has_method("get_network_rtt_ms") else -1,
		"network_rtt_avg_ms": connection.get_network_rtt_average_ms() if connection != null and connection.has_method("get_network_rtt_average_ms") else -1.0,
		"network_jitter_ms": connection.get_network_jitter_ms() if connection != null and connection.has_method("get_network_jitter_ms") else -1.0,
	}
	_write_sync_result("replication_stress_%s.json" % _instance_role, result)
	_replication_stress["written"] = true


func _setup_beetle_targeting_scenario(player) -> void:
	if String(_beetle_targeting["state"]) != "" or not player.is_multiplayer_authority():
		return
	var beetle_director := _find_beetle_director(player)
	var activator := _find_cube_activator(player)
	if beetle_director == null or activator == null:
		return
	player.velocity = Vector3.ZERO
	_beetle_targeting["state"] = "observe"
	_beetle_targeting["started_ms"] = Time.get_ticks_msec()
	_beetle_targeting["written"] = false


func _setup_beetle_door_charge_scenario(player) -> void:
	if String(_beetle_door_charge["state"]) != "" or not player.is_multiplayer_authority():
		return
	var beetle_director := _find_beetle_director(player)
	var bomb_doors: Array[Node3D] = _find_cube_mission_bomb_doors(player)
	if beetle_director == null or bomb_doors.is_empty():
		return
	player.velocity = Vector3.ZERO
	match _instance_role:
		"server":
			_beetle_door_charge["state"] = "monitor"
		"client_1":
			_beetle_door_charge["state"] = "open_door"
		"client_2":
			_beetle_door_charge["target_peer_id"] = player.get_multiplayer_authority()
			_beetle_door_charge["state"] = "wait_door_open"
		_:
			_beetle_door_charge["state"] = "idle"
	_beetle_door_charge["started_ms"] = Time.get_ticks_msec()
	_beetle_door_charge["phase_started_ms"] = Time.get_ticks_msec()
	_beetle_door_charge["written"] = false
	_beetle_door_charge["bomb_requested"] = false
	_beetle_door_charge["initial_distance"] = -1.0
	_beetle_door_charge["final_distance"] = -1.0
	_beetle_door_charge["closest_distance_seen"] = -1.0
	_beetle_door_charge["targeting_observed"] = false
	_beetle_door_charge["tracked_beetle_name"] = ""


func _setup_portal_unlock_scenario(player) -> void:
	if String(_portal_unlock["state"]) != "" or not player.is_multiplayer_authority():
		return
	var chest := _find_chest(player)
	var breche_portal := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_BRECHE)
	var reactor_portal := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_REACTOR)
	var scierie_zone := _find_first_node3d_in_group(player, GROUP_MISSION_ZONE_SCIERIE)
	var verger_zone := _find_first_node3d_in_group(player, GROUP_MISSION_ZONE_VERGER)
	if chest == null or breche_portal == null or reactor_portal == null or scierie_zone == null or verger_zone == null:
		return
	player.velocity = Vector3.ZERO
	match _instance_role:
		"client_a":
			var wood := _find_first_available_pickup_in_group_near_position(player, GROUP_MISSION_WOOD_PICKUPS, scierie_zone.global_position)
			if wood == null:
				return
			_portal_unlock["state"] = "pickup_wood"
		"client_b":
			var apple := _find_first_available_pickup_in_group_near_position(player, GROUP_MISSION_APPLE_PICKUPS, verger_zone.global_position)
			if apple == null:
				return
			_portal_unlock["state"] = "pickup_apple"
		"server":
			player.global_position = chest.global_position + Vector3(-0.8, 0.0, 2.2)
			_look_at_node(player, chest)
			_portal_unlock["state"] = "monitor"
		_:
			_portal_unlock["state"] = "idle"
	_portal_unlock["started_ms"] = Time.get_ticks_msec()
	_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
	_portal_unlock["written"] = false
	_portal_unlock["wood_stage"] = 0
	_portal_unlock["apple_done"] = false


func _setup_portal_logistics_scenario(player) -> void:
	if String(_portal_logistics["state"]) != "" or not player.is_multiplayer_authority():
		return
	var chest := _find_chest(player)
	var hub_scierie := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_SCIERIE)
	var hub_verger := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_VERGER)
	var scierie_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_SCIERIE_HUB)
	var verger_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_VERGER_HUB)
	if chest == null or hub_scierie == null or hub_verger == null or scierie_hub == null or verger_hub == null:
		return
	player.velocity = Vector3.ZERO
	match _instance_role:
		"server":
			player.global_position = chest.global_position + Vector3(-0.8, 0.0, 2.2)
			_look_at_node(player, chest)
			_portal_logistics["state"] = "monitor"
		"client_a":
			player.global_position = hub_scierie.global_position + Vector3(-1.4, 0.0, 0.0)
			_look_at_node(player, hub_scierie)
			_portal_logistics["state"] = "travel_to_scierie"
		"client_b":
			player.global_position = hub_verger.global_position + Vector3(-1.4, 0.0, 0.0)
			_look_at_node(player, hub_verger)
			_portal_logistics["state"] = "travel_to_verger"
		_:
			_portal_logistics["state"] = "idle"
	_portal_logistics["started_ms"] = Time.get_ticks_msec()
	_portal_logistics["phase_started_ms"] = Time.get_ticks_msec()
	_portal_logistics["written"] = false


func _setup_portal_progression_scenario(player) -> void:
	if String(_portal_progression["state"]) != "" or not player.is_multiplayer_authority():
		return
	var chest := _find_chest(player)
	var hub_scierie := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_SCIERIE)
	var hub_verger := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_VERGER)
	var hub_breche := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_BRECHE)
	var hub_reactor := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_REACTOR)
	var scierie_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_SCIERIE_HUB)
	var verger_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_VERGER_HUB)
	var breche_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_BRECHE_HUB)
	var reactor_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_REACTOR_HUB)
	if chest == null or hub_scierie == null or hub_verger == null or hub_breche == null or hub_reactor == null or scierie_hub == null or verger_hub == null or breche_hub == null or reactor_hub == null:
		return
	_portal_progression["initial_scierie_active"] = _portal_is_active(hub_scierie)
	_portal_progression["initial_verger_active"] = _portal_is_active(hub_verger)
	_portal_progression["initial_breche_active"] = _portal_is_active(hub_breche)
	_portal_progression["initial_reactor_active"] = _portal_is_active(hub_reactor)
	_portal_progression["breche_unlocked_observed"] = bool(_portal_progression["initial_breche_active"])
	_portal_progression["reactor_unlocked_observed"] = bool(_portal_progression["initial_reactor_active"])
	_portal_progression["breche_phase_written"] = false
	_portal_progression["reactor_phase_written"] = false
	_portal_progression["wood_stage"] = 0
	_portal_progression["bomb_requested"] = false
	_portal_progression["written"] = false
	player.velocity = Vector3.ZERO
	match _instance_role:
		"server":
			player.global_position = chest.global_position + Vector3(-0.8, 0.0, 2.2)
			_look_at_node(player, chest)
			_portal_progression["state"] = "monitor"
		"client_a":
			player.global_position = hub_scierie.global_position + Vector3(-1.4, 0.0, 0.0)
			_look_at_node(player, hub_scierie)
			_portal_progression["state"] = "travel_to_scierie"
		"client_b":
			player.global_position = hub_verger.global_position + Vector3(-1.4, 0.0, 0.0)
			_look_at_node(player, hub_verger)
			_portal_progression["state"] = "travel_to_verger"
		_:
			_portal_progression["state"] = "idle"
	_portal_progression["started_ms"] = Time.get_ticks_msec()
	_portal_progression["phase_started_ms"] = Time.get_ticks_msec()


func _update_beetle_targeting_scenario(player) -> void:
	if bool(_beetle_targeting["written"]):
		return
	var director := _find_match_director(player)
	if director == null:
		return
	var elapsed_ms: int = Time.get_ticks_msec() - int(_beetle_targeting["started_ms"])
	if elapsed_ms < 2200:
		return
	var activator := _find_cube_activator(player)
	if activator == null:
		return
	var beetles: Array[Node3D] = _find_beetles_near_position(player, activator.global_position, 18.0)
	var players: Array[Node3D] = _find_active_players(player)
	var participant_count: int = player.multiplayer.get_peers().size() + 1
	if (participant_count < 4 or players.size() < 3 or beetles.size() < 3) and elapsed_ms < 9000:
		return
	var assigned_targets: Array[int] = []
	var current_targets: Array[int] = []
	var beetle_rows: Array[Dictionary] = []
	for beetle in beetles:
		var assigned_peer_id := -1
		var current_peer_id := -1
		if beetle.has_method("get_assigned_target_peer_id"):
			assigned_peer_id = int(beetle.call("get_assigned_target_peer_id"))
		if beetle.has_method("get_current_target_peer_id"):
			current_peer_id = int(beetle.call("get_current_target_peer_id"))
		if assigned_peer_id > 0 and not assigned_targets.has(assigned_peer_id):
			assigned_targets.append(assigned_peer_id)
		if current_peer_id > 0 and not current_targets.has(current_peer_id):
			current_targets.append(current_peer_id)
		beetle_rows.append({
			"name": beetle.name,
			"assigned_target_peer_id": assigned_peer_id,
			"current_target_peer_id": current_peer_id,
			"position": [beetle.global_position.x, beetle.global_position.y, beetle.global_position.z],
		})
	var player_peer_ids: Array[int] = []
	for observed_player in players:
		player_peer_ids.append(observed_player.get_multiplayer_authority())
	player_peer_ids.sort()
	var expected_unique_targets: int = mini(beetles.size(), players.size())
	if assigned_targets.size() < expected_unique_targets and elapsed_ms < 11000:
		return
	var result := {
		"role": _instance_role,
		"state": _director_state_name(director),
		"participant_count": participant_count,
		"player_count": players.size(),
		"player_peer_ids": player_peer_ids,
		"beetle_count": beetles.size(),
		"unique_assigned_target_count": assigned_targets.size(),
		"unique_current_target_count": current_targets.size(),
		"assigned_target_peer_ids": assigned_targets,
		"current_target_peer_ids": current_targets,
		"beetles": beetle_rows,
	}
	_write_sync_result("beetle_targeting_%s.json" % _instance_role, result)
	_beetle_targeting["written"] = true
	_beetle_targeting["state"] = "done"

func _update_beetle_door_charge_scenario(player) -> void:
	if bool(_beetle_door_charge["written"]):
		return
	var director := _find_match_director(player)
	var bomb_doors: Array[Node3D] = _find_cube_mission_bomb_doors(player)
	if director == null or bomb_doors.is_empty():
		return
	if _instance_role == "server":
		return
	match String(_beetle_door_charge["state"]):
		"open_door":
			_perform_beetle_door_charge_open_door(player, bomb_doors, director)
		"wait_door_open":
			if _are_cube_mission_doors_open(bomb_doors):
				_beetle_door_charge["state"] = "observe_charge"
				_beetle_door_charge["phase_started_ms"] = Time.get_ticks_msec()
				_beetle_door_charge["initial_distance"] = -1.0
				_beetle_door_charge["closest_distance_seen"] = -1.0
				_beetle_door_charge["tracked_beetle_name"] = ""
		"observe_charge":
			_perform_beetle_charge_observation(player, bomb_doors, director)


func _setup_cube_mission_scenario(player) -> void:
	if _setup_done or not player.is_multiplayer_authority():
		return
	var resolved := await _await_cube_activator_and_bomb_door(player)
	var cube: Node3D = resolved.get("cube")
	var activator: Node3D = resolved.get("activator")
	var bomb_door: Node3D = resolved.get("bomb_door")
	var crates: Array[Node3D] = _find_cube_mission_crates(player)
	if cube == null or activator == null or bomb_door == null:
		_write_sync_result("cube_mission_debug_%s.json" % _instance_role, {
			"event": "setup_missing_nodes",
			"role": _instance_role,
		})
		return
	_setup_done = true
	player.velocity = Vector3.ZERO
	match _instance_role:
		"server":
			_cube_mission["state"] = "monitor_win"
			_cube_mission["started_ms"] = Time.get_ticks_msec()
			_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		"client_a":
			_cube_mission["anchor_offset"] = Vector3(-1.2, 0.0, 0.0)
			_cube_mission["state"] = "destroy_crates"
			_cube_mission["started_ms"] = Time.get_ticks_msec()
			_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
			if not crates.is_empty():
				player.global_position = crates[0].global_position + Vector3(-1.8, 0.0, 1.8)
				_look_at_node(player, crates[0])
		"client_b":
			_cube_mission["anchor_offset"] = Vector3(1.2, 0.0, 0.0)
			_cube_mission["state"] = "wait_door_open"
			_cube_mission["started_ms"] = Time.get_ticks_msec()
			_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
			player.global_position = bomb_door.global_position + Vector3(-2.0, 0.0, 0.8)
			_look_at_node(player, bomb_door)
		_:
			_cube_mission["state"] = "idle"
	_write_sync_result("cube_mission_debug_%s.json" % _instance_role, {
		"event": "setup_done",
		"role": _instance_role,
		"state": _cube_mission["state"],
		"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
		"activator_position": [activator.global_position.x, activator.global_position.y, activator.global_position.z],
		"scenario": _scenario_name,
	})


func _update_cube_mission_scenario(player) -> void:
	var cube := _find_primary_pull_cube(player)
	var activator := _find_cube_activator(player)
	var bomb_doors: Array[Node3D] = _find_cube_mission_bomb_doors(player)
	if cube == null or activator == null or bomb_doors.is_empty():
		return
	var director := _find_match_director(player)
	if director == null:
		return
	var cube_elapsed_ms: int = Time.get_ticks_msec() - int(_cube_mission["started_ms"])
	if not _cube_mission_session_is_ready(player) and cube_elapsed_ms < 12000:
		_write_cube_mission_progress(player, cube, activator, director, "waiting_session_ready")
		return
	match String(_cube_mission["state"]):
		"monitor_win":
			if _director_state_name(director) == "LOBBY" and director.has_method("start_match") and cube_elapsed_ms > 800:
				director.call("start_match")
			if _director_state_name(director) == "WON":
				var cube_on_goal_visual := cube.global_position.distance_to(activator.global_position) <= 3.0
				_write_sync_result(
					"cube_mission_server.json",
					{
						"state": _director_state_name(director),
						"cube_goal": cube.has_method("is_goal_reached") and bool(cube.call("is_goal_reached")),
						"cube_on_goal_visual": cube_on_goal_visual,
						"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
					}
				)
				_cube_mission["state"] = "done"
		"open_door":
			_perform_cube_mission_open_door(player, bomb_doors, cube, activator, director)
		"destroy_crates":
			_perform_cube_mission_destroy_crates(player, cube, activator, director)
		"wait_door_open":
			_perform_cube_mission_wait_door(player, bomb_doors, cube, activator, director)
		"pull_cube":
			_perform_real_cube_pull(player, cube, activator, bomb_doors, director)
		"wait_win":
			if _director_state_name(director) == "WON":
				var cube_on_goal_visual_wait := cube.global_position.distance_to(activator.global_position) <= 3.0
				if not cube_on_goal_visual_wait:
					_write_cube_mission_progress(player, cube, activator, director, "waiting_goal_replication")
					return
				_write_sync_result(
					"cube_mission_%s.json" % _instance_role,
					{
						"state": _director_state_name(director),
						"cube_goal": cube.has_method("is_goal_reached") and bool(cube.call("is_goal_reached")),
						"cube_on_goal_visual": cube_on_goal_visual_wait,
						"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
					}
				)
				_cube_mission["written"] = true
				_cube_mission["state"] = "done"


func _setup_late_join_bomb_wood_scenario(player) -> void:
	if _setup_done or not player.is_multiplayer_authority():
		return
	var resolved := await _await_bomb_door_and_item(player, "WoodPickup")
	var bomb_door: Node3D = resolved.get("bomb_door")
	var wood: Node3D = resolved.get("item")
	if bomb_door == null or wood == null:
		return
	_setup_done = true
	player.velocity = Vector3.ZERO
	match _instance_role:
		"client_a":
			player.global_position = bomb_door.global_position + Vector3(-2.0, 0.0, 0.8)
			_look_at_node(player, bomb_door)
			_late_join["state"] = "open_door"
			_late_join["started_ms"] = Time.get_ticks_msec()
		"client_b":
			player.global_position = bomb_door.global_position + Vector3(-2.4, 0.0, 1.0)
			_look_at_node(player, bomb_door)
			_late_join["state"] = "observe_door"
			_late_join["started_ms"] = Time.get_ticks_msec()
		_:
			_late_join["state"] = "idle"


func _update_late_join_bomb_wood_scenario(player) -> void:
	var bomb_door := _find_bomb_door(player)
	var wood := _find_world_item(player, "WoodPickup")
	if bomb_door == null:
		return
	match _instance_role:
		"client_a":
			_update_late_join_client_a(player, bomb_door, wood)
		"client_b":
			_update_late_join_client_b(player, bomb_door, wood)


func _update_late_join_client_a(player, bomb_door: Node3D, wood: Node3D) -> void:
	match String(_late_join["state"]):
		"open_door":
			if Time.get_ticks_msec() - int(_late_join["started_ms"]) < 500:
				return
			player.place_bomb()
			_late_join["state"] = "wait_door_open"
			_late_join["phase_started_ms"] = Time.get_ticks_msec()
		"wait_door_open":
			if bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")):
				if wood != null:
					player.global_position = wood.global_position + Vector3(0.2, 0.0, 2.0)
					player.velocity = Vector3.ZERO
					_look_at_node(player, wood)
					player.request_pickup_world_item(wood.get_path())
				_late_join["state"] = "wait_wood_pickup"
				_late_join["phase_started_ms"] = Time.get_ticks_msec()
		"wait_wood_pickup":
			var wood_pickable := wood != null and wood.has_method("can_be_picked_up") and bool(wood.call("can_be_picked_up"))
			if player.inventory.count_item("wood") > 0 or not wood_pickable:
				_write_sync_result(
					"late_join_client_a.json",
					{
						"door_open": bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")),
						"wood_pickable": wood_pickable,
						"wood_visible": wood != null and wood.visible,
						"player_wood_count": player.inventory.count_item("wood"),
					}
				)
				_late_join["state"] = "done"


func _update_late_join_client_b(player, bomb_door: Node3D, wood: Node3D) -> void:
	match String(_late_join["state"]):
		"observe_door":
			if Time.get_ticks_msec() - int(_late_join["started_ms"]) < 1800:
				return
			if wood != null:
				player.global_position = wood.global_position + Vector3(0.3, 0.0, 2.0)
				player.velocity = Vector3.ZERO
				_look_at_node(player, wood)
			_late_join["state"] = "write_observation"
		"write_observation":
			if bool(_late_join["written"]):
				return
			var wood_pickable := wood != null and wood.has_method("can_be_picked_up") and bool(wood.call("can_be_picked_up"))
			_write_sync_result(
				"late_join_client_b.json",
				{
					"door_open": bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")),
					"wood_pickable": wood_pickable,
					"wood_visible": wood != null and wood.visible,
					"player_wood_count": player.inventory.count_item("wood"),
				}
			)
			_late_join["written"] = true
			_late_join["state"] = "done"


func _store_proximity_snapshot(player, other, key: String) -> void:
	_proximity[key] = {
		"has_target": player.has_focused_inventory_target(),
		"target_name": player.get_target_inventory_display_name(),
		"distance": (other.global_position - player.global_position).length(),
	}


func _write_proximity_result(result: Dictionary) -> void:
	if bool(_proximity["written"]):
		return
	var dir := _get_sync_dir()
	if dir.is_empty():
		return
	var role := _instance_role if not _instance_role.is_empty() else "unknown"
	var path := dir + "/inventory_proximity_" + role + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(result))
	file.close()
	_proximity["written"] = true


func _write_sync_result(file_name: String, result: Dictionary) -> void:
	var dir := _get_sync_dir()
	if dir.is_empty():
		return
	var path := dir + "/" + file_name
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(result))
	file.close()


func _get_sync_dir() -> String:
	var dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if not dir.is_empty():
		return dir
	return OS.get_environment("UI_TEST_CHEST_SYNC_DIR").strip_edges()


func _move_player_to_chest(player, chest: Node3D, offset: Vector3) -> void:
	player.global_position = chest.global_position + offset
	player.velocity = Vector3.ZERO
	_look_at_node(player, chest)
	player.set_focused_inventory_target(chest)
	player.set_inventory_mode_open(true)


func _look_at_node(player, node: Node3D) -> void:
	_look_at_position(player, node.global_position)


func _look_at_position(player, target: Vector3) -> void:
	var look_target := target
	look_target.y = player.global_position.y
	if player.global_position.distance_to(look_target) <= 0.05:
		return
	player.look_at(look_target, Vector3.UP, true)
	if is_instance_valid(player._camera_controller):
		var camera_target := target
		camera_target.y = player._camera_controller.global_position.y
		if player._camera_controller.global_position.distance_to(camera_target) <= 0.05:
			return
		player._camera_controller.look_at(camera_target, Vector3.UP, true)


func _await_chest(player) -> Node3D:
	for _attempt in range(24):
		var chest := _find_chest(player)
		if chest != null and chest.is_inside_tree():
			return chest
		await player.get_tree().process_frame
	return null


func _await_chest_and_item(player, node_name: String) -> Dictionary:
	for _attempt in range(24):
		var chest := _find_chest(player)
		var item := _find_world_item(player, node_name)
		if chest != null and item != null and chest.is_inside_tree() and item.is_inside_tree():
			return {"chest": chest, "item": item}
		await player.get_tree().process_frame
	return {}


func _find_other_player(player):
	for node in player.get_tree().get_nodes_in_group("players"):
		if node is Player and node != player:
			return node
	return null


func _find_chest(player) -> Node3D:
	return _find_first_node3d_in_group(player, GROUP_MISSION_HUB_CHESTS)

func _find_chest_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "Chest" and root.has_method("get_inventory_component"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_chest_in_subtree(child)
		if found != null:
			return found
	return null


func _find_bomb_door(player) -> Node3D:
	var bomb_doors: Array[Node3D] = _find_cube_mission_bomb_doors(player)
	if bomb_doors.is_empty():
		return null
	return bomb_doors[0]


func _find_bomb_door_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "BombDoor" and root.has_method("is_open"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_bomb_door_in_subtree(child)
		if found != null:
			return found
	return null


func _find_cube_mission_bomb_doors(player) -> Array[Node3D]:
	var doors: Array[Node3D] = _find_nodes3d_in_group(player, GROUP_MISSION_CUBE_BOMB_DOORS)
	doors.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.x < b.global_position.x
	)
	return doors


func _get_cube_mission_door_anchor(bomb_doors: Array[Node3D]) -> Vector3:
	if bomb_doors.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	for bomb_door in bomb_doors:
		center += bomb_door.global_position
	return center / float(bomb_doors.size())


func _are_cube_mission_doors_open(bomb_doors: Array[Node3D]) -> bool:
	if bomb_doors.is_empty():
		return false
	for bomb_door in bomb_doors:
		if not bomb_door.has_method("is_open") or not bool(bomb_door.call("is_open")):
			return false
	return true


func _first_closed_cube_mission_door(bomb_doors: Array[Node3D]) -> Node3D:
	for bomb_door in bomb_doors:
		if bomb_door.has_method("is_open") and not bool(bomb_door.call("is_open")):
			return bomb_door
	return null


func _find_cube_activator(player) -> Node3D:
	return _find_first_node3d_in_group(player, GROUP_MISSION_CUBE_GOAL_ZONES)


func _cube_mission_session_is_ready(player) -> bool:
	if _instance_role == "server":
		return player.multiplayer.get_peers().size() >= 2
	return Connection.is_peer_connected and _find_active_players(player).size() >= 2


func _find_primary_pull_cube(player) -> Node3D:
	return _find_first_node3d_in_group(player, GROUP_MISSION_CUBE_PRIMARY)


func _find_match_director(player) -> Node:
	return player.get_tree().get_first_node_in_group("match_director")


func _find_beetle_director(player) -> Node3D:
	return _find_first_node3d_in_group(player, GROUP_MISSION_CUBE_BEETLE_DIRECTORS)


func _find_beetles(player) -> Array[Node3D]:
	if player == null or player.get_tree() == null:
		return []
	var beetles: Array[Node3D] = []
	for candidate in player.get_tree().get_nodes_in_group("beetles"):
		if candidate is Node3D and candidate.visible:
			beetles.append(candidate as Node3D)
	beetles.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return String(a.name) < String(b.name)
	)
	return beetles


func _find_beetles_near_position(player, center: Vector3, radius: float) -> Array[Node3D]:
	var filtered: Array[Node3D] = []
	for beetle in _find_beetles(player):
		if beetle.global_position.distance_to(center) > radius:
			continue
		filtered.append(beetle)
	return filtered


func _find_beetle_by_name(player, beetle_name: String) -> Node3D:
	if beetle_name.is_empty():
		return null
	for beetle in _find_beetles(player):
		if beetle.name == beetle_name:
			return beetle
	return null


func _observe_targeting_beetle_for_player(player) -> Dictionary:
	var own_peer_id: int = player.get_multiplayer_authority()
	var closest_targeting_beetle: Node3D = null
	var closest_targeting_distance: float = INF
	var fallback_beetle: Node3D = null
	var fallback_distance: float = INF
	for beetle in _find_beetles(player):
		var distance: float = beetle.global_position.distance_to(player.global_position)
		if distance < fallback_distance:
			fallback_distance = distance
			fallback_beetle = beetle
		var assigned_peer_id := -1
		var current_peer_id := -1
		if beetle.has_method("get_assigned_target_peer_id"):
			assigned_peer_id = int(beetle.call("get_assigned_target_peer_id"))
		if beetle.has_method("get_current_target_peer_id"):
			current_peer_id = int(beetle.call("get_current_target_peer_id"))
		if assigned_peer_id != own_peer_id and current_peer_id != own_peer_id:
			continue
		if distance < closest_targeting_distance:
			closest_targeting_distance = distance
			closest_targeting_beetle = beetle
	if closest_targeting_beetle != null:
		return {
			"name": closest_targeting_beetle.name,
			"distance": closest_targeting_distance,
			"assigned_target_peer_id": int(closest_targeting_beetle.call("get_assigned_target_peer_id")) if closest_targeting_beetle.has_method("get_assigned_target_peer_id") else -1,
			"current_target_peer_id": int(closest_targeting_beetle.call("get_current_target_peer_id")) if closest_targeting_beetle.has_method("get_current_target_peer_id") else -1,
		}
	if fallback_beetle != null:
		return {
			"name": fallback_beetle.name,
			"distance": fallback_distance,
			"assigned_target_peer_id": int(fallback_beetle.call("get_assigned_target_peer_id")) if fallback_beetle.has_method("get_assigned_target_peer_id") else -1,
			"current_target_peer_id": int(fallback_beetle.call("get_current_target_peer_id")) if fallback_beetle.has_method("get_current_target_peer_id") else -1,
		}
	return {
		"name": "",
		"distance": -1.0,
		"assigned_target_peer_id": -1,
		"current_target_peer_id": -1,
	}


func _find_active_players(player) -> Array[Node3D]:
	if player == null or player.get_tree() == null:
		return []
	var players: Array[Node3D] = []
	for candidate in player.get_tree().get_nodes_in_group("players"):
		if not (candidate is Node3D):
			continue
		if candidate.has_method("is_dead") and bool(candidate.call("is_dead")):
			continue
		players.append(candidate as Node3D)
	players.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.get_multiplayer_authority() < b.get_multiplayer_authority()
	)
	return players


func _director_state_name(director: Node) -> String:
	if director == null:
		return ""
	if director.has_method("_is_server_instance") and not bool(director.call("_is_server_instance")) and director.has_method("get_snapshot_text"):
		var remote_snapshot_text := String(director.call("get_snapshot_text"))
		for line in remote_snapshot_text.split("\n"):
			if line.begins_with("state:"):
				return line.trim_prefix("state:").strip_edges()
	if director.has_method("get_state_name"):
		return String(director.call("get_state_name"))
	if director.has_method("get_snapshot_text"):
		var snapshot_text := String(director.call("get_snapshot_text"))
		for line in snapshot_text.split("\n"):
			if line.begins_with("state:"):
				return line.trim_prefix("state:").strip_edges()
	return ""


func _send_cube_pull_intent(player, cube: Node3D, start: bool, override_intent: Vector3 = Vector3.ZERO) -> void:
	if cube == null:
		return
	var intent: Vector3 = override_intent
	if intent.length_squared() <= 0.0001:
		intent = player.global_position - cube.global_position
	intent.y = 0.0
	if intent.length_squared() <= 0.0001:
		return
	intent = intent.normalized()
	var authority: int = cube.get_multiplayer_authority()
	if authority <= 0:
		return
	if start:
		cube.request_start_pull.rpc_id(authority, intent)
	else:
		cube.request_update_pull_intent.rpc_id(authority, intent)


func _get_cube_mission_pull_intent(player, cube: Node3D, activator: Node3D, bomb_doors: Array[Node3D]) -> Vector3:
	if _scenario_name == "cube_mission_lock" and _instance_role == "client_a" and bool(_cube_mission["lock_enabled"]):
		var locked_intent: Vector3 = _cube_mission["locked_intent"]
		locked_intent.y = 0.0
		if locked_intent.length_squared() > 0.0001:
			return locked_intent.normalized()
	var navigation_target := _get_cube_mission_navigation_target(cube, activator, bomb_doors)
	var intent: Vector3 = navigation_target - cube.global_position
	intent.y = 0.0
	if intent.length_squared() > 0.0001:
		return intent.normalized()
	intent = player.global_position - cube.global_position
	intent.y = 0.0
	return intent.normalized() if intent.length_squared() > 0.0001 else Vector3.ZERO


func _perform_real_cube_pull(player, cube: Node3D, activator: Node3D, bomb_doors: Array[Node3D], director: Node) -> void:
	var now_ms := Time.get_ticks_msec()
	if _director_state_name(director) == "WON":
		var cube_on_goal_visual := cube.global_position.distance_to(activator.global_position) <= 3.0
		if not cube_on_goal_visual:
			_write_cube_mission_progress(player, cube, activator, director, "waiting_goal_replication")
			return
		_write_sync_result(
			"cube_mission_%s.json" % _instance_role,
			{
				"state": _director_state_name(director),
				"cube_goal": cube.has_method("is_goal_reached") and bool(cube.call("is_goal_reached")),
				"cube_on_goal_visual": cube_on_goal_visual,
				"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
			}
		)
		_cube_mission["written"] = true
		_cube_mission["state"] = "done"
		return
	if _director_state_name(director) == "LOBBY":
		_write_cube_mission_progress(player, cube, activator, director, "waiting_running")
		return
	var navigation_target := _get_cube_mission_navigation_target(cube, activator, bomb_doors)
	var to_goal: Vector3 = navigation_target - cube.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.001:
		_write_cube_mission_progress(player, cube, activator, director, "goal_vector_zero")
		return
	var goal_dir := to_goal.normalized()
	var lateral := Vector3(-goal_dir.z, 0.0, goal_dir.x)
	if lateral.length_squared() < 0.0001:
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	var anchor_offset: Vector3 = _cube_mission["anchor_offset"]
	var desired_position := cube.global_position + (goal_dir * 2.6) + (lateral * anchor_offset.x)
	desired_position.y = player.global_position.y
	if not bool(_cube_mission["lock_enabled"]):
		player.global_position = desired_position
		player.velocity = Vector3.ZERO
		_look_at_node(player, cube)
	var door_anchor: Vector3 = _get_cube_mission_door_anchor(bomb_doors)
	var lock_ready := cube.global_position.z > door_anchor.z + 1.2
	if _scenario_name == "cube_mission_lock" and _instance_role == "client_a" and not bool(_cube_mission["lock_enabled"]) and lock_ready:
		var locked_intent: Vector3 = navigation_target - cube.global_position
		locked_intent.y = 0.0
		if locked_intent.length_squared() <= 0.0001:
			locked_intent = player.global_position - cube.global_position
			locked_intent.y = 0.0
		if locked_intent.length_squared() > 0.0001:
			_cube_mission["locked_intent"] = locked_intent.normalized()
		_cube_mission["lock_enabled"] = true
		player.set_debug_position_lock(true)
	if not bool(_cube_mission["pull_started"]) or now_ms - int(_cube_mission["last_pull_start_ms"]) > 900:
		_send_cube_pull_intent(player, cube, true, _get_cube_mission_pull_intent(player, cube, activator, bomb_doors))
		_cube_mission["pull_started"] = true
		_cube_mission["last_pull_start_ms"] = now_ms
	else:
		_send_cube_pull_intent(player, cube, false, _get_cube_mission_pull_intent(player, cube, activator, bomb_doors))
	_write_cube_mission_progress(player, cube, activator, director, "pulling")
	if now_ms - int(_cube_mission["started_ms"]) > 60000 and not bool(_cube_mission["written"]):
		_write_sync_result(
			"cube_mission_debug_%s.json" % _instance_role,
			{
				"event": "timeout_before_win",
				"role": _instance_role,
				"director_state": _director_state_name(director),
				"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
				"activator_position": [activator.global_position.x, activator.global_position.y, activator.global_position.z],
			}
		)
		_cube_mission["written"] = true
		_cube_mission["state"] = "done"


func _perform_beetle_door_charge_open_door(player, bomb_doors: Array[Node3D], director: Node) -> void:
	if _director_state_name(director) == "LOBBY":
		return
	if _are_cube_mission_doors_open(bomb_doors):
		_beetle_door_charge["state"] = "done_opening"
		return
	var target_door: Node3D = _first_closed_cube_mission_door(bomb_doors)
	if target_door == null:
		return
	if Time.get_ticks_msec() - int(_beetle_door_charge["phase_started_ms"]) < 900:
		return
	_spawn_bomb_at_target_door(player, target_door)
	_beetle_door_charge["phase_started_ms"] = Time.get_ticks_msec()


func _perform_beetle_charge_observation(player, bomb_doors: Array[Node3D], director: Node) -> void:
	var activator := _find_cube_activator(player)
	if activator == null:
		return
	var observation_position := activator.global_position + BEETLE_DOOR_CHARGE_OBSERVER_OFFSET
	observation_position.y = player.global_position.y
	player.global_position = observation_position
	player.velocity = Vector3.ZERO
	_look_at_position(player, activator.global_position)
	var observation: Dictionary = _observe_targeting_beetle_for_player(player)
	var tracked_beetle_name: String = String(observation.get("name", ""))
	var elapsed_ms: int = Time.get_ticks_msec() - int(_beetle_door_charge["phase_started_ms"])
	var beetles: Array[Node3D] = _find_beetles(player)
	var beetle_count: int = beetles.size()
	var expected_beetle_count: int = beetle_count
	var beetle_director := _find_beetle_director(player)
	if beetle_director != null and beetle_director.has_method("_get_desired_beetle_count"):
		expected_beetle_count = int(beetle_director.call("_get_desired_beetle_count"))
	if beetle_count < expected_beetle_count and elapsed_ms < 9000:
		return
	var final_distance: float = float(observation.get("distance", -1.0))
	var own_peer_id: int = player.get_multiplayer_authority()
	var is_targeting_player: bool = int(observation.get("assigned_target_peer_id", -1)) == own_peer_id or int(observation.get("current_target_peer_id", -1)) == own_peer_id
	if is_targeting_player:
		_beetle_door_charge["targeting_observed"] = true
		_beetle_door_charge["tracked_beetle_name"] = tracked_beetle_name
		if float(_beetle_door_charge["initial_distance"]) < 0.0 and final_distance >= 0.0:
			_beetle_door_charge["initial_distance"] = final_distance
			_beetle_door_charge["closest_distance_seen"] = final_distance
	if is_targeting_player and final_distance >= 0.0:
		var closest_distance_seen: float = float(_beetle_door_charge["closest_distance_seen"])
		if closest_distance_seen < 0.0 or final_distance < closest_distance_seen:
			_beetle_door_charge["closest_distance_seen"] = final_distance
	var initial_distance: float = float(_beetle_door_charge["initial_distance"])
	var closest_distance: float = float(_beetle_door_charge["closest_distance_seen"])
	var targeting_observed: bool = bool(_beetle_door_charge["targeting_observed"])
	var charge_observed: bool = targeting_observed and initial_distance > 0.0 and closest_distance >= 0.0 and closest_distance < initial_distance - 1.2
	if not charge_observed and elapsed_ms < 7200:
		return
	_beetle_door_charge["final_distance"] = final_distance
	_write_sync_result("beetle_door_charge_%s.json" % _instance_role, {
		"state": _director_state_name(director),
		"door_open": _are_cube_mission_doors_open(bomb_doors),
		"participant_count": player.multiplayer.get_peers().size() + 1,
		"beetle_count": beetle_count,
		"player_peer_id": own_peer_id,
		"tracked_beetle_name": tracked_beetle_name,
		"initial_distance": initial_distance,
		"final_distance": final_distance,
		"closest_distance_seen": closest_distance,
		"assigned_target_peer_id": int(observation.get("assigned_target_peer_id", -1)),
		"current_target_peer_id": int(observation.get("current_target_peer_id", -1)),
		"is_targeting_player": targeting_observed,
		"charge_observed": charge_observed,
	})
	_beetle_door_charge["written"] = true
	_beetle_door_charge["state"] = "done"


func _update_portal_unlock_scenario(player) -> void:
	if bool(_portal_unlock["written"]):
		return
	var chest := _find_chest(player)
	var breche_portal := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_BRECHE)
	var reactor_portal := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_REACTOR)
	if chest == null or breche_portal == null or reactor_portal == null:
		return
	match _instance_role:
		"client_a":
			_update_portal_unlock_wood_player(player, chest)
		"client_b":
			_update_portal_unlock_apple_player(player, chest)
		"server":
			_update_portal_unlock_server(player, chest, breche_portal, reactor_portal)
	if _instance_role != "server" and breche_portal.has_method("is_portal_active") and bool(breche_portal.call("is_portal_active")):
		var chest_inventory: Variant = chest.get_inventory_component()
		var chest_wood: int = int(chest_inventory.call("count_item", "wood"))
		var chest_apple: int = int(chest_inventory.call("count_item", "apple"))
		_write_sync_result("portal_unlock_%s.json" % _instance_role, {
			"portal_breche_active": true,
			"portal_reactor_active": bool(reactor_portal.call("is_portal_active")) if reactor_portal.has_method("is_portal_active") else false,
			"chest_wood": chest_wood,
			"chest_apple": chest_apple,
		})
		_portal_unlock["written"] = true
		_portal_unlock["state"] = "done"


func _update_portal_logistics_scenario(player) -> void:
	if bool(_portal_logistics["written"]):
		return
	var chest := _find_chest(player)
	var hub_scierie := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_SCIERIE)
	var hub_verger := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_VERGER)
	var scierie_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_SCIERIE_HUB)
	var verger_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_VERGER_HUB)
	if chest == null or hub_scierie == null or hub_verger == null or scierie_hub == null or verger_hub == null:
		return
	match _instance_role:
		"server":
			_update_portal_logistics_server(player, chest)
		"client_a":
			_update_portal_logistics_wood_player(player, chest, hub_scierie, scierie_hub)
		"client_b":
			_update_portal_logistics_apple_player(player, chest, hub_verger, verger_hub)


func _update_portal_logistics_server(player, chest: Node3D) -> void:
	var director := _find_match_director(player)
	if director != null and _director_state_name(director) == "LOBBY" and director.has_method("start_match"):
		director.call("start_match")
	var inventory: Variant = chest.get_inventory_component()
	var chest_wood: int = int(inventory.call("count_item", "wood"))
	var chest_apple: int = int(inventory.call("count_item", "apple"))
	if chest_wood <= 6 or chest_apple <= 2:
		return
	_write_sync_result("portal_logistics_server.json", {
		"state": _director_state_name(director) if director != null else "",
		"chest_wood": chest_wood,
		"chest_apple": chest_apple,
		"wood_delivered": maxi(0, chest_wood - 6),
		"apple_delivered": maxi(0, chest_apple - 2),
	})
	_portal_logistics["written"] = true
	_portal_logistics["state"] = "done"


func _update_portal_logistics_wood_player(player, chest: Node3D, hub_portal: Node3D, return_portal: Node3D) -> void:
	match String(_portal_logistics["state"]):
		"travel_to_scierie":
			_move_player_into_portal(player, hub_portal)
			if player.global_position.distance_to(return_portal.global_position) <= 6.0:
				_portal_logistics["state"] = "pickup_wood"
				_portal_logistics["phase_started_ms"] = Time.get_ticks_msec()
		"pickup_wood":
			var wood := _find_first_available_pickup_in_group(player, GROUP_MISSION_WOOD_PICKUPS)
			if wood == null:
				return
			player.global_position = wood.global_position + Vector3(0.6, 0.0, 2.0)
			player.velocity = Vector3.ZERO
			_look_at_node(player, wood)
			player.request_pickup_world_item(wood.get_path())
			_portal_logistics["state"] = "wait_wood_pickup"
		"wait_wood_pickup":
			if player.inventory.count_item("wood") > 0:
				_portal_logistics["state"] = "return_hub"
		"return_hub":
			_move_player_into_portal(player, return_portal)
			if player.global_position.distance_to(hub_portal.global_position) <= 8.0:
				_portal_logistics["state"] = "deposit"
				_portal_logistics["phase_started_ms"] = Time.get_ticks_msec()
		"deposit":
			_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.2))
			if Time.get_ticks_msec() - int(_portal_logistics["phase_started_ms"]) > 800:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("wood")))
				_portal_logistics["state"] = "wait_deposit"
		"wait_deposit":
			if player.inventory.count_item("wood") == 0:
				var inventory: Variant = chest.get_inventory_component()
				_write_sync_result("portal_logistics_client_a.json", {
					"role": "client_a",
					"entered_zone": true,
					"returned_hub": true,
					"picked_item": "wood",
					"chest_wood": int(inventory.call("count_item", "wood")),
					"chest_apple": int(inventory.call("count_item", "apple")),
				})
				_portal_logistics["written"] = true
				_portal_logistics["state"] = "done"


func _update_portal_logistics_apple_player(player, chest: Node3D, hub_portal: Node3D, return_portal: Node3D) -> void:
	match String(_portal_logistics["state"]):
		"travel_to_verger":
			_move_player_into_portal(player, hub_portal)
			if player.global_position.distance_to(return_portal.global_position) <= 6.0:
				_portal_logistics["state"] = "pickup_apple"
				_portal_logistics["phase_started_ms"] = Time.get_ticks_msec()
		"pickup_apple":
			var apple := _find_first_available_pickup_in_group(player, GROUP_MISSION_APPLE_PICKUPS)
			if apple == null:
				return
			player.global_position = apple.global_position + Vector3(0.6, 0.0, 2.0)
			player.velocity = Vector3.ZERO
			_look_at_node(player, apple)
			player.request_pickup_world_item(apple.get_path())
			_portal_logistics["state"] = "wait_apple_pickup"
		"wait_apple_pickup":
			if player.inventory.count_item("apple") > 0:
				_portal_logistics["state"] = "return_hub"
		"return_hub":
			_move_player_into_portal(player, return_portal)
			if player.global_position.distance_to(hub_portal.global_position) <= 8.0:
				_portal_logistics["state"] = "deposit"
				_portal_logistics["phase_started_ms"] = Time.get_ticks_msec()
		"deposit":
			_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.2))
			if Time.get_ticks_msec() - int(_portal_logistics["phase_started_ms"]) > 800:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("apple")))
				_portal_logistics["state"] = "wait_deposit"
		"wait_deposit":
			if player.inventory.count_item("apple") == 0:
				var inventory: Variant = chest.get_inventory_component()
				_write_sync_result("portal_logistics_client_b.json", {
					"role": "client_b",
					"entered_zone": true,
					"returned_hub": true,
					"picked_item": "apple",
					"chest_wood": int(inventory.call("count_item", "wood")),
					"chest_apple": int(inventory.call("count_item", "apple")),
				})
				_portal_logistics["written"] = true
				_portal_logistics["state"] = "done"


func _update_portal_progression_scenario(player) -> void:
	if bool(_portal_progression["written"]):
		return
	var chest := _find_chest(player)
	var hub_scierie := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_SCIERIE)
	var hub_verger := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_VERGER)
	var hub_breche := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_BRECHE)
	var hub_reactor := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_REACTOR)
	var scierie_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_SCIERIE_HUB)
	var verger_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_VERGER_HUB)
	var breche_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_BRECHE_HUB)
	var reactor_hub := _find_first_node3d_in_group(player, GROUP_PORTAL_REACTOR_HUB)
	var bomb_doors: Array[Node3D] = _find_cube_mission_bomb_doors(player)
	if chest == null or hub_scierie == null or hub_verger == null or hub_breche == null or hub_reactor == null or scierie_hub == null or verger_hub == null or breche_hub == null or reactor_hub == null or bomb_doors.is_empty():
		return
	if _portal_is_active(hub_breche):
		_portal_progression["breche_unlocked_observed"] = true
	if _portal_is_active(hub_reactor):
		_portal_progression["reactor_unlocked_observed"] = true
	match _instance_role:
		"server":
			_update_portal_progression_server(player, chest, hub_scierie, hub_verger, hub_breche, hub_reactor)
		"client_a":
			_update_portal_progression_client_a(player, chest, hub_scierie, scierie_hub, hub_breche, breche_hub, hub_reactor, reactor_hub, bomb_doors)
		"client_b":
			_update_portal_progression_client_b(player, chest, hub_verger, verger_hub, hub_reactor, reactor_hub)


func _update_portal_progression_server(player, chest: Node3D, hub_scierie: Node3D, hub_verger: Node3D, hub_breche: Node3D, hub_reactor: Node3D) -> void:
	var director: Node = _find_match_director(player)
	if director != null and _director_state_name(director) == "LOBBY" and director.has_method("start_match"):
		director.call("start_match")
	if _portal_is_active(hub_breche) and not bool(_portal_progression["breche_phase_written"]):
		_write_sync_result("portal_progression_phase_breche.json", _build_portal_progression_phase_result(player, chest, hub_breche, hub_reactor, "breche_unlocked"))
		_portal_progression["breche_phase_written"] = true
	if _portal_is_active(hub_reactor) and not bool(_portal_progression["reactor_phase_written"]):
		_write_sync_result("portal_progression_phase_reactor.json", _build_portal_progression_phase_result(player, chest, hub_breche, hub_reactor, "reactor_unlocked"))
		_portal_progression["reactor_phase_written"] = true
	if not _portal_is_active(hub_breche) or not _portal_is_active(hub_reactor):
		return
	var inventory: Variant = chest.get_inventory_component()
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
		"state": _director_state_name(director) if director != null else "",
	})
	_portal_progression["written"] = true
	_portal_progression["state"] = "done"


func _update_portal_progression_client_a(player, chest: Node3D, hub_scierie: Node3D, scierie_hub: Node3D, hub_breche: Node3D, breche_hub: Node3D, hub_reactor: Node3D, reactor_hub: Node3D, bomb_doors: Array[Node3D]) -> void:
	match String(_portal_progression["state"]):
		"travel_to_scierie":
			_move_player_into_portal(player, hub_scierie)
			if player.global_position.distance_to(scierie_hub.global_position) <= 6.0:
				_portal_progression["state"] = "pickup_wood"
		"pickup_wood":
			var wood := _find_first_available_pickup_in_group(player, GROUP_MISSION_WOOD_PICKUPS)
			if wood == null:
				return
			player.global_position = wood.global_position + Vector3(0.6, 0.0, 2.0)
			player.velocity = Vector3.ZERO
			_look_at_node(player, wood)
			player.request_pickup_world_item(wood.get_path())
			_portal_progression["state"] = "wait_wood_pickup"
		"wait_wood_pickup":
			if player.inventory.count_item("wood") > 0:
				_portal_progression["state"] = "return_hub_from_scierie"
		"return_hub_from_scierie":
			_move_player_into_portal(player, scierie_hub)
			if player.global_position.distance_to(hub_scierie.global_position) <= 8.0:
				_portal_progression["state"] = "deposit_wood"
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
		"deposit_wood":
			_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.2))
			if Time.get_ticks_msec() - int(_portal_progression["phase_started_ms"]) > 800:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("wood")))
				_portal_progression["state"] = "wait_wood_deposit"
		"wait_wood_deposit":
			if player.inventory.count_item("wood") == 0:
				var wood_stage: int = int(_portal_progression["wood_stage"])
				if wood_stage < 1:
					_portal_progression["wood_stage"] = wood_stage + 1
					_portal_progression["state"] = "pickup_wood"
					_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
				elif not _portal_is_active(hub_breche):
					_portal_progression["state"] = "wait_breche_unlock"
				else:
					_portal_progression["state"] = "travel_to_breche"
		"wait_breche_unlock":
			if _portal_is_active(hub_breche):
				_portal_progression["state"] = "travel_to_breche"
		"travel_to_breche":
			_move_player_into_portal(player, hub_breche)
			if player.global_position.distance_to(breche_hub.global_position) <= 6.0:
				_portal_progression["state"] = "open_breche"
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
				_portal_progression["bomb_requested"] = false
		"open_breche":
			if _are_cube_mission_doors_open(bomb_doors):
				_portal_progression["state"] = "return_from_breche"
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
				_portal_progression["bomb_requested"] = false
				return
			var target_door: Node3D = _first_closed_cube_mission_door(bomb_doors)
			if target_door == null:
				return
			if Time.get_ticks_msec() - int(_portal_progression["phase_started_ms"]) < 700:
				_move_player_for_single_bomb_door(player, target_door)
				return
			if not bool(_portal_progression["bomb_requested"]):
				_move_player_for_single_bomb_door(player, target_door)
				_spawn_bomb_at_target_door(player, target_door)
				_portal_progression["bomb_requested"] = true
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
				return
			if target_door.has_method("is_open") and bool(target_door.call("is_open")):
				_portal_progression["bomb_requested"] = false
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
				return
			if Time.get_ticks_msec() - int(_portal_progression["phase_started_ms"]) > 6500:
				_portal_progression["bomb_requested"] = false
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
			_move_player_for_single_bomb_door(player, target_door)
		"return_from_breche":
			_move_player_into_portal(player, breche_hub)
			if player.global_position.distance_to(hub_breche.global_position) <= 8.0:
				if _portal_is_active(hub_reactor):
					_portal_progression["state"] = "travel_to_reactor"
				else:
					_portal_progression["state"] = "wait_reactor_unlock"
		"wait_reactor_unlock":
			if _portal_is_active(hub_reactor):
				_portal_progression["state"] = "travel_to_reactor"
		"travel_to_reactor":
			_move_player_into_portal(player, hub_reactor)
			if player.global_position.distance_to(reactor_hub.global_position) <= 6.0:
				var inventory: Variant = chest.get_inventory_component()
				_write_sync_result("portal_progression_client_a.json", {
					"role": "client_a",
					"initial_breche_active": bool(_portal_progression["initial_breche_active"]),
					"initial_reactor_active": bool(_portal_progression["initial_reactor_active"]),
					"breche_unlocked_observed": bool(_portal_progression["breche_unlocked_observed"]),
					"reactor_unlocked_observed": bool(_portal_progression["reactor_unlocked_observed"]),
					"breche_entered": true,
					"reactor_entered": true,
					"doors_opened": _are_cube_mission_doors_open(bomb_doors),
					"chest_wood": int(inventory.call("count_item", "wood")),
					"chest_apple": int(inventory.call("count_item", "apple")),
				})
				_portal_progression["written"] = true
				_portal_progression["state"] = "done"


func _update_portal_progression_client_b(player, chest: Node3D, hub_verger: Node3D, verger_hub: Node3D, hub_reactor: Node3D, reactor_hub: Node3D) -> void:
	match String(_portal_progression["state"]):
		"travel_to_verger":
			_move_player_into_portal(player, hub_verger)
			if player.global_position.distance_to(verger_hub.global_position) <= 6.0:
				_portal_progression["state"] = "pickup_apple"
		"pickup_apple":
			var apple := _find_first_available_pickup_in_group(player, GROUP_MISSION_APPLE_PICKUPS)
			if apple == null:
				return
			player.global_position = apple.global_position + Vector3(0.6, 0.0, 2.0)
			player.velocity = Vector3.ZERO
			_look_at_node(player, apple)
			player.request_pickup_world_item(apple.get_path())
			_portal_progression["state"] = "wait_apple_pickup"
		"wait_apple_pickup":
			if player.inventory.count_item("apple") > 0:
				_portal_progression["state"] = "return_hub_from_verger"
		"return_hub_from_verger":
			_move_player_into_portal(player, verger_hub)
			if player.global_position.distance_to(hub_verger.global_position) <= 8.0:
				_portal_progression["state"] = "deposit_apple"
				_portal_progression["phase_started_ms"] = Time.get_ticks_msec()
		"deposit_apple":
			_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.2))
			if Time.get_ticks_msec() - int(_portal_progression["phase_started_ms"]) > 800:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("apple")))
				_portal_progression["state"] = "wait_apple_deposit"
		"wait_apple_deposit":
			if player.inventory.count_item("apple") == 0:
				if _portal_is_active(hub_reactor):
					_portal_progression["state"] = "travel_to_reactor"
				else:
					_portal_progression["state"] = "wait_reactor_unlock"
		"wait_reactor_unlock":
			if _portal_is_active(hub_reactor):
				_portal_progression["state"] = "travel_to_reactor"
		"travel_to_reactor":
			_move_player_into_portal(player, hub_reactor)
			if player.global_position.distance_to(reactor_hub.global_position) <= 6.0:
				var inventory: Variant = chest.get_inventory_component()
				_write_sync_result("portal_progression_client_b.json", {
					"role": "client_b",
					"initial_breche_active": bool(_portal_progression["initial_breche_active"]),
					"initial_reactor_active": bool(_portal_progression["initial_reactor_active"]),
					"breche_unlocked_observed": bool(_portal_progression["breche_unlocked_observed"]),
					"reactor_unlocked_observed": bool(_portal_progression["reactor_unlocked_observed"]),
					"reactor_entered": true,
					"chest_wood": int(inventory.call("count_item", "wood")),
					"chest_apple": int(inventory.call("count_item", "apple")),
				})
				_portal_progression["written"] = true
				_portal_progression["state"] = "done"


func _build_portal_progression_phase_result(player, chest: Node3D, hub_breche: Node3D, hub_reactor: Node3D, phase_name: String) -> Dictionary:
	var inventory: Variant = chest.get_inventory_component()
	return {
		"role": _instance_role,
		"phase": phase_name,
		"breche_active": _portal_is_active(hub_breche),
		"reactor_active": _portal_is_active(hub_reactor),
		"chest_wood": int(inventory.call("count_item", "wood")),
		"chest_apple": int(inventory.call("count_item", "apple")),
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
	}


func _update_portal_unlock_wood_player(player, chest: Node3D) -> void:
	var current_stage: int = int(_portal_unlock["wood_stage"])
	var scierie_zone := _find_first_node3d_in_group(player, GROUP_MISSION_ZONE_SCIERIE)
	var current_target: Node3D = null
	if scierie_zone != null:
		current_target = _find_first_available_pickup_in_group_near_position(player, GROUP_MISSION_WOOD_PICKUPS, scierie_zone.global_position)
	match String(_portal_unlock["state"]):
		"pickup_wood":
			if current_target != null and current_target.has_method("can_be_picked_up") and bool(current_target.call("can_be_picked_up")):
				player.global_position = current_target.global_position + Vector3(0.6, 0.0, 2.0)
				player.velocity = Vector3.ZERO
				_look_at_node(player, current_target)
				player.request_pickup_world_item(current_target.get_path())
				_portal_unlock["state"] = "wait_wood_pickup"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"wait_wood_pickup":
			if player.inventory.count_item("wood") > 0:
				_move_player_to_chest(player, chest, Vector3(0.8, 0.0, 2.2))
				_portal_unlock["state"] = "give_wood"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"give_wood":
			if Time.get_ticks_msec() - int(_portal_unlock["phase_started_ms"]) > 900:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("wood")))
				_portal_unlock["state"] = "wait_wood_transfer"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"wait_wood_transfer":
			if player.inventory.count_item("wood") == 0:
				if current_stage >= 1:
					_portal_unlock["state"] = "done"
				else:
					_portal_unlock["wood_stage"] = current_stage + 1
					_portal_unlock["state"] = "pickup_wood"
					_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()


func _update_portal_unlock_apple_player(player, chest: Node3D) -> void:
	var verger_zone := _find_first_node3d_in_group(player, GROUP_MISSION_ZONE_VERGER)
	var apple: Node3D = null
	if verger_zone != null:
		apple = _find_first_available_pickup_in_group_near_position(player, GROUP_MISSION_APPLE_PICKUPS, verger_zone.global_position)
	match String(_portal_unlock["state"]):
		"pickup_apple":
			if apple != null and apple.has_method("can_be_picked_up") and bool(apple.call("can_be_picked_up")):
				player.global_position = apple.global_position + Vector3(0.6, 0.0, 2.0)
				player.velocity = Vector3.ZERO
				_look_at_node(player, apple)
				if Time.get_ticks_msec() - int(_portal_unlock["phase_started_ms"]) > 500:
					player.request_pickup_world_item(apple.get_path())
					_portal_unlock["state"] = "wait_apple_pickup"
					_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"wait_apple_pickup":
			if player.inventory.count_item("apple") > 0:
				_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.2))
				_portal_unlock["state"] = "give_apple"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - int(_portal_unlock["phase_started_ms"]) > 1800:
				_portal_unlock["state"] = "pickup_apple"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"give_apple":
			_move_player_to_chest(player, chest, Vector3(-0.8, 0.0, 2.2))
			if Time.get_ticks_msec() - int(_portal_unlock["phase_started_ms"]) > 900:
				player.request_transfer_to_target(0, maxi(1, player.inventory.count_item("apple")))
				_portal_unlock["state"] = "wait_apple_transfer"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"wait_apple_transfer":
			if player.inventory.count_item("apple") == 0:
				_portal_unlock["apple_done"] = true
				_portal_unlock["state"] = "wait_breche_unlock"
			elif Time.get_ticks_msec() - int(_portal_unlock["phase_started_ms"]) > 1800:
				_portal_unlock["state"] = "give_apple"
				_portal_unlock["phase_started_ms"] = Time.get_ticks_msec()
		"wait_breche_unlock":
			var breche_portal := _find_first_node3d_in_group(player, GROUP_PORTAL_HUB_BRECHE)
			if _portal_is_active(breche_portal):
				_portal_unlock["state"] = "done"


func _update_portal_unlock_server(player, chest: Node3D, breche_portal: Node3D, reactor_portal: Node3D) -> void:
	var director := _find_match_director(player)
	if director != null and _director_state_name(director) == "LOBBY" and director.has_method("start_match"):
		director.call("start_match")
	if not breche_portal.has_method("is_portal_active"):
		return
	if not bool(breche_portal.call("is_portal_active")):
		return
	var chest_inventory: Variant = chest.get_inventory_component()
	var chest_wood: int = int(chest_inventory.call("count_item", "wood"))
	var chest_apple: int = int(chest_inventory.call("count_item", "apple"))
	_write_sync_result("portal_unlock_server.json", {
		"state": _director_state_name(director) if director != null else "",
		"portal_breche_active": bool(breche_portal.call("is_portal_active")),
		"portal_reactor_active": bool(reactor_portal.call("is_portal_active")) if reactor_portal.has_method("is_portal_active") else false,
		"chest_wood": chest_wood,
		"chest_apple": chest_apple,
		"chest_wood_delivered": maxi(0, chest_wood - 6),
		"chest_apple_delivered": maxi(0, chest_apple - 2),
	})
	_portal_unlock["written"] = true
	_portal_unlock["state"] = "done"


func _perform_cube_mission_open_door(player, bomb_doors: Array[Node3D], cube: Node3D, activator: Node3D, director: Node) -> void:
	var director_state := _director_state_name(director)
	if director_state == "LOBBY":
		_write_cube_mission_progress(player, cube, activator, director, "waiting_running")
		return
	if _are_cube_mission_doors_open(bomb_doors):
		_cube_mission["win_requested"] = false
		_cube_mission["state"] = "pull_cube"
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		return
	var target_door: Node3D = _first_closed_cube_mission_door(bomb_doors)
	if target_door == null:
		return
	if Time.get_ticks_msec() - int(_cube_mission["phase_started_ms"]) < 700:
		_move_player_for_single_bomb_door(player, target_door)
		_write_cube_mission_progress(player, cube, activator, director, "approach_door")
		return
	if not bool(_cube_mission.get("win_requested", false)):
		_move_player_for_single_bomb_door(player, target_door)
		_spawn_bomb_at_target_door(player, target_door)
		_cube_mission["win_requested"] = true
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		_write_cube_mission_progress(player, cube, activator, director, "bomb_placed")
		return
	if target_door.has_method("is_open") and bool(target_door.call("is_open")):
		_cube_mission["win_requested"] = false
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		_write_cube_mission_progress(player, cube, activator, director, "door_opened")
		return
	if Time.get_ticks_msec() - int(_cube_mission["phase_started_ms"]) > 6500:
		_cube_mission["win_requested"] = false
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		_write_cube_mission_progress(player, cube, activator, director, "retry_bomb")
		return
	_move_player_for_single_bomb_door(player, target_door)
	_write_cube_mission_progress(player, cube, activator, director, "waiting_door_open")


func _perform_cube_mission_destroy_crates(player, cube: Node3D, activator: Node3D, director: Node) -> void:
	if _instance_role != "client_a":
		return
	var paths: Array[Node3D] = _find_cube_mission_crates(player)
	var index: int = int(_cube_mission["crate_index"])
	if index >= paths.size():
		_cube_mission["state"] = "open_door"
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		return
	var crate: Node3D = paths[index]
	if crate == null:
		_cube_mission["crate_index"] = index + 1
		return
	var now := Time.get_ticks_msec()
	if not bool(_cube_mission["crate_waiting"]):
		player.global_position = crate.global_position + Vector3(-1.8, 0.0, 1.8)
		player.velocity = Vector3.ZERO
		_look_at_node(player, crate)
		if crate.has_method("damage"):
			crate.call("damage", Vector3.ZERO, Vector3.ZERO)
		_cube_mission["crate_waiting"] = true
		_cube_mission["crate_phase_started"] = now
		_write_cube_mission_progress(player, cube, activator, director, "destroying_crate_%d" % index)
		return
	if crate.has_method("is_destroyed") and bool(crate.call("is_destroyed")):
		_cube_mission["crate_index"] = index + 1
		_cube_mission["crate_waiting"] = false
		_cube_mission["crate_phase_started"] = now
		return
	if now - int(_cube_mission["crate_phase_started"]) > 2500:
		_cube_mission["crate_waiting"] = false
		_cube_mission["crate_phase_started"] = now


func _perform_cube_mission_wait_door(player, bomb_doors: Array[Node3D], cube: Node3D, activator: Node3D, director: Node) -> void:
	if _director_state_name(director) == "LOBBY":
		_write_cube_mission_progress(player, cube, activator, director, "waiting_running")
		return
	if _are_cube_mission_doors_open(bomb_doors):
		_cube_mission["state"] = "pull_cube"
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		return
	var target_door: Node3D = _first_closed_cube_mission_door(bomb_doors)
	if target_door != null:
		_move_player_for_single_bomb_door(player, target_door)
	else:
		_move_player_near_cube(player, cube, activator, bomb_doors)
	_write_cube_mission_progress(player, cube, activator, director, "waiting_door_open")


func _move_player_for_bomb_door(player, bomb_doors: Array[Node3D]) -> void:
	var door_anchor: Vector3 = _get_cube_mission_door_anchor(bomb_doors)
	player.global_position = door_anchor + Vector3(0.0, 0.0, -2.4)
	player.velocity = Vector3.ZERO
	_look_at_position(player, door_anchor)


func _move_player_for_single_bomb_door(player, bomb_door: Node3D) -> void:
	player.global_position = bomb_door.global_position + Vector3(-2.0, 0.0, 0.8)
	player.velocity = Vector3.ZERO
	_look_at_node(player, bomb_door)


func _portal_is_active(portal: Node) -> bool:
	return is_instance_valid(portal) and portal.has_method("is_portal_active") and bool(portal.call("is_portal_active"))


func _move_player_into_portal(player, portal: Node3D) -> void:
	var portal_forward := -portal.global_transform.basis.z
	portal_forward.y = 0.0
	if portal_forward.length_squared() < 0.001:
		portal_forward = Vector3.FORWARD
	else:
		portal_forward = portal_forward.normalized()
	player.global_position = portal.global_position + portal_forward * 0.2
	player.velocity = Vector3.ZERO
	_look_at_position(player, portal.global_position + portal_forward)
	if portal.has_method("_on_portal_entered"):
		portal.call("_on_portal_entered", player)


func _spawn_bomb_at_target_door(player, bomb_door: Node3D) -> void:
	var bomb_position := bomb_door.global_position + Vector3(0.0, 1.0, 0.0)
	player.spawn_bomb.rpc(bomb_position, Vector3.ZERO)


func _move_player_near_cube(player, cube: Node3D, activator: Node3D, bomb_doors: Array[Node3D]) -> void:
	var navigation_target := _get_cube_mission_navigation_target(cube, activator, bomb_doors)
	var to_goal: Vector3 = navigation_target - cube.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.001:
		return
	var goal_dir := to_goal.normalized()
	var lateral := Vector3(-goal_dir.z, 0.0, goal_dir.x)
	if lateral.length_squared() < 0.0001:
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	var anchor_offset: Vector3 = _cube_mission["anchor_offset"]
	var desired_position := cube.global_position + (goal_dir * 2.6) + (lateral * anchor_offset.x)
	desired_position.y = player.global_position.y
	player.global_position = desired_position
	player.velocity = Vector3.ZERO
	_look_at_node(player, cube)


func _get_cube_mission_navigation_target(cube: Node3D, activator: Node3D, bomb_doors: Array[Node3D]) -> Vector3:
	var door_anchor: Vector3 = _get_cube_mission_door_anchor(bomb_doors)
	var corridor_exit := Vector3(
		door_anchor.x - 1.4,
		cube.global_position.y,
		door_anchor.z + 4.4
	)
	var bridge_waypoint := Vector3(
		activator.global_position.x - 5.0,
		cube.global_position.y,
		activator.global_position.z - 6.0
	)
	var final_waypoint := Vector3(
		activator.global_position.x - 1.2,
		cube.global_position.y,
		activator.global_position.z - 1.5
	)
	if cube.global_position.z < corridor_exit.z - 0.8:
		return corridor_exit
	if cube.global_position.distance_to(bridge_waypoint) > 2.6:
		return bridge_waypoint
	if cube.global_position.distance_to(final_waypoint) > 1.8:
		return final_waypoint
	return activator.global_position


func _write_cube_mission_progress(player, cube: Node3D, activator: Node3D, director: Node, event_name: String) -> void:
	var now_ms := Time.get_ticks_msec()
	if now_ms - int(_cube_mission["last_debug_write_ms"]) < 1000:
		return
	_cube_mission["last_debug_write_ms"] = now_ms
	var cube_to_goal := activator.global_position - cube.global_position
	var cube_on_goal_visual := cube.global_position.distance_to(activator.global_position) <= 3.0
	_write_sync_result(
		"cube_mission_debug_%s.json" % _instance_role,
		{
			"event": event_name,
			"role": _instance_role,
			"director_state": _director_state_name(director),
			"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
			"cube_position": [cube.global_position.x, cube.global_position.y, cube.global_position.z],
			"activator_position": [activator.global_position.x, activator.global_position.y, activator.global_position.z],
			"cube_to_goal_distance": cube_to_goal.length(),
			"cube_goal": cube.has_method("is_goal_reached") and bool(cube.call("is_goal_reached")),
			"cube_on_goal_visual": cube_on_goal_visual,
		}
	)


func _find_node_by_path(player: Node3D, path: String) -> Node3D:
	if player == null:
		return null
	var tree := player.get_tree()
	if tree == null:
		return null
	var root: Node = tree.get_root()
	var node := root.get_node_or_null(path)
	if node is Node3D:
		return node
	return null


func _find_cube_mission_crates(player: Node3D) -> Array[Node3D]:
	var crates: Array[Node3D] = _find_nodes3d_in_group(player, GROUP_MISSION_CUBE_BLOCKERS)
	crates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.x < b.global_position.x
	)
	return crates


func _find_first_node3d_in_group(player, group_name: String) -> Node3D:
	var nodes: Array[Node3D] = _find_nodes3d_in_group(player, group_name)
	if nodes.is_empty():
		return null
	return nodes[0]


func _find_nodes3d_in_group(player, group_name: String) -> Array[Node3D]:
	if player == null or player.get_tree() == null:
		return []
	var nodes: Array[Node3D] = []
	for candidate in player.get_tree().get_nodes_in_group(group_name):
		if candidate is Node3D:
			nodes.append(candidate as Node3D)
	nodes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return String(a.get_path()) < String(b.get_path())
	)
	return nodes


func _find_world_item(player, node_name: String) -> Node3D:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return null
	return _find_world_item_in_subtree(scene_root, node_name)


func _find_world_item_in_subtree(root: Node, node_name: String) -> Node3D:
	if root is Node3D and root.name == node_name and root.has_method("can_be_picked_up"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_world_item_in_subtree(child, node_name)
		if found != null:
			return found
	return null


func _find_first_available_pickup_in_group(player, group_name: String) -> Node3D:
	var best_pickup: Node3D = null
	var best_distance: float = INF
	for candidate in _find_nodes3d_in_group(player, group_name):
		if candidate.has_method("can_be_picked_up") and bool(candidate.call("can_be_picked_up")):
			var distance: float = player.global_position.distance_to(candidate.global_position)
			if distance < best_distance:
				best_pickup = candidate
				best_distance = distance
	return best_pickup


func _find_first_available_pickup_in_group_near_position(player, group_name: String, center: Vector3) -> Node3D:
	var best_pickup: Node3D = null
	var best_distance: float = INF
	for candidate in _find_nodes3d_in_group(player, group_name):
		if candidate.has_method("can_be_picked_up") and bool(candidate.call("can_be_picked_up")):
			var distance: float = center.distance_to(candidate.global_position)
			if distance < best_distance:
				best_pickup = candidate
				best_distance = distance
	return best_pickup


func _await_bomb_door_and_item(player, node_name: String) -> Dictionary:
	for _attempt in range(60):
		var bomb_door := _find_bomb_door(player)
		var item := _find_world_item(player, node_name)
		if bomb_door != null and item != null and bomb_door.is_inside_tree() and item.is_inside_tree():
			return {"bomb_door": bomb_door, "item": item}
		await player.get_tree().process_frame
	return {}


func _await_replication_stress_nodes(player) -> Dictionary:
	for _attempt in range(120):
		var bomb_door := _find_bomb_door(player)
		var chest := _find_chest(player)
		var wood := _find_world_item(player, "WoodPickup")
		var apple := _find_world_item(player, "ApplePickup")
		if bomb_door != null and chest != null and wood != null and apple != null:
			if bomb_door.is_inside_tree() and chest.is_inside_tree() and wood.is_inside_tree() and apple.is_inside_tree():
				return {
					"bomb_door": bomb_door,
					"chest": chest,
					"wood": wood,
					"apple": apple,
				}
		await player.get_tree().process_frame
	return {}


func _await_cube_and_activator(player) -> Dictionary:
	for _attempt in range(90):
		var cube := _find_primary_pull_cube(player)
		var activator := _find_cube_activator(player)
		if cube != null and activator != null and cube.is_inside_tree() and activator.is_inside_tree():
			return {"cube": cube, "activator": activator}
		await player.get_tree().process_frame
	return {}


func _await_cube_activator_and_bomb_door(player) -> Dictionary:
	for _attempt in range(120):
		var cube := _find_primary_pull_cube(player)
		var activator := _find_cube_activator(player)
		var bomb_door := _find_bomb_door(player)
		if cube != null and activator != null and bomb_door != null and cube.is_inside_tree() and activator.is_inside_tree() and bomb_door.is_inside_tree():
			return {"cube": cube, "activator": activator, "bomb_door": bomb_door}
		await player.get_tree().process_frame
	return {}


func _find_connection(player) -> Node:
	var current_scene: Node = player.get_tree().current_scene
	if current_scene == null:
		return null
	return current_scene.get_node_or_null("Connection")


func _get_instance_role_index() -> int:
	if not _instance_role.begins_with("client_"):
		return -1
	var value_text := _instance_role.trim_prefix("client_")
	return int(value_text) if value_text.is_valid_int() else -1
