extends GutTest

const PLAYER_SCENE := preload("res://player/player.tscn")
const CHARACTER_SKIN_SCENE := preload("res://player/model/character_skin.tscn")


func _assert_no_no_peer_errors(context: String) -> void:
	for err in get_errors():
		if err.is_engine_error() and err.contains_text("No multiplayer peer is assigned. Unable to get unique ID."):
			err.handled = true
			fail_test("%s ne doit pas appeler get_unique_id sans peer assigne." % context)

func test_player_scene_charge():
	# Basic resource load check to fail fast on missing/broken scene references.
	assert_not_null(PLAYER_SCENE)


func test_player_camera_keeps_distant_world_labels_sharp() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)

	var camera := player.get_node("CameraController/PlayerCamera") as Camera3D
	var attributes := camera.attributes as CameraAttributesPractical

	assert_not_null(attributes)
	assert_false(attributes.dof_blur_far_enabled, "La camera joueur ne doit pas flouter les labels 3D distants.")


func test_player_lives_overlay_is_hidden_because_hud_groups_persistent_stats() -> void:
	var player := PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	await wait_process_frames(2)

	var lives_overlay := player.get_node("LivesOverlay") as CanvasLayer
	assert_not_null(lives_overlay)
	assert_false(lives_overlay.visible, "Les vies persistantes doivent etre affichees dans le panneau HUD sombre, pas en overlay separe.")


func test_character_skin_swim_animation_has_motion_tracks() -> void:
	# The swim clip is edited locally in character_skin.tscn, so keep a guard against
	# accidentally saving it as an empty animation from the Godot animation panel.
	var skin := CHARACTER_SKIN_SCENE.instantiate()
	add_child_autofree(skin)

	var animation_player := skin.get_node("gdbot/AnimationPlayer") as AnimationPlayer
	var swim := animation_player.get_animation("swim")
	assert_not_null(swim, "CharacterSkin doit exposer une animation swim.")
	if swim != null:
		assert_gt(swim.get_track_count(), 4, "swim doit contenir des pistes d'os, pas seulement un nom vide.")
		assert_true(swim.loop_mode != Animation.LOOP_NONE, "swim doit boucler pour une nage continue.")


func test_character_skin_can_enter_swim_state() -> void:
	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	add_child_autofree(skin)
	await wait_process_frames(1)

	skin.set_swimming(true)
	await wait_process_frames(1)

	assert_true(skin.get("_swimming"), "CharacterSkin doit pouvoir activer l'etat visuel swim.")


func test_player_replicates_swim_state_for_remote_visuals() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await wait_process_frames(2)

	var synchronizer := player.get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var replication_config := synchronizer.replication_config
	var replicated_properties := replication_config.get_properties()

	assert_true(replicated_properties.has(NodePath(".:_is_swimming_sync")), "L'etat nage doit etre replique pour corriger la pose des proxies et late joins.")


func test_remote_sync_restores_standing_pose_after_swim() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	await wait_process_frames(2)

	var skin := player.get_node("CharacterRotationRoot/CharacterSkin") as CharacterSkin
	skin.swim_pose_transition_speed = 100.0
	var model_root := skin.get_node("gdbot") as Node3D
	var normal_transform := model_root.transform

	player.set("_is_swimming", true)
	player.set("_is_swimming_sync", false)
	skin.set_swimming(true)
	await wait_process_frames(1)
	assert_ne(model_root.transform, normal_transform, "Le preconditionnement doit placer le proxy en pose nage.")

	player.on_synchronized()
	await wait_process_frames(1)

	assert_false(player.is_swimming(), "La synchro reseau doit remettre l'etat nage local a false.")
	assert_eq(model_root.transform, normal_transform, "La pose visuelle distante doit revenir debout quand _is_swimming_sync=false.")


func test_character_skin_swim_pose_lays_model_horizontal_and_restores() -> void:
	# Swimming is not just a different limb cycle: the whole visible model must be
	# laid down, then restored when leaving water so ground animations stay upright.
	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	add_child_autofree(skin)
	await wait_process_frames(1)
	skin.swim_pose_transition_speed = 100.0

	var model_root := skin.get_node("gdbot") as Node3D
	var normal_transform := model_root.transform

	skin.set_swimming(true)
	await wait_process_frames(1)

	assert_almost_eq(model_root.rotation_degrees.x, 80.0, 0.01, "Le modele doit rester presque horizontal pendant la nage.")
	assert_gt(model_root.position.y, normal_transform.origin.y, "Le modele nageur doit etre legerement releve pour rester visible a la surface.")
	assert_lt(model_root.position.y - normal_transform.origin.y, 0.6, "La pose nage ne doit pas faire flotter le personnage trop haut au-dessus de l'eau.")

	skin.set_swimming(false)
	await wait_process_frames(1)

	assert_eq(model_root.transform, normal_transform, "La sortie de nage doit restaurer la pose verticale normale.")


func test_character_skin_swim_pose_transitions_between_standing_and_swimming() -> void:
	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	add_child_autofree(skin)
	await wait_process_frames(1)

	var model_root := skin.get_node("gdbot") as Node3D
	var normal_transform := model_root.transform
	skin.swim_pose_transition_speed = 2.0
	skin.set_swimming(true)
	skin._process(0.1)

	var blend: float = skin.get("_swim_pose_blend")
	assert_gt(blend, 0.0, "La pose swim doit commencer a entrer progressivement.")
	assert_lt(blend, 1.0, "La pose swim ne doit pas se plaquer instantanement.")
	assert_gt(model_root.rotation_degrees.x, 0.0, "Le modele doit commencer a se coucher.")
	assert_lt(model_root.rotation_degrees.x, skin.swim_model_pitch_degrees, "Le modele ne doit pas atteindre la pose finale en une frame.")

	skin.set_swimming(false)
	skin._process(0.2)
	assert_lt(skin.get("_swim_pose_blend"), blend, "La sortie de nage doit revenir progressivement vers debout.")
	skin.swim_pose_transition_speed = 100.0
	await wait_process_frames(1)
	assert_eq(model_root.transform, normal_transform, "La transition de sortie doit finir sur la pose normale.")


func test_character_skin_swim_pose_lifts_head_with_global_override() -> void:
	# Local head tracks are not reliable on this imported rig during the swim blend:
	# the readable head-up pose depends on a persistent Skeleton3D global override.
	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	add_child_autofree(skin)
	await wait_process_frames(2)
	skin.swim_pose_transition_speed = 100.0

	var skeleton := skin.get_node("gdbot/Armature/Skeleton3D") as Skeleton3D
	var head_bone_idx := skeleton.find_bone("head")
	assert_ne(head_bone_idx, -1, "Le rig doit exposer l'os head pour relever la tete en nage.")
	var upperarm_l_idx := skeleton.find_bone("upperarm.L")
	assert_ne(upperarm_l_idx, -1, "Le rig doit exposer upperarm.L pour pousser les bras vers l'avant en nage.")
	var lowerleg_l_idx := skeleton.find_bone("lowerleg.L")
	assert_ne(lowerleg_l_idx, -1, "Le rig doit exposer lowerleg.L pour animer le battement des pieds.")
	var foot_l_idx := skeleton.find_bone("foot.L")
	assert_ne(foot_l_idx, -1, "Le rig doit exposer foot.L pour animer le battement des pieds.")

	skin.set_swimming(true)
	await wait_process_frames(2)

	var override_pose := skeleton.get_bone_global_pose_override(head_bone_idx)
	var rest_pose := skeleton.get_bone_global_pose_no_override(head_bone_idx)
	assert_ne(override_pose.basis, rest_pose.basis, "La nage doit appliquer un override global visible sur la tete.")
	var model_root := skin.get_node("gdbot") as Node3D
	var face_direction := (model_root.global_basis * override_pose.basis.z).normalized()
	var expected_direction := (Vector3.FORWARD + (Vector3.UP * skin.swim_look_up_bias)).normalized()
	var face_angle := rad_to_deg(face_direction.angle_to(expected_direction))
	assert_lt(face_angle, 5.0, "Les yeux doivent regarder devant et legerement vers le haut, comme en brasse.")
	assert_gt(face_direction.y, 0.25, "Le regard de nage doit rester releve au-dessus de l'horizon.")
	var arm_override_pose := skeleton.get_bone_global_pose_override(upperarm_l_idx)
	var arm_base_pose := skeleton.get_bone_global_pose_no_override(upperarm_l_idx)
	assert_ne(arm_override_pose.basis, arm_base_pose.basis, "La nage doit appliquer une correction visible aux bras.")
	var leg_override_pose := skeleton.get_bone_global_pose_override(lowerleg_l_idx)
	var leg_base_pose := skeleton.get_bone_global_pose_no_override(lowerleg_l_idx)
	assert_ne(leg_override_pose.basis, leg_base_pose.basis, "La nage doit appliquer un battement visible aux jambes.")
	var foot_override_pose := skeleton.get_bone_global_pose_override(foot_l_idx)
	var foot_base_pose := skeleton.get_bone_global_pose_no_override(foot_l_idx)
	assert_ne(foot_override_pose.basis, foot_base_pose.basis, "La nage doit appliquer un battement visible aux pieds.")

	skin.set_swimming(false)
	await wait_process_frames(1)

	var restored_global_pose := skeleton.get_bone_global_pose(head_bone_idx)
	var restored_pose_without_override := skeleton.get_bone_global_pose_no_override(head_bone_idx)
	assert_eq(restored_global_pose, restored_pose_without_override, "La sortie de nage doit nettoyer l'effet visible de l'override global de tete.")


func test_character_skin_swim_kick_animates_feet_over_time() -> void:
	var skin := CHARACTER_SKIN_SCENE.instantiate() as CharacterSkin
	add_child_autofree(skin)
	await wait_process_frames(2)
	skin.swim_pose_transition_speed = 100.0
	skin.swim_kick_cycles_per_second = 1.0
	skin.swim_upperleg_kick_degrees = 4.0
	skin.swim_lowerleg_kick_degrees = 8.0
	skin.swim_foot_kick_degrees = 36.0
	skin.swim_kick_override_weight = 1.0

	var skeleton := skin.get_node("gdbot/Armature/Skeleton3D") as Skeleton3D
	var foot_l_idx := skeleton.find_bone("foot.L")
	var foot_r_idx := skeleton.find_bone("foot.R")
	assert_ne(foot_l_idx, -1, "Le rig doit exposer foot.L.")
	assert_ne(foot_r_idx, -1, "Le rig doit exposer foot.R.")
	assert_gt(skin.swim_foot_kick_degrees, skin.swim_lowerleg_kick_degrees, "Les pieds doivent avoir plus d'amplitude que les mollets.")
	assert_gt(skin.swim_lowerleg_kick_degrees, skin.swim_upperleg_kick_degrees, "Les mollets doivent rester plus actifs que les cuisses.")

	skin.set_swimming(true)
	skin._process(0.125)
	var left_pose_a := skeleton.get_bone_global_pose_override(foot_l_idx)
	var right_pose_a := skeleton.get_bone_global_pose_override(foot_r_idx)

	skin._process(0.125)
	var left_pose_b := skeleton.get_bone_global_pose_override(foot_l_idx)
	var right_pose_b := skeleton.get_bone_global_pose_override(foot_r_idx)

	assert_ne(left_pose_a.basis, left_pose_b.basis, "Le battement du pied gauche doit changer avec le temps.")
	assert_ne(right_pose_a.basis, right_pose_b.basis, "Le battement du pied droit doit changer avec le temps.")
	assert_ne(left_pose_b.basis, right_pose_b.basis, "Les deux jambes doivent battre en opposition.")


func test_player_instance():
	var player: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(player)
	assert_true(player is Player)
	# Free immediately to avoid orphan warnings in this minimal instantiation test.
	player.free()


func test_camera_controller_swim_mode_follows_player_height_instead_of_underwater_ground() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await wait_process_frames(2)

	var camera_controller := player.get_node("CameraController") as CameraController
	var spring_arm := camera_controller.get_node("CameraSpringArm") as SpringArm3D
	player.global_position = Vector3(0.0, 2.0, 0.0)
	player.set("_ground_height", -8.0)
	player.set("_is_swimming", true)
	camera_controller.swim_transition_speed = 100.0
	camera_controller.swim_follow_height_offset = 1.5
	camera_controller.swim_spring_arm_height_offset = 0.6
	camera_controller.swim_spring_length = 7.2
	camera_controller.global_position.y = -8.0

	camera_controller._physics_process(0.2)

	assert_gt(camera_controller.global_position.y, -7.0, "La camera swim ne doit plus suivre le terrain sous l'eau.")
	assert_gt(camera_controller.get("_swim_camera_blend"), 0.9, "Le mode swim doit pouvoir interpoler rapidement vers ses reglages.")
	assert_almost_eq(spring_arm.spring_length, 7.2, 0.01, "La longueur du bras swim doit etre reglable dans l'inspecteur.")


func test_camera_spring_arm_keeps_world_collision_enabled() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var spring_arm := player.get_node("CameraController/CameraSpringArm") as SpringArm3D
	assert_not_null(spring_arm.shape, "Le bras camera doit garder une forme de collision.")
	assert_true((spring_arm.collision_mask & 1) != 0, "Le bras camera doit tester le layer monde pour ne pas traverser murs et plafonds.")


func test_player_ready_and_physics_without_peer_do_not_raise_unique_id_errors() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await wait_process_frames(2)

	player._physics_process(0.016)
	await wait_process_frames(1)

	_assert_no_no_peer_errors("player sans peer")
	assert_true(player.is_inside_tree(), "Le joueur doit rester instanciable meme sans peer actif.")
