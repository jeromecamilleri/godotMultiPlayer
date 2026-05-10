extends GutTest


func after_each() -> void:
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	Connection.is_peer_connected = false


func test_client_connection_timeout_closes_peer_and_returns_failure_signal() -> void:
	var connection := Connection.new()
	connection.host = "127.0.0.1"
	connection.port = 59998
	connection.client_connect_timeout_seconds = 1.0
	add_child_autofree(connection)
	await wait_process_frames(1)

	var observed := {
		"failure_reason": "",
		"disconnected_count": 0,
	}
	connection.client_connection_failed.connect(func(reason: String): observed["failure_reason"] = reason)
	connection.disconnected.connect(func(): observed["disconnected_count"] = int(observed["disconnected_count"]) + 1)

	connection.start_client()
	assert_true(bool(connection.get("_is_client_connecting")), "La tentative client doit etre marquee active.")
	assert_not_null(connection.get("_client_connect_timer"), "Une tentative client doit demarrer un timer de timeout.")

	connection._on_client_connect_timeout()
	await wait_process_frames(1)

	assert_false(bool(connection.get("_is_client_connecting")), "Le timeout doit terminer la tentative client.")
	assert_null(connection.get("_client_connect_timer"), "Le timer doit etre libere apres timeout.")
	assert_null(connection.multiplayer.multiplayer_peer, "Le peer ENet doit etre ferme pour permettre une nouvelle tentative.")
	assert_eq(1, int(observed["disconnected_count"]), "Le timeout doit declencher le retour UI via disconnected.")
	assert_string_contains(String(observed["failure_reason"]), "127.0.0.1:59998")


func test_connection_failed_signal_uses_same_client_failure_path_while_connecting() -> void:
	var connection := Connection.new()
	connection.host = "127.0.0.1"
	connection.port = 59997
	connection.client_connect_timeout_seconds = 5.0
	add_child_autofree(connection)
	await wait_process_frames(1)

	var observed := {
		"failure_reason": "",
	}
	connection.client_connection_failed.connect(func(reason: String): observed["failure_reason"] = reason)

	connection.start_client()
	connection.server_connection_failure()
	await wait_process_frames(1)

	assert_false(bool(connection.get("_is_client_connecting")))
	assert_null(connection.multiplayer.multiplayer_peer)
	assert_string_contains(String(observed["failure_reason"]), "127.0.0.1:59997")
