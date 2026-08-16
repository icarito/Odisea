# Odisea Shared Skills

Este directorio contiene workflows canonicos compartidos por agentes. Si una herramienta necesita
su propio formato, debe crear un adaptador que enlace aca.

Indice general: `docs/agents/skills-index.md`.

## Workflows

- `fd-explore.md`: cargar contexto del proyecto.
- `fd-new.md`: crear un Feature Design numerado.
- `fd-status.md`: mostrar estado de features.
- `fd-verify.md`: verificar implementacion contra spec.
- `fd-close.md`: archivar FD completado y actualizar changelog.
- `enrich.md`: enriquecer un FD hasta dejarlo ejecutable (assets, riesgos, plan de tareas).
- `deliver.md`: ejecutar el plan (subagentes Sonnet + Jules + checkpoints en vivo).
- `jules.md`: delegar tareas asincronas a Jules con `bin/jules-cli`.

Ciclo completo: `fd-new` → `enrich` → `deliver` → `fd-verify` → `fd-close`.

## Regla de mantenimiento

No duplicar instrucciones largas en `.kilo/command/`, `.claude/skills/` u otros shims. Actualizar
este directorio y luego ajustar los adaptadores minimos.

