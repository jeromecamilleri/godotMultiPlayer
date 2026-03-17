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
		"inventory_proximity":
			_setup_inventory_proximity_scenario(player)


func process(player) -> void:
	match _scenario_name:
		"transfer":
			_update_transfer_scenario(player)
		"inventory_proximity":
			_update_inventory_proximity_scenario(player)


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


func _store_proximity_snapshot(player, other, key: String) -> void:
	_proximity[key] = {
		"has_target": player.has_focused_inventory_target(),
		"target_name": player.get_target_inventory_display_name(),
		"distance": (other.global_position - player.global_position).length(),
	}


func _write_proximity_result(result: Dictionary) -> void:
	if bool(_proximity["written"]):
		return
	var dir := OS.get_environment("UI_TEST_CHEST_SYNC_DIR").strip_edges()
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
