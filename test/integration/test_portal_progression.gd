extends GutTest

const PORTAL_SCENE := preload("res://levels/portal/portal.tscn")
const BRECHE_INTERACTIVES_SCENE := preload("res://main/mission_zone_breche_interactives.tscn")
const HUB_INTERACTIVES_SCENE := preload("res://main/mission_hub_interactives.tscn")
const WOOD_ITEM := preload("res://inventory/items/wood.tres")
const APPLE_ITEM := preload("res://inventory/items/apple.tres")


func _setup_portal_progression_world() -> Dictionary:
	var world := Node3D.new()
	add_child_autofree(world)

	var director := MatchDirector.new()
	director.force_server_mode = true
	director.auto_start_match = false
	world.add_child(director)

	var hub_interactives := HUB_INTERACTIVES_SCENE.instantiate()
	world.add_child(hub_interactives)

	var breche_portal := PORTAL_SCENE.instantiate()
	breche_portal.name = "PortalHubBreche"
	breche_portal.add_to_group("mission_portal_hub_breche")
	breche_portal.set("starts_active", false)
	world.add_child(breche_portal)

	var reactor_portal := PORTAL_SCENE.instantiate()
	reactor_portal.name = "PortalHubReactor"
	reactor_portal.add_to_group("mission_portal_hub_reactor")
	reactor_portal.set("starts_active", false)
	world.add_child(reactor_portal)

	var breche_interactives := BRECHE_INTERACTIVES_SCENE.instantiate()
	world.add_child(breche_interactives)

	return {
		"world": world,
		"director": director,
		"chest": hub_interactives.get_node("Chest"),
		"breche_portal": breche_portal,
		"reactor_portal": reactor_portal,
	}


func _fill_hub_chest_with_unlock_quota(chest: Node) -> void:
	var chest_inventory: Variant = chest.call("get_inventory_component")
	assert_not_null(chest_inventory)
	chest_inventory.call("add_payload", WOOD_ITEM.call("to_inventory_payload", 4))
	chest_inventory.call("add_payload", APPLE_ITEM.call("to_inventory_payload", 2))


func test_match_director_unlocks_breche_portal_from_chest_quota() -> void:
	var setup := _setup_portal_progression_world()
	await wait_process_frames(3)

	var chest := setup["chest"] as Node
	var director := setup["director"] as MatchDirector
	var breche_portal := setup["breche_portal"] as Node
	var reactor_portal := setup["reactor_portal"] as Node
	assert_not_null(chest)

	assert_false(bool(breche_portal.call("is_portal_active")), "Le portail Breche doit commencer inactif.")
	assert_false(bool(reactor_portal.call("is_portal_active")), "Le portail Reactor doit commencer inactif.")

	_fill_hub_chest_with_unlock_quota(chest)
	director.call("_update_zone_progression")

	assert_true(bool(breche_portal.call("is_portal_active")), "Le portail Breche doit s'activer après dépôt du quota bois/pommes.")
	assert_false(bool(reactor_portal.call("is_portal_active")), "Le portail Reactor doit rester fermé tant que les portes ne sont pas ouvertes.")
	assert_string_contains(director.get_snapshot_text(), "portal_breche_unlocked: 1")
	assert_string_contains(director.get_snapshot_text(), "portal_reactor_unlocked: 0")


func test_match_director_unlocks_reactor_portal_after_bomb_doors_open() -> void:
	var setup := _setup_portal_progression_world()
	await wait_process_frames(3)

	var world := setup["world"] as Node3D
	var chest := setup["chest"] as Node
	var director := setup["director"] as MatchDirector
	var breche_portal := setup["breche_portal"] as Node
	var reactor_portal := setup["reactor_portal"] as Node
	assert_not_null(chest)

	_fill_hub_chest_with_unlock_quota(chest)
	director.call("_update_zone_progression")
	assert_true(bool(breche_portal.call("is_portal_active")), "La phase breche doit être ouverte avant le test reactor.")
	assert_false(bool(reactor_portal.call("is_portal_active")), "Le portail Reactor doit rester fermé avant ouverture des BombDoor.")

	for door in world.get_tree().get_nodes_in_group("mission_cube_bomb_doors"):
		door.call("_apply_open_state", true)
	director.call("_update_zone_progression")

	assert_true(bool(reactor_portal.call("is_portal_active")), "Le portail Reactor doit s'activer après ouverture de la brèche.")
	assert_string_contains(director.get_snapshot_text(), "portal_reactor_unlocked: 1")


func test_portal_visual_state_switches_from_red_blocked_to_green_active() -> void:
	var world := Node3D.new()
	add_child_autofree(world)

	var portal := PORTAL_SCENE.instantiate()
	portal.set("starts_active", false)
	world.add_child(portal)

	await wait_process_frames(2)

	var light: OmniLight3D = portal.get_node("Portal/OmniLight3D")
	var front_plane: MeshInstance3D = portal.get_node("Portal/MeshInstance3D")
	var label: Label3D = portal.get_node("PortalLabel")
	var blocked_material := front_plane.get_active_material(0) as StandardMaterial3D

	assert_false(bool(portal.call("is_portal_active")), "Le portail doit commencer bloqué pour ce test visuel.")
	assert_eq(portal.get("inactive_color"), light.light_color, "Un portail bloqué doit être rouge côté lumière.")
	assert_not_null(blocked_material, "Le portail doit générer un matériau visuel runtime.")
	assert_eq(portal.get("inactive_color"), blocked_material.emission, "Un portail bloqué doit émettre en rouge.")
	assert_not_null(label, "Le portail doit exposer un libellé lisible.")
	assert_string_contains(label.text, "BLOQUE")

	portal.call("set_portal_active", true)

	var active_material := front_plane.get_active_material(0) as StandardMaterial3D
	assert_true(bool(portal.call("is_portal_active")), "Le portail doit pouvoir redevenir actif.")
	assert_eq(portal.get("active_color"), light.light_color, "Un portail actif doit être vert côté lumière.")
	assert_not_null(active_material, "Le matériau runtime doit rester accessible après activation.")
	assert_eq(portal.get("active_color"), active_material.emission, "Un portail actif doit émettre en vert.")
	assert_string_contains(label.text, "OUVERT")
