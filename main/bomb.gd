extends StaticBody3D
class_name Bomb

const PUFF_SCENE := preload("res://enemies/smoke_puff/smoke_puff.tscn")

@export var fuse_seconds: float = 5.0
@export var explosion_radius: float = 4.0
@export var explosion_force: float = 9.0
@export var explosion_mask: int = 2147483647

@onready var _countdown_label: Label3D = $CountdownLabel3D

var _explode_at_sec: float = 0.0
var _exploded := false


func _ready() -> void:
	DebugLog.gameplay("Bomb ready at %s" % str(global_position))
	# Use an absolute explode timestamp so countdown stays deterministic per instance.
	_explode_at_sec = Time.get_ticks_msec() / 1000.0 + fuse_seconds
	_update_countdown_label()


func _process(_delta: float) -> void:
	if _exploded:
		return

	var remaining: float = _explode_at_sec - (Time.get_ticks_msec() / 1000.0)
	if remaining <= 0.0:
		_explode()
		return
	_update_countdown_label()


func _update_countdown_label() -> void:
	var remaining: float = _explode_at_sec - (Time.get_ticks_msec() / 1000.0)
	var shown_seconds: int = maxi(0, int(ceil(remaining)))
	_countdown_label.text = str(shown_seconds)


func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	_spawn_puff()

	# Visual explosion can be local; gameplay damage stays server-authoritative.
	if multiplayer.is_server():
		_apply_explosion_damage()

	queue_free()


func _spawn_puff() -> void:
	var puff := PUFF_SCENE.instantiate()
	get_parent().add_child(puff)
	puff.global_position = global_position


func _apply_explosion_damage() -> void:
	# Query a sphere volume around the bomb and apply radial force-based damage.
	var sphere := SphereShape3D.new()
	sphere.radius = explosion_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.collision_mask = explosion_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var hits := get_world_3d().direct_space_state.intersect_shape(query, 64)
	var processed: Dictionary = {}
	for hit in hits:
		var collider: Variant = hit.get("collider")
		if not (collider is Node3D):
			continue

		var body := collider as Node3D
		var body_id := body.get_instance_id()
		# A body may have multiple colliders; process each body only once.
		if processed.has(body_id):
			continue
		processed[body_id] = true

		if not (body.is_in_group("damageables") and body.has_method("damage")):
			continue

		var to_body: Vector3 = body.global_position - global_position
		var dist: float = maxf(0.001, to_body.length())
		if dist > explosion_radius:
			continue

		var dir: Vector3 = to_body / dist
		var attenuation: float = 1.0 - (dist / explosion_radius)
		var force: Vector3 = dir * (explosion_force * attenuation)
		var impact_point: Vector3 = global_position - body.global_position
		body.damage(impact_point, force)
