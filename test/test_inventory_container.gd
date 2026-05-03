extends GutTest

const CHEST_SCENE: PackedScene = preload("res://inventory/inventory_container.tscn")
const APPLE_DEF := preload("res://inventory/items/apple.tres")
const WOOD_DEF := preload("res://inventory/items/wood.tres")


func _spawn_chest() -> InventoryContainer3D:
	var chest: InventoryContainer3D = CHEST_SCENE.instantiate() as InventoryContainer3D
	add_child_autofree(chest)
	return chest


func _serialize_payloads(payloads: Array[Dictionary]) -> Array[Dictionary]:
	var chest := _spawn_chest()
	chest.get_inventory_component().load_contents(payloads)
	return chest.get_inventory_component().serialize_contents()


func test_inventory_container_label_is_readable_through_foreground_decoration() -> void:
	var chest: InventoryContainer3D = autofree(CHEST_SCENE.instantiate()) as InventoryContainer3D
	var label := chest.get_node("Label3D") as Label3D

	assert_true(label.no_depth_test, "Le label coffre doit rester lisible meme si un arbre passe devant.")
	assert_true(label.outline_size >= 12, "Le label coffre doit garder un contour assez fort pour les fonds clairs.")
	assert_true(label.font_size >= 36, "Le label coffre doit rester lisible a distance.")


func test_inventory_delta_tracks_only_changed_slots() -> void:
	var chest := _spawn_chest()
	var before: Array[Dictionary] = _serialize_payloads([
		APPLE_DEF.to_inventory_payload(2),
		WOOD_DEF.to_inventory_payload(4),
	])
	var after: Array[Dictionary] = _serialize_payloads([
		APPLE_DEF.to_inventory_payload(3),
		WOOD_DEF.to_inventory_payload(4),
	])

	var delta: Dictionary = chest.call("_build_inventory_delta", before, after)
	var slots: Array = delta.get("slots", [])

	assert_eq(1, slots.size(), "Un simple changement de quantité doit produire un delta d'un seul slot.")
	assert_eq(0, int((slots[0] as Dictionary).get("index", -1)))
	assert_eq(3, int(((slots[0] as Dictionary).get("slot", {}) as Dictionary).get("quantity", 0)))


func test_inventory_delta_application_restores_expected_contents() -> void:
	var chest := _spawn_chest()
	var before: Array[Dictionary] = _serialize_payloads([
		APPLE_DEF.to_inventory_payload(2),
		WOOD_DEF.to_inventory_payload(1),
	])
	var after: Array[Dictionary] = _serialize_payloads([
		WOOD_DEF.to_inventory_payload(5),
	])

	var delta: Dictionary = chest.call("_build_inventory_delta", before, after)
	var rebuilt: Array[Dictionary] = chest.call("_apply_inventory_delta_contents", before, delta)

	assert_eq(JSON.stringify(after), JSON.stringify(rebuilt), "Le delta applique doit reconstruire exactement le nouvel inventaire.")


func test_inventory_container_prefers_delta_when_smaller_than_snapshot() -> void:
	var chest := _spawn_chest()
	var before: Array[Dictionary] = _serialize_payloads([
		APPLE_DEF.to_inventory_payload(2),
		WOOD_DEF.to_inventory_payload(4),
	])
	var after: Array[Dictionary] = _serialize_payloads([
		APPLE_DEF.to_inventory_payload(3),
		WOOD_DEF.to_inventory_payload(4),
	])
	var delta: Dictionary = chest.call("_build_inventory_delta", before, after)
	var delta_json := JSON.stringify(delta)
	var snapshot_json := JSON.stringify(after)

	assert_true(bool(chest.call("_should_use_delta_replication", false, delta, delta_json, snapshot_json)), "Le coffre doit préférer le delta quand il est plus compact qu'un snapshot complet.")
	assert_false(bool(chest.call("_should_use_delta_replication", true, delta, delta_json, snapshot_json)), "Un broadcast forcé doit rester un snapshot complet.")
