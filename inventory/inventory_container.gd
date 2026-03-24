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
var _last_snapshot_server_ms := -1
var _last_snapshot_replication_delay_ms := -1
var _snapshot_revision := 0
var _pending_broadcast := false
var _last_snapshot_request_ms_by_peer: Dictionary = {}


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponentScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	inventory.inventory_name = inventory_name
	inventory.contents_changed.connect(_on_inventory_changed)
	if multiplayer.is_server():
		_seed_initial_contents()
		call_deferred("_queue_inventory_snapshot_broadcast", true)
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
		_queue_inventory_snapshot_broadcast()


func _queue_inventory_snapshot_broadcast(force: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if force:
		_pending_broadcast = false
		_flush_inventory_snapshot_broadcast(true)
		return
	if _pending_broadcast:
		return
	_pending_broadcast = true
	call_deferred("_flush_inventory_snapshot_broadcast")


func _flush_inventory_snapshot_broadcast(force: bool = false) -> void:
	_pending_broadcast = false
	var next_snapshot_json := JSON.stringify(inventory.serialize_contents())
	if not force and next_snapshot_json == _inventory_snapshot_json:
		return
	_inventory_snapshot_json = next_snapshot_json
	_last_snapshot_server_ms = Time.get_ticks_msec()
	_snapshot_revision += 1
	sync_inventory_snapshot.rpc(_inventory_snapshot_json, _last_snapshot_server_ms, _snapshot_revision)


## Demande côté client : le serveur renvoie le snapshot actuel à l’appelant.
## Garantit que le client a bien l’état à jour (évite les RPC broadcast manqués).
@rpc("any_peer", "call_remote", "reliable")
func request_chest_snapshot(known_revision: int = -1, force: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return
	var now_ms := Time.get_ticks_msec()
	var last_request_ms := int(_last_snapshot_request_ms_by_peer.get(sender_id, -100000))
	if not force and known_revision == _snapshot_revision and now_ms - last_request_ms < 500:
		return
	_last_snapshot_request_ms_by_peer[sender_id] = now_ms
	sync_inventory_snapshot.rpc_id(sender_id, _inventory_snapshot_json, _last_snapshot_server_ms, _snapshot_revision)


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_snapshot(snapshot_json: String, server_event_ms: int = -1, revision: int = -1) -> void:
	if revision >= 0 and revision < _snapshot_revision:
		return
	_inventory_snapshot_json = snapshot_json
	if server_event_ms >= 0 and not multiplayer.is_server():
		_last_snapshot_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_last_snapshot_server_ms = server_event_ms
	if revision >= 0:
		_snapshot_revision = revision
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


func get_last_snapshot_replication_delay_ms() -> int:
	return _last_snapshot_replication_delay_ms


func get_snapshot_revision() -> int:
	return _snapshot_revision
