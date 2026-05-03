extends Node
class_name UserDataManager

@export var user_data_spawner: UserDataSpawner
@export var user_data_events: UserDataEvents

const DEFAULT_NICKNAME := "Player"
const MAX_NICKNAME_LENGTH := 20

var my_user_data: UserData
var user_datas = {} # {Peer ID: UserData}
var _custom_local_nickname := ""


func _ready() -> void:
	if Connection.is_server(): return
	
	user_data_events.set_user_data_manager(self)
	user_data_spawner.user_data_spawned.connect(user_data_spawned)
	user_data_spawner.user_data_despawned.connect(user_data_despawned)
	_update_window_title()


func user_data_spawned(id: int, user_data: UserData) -> void:
	if id == multiplayer.get_unique_id():
		user_data.is_my_data = true
		my_user_data = user_data
		apply_local_nickname_to(user_data)
	else:
		user_datas[id] = user_data
	
	user_data_events.user_data_spawned_emit(id, user_data)


func user_data_despawned(id: int) -> void:
	if id == multiplayer.get_unique_id():
		my_user_data = null
	else:
		user_datas.erase(id)
	
	user_data_events.user_data_despawned_emit(id)


func try_get_user_data(id: int) -> UserData:
	return user_datas[id] if user_datas.has(id) else null


func configure_local_nickname(nickname: String) -> void:
	var normalized := normalize_nickname(nickname)
	_custom_local_nickname = "" if normalized == DEFAULT_NICKNAME else normalized
	if is_instance_valid(my_user_data):
		apply_local_nickname_to(my_user_data)
	_update_window_title()


func get_pending_local_nickname() -> String:
	if not _custom_local_nickname.is_empty():
		return _custom_local_nickname
	return get_default_local_nickname()


func get_default_local_nickname() -> String:
	if not is_inside_tree() or multiplayer == null or multiplayer.multiplayer_peer == null:
		return DEFAULT_NICKNAME
	var local_id := multiplayer.get_unique_id()
	if local_id <= 1:
		return DEFAULT_NICKNAME
	return "%s %d" % [DEFAULT_NICKNAME, local_id]


func apply_local_nickname_to(user_data: UserData) -> void:
	if not is_instance_valid(user_data):
		return
	user_data.nickname = get_pending_local_nickname()
	_update_window_title()


static func normalize_nickname(nickname: String) -> String:
	var normalized := nickname.strip_edges()
	if normalized.is_empty():
		normalized = DEFAULT_NICKNAME
	if normalized.length() > MAX_NICKNAME_LENGTH:
		normalized = normalized.substr(0, MAX_NICKNAME_LENGTH)
	return normalized


func _update_window_title() -> void:
	if _is_ui_test_runtime():
		return
	var app_name := String(ProjectSettings.get_setting("application/config/name", "Godot"))
	DisplayServer.window_set_title("%s - %s" % [app_name, get_pending_local_nickname()])


func _is_ui_test_runtime() -> bool:
	return not OS.get_environment("UI_TEST_AUTO_ROLE").strip_edges().is_empty() \
		or not OS.get_environment("UI_TEST_INSTANCE_ROLE").strip_edges().is_empty()
