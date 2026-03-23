extends GutTest

const MATCH_DIRECTOR_SCRIPT: GDScript = preload("res://main/match_director.gd")
const PULL_CUBE_SCRIPT: GDScript = preload("res://main/rigid_body_3d.gd")
const CUBE_ACTIVATOR_SCRIPT: GDScript = preload("res://main/cube_activator.gd")


func test_cube_activator_completes_objective_and_wins_match() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var director: MatchDirector = MATCH_DIRECTOR_SCRIPT.new() as MatchDirector
	director.force_server_mode = true
	director.auto_start_match = false
	world.add_child(director)
	await wait_process_frames(1)
	director.start_match()

	var activator: Area3D = CUBE_ACTIVATOR_SCRIPT.new() as Area3D
	activator.objective_id = "cube_activator_reached"
	activator.win_reason = "cube_activator_reached"
	world.add_child(activator)
	activator.global_position = Vector3(3.0, 0.0, 0.0)

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.4
	cylinder.height = 2.5
	shape.shape = cylinder
	activator.add_child(shape)
	await wait_process_frames(1)

	var cube: PullableCube = PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(cube)
	cube.server_peer_id = multiplayer.get_unique_id()
	world.add_child(cube)
	cube.global_position = Vector3(3.2, 0.0, 0.2)
	await wait_process_frames(2)

	activator._on_body_entered(cube)
	await wait_process_frames(1)

	assert_true(cube.is_goal_reached(), "Le cube doit etre marque comme objectif atteint dans l'activateur.")
	assert_true(cube.freeze, "Le cube doit etre fige une fois amene sur l'activateur.")
	assert_eq(3, cube._pull_state_sync, "Le cube doit diffuser l'etat GOAL.")

	var snapshot: String = director.get_snapshot_text()
	assert_true(snapshot.find("cube_activator_reached: 1") >= 0, "Le directeur doit enregistrer l'objectif coop.")
	assert_true(snapshot.find("state: WON") >= 0, "L'activateur doit permettre de terminer la mission.")
