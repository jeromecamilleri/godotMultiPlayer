extends GutTest

const BEE_DIRECTOR_SCRIPT := preload("res://enemies/bee_director.gd")
const BEETLE_DIRECTOR_SCRIPT := preload("res://enemies/beetle_director.gd")
const BEE_SCENE := preload("res://enemies/bee_bot.tscn")
const BEETLE_SCENE := preload("res://enemies/beetle_bot.tscn")


func test_enemy_instances_expose_common_director_contract() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var bee := BEE_SCENE.instantiate()
	var beetle := BEETLE_SCENE.instantiate()
	root.add_child(bee)
	root.add_child(beetle)

	assert_true(bee.is_in_group("enemy_instances"), "Une abeille doit exposer le groupe générique des ennemis gérés.")
	assert_true(beetle.is_in_group("enemy_instances"), "Un scarabée doit exposer le groupe générique des ennemis gérés.")
	assert_true(bee.has_method("set_director_active"), "Une abeille doit exposer set_director_active.")
	assert_true(beetle.has_method("set_director_active"), "Un scarabée doit exposer set_director_active.")
	assert_true(bee.has_method("apply_director_config"), "Une abeille doit exposer apply_director_config.")
	assert_true(beetle.has_method("apply_director_config"), "Un scarabée doit exposer apply_director_config.")
	assert_true(bee.has_method("get_current_target_peer_id"), "Une abeille doit exposer get_current_target_peer_id.")
	assert_true(beetle.has_method("get_current_target_peer_id"), "Un scarabée doit exposer get_current_target_peer_id.")
	assert_true(bee.has_method("get_assigned_target_peer_id"), "Une abeille doit exposer get_assigned_target_peer_id.")
	assert_true(beetle.has_method("get_assigned_target_peer_id"), "Un scarabée doit exposer get_assigned_target_peer_id.")


func test_enemy_directors_expose_common_groups() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var bee_director := BEE_DIRECTOR_SCRIPT.new()
	var beetle_director := BEETLE_DIRECTOR_SCRIPT.new()
	root.add_child(bee_director)
	root.add_child(beetle_director)

	assert_true(bee_director.is_in_group("enemy_directors"), "Le directeur d'abeilles doit exposer le groupe générique enemy_directors.")
	assert_true(beetle_director.is_in_group("enemy_directors"), "Le directeur de scarabées doit exposer le groupe générique enemy_directors.")
	assert_true(bee_director.is_in_group("bee_directors"), "Le directeur d'abeilles doit exposer son groupe spécifique.")
	assert_true(beetle_director.is_in_group("beetle_directors"), "Le directeur de scarabées doit exposer son groupe spécifique.")
