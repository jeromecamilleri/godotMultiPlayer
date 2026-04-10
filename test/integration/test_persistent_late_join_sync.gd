extends GutTest

const WORLD_ITEM_SCENE := preload("res://inventory/world_item.tscn")
const CHEST_SCENE := preload("res://inventory/inventory_container.tscn")
const BOX_SCENE := preload("res://environment/box/box.tscn")
const DOOR_SCENE := preload("res://main/mission_cube_interactives.tscn")
const APPLE_ITEM := preload("res://inventory/items/apple.tres")
const PULL_CUBE_SCRIPT := preload("res://main/rigid_body_3d.gd")


func _spawn_root() -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	return root


func test_world_item_collected_state_can_be_reapplied_to_late_join_copy() -> void:
	var root := _spawn_root()
	var late_join_copy := WORLD_ITEM_SCENE.instantiate()
	root.add_child(late_join_copy)
	await wait_process_frames(1)

	late_join_copy.set_collected_state(true, 1200)

	assert_false(late_join_copy.visible)
	assert_false(late_join_copy.can_be_picked_up())
	assert_eq(1, late_join_copy.get_state_revision())


func test_bomb_door_open_state_can_be_reapplied_to_late_join_copy() -> void:
	var root := _spawn_root()
	var interactives := DOOR_SCENE.instantiate()
	root.add_child(interactives)
	await wait_process_frames(1)

	var late_join_copy := interactives.get_node("BombDoor") as BombDoor
	late_join_copy._set_open_state(true, 1600)

	assert_true(late_join_copy.is_open())
	assert_eq(1, late_join_copy.get_state_revision())


func test_box_destroyed_state_can_be_reapplied_to_late_join_copy() -> void:
	var root := _spawn_root()
	var late_join_copy := BOX_SCENE.instantiate()
	root.add_child(late_join_copy)
	await wait_process_frames(1)

	late_join_copy._sync_destroy_snapshot(true)

	assert_eq(1, late_join_copy.get_state_revision())
	assert_true(bool(late_join_copy.get("_destroyed")), "La copie late join doit être marquée détruite.")
	assert_string_contains(late_join_copy.get_debug_sync_summary(), "detruite")


func test_inventory_container_snapshot_can_be_reapplied_to_late_join_copy() -> void:
	var root := _spawn_root()
	var source_chest := CHEST_SCENE.instantiate()
	root.add_child(source_chest)
	await wait_process_frames(1)

	source_chest.get_inventory_component().add_payload(APPLE_ITEM.call("to_inventory_payload", 2))
	source_chest.call("_flush_inventory_snapshot_broadcast", true)
	var snapshot_json := String(source_chest.get("_inventory_snapshot_json"))
	var snapshot_revision := int(source_chest.get_state_revision())

	var late_join_copy := CHEST_SCENE.instantiate()
	root.add_child(late_join_copy)
	await wait_process_frames(1)
	late_join_copy.sync_inventory_snapshot(snapshot_json, 2200, snapshot_revision)

	assert_eq(2, late_join_copy.get_inventory_component().count_item("apple"))
	assert_eq(snapshot_revision, late_join_copy.get_state_revision())


func test_pullable_cube_goal_state_can_be_reapplied_to_late_join_copy() -> void:
	var root := _spawn_root()
	var late_join_copy := PULL_CUBE_SCRIPT.new() as PullableCube
	root.add_child(late_join_copy)
	await wait_process_frames(1)

	late_join_copy._sync_current_state(
		true,
		true,
		Transform3D(Basis.IDENTITY, Vector3(3.0, 4.0, 5.0)),
		Vector3.ZERO,
		Vector3.ZERO,
		PullableCube.PULL_STATE_GOAL,
		false
	)

	assert_true(late_join_copy.is_goal_reached())
	assert_eq(PullableCube.PULL_STATE_GOAL, late_join_copy._pull_state_sync)
	assert_eq(1, late_join_copy.get_state_revision())
