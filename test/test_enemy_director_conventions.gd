extends GutTest

const BEE_DIRECTOR_SCRIPT := preload("res://enemies/bee_director.gd")
const BEETLE_DIRECTOR_SCRIPT := preload("res://enemies/beetle_director.gd")
const BEE_SCENE := preload("res://enemies/bee_bot.tscn")
const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")
const PORTAL_SCENE := preload("res://levels/portal/portal.tscn")
const ZONE_VERGER_SCENE := preload("res://levels/zones/verger/zone_verger.tscn")


func test_enemy_instances_expose_common_director_contract() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var bee := BEE_SCENE.instantiate()
	var beetle := BEETLE_SCENE.instantiate()
	root.add_child(bee)
	root.add_child(beetle)

	assert_true(bee.is_in_group("enemy_instances"), "Une abeille doit exposer le groupe générique des ennemis gérés.")
	assert_true(beetle.is_in_group("enemy_instances"), "Un scarabée doit exposer le groupe générique des ennemis gérés.")
	assert_true(bee.is_in_group("replicated_persistent_objects"), "Une abeille doit être visible comme objet persistant répliqué.")
	assert_true(beetle.is_in_group("replicated_persistent_objects"), "Un scarabée doit être visible comme objet persistant répliqué.")
	assert_true(bee.has_method("set_director_active"), "Une abeille doit exposer set_director_active.")
	assert_true(beetle.has_method("set_director_active"), "Un scarabée doit exposer set_director_active.")
	assert_true(bee.has_method("apply_director_config"), "Une abeille doit exposer apply_director_config.")
	assert_true(beetle.has_method("apply_director_config"), "Un scarabée doit exposer apply_director_config.")
	assert_true(bee.has_method("get_current_target_peer_id"), "Une abeille doit exposer get_current_target_peer_id.")
	assert_true(beetle.has_method("get_current_target_peer_id"), "Un scarabée doit exposer get_current_target_peer_id.")
	assert_true(bee.has_method("get_assigned_target_peer_id"), "Une abeille doit exposer get_assigned_target_peer_id.")
	assert_true(beetle.has_method("get_assigned_target_peer_id"), "Un scarabée doit exposer get_assigned_target_peer_id.")
	assert_true(bee.has_method("request_current_state_from_server"), "Une abeille doit exposer request_current_state_from_server.")
	assert_true(beetle.has_method("request_current_state_from_server"), "Un scarabée doit exposer request_current_state_from_server.")
	assert_true(bee.has_method("push_current_state_to_peer"), "Une abeille doit exposer push_current_state_to_peer.")
	assert_true(beetle.has_method("push_current_state_to_peer"), "Un scarabée doit exposer push_current_state_to_peer.")
	assert_true(bee.has_method("get_state_revision"), "Une abeille doit exposer get_state_revision.")
	assert_true(beetle.has_method("get_state_revision"), "Un scarabée doit exposer get_state_revision.")
	assert_true(bee.has_method("get_debug_sync_summary"), "Une abeille doit exposer get_debug_sync_summary.")
	assert_true(beetle.has_method("get_debug_sync_summary"), "Un scarabée doit exposer get_debug_sync_summary.")


func test_enemy_directors_expose_common_groups() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var bee_director := BEE_DIRECTOR_SCRIPT.new()
	var beetle_director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(bee_director)
	root.add_child(beetle_director)

	assert_true(bee_director.is_in_group("enemy_directors"), "Le directeur d'abeilles doit exposer le groupe générique enemy_directors.")
	assert_true(beetle_director.is_in_group("enemy_directors"), "Le directeur de scarabées doit exposer le groupe générique enemy_directors.")
	assert_true(bee_director.is_in_group("replicated_persistent_objects"), "Le directeur d'abeilles doit être visible comme objet persistant répliqué.")
	assert_true(beetle_director.is_in_group("replicated_persistent_objects"), "Le directeur de scarabées doit être visible comme objet persistant répliqué.")
	assert_true(bee_director.is_in_group("bee_directors"), "Le directeur d'abeilles doit exposer son groupe spécifique.")
	assert_true(beetle_director.is_in_group("beetle_directors"), "Le directeur de scarabées doit exposer son groupe spécifique.")
	assert_true(bee_director.has_method("request_current_state_from_server"), "Le directeur d'abeilles doit exposer request_current_state_from_server.")
	assert_true(beetle_director.has_method("request_current_state_from_server"), "Le directeur de scarabées doit exposer request_current_state_from_server.")
	assert_true(bee_director.has_method("push_current_state_to_peer"), "Le directeur d'abeilles doit exposer push_current_state_to_peer.")
	assert_true(beetle_director.has_method("push_current_state_to_peer"), "Le directeur de scarabées doit exposer push_current_state_to_peer.")
	assert_true(bee_director.has_method("get_state_revision"), "Le directeur d'abeilles doit exposer get_state_revision.")
	assert_true(beetle_director.has_method("get_state_revision"), "Le directeur de scarabées doit exposer get_state_revision.")
	assert_true(bee_director.has_method("get_debug_sync_summary"), "Le directeur d'abeilles doit exposer get_debug_sync_summary.")
	assert_true(beetle_director.has_method("get_debug_sync_summary"), "Le directeur de scarabées doit exposer get_debug_sync_summary.")


func test_bee_director_can_gate_population_by_portal_and_zone_presence() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var marker := Node3D.new()
	marker.name = "ZoneMarker"
	root.add_child(marker)

	var portal := PORTAL_SCENE.instantiate()
	portal.name = "PortalHubVerger"
	root.add_child(portal)
	portal.add_to_group("mission_portal_hub_verger")
	portal.call("set_portal_active", false)

	var player := Node3D.new()
	player.name = "Player2"
	player.set_multiplayer_authority(2)
	player.position = Vector3(1.0, 0.0, 0.0)
	player.add_to_group("players")
	root.add_child(player)

	var bee_director := BEE_DIRECTOR_SCRIPT.new()
	root.add_child(bee_director)
	bee_director.activation_center_path = NodePath("../ZoneMarker")
	bee_director.activation_radius = 4.0
	bee_director.activation_portal_group = "mission_portal_hub_verger"
	bee_director.activation_requires_player_presence = true

	await get_tree().process_frame

	assert_eq(0, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles doit rester inactif si le portail de zone est fermé.")

	portal.call("set_portal_active", true)
	assert_eq(2, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles doit s'activer quand le portail est ouvert et qu'un joueur est dans la zone.")
	bee_director.call("_refresh_bee_population")

	player.position = Vector3(10.0, 0.0, 0.0)
	assert_eq(2, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles ne doit pas despawn les ennemis déjà actifs quand la zone devient vide.")


func test_verger_bee_director_defends_apple_without_waiting_for_player_presence() -> void:
	var zone := ZONE_VERGER_SCENE.instantiate()
	add_child_autofree(zone)

	var director := zone.get_node_or_null("Enemies")
	assert_not_null(director, "Le verger doit exposer un BeeDirector.")
	assert_eq(NodePath("../Interactives/ApplePickup"), director.get("activation_center_path"), "L'activation du verger doit etre centree sur la pomme.")
	assert_eq(NodePath("../Interactives/ApplePickup"), director.get("defense_center_path"), "Les abeilles du verger doivent defendre explicitement la pomme.")
	assert_false(bool(director.get("activation_requires_player_presence")), "Les abeilles doivent etre pretes des que le portail verger est ouvert, sans apparition tardive au contact joueur.")

	var config: Dictionary = director.call("_build_bee_config", 2)
	var apple := zone.get_node("Interactives/ApplePickup") as Node3D
	assert_eq(apple.global_position, config.get("patrol_center", Vector3.INF), "La patrouille des abeilles doit tourner autour de la pomme.")


func test_verger_habitation_is_static_env_without_retargeting_apple_defense() -> void:
	var zone := ZONE_VERGER_SCENE.instantiate()
	add_child_autofree(zone)

	assert_not_null(zone.get_node_or_null("Env/Habitation"), "Le verger doit instancier l'habitation comme decor statique.")
	assert_not_null(zone.get_node_or_null("Interactives/ApplePickup"), "La pomme doit rester dans le noeud Interactives attendu.")
	assert_not_null(zone.get_node_or_null("Enemies/bee_bot"), "Les abeilles graines doivent rester gerees par le BeeDirector du verger.")
	assert_true(zone.get_node("Env/Habitation/Props/Barrel").is_in_group("pushable_barrels"), "L'habitation doit reutiliser le barrel gameplay du projet au lieu d'un duplicat importe.")

	var director := zone.get_node("Enemies")
	assert_eq(NodePath("../Interactives/ApplePickup"), director.get("defense_center_path"), "L'ajout de decor ne doit pas deplacer la defense des abeilles hors de la pomme.")


func test_verger_habitation_ceilings_block_camera_spring_arm() -> void:
	var zone := ZONE_VERGER_SCENE.instantiate()
	add_child_autofree(zone)

	var ceiling := zone.get_node_or_null("Env/Habitation/Ceiling/Ceiling2") as StaticBody3D
	assert_not_null(ceiling, "Les plafonds de l'habitation doivent avoir une collision pour bloquer le SpringArm3D camera.")
	if ceiling == null:
		return

	var collision_shape := ceiling.get_node_or_null("CollisionShape3D") as CollisionShape3D
	assert_not_null(collision_shape, "Chaque tuile de plafond doit exposer une collision camera.")
	if collision_shape != null:
		assert_false(collision_shape.disabled, "La collision plafond doit rester active.")
		assert_not_null(collision_shape.shape, "La collision plafond doit avoir une forme.")
