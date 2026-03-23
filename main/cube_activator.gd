extends Area3D
class_name CubeActivator

@export var objective_id := "cube_activator_reached"
@export var win_reason := "cube_activator_reached"
@export var trigger_once := true
@export var complete_match_on_activate := true
@export var snap_cube_to_center := true
@export var vertical_snap_offset := 0.8

var _activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _activated and trigger_once:
		return
	if not _is_server_instance():
		return
	if body == null or not body.is_in_group("pullable_cubes"):
		return
	var cube := body as PullableCube
	if cube == null:
		return
	var target_position := cube.global_position
	if snap_cube_to_center:
		target_position = global_position + Vector3(0.0, vertical_snap_offset, 0.0)
	cube.complete_goal(target_position)
	_activated = true
	_report_activation()
	_write_ui_test_server_result(cube, target_position)


func _report_activation() -> void:
	var director := get_tree().get_first_node_in_group("match_director")
	if director == null:
		return
	if objective_id.strip_edges() != "" and director.has_method("report_objective_progress"):
		director.report_objective_progress(objective_id, 1)
	if complete_match_on_activate and director.has_method("report_team_won"):
		director.report_team_won(win_reason)


func _is_server_instance() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _write_ui_test_server_result(cube: PullableCube, target_position: Vector3) -> void:
	var scenario := OS.get_environment("UI_TEST_SCENARIO").strip_edges().to_lower()
	if scenario != "cube_mission" and scenario != "cube_mission_lock":
		return
	var sync_dir := OS.get_environment("UI_TEST_SYNC_DIR").strip_edges()
	if sync_dir.is_empty():
		return
	var file := FileAccess.open("%s/cube_mission_server.json" % sync_dir, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"state": "WON",
		"cube_goal": cube != null and cube.is_goal_reached(),
		"cube_on_goal_visual": true,
		"cube_position": [target_position.x, target_position.y, target_position.z],
	}))
	file.close()
