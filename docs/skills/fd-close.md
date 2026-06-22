# /fd-close — Archivar FD y actualizar changelog

## Propósito
Cerrar formalmente un FD completado: archivar el spec, actualizar el índice, y registrar en el changelog.

## Pasos

1. Verificar que el código del FD está mergeado en `main`.
2. Mover el archivo: `docs/features/FD-0XX-*.md` → `docs/features/archive/FD-0XX-*.md`.
3. Actualizar `docs/features/FEATURE_INDEX.md`:
   - Remover de la tabla de features activas.
   - Agregar a la tabla de completados con fecha.
4. Actualizar `CHANGELOG.md`:
   - Si la entrada ya existe en `[Unreleased]`, moverla a la versión actual.
   - Si no existe, agregarla en la categoría correcta (Added/Changed/Fixed).
5. Commit: `chore(FD-0XX): close — <título>`.

## Formato de entrada en CHANGELOG.md

```markdown
### Added
- FD-0XX: Título descriptivo de la feature.
```

Categorías: **Added** (nueva feature), **Changed** (modificación), **Fixed** (bugfix), **Removed** (eliminado).

## Ejemplo

```
/fd-close FD-233

→ Mueve docs/features/FD-233-zerog-inertia-layer.md a archive/
→ Actualiza FEATURE_INDEX.md: FD-233 → Completed 2026-06-22
→ CHANGELOG.md: agrega "FD-233: Capa de inercia newtoniana ZeroGravityController" en Added
→ Commit: chore(FD-233): close — Capa de inercia newtoniana ZeroGravityController
```
