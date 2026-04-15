extends RigidBody3D

@export var server_peer_id := 1


func _ready() -> void:
	# Keep barrels server-authoritative like the rest of gameplay physics.
	set_multiplayer_authority(server_peer_id)
	add_to_group("replicated_persistent_objects")
	if not is_multiplayer_authority():
		sleeping = true


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# Prevent client-side physics from fighting replicated transforms.
		sleeping = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_push(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	# Clamp to avoid abusive impulses from malformed clients.
	var safe_impulse: Vector3 = impulse.limit_length(28.0)
	# Never add upward impulse from player collision pushes.
	safe_impulse.y = minf(0.0, safe_impulse.y)
	apply_central_impulse(safe_impulse)
