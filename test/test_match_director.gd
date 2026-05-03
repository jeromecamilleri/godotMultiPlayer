extends GutTest

const MATCH_DIRECTOR_SCRIPT := preload("res://main/match_director.gd")
var _previous_dev_spawn_zone := ""


func before_each() -> void:
	_previous_dev_spawn_zone = OS.get_environment("DEV_SPAWN_ZONE")


func after_each() -> void:
	OS.set_environment("DEV_SPAWN_ZONE", _previous_dev_spawn_zone)

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


func _make_fake_inventory(wood_count: int, apple_count: int) -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node
var wood := 0
var apple := 0
func count_item(item_id: String) -> int:
	if item_id == "wood":
		return wood
	if item_id == "apple":
		return apple
	return 0
"""
	assert_eq(OK, script.reload())
	var inventory := Node.new()
	inventory.set_script(script)
	inventory.set("wood", wood_count)
	inventory.set("apple", apple_count)
	return inventory


func _make_fake_chest(inventory: Node) -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node
var inventory_ref: Node = null
func get_inventory_component():
	return inventory_ref
"""
	assert_eq(OK, script.reload())
	var chest := Node.new()
	chest.set_script(script)
	chest.set("inventory_ref", inventory)
	chest.add_to_group("mission_hub_chests")
	return chest


func _make_fake_portal(group_name: String) -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node
var active := false
func set_portal_active(value: bool) -> void:
	active = value
func is_portal_active() -> bool:
	return active
"""
	assert_eq(OK, script.reload())
	var portal := Node.new()
	portal.set_script(script)
	portal.add_to_group(group_name)
	return portal


func _make_fake_bomb_door(opened: bool) -> Node:
	var script := GDScript.new()
	script.source_code = """
extends Node
var opened := false
func is_open() -> bool:
	return opened
"""
	assert_eq(OK, script.reload())
	var door := Node.new()
	door.set_script(script)
	door.set("opened", opened)
	door.add_to_group("mission_cube_bomb_doors")
	return door


func test_register_peer_auto_starts_running() -> void:
	var director := await _create_director()
	director.register_peer(10)
	await wait_process_frames(1)

	assert_eq("RUNNING", director.get_state_name(), "First peer should auto-start the match")
	assert_true(director.get_snapshot_text().find("state: RUNNING") >= 0, "Snapshot must expose running state")


func test_timer_reaching_zero_sets_lost() -> void:
	var director := await _create_director(0.25)
	director.register_peer(1)
	await wait_seconds(0.5)
	await wait_process_frames(2)

	var snapshot: String = director.get_snapshot_text()
	assert_eq("LOST", director.get_state_name(), "Timer expiration doit echouer la mission si l'objectif final n'est pas atteint.")
	assert_true(snapshot.find("state: LOST") >= 0, "Le snapshot doit exposer l'echec par expiration du timer.")
	assert_true(snapshot.find("result_reason: timer_expired") >= 0, "La raison permet a l'UI de ne pas afficher mission reussie.")


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


func test_dev_spawn_zone_reactor_unlocks_required_portals_on_match_start() -> void:
	OS.set_environment("DEV_SPAWN_ZONE", "reactor")
	var director := await _create_director(5.0)
	director.register_peer(15)
	await wait_process_frames(1)
	var snapshot: String = director.get_snapshot_text()

	assert_true(snapshot.find("portal_breche_unlocked: 1") >= 0, "DEV_SPAWN_ZONE=reactor doit déverrouiller le portail brèche.")
	assert_true(snapshot.find("portal_reactor_unlocked: 1") >= 0, "DEV_SPAWN_ZONE=reactor doit déverrouiller le portail reactor.")


func test_zone_progression_exposes_collect_breche_reactor_phases() -> void:
	var director := await _create_director(5.0)
	director.register_peer(21)
	await wait_process_frames(1)

	var inventory := _make_fake_inventory(6, 2)
	add_child_autofree(inventory)
	var chest := _make_fake_chest(inventory)
	add_child_autofree(chest)
	var portal_breche := _make_fake_portal("mission_portal_hub_breche")
	add_child_autofree(portal_breche)
	var portal_reactor := _make_fake_portal("mission_portal_hub_reactor")
	add_child_autofree(portal_reactor)
	var door_a := _make_fake_bomb_door(false)
	var door_b := _make_fake_bomb_door(false)
	var door_c := _make_fake_bomb_door(false)
	add_child_autofree(door_a)
	add_child_autofree(door_b)
	add_child_autofree(door_c)

	director.call("_update_zone_progression")
	director.call("_emit_snapshot")
	var snapshot_collect: String = director.get_snapshot_text()
	assert_true(snapshot_collect.find("mission_phase: 1") >= 0, "Phase 1 attendue tant que les quotas coffre ne sont pas atteints.")
	assert_true(snapshot_collect.find("required_bomb_doors: 3") >= 0, "Le snapshot doit publier le nombre total de BombDoor.")
	assert_true(snapshot_collect.find("bomb_door_opened: 0") >= 0)

	inventory.set("wood", 10)
	inventory.set("apple", 4)
	director.call("_update_zone_progression")
	director.call("_emit_snapshot")
	var snapshot_breche: String = director.get_snapshot_text()
	assert_true(snapshot_breche.find("portal_breche_unlocked: 1") >= 0, "Le portail brèche doit s'ouvrir après dépôt des quotas.")
	assert_true(snapshot_breche.find("mission_phase: 2") >= 0, "Le directeur doit exposer la phase BRECHE.")

	door_a.set("opened", true)
	director.call("_update_zone_progression")
	director.call("_emit_snapshot")
	var snapshot_breche_doors: String = director.get_snapshot_text()
	assert_true(snapshot_breche_doors.find("bomb_door_opened: 1") >= 0, "La progression BombDoor doit suivre l'état réel des portes.")
	assert_true(snapshot_breche_doors.find("mission_phase: 2") >= 0)

	door_b.set("opened", true)
	door_c.set("opened", true)
	director.call("_update_zone_progression")
	director.call("_emit_snapshot")
	var snapshot_reactor: String = director.get_snapshot_text()
	assert_true(snapshot_reactor.find("portal_reactor_unlocked: 1") >= 0, "Le portail reactor doit s'ouvrir quand toutes les BombDoor sont ouvertes.")
	assert_true(snapshot_reactor.find("mission_phase: 3") >= 0, "Le directeur doit exposer la phase REACTOR.")


func test_timer_expiration_keeps_current_mission_phase() -> void:
	var director := await _create_director(5.0)
	director.register_peer(31)
	await wait_process_frames(1)

	director.call("_update_zone_progression")
	director.call("report_team_lost", "timer_expired")
	var snapshot: String = director.get_snapshot_text()

	assert_true(snapshot.find("state: LOST") >= 0, "L'expiration doit rester un echec de match.")
	assert_true(snapshot.find("mission_phase: 1") >= 0, "L'expiration ne doit pas transformer une collecte incomplete en phase finale.")
	assert_false(snapshot.find("mission_phase: 4") >= 0, "La phase 4 est reservee au cube pose sur l'Activator.")
