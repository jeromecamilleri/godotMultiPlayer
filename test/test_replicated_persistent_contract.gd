extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")
const TERRAIN3D_DEPRECATION_TEXT := "instance_reset_physics_interpolation() is deprecated."
const TERRAIN3D_TEXTURE_WARNING_TEXT := "normal texture is not connected to a file."
const WORLD_ITEM_SCENE := preload("res://inventory/world_item.tscn")
const CHEST_SCENE := preload("res://inventory/inventory_container.tscn")
const COIN_SCENE := preload("res://player/coin/coin.tscn")
const BOX_SCENE := preload("res://environment/box/box.tscn")
const PORTAL_SCENE := preload("res://levels/portal/portal.tscn")
const BEE_SCENE := preload("res://enemies/bee_bot.tscn")
const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")
const PULL_CUBE_SCRIPT := preload("res://main/rigid_body_3d.gd")


func _handle_known_terrain3d_engine_warning() -> void:
	for err in get_errors():
		if err.is_engine_error() and (err.contains_text(TERRAIN3D_DEPRECATION_TEXT) or err.contains_text(TERRAIN3D_TEXTURE_WARNING_TEXT)):
			err.handled = true


func _assert_replicated_contract(node: Node, label: String) -> void:
	assert_true(node.is_in_group("replicated_persistent_objects"), "%s doit appartenir au groupe replicated_persistent_objects." % label)
	assert_true(node.has_method("request_current_state_from_server"), "%s doit exposer request_current_state_from_server." % label)
	assert_true(node.has_method("push_current_state_to_peer"), "%s doit exposer push_current_state_to_peer." % label)
	assert_true(node.has_method("get_state_revision"), "%s doit exposer get_state_revision." % label)
	assert_true(node.has_method("get_debug_sync_summary"), "%s doit exposer get_debug_sync_summary." % label)
	assert_true(String(node.call("get_debug_sync_summary")).length() > 0, "%s doit retourner un resume debug non vide." % label)


func test_persistent_objects_expose_common_replicated_contract() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()

	var world_item := WORLD_ITEM_SCENE.instantiate()
	root.add_child(world_item)

	var chest := CHEST_SCENE.instantiate()
	root.add_child(chest)

	var coin := COIN_SCENE.instantiate()
	root.add_child(coin)

	var box := BOX_SCENE.instantiate()
	root.add_child(box)

	var portal := PORTAL_SCENE.instantiate()
	root.add_child(portal)

	var bee := BEE_SCENE.instantiate()
	root.add_child(bee)

	var beetle := BEETLE_SCENE.instantiate()
	root.add_child(beetle)

	var cube := PULL_CUBE_SCRIPT.new() as PullableCube
	root.add_child(cube)

	await wait_process_frames(3)

	var bomb_door := root.get_tree().get_first_node_in_group("bomb_reactives")
	var match_director := root.get_tree().get_first_node_in_group("match_director")
	var bee_director := root.get_tree().get_first_node_in_group("bee_directors")
	var beetle_director := root.get_tree().get_first_node_in_group("beetle_directors")

	_assert_replicated_contract(world_item, "WorldItem")
	_assert_replicated_contract(chest, "InventoryContainer3D")
	_assert_replicated_contract(coin, "Coin")
	_assert_replicated_contract(box, "Box")
	_assert_replicated_contract(portal, "Portal")
	_assert_replicated_contract(cube, "PullableCube")
	assert_not_null(bomb_door)
	_assert_replicated_contract(bomb_door, "BombDoor")
	assert_not_null(match_director)
	_assert_replicated_contract(match_director, "MatchDirector")
	assert_not_null(bee_director)
	_assert_replicated_contract(bee_director, "BeeDirector")
	assert_not_null(beetle_director)
	_assert_replicated_contract(beetle_director, "BeetleDirector")


func test_state_revisions_advance_on_persistent_state_changes() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var world_item := WORLD_ITEM_SCENE.instantiate()
	root.add_child(world_item)
	await wait_process_frames(1)
	var world_item_revision_before := int(world_item.call("get_state_revision"))
	world_item.call("set_collected_state", true, 10)
	assert_gt(int(world_item.call("get_state_revision")), world_item_revision_before, "Le WorldItem doit avancer sa revision sur collecte.")

	var coin := COIN_SCENE.instantiate()
	root.add_child(coin)
	await wait_process_frames(1)
	var coin_revision_before := int(coin.call("get_state_revision"))
	coin.call("_sync_coin_state", false, 2, Vector3(1.0, 0.0, 0.0), 10, false)
	coin.call("_sync_coin_state", true, -1, Vector3(1.0, 0.0, 0.0), 20, false)
	assert_gt(int(coin.call("get_state_revision")), coin_revision_before, "La Coin doit avancer sa revision sur ciblage/consommation.")

	var box := BOX_SCENE.instantiate()
	root.add_child(box)
	await wait_process_frames(1)
	var box_revision_before := int(box.call("get_state_revision"))
	box.call("_apply_destroy_state", false, false)
	assert_gt(int(box.call("get_state_revision")), box_revision_before, "La Box doit avancer sa revision sur destruction.")

	var portal := PORTAL_SCENE.instantiate()
	root.add_child(portal)
	await wait_process_frames(1)
	var portal_revision_before := int(portal.call("get_state_revision"))
	portal.call("set_portal_active", false)
	assert_gt(int(portal.call("get_state_revision")), portal_revision_before, "Le Portal doit avancer sa revision sur changement d'activation.")

	var cube := PULL_CUBE_SCRIPT.new() as PullableCube
	root.add_child(cube)
	await wait_process_frames(1)
	var cube_revision_before := cube.get_state_revision()
	cube.complete_goal(Vector3.ZERO)
	assert_gt(cube.get_state_revision(), cube_revision_before, "Le PullableCube doit avancer sa revision sur objectif atteint.")

	var director := MatchDirector.new()
	director.force_server_mode = true
	director.auto_start_match = false
	root.add_child(director)
	await wait_process_frames(1)
	var director_revision_before := director.get_state_revision()
	director.start_match()
	assert_gt(director.get_state_revision(), director_revision_before, "Le MatchDirector doit avancer sa revision sur nouveau snapshot.")
