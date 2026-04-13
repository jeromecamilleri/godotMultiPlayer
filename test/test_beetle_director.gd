extends GutTest

const BEETLE_DIRECTOR_SCRIPT := preload("res://enemies/beetle_director.gd")
const BEETLE_SCRIPT := preload("res://enemies/beetle_bot.gd")
const MAIN_SCENE := preload("res://main/main.tscn")
const PORTAL_SCENE := preload("res://levels/portal/portal.tscn")


func _spawn_fake_player(parent: Node3D, peer_id: int, position: Vector3 = Vector3.ZERO) -> Node3D:
	var player := Node3D.new()
	player.name = "Player%s" % peer_id
	player.set_multiplayer_authority(peer_id)
	parent.add_child(player)
	player.add_to_group("players")
	player.position = position
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


func test_beetle_director_resolves_explicit_defense_zone_and_seed_paths() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var guard_zone := Node3D.new()
	guard_zone.name = "GuardZone"
	guard_zone.position = Vector3(6.0, 0.0, 9.0)
	root.add_child(guard_zone)

	var seed := Node3D.new()
	seed.name = "SeedBeetle"
	root.add_child(seed)
	seed.add_to_group("beetles")

	var director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	director.defense_zone_path = NodePath("../GuardZone")
	var scene_root: Node = director.call("_get_scene_root")
	var seed_path: NodePath = scene_root.get_path_to(seed)
	director.managed_seed_beetle_paths = [seed_path]

	var config: Dictionary = director.call("_build_beetle_config", 2)

	assert_eq([seed_path], director.managed_seed_beetle_paths, "Le directeur doit conserver les scarabees graines explicites au lieu d'un scan global implicite.")
	assert_eq(Vector3(6.0, 0.0, 9.0), config.get("guard_center", Vector3.ZERO), "Le centre de garde doit venir de la zone de defense configuree.")


func test_main_scene_has_no_root_level_beetle_instance() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	var stray_beetle_names: Array[String] = []
	for child in main.get_children():
		if child.get_script() == BEETLE_SCRIPT:
			stray_beetle_names.append(String(child.name))
	assert_true(stray_beetle_names.is_empty(), "Aucun scarabée ne doit exister à la racine de la scène principale: %s" % str(stray_beetle_names))


func test_main_scene_beetle_director_targets_activator_zone() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)

	var director := main.get_node_or_null("ZoneReactor/Enemies/BeetleDirector")
	assert_not_null(director, "La scene principale doit embarquer un BeetleDirector.")
	assert_eq(NodePath("../../Interactives/Activator/CubeActivator"), director.get("defense_zone_path"), "Le BeetleDirector doit defendre explicitement la zone Activator du reactor.")
	assert_eq(NodePath("../../Interactives/Activator/CubeActivator"), director.get("activation_center_path"), "Le BeetleDirector doit utiliser l'Activator comme centre d'activation runtime.")
	assert_eq("", String(director.get("activation_portal_group")), "Le BeetleDirector du reactor doit se baser sur la présence joueur locale, pas sur un portail.")
	assert_true(bool(director.get("activation_requires_player_presence")), "Le BeetleDirector du reactor doit attendre un joueur dans la zone avant de s'activer.")
	assert_eq([], director.get("managed_seed_beetle_paths"), "La scene principale ne doit plus melanger scarabees seeds et dynamiques hors directeur.")


func test_main_scene_breche_beetle_director_targets_defense_zone() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)

	var director := main.get_node_or_null("ZoneBreche/Enemies/BeetleDirector")
	assert_not_null(director, "La scene principale doit embarquer un BeetleDirector dans la brèche.")
	assert_eq(NodePath("../../MissionMarkers/DefenseMarker"), director.get("defense_zone_path"), "Le BeetleDirector de la brèche doit défendre explicitement la zone centrale de la brèche.")
	assert_eq(NodePath("../../MissionMarkers/DefenseMarker"), director.get("activation_center_path"), "Le BeetleDirector de la brèche doit utiliser la zone centrale comme centre d'activation.")
	assert_eq("mission_portal_hub_breche", String(director.get("activation_portal_group")), "Le BeetleDirector de la brèche doit dépendre du portail de la brèche.")
	assert_true(bool(director.get("activation_requires_player_presence")), "Le BeetleDirector de la brèche doit attendre un joueur dans la zone avant de s'activer.")


func test_beetle_director_gates_population_by_portal_and_zone_presence() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var guard_zone := Node3D.new()
	guard_zone.name = "GuardZone"
	root.add_child(guard_zone)

	var portal := PORTAL_SCENE.instantiate()
	portal.name = "PortalHubScierie"
	root.add_child(portal)
	portal.add_to_group("mission_portal_hub_scierie")
	portal.call("set_portal_active", false)

	var director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	director.activation_center_path = NodePath("../GuardZone")
	director.activation_radius = 4.0
	director.activation_portal_group = "mission_portal_hub_scierie"
	director.activation_requires_player_presence = true

	await wait_process_frames(2)

	var player := _spawn_fake_player(root, 2, Vector3(1.0, 0.0, 0.0))
	assert_eq(0, int(director.call("_get_desired_beetle_count")), "Le directeur doit rester inactif si le portail de zone est fermé.")

	portal.call("set_portal_active", true)
	assert_eq(1, int(director.call("_get_desired_beetle_count")), "Le directeur doit s'activer quand le portail est ouvert et qu'un joueur est dans la zone.")
	director.call("_refresh_beetle_population")

	player.position = Vector3(12.0, 0.0, 0.0)
	assert_eq(1, int(director.call("_get_desired_beetle_count")), "Le directeur ne doit pas forcer un despawn des scarabées déjà actifs quand les joueurs quittent la zone.")


func test_main_scene_exposes_stable_mission_groups() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)

	var activator := main.get_node_or_null("ZoneReactor/Interactives/Activator/CubeActivator")
	var director := main.get_node_or_null("ZoneReactor/Enemies/BeetleDirector")
	var breche_director := main.get_node_or_null("ZoneBreche/Enemies/BeetleDirector")
	var chest := main.get_node_or_null("HubLevel/Env/Interactives/Chest")
	var primary_cube := main.get_node_or_null("ZoneReactor/Env/PhysicsObjects/RigidCube3D")
	var bomb_doors: Array[Node] = main.get_tree().get_nodes_in_group("mission_cube_bomb_doors")
	var blockers: Array[Node] = main.get_tree().get_nodes_in_group("mission_cube_blockers")

	assert_true(activator != null and activator.is_in_group("mission_cube_goal_zones"), "La zone Activator doit exposer un groupe stable de mission.")
	assert_true(activator != null and activator.is_in_group("defense_zones"), "La zone Activator doit aussi exposer un groupe stable de defense.")
	assert_true(director != null and director.is_in_group("enemy_directors"), "Le BeetleDirector doit exposer un groupe stable de directeurs ennemis.")
	assert_true(director != null and director.is_in_group("mission_cube_beetle_directors"), "Le BeetleDirector doit exposer un groupe stable de mission.")
	assert_true(breche_director != null and breche_director.is_in_group("mission_breche_beetle_directors"), "Le BeetleDirector de la brèche doit exposer un groupe stable dédié.")
	assert_true(chest != null and chest.is_in_group("mission_hub_chests"), "Le coffre du hub doit exposer un groupe stable.")
	assert_true(primary_cube != null and primary_cube.is_in_group("mission_cube_primary"), "Le cube principal doit exposer un groupe stable.")
	assert_true(bomb_doors.size() >= 3, "La mission cube doit exposer au moins 3 portes via un groupe stable.")
	for door in bomb_doors:
		assert_true(door is BombDoor, "Chaque porte de mission groupee doit rester un BombDoor.")
	assert_eq(3, blockers.size(), "La mission cube doit exposer exactement 3 caisses bloqueuses via un groupe stable.")
