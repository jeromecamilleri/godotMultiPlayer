extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")


func test_main_scene_preserves_modular_runtime_paths() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await wait_process_frames(3)

	assert_not_null(main.get_node_or_null("HubLevel/Env/Enemies"), "La scène doit conserver le conteneur Enemies.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/PhysicsObjects"), "La scène doit conserver le conteneur PhysicsObjects.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/Interactives"), "La scène doit conserver le conteneur Interactives.")
	assert_not_null(main.get_node_or_null("ZoneScierie"), "La scène doit exposer la zone Scierie.")
	assert_not_null(main.get_node_or_null("ZoneVerger"), "La scène doit exposer la zone Verger.")
	assert_not_null(main.get_node_or_null("ZoneBreche"), "La scène doit exposer la zone Brèche.")
	assert_not_null(main.get_node_or_null("ZoneReactor"), "La scène doit exposer la zone Reactor.")
	assert_not_null(main.get_node_or_null("ZoneBreche/Enemies/BeetleDirector"), "La scène doit exposer le BeetleDirector dans la zone Brèche.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Interactives/Activator/CubeActivator"), "La scène doit exposer la zone objectif du réacteur.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Env/PhysicsObjects/RigidCube3D"), "La scène doit exposer le cube principal dans la zone Reactor.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Enemies/BeetleDirector"), "La scène doit exposer le BeetleDirector dans la zone Reactor.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Scierie"), "Le hub doit exposer le portail vers la Scierie.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Verger"), "Le hub doit exposer le portail vers le Verger.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Breche"), "Le hub doit exposer le portail vers la Brèche.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Reactor"), "Le hub doit exposer le portail vers le Reactor.")
	assert_not_null(main.get_node_or_null("ZoneScierie/Portals/Portal_Scierie_To_Hub"), "La Scierie doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneVerger/Portals/Portal_Verger_To_Hub"), "Le Verger doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneBreche/Portals/Portal_Breche_To_Hub"), "La Brèche doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Portals/Portal_Reactor_To_Hub"), "Le Reactor doit exposer son portail retour.")

	var cube := main.get_tree().get_first_node_in_group("mission_cube_primary")
	assert_not_null(cube)
	assert_eq(NodePath("ZoneReactor/Env/PhysicsObjects/RigidCube3D"), main.get_path_to(cube))
