# FD-238 — Mejoras al sistema FD: skills compartidos, cierre automático, changelog

**Status:** Design
**Priority:** Medium
**Effort:** Small
**Created:** 2026-06-22

## Problema

El sistema FD actual (inspirado en [Manuel Schipper — Parallel Coding Agents](https://schipper.ai/posts/parallel-coding-agents/)) tiene gaps respecto al artículo original:

1. **Skills en `.claude/` solamente** — Jules y otros agentes no pueden accederlas. Deberían estar en el repo (`docs/skills/` o `.agents/skills/`) para que cualquier agente (Claude, Jules, etc.) las use.

2. **Sin `/fd-close`** — cuando un FD se completa, mergeamos el PR pero el FD queda en `docs/features/` sin archivar. Falta moverlo a `docs/features/archive/`, actualizar `FEATURE_INDEX.md`, y registrar en `CHANGELOG.md`.

3. **Sin `CHANGELOG.md`** — no hay registro automático de FDs completados. Schipper lo genera incrementalmente.

4. **Sin `/fd-explore`** — Jules arranca desde cero cada sesión. Cargar contexto (arquitectura, dev guide, FDs activos) al iniciar reduciría tiempo de ramp-up.

## Solución

### 1. Skills compartidos en el repo

Mover las skills de `.claude/commands/` a `docs/skills/` dentro del repo:

```
docs/skills/
├── fd-new.md       # Crear nuevo FD desde idea
├── fd-status.md    # Ver índice de FDs activos
├── fd-explore.md   # Cargar contexto del proyecto
├── fd-verify.md    # Verificar implementación
└── fd-close.md     # Archivar FD + actualizar changelog
```

Cada skill es un `.md` que describe el comando, sus pasos, y qué archivos toca. Los agentes lo leen como instrucción.

### 2. `/fd-close` — cierre formal de FD

Skill que al invocarse:
- Mueve `docs/features/FD-0XX-*.md` → `docs/features/archive/`
- Actualiza `FEATURE_INDEX.md`: mueve de "Active" a "Completed" con fecha
- Agrega entrada en `CHANGELOG.md` con formato Keep a Changelog
- Commitea con mensaje `chore(FD-0XX): close — <título>`

### 3. `CHANGELOG.md` automático

Formato Keep a Changelog (https://keepachangelog.com/):

```markdown
# Changelog — Odisea

## [Unreleased]
### Added
- FD-238: Mejoras al sistema FD

## [0.3.2] — 2026-06-22
### Added
- FD-233: Capa de inercia newtoniana ZeroGravityController
- FD-234: Escape abre menú + versión/fecha en boot y menú
### Fixed
- FD-232: Reparar FireEmitter + EmergencyBeaconV2
### Changed
- FD-235: Performance pass LOD + instrumentación
```

Se actualiza automáticamente con `/fd-close`.

### 4. `/fd-explore` para Jules

Skill que carga en una sesión nueva:
- `docs/architecture.md` o equivalente (resumen de arquitectura)
- `FEATURE_INDEX.md` (FDs activos)
- `CHANGELOG.md` (últimos cambios)
- `AGENTS.md` del repo (convenciones del proyecto)

Jules arranca con contexto en vez de desde cero.

## Files to Modify

| Archivo | Acción |
|---------|--------|
| `docs/skills/fd-new.md` | Nuevo — crear FD desde idea |
| `docs/skills/fd-status.md` | Nuevo — índice de FDs |
| `docs/skills/fd-explore.md` | Nuevo — carga de contexto |
| `docs/skills/fd-verify.md` | Nuevo — verificación |
| `docs/skills/fd-close.md` | Nuevo — archivar + changelog |
| `CHANGELOG.md` | Nuevo — Keep a Changelog |
| `docs/features/FEATURE_INDEX.md` | Modificar — actualizar con FDs recientes |
| `docs/features/archive/` | Usar — mover FDs completados |
| `.claude/commands/` | Deprecar — mover a `docs/skills/` |

## Verificación

1. `docs/skills/` contiene los 5 skills
2. `/fd-close FD-232` mueve el archivo a archive, actualiza FEATURE_INDEX, agrega entrada en CHANGELOG
3. `CHANGELOG.md` refleja los FDs mergeados esta noche (232, 233, 234, 235)
4. Jules puede leer `docs/skills/fd-explore.md` y cargar contexto

## Out of scope

- No modificar el flujo Jules existente (rama → Jules → PR → merge)
- No migrar skills de OpenClaw (eso es otra capa)
- No implementar `/fd-deep` todavía (4 agentes paralelos requiere infra)
