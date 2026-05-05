extends GutTest


func test_runtime_environment_overrides_host_and_port() -> void:
	OS.set_environment("GODOT_RUNTIME_HOST", "192.0.2.10")
	OS.set_environment("GODOT_RUNTIME_PORT", "5055")
	OS.set_environment("UI_TEST_PORT", "")
	var connection := Connection.new()
	connection.host = "127.0.0.1"
	connection.port = 5050
	add_child_autofree(connection)
	await wait_process_frames(1)

	assert_eq("192.0.2.10", connection.get_runtime_host())
	assert_eq(5055, connection.get_runtime_port())
	_clear_runtime_environment()


func test_ui_test_port_still_works_when_runtime_port_is_empty() -> void:
	OS.set_environment("GODOT_RUNTIME_HOST", "")
	OS.set_environment("GODOT_RUNTIME_PORT", "")
	OS.set_environment("UI_TEST_PORT", "5060")
	var connection := Connection.new()
	connection.host = "127.0.0.1"
	connection.port = 5050
	add_child_autofree(connection)
	await wait_process_frames(1)

	assert_eq("127.0.0.1", connection.get_runtime_host())
	assert_eq(5060, connection.get_runtime_port())
	_clear_runtime_environment()


func _clear_runtime_environment() -> void:
	OS.set_environment("GODOT_RUNTIME_HOST", "")
	OS.set_environment("GODOT_RUNTIME_PORT", "")
	OS.set_environment("UI_TEST_PORT", "")
