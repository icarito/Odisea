---
description: Mostrar estado de Features: activas, en progreso, pendientes y completadas
---

# /fd-status — Estado de Features

Fuente canonica compartida: `docs/skills/fd-status.md`.

## Propósito
Mostrar el índice de FDs: qué está activo, en progreso, pendiente de verificación, y completado.

## Pasos

1. Leer `docs/features/FEATURE_INDEX.md`.
2. Mostrar tabla resumen con columnas: FD, Title, Status, Priority, Effort.
3. Agrupar por estado: activos primero, luego completados.
4. Resaltar FDs con status "In Progress" o "Pending Verification".
5. Si hay FDs con status "Planned" sin asignar, sugerir priorización.

## Ejemplo de salida

```
Activos (8):
  FD-050  Scaffold WFC           In Progress  P0  Large
  FD-040  PlateContentStream     Open         P0  Small
  FD-233  ZeroG Inertia          Complete     P0  Medium

Completados recientes:
  FD-232  Fix broken assets      2026-06-22
  FD-231  Main menu and pause    2026-06-21
```
