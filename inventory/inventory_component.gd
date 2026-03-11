extends Node
class_name InventoryComponent

signal contents_changed(contents: Array[Dictionary])

@export var inventory_name := "Inventaire"
@export var max_slots := 16

var _contents: Array[Dictionary] = []


func get_contents() -> Array[Dictionary]:
	return _duplicate_contents(_contents)


func get_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= _contents.size():
		return {}
	return _contents[slot_index].duplicate(true)


func get_slot_count() -> int:
	return _contents.size()


func clear() -> void:
	_contents.clear()
	_emit_changed()


func load_contents(serialized_contents: Array) -> void:
	_contents.clear()
	for entry in serialized_contents:
		if not (entry is Dictionary):
			continue
		var normalized := _normalize_payload(entry as Dictionary)
		if normalized.is_empty():
			continue
		_contents.append(normalized)
	_emit_changed()


func serialize_contents() -> Array[Dictionary]:
	return get_contents()


func can_add_payload(payload: Dictionary) -> bool:
	var normalized := _normalize_payload(payload)
	if normalized.is_empty():
		return false
	var simulation := _duplicate_contents(_contents)
	return _apply_add_to_contents(simulation, normalized, max_slots) == 0


func add_payload(payload: Dictionary) -> int:
	var normalized := _normalize_payload(payload)
	if normalized.is_empty():
		return 0
	var remaining := _apply_add_to_contents(_contents, normalized, max_slots)
	if remaining != normalized["quantity"]:
		_emit_changed()
	return remaining


func remove_from_slot(slot_index: int, quantity: int = 1) -> Dictionary:
	if slot_index < 0 or slot_index >= _contents.size():
		return {}
	var slot := _contents[slot_index]
	var removed_quantity := clampi(quantity, 1, int(slot["quantity"]))
	var removed := slot.duplicate(true)
	removed["quantity"] = removed_quantity
	slot["quantity"] = int(slot["quantity"]) - removed_quantity
	if int(slot["quantity"]) <= 0:
		_contents.remove_at(slot_index)
	else:
		_contents[slot_index] = slot
	_emit_changed()
	return removed


func transfer_to(target: InventoryComponent, slot_index: int, quantity: int = 1) -> bool:
	if target == null:
		return false
	var payload := get_slot(slot_index)
	if payload.is_empty():
		return false
	payload["quantity"] = clampi(quantity, 1, int(payload["quantity"]))
	if not target.can_add_payload(payload):
		return false
	var remaining := target.add_payload(payload)
	if remaining != 0:
		return false
	remove_from_slot(slot_index, int(payload["quantity"]))
	return true


func count_item(item_id: String) -> int:
	var total := 0
	for slot in _contents:
		if String(slot.get("item_id", "")) != item_id:
			continue
		total += int(slot.get("quantity", 0))
	return total


func _emit_changed() -> void:
	contents_changed.emit(get_contents())


static func _apply_add_to_contents(contents: Array[Dictionary], payload: Dictionary, slot_limit: int) -> int:
	var remaining := int(payload["quantity"])
	for i in range(contents.size()):
		if remaining <= 0:
			break
		var slot := contents[i]
		if String(slot.get("item_id", "")) != String(payload["item_id"]):
			continue
		var max_stack_value := maxi(1, int(slot.get("max_stack", 1)))
		var current_quantity := int(slot.get("quantity", 0))
		if current_quantity >= max_stack_value:
			continue
		var available_space := max_stack_value - current_quantity
		var added := mini(available_space, remaining)
		slot["quantity"] = current_quantity + added
		contents[i] = slot
		remaining -= added
	while remaining > 0 and contents.size() < maxi(0, slot_limit):
		var new_slot := payload.duplicate(true)
		var stack_quantity := mini(maxi(1, int(payload.get("max_stack", 1))), remaining)
		new_slot["quantity"] = stack_quantity
		contents.append(new_slot)
		remaining -= stack_quantity
	return remaining


static func _normalize_payload(payload: Dictionary) -> Dictionary:
	if payload.is_empty():
		return {}
	var item_id := String(payload.get("item_id", ""))
	if item_id.is_empty():
		return {}
	var quantity := maxi(1, int(payload.get("quantity", 1)))
	var max_stack_value := maxi(1, int(payload.get("max_stack", 1)))
	var metadata: Variant = payload.get("metadata", {})
	if not (metadata is Dictionary):
		metadata = {}
	return {
		"item_id": item_id,
		"display_name": String(payload.get("display_name", item_id)),
		"description": String(payload.get("description", "")),
		"quantity": quantity,
		"max_stack": max_stack_value,
		"world_item_scene": String(payload.get("world_item_scene", "")),
		"icon_path": String(payload.get("icon_path", "")),
		"metadata": (metadata as Dictionary).duplicate(true),
	}


static func _duplicate_contents(contents: Array[Dictionary]) -> Array[Dictionary]:
	var duplicated: Array[Dictionary] = []
	for slot in contents:
		duplicated.append(slot.duplicate(true))
	return duplicated
