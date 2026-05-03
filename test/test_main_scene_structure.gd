extends GutTest

const MAIN_SCENE := preload("res://main/main.tscn")
const ZONE_SCIERIE_SCENE := preload("res://levels/zones/scierie/zone_scierie.tscn")
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


# Vérifie l'invariant d'ancrage introduit avec Terrain3D:
# la scène source et l'instance dans main doivent partager le même ancrage de zone.
# Le noeud Terrain reste top_level et vit à l'origine monde; c'est donc l'ancrage de ZoneScierie
# qui est le vrai contrat de placement pour le gameplay et l'édition.
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
	var zone_only_terrain_global := zone_only_terrain.global_position
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
	assert_eq(zone_only_terrain_global, main_terrain.global_position, "Le Terrain3D doit garder le même repère global entre la scène source et main.")


# Vérifie que la scène scierie reste centrée sur Terrain3D.
# Les meshes décoratifs de berge sont exclus tant qu'ils ne suivent pas réellement la surface
# Terrain3D: sinon ils peuvent masquer les textures dans l'éditeur ou en jeu.
func test_zone_scierie_uses_terrain3d_without_overlay_shore_meshes() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var zone_only := ZONE_SCIERIE_SCENE.instantiate()
	root.add_child(zone_only)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var terrain := zone_only.get_node_or_null("Ground/Terrain")
	assert_null(zone_only.get_node_or_null("Env/SwampWater"), "La scierie ne doit pas ajouter de plan d'eau local qui recouvre le gameplay.")
	assert_null(zone_only.get_node_or_null("Env/ShoreDetails"), "La scierie ne doit pas ajouter de plaques de berge au-dessus du Terrain3D.")
	assert_not_null(terrain, "La scierie doit garder son noeud Terrain3D.")
	if terrain != null:
		assert_not_null(terrain.get("assets"), "Terrain3D doit garder sa ressource d'assets pour afficher les textures dans l'editeur.")
		assert_not_null(terrain.get("material"), "Terrain3D doit garder son materiau dedie.")


func test_zone_scierie_terrain_assets_expose_expected_textures() -> void:
	var assets := load("res://levels/zones/scierie/zone_scierie_terrain_assets.tres")
	assert_not_null(assets, "La scierie doit charger sa ressource Terrain3DAssets.")
	if assets == null:
		return

	var texture_list: Array = assets.get("texture_list")
	assert_eq(4, texture_list.size(), "La scierie doit exposer Grass, Dirt, Rock et FlowerGrass dans Terrain3D.")
	if texture_list.size() < 4:
		return

	var expected_names := ["Grass", "Dirt", "Rock", "FlowerGrass"]
	for index in range(expected_names.size()):
		var texture_asset: Resource = texture_list[index] as Resource
		assert_eq(expected_names[index], texture_asset.get("name"), "Les textures Terrain3D doivent garder un ordre stable dans le dock.")
		assert_eq(index, texture_asset.get("id"), "L'id Terrain3D doit rester aligné avec le slot peint.")
		assert_not_null(texture_asset.get("albedo_texture"), "%s doit avoir une texture albedo." % expected_names[index])
		assert_not_null(texture_asset.get("normal_texture"), "%s doit avoir une normal map." % expected_names[index])


# Garde-fou gameplay: les points de spawn des scarabées doivent toujours retomber sur une
# collision valide. En pratique le raycast retombe actuellement sur AnchorSupport, qui sert
# de support stable côté éditeur autour du plateau Terrain3D.
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
			assert_true(["Terrain", "AnchorSupport"].has(String(collider.get("name"))), "%s doit retomber sur un support solide de la scierie." % anchor_path)


# Même logique que pour les scarabées, mais appliquée au portail retour:
# on accepte Terrain3D ou AnchorSupport comme support solide tant que le portail reste jouable.
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
			assert_true(["Terrain", "AnchorSupport"].has(String(collider.get("name"))), "Le support du portail doit venir d'un sol solide de la scierie.")


# Vérifie qu'un déplacement du portail dans zone_scierie.tscn se propage dans main
# sans être masqué par un override local oublié dans l'instance.
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


# Régression visuelle: le grand plan d'eau du hub ne doit plus revenir sous l'accès scierie.
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


# Ce test complète le précédent:
# on veut un plan d'eau assez large pour entourer les îles principales, mais toujours arrêté avant la scierie.
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


func test_hub_water_uses_animated_shader_without_changing_collision() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var water := main.get_node("HubLevel/Env/Water") as MeshInstance3D
	var water_area := main.get_node("HubLevel/Env/WaterArea") as Area3D
	var mesh := water.mesh as PlaneMesh
	var material := water.get_surface_override_material(0) as ShaderMaterial
	assert_not_null(mesh, "Le plan d'eau doit rester un PlaneMesh visuel.")
	assert_not_null(material, "Le plan d'eau doit utiliser un ShaderMaterial anime.")
	assert_not_null(water_area, "La collision/detection d'eau doit rester separee du shader visuel.")
	if mesh != null:
		assert_gte(mesh.subdivide_width, 80, "Le shader de vagues a besoin d'un plan suffisamment subdivise.")
		assert_gte(mesh.subdivide_depth, 80, "Le shader de vagues a besoin d'un plan suffisamment subdivise.")
	if material != null:
		assert_gt(float(material.get_shader_parameter("wave_height")), 0.25, "Les vagues doivent rester visibles.")
		assert_gt(float(material.get_shader_parameter("normal_speed")), 0.5, "Les normales doivent animer les reflets.")
		assert_gt(float(material.get_shader_parameter("foam_strength")), 0.0, "L'eau doit garder une ecume stylisee visible.")
		assert_gt(float(material.get_shader_parameter("color_ripple_strength")), 0.0, "L'eau doit garder une variation de couleur animee.")


func test_hub_water_area_drives_swim_without_replacing_fall_checker() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	_handle_known_terrain3d_engine_warning()
	await wait_process_frames(3)

	var water_area := main.get_node_or_null("HubLevel/Env/WaterArea") as Area3D
	var water_shape_node := main.get_node_or_null("HubLevel/Env/WaterArea/CollisionShape3D") as CollisionShape3D
	var fall_checker := main.get_node("FallChecker") as FallChecker
	assert_not_null(water_area, "Le plan d'eau doit avoir une Area3D dediee pour declencher l'animation swim.")
	assert_not_null(water_shape_node, "WaterArea doit exposer une collision de detection.")
	if water_area != null and water_shape_node != null:
		assert_true(water_area.is_in_group("water_areas"), "WaterArea doit etre identifiable sans etre confondue avec FallChecker.")
		var box := water_shape_node.shape as BoxShape3D
		assert_not_null(box)
		if box != null:
			var water_bottom := water_area.global_position.y - (box.size.y * 0.5)
			assert_gt(water_bottom, fall_checker.fall_height, "WaterArea doit s'arreter au-dessus du seuil FallChecker pour laisser le respawn fonctionner.")


# Test purement structurel sur le fichier texte de main.tscn.
# Son but est d'empêcher le retour du bug principal observé pendant l'intégration Terrain3D:
# des overrides enregistrés sous ZoneScierie dans main qui désynchronisent l'édition entre
# la scène source et l'instance utilisée au runtime.
func test_main_scene_keeps_zone_scierie_as_clean_instance_without_child_overrides() -> void:
	var main_scene_text := FileAccess.get_file_as_string("res://main/main.tscn")
	assert_false(main_scene_text.contains("parent=\"ZoneScierie/"), "main.tscn ne doit plus contenir d'override sur des enfants de ZoneScierie.")
