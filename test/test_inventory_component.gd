extends GutTest

const InventoryComponentScript := preload("res://inventory/inventory_component.gd")
const APPLE_DEF = preload("res://inventory/items/apple.tres")
const WOOD_DEF = preload("res://inventory/items/wood.tres")


func test_add_payload_stacks_and_respects_slot_limit() -> void:
	var inventory = InventoryComponentScript.new()
	inventory.max_slots = 2
	add_child_autofree(inventory)

	var remaining: int = inventory.add_payload(APPLE_DEF.to_inventory_payload(15))

	assert_eq(0, remaining, "Toutes les pommes doivent rentrer dans 2 slots de 10 et 5")
	assert_eq(2, inventory.get_slot_count())
	assert_eq(10, int(inventory.get_slot(0).get("quantity", 0)))
	assert_eq(5, int(inventory.get_slot(1).get("quantity", 0)))

	var wood_remaining: int = inventory.add_payload(WOOD_DEF.to_inventory_payload(1))
	assert_eq(1, wood_remaining, "Un nouvel item ne doit pas rentrer si tous les slots sont occupes")


func test_transfer_between_inventories_is_atomic() -> void:
	var source = InventoryComponentScript.new()
	var target = InventoryComponentScript.new()
	source.max_slots = 4
	target.max_slots = 1
	add_child_autofree(source)
	add_child_autofree(target)

	source.add_payload(APPLE_DEF.to_inventory_payload(3))
	target.add_payload(WOOD_DEF.to_inventory_payload(20))

	var transferred: bool = source.transfer_to(target, 0, 2)

	assert_false(transferred, "Le transfert doit echouer si la cible n'a pas de place")
	assert_eq(3, source.count_item("apple"))
	assert_eq(20, target.count_item("wood"))


func test_serialize_and_reload_contents() -> void:
	var inventory = InventoryComponentScript.new()
	var restored = InventoryComponentScript.new()
	add_child_autofree(inventory)
	add_child_autofree(restored)

	inventory.add_payload(APPLE_DEF.to_inventory_payload(4))
	inventory.add_payload(WOOD_DEF.to_inventory_payload(7))
	var serialized: Array = inventory.serialize_contents()
	restored.load_contents(serialized)

	assert_eq(4, restored.count_item("apple"))
	assert_eq(7, restored.count_item("wood"))
