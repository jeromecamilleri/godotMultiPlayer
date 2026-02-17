class_name CharacterSkin
extends Node3D

@export var main_animation_player : AnimationPlayer

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

# False : set animation to "idle"
# True : set animation to "move"
@onready var moving : bool = false : set = set_moving

# Blend value between the walk and run cycle
# 0.0 walk - 1.0 run
@onready var move_speed : float = 0.0 : set = set_moving_speed
@onready var animation_tree : AnimationTree = $AnimationTree
@onready var state_machine : AnimationNodeStateMachinePlayback = animation_tree.get("parameters/StateMachine/playback")
@onready var _mesh: MeshInstance3D = $gdbot/Armature/Skeleton3D/gdbot_mesh

@onready var _step_sound: AudioStreamPlayer3D = $StepSound
@onready var _landing_sound: AudioStreamPlayer3D = $LandingSound
## Instance-local heart material (duplicated from shared resource on first use).
var _heart_material_instance: StandardMaterial3D


func _ready():
	animation_tree.active = true
	main_animation_player["playback_default_blend_time"] = 0.1


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
	state_machine.travel("jump")


@rpc("authority", "call_local", "unreliable_ordered")
func fall():
	state_machine.travel("fall")


@rpc("authority", "call_local", "unreliable_ordered")
func punch():
	animation_tree["parameters/PunchOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func play_step_sound():
	_step_sound.pitch_scale = randfn(1.1, 0.05)
	_step_sound.play()


func play_landing_sound():
	_landing_sound.play()
