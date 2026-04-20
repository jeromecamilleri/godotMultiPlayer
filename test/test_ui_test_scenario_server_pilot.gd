extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")
const UI_TEST_SCENARIO_SERVER_PILOT := preload("res://main/ui_test_scenario_server_pilot.gd")
const TERRAIN3D_DEPRECATION_TEXT := "instance_reset_physics_interpolation() is deprecated."
const TERRAIN3D_TEXTURE_WARNING_TEXT := "normal texture is not connected to a file."


func _handle_known_terrain3d_engine_warning() -> void:
	for err in get_errors():
		if err.is_engine_error() and (err.contains_text(TERRAIN3D_DEPRECATION_TEXT) or err.contains_text(TERRAIN3D_TEXTURE_WARNING_TEXT)):
			err.handled = true


func test_main_scene_exposes_ui_test_scenario_server_pilot() -> void:
	var root := Node.new()
	add_child_autofree(root)
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()

	var pilot := main.get_node_or_null("UiTestScenarioServerPilot")
	assert_not_null(pilot, "La scene principale doit exposer un pilote de scenario UI cote serveur.")
	assert_eq(NodePath("../MatchDirector"), pilot.get("match_director_path"), "Le pilote doit cibler explicitement le MatchDirector.")
	assert_eq(NodePath("../ZoneReactor/Interactives/Activator/CubeActivator"), pilot.get("reactor_activator_path"), "Le pilote doit cibler explicitement l'Activator du reactor.")


func test_ui_test_scenario_server_pilot_builds_stable_beetle_targeting_slots() -> void:
	var pilot := UI_TEST_SCENARIO_SERVER_PILOT.new()
	add_child_autofree(pilot)

	var slots: Array[Vector3] = pilot.call("_build_beetle_targeting_slots", Vector3(10.0, 0.0, 5.0), 5)
	assert_eq(3, slots.size(), "Le pilote ne doit preparer que les 3 joueurs clients du scenario beetle_targeting.")
	assert_eq(Vector3(7.0, 0.0, 7.2), slots[0], "Le slot client_1 doit rester stable autour de l'Activator.")
	assert_eq(Vector3(13.0, 0.0, 7.2), slots[1], "Le slot client_2 doit rester stable autour de l'Activator.")
	assert_eq(Vector3(10.0, 0.0, 2.8), slots[2], "Le slot client_3 doit rester stable autour de l'Activator.")
