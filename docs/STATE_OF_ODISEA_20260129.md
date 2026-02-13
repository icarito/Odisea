# STATE_OF_ODISEA_20260129.md

## Estado general (29 de enero de 2026)

- Proyecto Odisea migrado a estructura modular en `core` (componentes, sistemas, player_controller, UI, autoloads, simulación, utilidades, tests).
- Features fundacionales implementadas y documentadas en `docs/canon/` (OdysseyScript, interactuables, PushableBox, gamefeel, sidescroller, test battery, test runner, etc).
- Features legacy y descartadas archivadas en `docs/archived/`.
- Contratos de determinismo, snapshot y normas de trabajo centralizados en `AGENTS.md`.
- Limpieza de assets, scripts y autoloads legacy completada.
- Validación de determinismo y replays con GdUnit3 y test battery automatizada.
- Documentación y referencias actualizadas en README.md, TODO.md y DONE.md.

## Pendientes principales
- Reimplementar BGM mínimo (`autoload/AudioManager.gd` en Menu y criogenia)
- Reimplementar Kill/Respawn + Checkpoints (`KillZone.tscn`, `Checkpoint.tscn`, lógica de respawn)
- Reimplementar WindZone (scenes/common)
- Reimplementar multiplayer split-screen (core)
- Plataformas con barandas, tubos conectores, objetivo de alto contraste, spawn cinematográfico, obstáculos ambientales, drones, ventanal final, diálogos IA, integración de "Cargol" (ver TODO.md)

## QA y balance
- Pruebas de apilado de cajas y respawn en checkpoints
- Validar entregables del MVP en `Criogenia.tscn`
- Medir cobertura y limpiar pendientes menores

## Referencias
- Estructura y normas: ver `README.md` y `AGENTS.md`.
- Features implementados: ver `docs/canon/`.
- Capas de colisión y detalles técnicos: ver TODO.md
