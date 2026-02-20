extends RigidBody3D

@export var server_peer_id := 1

@export var base_mass := 2.0
@export var mass_per_player := 2.0
@export var min_players := 1

func _on_player_count_changed(_id: int) -> void:
	_update_mass_for_player_count()

func _update_mass_for_player_count() -> void:
	var players: int = max(min_players, multiplayer.get_peers().size() + 1) # + 1 for server/host peer
	mass = base_mass + mass_per_player * float(players - 1)


func _ready() -> void:
	# Only the authority simulates physics; clients receive replicated state.
	set_multiplayer_authority(server_peer_id)
	freeze = not is_multiplayer_authority()
	sleeping = not is_multiplayer_authority()
	if is_multiplayer_authority():
		_update_mass_for_player_count()
		multiplayer.peer_connected.connect(_on_player_count_changed)
		multiplayer.peer_disconnected.connect(_on_player_count_changed)


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		# Prevent local physics from fighting replicated transform updates.
		sleeping = true


@rpc("any_peer", "call_remote", "unreliable_ordered")
func request_push(impulse: Vector3) -> void:
	if not is_multiplayer_authority():
		return
	apply_central_impulse(impulse)
