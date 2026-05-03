extends GutTest

const FLOATING_NICKNAME_SCRIPT := preload("res://ui/floating_nickname.gd")


func _assert_no_unproject_errors(context: String) -> void:
	for err in get_errors():
		if err.is_engine_error() and err.contains_text("unproject_position"):
			err.handled = true
			fail_test("%s ne doit pas appeler Camera3D.unproject_position avec une projection invalide." % context)


func test_process_hides_label_when_anchor_is_on_camera_projection_plane() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var camera := Camera3D.new()
	camera.current = true
	world.add_child(camera)

	var anchor := Node3D.new()
	world.add_child(anchor)

	var nickname := FLOATING_NICKNAME_SCRIPT.new()
	nickname.anchor = anchor
	add_child_autofree(nickname)
	await wait_process_frames(1)

	nickname._process(0.016)

	_assert_no_unproject_errors("floating nickname sur le plan camera")
	assert_false(nickname.visible, "Le pseudo flottant doit se cacher quand sa projection 2D est invalide.")
