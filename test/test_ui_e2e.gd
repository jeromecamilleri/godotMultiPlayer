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


func test_ui_e2e_inventory_chest() -> void:
	if OS.get_name() != "Linux":
		assert_true(true, "E2E UI ignoré : Linux uniquement.")
		return
	if OS.get_environment("RUN_UI_E2E").is_empty():
		assert_true(true, "E2E UI ignoré : définir RUN_UI_E2E=1 pour lancer (ex. lancer Godot depuis un terminal avec cette variable).")
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
	var result := _run_ui_script("test/UI/test_inventory_transfer_multiplayer_ui.sh")
	_assert_e2e_result("test_inventory_transfer_multiplayer_ui.sh", result)
