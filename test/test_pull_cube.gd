extends GutTest

const PULL_CUBE_SCRIPT: GDScript = preload("res://main/rigid_body_3d.gd")


func test_pull_vector_accumulates_when_players_pull_same_side() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var cube: RigidBody3D = PULL_CUBE_SCRIPT.new() as RigidBody3D
	assert_not_null(cube)
	world.add_child(cube)
	await wait_process_frames(1)

	var points: Array[Vector3] = [Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)]
	var net: Vector3 = cube.compute_pull_vector_from_points(points)

	assert_true(net.length() > 1.9, "Two players pulling same direction should strongly accumulate")
	assert_true(net.x > 0.0, "Accumulated direction should point toward players")


func test_pull_vector_cancels_when_players_pull_opposite() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var cube: RigidBody3D = PULL_CUBE_SCRIPT.new() as RigidBody3D
	assert_not_null(cube)
	world.add_child(cube)
	await wait_process_frames(1)

	var points: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)]
	var net: Vector3 = cube.compute_pull_vector_from_points(points)

	assert_true(net.length() < 0.05, "Opposite pull directions should mostly cancel")


func test_cube_reaching_reactor_switches_to_goal_state() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var reactor := Node3D.new()
	reactor.name = "reactor"
	reactor.position = Vector3(0.0, 0.0, 0.0)
	world.add_child(reactor)

	var cube: RigidBody3D = PULL_CUBE_SCRIPT.new() as RigidBody3D
	cube.server_peer_id = multiplayer.get_unique_id()
	cube.reactor_goal_radius = 2.5
	cube.position = Vector3(1.0, 0.0, 0.0)
	world.add_child(cube)
	await wait_process_frames(3)

	assert_true(cube.evaluate_goal_reached(), "Cube should be detected inside reactor goal radius")
	assert_true(cube.freeze, "Cube should freeze once parked in reactor")
	assert_eq(3, cube._pull_state_sync, "Goal state should be replicated as state=3")
