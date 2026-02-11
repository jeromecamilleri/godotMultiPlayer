extends Node
class_name FallChecker

@export var fall_height: float
@export var player_spawner: PlayerSpawner
@export var debug_respawn := true

var timer : Timer
var players = {} # {Peer ID: Player}


func _ready() -> void:
	timer = Timer.new()
	add_child(timer)
	timer.start(0.25)
	timer.timeout.connect(check_fallen)
	
	player_spawner.player_spawned.connect(player_spawned)
	player_spawner.player_despawned.connect(player_despawned)
	if debug_respawn:
		print("[FallChecker] ready | multiplayer.is_server=", multiplayer.is_server(), " fall_height=", fall_height)


func player_spawned(id: int, player: Player) -> void:
	players[id] = player
	if debug_respawn:
		print("[FallChecker] tracked player=", id, " y=", player.global_position.y)


func player_despawned(id: int) -> void:
	players.erase(id)
	if debug_respawn:
		print("[FallChecker] untracked player=", id)


func check_fallen() -> void:
	if not multiplayer.is_server():
		return
	for id in players.keys():
		var player = players[id] as Player
		if player.global_position.y < fall_height:
			if debug_respawn:
				print("[FallChecker] respawn trigger | player=", id, " y=", player.global_position.y, " threshold=", fall_height)
			player_spawner.respawn_player(id)
