extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const WORLD_ITEM_SCENE: PackedScene = preload("res://inventory/world_item.tscn")
const CHEST_SCENE: PackedScene = preload("res://inventory/inventory_container.tscn")
const APPLE_DEF = preload("res://inventory/items/apple.tres")
const WOOD_DEF = preload("res://inventory/items/wood.tres")


func _spawn_world() -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	var interactives := Node3D.new()
	interactives.name = "Interactives"
	world.add_child(interactives)
	var players_root := Node3D.new()
	players_root.name = "Players"
	world.add_child(players_root)
	await wait_process_frames(2)
	return world


func _spawn_player(world: Node3D) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	player.set_multiplayer_authority(2)
	world.get_node("Players").add_child(player)
	await wait_process_frames(2)
	return player


func test_player_can_pickup_and_drop_world_items() -> void:
	var world := await _spawn_world()
	var player := await _spawn_player(world)
	var world_item = WORLD_ITEM_SCENE.instantiate()
	world_item.item_definition = APPLE_DEF
	world_item.quantity = 3
	world.get_node("Interactives").add_child(world_item)
	await wait_process_frames(1)

	player.request_pickup_world_item(world_item.get_path())
	await wait_process_frames(2)

	assert_eq(3, player.get_inventory_component().count_item("apple"))
	assert_false(world_item.visible, "L'objet ramasse doit disparaitre de la scene")

	player.request_drop_inventory_slot(0, 2)
	await wait_process_frames(2)

	assert_eq(1, player.get_inventory_component().count_item("apple"))
	var visible_world_items := 0
	for node in get_tree().get_nodes_in_group("world_items"):
		if node.visible:
			visible_world_items += 1
	assert_eq(1, visible_world_items, "Le depot doit recreer un objet visible dans le monde")


func test_non_pickable_world_item_is_rejected() -> void:
	var world := await _spawn_world()
	var player := await _spawn_player(world)
	var world_item = WORLD_ITEM_SCENE.instantiate()
	world_item.item_definition = WOOD_DEF
	world_item.quantity = 1
	world_item.is_pickable = false
	world.get_node("Interactives").add_child(world_item)
	await wait_process_frames(1)

	player.request_pickup_world_item(world_item.get_path())
	await wait_process_frames(2)

	assert_eq(0, player.get_inventory_component().get_slot_count())
	assert_true(world_item.visible, "Un objet non ramassable doit rester en scene")


func test_player_can_transfer_with_chest() -> void:
	var world := await _spawn_world()
	var player := await _spawn_player(world)
	var chest = CHEST_SCENE.instantiate()
	chest.inventory_name = "Coffre test"
	world.get_node("Interactives").add_child(chest)
	await wait_process_frames(2)
	chest.get_inventory_component().add_payload(WOOD_DEF.to_inventory_payload(5))

	player.get_inventory_component().add_payload(APPLE_DEF.to_inventory_payload(2))
	player.set_focused_inventory_target(chest)
	await wait_process_frames(1)

	player.request_transfer_to_target(0, 1)
	await wait_process_frames(2)
	assert_eq(1, player.get_inventory_component().count_item("apple"))
	assert_eq(1, chest.get_inventory_component().count_item("apple"))

	player.request_transfer_from_target(0, 2)
	await wait_process_frames(2)
	assert_eq(2, player.get_inventory_component().count_item("wood"))
	assert_eq(3, chest.get_inventory_component().count_item("wood"))
