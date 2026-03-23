extends Control

signal start_server
signal connect_client

@export var hide_ui_and_connect: bool
@onready var _server_status_label: Label = $InGameUI/ServerStatus
@onready var _match_timer_label: Label = get_node_or_null("InGameUI/MatchTimer") as Label
@onready var _connection: Connection = get_node("../Connection") as Connection
@onready var _match_director: Node = get_node_or_null("../MatchDirector")
@onready var _network_stats_label: Label = get_node_or_null("InGameUI/NetworkStats") as Label
@onready var _player_inventory_panel: Control = get_node_or_null("InGameUI/PlayerInventoryPanel") as Control
@onready var _external_inventory_panel: Control = get_node_or_null("InGameUI/TargetInventoryPanel") as Control
@onready var _player_list_margin: Control = get_node_or_null("InGameUI/MarginContainer") as Control
@onready var _inventory_toggle_button: Button = get_node_or_null("InGameUI/InventoryToggleButton") as Button
@onready var _inventory_toggle_hint: Label = get_node_or_null("InGameUI/InventoryToggleHint") as Label
@onready var _match_result_backdrop: ColorRect = get_node_or_null("InGameUI/MatchResultBackdrop") as ColorRect
@onready var _match_result_banner: Label = get_node_or_null("InGameUI/MatchResultBanner") as Label

var _connection_status_text := "SERVER STATUS\nreason: startup\nclients_connected: 0\nclient_ids: []"
var _match_status_text := "MATCH\nstate: LOBBY\ntime_left: 0.0s\nplayers: 0\nscore:"
var _is_exiting_client := false
var _is_exiting_server := false
var _player_selected_slot := 0
var _external_selected_slot := 0
var _ui_test_result_written := false


func _ready():
	_connection.server_status_changed.connect(_on_server_status_changed)
	_connection.network_stats_changed.connect(_on_network_stats_changed)
	if is_instance_valid(_match_director) and _match_director.has_signal("snapshot_changed"):
		_match_director.snapshot_changed.connect(_on_match_snapshot_changed)
		if _match_director.has_method("get_snapshot_text"):
			_match_status_text = _match_director.get_snapshot_text()
	_update_server_status_label()
	_update_match_timer_label()
	_update_network_stats_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	if is_instance_valid(_player_inventory_panel):
		_player_inventory_panel.slot_action_requested.connect(_on_player_inventory_action_requested)
		_player_inventory_panel.slot_selected.connect(_on_player_slot_selected)
	if is_instance_valid(_external_inventory_panel):
		_external_inventory_panel.slot_action_requested.connect(_on_external_inventory_action_requested)
		_external_inventory_panel.slot_selected.connect(_on_external_slot_selected)
	if is_instance_valid(_inventory_toggle_button):
		_inventory_toggle_button.pressed.connect(_on_inventory_toggle_button_pressed)

	if Connection.is_server(): return

	var auto_role := OS.get_environment("UI_TEST_AUTO_ROLE").strip_edges().to_lower()
	if auto_role == "server":
		start_server_emit()
		return
	if auto_role == "client":
		connect_client_emit()
		return
	
	if hide_ui_and_connect:
		connect_client_emit()
	else:
		show_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_ESCAPE:
		return
	var local_player := _get_local_player()
	if local_player != null and local_player.is_inventory_mode_open():
		local_player.set_inventory_mode_open(false)
		return
	if _is_server_instance():
		if _is_exiting_server:
			return
		_is_exiting_server = true
		_exit_server()
		return
	if _is_exiting_client:
		return
	if not Connection.is_peer_connected:
		return
	_is_exiting_client = true
	_exit_client()


func _process(_delta: float) -> void:
	_refresh_inventory_panels()


func start_server_emit() -> void:
	start_server.emit()
	$MainMenu.visible = false
	$InGameUI.visible = true
	_refresh_server_status_visibility()


func connect_client_emit() -> void:
	connect_client.emit()
	hide_ui()


func hide_ui() -> void:
	$MainMenu.visible = false
	$InGameUI.visible = true
	_refresh_server_status_visibility()


func show_ui() -> void:
	$MainMenu.visible = true
	$InGameUI.visible = false
	_refresh_server_status_visibility()


func _on_server_status_changed(status_text: String) -> void:
	_connection_status_text = status_text
	_update_server_status_label()
	_update_match_timer_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	_try_write_ui_test_result()


func _on_match_snapshot_changed(status_text: String) -> void:
	_match_status_text = status_text
	_update_server_status_label()
	_update_match_timer_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	_try_write_ui_test_result()


func _on_network_stats_changed(_stats_text: String) -> void:
	_update_network_stats_label()


func _refresh_server_status_visibility() -> void:
	_server_status_label.visible = _is_server_instance() and $InGameUI.visible
	if is_instance_valid(_match_timer_label):
		_match_timer_label.visible = $InGameUI.visible
	if is_instance_valid(_network_stats_label):
		_network_stats_label.visible = $InGameUI.visible
	if is_instance_valid(_player_inventory_panel):
		var local_player := _get_local_player()
		var inventory_open := local_player != null and local_player.is_inventory_mode_open()
		_player_inventory_panel.visible = $InGameUI.visible and inventory_open
		_player_inventory_panel.z_index = 20
	if is_instance_valid(_external_inventory_panel) and not $InGameUI.visible:
		_external_inventory_panel.visible = false
	elif is_instance_valid(_external_inventory_panel):
		_external_inventory_panel.z_index = 20
	if is_instance_valid(_player_list_margin):
		var local_player := _get_local_player()
		var inventory_open := local_player != null and local_player.is_inventory_mode_open()
		_player_list_margin.visible = $InGameUI.visible and not inventory_open
	if is_instance_valid(_inventory_toggle_button):
		var local_player := _get_local_player()
		var inventory_open := local_player != null and local_player.is_inventory_mode_open()
		_inventory_toggle_button.visible = $InGameUI.visible
		_inventory_toggle_button.text = "Fermer sac" if inventory_open else "Sac"
	if is_instance_valid(_inventory_toggle_hint):
		_inventory_toggle_hint.visible = $InGameUI.visible
		_inventory_toggle_hint.text = "Touche I"
	if is_instance_valid(_match_result_banner):
		_match_result_banner.visible = $InGameUI.visible and not _match_result_banner.text.is_empty()
	if is_instance_valid(_match_result_backdrop):
		_match_result_backdrop.visible = $InGameUI.visible and is_instance_valid(_match_result_banner) and not _match_result_banner.text.is_empty()


func _update_server_status_label() -> void:
	_server_status_label.text = _connection_status_text + "\n\n" + _match_status_text


func _update_match_timer_label() -> void:
	if not is_instance_valid(_match_timer_label):
		return
	var seconds_left: float = _extract_time_left_seconds(_match_status_text)
	var state_name: String = _extract_state_name(_match_status_text)
	var total_seconds: int = maxi(0, int(ceil(seconds_left)))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	_match_timer_label.text = "%s %02d:%02d" % [state_name, minutes, seconds]


func _update_network_stats_label() -> void:
	if not is_instance_valid(_network_stats_label):
		return
	_network_stats_label.text = _connection.get_network_stats_text()


func _update_match_result_banner() -> void:
	if not is_instance_valid(_match_result_banner):
		return
	var state_name := _extract_state_name(_match_status_text)
	match state_name:
		"WON":
			_match_result_banner.text = "MISSION REUSSIE"
			_match_result_banner.modulate = Color(0.85, 1.0, 0.86, 1.0)
			if is_instance_valid(_match_result_backdrop):
				_match_result_backdrop.color = Color(0.08, 0.42, 0.16, 0.82)
		"LOST":
			_match_result_banner.text = "MISSION ECHOUEE"
			_match_result_banner.modulate = Color(1.0, 0.82, 0.82, 1.0)
			if is_instance_valid(_match_result_backdrop):
				_match_result_backdrop.color = Color(0.46, 0.12, 0.12, 0.82)
		_:
			_match_result_banner.text = ""
			if is_instance_valid(_match_result_backdrop):
				_match_result_backdrop.color = Color(0, 0, 0, 0)
	_match_result_banner.visible = $InGameUI.visible and not _match_result_banner.text.is_empty()
	if is_instance_valid(_match_result_backdrop):
		_match_result_backdrop.visible = $InGameUI.visible and not _match_result_banner.text.is_empty()


func _try_write_ui_test_result() -> void:
	if _ui_test_result_written:
		return
	var scenario := OS.get_environment("UI_TEST_SCENARIO").strip_edges().to_lower()
	if scenario != "cube_mission":
		return
	var role := OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().to_lower()
	var sync_dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if role.is_empty() or sync_dir.is_empty():
		return
	var state_name := _extract_state_name(_match_status_text)
	if state_name != "WON" and state_name != "LOST":
		return
	var file := FileAccess.open("%s/cube_mission_ui_%s.json" % [sync_dir, role], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"state": state_name,
		"banner": _match_result_banner.text if is_instance_valid(_match_result_banner) else "",
		"timer": _match_timer_label.text if is_instance_valid(_match_timer_label) else "",
	}))
	file.close()
	_ui_test_result_written = true
func _extract_time_left_seconds(snapshot_text: String) -> float:
	for line in snapshot_text.split("\n"):
		if not line.begins_with("time_left:"):
			continue
		var value_text := line.trim_prefix("time_left:").strip_edges()
		value_text = value_text.trim_suffix("s")
		return float(value_text)
	return 0.0


func _extract_state_name(snapshot_text: String) -> String:
	for line in snapshot_text.split("\n"):
		if not line.begins_with("state:"):
			continue
		return line.trim_prefix("state:").strip_edges()
	return "LOBBY"


func _exit_client() -> void:
	_connection.disconnect_peer()
	# Hide immediately to avoid a frozen gray frame while quitting.
	get_window().visible = false
	await get_tree().process_frame
	get_tree().quit()


func _exit_server() -> void:
	await _connection.shutdown_server()
	get_window().visible = false
	await get_tree().process_frame
	get_tree().quit()


func _is_server_instance() -> bool:
	return multiplayer.is_server()


func _refresh_inventory_panels() -> void:
	if not is_instance_valid(_player_inventory_panel):
		return
	var local_player := _get_local_player()
	if local_player == null:
		_player_inventory_panel.set_panel_state("Sac", [], [], "I ouvre/ferme l'inventaire")
		if is_instance_valid(_external_inventory_panel):
			_external_inventory_panel.visible = false
		return
	if not local_player.is_inventory_mode_open():
		_player_inventory_panel.visible = false
		if is_instance_valid(_external_inventory_panel):
			_external_inventory_panel.visible = false
		return
	_player_inventory_panel.visible = true
	var player_actions: Array[Dictionary] = [{"id": "drop", "label": "Deposer"}]
	var player_hint := "Clique un slot puis choisis une action"
	if local_player.has_focused_inventory_target():
		player_actions.append({"id": "give", "label": "Vers cible"})
		player_hint = "Cible active: transfert sac <-> coffre/joueur"
	_player_inventory_panel.set_panel_state(local_player.get_inventory_display_name(), local_player.get_inventory_contents(), player_actions, player_hint, _player_selected_slot)
	var external_name := local_player.get_target_inventory_display_name()
	var external_contents := local_player.get_target_inventory_contents()
	if not is_instance_valid(_external_inventory_panel):
		return
	if external_name.is_empty():
		_external_inventory_panel.visible = false
		return
	_external_inventory_panel.visible = true
	_external_inventory_panel.set_panel_state(external_name, external_contents, [{"id": "take", "label": "Prendre"}], "Selectionne un slot de l'inventaire externe puis clique", _external_selected_slot)
	# Hook test UI : écrire le contenu vu du coffre pour assertions de synchro multijoueur.
	var sync_dir := OS.get_environment("UI_TEST_CHEST_SYNC_DIR")
	var role := OS.get_environment("UI_TEST_INSTANCE_ROLE")
	if not sync_dir.is_empty() and not role.is_empty():
		var path := sync_dir + "/chest_" + role + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(external_contents))
			file.close()


func _get_local_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node as Player
	return null


func _on_player_inventory_action_requested(action_id: String, slot_index: int) -> void:
	var local_player := _get_local_player()
	if local_player == null:
		return
	match action_id:
		"drop":
			local_player.request_drop_inventory_slot(slot_index)
		"give":
			local_player.request_transfer_to_target(slot_index)


func _on_external_inventory_action_requested(action_id: String, slot_index: int) -> void:
	var local_player := _get_local_player()
	if local_player == null:
		return
	if action_id == "take":
		local_player.request_transfer_from_target(slot_index)


func _on_player_slot_selected(slot_index: int) -> void:
	_player_selected_slot = slot_index


func _on_external_slot_selected(slot_index: int) -> void:
	_external_selected_slot = slot_index


func _on_inventory_toggle_button_pressed() -> void:
	var local_player := _get_local_player()
	if local_player == null:
		return
	local_player.toggle_inventory_mode()
