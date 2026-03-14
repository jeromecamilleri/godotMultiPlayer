extends Control

var is_in_game: bool


func _ready() -> void:
	visibility_changed.connect(on_visibility_changed)
	on_visibility_changed()
	set_process(true)


func _input(_event: InputEvent) -> void:
	if not is_in_game: return
	
	if Input.is_action_just_pressed("show_mouse"): set_captured(false)
	if Input.is_action_just_released("show_mouse"): set_captured(true)


func _process(_delta: float) -> void:
	if not is_in_game:
		return
	var local_player := _get_local_player()
	if local_player != null and local_player.has_method("is_inventory_mode_open"):
		set_captured(not bool(local_player.call("is_inventory_mode_open")))


func on_visibility_changed() -> void:
	if is_visible_in_tree():
		var local_player := _get_local_player()
		var should_capture := true
		if local_player != null and local_player.has_method("is_inventory_mode_open"):
			should_capture = not bool(local_player.call("is_inventory_mode_open"))
		set_captured(should_capture)
		is_in_game = true
	else:
		set_captured(false)
		is_in_game = false


func _notification(what: int) -> void:
	match what:
		MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN:
			if is_visible_in_tree():
				var local_player := _get_local_player()
				var should_capture := true
				if local_player != null and local_player.has_method("is_inventory_mode_open"):
					should_capture = not bool(local_player.call("is_inventory_mode_open"))
				set_captured(should_capture)
		MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT:
			pass


func set_captured(captured: bool) -> void:
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _get_local_player() -> Node:
	for node in get_tree().get_nodes_in_group("players"):
		if node.has_method("is_multiplayer_authority") and node.is_multiplayer_authority():
			return node
	return null
