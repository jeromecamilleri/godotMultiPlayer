extends Control

@export var user_data_events: UserDataEvents
@export var label: Label
@export var speaking_indicator: Control
@export var anchor: Node3D
@export var offset: Vector3

var camera: Camera3D
var user_data: UserData
var _base_label_text := ""
var _is_downed := false
var _default_label_modulate := Color.WHITE


func _ready() -> void:
	if Connection.is_server() or is_multiplayer_authority():
		set_visible(false)
		set_process(false)
		return

	# Use deterministic in-world labels derived from peer ids so every client
	# sees the same "Player 1 / Player 2 / ..." mapping.
	_update_default_player_label()
	_default_label_modulate = label.modulate
	if multiplayer.peer_connected.is_connected(_on_peer_list_changed) == false:
		multiplayer.peer_connected.connect(_on_peer_list_changed)
	if multiplayer.peer_disconnected.is_connected(_on_peer_list_changed) == false:
		multiplayer.peer_disconnected.connect(_on_peer_list_changed)

	# Then subscribe to replicated user data so free-form nickname edits
	# (e.g. via change_name action) update the floating label in real time.
	var id := get_multiplayer_authority()
	var manager := user_data_events.user_data_manager
	if not is_instance_valid(manager):
		# User data manager may not be initialized yet in some test/minimal contexts.
		return
	var _user_data = manager.try_get_user_data(id)
	if is_instance_valid(_user_data):
		retrieve_user_data(id, _user_data)
	else:
		user_data_events.user_data_spawned.connect(retrieve_user_data)


func _process(_delta: float) -> void:
	camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return
	
	var anchor_pos = anchor.global_position + offset
	visible = not camera.is_position_behind(anchor_pos)
	position = camera.unproject_position(anchor_pos)


func _on_peer_list_changed(_id: int) -> void:
	_update_default_player_label()


func _update_default_player_label() -> void:
	var authority_id: int = get_multiplayer_authority()
	var compact_index: int = _get_compact_player_index(authority_id)
	_base_label_text = "Player %d" % compact_index
	_refresh_label()


func _get_compact_player_index(authority_id: int) -> int:
	# Build a stable ordering from replicated user-data ids.
	# This excludes dedicated-server peer id and keeps labels compact (1..N players).
	var ids := PackedInt32Array()
	var manager := user_data_events.user_data_manager
	if is_instance_valid(manager):
		ids = PackedInt32Array(manager.user_datas.keys())
		ids.append(multiplayer.get_unique_id())
	else:
		# Fallback if the manager is not initialized yet.
		ids = PackedInt32Array(multiplayer.get_peers())
		ids.append(multiplayer.get_unique_id())
	ids.sort()
	var position := ids.find(authority_id)
	if position == -1:
		# Fallback to authority id if peer list is temporarily not ready.
		return authority_id
	return position + 1


func retrieve_user_data(id: int, _user_data: UserData) -> void:
	# User-data path provides replicated nickname/speaking state for this avatar.
	if id != get_multiplayer_authority(): return
	
	user_data = _user_data
	user_data.nickname_changed.connect(nickname_changed)
	user_data.speaking_changed.connect(speaking_changed)
	nickname_changed(user_data.nickname)
	speaking_changed(user_data.speaking)


func nickname_changed(nickname: String) -> void:
	var trimmed := nickname.strip_edges()
	if trimmed.is_empty():
		# Keep deterministic fallback if nickname has not been initialized yet.
		_update_default_player_label()
		return
	_base_label_text = trimmed
	_refresh_label()


func speaking_changed(speaking: bool) -> void:
	speaking_indicator.visible = speaking


func set_downed_state(downed: bool) -> void:
	_is_downed = downed
	_refresh_label()


func _refresh_label() -> void:
	var suffix := " [DOWNED]" if _is_downed else ""
	label.text = _base_label_text + suffix
	label.modulate = Color(1.0, 0.45, 0.45, 1.0) if _is_downed else _default_label_modulate
