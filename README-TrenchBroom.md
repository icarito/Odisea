# TrenchBroom Integration for Odisea

Welcome! We are using [TrenchBroom](https://trenchbroom.github.io/) as our primary level editor for Odisea along with [Qodot](https://qodotplugin.github.io/) to bridge it into Godot.

## Initial Setup

1. Make sure you have TrenchBroom installed on your system.
2. In the Godot Editor, look for the `addons/qodot/game_definitions/trenchbroom/trenchbroom_game_config.tres`.
3. Open it and modify the `trenchbroom_games_folder` line to point to the `games` folder of your TrenchBroom installation (e.g. `~/.TrenchBroom/games/` on Linux or `C:/Users/<Username>/AppData/Roaming/TrenchBroom/games` on Windows).
4. Click on the "Export File" checkbox. This automatically exports `Qodot.fgd`, `GameConfig.cfg`, and the icon to TrenchBroom!
5. Open TrenchBroom -> Open `Odisea` from the games list.

## Adding Props to the Map
We are using **FGD Point Classes** to expose Godot Prefabs/Things inside TrenchBroom.  
When in TrenchBroom, use the `Entity Browser` to search for:
* `prop_lever`
* `prop_door_iris`
* `prop_door_vertical`
* `light_ceiling`
* `light_flickering`

To use them, right-click any point in space, insert the entity, and Godot will automatically instance the `tscn` for you upon building the map with Qodot. You can manage rotation properties explicitly if the FGD supports it.

## Using Special Materials (E.g Glass)
TrenchBroom displays materials directly from your mapped textures folder.
If you apply a texture like `glass.png` to a brush in TrenchBroom, when built in Godot, Qodot will look for `glass.tres`. 

To make it look like actual glass:
1. Ensure your Godot material (`glass.tres`) has `Transparent` checked.
2. Qodot will automatically match the material string with the resources present in its materials directory.
