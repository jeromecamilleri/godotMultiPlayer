extends GutTest


class FakePlayer:
	extends RefCounted

	var focused_target: Node = null
	var pickup_paths: Array[NodePath] = []

	func set_focused_inventory_target(target: Node) -> void:
		focused_target = target

	func request_pickup_world_item(path: NodePath) -> void:
		pickup_paths.append(path)


class InteractionsDouble:
	extends PlayerInteractionsComponent

	var forced_target: Node = null
	var forced_proximity_target: Node = null
	var forced_fallback_pickable: Node = null
	var forced_fallback_inventory: Node = null

	func _get_interaction_target(_player) -> Node:
		return forced_target

	func _find_nearest_proximity_target(_player, _allow_pickable: bool = true, _allow_inventory: bool = true) -> Node:
		return forced_proximity_target

	func _find_nearest_pickable_target(_player) -> Node:
		return forced_fallback_pickable

	func _find_nearest_world_inventory_target(_player) -> Node:
		return forced_fallback_inventory


func _make_inventory_target(name: String) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nfunc get_inventory_component():\n\treturn self\n"
	assert_eq(OK, script.reload())
	var target := Node3D.new()
	target.name = name
	target.set_script(script)
	return target


func _make_barrel_target() -> Dictionary:
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	barrel.add_to_group("pushable_barrels")
	var mesh := Node3D.new()
	mesh.name = "BarrelMesh"
	barrel.add_child(mesh)
	return {
		"barrel": barrel,
		"mesh": mesh,
	}


func test_try_pickup_or_focus_target_does_not_focus_chest_when_barrel_blocks() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var chest := _make_inventory_target("Chest")
	root.add_child(chest)
	var barrel_setup := _make_barrel_target()
	var barrel := barrel_setup["barrel"] as Node3D
	var barrel_mesh := barrel_setup["mesh"] as Node3D
	root.add_child(barrel)

	var interactions := InteractionsDouble.new()
	interactions.forced_target = barrel_mesh
	interactions.forced_fallback_inventory = chest

	var player := FakePlayer.new()
	player.set_focused_inventory_target(chest)

	var consumed := interactions.try_pickup_or_focus_target(player)

	assert_true(consumed, "Le tonneau devant le joueur doit consommer l'interaction.")
	assert_null(player.focused_target, "Le coffre ne doit pas etre focus si un tonneau bloque le raycast.")
	assert_eq(0, player.pickup_paths.size(), "Aucun ramassage ne doit etre declenche dans ce cas.")

	var refreshed := interactions.refresh_inventory_focus(player)
	assert_false(refreshed, "Le focus inventaire doit rester inactif tant que le tonneau bloque.")
	assert_null(player.focused_target)


func test_try_pickup_or_focus_target_focuses_chest_without_barrel_blocker() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var chest := _make_inventory_target("Chest")
	root.add_child(chest)

	var interactions := InteractionsDouble.new()
	interactions.forced_target = chest

	var player := FakePlayer.new()
	player.set_focused_inventory_target(null)

	var consumed := interactions.try_pickup_or_focus_target(player)

	assert_true(consumed, "Le coffre doit rester interactif quand il est la cible directe.")
	assert_true(player.focused_target == chest, "Le focus doit pointer sur le coffre cible.")
	assert_eq(0, player.pickup_paths.size())
