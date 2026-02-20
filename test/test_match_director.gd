extends GutTest

const MATCH_DIRECTOR_SCRIPT := preload("res://main/match_director.gd")

func _create_director(match_duration_sec: float = 0.6) -> Node:
	# Build the node in isolation and force server behavior for deterministic tests.
	var director := MATCH_DIRECTOR_SCRIPT.new()
	director.force_server_mode = true
	director.auto_start_match = true
	director.min_players_to_start = 1
	director.match_duration_sec = match_duration_sec
	director.tick_interval_sec = 0.1
	add_child_autofree(director)
	await wait_process_frames(2)
	return director


func test_register_peer_auto_starts_running() -> void:
	var director := await _create_director()
	director.register_peer(10)
	await wait_process_frames(1)

	assert_eq("RUNNING", director.get_state_name(), "First peer should auto-start the match")
	assert_true(director.get_snapshot_text().find("state: RUNNING") >= 0, "Snapshot must expose running state")


func test_timer_reaching_zero_sets_won() -> void:
	var director := await _create_director(0.25)
	director.register_peer(1)
	await wait_seconds(0.5)
	await wait_process_frames(2)

	assert_eq("WON", director.get_state_name(), "Timer completion should mark the team as WON")
	assert_true(director.get_snapshot_text().find("state: WON") >= 0, "Snapshot must expose won state")


func test_score_updates_are_reflected_in_snapshot() -> void:
	var director := await _create_director(5.0)
	director.register_peer(3)
	director.add_score_for_peer(3, 7)
	await wait_process_frames(1)

	assert_true(director.get_snapshot_text().find("peer_3: 7") >= 0, "Snapshot must include updated score per peer")


func test_unregister_last_peer_marks_lost_while_running() -> void:
	var director := await _create_director(5.0)
	director.register_peer(5)
	await wait_process_frames(1)
	director.unregister_peer(5)
	await wait_process_frames(1)

	assert_eq("LOST", director.get_state_name(), "Removing the last peer during a running match should set LOST")


func test_report_player_fell_decrements_lives_and_counts_deaths() -> void:
	var director := await _create_director(5.0)
	director.register_peer(9)
	await wait_process_frames(1)
	var next_lives: int = director.report_player_fell(9)
	await wait_process_frames(1)

	assert_eq(4, next_lives, "A fall should decrement one life from default 5")
	assert_true(director.get_snapshot_text().find("peer_9: 4") >= 0, "Snapshot should expose updated lives")
	assert_true(director.get_snapshot_text().find("deaths:") >= 0, "Snapshot should include death counters")


func test_enemy_kill_reports_score_and_objective_progress() -> void:
	var director := await _create_director(5.0)
	director.register_peer(11)
	await wait_process_frames(1)
	director.report_enemy_killed("bee_bot", 11)
	await wait_process_frames(1)
	var snapshot: String = director.get_snapshot_text()

	assert_true(snapshot.find("peer_11: 1") >= 0, "Killer should receive +1 score")
	assert_true(snapshot.find("bees_killed: 1") >= 0, "Enemy objective progress should be incremented")
