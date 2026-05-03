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
