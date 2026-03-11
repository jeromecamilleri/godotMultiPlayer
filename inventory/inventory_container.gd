extends StaticBody3D
class_name InventoryContainer3D

const InventoryComponentScript := preload("res://inventory/inventory_component.gd")

@export var inventory_name := "Coffre"
@export var initial_items: Array[Resource] = []
@export var initial_quantities: PackedInt32Array = PackedInt32Array()

@onready var inventory = $Inventory
@onready var _label: Label3D = $Label3D

var _inventory_snapshot_json := "[]"
var _is_loading_snapshot := false
var _seeded := false


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponentScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	inventory.inventory_name = inventory_name
	inventory.contents_changed.connect(_on_inventory_changed)
	if multiplayer.is_server():
		_seed_initial_contents()
		call_deferred("_broadcast_inventory_snapshot")
	else:
		_apply_inventory_snapshot(_inventory_snapshot_json)
	_refresh_label()


func get_inventory_component():
	return inventory


func get_inventory_contents() -> Array[Dictionary]:
	return inventory.get_contents()


func get_inventory_display_name() -> String:
	return inventory_name


func _seed_initial_contents() -> void:
	if _seeded:
		return
	_seeded = true
	if inventory.get_slot_count() > 0:
		return
	for i in range(initial_items.size()):
		var definition: Resource = initial_items[i]
		if definition == null:
			continue
		var quantity := 1
		if i < initial_quantities.size():
			quantity = maxi(1, initial_quantities[i])
		inventory.add_payload(definition.call("to_inventory_payload", quantity))


func _on_inventory_changed(_contents: Array[Dictionary]) -> void:
	if _is_loading_snapshot:
		return
	_refresh_label()
	if multiplayer.is_server():
		_broadcast_inventory_snapshot()


func _broadcast_inventory_snapshot() -> void:
	_inventory_snapshot_json = JSON.stringify(inventory.serialize_contents())
	sync_inventory_snapshot.rpc(_inventory_snapshot_json)


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_snapshot(snapshot_json: String) -> void:
	_inventory_snapshot_json = snapshot_json
	_apply_inventory_snapshot(snapshot_json)
	_refresh_label()


func _apply_inventory_snapshot(snapshot_json: String) -> void:
	var parsed: Variant = JSON.parse_string(snapshot_json)
	if not (parsed is Array):
		return
	_is_loading_snapshot = true
	inventory.load_contents(parsed as Array)
	_is_loading_snapshot = false


func _refresh_label() -> void:
	if not is_instance_valid(_label):
		return
	var total_items := 0
	for slot in inventory.get_contents():
		total_items += int(slot.get("quantity", 0))
	_label.text = "%s\n%d objet(s)" % [inventory_name, total_items]
