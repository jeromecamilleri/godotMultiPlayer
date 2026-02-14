extends Node
class_name DebugLog

static var enabled := false
static var network_enabled := true
static var gameplay_enabled := true


static func net(message: String) -> void:
	if enabled and network_enabled:
		print(message)


static func gameplay(message: String) -> void:
	if enabled and gameplay_enabled:
		print(message)
