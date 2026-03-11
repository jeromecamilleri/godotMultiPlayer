extends PanelContainer
class_name InventoryPanel

signal slot_action_requested(action_id: String, slot_index: int)

@onready var _title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var _hint_label: Label = $MarginContainer/VBoxContainer/Hint
@onready var _rows_container: VBoxContainer = $MarginContainer/VBoxContainer/Rows

var _last_signature := ""


func set_panel_state(panel_name: String, contents: Array, action_specs: Array, hint_text: String) -> void:
	var signature := JSON.stringify({
		"name": panel_name,
		"contents": contents,
		"actions": action_specs,
		"hint": hint_text,
	})
	if signature == _last_signature:
		return
	_last_signature = signature
	_title_label.text = panel_name
	_hint_label.text = hint_text
	for child in _rows_container.get_children():
		child.queue_free()
	if contents.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Vide"
		_rows_container.add_child(empty_label)
		return
	for i in range(contents.size()):
		var slot: Variant = contents[i]
		if not (slot is Dictionary):
			continue
		var slot_dict := slot as Dictionary
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s x%d" % [String(slot_dict.get("display_name", slot_dict.get("item_id", "Objet"))), int(slot_dict.get("quantity", 0))]
		row.add_child(label)
		for action_spec in action_specs:
			var button := Button.new()
			button.text = String(action_spec.get("label", "Action"))
			button.pressed.connect(_on_action_pressed.bind(String(action_spec.get("id", "")), i))
			row.add_child(button)
		_rows_container.add_child(row)


func _on_action_pressed(action_id: String, slot_index: int) -> void:
	slot_action_requested.emit(action_id, slot_index)
