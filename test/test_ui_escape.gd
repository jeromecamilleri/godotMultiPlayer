extends GutTest


class MockConnection:
	extends Connection

	var disconnect_peer_called := false
	var shutdown_server_called := false

	func _ready() -> void:
		pass

	func disconnect_peer() -> void:
		disconnect_peer_called = true

	func shutdown_server() -> void:
		shutdown_server_called = true


class MockFallChecker:
	extends FallChecker

	func _ready() -> void:
		pass


class TestUI:
	extends "res://ui/ui.gd"

	var fake_server := false
	var exit_client_called := false
	var exit_server_called := false

	func _is_server_instance() -> bool:
		return fake_server

	func _exit_client() -> void:
		exit_client_called = true

	func _exit_server() -> void:
		exit_server_called = true


func _build_ui_context() -> Dictionary:
	var root := Node.new()
	add_child_autofree(root)

	var connection := MockConnection.new()
	connection.name = "Connection"
	root.add_child(connection)

	var fall_checker := MockFallChecker.new()
	fall_checker.name = "FallChecker"
	root.add_child(fall_checker)

	var ui := TestUI.new()
	ui.name = "UI"
	ui.hide_ui_and_connect = false

	var main_menu := Control.new()
	main_menu.name = "MainMenu"
	ui.add_child(main_menu)

	var in_game := Control.new()
	in_game.name = "InGameUI"
	ui.add_child(in_game)

	var status := Label.new()
	status.name = "ServerStatus"
	in_game.add_child(status)

	root.add_child(ui)

	await wait_process_frames(2)

	return {
		"ui": ui,
		"connection": connection,
	}


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	return event


func test_escape_client_connected_triggers_client_exit() -> void:
	var ctx: Dictionary = await _build_ui_context()
	var ui: TestUI = ctx["ui"] as TestUI
	ui.fake_server = false
	Connection.is_peer_connected = true

	ui._unhandled_input(_escape_event())
	await wait_process_frames(1)

	assert_true(ui.exit_client_called, "Escape cote client connecte doit lancer la sortie client")
	assert_false(ui.exit_server_called, "Escape cote client ne doit pas lancer la sortie serveur")


func test_escape_server_triggers_server_exit() -> void:
	var ctx: Dictionary = await _build_ui_context()
	var ui: TestUI = ctx["ui"] as TestUI
	ui.fake_server = true
	Connection.is_peer_connected = true

	ui._unhandled_input(_escape_event())
	await wait_process_frames(1)

	assert_true(ui.exit_server_called, "Escape cote serveur doit lancer la sortie serveur")
	assert_false(ui.exit_client_called, "Escape cote serveur ne doit pas lancer la sortie client")
