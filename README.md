# Godot 4 Multiplayer template


Template repository with client-server multiplayer ready to go. <br/>
It has: <br/>
\- Third person controller with interpolation on client <br/>
\- Pre-match player nickname configuration <br/>

## Recent Project Changes

- Level scenes were reorganized to reduce ambiguity:
  - `levels/hub/` contains the hub scene and hub interactives
  - `levels/zones/scierie/` contains the scierie scene and its Terrain3D assets/data
  - `levels/zones/verger/` contains the verger scene and its local sub-scenes
  - `levels/zones/finale/` groups breche + reactor and their local sub-scenes
- `ZoneScierie` now uses the `Terrain3D` plugin for terrain rendering and collision.
- The Terrain3D integration lives in:
  - `addons/terrain_3d/`
  - `levels/zones/scierie/zone_scierie.tscn`
  - `levels/zones/scierie/zone_scierie_terrain_material.tres`
  - `levels/zones/scierie/zone_scierie_terrain_assets.tres`
  - `levels/zones/scierie/zone_scierie_terrain_data/`
- The scierie terrain runtime also depends on `environment/terrain3d_runtime.gd`.
- Terrain edits must be done in `levels/zones/scierie/zone_scierie.tscn`, not in `main/main.tscn`.
- Two helper scripts were added for this workflow:
  - `tools/generate_zone_scierie_terrain.gd`
  - `tools/backup_zone_scierie_terrain.gd`
- The scierie currently stays visually driven by Terrain3D only; avoid local water planes or fixed overlay shore meshes there because they can visually cover enemies, terrain, and editor texture feedback.

## Editor Notes

- `main/main.tscn` should keep `ZoneScierie` as a clean instance without child overrides.
- Hub editing now starts from `levels/hub/hub_level.tscn`, not a root-level `levels/hub_level.tscn`.
- If Godot crashes while editing Terrain3D, reopen `zone_scierie.tscn` directly before checking `main/main.tscn`.
- The project currently uses a compiled Godot `4.7` local build at `/dataSSD/godot/bin/godot.linuxbsd.editor.x86_64`; Terrain3D editor stability should be validated carefully after terrain edits.

## Test Notes

- This repository's installed GUT CLI does not support `-gfilter`.
- Use `-gselect` to target a script and `-gunit_test_name` to target a specific test name.
- Example:
  - `... gut_cmdln.gd -gdir=test -ginclude_subdirs -gselect=test_ui_e2e.gd -gunit_test_name=test_ui_e2e_cube_mission -gexit`

## Release itch.io

Playable release builds are generated with:

```bash
scripts/release_itch.sh --export-only
```

The default target is Linux using the `MultiRobot` export preset and the local Godot 4.7 binary.
The script runs the full GUT suite before exporting unless `--skip-tests` is passed.

To publish with itch.io butler:

```bash
ITCH_TARGET=user/game scripts/release_itch.sh --publish --version 0.1.0
```

Useful options:

- `--target linux|windows`
- `--preset "Windows Desktop"`
- `--channel linux|windows`
- `--hidden` for the first upload of a hidden itch channel
- `--dry-run` to print commands without exporting or publishing

The build output goes to `build/itch/`, which is intentionally ignored by Git.

## Screenshots

<img src="screenshots\hub.png" width="500"> <br/> <br/>
<img src="screenshots\editor.png" width="500"> <br/> <br/>

[player/player.gd](player/player.gd)

<img src="screenshots\interpolation.png" width="500"> <br/> <br/>

## Credits

* Platformer Kit (2.2) - https://www.kenney.nl (CC0)
* RoboBlast: Third-Person Shooter demo - https://github.com/gdquest-demos/godot-4-3d-third-person-controller (MIT and CC-By 4.0)
