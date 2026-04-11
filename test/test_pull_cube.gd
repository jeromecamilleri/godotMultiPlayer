extends GutTest

const PULL_CUBE_SCRIPT: GDScript = preload("res://main/rigid_body_3d.gd")


func _make_fake_player(peer_id: int, locked: bool) -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D
var debug_locked := false
func is_debug_position_locked() -> bool:
	return debug_locked
func is_dead() -> bool:
	return false
"""
	var reload_error := script.reload()
	assert_eq(OK, reload_error)
	var player := Node3D.new()
	player.set_script(script)
	player.set_multiplayer_authority(peer_id)
	player.set("debug_locked", locked)
	player.add_to_group("players")
	return player


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


func test_coop_force_uses_goal_direction_when_locked_anchor_and_opposed_pulls() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var cube: PullableCube = PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(cube)
	world.add_child(cube)
	await wait_process_frames(1)

	var intents: Array[Vector3] = [Vector3(1.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)]
	var goal_dir := Vector3(0.0, 0.0, 1.0)
	var coop_force := cube.compute_coop_force_vector(intents, goal_dir, true)

	assert_true(coop_force.length() > 1.9, "Avec une ancre verrouillee, le cube doit quand meme recevoir une direction coop vers l'objectif.")
	assert_true(coop_force.z > 0.9, "La direction de secours doit pointer vers l'activateur.")


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


func test_cube_late_join_state_snapshot_reapplies_goal_visual_state() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var authoritative_cube: PullableCube = PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(authoritative_cube)
	authoritative_cube.server_peer_id = multiplayer.get_unique_id()
	world.add_child(authoritative_cube)
	await wait_process_frames(1)

	var goal_transform := Transform3D(Basis.IDENTITY, Vector3(6.0, 1.2, -3.0))
	authoritative_cube.complete_goal(goal_transform.origin)
	authoritative_cube.global_transform = goal_transform

	var late_join_cube: PullableCube = PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(late_join_cube)
	world.add_child(late_join_cube)
	await wait_process_frames(1)

	late_join_cube._apply_current_state(
		true,
		true,
		goal_transform,
		Vector3.ZERO,
		Vector3.ZERO,
		authoritative_cube.PULL_STATE_GOAL,
		false
	)

	assert_true(late_join_cube.is_goal_reached(), "Un late joiner doit voir le cube deja termine comme objectif atteint.")
	assert_true(late_join_cube.freeze, "Le cube resynchronise doit etre fige chez le late joiner.")
	assert_eq(goal_transform.origin, late_join_cube.global_transform.origin, "La position repliquée du cube doit etre reappliquee au late joiner.")
	assert_eq(authoritative_cube.PULL_STATE_GOAL, late_join_cube._pull_state_sync, "L'etat visuel GOAL doit etre reapplique au late joiner.")


func test_locked_anchor_can_remain_attached_beyond_normal_distance() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var cube: PullableCube = PULL_CUBE_SCRIPT.new() as PullableCube
	assert_not_null(cube)
	cube.server_peer_id = multiplayer.get_unique_id()
	world.add_child(cube)

	var locked_player := _make_fake_player(2, true)
	world.add_child(locked_player)
	locked_player.transform.origin = Vector3(12.0, 0.0, 0.0)
	await wait_process_frames(1)

	cube._attached_peers[2] = {
		"active": true,
		"intent_dir": Vector3.RIGHT,
		"last_seen_ms": Time.get_ticks_msec(),
	}

	assert_false(cube._is_peer_attachable(2), "Hors debug lock, cette distance doit rester trop grande.")
	assert_true(cube._is_peer_attachable(2, true), "Une ancre verrouillee deja attachee doit rester valide plus loin pour le test coop.")
	cube._cleanup_invalid_attached_peers()
	assert_true(cube._attached_peers.has(2), "Le nettoyage ne doit pas detacher une ancre verrouillee encore utile.")
