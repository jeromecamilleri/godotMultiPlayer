extends GutTest

const UserDataManagerScript := preload("res://user_data/user_data_manager.gd")
const UserDataScript := preload("res://user_data/user_data.gd")


func test_normalize_nickname_uses_default_when_blank() -> void:
	assert_eq("Player", UserDataManagerScript.normalize_nickname("   "))


func test_normalize_nickname_trims_and_limits_length() -> void:
	var normalized: String = UserDataManagerScript.normalize_nickname("  1234567890123456789012345  ")

	assert_eq(20, normalized.length())
	assert_eq("12345678901234567890", normalized)


func test_configured_local_nickname_is_applied_to_user_data() -> void:
	var manager: UserDataManager = autofree(UserDataManagerScript.new()) as UserDataManager
	var user_data: UserData = autofree(UserDataScript.new()) as UserData

	manager.configure_local_nickname("  Camille  ")
	manager.apply_local_nickname_to(user_data)

	assert_eq("Camille", manager.get_pending_local_nickname())
	assert_eq("Camille", user_data.nickname)


func test_default_local_nickname_starts_without_index_before_connection() -> void:
	var manager: UserDataManager = autofree(UserDataManagerScript.new()) as UserDataManager

	assert_eq("Player", manager.get_pending_local_nickname())
