# FD-180: Update system — binary+pack when project.godot changes

## Problem
The current update system downloads only a new `.pck` file. But when `project.godot` changes (input actions, config_version, project settings), the running binary (`odisea.arm64` / `odisea.wasm`) is incompatible with the new `.pck`. Godot 3 validates the pck against the binary — they must match versions.

On HTML5 this is less of an issue because the whole page reloads with new WebAssembly. But on desktop (Linux ARM64/x86_64, Windows, macOS), the binary stays on disk while the pck gets replaced → broken game.

## Goal
The update system must detect when `project.godot` changes and deliver a new binary alongside the new pck.

## Detection: hash of project.godot

The bridge/update server computes a SHA256 hash of `project.godot` from the repo at build time. This hash is included in the update manifest (metadata.json) served to clients.

**Client logic:**
1. Download update manifest (contains: pck_url, binary_url?, pck_hash, binary_hash?, project_godot_hash, version).
2. Compare `project_godot_hash` from manifest against locally computed hash of the current `project.godot`.
3. If hashes differ → binary update needed.
4. If hashes match → pck-only update (current behavior).

The local hash computation must be deterministic: read `project.godot` from the running binary's install directory, compute SHA256, compare.

## Binary delivery: bsdiff with full fallback

**Primary method — bsdiff patch:**
- The server stores a bsdiff patch (binary diff) between the last known binary and the new binary.
- The client downloads the patch (much smaller than full binary, typically 1-5 MB instead of 40 MB).
- Client applies bsdiff locally: `bspatch old_binary new_binary patch_file`.
- Verify SHA256 of the resulting binary against `binary_hash` from the manifest.

**Fallback — full binary download:**
- If bsdiff fails (wrong base binary, corrupt patch, missing `bspatch` binary), download the full binary.
- Verify SHA256 of the downloaded binary.
- Replace the old binary atomically (write to temp, rename).

**Why bsdiff:**
- Binaries change little between releases (same Godot engine, only project script changes).
- bsdiff patches are typically 1-5 MB vs 40 MB full binary.
- `bspatch` is a single C binary (~50 KB) that can be bundled with the game or downloaded once.
- If the base binary is unknown (fresh install), always download full binary.

## Delivery on each platform

### Linux ARM64/x86_64
- Binary: `odisea.arm64` / `odisea.x86_64`
- Update script replaces binary and pck, then restarts the game.
- **After binary update, the OS must exec the new binary.** On Linux: write new binary, `chmod +x`, then `exec("./odisea.arm64")`.
- Data directory: `~/.local/share/Odisea/` or alongside the binary (same as pck).

### Windows
- Binary: `odisea.exe`
- Windows locks the running executable. Solution: write update to a temp `.exe.new`, then launch a small updater stub that waits for the main process to exit, renames `.exe.new` → `.exe`, and relaunches.
- Or: use a batch script/launcher that handles the swap.

### macOS
- Binary inside `.app` bundle: `Odisea.app/Contents/MacOS/odisea`
- Same lock issue as Windows. Use a helper script or launchd trick.

### HTML5
- No binary update needed — page reload loads new `.wasm`.
- The update system currently doesn't apply to HTML5 (the server serves the latest build). Document that this FD is desktop-only.

## Integrity verification

**Before replacing:**
1. Download patch or full binary to a temp file.
2. Compute SHA256 of the temp file.
3. Compare against `binary_hash` from manifest.
4. Only if match → proceed with replacement.

**After replacement** (optional sanity check):
1. Launch the new binary with `--version` or `--check-pck` flag.
2. If it exits with error → rollback to previous binary + pck.

## Rollback strategy

Keep the previous binary and pck in a backup directory (`~/.local/share/Odisea/backup/`). If the new binary fails to start within 10 seconds, the launcher/updater restores from backup.

## Manifest schema (update to metadata.json)

Current:
```json
{
  "version": "1.2.3",
  "pck_url": "https://updates.odisea.game/v1.2.3/game.pck",
  "pck_hash": "sha256:abc123..."
}
```

New:
```json
{
  "version": "1.2.3",
  "project_godot_hash": "sha256:def456...",
  "pck_url": "https://updates.odisea.game/v1.2.3/game.pck",
  "pck_hash": "sha256:abc123...",
  "binary_patch_url": "https://updates.odisea.game/v1.2.3/odisea-arm64.bsdiff",
  "binary_full_url": "https://updates.odisea.game/v1.2.3/odisea.arm64",
  "binary_hash": "sha256:789ghi...",
  "binary_platform": "linux_arm64"
}
```

`binary_patch_url` is optional — if absent, always download full binary.
`binary_full_url` is always present.
`binary_hash` is the SHA256 of the final binary (post-patch or downloaded full).

## Server-side changes

The build pipeline must:
1. Compute SHA256 of `project.godot` from the repo.
2. Store the PREVIOUS binary for diffing.
3. Generate bsdiff patch: `bsdiff previous_binary new_binary patch.bsdiff`.
4. Upload patch + full binary + updated manifest.

If there is no previous binary (first release with this system), skip patch generation.

## Client-side changes

### New module: core_v2/update/UpdateManagerV2.gd
- Extends or replaces the existing update logic.
- Downloads manifest, checks `project_godot_hash`.
- If binary needed, tries bsdiff then falls back to full download.
- Verifies checksums.
- Applies binary atomically.
- Handles platform-specific binary paths.

### Helper binary: bspatch
- Bundled in `core_v2/update/native/bspatch` (compiled for each platform).
- Called via `OS.execute()` from GDScript.
- If missing, skip bsdiff and go straight to full download.

### Updater stub (Windows/macOS)
- Small C or Rust program that waits for main process, swaps binary, relaunches.
- Bundled in the update system.

## Test plan

1. **Same project.godot**: manifest has same hash → pck-only update (should work as before).
2. **Changed project.godot, bsdiff works**: download patch, apply, verify checksum, replace binary, restart.
3. **Changed project.godot, bsdiff fails (corrupt patch)**: fallback to full binary download.
4. **Changed project.godot, no previous binary (fresh install)**: download full binary.
5. **Binary checksum mismatch**: reject update, log error, keep old version.
6. **Rollback**: new binary fails to start → restore old binary + old pck from backup.

## Out of scope
- Differential updates for HTML5 (page reload handles it).
- Delta patching for pck (pck is replaced wholesale).
- Multi-platform simultaneous updates (each platform has its own manifest/binary).
- GUI progress bar (current update system has no UI, just silent download — keep it that way).
