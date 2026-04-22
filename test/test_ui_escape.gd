extends GutTest


class MockConnection:
	extends Connection

	var disconnect_peer_called := false
	var shutdown_server_called := false
	var fake_recent_sync_events: Array[String] = ["[00:00.001] coin | consomme (revive)"]

	func _ready() -> void:
		pass

	func disconnect_peer() -> void:
		disconnect_peer_called = true

	func shutdown_server() -> void:
		shutdown_server_called = true

	func get_network_stats_text() -> String:
		return "NET 12 ms | avg 10.0 | jitter 1.0"

	func get_server_client_network_stats_text() -> String:
		return "J2 12 ms  avg 10  jit 1  maj 20 ms"

	func get_recent_sync_events() -> Array[String]:
		return fake_recent_sync_events.duplicate()


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


func _assert_no_disconnect_errors(test_case: GutTest, context: String) -> void:
	for err in test_case.get_errors():
		if not err.is_engine_error():
			continue
		if err.contains_text("No multiplayer peer is assigned. Unable to get unique ID.") or err.contains_text("Can't change visibility of main window."):
			err.handled = true
			test_case.fail_test("%s ne doit pas produire d'erreur de déconnexion UI/multiplayer." % context)


func _build_ui_context() -> Dictionary:
	# Build only the nodes required by ui.gd and replace network dependencies with mocks.
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

	var debug_backdrop := ColorRect.new()
	debug_backdrop.name = "DebugOverlayBackdrop"
	in_game.add_child(debug_backdrop)

	var debug_label := Label.new()
	debug_label.name = "DebugOverlayLabel"
	in_game.add_child(debug_label)

	root.add_child(ui)

	await wait_process_frames(2)

	return {
		"ui": ui,
		"connection": connection,
	}


func _escape_event() -> InputEventKey:
	# Synthetic ESC event used to drive _unhandled_input deterministically.
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	return event


func _f3_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
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


func test_f3_toggle_affiche_et_masque_le_debug_overlay() -> void:
	var ctx: Dictionary = await _build_ui_context()
	var ui: TestUI = ctx["ui"] as TestUI
	var debug_label := ui.get_node("InGameUI/DebugOverlayLabel") as Label
	ui.hide_ui()
	await wait_process_frames(1)

	assert_false(debug_label.visible)

	ui._unhandled_input(_f3_event())
	await wait_process_frames(1)
	assert_true(debug_label.visible, "F3 doit afficher l'overlay debug.")
	assert_string_contains(debug_label.text, "DEBUG F3")
	assert_string_contains(debug_label.text, "MATCH")
	assert_string_contains(debug_label.text, "RESEAU")
	assert_string_contains(debug_label.text, "SYNCS")
	assert_string_contains(debug_label.text, "events (1)")
	assert_string_contains(debug_label.text, "coin | consomme")

	ui._unhandled_input(_f3_event())
	await wait_process_frames(1)
	assert_false(debug_label.visible, "Un second F3 doit masquer l'overlay debug.")


func test_show_ui_without_multiplayer_peer_does_not_raise_disconnect_errors() -> void:
	var ctx: Dictionary = await _build_ui_context()
	var ui: TestUI = ctx["ui"] as TestUI

	ui.show_ui()
	await wait_process_frames(1)

	_assert_no_disconnect_errors(self, "show_ui sans peer")
	assert_true(ui.get_node("MainMenu").visible, "Le menu principal doit rester visible sans peer actif.")
