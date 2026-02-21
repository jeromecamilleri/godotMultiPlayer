extends Control

signal start_server
signal connect_client

@export var hide_ui_and_connect: bool
@onready var _server_status_label: Label = $InGameUI/ServerStatus
@onready var _match_timer_label: Label = get_node_or_null("InGameUI/MatchTimer") as Label
@onready var _connection: Connection = get_node("../Connection") as Connection
@onready var _match_director: Node = get_node_or_null("../MatchDirector")

var _connection_status_text := "SERVER STATUS\nreason: startup\nclients_connected: 0\nclient_ids: []"
var _match_status_text := "MATCH\nstate: LOBBY\ntime_left: 0.0s\nplayers: 0\nscore:"
var _is_exiting_client := false
var _is_exiting_server := false


func _ready():
	_connection.server_status_changed.connect(_on_server_status_changed)
	if is_instance_valid(_match_director) and _match_director.has_signal("snapshot_changed"):
		_match_director.snapshot_changed.connect(_on_match_snapshot_changed)
		if _match_director.has_method("get_snapshot_text"):
			_match_status_text = _match_director.get_snapshot_text()
	_update_server_status_label()
	_update_match_timer_label()
	_refresh_server_status_visibility()

	if Connection.is_server(): return
	
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


func _on_match_snapshot_changed(status_text: String) -> void:
	_match_status_text = status_text
	_update_server_status_label()
	_update_match_timer_label()
	_refresh_server_status_visibility()


func _refresh_server_status_visibility() -> void:
	_server_status_label.visible = _is_server_instance() and $InGameUI.visible
	if is_instance_valid(_match_timer_label):
		_match_timer_label.visible = $InGameUI.visible


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
