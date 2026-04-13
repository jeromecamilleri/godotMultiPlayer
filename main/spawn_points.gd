extends Node3D
class_name SpawnPoints

var spawn_points: Array[Node]
var used_ids: Array[int]
var size: int


func _ready() -> void:
	# Exclure les nœuds zone_* qui sont réservés aux overrides DEV_SPAWN_ZONE
	spawn_points = get_children().filter(func(c): return not String(c.name).begins_with("zone_")) as Array[Node]
	size = spawn_points.size()


func get_spawn_position() -> Vector3:
	var id = 0
	for x in range(1000):
		id = randi() % size
		if not id in used_ids:
			used_ids.push_back(id)
			break
		elif used_ids.size() == size:
			used_ids.pop_front()
	
	return spawn_points[id].global_position


## Retourne la position d'un spawn nommé "zone_<zone_name>" si il existe,
## sinon retourne la position aléatoire normale. Utilisé par DEV_SPAWN_ZONE.
func get_dev_zone_spawn_position(zone_name: String) -> Vector3:
	var node_name := "zone_%s" % zone_name.to_lower().strip_edges()
	var override := get_node_or_null(node_name)
	if override is Node3D:
		return (override as Node3D).global_position
	# Fallback : spawn aléatoire normal
	push_warning("[SpawnPoints] Nœud '%s' non trouvé, spawn aléatoire utilisé." % node_name)
	return get_spawn_position()
