extends RefCounted
class_name PlayerUiTestDriver


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


func _setup_cube_mission_scenario(player) -> void:
	if _setup_done or not player.is_multiplayer_authority():
		return
	var resolved := await _await_cube_activator_and_bomb_door(player)
	var cube: Node3D = resolved.get("cube")
	var activator: Node3D = resolved.get("activator")
	var bomb_door: Node3D = resolved.get("bomb_door")
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
			_cube_mission["state"] = "open_door"
			_cube_mission["started_ms"] = Time.get_ticks_msec()
			_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		"client_b":
			_cube_mission["anchor_offset"] = Vector3(1.2, 0.0, 0.0)
			_cube_mission["state"] = "wait_door_open"
			_cube_mission["started_ms"] = Time.get_ticks_msec()
			_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
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
	var bomb_door := _find_bomb_door(player)
	if cube == null or activator == null or bomb_door == null:
		return
	var director := _find_match_director(player)
	if director == null:
		return
	match String(_cube_mission["state"]):
		"monitor_win":
			if _director_state_name(director) == "LOBBY" and director.has_method("start_match") and Time.get_ticks_msec() - int(_cube_mission["started_ms"]) > 800:
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
			_perform_cube_mission_open_door(player, bomb_door, cube, activator, director)
		"wait_door_open":
			_perform_cube_mission_wait_door(player, bomb_door, cube, activator, director)
		"pull_cube":
			_perform_real_cube_pull(player, cube, activator, bomb_door, director)
		"wait_win":
			if _director_state_name(director) == "WON":
				_write_sync_result(
					"cube_mission_%s.json" % _instance_role,
					{
						"state": _director_state_name(director),
						"cube_goal": cube.has_method("is_goal_reached") and bool(cube.call("is_goal_reached")),
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
	var look_target := node.global_position
	look_target.y = player.global_position.y
	player.look_at(look_target, Vector3.UP, true)


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
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return null
	return _find_chest_in_subtree(scene_root)

func _find_chest_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "Chest" and root.has_method("get_inventory_component"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_chest_in_subtree(child)
		if found != null:
			return found
	return null


func _find_bomb_door(player) -> Node3D:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return null
	return _find_bomb_door_in_subtree(scene_root)


func _find_bomb_door_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "BombDoor" and root.has_method("is_open"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_bomb_door_in_subtree(child)
		if found != null:
			return found
	return null


func _find_cube_activator(player) -> Node3D:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return null
	return _find_cube_activator_in_subtree(scene_root)


func _find_cube_activator_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "CubeActivator":
		return root as Node3D
	for child in root.get_children():
		var found := _find_cube_activator_in_subtree(child)
		if found != null:
			return found
	return null


func _find_primary_pull_cube(player) -> Node3D:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return null
	return _find_primary_pull_cube_in_subtree(scene_root)


func _find_primary_pull_cube_in_subtree(root: Node) -> Node3D:
	if root is Node3D and root.name == "RigidCube3D" and root.is_in_group("pullable_cubes"):
		return root as Node3D
	for child in root.get_children():
		var found := _find_primary_pull_cube_in_subtree(child)
		if found != null:
			return found
	return null


func _find_match_director(player) -> Node:
	return player.get_tree().get_first_node_in_group("match_director")


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


func _get_cube_mission_pull_intent(player, cube: Node3D) -> Vector3:
	if _scenario_name == "cube_mission_lock" and _instance_role == "client_a" and bool(_cube_mission["lock_enabled"]):
		var locked_intent: Vector3 = _cube_mission["locked_intent"]
		locked_intent.y = 0.0
		if locked_intent.length_squared() > 0.0001:
			return locked_intent.normalized()
	var intent: Vector3 = player.global_position - cube.global_position
	intent.y = 0.0
	return intent.normalized() if intent.length_squared() > 0.0001 else Vector3.ZERO


func _perform_real_cube_pull(player, cube: Node3D, activator: Node3D, bomb_door: Node3D, director: Node) -> void:
	var now_ms := Time.get_ticks_msec()
	if _director_state_name(director) == "WON":
		var cube_on_goal_visual := cube.global_position.distance_to(activator.global_position) <= 3.0
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
	var navigation_target := _get_cube_mission_navigation_target(cube, activator, bomb_door)
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
	var lock_ready := cube.global_position.z > bomb_door.global_position.z + 1.2
	if _scenario_name == "cube_mission_lock" and _instance_role == "client_a" and not bool(_cube_mission["lock_enabled"]) and lock_ready:
		var locked_intent: Vector3 = player.global_position - cube.global_position
		locked_intent.y = 0.0
		if locked_intent.length_squared() > 0.0001:
			_cube_mission["locked_intent"] = locked_intent.normalized()
		_cube_mission["lock_enabled"] = true
		player.set_debug_position_lock(true)
	if not bool(_cube_mission["pull_started"]) or now_ms - int(_cube_mission["last_pull_start_ms"]) > 900:
		_send_cube_pull_intent(player, cube, true, _get_cube_mission_pull_intent(player, cube))
		_cube_mission["pull_started"] = true
		_cube_mission["last_pull_start_ms"] = now_ms
	else:
		_send_cube_pull_intent(player, cube, false, _get_cube_mission_pull_intent(player, cube))
	_write_cube_mission_progress(player, cube, activator, director, "pulling")
	if now_ms - int(_cube_mission["started_ms"]) > 30000 and not bool(_cube_mission["written"]):
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


func _perform_cube_mission_open_door(player, bomb_door: Node3D, cube: Node3D, activator: Node3D, director: Node) -> void:
	var director_state := _director_state_name(director)
	if director_state == "LOBBY":
		_write_cube_mission_progress(player, cube, activator, director, "waiting_running")
		return
	if bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")):
		_cube_mission["state"] = "pull_cube"
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - int(_cube_mission["phase_started_ms"]) < 700:
		_move_player_for_bomb_door(player, bomb_door)
		_write_cube_mission_progress(player, cube, activator, director, "approach_door")
		return
	if not bool(_cube_mission.get("win_requested", false)):
		_move_player_for_bomb_door(player, bomb_door)
		player.place_bomb()
		_cube_mission["win_requested"] = true
		_write_cube_mission_progress(player, cube, activator, director, "bomb_placed")
		return
	_move_player_for_bomb_door(player, bomb_door)
	_write_cube_mission_progress(player, cube, activator, director, "waiting_door_open")


func _perform_cube_mission_wait_door(player, bomb_door: Node3D, cube: Node3D, activator: Node3D, director: Node) -> void:
	if _director_state_name(director) == "LOBBY":
		_write_cube_mission_progress(player, cube, activator, director, "waiting_running")
		return
	if bomb_door.has_method("is_open") and bool(bomb_door.call("is_open")):
		_cube_mission["state"] = "pull_cube"
		_cube_mission["phase_started_ms"] = Time.get_ticks_msec()
		return
	_move_player_near_cube(player, cube, activator, bomb_door)
	_write_cube_mission_progress(player, cube, activator, director, "waiting_door_open")


func _move_player_for_bomb_door(player, bomb_door: Node3D) -> void:
	player.global_position = bomb_door.global_position + Vector3(-2.0, 0.0, 0.8)
	player.velocity = Vector3.ZERO
	_look_at_node(player, bomb_door)


func _move_player_near_cube(player, cube: Node3D, activator: Node3D, bomb_door: Node3D) -> void:
	var navigation_target := _get_cube_mission_navigation_target(cube, activator, bomb_door)
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


func _get_cube_mission_navigation_target(cube: Node3D, activator: Node3D, bomb_door: Node3D) -> Vector3:
	var door_waypoint := bomb_door.global_position + Vector3(-0.8, -2.0, 0.2)
	var bridge_waypoint := Vector3(
		bomb_door.global_position.x + 0.4,
		cube.global_position.y,
		bomb_door.global_position.z + 3.2
	)
	var final_waypoint := activator.global_position + Vector3(-0.8, 0.0, -1.1)
	if cube.global_position.distance_to(door_waypoint) > 2.8:
		return door_waypoint
	if cube.global_position.distance_to(bridge_waypoint) > 2.4:
		return bridge_waypoint
	if cube.global_position.distance_to(final_waypoint) > 2.0:
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
