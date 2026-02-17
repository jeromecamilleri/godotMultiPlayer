extends Control
class_name PlayerPanel

@export var nickname_edit: LineEdit
@export var volume_slider: HSlider
@export var speaking_indicator: Control
@export var animation_player: AnimationPlayer
@export var user_data_events: UserDataEvents

var user_data: UserData


func _ready() -> void:
	# Give local player a deterministic default nickname only once.
	# Remote player nicknames are authority-owned and replicated.
	if is_instance_valid(user_data):
		if user_data.is_my_data:
			_ensure_default_nickname()
		nickname_changed(user_data.nickname)
	speaking_indicator.visible = false
	
	nickname_edit.text_submitted.connect(text_submitted)
	volume_slider.value_changed.connect(volume_changed)


func text_submitted(nickname: String) -> void:
	user_data.nickname = nickname


func volume_changed(volume: float) -> void:
	user_data_events.user_volume_changed_emit(user_data.id, volume)


func set_user_data(_user_data: UserData) -> void:
	user_data = _user_data
	if user_data.is_my_data: animation_player.play("my_panel")
	
	user_data.nickname_changed.connect(nickname_changed)
	user_data.speaking_changed.connect(speaking_changed)


func _ensure_default_nickname() -> void:
	var current := user_data.nickname.strip_edges()
	if not current.is_empty():
		return
	var default_nickname := "Player %d" % _get_compact_player_index(user_data.id)
	user_data.nickname = default_nickname


func _get_compact_player_index(authority_id: int) -> int:
	# Use UserDataManager ids to index only connected players.
	var ids := PackedInt32Array()
	var manager := user_data_events.user_data_manager
	if is_instance_valid(manager):
		ids = PackedInt32Array(manager.user_datas.keys())
		ids.append(multiplayer.get_unique_id())
	else:
		ids = PackedInt32Array(multiplayer.get_peers())
		ids.append(multiplayer.get_unique_id())
	ids.sort()
	var position := ids.find(authority_id)
	if position == -1:
		return authority_id
	return position + 1


func nickname_changed(nickname: String) -> void:
	nickname_edit.text = nickname


func speaking_changed(speaking: bool) -> void:
	speaking_indicator.visible = speaking
