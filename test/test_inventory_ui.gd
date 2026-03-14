extends GutTest

const INVENTORY_PANEL_SCENE: PackedScene = preload("res://ui/inventory_panel.tscn")
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")


func test_inventory_panel_emits_selected_slot_action() -> void:
	var panel = INVENTORY_PANEL_SCENE.instantiate()
	add_child_autofree(panel)
	await wait_process_frames(1)

	panel.set_panel_state("Sac", [{"item_id": "wood", "display_name": "Bois", "quantity": 3}], [{"id": "drop", "label": "Deposer"}], "hint", 0)
	await wait_process_frames(1)

	var actions: HBoxContainer = panel.get_node("MarginContainer/VBoxContainer/Actions")
	assert_eq(1, actions.get_child_count())
	assert_eq(0, panel.get_selected_slot())
	panel._on_slot_pressed(0)
	assert_eq(0, panel.get_selected_slot())
	assert_false((actions.get_child(0) as Button).disabled)


func test_player_can_toggle_inventory_mode() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await wait_process_frames(1)

	assert_false(player.is_inventory_mode_open())
	player.toggle_inventory_mode()
	assert_true(player.is_inventory_mode_open())
	player.toggle_inventory_mode()
	assert_false(player.is_inventory_mode_open())
