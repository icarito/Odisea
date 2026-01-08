
# DONE — Odisea MVP Acto I (2026)

## Estado tras limpieza y refactor

- Eliminados todos los archivos legacy, tests antiguos y autoloads no usados por core_v2.
- Validado determinismo y funcionamiento base con `./runtest.sh -a ./core_v2/tests/test_determinism_v2.gd` (OK).
- Solo permanecen autoloads y scripts activos requeridos por core_v2 y MVP.
- Proyecto listo para avanzar en features y QA según el nuevo TODO.

## Funcionalidades y sistemas integrados

- Menú, UI y efectos visuales principales.
- Optimizaciones de FPS y housekeeping inicial.
- **Conveyor y Moving Platform Refactor (V2)**:
  - Reimplementación determinista de cintas transportadoras (`Conveyor.gd`) con shaders sincronizados.
  - Fix de regresión en plataformas móviles (`MovingPlatformV2.gd`) — el jugador ahora se mantiene sobre la plataforma sin deslizarse.
  - Validación completa con test de determinismo: PASS (drift < 0.00001).

## Próximos pasos

- Seguir con limpieza de assets y scripts no referenciados.
- Avanzar con features y QA según el nuevo TODO.
- Test para conveyor