extends GutTest


func test_record_sync_event_stores_structured_history_and_caps_length() -> void:
	var connection := Connection.new()
	add_child_autofree(connection)
	await wait_process_frames(1)

	connection.clear_recent_sync_events()
	for index in range(15):
		connection.record_sync_event("coffre", "delta rev=%d" % index, {
			"revision": index,
		})

	var event_lines: Array[String] = connection.get_recent_sync_events()
	var event_entries: Array[Dictionary] = connection.get_recent_sync_event_entries()
	assert_eq(Connection.MAX_RECENT_SYNC_EVENTS, event_lines.size(), "Le texte des événements doit être borné.")
	assert_eq(Connection.MAX_RECENT_SYNC_EVENTS, event_entries.size(), "Les événements structurés doivent être bornés.")
	assert_string_contains(event_lines[0], "delta rev=3")
	var last_entry: Dictionary = event_entries[event_entries.size() - 1]
	assert_eq("coffre", String(last_entry.get("source", "")))
	assert_eq("delta rev=14", String(last_entry.get("detail", "")))
	assert_eq(14, int((last_entry.get("metadata", {}) as Dictionary).get("revision", -1)))
	assert_string_contains(String(last_entry.get("text", "")), "coffre | delta rev=14")


func test_clear_recent_sync_events_empties_both_views() -> void:
	var connection := Connection.new()
	add_child_autofree(connection)
	await wait_process_frames(1)

	connection.record_sync_event("coin", "consomme")
	assert_false(connection.get_recent_sync_events().is_empty())
	assert_false(connection.get_recent_sync_event_entries().is_empty())

	connection.clear_recent_sync_events()
	assert_true(connection.get_recent_sync_events().is_empty())
	assert_true(connection.get_recent_sync_event_entries().is_empty())
