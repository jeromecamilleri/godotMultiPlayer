extends Node3D

@export var scale_decay: Curve
@export var distance_limit: float = 5.0
@export var damage_enabled: bool = true
@export var hit_mask: int = 2147483647

var velocity: Vector3 = Vector3.ZERO
var shooter: Node = null

@onready var _area: Area3D = $Area3d
@onready var _bullet_visuals: Node3D = $Bullet
@onready var _projectile_sound: AudioStreamPlayer3D = $ProjectileSound

@onready var _time_alive := 0.0
@onready var _alive_limit := 0.0


func _ready() -> void:
	_area.body_entered.connect(_on_body_entered)
	_area.monitoring = true
	_area.monitorable = false
	# Face movement direction so visual trail/spark orientation matches travel.
	look_at(global_position + velocity)
	# Lifetime is distance-based to keep behavior consistent across frame rates.
	_alive_limit = distance_limit / velocity.length()
	_projectile_sound.pitch_scale = randfn(1.0, 0.1)
	_projectile_sound.play()


func _process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta

	# Raycast between previous and next position to avoid tunneling at high speed.
	var query := PhysicsRayQueryParameters3D.create(from, to, hit_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [_area.get_rid()]
	if shooter is CollisionObject3D:
		query.exclude.append((shooter as CollisionObject3D).get_rid())

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		_handle_collision(hit["collider"])
		return

	global_position = to
	_time_alive += delta
	
	_bullet_visuals.scale = Vector3.ONE * scale_decay.sample(_time_alive/_alive_limit)
	
	if _time_alive > _alive_limit:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	_handle_collision(body)


func _handle_collision(collider: Variant) -> void:
	if collider == null:
		return
	if not (collider is Node3D):
		queue_free()
		return

	var body := collider as Node3D
	if body == shooter:
		return

	# Gameplay damage can be disabled on non-authority peers for visual-only bullets.
	if damage_enabled and body.is_in_group("damageables") and body.has_method("damage"):
		var impact_point := global_position - body.global_position
		body.damage(impact_point, velocity)
	queue_free()
