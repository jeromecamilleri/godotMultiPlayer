extends GutTest


func _setup_cube() -> PullableCube:
	var world := Node3D.new()
	add_child_autofree(world)

	var cube: PullableCube = PullableCube.new()
	world.add_child(cube)
	await wait_process_frames(1)

	var reactor := Node3D.new()
	reactor.position = Vector3(0, 0, 4)
	world.add_child(reactor)
	cube._reactor_node = reactor
	return cube


func test_auto_move_ready_when_players_pull_aligned() -> void:
	var cube := await _setup_cube()
	cube._attached_peers[1] = true
	cube._attached_peers[2] = true

	var net_pull := Vector3(0, 0, 1)
	assert_true(cube.should_auto_move(net_pull))


func test_auto_move_not_ready_when_pull_misaligned() -> void:
	var cube := await _setup_cube()
	cube._attached_peers[1] = true
	cube._attached_peers[2] = true

	var net_pull := Vector3(0, 0, -1)
	assert_false(cube.should_auto_move(net_pull))
