extends SceneTree

# Backup helper for the scierie Terrain3D data.
# Usage:
#   /dataSSD/Godot_v4.6.2-stable_linux.x86_64 --headless --path . -s res://tools/backup_zone_scierie_terrain.gd
#
# What it copies:
# - zone_scierie.tscn
# - terrain assets/material resources used by the scene
# - every file in levels/zones/zone_scierie_terrain_data
#
# Output location:
# - user://terrain_backups/zone_scierie_<timestamp>/
#   Godot prints the resolved absolute path in the terminal.

const FILES_TO_COPY := [
	"res://levels/zones/zone_scierie.tscn",
	"res://levels/zones/zone_scierie_terrain_assets.tres",
	"res://levels/zones/zone_scierie_terrain_material.tres",
	"res://levels/zones/zone_scierie_grass_terrain.png",
	"res://levels/zones/zone_scierie_grass_terrain_normal.png",
	"res://levels/zones/zone_scierie_dirt_terrain.png",
	"res://levels/zones/zone_scierie_dirt_terrain_normal.png",
]
const DATA_DIR := "res://levels/zones/zone_scierie_terrain_data"
const BACKUP_ROOT := "user://terrain_backups"


func _initialize() -> void:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var backup_dir := "%s/zone_scierie_%s" % [BACKUP_ROOT, timestamp]
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(backup_dir))
	if err != OK:
		push_error("Impossible de creer le dossier de backup: %s" % backup_dir)
		quit(1)
		return

	for file_path in FILES_TO_COPY:
		_copy_file(file_path, backup_dir.path_join(file_path.get_file()))

	_copy_directory(DATA_DIR, backup_dir.path_join("zone_scierie_terrain_data"))
	print("Backup scierie cree dans: %s" % ProjectSettings.globalize_path(backup_dir))
	quit()


func _copy_directory(source_dir: String, dest_dir: String) -> void:
	var source_abs := ProjectSettings.globalize_path(source_dir)
	var dest_abs := ProjectSettings.globalize_path(dest_dir)
	var err := DirAccess.make_dir_recursive_absolute(dest_abs)
	if err != OK:
		push_error("Impossible de creer le dossier cible: %s" % dest_dir)
		quit(1)
		return

	var dir := DirAccess.open(source_abs)
	if dir == null:
		push_error("Impossible d'ouvrir le dossier source: %s" % source_dir)
		quit(1)
		return

	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var src_path := source_dir.path_join(entry)
		var dst_path := dest_dir.path_join(entry)
		if dir.current_is_dir():
			_copy_directory(src_path, dst_path)
		else:
			_copy_file(src_path, dst_path)
	dir.list_dir_end()


func _copy_file(source_path: String, dest_path: String) -> void:
	var source_abs := ProjectSettings.globalize_path(source_path)
	var dest_abs := ProjectSettings.globalize_path(dest_path)
	var parent_dir := dest_abs.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(parent_dir)
	if err != OK:
		push_error("Impossible de creer le dossier parent: %s" % parent_dir)
		quit(1)
		return

	err = DirAccess.copy_absolute(source_abs, dest_abs)
	if err != OK:
		push_error("Copie impossible: %s -> %s" % [source_path, dest_path])
		quit(1)
