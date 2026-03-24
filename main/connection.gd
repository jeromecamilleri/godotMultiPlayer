extends Node
class_name Connection

signal connected
signal disconnected
signal server_status_changed(status_text: String)
signal network_stats_changed(stats_text: String)

static var is_peer_connected: bool
var _connected_clients: Dictionary = {}
var _client_latency_reports: Dictionary = {}
var _status_timer: Timer

@export var port: int
@export var max_clients: int
@export var host: String
@export var use_localhost_in_editor: bool

var _resolved_port := 0
var _resolved_host := ""
var _ui_configured_port := -1
var _ui_configured_host := ""
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
	var address := _resolved_host
	if address.is_empty():
		address = host
	if OS.has_feature("editor") and use_localhost_in_editor and _ui_configured_host.is_empty():
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
	_client_latency_reports[id] = {
		"rtt_ms": -1,
		"avg_rtt_ms": -1.0,
		"jitter_ms": 0.0,
		"last_report_ms": 0,
	}
	_print_server_status("peer_connected")
	_emit_network_stats()


func peer_disconnected(id: int) -> void:
	DebugLog.net("Peer disconnected: " + str(id))
	if not multiplayer.is_server():
		return
	_connected_clients.erase(id)
	_client_latency_reports.erase(id)
	_print_server_status("peer_disconnected")
	_emit_network_stats()


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
	var status_text := "SERVEUR\netat: %s\nclients: %d\nport: %d" % [
		reason,
		_connected_clients.size(),
		_resolved_port
	]
	server_status_changed.emit(status_text)
	DebugLog.net("===== SERVER STATUS =====")
	DebugLog.net("reason: " + reason)
	DebugLog.net("clients_connected: " + str(_connected_clients.size()))
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
	_resolved_host = host
	var env_port_text := OS.get_environment("UI_TEST_PORT").strip_edges()
	if env_port_text.is_empty():
		_apply_ui_runtime_endpoint_override()
		return
	if env_port_text.is_valid_int():
		var env_port := int(env_port_text)
		if env_port > 0 and env_port <= 65535:
			_resolved_port = env_port
		else:
			DebugLog.net("Ignoring out-of-range UI_TEST_PORT=%d" % env_port)
	else:
		DebugLog.net("Ignoring invalid UI_TEST_PORT=%s" % env_port_text)
	_apply_ui_runtime_endpoint_override()


func configure_runtime_endpoint(address: String, port_value: int) -> void:
	_ui_configured_host = address.strip_edges()
	_ui_configured_port = port_value
	_apply_ui_runtime_endpoint_override()


func get_runtime_host() -> String:
	return _ui_configured_host if not _ui_configured_host.is_empty() else _resolved_host


func get_runtime_port() -> int:
	return _resolved_port


func get_runtime_endpoint_display() -> String:
	var address := get_runtime_host()
	if address.is_empty():
		address = host
	if ":" in address and not address.begins_with("["):
		address = "[%s]" % address
	return "%s:%d" % [address, _resolved_port]


func _apply_ui_runtime_endpoint_override() -> void:
	if not _ui_configured_host.is_empty():
		_resolved_host = _ui_configured_host
	if _ui_configured_port > 0 and _ui_configured_port <= 65535:
		_resolved_port = _ui_configured_port


func get_network_rtt_ms() -> int:
	return _last_rtt_ms


func get_network_rtt_average_ms() -> float:
	return _avg_rtt_ms


func get_network_jitter_ms() -> float:
	return _jitter_ms


func get_network_stats_text() -> String:
	if multiplayer.is_server():
		return _get_server_network_stats_text()
	if _last_rtt_ms < 0:
		return "NET sync..."
	return "NET %d ms | avg %.1f | jitter %.1f" % [_last_rtt_ms, _avg_rtt_ms, _jitter_ms]


func get_server_client_network_stats_text() -> String:
	if not multiplayer.is_server():
		return ""
	if _connected_clients.is_empty():
		return "Aucun client connecte"
	var ids := _get_sorted_client_ids()
	var lines: Array[String] = []
	for peer_id in ids:
		var report: Dictionary = _client_latency_reports.get(peer_id, {})
		var rtt_ms := int(report.get("rtt_ms", -1))
		var avg_rtt_ms := float(report.get("avg_rtt_ms", -1.0))
		var jitter_ms := float(report.get("jitter_ms", 0.0))
		var freshness_ms := maxi(0, Time.get_ticks_msec() - int(report.get("last_report_ms", 0)))
		if rtt_ms < 0:
			lines.append("J%s  sync..." % peer_id)
			continue
		lines.append("J%s  %d ms  avg %.0f  jit %.0f  maj %d ms" % [
			peer_id,
			rtt_ms,
			avg_rtt_ms,
			jitter_ms,
			freshness_ms,
		])
	return "\n".join(lines)


func _get_server_network_stats_text() -> String:
	if _connected_clients.is_empty():
		return "NET host | 0 client"
	var ids := _get_sorted_client_ids()
	var sample_count := 0
	var total_rtt := 0
	var max_rtt := 0
	var max_jitter := 0.0
	for peer_id in ids:
		var report: Dictionary = _client_latency_reports.get(peer_id, {})
		var rtt_ms := int(report.get("rtt_ms", -1))
		if rtt_ms < 0:
			continue
		sample_count += 1
		total_rtt += rtt_ms
		max_rtt = maxi(max_rtt, rtt_ms)
		max_jitter = maxf(max_jitter, float(report.get("jitter_ms", 0.0)))
	if sample_count == 0:
		return "NET host | %d clients | sync..." % _connected_clients.size()
	return "NET host | %d clients | avg %d ms | max %d | jit %.0f" % [
		_connected_clients.size(),
		int(round(float(total_rtt) / float(sample_count))),
		max_rtt,
		max_jitter,
	]


func _get_sorted_client_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in _connected_clients.keys():
		ids.append(int(key))
	ids.sort()
	return ids


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
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		_rpc_report_client_latency.rpc_id(1, _last_rtt_ms, _avg_rtt_ms, _jitter_ms)


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


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_report_client_latency(rtt_ms: int, avg_rtt_ms: float, jitter_ms: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if sender_id not in _connected_clients:
		return
	_client_latency_reports[sender_id] = {
		"rtt_ms": rtt_ms,
		"avg_rtt_ms": avg_rtt_ms,
		"jitter_ms": jitter_ms,
		"last_report_ms": Time.get_ticks_msec(),
	}
	_emit_network_stats()
