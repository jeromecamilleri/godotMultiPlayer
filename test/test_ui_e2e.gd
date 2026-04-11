extends GutTest
## Tests E2E UI : exécutent les scripts Python de test/UI (Xvfb, plusieurs instances Godot).
## Ils sont lancés comme processus externes ; la suite GUT vérifie le code de sortie.
##
## Prérequis (Linux) : Xvfb, xdotool, ImageMagick (import), python3, PIL.
## Pour exécuter uniquement les tests unitaires sans ces E2E : désactiver ce script dans GUT
## ou ne pas lancer sur un runeur qui n’a pas les prérequis.
## Variable d’environnement RUN_UI_E2E=1 pour forcer l’exécution (sinon skip si pas Linux).


func _project_root() -> String:
	var p: String = ProjectSettings.globalize_path("res://")
	if p.ends_with("/"):
		return p.substr(0, p.length() - 1)
	return p


const E2E_OUTPUT_MAX_CHARS := 3000

func _run_ui_script(script_name: String) -> Dictionary:
	var root := _project_root()
	var script_path := root + "/" + script_name
	var out: Dictionary = {"exit_code": -999, "output": ""}
	if not FileAccess.file_exists(script_path):
		out.output = "Script introuvable: %s" % script_path
		return out
	var output: Array = []
	out.exit_code = OS.execute("bash", [script_path], output, true, false)
	var output_str := ""
	for s in output:
		output_str += str(s)
	if output_str.length() > E2E_OUTPUT_MAX_CHARS:
		output_str = output_str.substr(0, E2E_OUTPUT_MAX_CHARS) + "\n... (tronqué)"
	out.output = output_str
	return out


func _assert_e2e_result(script_name: String, result: Dictionary) -> void:
	assert_eq(result.exit_code, 0, "E2E %s a échoué (exit %s).\n%s" % [script_name, result.exit_code, result.output])


func _ui_e2e_profile() -> String:
	var profile := OS.get_environment("UI_E2E_PROFILE").strip_edges().to_lower()
	if profile == "smoke" or profile == "full":
		return profile
	return "full"


func _should_run_ui_test(test_key: String) -> bool:
	if _ui_e2e_profile() == "full":
		return true
	var smoke_tests := {
		"inventory_chest": true,
		"portal_unlock": true,
		"portal_progression_breche": true,
		"cube_mission": true,
	}
	return bool(smoke_tests.get(test_key, false))


func test_ui_e2e_inventory_chest() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("inventory_chest"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_inventory_chest_ui.sh")
	_assert_e2e_result("test_inventory_chest_ui.sh", result)


func test_ui_e2e_inventory_transfer_multiplayer() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("inventory_transfer_multiplayer"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_inventory_transfer_multiplayer_ui.sh")
	_assert_e2e_result("test_inventory_transfer_multiplayer_ui.sh", result)


func test_ui_e2e_late_join_bomb_and_wood() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("late_join_bomb_wood"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_late_join_bomb_wood_ui.sh")
	_assert_e2e_result("test_late_join_bomb_wood_ui.sh", result)


func test_ui_e2e_cube_mission() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("cube_mission"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_cube_mission_ui.sh")
	_assert_e2e_result("test_cube_mission_ui.sh", result)


func test_ui_e2e_cube_mission_lock() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("cube_mission_lock"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_cube_mission_lock_ui.sh")
	_assert_e2e_result("test_cube_mission_lock_ui.sh", result)


func test_ui_e2e_beetle_targeting() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("beetle_targeting"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_beetle_targeting_ui.sh")
	_assert_e2e_result("test_beetle_targeting_ui.sh", result)


func test_ui_e2e_beetle_door_charge() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("beetle_door_charge"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_beetle_door_charge_ui.sh")
	_assert_e2e_result("test_beetle_door_charge_ui.sh", result)


func test_ui_e2e_portal_unlock() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("portal_unlock"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_portal_unlock_ui.sh")
	_assert_e2e_result("test_portal_unlock_ui.sh", result)


func test_ui_e2e_portal_logistics() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("portal_logistics"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_portal_logistics_ui.sh")
	_assert_e2e_result("test_portal_logistics_ui.sh", result)


func test_ui_e2e_portal_progression_breche() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("portal_progression_breche"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_portal_progression_breche_ui.sh")
	_assert_e2e_result("test_portal_progression_breche_ui.sh", result)


func test_ui_e2e_portal_progression_reactor() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("portal_progression_reactor"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_portal_progression_reactor_ui.sh")
	_assert_e2e_result("test_portal_progression_reactor_ui.sh", result)


func test_ui_e2e_portal_progression() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
		return
	if not _should_run_ui_test("portal_progression_full"):
		assert_true(true, "E2E UI ignoré par profil %s." % _ui_e2e_profile())
		return
	var result := _run_ui_script("test/UI/test_portal_progression_ui.sh")
	_assert_e2e_result("test_portal_progression_ui.sh", result)
