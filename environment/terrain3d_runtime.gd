extends Terrain3D

@onready var _fallback_camera: Camera3D = get_node_or_null("FallbackCamera") as Camera3D
var _bound_camera: Camera3D


func _ready() -> void:
	_sync_camera()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_camera()


func _sync_camera() -> void:
	var active_camera := get_viewport().get_camera_3d()
	var desired := active_camera if active_camera != null else _fallback_camera
	if desired == null:
		return
	if desired != _bound_camera:
		_bound_camera = desired
		set_camera(desired)
