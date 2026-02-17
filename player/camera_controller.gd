class_name CameraController
extends Node3D

@export var invert_mouse_y := false
@export_range(0.0, 1.0) var mouse_sensitivity := 0.25
@export var tilt_upper_limit := deg_to_rad(-60.0)
@export var tilt_lower_limit := deg_to_rad(60.0)
@export var spectator_speed := 12.0

@onready var camera: Camera3D = $PlayerCamera
@onready var _camera_spring_arm: SpringArm3D = $CameraSpringArm
@onready var _pivot: Node3D = $CameraSpringArm/CameraThirdPersonPivot

var _rotation_input: float
var _tilt_input: float
var _mouse_input := false
var _offset: Vector3
var _anchor: CharacterBody3D
var _euler_rotation: Vector3
var _spectator_mode := false
var _has_offset := false


func _ready() -> void:
	# Remote proxies do not process local camera/input logic.
	if not is_multiplayer_authority():
		set_process_input(false)
		set_physics_process(false)


func _unhandled_input(event: InputEvent) -> void:
	_mouse_input = event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _mouse_input:
		_rotation_input = -event.relative.x * mouse_sensitivity
		_tilt_input = -event.relative.y * mouse_sensitivity


func _physics_process(delta: float) -> void:
	_rotation_input += Input.get_action_raw_strength("camera_left") - Input.get_action_raw_strength("camera_right")
	_tilt_input += Input.get_action_raw_strength("camera_up") - Input.get_action_raw_strength("camera_down")
	
	if EditMode.is_enabled:
		_rotation_input = 0.0
		_tilt_input = 0.0
	
	if invert_mouse_y:
		_tilt_input *= -1

	# Rotates camera using euler rotation
	_euler_rotation.x += _tilt_input * delta
	_euler_rotation.x = clamp(_euler_rotation.x, tilt_lower_limit, tilt_upper_limit)
	_euler_rotation.y += _rotation_input * delta
	transform.basis = Basis.from_euler(_euler_rotation)

	if _spectator_mode:
		# Free-fly controls used while the local player is dead.
		var raw_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var move_dir := Vector3.ZERO
		move_dir += -global_transform.basis.x * raw_input.x
		move_dir += -global_transform.basis.z * raw_input.y

		var vertical_input := 0.0
		if Input.is_key_pressed(KEY_E):
			vertical_input += 1.0
		if Input.is_key_pressed(KEY_Q):
			vertical_input -= 1.0
		move_dir += Vector3.UP * vertical_input

		if not move_dir.is_zero_approx():
			global_position += move_dir.normalized() * spectator_speed * delta
		
		camera.global_transform = _pivot.global_transform
		camera.rotation.z = 0
		_rotation_input = 0.0
		_tilt_input = 0.0
		return

	if not _anchor:
		_rotation_input = 0.0
		_tilt_input = 0.0
		return
	
	# Set camera controller to current ground level for the character
	var target_position := _anchor.global_position + _offset
	target_position.y = lerp(global_position.y, _anchor._ground_height, 0.1)
	global_position = target_position

	camera.global_transform = _pivot.global_transform
	camera.rotation.z = 0
	
	_rotation_input = 0.0
	_tilt_input = 0.0


func setup(anchor: CharacterBody3D) -> void:
	_anchor = anchor
	# Keep a stable third-person offset so respawns can restore camera quickly.
	if not _has_offset:
		_offset = global_transform.origin - anchor.global_transform.origin
		_has_offset = true
	camera.global_transform = camera.global_transform.interpolate_with(_pivot.global_transform, 0.1)
	_camera_spring_arm.add_excluded_object(_anchor.get_rid())


func set_spectator_mode(enabled: bool) -> void:
	_spectator_mode = enabled
	if enabled:
		# Detach from character so camera movement is fully manual.
		_anchor = null


func exit_spectator(anchor: CharacterBody3D) -> void:
	_spectator_mode = false
	_anchor = anchor
	if not _has_offset:
		_offset = global_transform.origin - anchor.global_transform.origin
		_has_offset = true
	global_position = anchor.global_position + _offset
	camera.global_transform = _pivot.global_transform
