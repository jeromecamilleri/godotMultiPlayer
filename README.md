# Godot 4 Multiplayer template


Template repository with client-server multiplayer and voice chat ready to go. <br/>
It has: <br/>
\- Third person controller with interpolation on client <br/>
\- Voice over with 3d positioning <br/>
\- UI for changing names and tweaking voice volume <br/>

## Recent Project Changes

- `ZoneScierie` now uses the `Terrain3D` plugin for terrain rendering and collision.
- The Terrain3D integration lives in:
  - `addons/terrain_3d/`
  - `levels/zones/zone_scierie.tscn`
  - `levels/zones/zone_scierie_terrain_material.tres`
  - `levels/zones/zone_scierie_terrain_assets.tres`
  - `levels/zones/zone_scierie_terrain_data/`
- The scierie terrain runtime also depends on `environment/terrain3d_runtime.gd`.
- Terrain edits must be done in `levels/zones/zone_scierie.tscn`, not in `main/main.tscn`.
- Two helper scripts were added for this workflow:
  - `tools/generate_zone_scierie_terrain.gd`
  - `tools/backup_zone_scierie_terrain.gd`

## Editor Notes

- `main/main.tscn` should keep `ZoneScierie` as a clean instance without child overrides.
- If Godot crashes while editing Terrain3D, reopen `zone_scierie.tscn` directly before checking `main/main.tscn`.
- The project currently uses Godot `4.6.2` locally; Terrain3D editor stability should be validated carefully after terrain edits.

## Test Notes

- This repository's installed GUT CLI does not support `-gfilter`.
- Use `-gselect` to target a script and `-gunit_test_name` to target a specific test name.
- Example:
  - `... gut_cmdln.gd -gdir=test -ginclude_subdirs -gselect=test_ui_e2e.gd -gunit_test_name=test_ui_e2e_cube_mission -gexit`

## Screenshots

<img src="screenshots\hub.png" width="500"> <br/> <br/>
<img src="screenshots\editor.png" width="500"> <br/> <br/>

[player/player.gd](player/player.gd)

<img src="screenshots\interpolation.png" width="500"> <br/> <br/>

## Credits

* Platformer Kit (2.2) - https://www.kenney.nl (CC0)
* VoIP extension for Godot 4 - https://github.com/goatchurchprime/two-voip-godot-4 (MIT)
* RoboBlast: Third-Person Shooter demo - https://github.com/gdquest-demos/godot-4-3d-third-person-controller (MIT and CC-By 4.0)
