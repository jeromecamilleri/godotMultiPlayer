extends GutTest


class TestUI:
	extends "res://ui/ui.gd"

	func _ready() -> void:
		pass


func test_won_by_timer_does_not_report_cube_mission_accomplished() -> void:
	var ui := TestUI.new()

	ui._match_status_text = "\n".join([
		"MATCH",
		"state: WON",
		"result_reason: timer_completed",
		"time_left: 0.0s",
		"players: 1",
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
	ui.free()
