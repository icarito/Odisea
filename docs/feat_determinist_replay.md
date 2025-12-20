# Plan de Implementación: Test de Validación de Determinismo de Movimiento (TVDM)

## Objetivo
Implementar una suite de tests automatizados para validar que el sistema de movimiento del jugador es determinista bajo secuencias de input idénticas. El test compara la posición y rotación final entre una sesión grabada ("Live Record") y una reproducida ("Replay Playback"), con umbrales de tolerancia estrictos (0.1m para posición, 0.01 radianes para rotación).

## Suite de Inputs de Referencia
Crear `data/test_suite_inputs.json` con secuencias de 120 frames (2 segundos a 60fps) para cada test:

- **T1: Fricción** - Frames 0-30: move_forward, 31-120: Idle
- **T2: Salto** - Frame 10: jump (presión única)
- **T3: Strafe** - Frames 0-120: move_forward + move_right + strafe: True
- **T4: Tank Turn** - Frames 0-60: move_right + strafe: False
- **T5: Mouse Look** - Frames 0-60: mouse_delta.x = 10.0

## Script de Test Principal
Implementar `tests/test_replay_determinism.gd` con el pipeline:

1. **Fase 1: Grabación (Live Run)**
   - Instanciar jugador en (0,0,0)
   - Inyectar inputs al `InputState` en modo RECORD
   - Simular N frames con `_physics_process(1.0/60.0)`
   - Guardar `replays/replay_T[n]_recorded.json`
   - Almacenar posición/rotación final grabada

2. **Fase 2: Reproducción (Playback Run)**
   - Reiniciar escena, instanciar jugador en (0,0,0)
   - Cargar replay grabado
   - Poner `InputState` en modo PLAYBACK
   - Desactivar "Soft-Correction" para medir drift puro
   - Simular mismos N frames
   - Almacenar posición/rotación final reproducida

3. **Fase 3: Verificación**
   - Calcular drift de posición: `final_pos_recorded.distance_to(final_pos_replay) < 0.1`
   - Calcular drift de rotación: `abs(final_rot_recorded - final_rot_replay) < 0.01`
   - Reportar PASS/FAIL por test

## Refactorización del Sistema de Movimiento
Para asegurar determinismo:

1. **FixedPoint.gd**: Extender para cubrir todas las operaciones matemáticas necesarias (vectores, cuaterniones, etc.)
2. **PlayerController.gd**: Reemplazar todos los cálculos de movimiento con versiones usando `FixedPoint`
3. **Bloquear Inyecciones Externas**:
   - Usar `delta` fijo (1.0/60.0) en lugar de variable
   - Evitar acceso directo a `global_transform` para posiciones/rotaciones
   - Asegurar que inputs sean discretos y no interpolados

## Integración con Sistema Existente
- Usar `InputState.gd` para inyección de inputs
- Integrar con sistema de replays existente en `scripts/replay/`
- Asegurar compatibilidad con `PlayerManager.gd` y autoloads

## Ejecución y Validación
- Ejecutar suite completa: `godot3-bin --path . --scene tests/test_replay_determinism.tscn --headless`
- Iterar refactorizaciones hasta que todos los tests pasen
- Documentar resultados en `reports/report_determinism_[fecha].md`

## Cronograma
1. Día 1: Crear inputs de referencia y script base de test
2. Día 2: Implementar pipeline de grabación/reproducción
3. Día 3: Refactorizar PlayerController para FixedPoint
4. Día 4: Bloquear inyecciones externas y validar suite
5. Día 5: Optimizaciones finales y documentación

## Riesgos y Mitigaciones
- Drift por floating-point: Mitigado con FixedPoint completo
- Dependencias externas: Mockear o aislar en tests
- Rendimiento: Tests headless, optimizar si necesario