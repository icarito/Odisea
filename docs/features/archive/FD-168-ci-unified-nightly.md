# FD-168: CI/CD Unificado — Matrix Multiplataforma + Nightly Releases

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-06-12
**Completed:** -

## Problem

Actualmente hay 3 workflows de export separados:
- `export_all.yml` → linux_x64, linux_arm64, windows, iOS
- `export_android.yml` → Android APK con contenedor godot-ci
- `export_web.yml` → HTML5 + Netlify + Pages

Esto duplica lógica de setup, versionado y release. Cada workflow hace su propio release por separado con tags distintos. No hay un nightly unificado que produzca todos los artefactos en un solo release.

Además, los builds no inyectan metadata que permita al bridge distinguir builds oficiales de forks: el token del bridge está hardcodeado en `odisea_central.py` o se pasa por variables de entorno manuales, y HTML5 no recibe `commit`, `build_id`, ni `build_channel`.

## Solution

### A. Unificar matriz de export

Un solo `export_all.yml` con job `prep` común + matrix que incluya **todos** los targets:

| Platform | OS | Preset | Container |
|---|---|---|---|
| linux_x64 | ubuntu-latest | Linux/X11 x86_64 | — |
| linux_arm64 | ubuntu-latest | Linux/X11 ARM64 | — |
| windows | ubuntu-latest | Windows Desktop | — |
| android | ubuntu-latest | Android | barichello/godot-ci:3.6.2 |
| html5 | ubuntu-latest | HTML5 Threads | — |
| ios | macos-latest | iOS | — |

### B. Nightly pre-release mutable

- **Trigger:** push a `main`
- **Tag:** `nightly` (se sobreescribe en cada push)
- **Release title:** "Nightly Tip"
- **Comportamiento:** borrar assets existentes del release `nightly` y reemplazarlos con los nuevos artefactos
- **Body del release:** commit SHA, timestamp, lista de artefactos con tamaños

### C. Metadata inyectada en builds

Variables inyectadas en tiempo de build (vía `env` + Godot `script` o `build_meta.js`):

| Variable | Origen | Uso |
|---|---|---|
| `ODISEA_BUILD_CHANNEL` | `nightly` | Distinguir canal |
| `ODISEA_GIT_COMMIT` | `${{ github.sha }}` | Trazabilidad |
| `ODISEA_BUILD_ID` | `${{ github.run_id }}` | Trazabilidad |
| `ODISEA_GAME_VERSION` | `0.1.0-nightly+${{ github.sha_short }}` | Versión canónica |
| `ODISEA_BRIDGE_TOKEN` | `${{ secrets.ODISEA_CENTRAL_INGEST_TOKEN }}` | Conexión al bridge |

**HTML5:** generar `build_meta.js` en el paso post-export que declare: `window.ODISEA_BUILD_META = { token, commit, build_id, channel, version, officialHost }`. La shell HTML lo carga antes de iniciar el engine.

**Nativos:** inyectar vía `OS.set_environment()` o script de export que parchee `project.godot` — o más simple: archivo `build_meta.json` empaquetado en el zip.

### D. Host oficial

- HTML5: `ODISEA_OFFICIAL_HOST=odisea.educa.juegos` hardcodeado en el workflow (no es secreto)
- Nativos: `ODISEA_BUILD_CHANNEL=nightly` + token válido como señal de build oficial
- Futuro: firma criptográfica de builds

### E. Secrets en GitHub (no en el repo)

| Secret | Propósito |
|---|---|
| `ODISEA_CENTRAL_INGEST_TOKEN` | Token que el bridge valida para aceptar heartbeats/ghosts |
| `ODISEA_BUILD_SIGNING_KEY` | (futuro) Keystore para firmar APKs release |

**No se commitea ningún token en el repo.**

### F. Estructura del workflow

```
prep (version, sha)
  ↓
export (matrix: linux_x64, linux_arm64, windows, android, html5, ios)
  ├── setup godot + templates
  ├── inject metadata
  ├── export
  ├── post-process (HTML5: gzip + build_meta.js)
  └── upload artifact
  ↓
deploy-web (solo HTML5, condicional)
  ├── Netlify (core: html/js/workers)
  └── Pages (heavy: pck + wasm)
  ↓
nightly-release (solo push a main)
  ├── download all artifacts
  ├── delete old nightly release + tag
  └── create new nightly pre-release
```

### Considered Options

- **GitHub Environments + manual approval para nightly** — Overkill. Nightly es automático, no necesita approval.
- **Tags por timestamp (nightly-20260612-001)** — Mutable es más simple, no llena el repo de tags muertos.
- **Un solo job secuencial en vez de matrix** — Matrix es más rápido (paralelo) y escala mejor.
- **Selected: matrix + mutable nightly** — Mínimo cambio estructural, máximo reaprovechamiento del `export_all.yml` existente.

## Files to Modify

### Modificados
- `.github/workflows/export_all.yml` — Unificar matrix, agregar android+html5, metadata, nightly release

### Eliminados (o desactivados)
- `.github/workflows/export_android.yml` — Reabsorbido en export_all.yml
- `.github/workflows/export_web.yml` — Reabsorbido en export_all.yml

### Nuevos
- `scripts/inject_build_meta.py` — Script que genera `build_meta.js` y `build_meta.json`

### No tocar
- `.github/workflows/tests.yml` — Tests GDScript
- `.github/workflows/pytest_runner.yml` — Tests Python (bridge)
- `.github/workflows/asset_integrity.yml` — Smoke tests de assets
- `.github/workflows/determinism_tests.yml` — Tests de determinismo
- `.github/workflows/stress_performance.yml` — Stress tests
- `odisea_central.py` — Backend del bridge
- `dashboard/` — Frontend
- `project.godot` — Config del engine
- `export_presets.cfg` — Presets de export (ya configurados)
- Cualquier `.gd`, `.tscn`, `.tres`

## Verification

1. Push a `main` → el workflow dispara, matrix completa sin errores
2. Release `nightly` aparece en GitHub con artefactos de las 6 plataformas
3. Push subsecuente → release `nightly` se actualiza (mismo tag, nuevos assets)
4. HTML5: `build_meta.js` contiene `token`, `commit`, `build_id`, `channel`, `officialHost`
5. Android: APK debug se genera y se incluye en el nightly
6. `ODISEA_CENTRAL_INGEST_TOKEN` existe como secret en GitHub, no aparece en el repo
7. Workflow dispatch manual funciona (por si se necesita forzar un build)
