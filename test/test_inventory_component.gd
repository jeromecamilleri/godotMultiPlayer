extends GutTest

const InventoryComponentScript := preload("res://inventory/inventory_component.gd")
const APPLE_DEF = preload("res://inventory/items/apple.tres")
const WOOD_DEF = preload("res://inventory/items/wood.tres")
const APPLE_WORLD_ITEM_SCENE := preload("res://inventory/world_items/apple_pickup.tscn")


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


func test_apple_payload_uses_specific_pickup_scene() -> void:
	# Dropped apples must keep the apple-shaped pickup instead of falling back to the generic yellow sphere.
	var payload: Dictionary = APPLE_DEF.to_inventory_payload(1)

	assert_eq("res://inventory/world_items/apple_pickup.tscn", String(payload.get("world_item_scene", "")))


func test_apple_pickup_scene_keeps_world_item_contract_and_branch_visuals() -> void:
	var apple_pickup := APPLE_WORLD_ITEM_SCENE.instantiate()
	add_child_autofree(apple_pickup)

	assert_true(apple_pickup.has_node("CollisionShape3D"), "La scene specifique doit garder la collision attendue par WorldItem.")
	assert_true(apple_pickup.has_node("MeshInstance3D"), "La pomme doit garder le noeud mesh attendu par WorldItem.")
	assert_true(apple_pickup.has_node("Label3D"), "La scene specifique doit garder le label attendu par WorldItem.")
	assert_true(apple_pickup.has_node("BranchVisual/Branch"), "La pomme doit etre visuellement accrochee a une branche.")
	assert_true(apple_pickup.has_node("Stem"), "La pomme doit avoir une tige lisible.")
	assert_true(apple_pickup.has_node("Leaf"), "La pomme doit avoir une feuille lisible.")
