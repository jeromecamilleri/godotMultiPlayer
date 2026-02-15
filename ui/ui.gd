extends Control

signal start_server
signal connect_client

@export var hide_ui_and_connect: bool
@onready var _server_status_label: Label = $InGameUI/ServerStatus
@onready var _connection: Connection = get_node("../Connection") as Connection
@onready var _fall_checker: FallChecker = get_node("../FallChecker") as FallChecker

var _connection_status_text := "SERVER STATUS\nreason: startup\nclients_connected: 0\nclient_ids: []"
var _lives_status_text := "LIVES"
var _is_exiting_client := false
var _is_exiting_server := false


func _ready():
	_connection.server_status_changed.connect(_on_server_status_changed)
	_fall_checker.lives_status_changed.connect(_on_lives_status_changed)
	_update_server_status_label()
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
	_refresh_server_status_visibility()


func _on_lives_status_changed(status_text: String) -> void:
	_lives_status_text = status_text
	_update_server_status_label()
	_refresh_server_status_visibility()


func _refresh_server_status_visibility() -> void:
	_server_status_label.visible = _is_server_instance() and $InGameUI.visible


func _update_server_status_label() -> void:
	_server_status_label.text = _connection_status_text + "\n\n" + _lives_status_text


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
