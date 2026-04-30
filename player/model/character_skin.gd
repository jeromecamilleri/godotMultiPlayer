class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer
@export_group("Swim Pose")
@export var swim_model_pitch_degrees := 80.0
@export var swim_model_height_offset := 0.2
@export var swim_pose_transition_speed := 4.0
@export var swim_look_up_bias := 0.55
@export_range(0.0, 1.0, 0.05) var swim_arm_override_weight := 0.35
@export var swim_left_upperarm_rotation_degrees := Vector3(-12.0, -18.0, 10.0)
@export var swim_left_lowerarm_rotation_degrees := Vector3(0.0, -10.0, 8.0)
@export var swim_right_upperarm_rotation_degrees := Vector3(-12.0, 18.0, -10.0)
@export var swim_right_lowerarm_rotation_degrees := Vector3(0.0, 10.0, -8.0)
@export var swim_kick_cycles_per_second := 2.2
@export var swim_upperleg_kick_degrees := 6.0
@export var swim_lowerleg_kick_degrees := 10.0
@export var swim_foot_kick_degrees := 34.0
@export_range(0.0, 1.0, 0.05) var swim_kick_override_weight := 0.45

var moving_blend_path := "parameters/StateMachine/move/blend_position"
## Material slot index for the heart core surface in gdbot_mesh.
const HEART_MATERIAL_SLOT := 2
## Deterministic palette used to visually distinguish player instances.
const HEART_PALETTE: Array[Color] = [
	Color(0.10, 0.90, 0.35), # green
	Color(0.16, 0.54, 1.00), # blue
	Color(1.00, 0.52, 0.18), # orange
	Color(0.95, 0.25, 0.34), # red
	Color(1.00, 0.86, 0.16), # yellow
	Color(0.80, 0.33, 1.00)  # violet
]
const SWIM_LIMB_BONE_NAMES := [
	"upperarm.L",
	"lowerarm.L",
	"upperarm.R",
	"lowerarm.R",
	"upperleg.L",
	"lowerleg.L",
	"foot.L",
	"upperleg.R",
	"lowerleg.R",
	"foot.R",
]

# False : set animation to "idle"
# True : set animation to "move"
@onready var moving : bool = false : set = set_moving

# Blend value between the walk and run cycle
# 0.0 walk - 1.0 run
@onready var move_speed : float = 0.0 : set = set_moving_speed
@onready var animation_tree : AnimationTree = $AnimationTree
@onready var state_machine : AnimationNodeStateMachinePlayback = animation_tree.get("parameters/StateMachine/playback")
@onready var _model_root: Node3D = $gdbot
@onready var _skeleton: Skeleton3D = $gdbot/Armature/Skeleton3D
@onready var _mesh: MeshInstance3D = $gdbot/Armature/Skeleton3D/gdbot_mesh
@onready var _head_bone_idx := _skeleton.find_bone("head")

@onready var _step_sound: AudioStreamPlayer3D = $StepSound
@onready var _landing_sound: AudioStreamPlayer3D = $LandingSound
## Instance-local heart material (duplicated from shared resource on first use).
var _heart_material_instance: StandardMaterial3D
var _normal_model_transform := Transform3D.IDENTITY
var _sliding := false
var _swimming := false
var _swim_pose_blend := 0.0
var _swim_kick_time := 0.0
var _swim_limb_bone_indices: Dictionary = {}


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1
	_normal_model_transform = _model_root.transform
	_cache_swim_limb_bones()


func _process(delta: float) -> void:
	_update_swim_visual_pose(delta)


func apply_heart_color_from_peer_id(peer_id: int) -> void:
	if HEART_PALETTE.is_empty():
		return
	# Stable mapping: same authority id always gets the same heart color.
	var color_index: int = absi(peer_id) % HEART_PALETTE.size()
	apply_heart_color(HEART_PALETTE[color_index])


func apply_heart_color(color: Color) -> void:
	if _mesh == null:
		return
	var shared_material: Material = _mesh.get_surface_override_material(HEART_MATERIAL_SLOT)
	if shared_material == null:
		return
	if _heart_material_instance == null:
		# Duplicate once per character so color updates stay local to this player instance.
		_heart_material_instance = shared_material.duplicate() as StandardMaterial3D
		if _heart_material_instance == null:
			return
		_mesh.set_surface_override_material(HEART_MATERIAL_SLOT, _heart_material_instance)
	_heart_material_instance.emission_enabled = true
	_heart_material_instance.emission = color


@rpc("authority", "call_local", "unreliable_ordered")
func set_moving(value : bool):
	moving = value
	if _swimming:
		# Water visuals override ground locomotion, without changing movement physics.
		return
	if _sliding:
		# Keep slide fallback pose while sliding is active.
		return
	if moving:
		state_machine.travel("move")
	else:
		state_machine.travel("idle")


@rpc("authority", "call_local", "unreliable_ordered")
func set_moving_speed(value : float):
	move_speed = clamp(value, 0.0, 1.0)
	animation_tree.set(moving_blend_path, move_speed)


@rpc("authority", "call_local", "unreliable_ordered")
func jump():
	if _swimming:
		return
	state_machine.travel("jump")


@rpc("authority", "call_local", "unreliable_ordered")
func fall():
	if _swimming:
		return
	state_machine.travel("fall")


@rpc("authority", "call_local", "unreliable_ordered")
func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


@rpc("authority", "call_local", "unreliable_ordered")
func set_sliding(value: bool) -> void:
	_sliding = value
	if _swimming:
		return
	if _sliding:
		# Keep locomotion-driven visuals from Player while sliding is active.
		return
	# Restore locomotion state when sliding stops.
	if moving:
		state_machine.travel("move")
	else:
		state_machine.travel("idle")


@rpc("authority", "call_local", "unreliable_ordered")
func set_swimming(value: bool) -> void:
	if _swimming == value:
		return
	_swimming = value
	if _swimming:
		state_machine.travel("swim")
		return
	if moving:
		state_machine.travel("move")
	else:
		state_machine.travel("idle")


func _cache_swim_limb_bones() -> void:
	for bone_name in SWIM_LIMB_BONE_NAMES:
		_swim_limb_bone_indices[bone_name] = _skeleton.find_bone(bone_name)


func _update_swim_visual_pose(delta: float) -> void:
	var target_blend := 1.0 if _swimming else 0.0
	_swim_pose_blend = move_toward(_swim_pose_blend, target_blend, maxf(0.0, delta * swim_pose_transition_speed))
	if _swim_pose_blend <= 0.0:
		_restore_normal_visual_pose()
		return
	if _swimming:
		_swim_kick_time += delta * maxf(0.0, swim_kick_cycles_per_second) * TAU
	_apply_swim_visual_pose(_swim_pose_blend)


func _apply_swim_visual_pose(blend: float) -> void:
	_model_root.transform = _normal_model_transform
	_model_root.rotation_degrees.x += swim_model_pitch_degrees * blend
	_model_root.position.y += swim_model_height_offset * blend
	_apply_swim_head_lift(blend)
	_apply_swim_arm_pose(blend)
	_apply_swim_kick_pose(blend)


func _restore_normal_visual_pose() -> void:
	_skeleton.clear_bones_global_pose_override()
	_model_root.transform = _normal_model_transform


func _apply_swim_head_lift(blend: float) -> void:
	if _head_bone_idx == -1:
		return
	var head_pose := _skeleton.get_bone_global_pose_no_override(_head_bone_idx)
	var desired_world_face := (Vector3.FORWARD + (Vector3.UP * swim_look_up_bias)).normalized()
	var desired_skeleton_face := (_model_root.global_basis.inverse() * desired_world_face).normalized()
	var desired_skeleton_up := (_model_root.global_basis.inverse() * Vector3.UP).normalized()
	head_pose.basis = _basis_with_z_axis(desired_skeleton_face, desired_skeleton_up)
	_skeleton.set_bone_global_pose_override(_head_bone_idx, head_pose, blend, true)
	_skeleton.force_update_all_bone_transforms()


func _apply_swim_arm_pose(blend: float) -> void:
	var override_strength := clampf(swim_arm_override_weight * blend, 0.0, 1.0)
	if override_strength <= 0.0:
		return
	_apply_bone_rotation_offset("upperarm.L", swim_left_upperarm_rotation_degrees, override_strength)
	_apply_bone_rotation_offset("lowerarm.L", swim_left_lowerarm_rotation_degrees, override_strength)
	_apply_bone_rotation_offset("upperarm.R", swim_right_upperarm_rotation_degrees, override_strength)
	_apply_bone_rotation_offset("lowerarm.R", swim_right_lowerarm_rotation_degrees, override_strength)
	_skeleton.force_update_all_bone_transforms()


func _apply_swim_kick_pose(blend: float) -> void:
	var override_strength := clampf(swim_kick_override_weight * blend, 0.0, 1.0)
	if override_strength <= 0.0:
		return
	var kick := sin(_swim_kick_time)
	var counter_kick := -kick
	# Opposed flutter kick: legs stay subtle, feet provide the visible up/down motion.
	_apply_bone_rotation_offset("upperleg.L", Vector3(swim_upperleg_kick_degrees * kick, 0.0, 0.0), override_strength)
	_apply_bone_rotation_offset("lowerleg.L", Vector3(swim_lowerleg_kick_degrees * counter_kick, 0.0, 0.0), override_strength)
	_apply_bone_rotation_offset("foot.L", Vector3(swim_foot_kick_degrees * kick, 0.0, 0.0), override_strength)
	_apply_bone_rotation_offset("upperleg.R", Vector3(swim_upperleg_kick_degrees * counter_kick, 0.0, 0.0), override_strength)
	_apply_bone_rotation_offset("lowerleg.R", Vector3(swim_lowerleg_kick_degrees * kick, 0.0, 0.0), override_strength)
	_apply_bone_rotation_offset("foot.R", Vector3(swim_foot_kick_degrees * counter_kick, 0.0, 0.0), override_strength)
	_skeleton.force_update_all_bone_transforms()


func _apply_bone_rotation_offset(bone_name: String, euler_degrees: Vector3, strength: float) -> void:
	var bone_idx: int = int(_swim_limb_bone_indices.get(bone_name, -1))
	if bone_idx == -1:
		return
	var base_pose := _skeleton.get_bone_global_pose_no_override(bone_idx)
	var target_pose := base_pose
	var offset_basis := Basis.from_euler(Vector3(
		deg_to_rad(euler_degrees.x),
		deg_to_rad(euler_degrees.y),
		deg_to_rad(euler_degrees.z)
	))
	target_pose.basis = base_pose.basis * offset_basis
	_skeleton.set_bone_global_pose_override(bone_idx, target_pose, strength, true)


func _basis_with_z_axis(z_axis: Vector3, up_hint: Vector3) -> Basis:
	var z := z_axis.normalized()
	var x := up_hint.cross(z).normalized()
	if x.is_zero_approx():
		x = Vector3.RIGHT
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


func play_step_sound():
	_step_sound.pitch_scale = randfn(1.1, 0.05)
	_step_sound.play()


func play_landing_sound():
	_landing_sound.play()
