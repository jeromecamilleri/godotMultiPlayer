extends Area3D

@onready var collision_shape: CollisionShape3D = $CollisionShape3d



func _ready() -> void:
	# Hit detection is event-based and only active during attack frames.
	body_entered.connect(_on_body_entered)


func activate():
	# Enabled by animation event at attack start.
	collision_shape.set_deferred("disabled", false)


func deactivate():
	# Disabled by animation event at attack end.
	collision_shape.set_deferred("disabled", true)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("damageables") and body.has_method("damage"):
		# Reuse the generic damage interface so enemies/players handle authority routing.
		var impact_point := global_position - body.global_position
		var force := -impact_point
		body.damage(impact_point, force)
