extends GutTest


class TestUI:
	extends "res://ui/ui.gd"

	var fake_peer_id := 1

	func _ready() -> void:
		pass

	func _get_local_peer_id() -> int:
		return fake_peer_id


func test_won_by_timer_does_not_report_cube_mission_accomplished() -> void:
	var ui := TestUI.new()

	ui._match_status_text = "\n".join([
		"MATCH",
		"state: WON",
		"result_reason: timer_completed",
		"time_left: 0.0s",
		"players: 1",
		"team_score: 4",
		"score:",
		"peer_1: 0",
		"lives:",
		"peer_1: 5",
		"deaths:",
		"peer_1: 0",
		"objectives:",
		"cube_activator_reached: 0",
		"mission_phase: 3",
	])

	var phase_data := ui._build_mission_phase_data()
	assert_ne("MISSION ACCOMPLIE", String(phase_data.get("title", "")), "Le tracker ne doit pas annoncer la mission finale reussie sur un simple WON par timer.")
	ui.free()


func test_won_by_cube_activator_reports_mission_accomplished() -> void:
	var ui := TestUI.new()

	ui._match_status_text = "\n".join([
		"MATCH",
		"state: WON",
		"result_reason: cube_activator_reached",
		"time_left: 12.0s",
		"players: 1",
		"team_score: 9",
		"score:",
		"peer_1: 0",
		"lives:",
		"peer_1: 5",
		"deaths:",
		"peer_1: 0",
		"objectives:",
		"cube_activator_reached: 1",
		"mission_phase: 4",
	])

	var phase_data := ui._build_mission_phase_data()
	assert_eq("MISSION ACCOMPLIE", String(phase_data.get("title", "")), "Le tracker doit annoncer la reussite quand le cube atteint vraiment l'Activator.")
	assert_string_contains(String(phase_data.get("body", "")), "Score equipe: 9")
	ui.free()


func test_local_player_stats_use_snapshot_score_and_lives() -> void:
	var ui := TestUI.new()
	ui.fake_peer_id = 2
	ui._match_status_text = "\n".join([
		"MATCH",
		"state: RUNNING",
		"result_reason: ",
		"time_left: 60.0s",
		"players: 2",
		"team_score: 12",
		"score:",
		"peer_1: 4",
		"peer_2: 8",
		"lives:",
		"peer_1: 5",
		"peer_2: 2",
		"deaths:",
		"peer_1: 0",
		"peer_2: 3",
		"objectives:",
		"mission_phase: 2",
	])

	assert_eq("Vies: 2   Score: 8", ui._format_local_player_stats_text())
	ui.free()
