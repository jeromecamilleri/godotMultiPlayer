extends GutTest

const PULL_CUBE_SCRIPT := preload("res://main/rigid_body_3d.gd")
const BARREL_SCENE := preload("res://environment/barrel/barrels.tscn")


func _assert_no_missing_peer_errors(context: String) -> void:
	for err in get_errors():
		if not err.is_engine_error():
			continue
		if err.contains_text("No multiplayer peer is assigned. Unable to get unique ID."):
			err.handled = true
			fail_test("%s ne doit pas appeler get_unique_id sans peer actif." % context)


func test_pullable_cube_without_peer_does_not_raise_unique_id_errors() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var cube := PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(cube)
	root.add_child(cube)
	await wait_process_frames(2)

	cube._physics_process(0.016)
	await wait_process_frames(1)

	_assert_no_missing_peer_errors("pullable cube sans peer")
	assert_true(cube.is_inside_tree(), "Le cube doit rester instanciable sans peer actif.")


func test_pushable_barrel_without_peer_does_not_raise_unique_id_errors() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var barrel := BARREL_SCENE.instantiate() as RigidBody3D
	assert_not_null(barrel)
	root.add_child(barrel)
	await wait_process_frames(2)

	barrel._physics_process(0.016)
	await wait_process_frames(1)

	_assert_no_missing_peer_errors("barrel sans peer")
	assert_true(barrel.is_inside_tree(), "Le barrel doit rester instanciable sans peer actif.")
