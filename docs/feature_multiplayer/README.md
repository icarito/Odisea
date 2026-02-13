# Multiplayer (Split-Screen) — Estado (2026-01-07)

## Estado
- Requiere reimplementación tras el refactor core.
- Documentos relacionados:
  - odisea_splitscreen_plan.md
  - odisea_splitscreen_code.md
  - odisea_splitscreen_exe.md

## Próximos pasos
- Integrar múltiples `InputProvider` con `device_id`.
- Extender `SessionManager` para gestionar sesiones multi-jugador locales.
- Asegurar determinismo en replays locales (cada jugador en `replay_sync`).
- Escribir tests en `core/tests` para validar interacción multi-jugador.
