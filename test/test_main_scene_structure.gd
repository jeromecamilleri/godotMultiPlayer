extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")


func test_main_scene_preserves_modular_runtime_paths() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await wait_process_frames(3)

	assert_not_null(main.get_node_or_null("HubLevel/Env/Enemies"), "La scène doit conserver le conteneur Enemies.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/Enemies/BeetleDirector"), "La scène doit conserver le BeetleDirector sous Enemies.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/PhysicsObjects"), "La scène doit conserver le conteneur PhysicsObjects.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/PhysicsObjects/RigidCube3D"), "La scène doit conserver le cube principal sous PhysicsObjects.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/Interactives"), "La scène doit conserver le conteneur Interactives.")
	assert_not_null(main.get_node_or_null("HubLevel/Ground/Activator/CubeActivator"), "La scène doit conserver le chemin logique vers CubeActivator.")

	var cube := main.get_tree().get_first_node_in_group("mission_cube_primary")
	assert_not_null(cube)
	assert_eq(NodePath("HubLevel/Env/PhysicsObjects/RigidCube3D"), main.get_path_to(cube))
