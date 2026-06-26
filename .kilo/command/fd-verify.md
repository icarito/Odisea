---
description: Verificar implementación de un FD contra su spec, detectar bugs y preparar para merge
---

# /fd-verify — Verificar implementación

Fuente canonica compartida: `docs/skills/fd-verify.md`.

## Propósito
Revisar el código implementado contra el spec del FD, detectar bugs, y preparar para merge.

## Pasos

1. Leer el FD spec (`docs/features/FD-0XX-*.md`) y comparar contra los archivos modificados.
2. Revisar el diff completo:
   - ¿Cubre todos los puntos del spec?
   - ¿Rompe algo fuera del scope?
   - ¿Hay dead code, duplicación, o anti-patrones?
   - ¿Sigue las convenciones del proyecto (Godot 3, GDScript 1.x, señales, composición)?
3. Ejecutar la sección **Verification** del FD punto por punto.
4. Si hay tests, correrlos.
5. Reportar hallazgos en el PR o como comentarios inline.

## Reglas para el agente implementador
- Si el código no compila o rompe CI, corregir antes de pedir review.
- Si hay decisiones de diseño no cubiertas en el spec, preguntar (no inventar).
- Commits atómicos: un commit por archivo o por cambio lógico.
- Formato de commit: `feat(FD-0XX): descripción` o `fix(FD-0XX): descripción`.

## Output esperado
- PR abierto con descripción clara de cambios.
- Checklist de verificación completado.
- Notas de cualquier edge case o limitación conocida.
