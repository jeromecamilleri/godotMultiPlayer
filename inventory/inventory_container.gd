extends StaticBody3D
class_name InventoryContainer3D

const InventoryComponentScript := preload("res://inventory/inventory_component.gd")
@onready var chest_anim: AnimationPlayer = $chest_gold/AnimationPlayer

var is_open := false

func open_chestlid() -> void:
	if is_open:
		return
	
	is_open = true
	chest_anim.play("open")

func close_chestlid() -> void:
	if not is_open:
		return
	
	is_open = false
	chest_anim.play_backwards("open")

func toggle_chestlid() -> void:
	if is_open:
		close_chestlid()
	else:
		open_chestlid()
		
@export var inventory_name := "Coffre"
@export var initial_items: Array[Resource] = []
@export var initial_quantities: PackedInt32Array = PackedInt32Array()

@onready var inventory = $Inventory
@onready var _label: Label3D = $Label3D

var _inventory_snapshot_json := "[]"
var _inventory_snapshot_contents: Array[Dictionary] = []
var _is_loading_snapshot := false
var _seeded := false
var _last_snapshot_server_ms := -1
var _last_snapshot_replication_delay_ms := -1
var _snapshot_revision := 0
var _pending_broadcast := false
var _last_snapshot_request_ms_by_peer: Dictionary = {}
var _last_sync_mode := "snapshot"


func _ready() -> void:
	add_to_group("inventory_containers")
	add_to_group("replicated_persistent_objects")
	if inventory == null:
		inventory = InventoryComponentScript.new()
		inventory.name = "Inventory"
		add_child(inventory)
	inventory.inventory_name = inventory_name
	inventory.contents_changed.connect(_on_inventory_changed)
	if _is_authority_instance():
		if multiplayer.multiplayer_peer != null and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
		_seed_initial_contents()
		call_deferred("_queue_inventory_snapshot_broadcast", true)
	else:
		_apply_inventory_snapshot(_inventory_snapshot_json)
		if multiplayer.multiplayer_peer != null:
			call_deferred("_request_snapshot_when_connected")
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
	if _is_authority_instance():
		_queue_inventory_snapshot_broadcast()


func _queue_inventory_snapshot_broadcast(force: bool = false) -> void:
	if not _is_authority_instance():
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
	var next_snapshot_contents: Array[Dictionary] = _normalize_serialized_contents(inventory.serialize_contents())
	var next_snapshot_json := JSON.stringify(next_snapshot_contents)
	if not force and next_snapshot_json == _inventory_snapshot_json:
		return
	var delta_payload: Dictionary = _build_inventory_delta(_inventory_snapshot_contents, next_snapshot_contents)
	var delta_json := JSON.stringify(delta_payload)
	_inventory_snapshot_json = next_snapshot_json
	_inventory_snapshot_contents = _duplicate_serialized_contents(next_snapshot_contents)
	_last_snapshot_server_ms = Time.get_ticks_msec()
	_snapshot_revision += 1
	if multiplayer.multiplayer_peer == null:
		return
	if _should_use_delta_replication(force, delta_payload, delta_json, next_snapshot_json):
		_last_sync_mode = "delta"
		_record_sync_event("coffre", "delta rev=%d slots=%d" % [_snapshot_revision, int((delta_payload.get("slots", []) as Array).size())])
		sync_inventory_delta.rpc(delta_json, _last_snapshot_server_ms, _snapshot_revision)
	else:
		_last_sync_mode = "snapshot"
		_record_sync_event("coffre", "snapshot rev=%d" % _snapshot_revision)
		sync_inventory_snapshot.rpc(_inventory_snapshot_json, _last_snapshot_server_ms, _snapshot_revision)


## Demande côté client : le serveur renvoie le snapshot actuel à l’appelant.
## Garantit que le client a bien l’état à jour (évite les RPC broadcast manqués).
@rpc("any_peer", "call_remote", "reliable")
func request_chest_snapshot(known_revision: int = -1, force: bool = false) -> void:
	if not _is_authority_instance():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return
	var now_ms := Time.get_ticks_msec()
	var last_request_ms := int(_last_snapshot_request_ms_by_peer.get(sender_id, -100000))
	if not force and known_revision == _snapshot_revision and now_ms - last_request_ms < 500:
		return
	_last_snapshot_request_ms_by_peer[sender_id] = now_ms
	_record_sync_event("coffre", "push snapshot->J%d rev=%d%s" % [sender_id, _snapshot_revision, " force" if force else ""])
	sync_inventory_snapshot.rpc_id(sender_id, _inventory_snapshot_json, _last_snapshot_server_ms, _snapshot_revision)


func _request_snapshot_when_connected() -> void:
	if _is_authority_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_request_snapshot_when_connected")):
		return
	request_chest_snapshot.rpc_id(1, _snapshot_revision, false)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_authority_instance():
		return
	call_deferred("_push_current_snapshot_to_peer", peer_id)


func _push_current_snapshot_to_peer(peer_id: int) -> void:
	if not _is_authority_instance():
		return
	if multiplayer.multiplayer_peer == null:
		return
	sync_inventory_snapshot.rpc_id(peer_id, _inventory_snapshot_json, _last_snapshot_server_ms, _snapshot_revision)


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_snapshot(snapshot_json: String, server_event_ms: int = -1, revision: int = -1) -> void:
	if revision >= 0 and revision < _snapshot_revision:
		return
	_inventory_snapshot_json = snapshot_json
	_inventory_snapshot_contents = _parse_snapshot_json(snapshot_json)
	if server_event_ms >= 0 and not _is_authority_instance():
		_last_snapshot_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_last_sync_mode = "snapshot"
	_last_snapshot_server_ms = server_event_ms
	if revision >= 0:
		_snapshot_revision = revision
	_apply_inventory_snapshot(snapshot_json)
	_refresh_label()


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_delta(delta_json: String, server_event_ms: int = -1, revision: int = -1) -> void:
	if revision >= 0 and revision <= _snapshot_revision:
		return
	if revision >= 0 and _snapshot_revision >= 0 and revision > _snapshot_revision + 1:
		_request_forced_snapshot_recovery()
		return
	var parsed: Variant = JSON.parse_string(delta_json)
	if not (parsed is Dictionary):
		_request_forced_snapshot_recovery()
		return
	var next_snapshot_contents: Array[Dictionary] = _apply_inventory_delta_contents(_inventory_snapshot_contents, parsed as Dictionary)
	_inventory_snapshot_contents = _duplicate_serialized_contents(next_snapshot_contents)
	_inventory_snapshot_json = JSON.stringify(_inventory_snapshot_contents)
	if server_event_ms >= 0 and not _is_authority_instance():
		_last_snapshot_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_last_sync_mode = "delta"
	_last_snapshot_server_ms = server_event_ms
	if revision >= 0:
		_snapshot_revision = revision
	_apply_inventory_snapshot(_inventory_snapshot_json)
	_refresh_label()


func _apply_inventory_snapshot(snapshot_json: String) -> void:
	var parsed: Array[Dictionary] = _parse_snapshot_json(snapshot_json)
	_is_loading_snapshot = true
	inventory.load_contents(parsed)
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


func get_last_sync_mode() -> String:
	return _last_sync_mode


func request_current_state_from_server() -> void:
	_request_snapshot_when_connected()


func push_current_state_to_peer(peer_id: int) -> void:
	_push_current_snapshot_to_peer(peer_id)


func get_state_revision() -> int:
	return _snapshot_revision


func get_debug_sync_summary() -> String:
	return "coffre=%s rev=%d mode=%s rep=%s" % [
		inventory_name,
		_snapshot_revision,
		_last_sync_mode,
		"-" if _last_snapshot_replication_delay_ms < 0 else "%d ms" % _last_snapshot_replication_delay_ms,
	]


func _should_use_delta_replication(force: bool, delta_payload: Dictionary, delta_json: String, snapshot_json: String) -> bool:
	if force:
		return false
	var slots_variant: Variant = delta_payload.get("slots", [])
	if not (slots_variant is Array):
		return false
	if (slots_variant as Array).is_empty():
		return false
	return delta_json.length() < snapshot_json.length()


func _build_inventory_delta(previous: Array[Dictionary], next: Array[Dictionary]) -> Dictionary:
	var slots: Array[Dictionary] = []
	var max_slot_count: int = maxi(previous.size(), next.size())
	for index in range(max_slot_count):
		var previous_slot: Variant = null
		var next_slot: Variant = null
		if index < previous.size():
			previous_slot = previous[index]
		if index < next.size():
			next_slot = next[index]
		if previous_slot == next_slot:
			continue
		slots.append({
			"index": index,
			"slot": next_slot,
		})
	return {"slots": slots}


func _apply_inventory_delta_contents(base: Array[Dictionary], delta_payload: Dictionary) -> Array[Dictionary]:
	var slot_values: Array = []
	for slot in base:
		slot_values.append((slot as Dictionary).duplicate(true))
	var slots_variant: Variant = delta_payload.get("slots", [])
	if not (slots_variant is Array):
		return _duplicate_serialized_contents(base)
	for raw_entry in slots_variant:
		if not (raw_entry is Dictionary):
			continue
		var entry := raw_entry as Dictionary
		var index: int = int(entry.get("index", -1))
		if index < 0:
			continue
		while slot_values.size() <= index:
			slot_values.append(null)
		var next_slot: Variant = entry.get("slot", null)
		if next_slot is Dictionary:
			slot_values[index] = (next_slot as Dictionary).duplicate(true)
		else:
			slot_values[index] = null
	var compacted: Array[Dictionary] = []
	for slot in slot_values:
		if slot is Dictionary:
			compacted.append((slot as Dictionary).duplicate(true))
	return compacted


func _normalize_serialized_contents(contents: Array) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	for slot in contents:
		if slot is Dictionary:
			normalized.append((slot as Dictionary).duplicate(true))
	return normalized


func _duplicate_serialized_contents(contents: Array[Dictionary]) -> Array[Dictionary]:
	var duplicated: Array[Dictionary] = []
	for slot in contents:
		duplicated.append(slot.duplicate(true))
	return duplicated


func _parse_snapshot_json(snapshot_json: String) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(snapshot_json)
	if not (parsed is Array):
		return []
	return _normalize_serialized_contents(parsed as Array)


func _request_forced_snapshot_recovery() -> void:
	if _is_authority_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_request_forced_snapshot_recovery")):
		return
	_record_sync_event("coffre", "recovery snapshot rev=%d" % _snapshot_revision)
	request_chest_snapshot.rpc_id(1, _snapshot_revision, true)


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)


func _is_authority_instance() -> bool:
	return multiplayer.is_server() or multiplayer.multiplayer_peer == null
