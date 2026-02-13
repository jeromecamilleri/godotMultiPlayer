extends Control

signal start_server
signal connect_client

@export var hide_ui_and_connect: bool
@onready var _server_status_label: Label = $InGameUI/ServerStatus
@onready var _connection: Connection = get_node("../Connection") as Connection
@onready var _fall_checker: FallChecker = get_node("../FallChecker") as FallChecker

var _connection_status_text := "SERVER STATUS\nreason: startup\nclients_connected: 0\nclient_ids: []"
var _lives_status_text := "LIVES"


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
	_server_status_label.visible = multiplayer.is_server() and $InGameUI.visible


func _update_server_status_label() -> void:
	_server_status_label.text = _connection_status_text + "\n\n" + _lives_status_text
