extends StaticBody3D
class_name BombDoor

enum OpenBehavior {
	LIFT,
	DISINTEGRATE,
}

const PUFF_SCENE := preload("res://enemies/smoke_puff/smoke_puff.tscn")

@export var required_bombs := 1
@export var trigger_radius := 5.0
@export var open_behavior: OpenBehavior = OpenBehavior.DISINTEGRATE
@export var open_height := 3.0
@export var open_tween_duration := 0.35
@export var disintegrate_duration := 0.45
@export var disintegrate_scale := 0.05
@export var objective_id := ""

@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D

var _bomb_hits := 0
var _is_open := false
var _closed_position := Vector3.ZERO
var _closed_scale := Vector3.ONE


func _ready() -> void:
	# Bomb reactives listen to utility explosions through a shared group.
	add_to_group("bomb_reactives")
	_closed_position = global_position
	_closed_scale = _mesh_instance.scale


func on_bomb_exploded(world_pos: Vector3, explosion_radius: float, _owner_peer_id: int) -> void:
	# Server decides door progression/opening to keep deterministic multiplayer state.
	if not multiplayer.is_server():
		return
	if _is_open:
		return
	var max_distance := trigger_radius + explosion_radius
	if global_position.distance_to(world_pos) > max_distance:
		return

	_bomb_hits += 1
	if _bomb_hits < required_bombs:
		return

	_set_open_state.rpc(true)
	if objective_id.strip_edges() != "":
		var director := get_tree().get_first_node_in_group("match_director")
		if is_instance_valid(director) and director.has_method("report_objective_progress"):
			director.report_objective_progress(objective_id, 1)


@rpc("any_peer", "reliable")
func _set_open_state(open: bool) -> void:
	if _is_open == open:
		return
	_is_open = open
	_collision_shape.disabled = open
	if open:
		if open_behavior == OpenBehavior.DISINTEGRATE:
			_play_disintegrate_open_effect()
			return
		var target_position := _closed_position + Vector3.UP * open_height
		var tween := create_tween()
		tween.tween_property(self, "global_position", target_position, open_tween_duration)
		return

	# Reset path (currently only useful for editor/manual testing).
	_mesh_instance.visible = true
	_mesh_instance.scale = _closed_scale
	_mesh_instance.transparency = 0.0
	global_position = _closed_position


func _play_disintegrate_open_effect() -> void:
	_spawn_puff()
	var tween := create_tween()
	tween.parallel().tween_property(_mesh_instance, "scale", _closed_scale * disintegrate_scale, disintegrate_duration)
	tween.parallel().tween_property(_mesh_instance, "transparency", 1.0, disintegrate_duration)
	tween.tween_callback(_mesh_instance.hide)


func _spawn_puff() -> void:
	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position


func is_open() -> bool:
	return _is_open
