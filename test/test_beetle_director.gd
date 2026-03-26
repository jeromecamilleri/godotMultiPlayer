extends GutTest

const BEETLE_DIRECTOR_SCRIPT := preload("res://enemies/beetle_director.gd")


func _spawn_fake_player(parent: Node3D, peer_id: int) -> Node3D:
	var player := Node3D.new()
	player.name = "Player%s" % peer_id
	player.set_multiplayer_authority(peer_id)
	parent.add_child(player)
	player.add_to_group("players")
	return player


func test_beetle_director_scales_to_three_beetles_for_four_players() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	for peer_id in [1, 2, 3, 4]:
		_spawn_fake_player(root, peer_id)

	var desired_count: int = int(director.call("_get_desired_beetle_count"))
	assert_eq(3, desired_count, "Avec 4 joueurs, le directeur doit viser 3 scarabées")


func test_beetle_director_assigns_unique_targets_until_shortage() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	var player_ids: Array[int] = [1, 2, 3, 4]
	var assignments: Array[int] = director.call("_build_target_assignments", 3, player_ids)
	assert_eq([1, 2, 3], assignments, "Les 3 scarabées doivent viser 3 joueurs distincts quand 4 joueurs sont vivants")


func test_beetle_director_reuses_targets_only_after_all_players_are_covered() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	var player_ids: Array[int] = [1, 2]
	var assignments: Array[int] = director.call("_build_target_assignments", 5, player_ids)
	assert_eq([1, 2, 1, 2, 1], assignments, "Le recyclage des cibles ne doit commencer qu'après avoir couvert tous les joueurs disponibles")
