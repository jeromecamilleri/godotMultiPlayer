extends GutTest

const BEE_DIRECTOR_SCRIPT := preload("res://enemies/bee_director.gd")
const BEETLE_DIRECTOR_SCRIPT := preload("res://enemies/beetle_director.gd")
const BEE_SCENE := preload("res://enemies/bee_bot.tscn")
const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")
const PORTAL_SCENE := preload("res://levels/portal/portal.tscn")


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

	portal.call("set_portal_active", false)
	assert_eq(0, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles doit rester inactif si le portail de zone est fermé.")

	portal.call("set_portal_active", true)
	assert_eq(2, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles doit s'activer quand le portail est ouvert et qu'un joueur est dans la zone.")

	player.position = Vector3(10.0, 0.0, 0.0)
	assert_eq(0, int(bee_director.call("_get_desired_bee_count")), "Le directeur d'abeilles doit retomber à zéro si personne n'est dans la zone.")
