extends Node3D

@export var url: String
@export var linked_portal_path: NodePath
@export var exit_distance := 2.0
@export var teleport_cooldown_ms := 600
@export var starts_active := true
@export var portal_title := ""
@export var locked_status_text := "BLOQUE"
@export var unlocked_status_text := "OUVERT"
@export var inactive_light_energy := 0.6
@export var active_light_energy := 3.141
@export var inactive_color: Color = Color(0.93, 0.19, 0.17, 1.0)
@export var active_color: Color = Color(0.18, 0.95, 0.39, 1.0)
@export var inactive_plane_alpha := 0.52
@export var active_plane_alpha := 0.72
@export var inactive_emission_energy := 0.7
@export var active_emission_energy := 2.2

var _last_teleport_by_authority: Dictionary = {}
var _is_active := true
var _state_revision := 0
var _last_state_server_ms := -1
var _last_state_replication_delay_ms := -1

@onready var _portal_area: Area3D = $Portal
@onready var _portal_light: OmniLight3D = $Portal/OmniLight3D
@onready var _portal_plane_front: MeshInstance3D = $Portal/MeshInstance3D
@onready var _portal_plane_back: MeshInstance3D = $Portal/MeshInstance3D2
@onready var _portal_label: Label3D = $PortalLabel
@onready var _guide_pylon_left: MeshInstance3D = $GuidePylonLeft
@onready var _guide_pylon_right: MeshInstance3D = $GuidePylonRight


func _ready() -> void:
	add_to_group("replicated_persistent_objects")
	if _is_authority_instance():
		_is_active = starts_active
		_state_revision = 1
		_last_state_server_ms = Time.get_ticks_msec()
		if multiplayer.multiplayer_peer != null and not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	else:
		_request_current_state_when_connected()
	_apply_portal_state(_is_active)


func _on_portal_entered(body):
	if not body is Player: return
	if not _is_active:
		return
	if body.get_multiplayer_authority() != multiplayer.get_unique_id(): return

	var authority_id: int = body.get_multiplayer_authority()
	var now_ms: int = Time.get_ticks_msec()
	var last_ms: int = int(_last_teleport_by_authority.get(authority_id, 0))
	if now_ms - last_ms < teleport_cooldown_ms:
		return

	var target: Node3D = get_node_or_null(linked_portal_path) as Node3D
	if target != null:
		_last_teleport_by_authority[authority_id] = now_ms
		if target.has_method("set_last_teleport_for"):
			target.set_last_teleport_for(authority_id, now_ms)

		var target_exit_distance: float = exit_distance
		if "exit_distance" in target:
			target_exit_distance = float(target.get("exit_distance"))
		var exit_pos: Vector3 = target.global_position + target.global_transform.basis.z * target_exit_distance + Vector3.UP * 0.5
		body.global_position = exit_pos
		if "velocity" in body:
			body.velocity = Vector3.ZERO
		return

	DebugLog.gameplay("Portal_entered: " + url)
	await get_tree().create_timer(0.2).timeout

	if get_tree().has_method("open_gate"):
		get_tree().open_gate(url)
	else:
		push_warning("Tree doesn't have method open_gate. Do nothing")


func set_last_teleport_for(authority_id: int, timestamp_ms: int) -> void:
	_last_teleport_by_authority[authority_id] = timestamp_ms


func set_portal_active(active: bool) -> void:
	if not _is_authority_instance():
		return
	if _state_revision > 0 and _is_active == active:
		return
	_is_active = active
	_state_revision += 1
	_last_state_server_ms = Time.get_ticks_msec()
	_apply_portal_state(_is_active)
	_record_sync_event("portal", "%s %s rev=%d" % [name, "active" if _is_active else "inactive", _state_revision])
	_sync_portal_state.rpc(_is_active, _state_revision, _last_state_server_ms)


func is_portal_active() -> bool:
	return _is_active


func request_current_state_from_server() -> void:
	_request_current_state_when_connected()


func push_current_state_to_peer(peer_id: int) -> void:
	if not _is_authority_instance():
		return
	_sync_portal_state.rpc_id(peer_id, _is_active, _state_revision, _last_state_server_ms)


func get_state_revision() -> int:
	return _state_revision


func get_debug_sync_summary() -> String:
	return "portal=%s actif=%s rev=%d rep=%s" % [
		name,
		"oui" if _is_active else "non",
		_state_revision,
		"-" if _last_state_replication_delay_ms < 0 else "%d ms" % _last_state_replication_delay_ms,
	]


func _request_current_state_when_connected() -> void:
	if _is_authority_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_state")):
		return
	call_deferred("_request_current_state_from_authority")


func _on_connected_to_server_request_state() -> void:
	_request_current_state_from_authority()


func _request_current_state_from_authority() -> void:
	if _is_authority_instance():
		return
	if not Connection.ensure_client_rpc_ready(multiplayer, Callable(self, "_on_connected_to_server_request_state")):
		return
	_request_current_state.rpc_id(1)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_authority_instance():
		return
	call_deferred("push_current_state_to_peer", peer_id)


func _apply_portal_state(active: bool) -> void:
	_is_active = active
	if is_instance_valid(_portal_area):
		_portal_area.set_deferred("monitoring", active)
		_portal_area.set_deferred("monitorable", active)
	if is_instance_valid(_portal_light):
		_portal_light.light_color = active_color if active else inactive_color
		_portal_light.light_energy = active_light_energy if active else inactive_light_energy
	_apply_portal_visual_material(_portal_plane_front, active)
	_apply_portal_visual_material(_portal_plane_back, active)
	_apply_portal_visual_material(_guide_pylon_left, active)
	_apply_portal_visual_material(_guide_pylon_right, active)
	_update_portal_label(active)


func _apply_portal_visual_material(mesh_instance: MeshInstance3D, active: bool) -> void:
	if not is_instance_valid(mesh_instance):
		return
	var material := StandardMaterial3D.new()
	var target_color: Color = active_color if active else inactive_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(target_color.r, target_color.g, target_color.b, active_plane_alpha if active else inactive_plane_alpha)
	material.emission_enabled = true
	material.emission = target_color
	material.emission_energy_multiplier = active_emission_energy if active else inactive_emission_energy
	mesh_instance.set_surface_override_material(0, material)


func _update_portal_label(active: bool) -> void:
	if not is_instance_valid(_portal_label):
		return
	var base_title := _get_portal_display_name()
	var status_text := unlocked_status_text if active else locked_status_text
	_portal_label.text = "%s\n%s" % [base_title, status_text]
	_portal_label.modulate = active_color if active else inactive_color


func _get_portal_display_name() -> String:
	if not portal_title.is_empty():
		return portal_title
	match url:
		"zone_scierie":
			return "SCIERIE"
		"zone_verger":
			return "VERGER"
		"zone_breche":
			return "BRECHE"
		"zone_reactor":
			return "REACTOR"
		"hub":
			return "HUB"
		_:
			if not url.is_empty():
				return url.to_upper().replace("ZONE_", "")
	return name.to_upper()


@rpc("any_peer", "call_remote", "reliable")
func _request_current_state() -> void:
	if not _is_authority_instance():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	push_current_state_to_peer(sender_id)


@rpc("authority", "call_local", "reliable")
func _sync_portal_state(active: bool, revision: int, server_event_ms: int = -1) -> void:
	if revision >= 0 and revision < _state_revision:
		return
	_is_active = active
	if revision >= 0:
		_state_revision = revision
	_last_state_server_ms = server_event_ms
	if server_event_ms >= 0 and not _is_authority_instance():
		_last_state_replication_delay_ms = maxi(0, Time.get_ticks_msec() - server_event_ms)
	_apply_portal_state(_is_active)


func _record_sync_event(source: String, detail: String) -> void:
	var connection := get_tree().get_first_node_in_group("connection_service")
	if is_instance_valid(connection) and connection.has_method("record_sync_event"):
		connection.call("record_sync_event", source, detail)


func _is_authority_instance() -> bool:
	return multiplayer.is_server() or multiplayer.multiplayer_peer == null
