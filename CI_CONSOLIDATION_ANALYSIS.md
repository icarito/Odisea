# CI Consolidation Analysis — `.github/workflows/`

**Fecha:** 2026-11-13  
**Workflows analizados:** 7 (asset_integrity, determinism_tests, pytest_runner, stress_performance, export_all, export_platform, testflight_promote)

---

## Resumen Ejecutivo

| Workflow | Líneas | Trigger Principal | Propósito |
|----------|--------|-------------------|-----------|
| `asset_integrity.yml` | 138 | push/PR (asset paths) | **Full clean rebuild** import + smoke |
| `determinism_tests.yml` | 184 | nightly + push/PR (core_v2) | Determinismo en **single Godot process** |
| `pytest_runner.yml` | 407 | push/PR (code) | **Main CI gate** — sharded 8 ways, dispatch export |
| `stress_performance.yml` | 302 | nightly + dispatch | Stress + Box3D workers benchmark + regression |
| `export_all.yml` | ~1000 | workflow_dispatch (from pytest_runner) | Multi-platform export + publish |
| `export_platform.yml` | ~1100 | workflow_call | Reusable single-platform export body |
| `testflight_promote.yml` | 42 | schedule (30min) | Promote approved TestFlight builds |

---

## Duplicaciones Identificadas

### 1. Setup Godot Binary (idéntico en 6/7 workflows)
```yaml
# Repetido en: asset_integrity, determinism_tests, pytest_runner, 
# stress_performance, export_all (prep), export_platform
BOX3D_RELEASE="$(cat .github/box3d_release)"
curl -fSL -o "$TARGET_BIN" "https://github.com/icarito/godot-box3d-3/releases/download/${BOX3D_RELEASE}/godot.box3d.linux.x86_64.headless"
sudo install -m 755 "$TARGET_BIN" /usr/local/bin/godot
```

### 2. Python Venv + Pytest Install (idéntico en 4/7)
```yaml
# Repetido en: determinism_tests, pytest_runner, stress_performance (parcial), export_platform (no)
actions/setup-python@v7 + cache + pip install -r requirements-pytest.txt
```

### 3. Validación Import Manifests (4/7 workflows)
```yaml
# Repetido en: asset_integrity, determinism_tests, pytest_runner, stress_performance
python3 scripts/check_tracked_imports.py
python3 scripts/check_critical_import_artifacts.py
```

### 4. Import + Smoke (4/7 workflows con variantes)
| Workflow | `--clean-cache` | `--import-mode` | Script Smoke |
|----------|-----------------|-----------------|--------------|
| asset_integrity | `1` (FULL) | `quick` | `ci_resource_smoke_asset_integrity.gd` |
| determinism_tests | `0` (self-healing) | `auto` | `ci_resource_smoke.gd` (implícito) |
| pytest_runner | `0` (self-healing) | `auto` | `ci_resource_smoke.gd` |
| stress_performance | `0` (self-healing) | `auto` | `ci_resource_smoke.gd` |

### 5. Cache Keys `.import` (ligeramente diferentes)
- `asset_integrity`: hashea **todo** (assets, textures, models, .import/**, etc.)
- `determinism_tests` / `stress_performance`: solo `project.godot` + `*.import` (estable)
- `pytest_runner`: hashea todo + `assets/**` + `textures/**` + `models/**`...
- `export_platform`: **por plataforma** con hash VRAM formats (correcto)

---

## Oportunidades de Consolidación

### 🔴 Alta Prioridad: Extraer Setup Común a Reusable Workflow

**Crear:** `.github/workflows/_setup_godot.yml` (workflow_call)
```yaml
# Inputs: box3d_release_path, cache_key_suffix
# Outputs: godot_bin_path, cache_hit_status
# Steps: checkout → cache godot binary → download/install Box3D → cache .import (opcional)
```

**Beneficio:** ~150 líneas eliminadas × 5 workflows = **~750 líneas menos**, single source of truth.

### 🟡 Media Prioridad: Unificar Validación Imports

**Crear:** `.github/workflows/_validate_imports.yml` (workflow_call)
```yaml
# Steps: check_tracked_imports.py + check_critical_import_artifacts.py
# Opcional: check_import_artifacts_present.py (para PRs con base commit)
```

**Beneficio:** Elimina duplicación en 4 workflows; añade consistencia.

### 🟡 Media Prioridad: Unificar Import + Smoke

**Crear:** `.github/workflows/_import_smoke.yml` (workflow_call)
```yaml
# Inputs: clean_cache (bool), import_mode, smoke_script, timeout_import, timeout_smoke
# Usa scripts/godot_import_smoke.sh con parámetros
```

**Diferencia clave:** `asset_integrity` usa `--clean-cache 1` (full rebuild); los demás `0` (self-healing). **Mantener como parámetro.**

### 🟢 Baja Prioridad: Merge `asset_integrity` → `pytest_runner`

**Rationale:** `asset_integrity` solo corre en asset paths; `pytest_runner` ya corre en code paths. Podría ser un **job condicional** en `pytest_runner`:
```yaml
job asset-integrity:
  if: github.event_name == 'push' && contains(github.event.commits[0].modified_files, 'assets/') || ...
  needs: [preflight-checks]  # setup godot, validate imports
  uses: ./.github/workflows/_import_smoke.yml
  with:
    clean_cache: true
    import_mode: quick
```

**Trade-off:** `asset_integrity` tiene concurrency propia y timeout 30min. Si se mergea, hereda concurrency de `pytest_runner` (puede cancelar builds reales). **Mejor mantener separado pero reutilizando _setup_godot + _validate_imports + _import_smoke.**

### 🟢 Baja Prioridad: `determinism_tests` como job en `pytest_runner`

**Rationale:** Diferente runner model (single Godot process vs 8 shards). El schedule (nightly 2AM) es distinto. **Mantener separado** pero reutilizar setup común.

### 🟢 Baja Prioridad: `stress_performance` comparte setup

Ya usa cache key estable (`project.godot` + `*.import`). Reutilizaría `_setup_godot` + `_validate_imports`.

---

## Propuesta de Arquitectura Final

```
.github/workflows/
├── _setup_godot.yml           # NEW: reusable - Godot binary + cache
├── _validate_imports.yml      # NEW: reusable - check_tracked + check_critical
├── _import_smoke.yml          # NEW: reusable - godot_import_smoke.sh paramétrico
├── pytest_runner.yml          # MAIN GATE - code changes, sharded tests, dispatch export
├── asset_integrity.yml        # KEEP: full clean rebuild on asset changes (uses _setup + _validate + _import_smoke)
├── determinism_tests.yml      # KEEP: nightly + code changes, single process (uses _setup + _validate + _import_smoke)
├── stress_performance.yml     # KEEP: nightly stress + benchmark (uses _setup + _validate + _import_smoke)
├── export_all.yml             # KEEP: dispatched by pytest_runner (uses _setup via export_platform)
├── export_platform.yml        # KEEP: reusable export body (uses _setup_godot internally)
└── testflight_promote.yml     # KEEP: independent schedule (no Godot needed)
```

---

## Estimación de Impacto

| Métrica | Actual | Post-Consolidación | Delta |
|---------|--------|-------------------|-------|
| Líneas totales | ~2175 | ~1400 | **-35%** |
| Duplicación setup Godot | 6× | 1× (shared) | -83% |
| Duplicación validate imports | 4× | 1× (shared) | -75% |
| Duplicación import smoke | 4× | 1× (shared) | -75% |
| Puntos de fallo setup | 6 | 1 | -83% |
| Tiempo mantenimiento cambio setup | 6 edits | 1 edit | -83% |

---

## Riesgos / Consideraciones

1. **`export_platform.yml` ya es reusable** — no tocar su estructura interna; solo hacer que use `_setup_godot.yml` para la parte de binary/cache.

2. **Concurrency groups** — `asset_integrity` y `determinism_tests` tienen grupos propios. Al usar reusable workflows, **el caller controla concurrency**. No cambiar groups existentes.

3. **Cache keys** — `_setup_godot.yml` debe aceptar `cache_key_suffix` input para que cada workflow mantenga su key aislada (asset_integrity incluye assets, determinism no, etc.).

4. **`asset_integrity` full clean rebuild** — es intencional (valida que los manifests trackeados sean completos). Mantener `--clean-cache 1` como parámetro.

5. **`determinism_tests` single process** — arquitectura distinta a pytest_runner (8 shards). No mergear jobs.

6. **Secrets** — `_setup_godot` no necesita secrets. `_import_smoke` tampoco. `export_platform` sí (keystore, certs). Mantener separation of concerns.

---

## Próximos Pasos

1. **Crear `_setup_godot.yml`** — extraer steps 64-95 de `asset_integrity.yml` (checkout + cache binary + install)
2. **Crear `_validate_imports.yml`** — extraer steps 97-105
3. **Crear `_import_smoke.yml`** — parametrizar `godot_import_smoke.sh` call
4. **Refactor `asset_integrity.yml`** — usar 3 reusable workflows
5. **Refactor `determinism_tests.yml`** — usar 3 reusable workflows
6. **Refactor `stress_performance.yml`** — usar 3 reusable workflows
7. **Refactor `export_platform.yml`** — usar `_setup_godot.yml` para binary install
8. **Test:** push a branch, verificar que todos los workflows pasan

---

## Archivos a Crear/Modificar

| Acción | Archivo |
|--------|---------|
| CREATE | `.github/workflows/_setup_godot.yml` |
| CREATE | `.github/workflows/_validate_imports.yml` |
| CREATE | `.github/workflows/_import_smoke.yml` |
| MODIFY | `.github/workflows/asset_integrity.yml` |
| MODIFY | `.github/workflows/determinism_tests.yml` |
| MODIFY | `.github/workflows/stress_performance.yml` |
| MODIFY | `.github/workflows/export_platform.yml` |
| KEEP   | `.github/workflows/pytest_runner.yml` (ya dispatcher principal) |
| KEEP   | `.github/workflows/export_all.yml` |
| KEEP   | `.github/workflows/testflight_promote.yml` |