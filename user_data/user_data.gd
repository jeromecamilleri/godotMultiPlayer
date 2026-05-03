extends Node
class_name UserData

signal nickname_changed(nickname: String)

@export var nickname: String:
	set(value):
		nickname = value
		nickname_changed.emit(value)

var is_my_data: bool
var id: int
