extends RigidBody3D

@export var server_peer_id := 1

func _ready() -> void:
	set_multiplayer_authority(server_peer_id)
	# Only the authority simulates physics; clients receive replicated state.
	freeze = not is_multiplayer_authority()
	sleeping = not is_multiplayer_authority()


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# Prevent local physics from fighting replicated transform updates.
		sleeping = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_push(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_central_impulse(impulse)
