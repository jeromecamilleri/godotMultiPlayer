extends OmniLight3D

@export var base_energy := 1.05
@export var flicker_energy := 1.15
@export var base_range := 5.2
@export var flicker_range := 1.1
@export var flicker_speed := 8.0
@export var flame_mesh_path: NodePath

var _phase := 0.0
var _flame_mesh: MeshInstance3D
var _flame_material: StandardMaterial3D


func _ready() -> void:
	_phase = float(abs(hash(get_path()))) * 0.001
	_flame_mesh = get_node_or_null(flame_mesh_path) as MeshInstance3D
	if _flame_mesh != null:
		_flame_material = _flame_mesh.get_surface_override_material(0) as StandardMaterial3D
		if _flame_material != null:
			_flame_material = _flame_material.duplicate()
			_flame_mesh.set_surface_override_material(0, _flame_material)
	_apply_flicker(0.0)


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var flicker := (
		sin(_phase) * 0.45
		+ sin(_phase * 2.37 + 1.8) * 0.32
		+ sin(_phase * 5.11 + 0.6) * 0.23
	)
	_apply_flicker(clampf((flicker + 1.0) * 0.5, 0.0, 1.0))


func _apply_flicker(amount: float) -> void:
	light_energy = base_energy + flicker_energy * amount
	omni_range = base_range + flicker_range * amount
	light_color = Color(1.0, lerpf(0.42, 0.58, amount), lerpf(0.08, 0.16, amount), 1.0)

	if _flame_mesh == null:
		return
	var flame_scale := lerpf(0.82, 1.18, amount)
	_flame_mesh.scale = Vector3(0.55, 0.85 * flame_scale, 0.55)
	if _flame_material != null:
		_flame_material.emission_energy_multiplier = lerpf(1.9, 4.2, amount)
