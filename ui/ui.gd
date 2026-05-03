extends Control

signal start_server
signal connect_client

@export var hide_ui_and_connect: bool
@onready var _server_status_label: Label = $InGameUI/ServerStatus
@onready var _match_timer_label: Label = get_node_or_null("InGameUI/MatchTimer") as Label
@onready var _player_stats_label: Label = get_node_or_null("InGameUI/PlayerStats") as Label
@onready var _connection: Connection = get_node("../Connection") as Connection
@onready var _match_director: Node = get_node_or_null("../MatchDirector")
@onready var _network_stats_label: Label = get_node_or_null("InGameUI/NetworkStats") as Label
@onready var _endpoint_reminder_label: Label = get_node_or_null("InGameUI/EndpointReminder") as Label
@onready var _server_black_backdrop: ColorRect = get_node_or_null("InGameUI/ServerBlackBackdrop") as ColorRect
@onready var _server_hud_backdrop: Control = get_node_or_null("InGameUI/ServerHudBackdrop") as Control
@onready var _server_match_stats_label: Label = get_node_or_null("InGameUI/ServerMatchStats") as Label
@onready var _server_client_stats_label: Label = get_node_or_null("InGameUI/ServerClientStats") as Label
@onready var _server_player_stats_label: Label = get_node_or_null("InGameUI/ServerPlayerStats") as Label
@onready var _debug_overlay_backdrop: Control = get_node_or_null("InGameUI/DebugOverlayBackdrop") as Control
@onready var _debug_overlay_label: Label = get_node_or_null("InGameUI/DebugOverlayLabel") as Label
@onready var _mission_tracker_backdrop: ColorRect = get_node_or_null("InGameUI/MissionTrackerBackdrop") as ColorRect
@onready var _mission_tracker_title: Label = get_node_or_null("InGameUI/MissionTrackerTitle") as Label
@onready var _mission_tracker_body: Label = get_node_or_null("InGameUI/MissionTrackerBody") as Label
@onready var _mission_event_backdrop: ColorRect = get_node_or_null("InGameUI/MissionEventBackdrop") as ColorRect
@onready var _mission_event_label: Label = get_node_or_null("InGameUI/MissionEventLabel") as Label
@onready var _mission_event_sfx: AudioStreamPlayer = get_node_or_null("InGameUI/MissionEventSfx") as AudioStreamPlayer
@onready var _context_hint_backdrop: ColorRect = get_node_or_null("InGameUI/ContextHintBackdrop") as ColorRect
@onready var _context_hint_label: Label = get_node_or_null("InGameUI/ContextHintLabel") as Label
@onready var _player_inventory_panel: Control = get_node_or_null("InGameUI/PlayerInventoryPanel") as Control
@onready var _external_inventory_panel: Control = get_node_or_null("InGameUI/TargetInventoryPanel") as Control
@onready var _inventory_toggle_button: Button = get_node_or_null("InGameUI/InventoryToggleButton") as Button
@onready var _inventory_toggle_hint: Label = get_node_or_null("InGameUI/InventoryToggleHint") as Label
@onready var _match_result_backdrop: ColorRect = get_node_or_null("InGameUI/MatchResultBackdrop") as ColorRect
@onready var _match_result_banner: Label = get_node_or_null("InGameUI/MatchResultBanner") as Label
@onready var _user_data_manager: UserDataManager = get_node_or_null("../UserDataManager") as UserDataManager
@onready var _player_name_edit: LineEdit = get_node_or_null("MainMenu/Buttons/PlayerNameConfig/PlayerNameEdit") as LineEdit
@onready var _server_ip_edit: LineEdit = get_node_or_null("MainMenu/Buttons/EndpointConfig/ServerIpEdit") as LineEdit
@onready var _server_port_spinbox: SpinBox = get_node_or_null("MainMenu/Buttons/EndpointConfig/ServerPortSpinBox") as SpinBox
@onready var _main_menu: Control = $MainMenu
@onready var _server_button: Button = get_node_or_null("MainMenu/Buttons/Server") as Button
@onready var _client_button: Button = get_node_or_null("MainMenu/Buttons/Client") as Button

var _connection_status_text := "SERVER STATUS\nreason: startup\nclients_connected: 0\nclient_ids: []"
var _match_status_text := "MATCH\nstate: LOBBY\ntime_left: 0.0s\nplayers: 0\nscore:"
var _is_exiting_client := false
var _is_exiting_server := false
var _player_selected_slot := 0
var _external_selected_slot := 0
var _ui_test_result_written := false
var _last_ui_test_layout_signature := ""
var _debug_overlay_enabled := false
var _last_objectives: Dictionary = {}
var _mission_event_hide_at_ms := 0


func _ready():
	_register_test_ids()
	_connection.server_status_changed.connect(_on_server_status_changed)
	_connection.network_stats_changed.connect(_on_network_stats_changed)
	if is_instance_valid(_match_director) and _match_director.has_signal("snapshot_changed"):
		_match_director.snapshot_changed.connect(_on_match_snapshot_changed)
		if _match_director.has_method("get_snapshot_text"):
			_match_status_text = _match_director.get_snapshot_text()
	_update_server_status_label()
	_update_match_timer_label()
	_update_player_stats_label()
	_update_network_stats_label()
	_update_endpoint_reminder_label()
	_update_server_match_stats_label()
	_update_server_client_stats_label()
	_update_server_player_stats_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	_last_objectives = _extract_objectives_map()
	_update_mission_tracker()
	_update_context_hint()
	_sync_main_menu_endpoint_fields()
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
	if key_event.keycode == KEY_F1:
		_debug_overlay_enabled = not _debug_overlay_enabled
		_refresh_server_status_visibility()
		_update_debug_overlay()
		get_viewport().set_input_as_handled()
		return
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
	_update_player_stats_label()
	_update_debug_overlay()
	_update_mission_event_toast()
	_update_context_hint()
	_write_ui_test_layout_snapshot()
	_write_portal_unlock_ui_test_state()


func start_server_emit() -> void:
	_apply_main_menu_endpoint_config()
	_apply_main_menu_player_name_config()
	start_server.emit()
	$MainMenu.visible = false
	$InGameUI.visible = true
	_refresh_server_status_visibility()


func connect_client_emit() -> void:
	_apply_main_menu_endpoint_config()
	_apply_main_menu_player_name_config()
	connect_client.emit()
	hide_ui()


func hide_ui() -> void:
	$MainMenu.visible = false
	$InGameUI.visible = true
	_refresh_server_status_visibility()


func show_ui() -> void:
	$MainMenu.visible = true
	$InGameUI.visible = false
	_sync_main_menu_endpoint_fields()
	_refresh_server_status_visibility()


func _on_server_status_changed(status_text: String) -> void:
	_connection_status_text = status_text
	_update_server_status_label()
	_update_match_timer_label()
	_update_player_stats_label()
	_update_endpoint_reminder_label()
	_update_server_match_stats_label()
	_update_server_client_stats_label()
	_update_server_player_stats_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	_try_write_ui_test_result()


func _on_match_snapshot_changed(status_text: String) -> void:
	var previous_objectives := _extract_objectives_map()
	_match_status_text = status_text
	_update_server_status_label()
	_update_match_timer_label()
	_update_endpoint_reminder_label()
	_update_server_match_stats_label()
	_update_server_player_stats_label()
	_refresh_server_status_visibility()
	_update_match_result_banner()
	_update_mission_tracker()
	_process_mission_progress_events(previous_objectives, _extract_objectives_map())
	_try_write_ui_test_result()


func _on_network_stats_changed(_stats_text: String) -> void:
	_update_network_stats_label()
	_update_endpoint_reminder_label()
	_update_server_match_stats_label()
	_update_server_client_stats_label()
	_update_server_player_stats_label()


func _refresh_server_status_visibility() -> void:
	_server_status_label.visible = _is_server_instance() and $InGameUI.visible
	if is_instance_valid(_match_timer_label):
		_match_timer_label.visible = $InGameUI.visible and not _is_server_instance()
		_match_timer_label.z_index = 10
	if is_instance_valid(_player_stats_label):
		_player_stats_label.visible = $InGameUI.visible and not _is_server_instance()
		_player_stats_label.z_index = 10
	if is_instance_valid(_mission_tracker_backdrop):
		_mission_tracker_backdrop.visible = $InGameUI.visible and not _is_server_instance()
	if is_instance_valid(_mission_tracker_title):
		_mission_tracker_title.visible = $InGameUI.visible and not _is_server_instance()
	if is_instance_valid(_mission_tracker_body):
		_mission_tracker_body.visible = $InGameUI.visible and not _is_server_instance()
	if is_instance_valid(_network_stats_label):
		_network_stats_label.visible = false
	if is_instance_valid(_endpoint_reminder_label):
		_endpoint_reminder_label.visible = $InGameUI.visible
	if is_instance_valid(_server_black_backdrop):
		_server_black_backdrop.visible = $InGameUI.visible and _is_server_instance()
	if is_instance_valid(_server_hud_backdrop):
		_server_hud_backdrop.visible = $InGameUI.visible and _is_server_instance()
	if is_instance_valid(_server_match_stats_label):
		_server_match_stats_label.visible = $InGameUI.visible and _is_server_instance()
	if is_instance_valid(_server_client_stats_label):
		_server_client_stats_label.visible = $InGameUI.visible and _is_server_instance()
	if is_instance_valid(_server_player_stats_label):
		_server_player_stats_label.visible = $InGameUI.visible and _is_server_instance()
	if is_instance_valid(_debug_overlay_backdrop):
		_debug_overlay_backdrop.visible = $InGameUI.visible and _debug_overlay_enabled
	if is_instance_valid(_debug_overlay_label):
		_debug_overlay_label.visible = $InGameUI.visible and _debug_overlay_enabled
	if is_instance_valid(_mission_event_backdrop):
		_mission_event_backdrop.visible = $InGameUI.visible and not _is_server_instance() and Time.get_ticks_msec() < _mission_event_hide_at_ms
	if is_instance_valid(_mission_event_label):
		_mission_event_label.visible = $InGameUI.visible and not _is_server_instance() and Time.get_ticks_msec() < _mission_event_hide_at_ms and not _mission_event_label.text.is_empty()
	if is_instance_valid(_context_hint_backdrop):
		_context_hint_backdrop.visible = $InGameUI.visible and not _is_server_instance() and is_instance_valid(_context_hint_label) and not _context_hint_label.text.is_empty()
	if is_instance_valid(_context_hint_label):
		_context_hint_label.visible = $InGameUI.visible and not _is_server_instance() and not _context_hint_label.text.is_empty()
	if is_instance_valid(_player_inventory_panel):
		var local_player := _get_local_player()
		var inventory_open := local_player != null and local_player.is_inventory_mode_open()
		_player_inventory_panel.visible = $InGameUI.visible and inventory_open
		_player_inventory_panel.z_index = 20
	if is_instance_valid(_external_inventory_panel) and not $InGameUI.visible:
		_external_inventory_panel.visible = false
	elif is_instance_valid(_external_inventory_panel):
		_external_inventory_panel.z_index = 20
	if is_instance_valid(_inventory_toggle_button):
		var local_player := _get_local_player()
		var inventory_open := local_player != null and local_player.is_inventory_mode_open()
		_inventory_toggle_button.visible = $InGameUI.visible and not _is_server_instance()
		_inventory_toggle_button.text = "Fermer sac" if inventory_open else "Sac"
	if is_instance_valid(_inventory_toggle_hint):
		_inventory_toggle_hint.visible = $InGameUI.visible and not _is_server_instance()
		_inventory_toggle_hint.text = "Touche I"
	if is_instance_valid(_match_result_banner):
		_match_result_banner.visible = $InGameUI.visible and not _match_result_banner.text.is_empty()
	if is_instance_valid(_match_result_backdrop):
		_match_result_backdrop.visible = $InGameUI.visible and is_instance_valid(_match_result_banner) and not _match_result_banner.text.is_empty()


func _update_server_status_label() -> void:
	_server_status_label.text = _connection_status_text


func _update_match_timer_label() -> void:
	if not is_instance_valid(_match_timer_label):
		return
	var seconds_left: float = _extract_time_left_seconds(_match_status_text)
	var state_name: String = _extract_state_name(_match_status_text)
	var total_seconds: int = maxi(0, int(ceil(seconds_left)))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	_match_timer_label.text = "%s %02d:%02d" % [state_name, minutes, seconds]


func _update_player_stats_label() -> void:
	if not is_instance_valid(_player_stats_label):
		return
	_player_stats_label.text = _format_local_player_stats_text()


func _update_network_stats_label() -> void:
	if not is_instance_valid(_network_stats_label):
		return
	_network_stats_label.text = _connection.get_network_stats_text()


func _update_mission_tracker() -> void:
	if not is_instance_valid(_mission_tracker_title) or not is_instance_valid(_mission_tracker_body):
		return
	var phase_data := _build_mission_phase_data()
	_mission_tracker_title.text = String(phase_data.get("title", "MISSION"))
	_mission_tracker_body.text = String(phase_data.get("body", ""))


func _build_mission_phase_data() -> Dictionary:
	# The client renders mission guidance from server snapshot values only.
	var objectives := _extract_objectives_map()
	var state_name := _extract_state_name(_match_status_text)
	var result_reason := _extract_result_reason(_match_status_text)
	var required_wood := _objective_int(objectives, "required_wood", 4)
	var required_apples := _objective_int(objectives, "required_apples", 2)
	var delivered_wood := _objective_int(objectives, "chest_wood_delivered", 0)
	var delivered_apples := _objective_int(objectives, "chest_apples_delivered", 0)
	var required_bomb_doors := _objective_int(objectives, "required_bomb_doors", 0)
	var opened_bomb_doors := _objective_int(objectives, "bomb_door_opened", 0)
	var mission_phase := _objective_int(objectives, "mission_phase", 1)
	var portal_breche_unlocked := _objective_int(objectives, "portal_breche_unlocked", 0) > 0
	var portal_reactor_unlocked := _objective_int(objectives, "portal_reactor_unlocked", 0) > 0
	var cube_goal_reached := _objective_int(objectives, "cube_activator_reached", 0) > 0

	if state_name == "WON" and (cube_goal_reached or result_reason == "cube_activator_reached"):
		var team_score := _extract_snapshot_value("team_score")
		return {
			"title": "MISSION ACCOMPLIE",
			"body": "Le cube est sur l'Activator.\nScore equipe: %s\nExfiltration ou nouvelle partie." % team_score,
		}

	if mission_phase <= 1:
		var remaining_wood := maxi(0, required_wood - delivered_wood)
		var remaining_apples := maxi(0, required_apples - delivered_apples)
		return {
			"title": "PHASE 1 - COLLECTE",
			"body": "Deposez au coffre du hub:\nBois %d/%d (reste %d)\nPommes %d/%d (reste %d)\nPortail BRECHE: %s" % [
				delivered_wood,
				required_wood,
				remaining_wood,
				delivered_apples,
				required_apples,
				remaining_apples,
				"OUVERT" if portal_breche_unlocked else "BLOQUE",
			],
		}

	if mission_phase == 2:
		var door_goal := maxi(1, required_bomb_doors)
		return {
			"title": "PHASE 2 - BRECHE",
			"body": "Ouvrez les BombDoor avec des bombes:\nBombDoor %d/%d\nPortail REACTOR: %s" % [
				opened_bomb_doors,
				door_goal,
				"OUVERT" if portal_reactor_unlocked else "BLOQUE",
			],
		}

	if mission_phase >= 3 and not cube_goal_reached:
		return {
			"title": "PHASE 3 - REACTOR",
			"body": "Poussez le gros cube vers l'Activator.\nMaintenez la poussee a plusieurs pour stabiliser le mouvement.",
		}

	return {
		"title": "MISSION",
		"body": "Objectifs en cours...",
	}


func _extract_result_reason(snapshot_text: String) -> String:
	for raw_line in snapshot_text.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("result_reason:"):
			return line.trim_prefix("result_reason:").strip_edges()
	return ""


func _extract_objectives_map() -> Dictionary:
	var values: Dictionary = {}
	var in_objectives := false
	# Parse the textual snapshot section produced by MatchDirector.get_snapshot_text().
	for raw_line in _match_status_text.split("\n"):
		var line := raw_line.strip_edges()
		if line == "objectives:":
			in_objectives = true
			continue
		if not in_objectives:
			continue
		if line.is_empty():
			continue
		if not line.contains(":"):
			continue
		var parts := line.split(":")
		if parts.size() < 2:
			continue
		var key := String(parts[0]).strip_edges()
		var value_text := String(parts[1]).strip_edges()
		values[key] = value_text
	return values


func _objective_int(objectives: Dictionary, key: String, default_value: int = 0) -> int:
	if not objectives.has(key):
		return default_value
	var value := String(objectives.get(key, str(default_value))).strip_edges()
	if not value.is_valid_int():
		return default_value
	return int(value)


func _process_mission_progress_events(previous_objectives: Dictionary, current_objectives: Dictionary) -> void:
	# Keep one "important" toast per snapshot transition to avoid noisy stacking.
	var previous_phase := _objective_int(previous_objectives, "mission_phase", 1)
	var current_phase := _objective_int(current_objectives, "mission_phase", previous_phase)
	var important_event := ""
	if current_phase > previous_phase:
		match current_phase:
			2:
				important_event = "Phase 2 debloquee: direction la BRECHE."
			3:
				important_event = "Phase 3 debloquee: portail REACTOR actif."
			4:
				important_event = "Objectif final valide: cube sur Activator."
			_:
				important_event = "Nouvelle phase mission: %d" % current_phase

	var prev_breche := _objective_int(previous_objectives, "portal_breche_unlocked", 0)
	var curr_breche := _objective_int(current_objectives, "portal_breche_unlocked", prev_breche)
	if important_event.is_empty() and prev_breche == 0 and curr_breche == 1:
		important_event = "Portail BRECHE ouvert."

	var prev_reactor := _objective_int(previous_objectives, "portal_reactor_unlocked", 0)
	var curr_reactor := _objective_int(current_objectives, "portal_reactor_unlocked", prev_reactor)
	if important_event.is_empty() and prev_reactor == 0 and curr_reactor == 1:
		important_event = "Portail REACTOR ouvert."

	if not important_event.is_empty():
		_show_mission_event(important_event, true)

	var prev_wood := _objective_int(previous_objectives, "chest_wood_delivered", 0)
	var curr_wood := _objective_int(current_objectives, "chest_wood_delivered", prev_wood)
	if important_event.is_empty() and curr_wood > prev_wood:
		_show_mission_event("Depot coffre: +%d bois." % (curr_wood - prev_wood), false)

	var prev_apples := _objective_int(previous_objectives, "chest_apples_delivered", 0)
	var curr_apples := _objective_int(current_objectives, "chest_apples_delivered", prev_apples)
	if important_event.is_empty() and curr_apples > prev_apples:
		_show_mission_event("Depot coffre: +%d pomme(s)." % (curr_apples - prev_apples), false)

	_last_objectives = current_objectives.duplicate(true)


func _show_mission_event(text: String, play_sound: bool = true) -> void:
	if not is_instance_valid(_mission_event_label):
		return
	_mission_event_label.text = text
	_mission_event_hide_at_ms = Time.get_ticks_msec() + 2800
	if play_sound and is_instance_valid(_mission_event_sfx):
		_mission_event_sfx.play()
	_refresh_server_status_visibility()


func _update_mission_event_toast() -> void:
	if _mission_event_hide_at_ms <= 0:
		return
	if Time.get_ticks_msec() < _mission_event_hide_at_ms:
		return
	_mission_event_hide_at_ms = 0
	if is_instance_valid(_mission_event_label):
		_mission_event_label.text = ""
	_refresh_server_status_visibility()


func _update_context_hint() -> void:
	if not is_instance_valid(_context_hint_label):
		return
	var hint := ""
	if not _is_server_instance():
		var player := _get_local_player()
		if player != null:
			hint = _build_context_hint(player)
	_context_hint_label.text = hint
	_refresh_server_status_visibility()


func _build_context_hint(player: Player) -> String:
	# Local proximity hint only; gameplay validation remains server-authoritative.
	var chest := get_tree().get_first_node_in_group("mission_hub_chests") as Node3D
	if is_instance_valid(chest):
		var chest_distance := player.global_position.distance_to(chest.global_position)
		if chest_distance <= 5.0:
			if player.has_focused_inventory_target():
				var target := player.get_focused_inventory_target()
				if target == chest:
					return "Coffre cible: appuyez sur I puis transferez vos objets."
			return "Objectif collecte: approchez du coffre puis appuyez sur I."
	var cube := get_tree().get_first_node_in_group("mission_cube_primary") as Node3D
	var activator := get_tree().get_first_node_in_group("mission_cube_goal_zones") as Node3D
	if is_instance_valid(cube):
		var cube_distance := player.global_position.distance_to(cube.global_position)
		if cube_distance <= 9.0:
			var target_name := "l'Activator"
			if is_instance_valid(activator):
				target_name = "la zone Activator"
			return "Devant le cube, maintenez le clic gauche pour pousser vers %s." % target_name
	return ""


func _update_endpoint_reminder_label() -> void:
	if not is_instance_valid(_endpoint_reminder_label):
		return
	var prefix := "Serveur" if _is_server_instance() else "Connexion"
	_endpoint_reminder_label.text = "%s: %s" % [prefix, _connection.get_runtime_endpoint_display()]


func _update_server_match_stats_label() -> void:
	if not is_instance_valid(_server_match_stats_label):
		return
	if not _is_server_instance():
		_server_match_stats_label.text = ""
		return
	_server_match_stats_label.text = _format_match_status_for_hud()


func _update_server_client_stats_label() -> void:
	if not is_instance_valid(_server_client_stats_label):
		return
	if not _is_server_instance():
		_server_client_stats_label.text = ""
		return
	_server_client_stats_label.text = "RESEAU CLIENTS\n" + _connection.get_server_client_network_stats_text()


func _update_server_player_stats_label() -> void:
	if not is_instance_valid(_server_player_stats_label):
		return
	if not _is_server_instance():
		_server_player_stats_label.text = ""
		return
	_server_player_stats_label.text = _format_server_player_stats()


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
	if scenario != "cube_mission" and scenario != "cube_mission_lock":
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


func _write_portal_unlock_ui_test_state() -> void:
	var scenario := OS.get_environment("UI_TEST_SCENARIO").strip_edges().to_lower()
	if scenario != "portal_unlock":
		return
	var role := OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().to_lower()
	if role.is_empty():
		return
	var sync_dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if sync_dir.is_empty():
		return
	var breche_portal := get_tree().get_first_node_in_group("mission_portal_hub_breche")
	var reactor_portal := get_tree().get_first_node_in_group("mission_portal_hub_reactor")
	var chest := get_tree().get_first_node_in_group("mission_hub_chests")
	if not is_instance_valid(breche_portal) or not is_instance_valid(reactor_portal) or not is_instance_valid(chest):
		return
	if not breche_portal.has_method("is_portal_active") or not reactor_portal.has_method("is_portal_active"):
		return
	if not chest.has_method("get_inventory_component"):
		return
	var inventory = chest.call("get_inventory_component")
	if inventory == null:
		return
	var chest_wood: int = int(inventory.call("count_item", "wood"))
	var chest_apple: int = int(inventory.call("count_item", "apple"))
	var file_name := "portal_unlock_server.json" if role == "server" else "portal_unlock_%s.json" % role
	var file := FileAccess.open("%s/%s" % [sync_dir, file_name], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"state": _extract_state_name(_match_status_text),
		"portal_breche_active": bool(breche_portal.call("is_portal_active")),
		"portal_reactor_active": bool(reactor_portal.call("is_portal_active")),
		"chest_wood": chest_wood,
		"chest_apple": chest_apple,
		"chest_wood_delivered": maxi(0, chest_wood - 6),
		"chest_apple_delivered": maxi(0, chest_apple - 2),
	}))
	file.close()


func _register_test_ids() -> void:
	if is_instance_valid(_main_menu):
		_main_menu.set_meta("test_id", "main_menu")
	if is_instance_valid(_server_ip_edit):
		_server_ip_edit.set_meta("test_id", "server_ip_input")
	if is_instance_valid(_server_port_spinbox):
		_server_port_spinbox.set_meta("test_id", "server_port_input")
	if is_instance_valid(_server_button):
		_server_button.set_meta("test_id", "start_server_button")
	if is_instance_valid(_client_button):
		_client_button.set_meta("test_id", "start_client_button")
	if is_instance_valid(_player_name_edit):
		_player_name_edit.set_meta("test_id", "player_name_input")
	if is_instance_valid(_endpoint_reminder_label):
		_endpoint_reminder_label.set_meta("test_id", "endpoint_reminder")
	if is_instance_valid(_inventory_toggle_button):
		_inventory_toggle_button.set_meta("test_id", "inventory_toggle_button")
	if is_instance_valid(_inventory_toggle_hint):
		_inventory_toggle_hint.set_meta("test_id", "inventory_toggle_hint")
	if is_instance_valid(_match_timer_label):
		_match_timer_label.set_meta("test_id", "match_timer")
	if is_instance_valid(_mission_tracker_title):
		_mission_tracker_title.set_meta("test_id", "mission_tracker_title")
	if is_instance_valid(_mission_tracker_body):
		_mission_tracker_body.set_meta("test_id", "mission_tracker_body")
	if is_instance_valid(_mission_event_label):
		_mission_event_label.set_meta("test_id", "mission_event_label")
	if is_instance_valid(_context_hint_label):
		_context_hint_label.set_meta("test_id", "context_hint_label")
	if is_instance_valid(_network_stats_label):
		_network_stats_label.set_meta("test_id", "network_stats")
	if is_instance_valid(_match_result_banner):
		_match_result_banner.set_meta("test_id", "match_result_banner")
	if is_instance_valid(_server_status_label):
		_server_status_label.set_meta("test_id", "server_status")
	if is_instance_valid(_server_match_stats_label):
		_server_match_stats_label.set_meta("test_id", "server_match_stats")
	if is_instance_valid(_server_client_stats_label):
		_server_client_stats_label.set_meta("test_id", "server_client_stats")
	if is_instance_valid(_server_player_stats_label):
		_server_player_stats_label.set_meta("test_id", "server_player_stats")
	if is_instance_valid(_player_inventory_panel):
		_player_inventory_panel.set_meta("test_id", "player_inventory_panel")
	if is_instance_valid(_external_inventory_panel):
		_external_inventory_panel.set_meta("test_id", "external_inventory_panel")
	if is_instance_valid(_debug_overlay_label):
		_debug_overlay_label.set_meta("test_id", "debug_overlay")


func _write_ui_test_layout_snapshot() -> void:
	var sync_dir := _get_ui_test_sync_dir()
	if sync_dir.is_empty():
		return
	var role := OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().to_lower()
	if role.is_empty():
		role = "default"
	var payload := {
		"role": role,
		"main_menu_visible": _main_menu.visible if is_instance_valid(_main_menu) else false,
		"in_game_visible": $InGameUI.visible,
		"controls": _collect_test_controls(),
	}
	var signature := JSON.stringify(payload)
	if signature == _last_ui_test_layout_signature:
		return
	_last_ui_test_layout_signature = signature
	var file := FileAccess.open("%s/ui_layout_%s.json" % [sync_dir, role], FileAccess.WRITE)
	if file == null:
		return
	file.store_string(signature)
	file.close()


func _collect_test_controls() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_collect_test_controls_from(self, entries)
	return entries


func _collect_test_controls_from(root: Node, entries: Array[Dictionary]) -> void:
	if root is Control:
		var control := root as Control
		if control.has_meta("test_id"):
			entries.append(_serialize_test_control(control))
	for child in root.get_children():
		_collect_test_controls_from(child, entries)


func _serialize_test_control(control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	var text_value := ""
	if control is Button:
		text_value = (control as Button).text
	elif control is Label:
		text_value = (control as Label).text
	elif control is LineEdit:
		text_value = (control as LineEdit).text
	var disabled := false
	if control is BaseButton:
		disabled = (control as BaseButton).disabled
	return {
		"test_id": String(control.get_meta("test_id")),
		"path": str(control.get_path()),
		"visible": control.is_visible_in_tree(),
		"disabled": disabled,
		"text": text_value,
		"x": snappedf(rect.position.x, 0.01),
		"y": snappedf(rect.position.y, 0.01),
		"width": snappedf(rect.size.x, 0.01),
		"height": snappedf(rect.size.y, 0.01),
		"center_x": snappedf(rect.position.x + rect.size.x * 0.5, 0.01),
		"center_y": snappedf(rect.position.y + rect.size.y * 0.5, 0.01),
	}


func _get_ui_test_sync_dir() -> String:
	var sync_dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if not sync_dir.is_empty():
		return sync_dir
	return OS.get_environment("UI_TEST_CHEST_SYNC_DIR").strip_edges()


func _update_debug_overlay() -> void:
	if not is_instance_valid(_debug_overlay_label):
		return
	if not _debug_overlay_enabled or not $InGameUI.visible:
		_debug_overlay_label.text = ""
		return
	_debug_overlay_label.text = _build_debug_overlay_text()


func _build_debug_overlay_text() -> String:
	var sections: Array[String] = []
	sections.append("DEBUG F1")
	sections.append(_build_debug_match_section())
	sections.append(_build_debug_network_section())
	sections.append(_build_debug_inventory_section())
	sections.append(_build_debug_enemy_section())
	sections.append(_build_debug_sync_section())
	return "\n\n".join(sections)


func _build_debug_match_section() -> String:
	var lines: Array[String] = ["MATCH"]
	lines.append("etat=%s" % _extract_state_name(_match_status_text))
	lines.append("chrono=%s" % _format_match_clock())
	lines.append("joueurs=%s" % _extract_snapshot_value("players"))
	lines.append("score equipe=%s" % _extract_snapshot_value("team_score"))
	lines.append("vies=%s" % _format_snapshot_compact_section("lives"))
	lines.append("scores=%s" % _format_snapshot_compact_section("score"))
	lines.append("morts=%s" % _format_snapshot_compact_section("deaths"))
	lines.append("objectifs=%s" % _format_debug_objectives_summary())
	return "\n".join(lines)


func _build_debug_network_section() -> String:
	var lines: Array[String] = ["RESEAU"]
	lines.append(_connection.get_network_stats_text())
	if _is_server_instance():
		lines.append(_connection.get_server_client_network_stats_text())
	return "\n".join(lines)


func _build_debug_inventory_section() -> String:
	var lines: Array[String] = ["INVENTAIRES"]
	var local_player := _get_local_player()
	if local_player == null:
		lines.append("joueur_local=aucun")
	else:
		if local_player.has_method("get_inventory_debug_summary"):
			lines.append(String(local_player.call("get_inventory_debug_summary")))
		else:
			lines.append("resume indisponible")
	var chest: Node = _find_first_inventory_container()
	if is_instance_valid(chest):
		var chest_rev := "-"
		var chest_mode := "-"
		if chest.has_method("get_snapshot_revision"):
			chest_rev = str(chest.call("get_snapshot_revision"))
		if chest.has_method("get_last_sync_mode"):
			chest_mode = String(chest.call("get_last_sync_mode"))
		lines.append("coffre rev=%s mode=%s" % [chest_rev, chest_mode])
	return "\n".join(lines)


func _build_debug_enemy_section() -> String:
	var lines: Array[String] = ["ENNEMIS"]
	var beetle_lines := _collect_beetle_debug_lines()
	var bee_lines := _collect_bee_debug_lines()
	lines.append("scarabees=%d abeilles=%d" % [beetle_lines.size(), bee_lines.size()])
	if beetle_lines.is_empty() and bee_lines.is_empty():
		lines.append("aucun suivi")
		return "\n".join(lines)
	for line in beetle_lines:
		lines.append(line)
	for line in bee_lines:
		lines.append(line)
	return "\n".join(lines)


func _build_debug_sync_section() -> String:
	var lines: Array[String] = ["SYNCS"]
	var sync_nodes: Array[Node] = _collect_replicated_debug_nodes()
	var sync_items: Array[String] = []
	for sync_node in sync_nodes:
		if not sync_node.has_method("get_debug_sync_summary"):
			continue
		sync_items.append(String(sync_node.call("get_debug_sync_summary")))
	if sync_items.is_empty():
		lines.append("aucune mesure")
	else:
		lines.append("objets suivis=%d" % sync_nodes.size())
		for item_summary in sync_items:
			lines.append("- " + item_summary)
	var recent_events: Array[Dictionary] = []
	if _connection.has_method("get_recent_sync_event_entries"):
		recent_events = _connection.get_recent_sync_event_entries()
	if recent_events.is_empty():
		var fallback_events: Array[String] = _connection.get_recent_sync_events()
		for event_text in fallback_events:
			recent_events.append({
				"text": event_text,
			})
	if recent_events.is_empty():
		lines.append("events (0)")
	else:
		lines.append("events (%d)" % recent_events.size())
		for event_entry in recent_events:
			lines.append("- " + String(event_entry.get("text", "")))
	return "\n".join(lines)


func _collect_replicated_debug_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for node in get_tree().get_nodes_in_group("replicated_persistent_objects"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("get_debug_sync_summary"):
			continue
		if node.is_in_group("match_director"):
			continue
		if node.is_in_group("enemy_instances"):
			continue
		nodes.append(node)
	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		var priority_a := _persistent_debug_priority(a)
		var priority_b := _persistent_debug_priority(b)
		if priority_a == priority_b:
			return String(a.name) < String(b.name)
		return priority_a < priority_b
	)
	if nodes.size() > 6:
		nodes.resize(6)
	return nodes


func _persistent_debug_priority(node: Node) -> int:
	if node.is_in_group("bomb_reactives"):
		return 10
	if node.is_in_group("inventory_containers"):
		return 20
	if node.is_in_group("revive_coins"):
		return 30
	if node.is_in_group("world_items"):
		return 40
	if node.is_in_group("mission_cube_primary"):
		return 50
	if node.is_in_group("enemy_directors"):
		return 60
	return 100


func _collect_beetle_debug_lines() -> Array[String]:
	var lines: Array[String] = []
	for node in get_tree().get_nodes_in_group("beetles"):
		if not is_instance_valid(node):
			continue
		var assigned_peer := -1
		var current_peer := -1
		if node.has_method("get_assigned_target_peer_id"):
			assigned_peer = int(node.call("get_assigned_target_peer_id"))
		if node.has_method("get_current_target_peer_id"):
			current_peer = int(node.call("get_current_target_peer_id"))
		lines.append("scarabee %s -> assigne J%s / courant J%s" % [
			String(node.name),
			"-" if assigned_peer <= 0 else str(assigned_peer),
			"-" if current_peer <= 0 else str(current_peer),
		])
	return lines


func _collect_bee_debug_lines() -> Array[String]:
	var lines: Array[String] = []
	for node in get_tree().get_nodes_in_group("bee_bots"):
		if not is_instance_valid(node):
			continue
		var current_peer := -1
		if node.has_method("get_current_target_peer_id"):
			current_peer = int(node.call("get_current_target_peer_id"))
		lines.append("abeille %s -> courant J%s" % [
			String(node.name),
			"-" if current_peer <= 0 else str(current_peer),
		])
	return lines


func _find_first_inventory_container() -> Node:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("inventory_containers")
	for node in nodes:
		return node
	var fallback: Node = get_tree().root.find_child("Chest", true, false)
	return fallback


func _find_first_revive_coin() -> Node:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("revive_coins")
	for node in nodes:
		return node
	return null


func _format_match_clock() -> String:
	var seconds_left: float = _extract_time_left_seconds(_match_status_text)
	var total_seconds: int = maxi(0, int(ceil(seconds_left)))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _format_debug_objectives_summary() -> String:
	var objective_lines: Array[String] = []
	for line in _match_status_text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			continue
		if trimmed == "objectives:":
			continue
		if trimmed.find(":") <= 0:
			continue
		if trimmed.begins_with("peer_"):
			continue
		if trimmed.begins_with("state:") or trimmed.begins_with("result_reason:") or trimmed.begins_with("time_left:") or trimmed.begins_with("players:") or trimmed.begins_with("team_score:") or trimmed == "MATCH" or trimmed == "score:" or trimmed == "lives:" or trimmed == "deaths:":
			continue
		var parts := trimmed.split(":")
		if parts.size() < 2:
			continue
		var key := String(parts[0]).strip_edges()
		var value := String(parts[1]).strip_edges()
		objective_lines.append("%s=%s" % [key, value])
	if objective_lines.is_empty():
		return "-"
	return ", ".join(objective_lines)


func _format_snapshot_compact_section(section_name: String) -> String:
	var section_values := _extract_snapshot_section(section_name)
	if section_values.is_empty():
		return "-"
	var peer_ids: Array[int] = []
	for peer_id in section_values.keys():
		peer_ids.append(int(peer_id))
	peer_ids.sort()
	var items: Array[String] = []
	for peer_id in peer_ids:
		items.append("J%d:%s" % [peer_id, str(section_values.get(peer_id, "-"))])
	return ", ".join(items)


func _format_local_player_stats_text() -> String:
	var peer_id := _get_local_peer_id()
	if peer_id <= 0:
		return "Vies: -   Score: -"
	var lives := _extract_snapshot_section("lives")
	var scores := _extract_snapshot_section("score")
	return "Vies: %s   Score: %s" % [
		str(lives.get(peer_id, "-")),
		str(scores.get(peer_id, "0")),
	]


func _get_local_peer_id() -> int:
	var local_player := _get_local_player()
	if local_player != null:
		return local_player.get_multiplayer_authority()
	if _has_active_multiplayer_peer():
		return multiplayer.get_unique_id()
	return -1


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


func _format_match_status_for_hud() -> String:
	var state_name := _extract_state_name(_match_status_text)
	var seconds_left: float = _extract_time_left_seconds(_match_status_text)
	var total_seconds: int = maxi(0, int(ceil(seconds_left)))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	var players := _extract_snapshot_value("players")
	var team_score := _extract_snapshot_value("team_score")
	return "MATCH\netat: %s\nchrono: %02d:%02d\njoueurs: %s\nscore equipe: %s" % [
		state_name,
		minutes,
		seconds,
		players,
		team_score,
	]


func _extract_snapshot_value(key: String) -> String:
	for line in _match_status_text.split("\n"):
		if not line.begins_with("%s:" % key):
			continue
		return line.trim_prefix("%s:" % key).strip_edges()
	return "-"


func _format_server_player_stats() -> String:
	var scores := _extract_snapshot_section("score")
	var lives := _extract_snapshot_section("lives")
	var deaths := _extract_snapshot_section("deaths")
	if scores.is_empty() and lives.is_empty() and deaths.is_empty():
		return "JOUEURS\naucune donnee"
	var peer_ids: Array[int] = []
	for key in scores.keys():
		peer_ids.append(int(key))
	for key in lives.keys():
		var peer_id := int(key)
		if peer_id not in peer_ids:
			peer_ids.append(peer_id)
	for key in deaths.keys():
		var peer_id := int(key)
		if peer_id not in peer_ids:
			peer_ids.append(peer_id)
	peer_ids.sort()
	var lines: Array[String] = ["JOUEURS"]
	for peer_id in peer_ids:
		lines.append("J%s  vies %s  score %s  morts %s" % [
			peer_id,
			str(lives.get(peer_id, "-")),
			str(scores.get(peer_id, "-")),
			str(deaths.get(peer_id, "-")),
		])
	return "\n".join(lines)


func _extract_snapshot_section(section_name: String) -> Dictionary:
	var section_values: Dictionary = {}
	var in_section := false
	for line in _match_status_text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed == "%s:" % section_name:
			in_section = true
			continue
		if not in_section:
			continue
		if trimmed.ends_with(":") and not trimmed.begins_with("peer_"):
			break
		if not trimmed.begins_with("peer_"):
			continue
		var parts := trimmed.split(":")
		if parts.size() < 2:
			continue
		var peer_text := String(parts[0]).trim_prefix("peer_").strip_edges()
		if not peer_text.is_valid_int():
			continue
		section_values[int(peer_text)] = String(parts[1]).strip_edges()
	return section_values


func _exit_client() -> void:
	_connection.disconnect_peer()
	await _quit_after_disconnect()


func _exit_server() -> void:
	await _connection.shutdown_server()
	await _quit_after_disconnect()


func _is_server_instance() -> bool:
	return _has_active_multiplayer_peer() and multiplayer.is_server()


func _has_active_multiplayer_peer() -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer()


func _quit_after_disconnect() -> void:
	await get_tree().process_frame
	get_tree().quit()


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
	if not _has_active_multiplayer_peer():
		return null
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


func _sync_main_menu_endpoint_fields() -> void:
	if is_instance_valid(_player_name_edit):
		var nickname := UserDataManager.DEFAULT_NICKNAME
		if is_instance_valid(_user_data_manager):
			nickname = _user_data_manager.get_pending_local_nickname()
		_player_name_edit.text = nickname
	if is_instance_valid(_server_ip_edit):
		_server_ip_edit.text = _connection.get_runtime_host()
	if is_instance_valid(_server_port_spinbox):
		_server_port_spinbox.value = _connection.get_runtime_port()


func _apply_main_menu_endpoint_config() -> void:
	var host_text := _connection.get_runtime_host()
	var port_value := _connection.get_runtime_port()
	if is_instance_valid(_server_ip_edit):
		host_text = _server_ip_edit.text.strip_edges()
	if is_instance_valid(_server_port_spinbox):
		port_value = int(_server_port_spinbox.value)
	_connection.configure_runtime_endpoint(host_text, port_value)


func _apply_main_menu_player_name_config() -> void:
	if not is_instance_valid(_user_data_manager):
		return
	var nickname := _user_data_manager.get_pending_local_nickname()
	if is_instance_valid(_player_name_edit):
		nickname = _player_name_edit.text
	_user_data_manager.configure_local_nickname(nickname)
