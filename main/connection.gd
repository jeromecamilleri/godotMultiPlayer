extends Node
class_name Connection

signal connected
signal disconnected
signal server_status_changed(status_text: String)

static var is_peer_connected: bool
var _connected_clients: Dictionary = {}
var _status_timer: Timer

@export var port: int
@export var max_clients: int
@export var host: String
@export var use_localhost_in_editor: bool


func _ready() -> void:
	if Connection.is_server(): start_server()
	connected.connect(func(): Connection.is_peer_connected = true)
	disconnected.connect(func(): Connection.is_peer_connected = false)
	disconnected.connect(disconnect_all)


static func is_server() -> bool:
	return "--server" in OS.get_cmdline_args()


func start_server() -> void:
	if max_clients == 0:
		max_clients = 32
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_clients)
	if err != OK:
		print("Cannot start server. Err: " + str(err))
		disconnected.emit()
		return
	else:
		print("Server started")
		connected.emit()
	
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	_start_server_status_output()
	_print_server_status("server_started")


func start_client() -> void:
	var address = host
	if OS.has_feature("editor") and use_localhost_in_editor:
		address = "localhost"
	
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		print("Cannot start client. Err: " + str(err))
		disconnected.emit()
		return
	else: print("Connecting to server...")
	
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(connected_to_server)
	multiplayer.server_disconnected.connect(server_connection_failure)
	multiplayer.connection_failed.connect(server_connection_failure)


func disconnect_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	disconnected.emit()


func connected_to_server() -> void:
	print("Connected to server")
	connected.emit()


func server_connection_failure() -> void:
	print("Disconnected")
	disconnected.emit()


func peer_connected(id: int) -> void:
	print("Peer connected: " + str(id))
	if not multiplayer.is_server():
		return
	_connected_clients[id] = true
	_print_server_status("peer_connected")


func peer_disconnected(id: int) -> void:
	print("Peer disconnected: " + str(id))
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
	print("===== SERVER STATUS =====")
	print("reason: ", reason)
	print("clients_connected: ", client_ids.size())
	print("client_ids: ", client_ids)
	print("=========================")


func disconnect_all() -> void:
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
