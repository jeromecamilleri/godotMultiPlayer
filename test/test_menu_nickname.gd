extends GutTest

const UI_SCENE := preload("res://ui/ui.tscn")
const MAIN_SCENE := preload("res://main/main.tscn")
const USER_DATA_SCENE := preload("res://user_data/user_data.tscn")


func test_main_menu_exposes_default_player_name_before_launch() -> void:
	var ui: Control = autofree(UI_SCENE.instantiate()) as Control

	var player_name_edit := ui.get_node_or_null("MainMenu/Buttons/PlayerNameConfig/PlayerNameEdit") as LineEdit

	assert_not_null(player_name_edit)
	assert_eq("Player", player_name_edit.text)
	assert_eq("Player", player_name_edit.placeholder_text)
	assert_eq(20, player_name_edit.max_length)


func test_client_ui_no_longer_contains_player_list_overlay() -> void:
	var ui: Control = autofree(UI_SCENE.instantiate()) as Control

	assert_null(ui.get_node_or_null("InGameUI/MarginContainer"))


func test_player_hud_groups_timer_with_mission_panel_and_keeps_network_in_debug() -> void:
	var ui: Control = autofree(UI_SCENE.instantiate()) as Control
	var timer := ui.get_node("InGameUI/MatchTimer") as Label
	var player_stats := ui.get_node("InGameUI/PlayerStats") as Label
	var mission_backdrop := ui.get_node("InGameUI/MissionTrackerBackdrop") as ColorRect
	var mission_body := ui.get_node("InGameUI/MissionTrackerBody") as Label
	var network_stats := ui.get_node("InGameUI/NetworkStats") as Label
	var server_black_backdrop := ui.get_node("InGameUI/ServerBlackBackdrop") as ColorRect
	var debug_backdrop := ui.get_node("InGameUI/DebugOverlayBackdrop") as ColorRect

	assert_not_null(timer)
	assert_not_null(player_stats)
	assert_not_null(mission_backdrop)
	assert_not_null(mission_body)
	assert_not_null(network_stats)
	assert_not_null(server_black_backdrop)
	assert_not_null(debug_backdrop)
	var mission_title := ui.get_node("InGameUI/MissionTrackerTitle") as Label
	assert_lt(timer.offset_top, player_stats.offset_top)
	assert_lt(player_stats.offset_top, mission_title.offset_top)
	assert_gt(mission_backdrop.offset_bottom, timer.offset_bottom, "Le panneau mission doit englober le timer.")
	assert_gt(mission_backdrop.offset_bottom, player_stats.offset_bottom, "Le panneau mission doit englober les stats persistantes du joueur.")
	assert_gt(mission_backdrop.offset_bottom, mission_body.offset_bottom, "Le panneau mission doit laisser une marge sous la derniere ligne.")
	assert_false(network_stats.visible, "Les stats reseau ne doivent plus etre affichees en HUD normal.")
	assert_false(server_black_backdrop.visible, "Le fond noir serveur est masque cote scene par defaut.")
	assert_eq(1.0, debug_backdrop.anchor_left, "Le debug F1 doit etre ancre a droite pour ne pas couvrir le suivi mission.")
	assert_eq(1.0, debug_backdrop.anchor_right)
	assert_eq(0.0, debug_backdrop.anchor_top, "Le fond du debug F1 doit couvrir les premieres lignes.")
	assert_lt(debug_backdrop.offset_left, 0.0)
	assert_lt(debug_backdrop.offset_right, 0.0)
	assert_gt(debug_backdrop.offset_top, 0.0)


func test_main_scene_no_longer_instantiates_voice_runtime() -> void:
	var main: Node = autofree(MAIN_SCENE.instantiate()) as Node

	assert_null(main.get_node_or_null("VoipManager"))
	assert_null(main.get_node_or_null("Microphone"))


func test_user_data_replication_only_contains_nickname() -> void:
	var user_data: Node = autofree(USER_DATA_SCENE.instantiate()) as Node
	var synchronizer := user_data.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var replication_config: SceneReplicationConfig = synchronizer.replication_config
	var replicated_properties: Array[NodePath] = replication_config.get_properties()

	assert_eq(1, replicated_properties.size())
	assert_eq(NodePath(".:nickname"), replicated_properties[0])
