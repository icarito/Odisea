# TrenchBroom Configuration

`Qodot.fgd` at the repository root is the canonical entity definition file for
Odisea's TrenchBroom setup.

The local TrenchBroom game folder should not keep an independent copy of this
file. Use the repo-managed symlink instead:

```bash
scripts/link_trenchbroom_fgd.sh
```

This links both known local locations to the repo file:

```text
~/.TrenchBroom/games/Odisea/Qodot.fgd
~/.TrenchBroom/games/Odisea/Odisea/Qodot.fgd
```

If either target is a regular file, the script creates a timestamped backup
before replacing it with a symlink.

After changing `Qodot.fgd`, reload TrenchBroom entity definitions with
`File > Reload Entity Definitions` or restart TrenchBroom.

## Native Editor Types

The FGD exporter emits any property named `angle` as `angle(angle)`, so
TrenchBroom can use its native yaw/rotation UI for point props instead of a
plain numeric field.

For light colors, prefer TrenchBroom's native `_color(color255)` property when a
prop needs an editor-visible color picker.

## Emergency Beacon

`light_emergency_beacon` uses TrenchBroom-native editor types where possible:

- `angle(angle)` for the native yaw/rotation control.
- `_color(color255)` for the native color picker.

`light_color` and `beacon_color` remain available as compatibility aliases for
existing maps, but new maps should prefer `_color`.
