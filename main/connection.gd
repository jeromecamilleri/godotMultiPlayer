extends Node
class_name Connection

signal connected
signal disconnected
signal server_status_changed(status_text: String)
signal network_stats_changed(stats_text: String)

static var is_peer_connected: bool
var _connected_clients: Dictionary = {}
var _status_timer: Timer

@export var port: int
@export var max_clients: int
@export var host: String
@export var use_localhost_in_editor: bool

var _resolved_port := 0
var _latency_probe_timer: Timer
var _last_ping_sent_ms := -1
var _last_rtt_ms := -1
var _avg_rtt_ms := -1.0
var _jitter_ms := 0.0


func _ready() -> void:
	_resolve_runtime_network_config()
	# Dedicated server mode is selected by command-line argument.
	if Connection.is_server(): start_server()
	connected.connect(func(): Connection.is_peer_connected = true)
	disconnected.connect(func(): Connection.is_peer_connected = false)
	connected.connect(_start_latency_probe)
	disconnected.connect(_stop_latency_probe)
	disconnected.connect(disconnect_all)
	_emit_network_stats()


static func is_server() -> bool:
	return "--server" in OS.get_cmdline_args()


func start_server() -> void:
	if max_clients == 0:
		max_clients = 32
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(_resolved_port, max_clients)
	if err != OK:
		DebugLog.net("Cannot start server on port %d. Err: %s" % [_resolved_port, str(err)])
		disconnected.emit()
		return
	else:
		DebugLog.net("Server started on port %d" % _resolved_port)
		connected.emit()
	
	multiplayer.multiplayer_peer = peer
	# Server tracks joins/leaves to drive in-game status UI.
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	_start_server_status_output()
	_print_server_status("server_started")


func start_client() -> void:
	var address = host
	if OS.has_feature("editor") and use_localhost_in_editor:
		address = "localhost"
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, _resolved_port)
	if err != OK:
		DebugLog.net("Cannot start client to %s:%d. Err: %s" % [address, _resolved_port, str(err)])
		disconnected.emit()
		return
	else: DebugLog.net("Connecting to server %s:%d..." % [address, _resolved_port])
	
	multiplayer.multiplayer_peer = peer
	# Client listens for successful connect and failure/disconnect paths.
	multiplayer.connected_to_server.connect(connected_to_server)
	multiplayer.server_disconnected.connect(server_connection_failure)
	multiplayer.connection_failed.connect(server_connection_failure)


func disconnect_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	disconnected.emit()


func shutdown_server() -> void:
	if not multiplayer.is_server():
		disconnect_peer()
		return
	# Ask clients to close first so they cleanly leave game state and UI.
	rpc("_rpc_shutdown_client_session")
	await get_tree().create_timer(0.25).timeout
	disconnect_peer()


func connected_to_server() -> void:
	DebugLog.net("Connected to server")
	connected.emit()
	_emit_network_stats()


func server_connection_failure() -> void:
	DebugLog.net("Disconnected")
	disconnected.emit()
	_emit_network_stats()


func peer_connected(id: int) -> void:
	DebugLog.net("Peer connected: " + str(id))
	if not multiplayer.is_server():
		return
	_connected_clients[id] = true
	_print_server_status("peer_connected")


func peer_disconnected(id: int) -> void:
	DebugLog.net("Peer disconnected: " + str(id))
	if not multiplayer.is_server():
		return
	_connected_clients.erase(id)
	_print_server_status("peer_disconnected")


func _start_server_status_output() -> void:
	if not multiplayer.is_server():
		return
	if _status_timer != null:
		return
	_status_timer = Timer.new()
	_status_timer.wait_time = 1.0
	_status_timer.autostart = true
	_status_timer.timeout.connect(func(): _print_server_status("heartbeat"))
	add_child(_status_timer)


func _print_server_status(reason: String) -> void:
	if not multiplayer.is_server():
		return
	var client_ids := PackedInt32Array(_connected_clients.keys())
	client_ids.sort()
	var status_text := "SERVER STATUS\nreason: %s\nclients_connected: %d\nclient_ids: %s" % [
		reason,
		client_ids.size(),
		str(client_ids)
	]
	server_status_changed.emit(status_text)
	DebugLog.net("===== SERVER STATUS =====")
	DebugLog.net("reason: " + reason)
	DebugLog.net("clients_connected: " + str(client_ids.size()))
	DebugLog.net("client_ids: " + str(client_ids))
	DebugLog.net("=========================")


func disconnect_all() -> void:
	_stop_latency_probe()
	if multiplayer.peer_connected.is_connected(peer_connected):
		multiplayer.peer_connected.disconnect(peer_connected)
	if multiplayer.peer_disconnected.is_connected(peer_disconnected):
		multiplayer.peer_disconnected.disconnect(peer_disconnected)
	if multiplayer.connected_to_server.is_connected(connected_to_server):
		multiplayer.connected_to_server.disconnect(connected_to_server)
	if multiplayer.server_disconnected.is_connected(server_connection_failure):
		multiplayer.server_disconnected.disconnect(server_connection_failure)
	if multiplayer.connection_failed.is_connected(server_connection_failure):
		multiplayer.connection_failed.disconnect(server_connection_failure)


func _resolve_runtime_network_config() -> void:
	_resolved_port = port
	var env_port_text := OS.get_environment("UI_TEST_PORT").strip_edges()
	if env_port_text.is_empty():
		return
	if not env_port_text.is_valid_int():
		DebugLog.net("Ignoring invalid UI_TEST_PORT=%s" % env_port_text)
		return
	var env_port := int(env_port_text)
	if env_port <= 0 or env_port > 65535:
		DebugLog.net("Ignoring out-of-range UI_TEST_PORT=%d" % env_port)
		return
	_resolved_port = env_port


func get_network_rtt_ms() -> int:
	return _last_rtt_ms


func get_network_rtt_average_ms() -> float:
	return _avg_rtt_ms


func get_network_jitter_ms() -> float:
	return _jitter_ms


func get_network_stats_text() -> String:
	if multiplayer.is_server():
		return "NET host"
	if _last_rtt_ms < 0:
		return "NET sync..."
	return "NET %d ms | avg %.1f | jitter %.1f" % [_last_rtt_ms, _avg_rtt_ms, _jitter_ms]


func reset_network_metrics() -> void:
	_last_ping_sent_ms = -1
	_last_rtt_ms = -1
	_avg_rtt_ms = -1.0
	_jitter_ms = 0.0
	_emit_network_stats()


func _start_latency_probe() -> void:
	if multiplayer.is_server():
		_emit_network_stats()
		return
	if _latency_probe_timer != null:
		return
	_latency_probe_timer = Timer.new()
	_latency_probe_timer.wait_time = 0.5
	_latency_probe_timer.autostart = true
	_latency_probe_timer.timeout.connect(_send_latency_ping)
	add_child(_latency_probe_timer)
	_send_latency_ping()


func _stop_latency_probe() -> void:
	if _latency_probe_timer != null:
		_latency_probe_timer.queue_free()
		_latency_probe_timer = null
	_last_ping_sent_ms = -1


func _send_latency_ping() -> void:
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	_last_ping_sent_ms = Time.get_ticks_msec()
	_rpc_latency_ping.rpc_id(1, _last_ping_sent_ms)


func _update_latency_metrics(sample_rtt_ms: int) -> void:
	_last_rtt_ms = sample_rtt_ms
	if _avg_rtt_ms < 0.0:
		_avg_rtt_ms = float(sample_rtt_ms)
		_jitter_ms = 0.0
	else:
		var previous_avg := _avg_rtt_ms
		_avg_rtt_ms = lerpf(_avg_rtt_ms, float(sample_rtt_ms), 0.2)
		_jitter_ms = lerpf(_jitter_ms, absf(float(sample_rtt_ms) - previous_avg), 0.2)
	_emit_network_stats()


func _emit_network_stats() -> void:
	network_stats_changed.emit(get_network_stats_text())


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_latency_ping(sent_ms: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_rpc_latency_pong.rpc_id(sender_id, sent_ms)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_latency_pong(sent_ms: int) -> void:
	if multiplayer.is_server():
		return
	var now_ms := Time.get_ticks_msec()
	var sample_rtt_ms := maxi(0, now_ms - sent_ms)
	_update_latency_metrics(sample_rtt_ms)


@rpc("authority", "call_remote", "reliable")
func _rpc_shutdown_client_session() -> void:
	if multiplayer.is_server():
		return
	disconnect_peer()
