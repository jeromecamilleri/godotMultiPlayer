extends SceneTree

const CHARACTER_SKIN_SCENE := preload("res://player/model/character_skin.tscn")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var output_dir := args[0] if not args.is_empty() else "/tmp/swim-pose-ui"
	DirAccess.make_dir_recursive_absolute(output_dir)

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.72, 0.92, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.15
	env.environment = environment
	world.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 2.0
	world.add_child(light)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	water.mesh = plane
	water.position.y = 0.0
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.25, 0.65, 0.95, 0.62)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.material_override = water_material
	world.add_child(water)

	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	world.add_child(skin)
	await process_frame
	skin.swim_pose_transition_speed = 100.0
	skin.set_swimming(true)
	for i in 10:
		await process_frame

	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(4.5, 0.75, 0.25)
	camera.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)
	camera.fov = 34.0
	camera.current = true
	for i in 8:
		await process_frame

	var screenshot_path := output_dir.path_join("swim_pose.png")
	root.get_viewport().get_texture().get_image().save_png(screenshot_path)

	var skeleton := skin.get_node("gdbot/Armature/Skeleton3D") as Skeleton3D
	var head_idx := skeleton.find_bone("head")
	var head_pose := skeleton.get_bone_global_pose(head_idx)
	var model_root := skin.get_node("gdbot") as Node3D
	var face_direction := (model_root.global_basis * head_pose.basis.z).normalized()
	var expected_direction := (Vector3.FORWARD + (Vector3.UP * skin.swim_look_up_bias)).normalized()
	var face_angle := rad_to_deg(face_direction.angle_to(expected_direction))
	var summary := {
		"face_angle_from_expected_degrees": face_angle,
		"face_direction_y": face_direction.y,
		"model_pitch_degrees": model_root.rotation_degrees.x,
		"screenshot": screenshot_path,
	}
	var file := FileAccess.open(output_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	quit()
