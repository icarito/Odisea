# /fd-new — Crear nuevo Feature Design

## Propósito
Crear un nuevo FD (Feature Design) numerado secuencialmente a partir de una idea o problema.

## Pasos

1. Leer `docs/features/FEATURE_INDEX.md` para determinar el siguiente número FD disponible.
2. Usar `docs/features/TEMPLATE.md` como plantilla.
3. Crear `docs/features/FD-0XX-slug.md` con:
   - **Status:** Design
   - **Priority:** [High/Medium/Low]
   - **Effort:** [Small/Medium/Large]
   - **Problem**: descripción clara del problema o necesidad
   - **Solution**: enfoque propuesto, opciones consideradas
   - **Files to Modify**: lista de archivos (nuevos y existentes)
   - **Verification**: pasos para verificar la feature
   - **Out of scope**: lo que explícitamente NO se incluye
4. Agregar entrada en `FEATURE_INDEX.md` en la tabla de features activas.
5. Commit: `docs(FD-0XX): <título>`.

## Contexto adicional
- Los FDs viven en `docs/features/` y se archivan a `docs/features/archive/` al cerrarse.
- Todo commit de implementación referencia su FD: `feat(FD-0XX): descripción`.
- El ciclo de vida: Design → Open → In Progress → Complete.
