extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")
const ZONE_SCIERIE_SCENE := preload("res://levels/zones/zone_scierie.tscn")
const TERRAIN3D_DEPRECATION_TEXT := "instance_reset_physics_interpolation() is deprecated."
const TERRAIN3D_TEXTURE_WARNING_TEXT := "normal texture is not connected to a file."


func _handle_known_terrain3d_engine_warning() -> void:
	for err in get_errors():
		if err.is_engine_error() and (err.contains_text(TERRAIN3D_DEPRECATION_TEXT) or err.contains_text(TERRAIN3D_TEXTURE_WARNING_TEXT)):
			err.handled = true


func test_main_scene_preserves_modular_runtime_paths() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	assert_not_null(main.get_node_or_null("HubLevel/Env/Enemies"), "La scène doit conserver le conteneur Enemies.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/PhysicsObjects"), "La scène doit conserver le conteneur PhysicsObjects.")
	assert_not_null(main.get_node_or_null("HubLevel/Env/Interactives"), "La scène doit conserver le conteneur Interactives.")
	assert_not_null(main.get_node_or_null("ZoneScierie"), "La scène doit exposer la zone Scierie.")
	assert_not_null(main.get_node_or_null("ZoneVerger"), "La scène doit exposer la zone Verger.")
	assert_not_null(main.get_node_or_null("ZoneBreche"), "La scène doit exposer la zone Brèche.")
	assert_not_null(main.get_node_or_null("ZoneReactor"), "La scène doit exposer la zone Reactor.")
	assert_not_null(main.get_node_or_null("ZoneBreche/Enemies/BeetleDirector"), "La scène doit exposer le BeetleDirector dans la zone Brèche.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Interactives/Activator/CubeActivator"), "La scène doit exposer la zone objectif du réacteur.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Env/PhysicsObjects/RigidCube3D"), "La scène doit exposer le cube principal dans la zone Reactor.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Enemies/BeetleDirector"), "La scène doit exposer le BeetleDirector dans la zone Reactor.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Scierie"), "Le hub doit exposer le portail vers la Scierie.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Verger"), "Le hub doit exposer le portail vers le Verger.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Breche"), "Le hub doit exposer le portail vers la Brèche.")
	assert_not_null(main.get_node_or_null("HubLevel/Portals/Portal_Hub_To_Reactor"), "Le hub doit exposer le portail vers le Reactor.")
	assert_not_null(main.get_node_or_null("ZoneScierie/Portals/Portal_Scierie_To_Hub"), "La Scierie doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneVerger/Portals/Portal_Verger_To_Hub"), "Le Verger doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneBreche/Portals/Portal_Breche_To_Hub"), "La Brèche doit exposer son portail retour.")
	assert_not_null(main.get_node_or_null("ZoneReactor/Portals/Portal_Reactor_To_Hub"), "Le Reactor doit exposer son portail retour.")

	var cube := main.get_tree().get_first_node_in_group("mission_cube_primary")
	assert_not_null(cube)
	assert_eq(NodePath("ZoneReactor/Env/PhysicsObjects/RigidCube3D"), main.get_path_to(cube))


func test_zone_scierie_terrain_uses_same_world_anchor_in_zone_and_main() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var zone_only := ZONE_SCIERIE_SCENE.instantiate()
	root.add_child(zone_only)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var zone_only_root := zone_only as Node3D
	var zone_only_terrain := zone_only.get_node("Ground/Terrain") as Node3D
	var zone_only_anchor_support := zone_only.get_node("Ground/AnchorSupport") as StaticBody3D
	var expected_anchor := Vector3(120.0, 0.0, 0.0)
	var zone_only_anchor := zone_only_root.transform.origin
	assert_eq(expected_anchor, zone_only_root.global_position, "La scène zone_scierie doit être éditée à son offset final.")
	assert_true(zone_only_terrain.top_level, "Le plugin Terrain3D force un repère monde indépendant; ce comportement doit rester explicite dans ce test.")
	assert_lt(zone_only_anchor_support.global_position.y, zone_only_terrain.global_position.y, "Le support d'ancrage doit rester légèrement sous le terrain visible.")
	assert_null(zone_only.get_node_or_null("Ground/FloorFallback"), "Le fallback ne doit plus masquer un décalage du terrain.")

	zone_only.queue_free()
	await wait_process_frames(2)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var main_zone := main.get_node("ZoneScierie") as Node3D
	var main_terrain := main.get_node("ZoneScierie/Ground/Terrain") as Node3D
	assert_eq(expected_anchor, main_zone.global_position, "Main doit instancier la scierie au même ancrage que la scène dédiée.")
	assert_eq(zone_only_anchor, main_zone.transform.origin, "Main ne doit pas réintroduire un décalage supplémentaire sur ZoneScierie.")
	assert_eq(expected_anchor, main_terrain.global_position, "Le Terrain3D instancié dans main doit garder le même ancrage global que dans la scène dédiée.")


func test_zone_scierie_beetle_anchors_stay_over_supported_ground() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var zone := main.get_node("ZoneScierie") as Node3D
	var space: PhysicsDirectSpaceState3D = zone.get_world_3d().direct_space_state
	var anchor_paths := [
		"ZoneScierie/Enemies/BeetleDirector/beetle_anchor_1",
		"ZoneScierie/Enemies/BeetleDirector/beetle_anchor_2",
	]
	for anchor_path in anchor_paths:
		var anchor := main.get_node(anchor_path) as Node3D
		var query := PhysicsRayQueryParameters3D.create(anchor.global_position + Vector3.UP * 8.0, anchor.global_position + Vector3.DOWN * 12.0)
		var hit: Dictionary = space.intersect_ray(query)
		assert_false(hit.is_empty(), "%s doit avoir un sol sous l'ancre." % anchor_path)
		if not hit.is_empty():
			var collider := hit["collider"] as Object
			assert_eq("Terrain", String(collider.get("name")), "%s doit retomber sur le Terrain3D de la scierie." % anchor_path)


func test_zone_scierie_portal_has_terrain_support_beneath_it() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var portal := main.get_node("ZoneScierie/Portals/Portal_Scierie_To_Hub") as Node3D
	var zone := main.get_node("ZoneScierie") as Node3D
	var space: PhysicsDirectSpaceState3D = zone.get_world_3d().direct_space_state
	var offsets := [
		Vector3.ZERO,
		Vector3(2.0, 0.0, 0.0),
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 2.0),
		Vector3(0.0, 0.0, -2.0),
	]
	var exclude: Array[RID] = []
	for child in portal.find_children("*", "CollisionObject3D", true, false):
		exclude.append((child as CollisionObject3D).get_rid())
	for offset in offsets:
		var sample: Vector3 = portal.global_position + offset
		var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 8.0, sample + Vector3.DOWN * 12.0)
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		assert_false(hit.is_empty(), "Le portail de la scierie doit avoir du terrain sous %s." % sample)
		if not hit.is_empty():
			var collider := hit["collider"] as Object
			assert_eq("Terrain", String(collider.get("name")), "Le support du portail doit venir du Terrain3D.")


func test_zone_scierie_portal_transform_matches_between_source_scene_and_main() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var zone_only := ZONE_SCIERIE_SCENE.instantiate()
	root.add_child(zone_only)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var zone_portal := zone_only.get_node("Portals/Portal_Scierie_To_Hub") as Node3D
	var expected_local := zone_portal.transform.origin
	var expected_global := zone_portal.global_position

	zone_only.queue_free()
	await wait_process_frames(2)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var main_portal := main.get_node("ZoneScierie/Portals/Portal_Scierie_To_Hub") as Node3D
	assert_eq(expected_local, main_portal.transform.origin, "Main ne doit pas conserver un override local sur le portail retour de la scierie.")
	assert_eq(expected_global, main_portal.global_position, "Le portail retour doit apparaître au même endroit dans main et dans la scène source.")


func test_hub_water_plane_stays_out_of_zone_scierie_portal_area() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var water := main.get_node("HubLevel/Env/Water") as MeshInstance3D
	var portal := main.get_node("ZoneScierie/Portals/Portal_Scierie_To_Hub") as Node3D
	var mesh := water.mesh as PlaneMesh
	var half_x := mesh.size.x * water.global_basis.x.length() * 0.5
	var half_z := mesh.size.y * water.global_basis.z.length() * 0.5
	var water_min_x := water.global_position.x - half_x
	var water_max_x := water.global_position.x + half_x
	var water_min_z := water.global_position.z - half_z
	var water_max_z := water.global_position.z + half_z
	assert_true(portal.global_position.x > water_max_x, "Le plan d'eau du hub ne doit plus recouvrir l'accès à la scierie.")
	assert_true(portal.global_position.x > water_min_x, "Régression de calcul des bornes sur l'axe X.")
	assert_true(portal.global_position.z >= water_min_z and portal.global_position.z <= water_max_z, "Le test suppose le portail aligné sur la profondeur du plan d'eau.")


func test_hub_water_plane_wraps_main_islands_without_covering_scierie() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var water := main.get_node("HubLevel/Env/Water") as MeshInstance3D
	var mesh := water.mesh as PlaneMesh
	var half_x := mesh.size.x * water.global_basis.x.length() * 0.5
	var half_z := mesh.size.y * water.global_basis.z.length() * 0.5
	var water_min_x := water.global_position.x - half_x
	var water_max_x := water.global_position.x + half_x
	var water_min_z := water.global_position.z - half_z
	var water_max_z := water.global_position.z + half_z
	var island_centers := {
		"HubLevel": (main.get_node("HubLevel") as Node3D).global_position,
		"ZoneVerger": (main.get_node("ZoneVerger") as Node3D).global_position,
		"ZoneBreche": (main.get_node("ZoneBreche") as Node3D).global_position,
		"ZoneReactor": (main.get_node("ZoneReactor") as Node3D).global_position,
	}
	for island_name in island_centers.keys():
		var center: Vector3 = island_centers[island_name]
		assert_true(center.x >= water_min_x and center.x <= water_max_x, "%s doit rester englobee par le plan d'eau sur l'axe X." % island_name)
		assert_true(center.z >= water_min_z and center.z <= water_max_z, "%s doit rester englobee par le plan d'eau sur l'axe Z." % island_name)

	var scierie_portal := main.get_node("ZoneScierie/Portals/Portal_Scierie_To_Hub") as Node3D
	assert_true(scierie_portal.global_position.x > water_max_x, "La scierie doit rester hors du plan d'eau malgre l'agrandissement.")


func test_main_scene_keeps_zone_scierie_as_clean_instance_without_child_overrides() -> void:
	var main_scene_text := FileAccess.get_file_as_string("res://main/main.tscn")
	assert_false(main_scene_text.contains("parent=\"ZoneScierie/"), "main.tscn ne doit plus contenir d'override sur des enfants de ZoneScierie.")
