extends SceneTree

# Regenerates the Terrain3D data for ZoneScierie.
#
# Usage:
#   /dataSSD/Godot_v4.6.2-stable_linux.x86_64 --headless --path . -s res://tools/generate_zone_scierie_terrain.gd
#
# What this script does:
# - clears res://levels/zones/zone_scierie_terrain_data
# - generates a compact island centered on the scierie gameplay area
# - keeps the portal, pickups, crates and landmark on stable ground near y=4
# - saves 4 terrain regions (64x64 each) for a small island footprint
#
# Main parameters to tweak:
# - ISLAND_HALF_EXTENTS: overall island width/depth before cliffs
# - PLATEAU_HALF_EXTENTS: flat playable area
# - EDGE_DEPTH: how far the border drops into the void
# - SAFE_POINTS: gameplay anchors forced flat so the terrain supports objects
#
# Important:
# ZoneScierie and its Terrain3D node are both saved at x = 120 in the scene so
# the Terrain3D editor and main/main.tscn use the same world coordinates.
# Keep ZONE_WORLD_OFFSET in sync with that saved scene transform.

const DATA_DIR := "res://levels/zones/zone_scierie_terrain_data"
const HEIGHT_SIZE := 128
const WORLD_HALF_SIZE := HEIGHT_SIZE * 0.5
const BASE_HEIGHT := 4.0
const EDGE_DEPTH := -4.0
const ZONE_WORLD_OFFSET := Vector2(120.0, 0.0)

const ISLAND_HALF_EXTENTS := Vector2(18.0, 12.0)
const PLATEAU_HALF_EXTENTS := Vector2(14.5, 9.5)
const RIM_HALF_EXTENTS := Vector2(16.2, 10.8)
const SAFE_RADIUS := 2.8

const SAFE_POINTS := [
	Vector2(-14.0, 0.0),
	Vector2(3.5, -3.0),
	Vector2(4.5, -1.8),
	Vector2(5.2, 2.4),
	Vector2(6.8, -2.2),
	Vector2(8.0, 0.0),
	Vector2(8.2, 0.35),
	Vector2(8.5, 1.8),
	Vector2(11.4, -1.7),
	Vector2(13.0, -8.0),
]


func _initialize() -> void:
	_reset_directory(DATA_DIR)

	var camera := Camera3D.new()
	camera.current = true
	root.add_child(camera)

	var terrain := Terrain3D.new()
	root.add_child(terrain)
	await process_frame
	await process_frame

	# Terrain3D picks up this value reliably once the node has entered the tree.
	terrain.region_size = 64
	terrain.set_camera(camera)
	await process_frame
	await process_frame

	var imported_images: Array[Image] = []
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = _build_height_image()
	imported_images[Terrain3DRegion.TYPE_COLOR] = _build_color_image()

	terrain.data.import_images(
		imported_images,
		Vector3(ZONE_WORLD_OFFSET.x - WORLD_HALF_SIZE, 0, ZONE_WORLD_OFFSET.y - WORLD_HALF_SIZE),
		0.0,
		1.0
	)
	terrain.data.save_directory(DATA_DIR)

	print("region_size=", terrain.region_size)
	print("saved_regions=", terrain.data.region_locations)
	print("height@portal=", terrain.data.get_height(Vector3(106.0, 0.0, 0.0)))
	print("height@pickup=", terrain.data.get_height(Vector3(128.2, 0.0, 0.35)))
	quit()


func _reset_directory(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path)
	var dir := DirAccess.open(absolute_path)
	if dir == null:
		push_error("Cannot open %s" % absolute_path)
		return
	for file_name in dir.get_files():
		var file_path := absolute_path.path_join(file_name)
		var err := DirAccess.remove_absolute(file_path)
		if err != OK:
			push_error("Cannot remove %s (%s)" % [file_path, error_string(err)])
	for directory_name in dir.get_directories():
		var subdir_path := absolute_path.path_join(directory_name)
		var err := DirAccess.remove_absolute(subdir_path)
		if err != OK:
			push_error("Cannot remove %s (%s)" % [subdir_path, error_string(err)])


func _build_height_image() -> Image:
	var image := Image.create_empty(HEIGHT_SIZE, HEIGHT_SIZE, false, Image.FORMAT_RF)
	var plateau_noise := FastNoiseLite.new()
	plateau_noise.seed = 241
	plateau_noise.frequency = 0.18
	var rim_noise := FastNoiseLite.new()
	rim_noise.seed = 911
	rim_noise.frequency = 0.08

	for x in image.get_width():
		for z in image.get_height():
			var world := _image_to_world(x, z)
			var local := world - ZONE_WORLD_OFFSET
			var island_ratio := _ellipse_ratio(local, ISLAND_HALF_EXTENTS)
			var plateau_ratio := _ellipse_ratio(local, PLATEAU_HALF_EXTENTS)
			var rim_ratio := _ellipse_ratio(local, RIM_HALF_EXTENTS)

			var plateau_variation := plateau_noise.get_noise_2d(local.x, local.y) * 0.12
			var plateau_height := minf(0.0, plateau_variation * smoothstep(0.35, 1.0, plateau_ratio))
			var rim_drop := smoothstep(0.82, 1.0, rim_ratio)
			var outer_drop := smoothstep(0.94, 1.12, island_ratio)
			var rim_variation := rim_noise.get_noise_2d(local.x, local.y) * 0.2 * rim_drop

			var height := plateau_height
			height = minf(height, lerpf(0.0, -1.4, rim_drop) + rim_variation)
			height = minf(height, lerpf(height, EDGE_DEPTH, outer_drop))
			height = _flatten_near_safe_points(world, height)
			height += BASE_HEIGHT
			image.set_pixel(x, z, Color(height, 0.0, 0.0, 1.0))

	return image


func _build_color_image() -> Image:
	var image := Image.create_empty(HEIGHT_SIZE, HEIGHT_SIZE, false, Image.FORMAT_RGBA8)
	var dirt_noise := FastNoiseLite.new()
	dirt_noise.seed = 101
	dirt_noise.frequency = 0.16
	var moss_noise := FastNoiseLite.new()
	moss_noise.seed = 404
	moss_noise.frequency = 0.09

	var dirt_low := Color(0.36, 0.27, 0.18, 1.0)
	var dirt_high := Color(0.53, 0.40, 0.25, 1.0)
	var moss := Color(0.28, 0.35, 0.20, 1.0)
	var shadow := Color(0.18, 0.15, 0.12, 1.0)

	for x in image.get_width():
		for z in image.get_height():
			var world := _image_to_world(x, z)
			var local := world - ZONE_WORLD_OFFSET
			var island_ratio := _ellipse_ratio(local, ISLAND_HALF_EXTENTS)
			var plateau_ratio := _ellipse_ratio(local, PLATEAU_HALF_EXTENTS)
			var dirt_mix := clampf((dirt_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0)
			var moss_mix := clampf((moss_noise.get_noise_2d(local.x, local.y) + 1.0) * 0.5, 0.0, 1.0)

			var color := dirt_low.lerp(dirt_high, dirt_mix)
			color = color.lerp(moss, smoothstep(0.2, 0.85, plateau_ratio) * moss_mix * 0.22)
			color = color.lerp(shadow, smoothstep(0.88, 1.08, island_ratio) * 0.75)
			image.set_pixel(x, z, color)

	return image


func _image_to_world(x: int, z: int) -> Vector2:
	return Vector2(
		lerpf(ZONE_WORLD_OFFSET.x - WORLD_HALF_SIZE, ZONE_WORLD_OFFSET.x + WORLD_HALF_SIZE, float(x) / float(HEIGHT_SIZE - 1)),
		lerpf(ZONE_WORLD_OFFSET.y - WORLD_HALF_SIZE, ZONE_WORLD_OFFSET.y + WORLD_HALF_SIZE, float(z) / float(HEIGHT_SIZE - 1))
	)


func _ellipse_ratio(world: Vector2, half_extents: Vector2) -> float:
	var px := world.x / half_extents.x
	var pz := world.y / half_extents.y
	return sqrt(px * px + pz * pz)


func _flatten_near_safe_points(world: Vector2, height: float) -> float:
	var flattened := height
	for safe_point in SAFE_POINTS:
		var world_safe_point: Vector2 = safe_point + ZONE_WORLD_OFFSET
		var distance_to_safe := world.distance_to(world_safe_point)
		if distance_to_safe < SAFE_RADIUS:
			var blend := 1.0 - smoothstep(0.0, SAFE_RADIUS, distance_to_safe)
			flattened = lerpf(flattened, 0.0, blend)
	return flattened
