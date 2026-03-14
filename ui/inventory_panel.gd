extends PanelContainer
class_name InventoryPanel

signal slot_selected(slot_index: int)
signal slot_action_requested(action_id: String, slot_index: int)

@onready var _title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var _hint_label: Label = $MarginContainer/VBoxContainer/Hint
@onready var _rows_container: VBoxContainer = $MarginContainer/VBoxContainer/Rows
@onready var _actions_container: HBoxContainer = $MarginContainer/VBoxContainer/Actions

var _selected_slot := -1
var _contents: Array = []
var _last_signature := ""


func set_panel_state(panel_name: String, contents: Array, action_specs: Array, hint_text: String, selected_slot: int = -1) -> void:
	var normalized_selected := -1
	if not contents.is_empty():
		normalized_selected = clampi(selected_slot, 0, contents.size() - 1) if selected_slot >= 0 else 0
	var signature := JSON.stringify({
		"panel_name": panel_name,
		"contents": contents,
		"action_specs": action_specs,
		"hint_text": hint_text,
		"selected_slot": normalized_selected,
	})
	if signature == _last_signature:
		return
	_last_signature = signature
	_contents = contents.duplicate(true)
	_title_label.text = panel_name
	_hint_label.text = hint_text
	_selected_slot = normalized_selected
	_rebuild_rows()
	_rebuild_actions(action_specs)


func get_selected_slot() -> int:
	return _selected_slot


func _rebuild_rows() -> void:
	for child in _rows_container.get_children():
		child.queue_free()
	if _contents.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Vide"
		_rows_container.add_child(empty_label)
		return
	for i in range(_contents.size()):
		var slot: Variant = _contents[i]
		if not (slot is Dictionary):
			continue
		var slot_dict := slot as Dictionary
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = i == _selected_slot
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s x%d" % [String(slot_dict.get("display_name", slot_dict.get("item_id", "Objet"))), int(slot_dict.get("quantity", 0))]
		button.pressed.connect(_on_slot_pressed.bind(i))
		_rows_container.add_child(button)


func _rebuild_actions(action_specs: Array) -> void:
	for child in _actions_container.get_children():
		child.queue_free()
	if _contents.is_empty():
		return
	for action_spec in action_specs:
		var button := Button.new()
		button.text = String(action_spec.get("label", "Action"))
		button.disabled = _selected_slot < 0
		button.pressed.connect(_on_action_pressed.bind(String(action_spec.get("id", ""))))
		_actions_container.add_child(button)


func _on_slot_pressed(slot_index: int) -> void:
	_selected_slot = slot_index
	_rebuild_rows()
	for child in _actions_container.get_children():
		if child is Button:
			child.disabled = false
	slot_selected.emit(slot_index)


func _on_action_pressed(action_id: String) -> void:
	if _selected_slot < 0:
		return
	slot_action_requested.emit(action_id, _selected_slot)
