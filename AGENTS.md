# AGENTS.md — Guía de orientación para agentes (Odisea: El Arca Silenciosa)

Nota: Recuerda que en GDScript los ternarios son como en Python no como en JS.

## 1) En una frase
Odisea (MVP) es un juego 3D en Godot 3.6 (GLES2): tercera persona + plataformas con plataformas móviles/conveyor, cámara suave, y narrativa ligera por diálogos JSON; primera entrega jugable: Acto I "Criogenia" como nivel continuo.

## 2) Lo que más importa (Top Goals — MVP Acto I)
- Jugabilidad base estable y agradable: `move_and_slide_with_snap`, transferencia de velocidad de plataformas y conveyor, coyote time e input buffer.
- Un solo nivel continuo `scenes/levels/act1/criogenia.tscn` con: plataformas con barandas, conveyor, tubos conectores, zonas de viento, cajas apilables, kill/respawn y objetivo claro.
- Narrativa mínima funcional: DialogueManager (JSON + AudioStreamPlayer3D) integrado en el nivel.
- Rendimiento estable: 60 FPS desktop, 30–60 FPS Android (GLES2).

## 3) No-objetivos (por ahora)
- Migrar a Godot 4.x o CharacterBody3D.
- Sistemas complejos de IA, inventario o árbol de diálogos ramificado.
- Gráficos pesados de postproceso o materiales avanzados costosos (limitación GLES2).

## 4) Estado técnico (hechos rápidos)
- Motor: Godot 3.6.x | Render: GLES2 | Plataformas: Linux/X11 + Android.
- Jugador: `KinematicBody` tercera persona con `AnimationTree`.
- Problema clave resuelto en diseño: interfaz de velocidad externa para plataformas/conveyor y uso de `move_and_slide_with_snap`.
- Prioridades técnicas: feel de movimiento, estabilidad sobre plataformas, cámara spring-damper, diálogos JSON.

## 5) Cómo correr y probar
- Abrir el proyecto en Godot 3.6.x.
- Escena de foco MVP: `scenes/levels/act1/criogenia.tscn`.
- Pruebas puntuales sugeridas:
  - Movimiento en plataformas móviles: adherencia sin jitter; salto conserva parte de velocidad.
  - Conveyor: empuje constante, requiere correcciones pero sin frustración.
  - Viento: ascenso controlable; calibrar `lift_force`/`max_speed`.
  - Kill/Respawn: caídas respawnean en último checkpoint seguro.

## 6) Mapa mínimo del código (rutas clave)
- Jugador y cámara:
  - `players/elias/PlayerTemplate.gd` (actual) → futuro `PlayerController.gd` mejorado.
  - `scripts/CameraTemplate.gd` → base para spring-damper.
- Plataformas y entorno dinámico:
  - `scripts/MovingPlatform.gd` | `scenes/common/` (plataformas A↔B; añadir curva más adelante).
  - `scripts/Conveyor.gd` | `scenes/common/Conveyor.tscn` (empuje direccional constante).
  - `scripts/WindZone.gd` | `scenes/common/WindZone.tscn` (fuerza vertical configurable).
  - `scripts/KillZone.gd` | `scenes/common/KillZone.tscn` (muerte por caída/límites).
  - `autoload/PlayerManager.gd` (spawn/respawn, checkpoints).
- Datos y docs:
  - `data/Curves/*.tres` (perfiles de aceleración).
  - `data/odisea_wiki.json` (índice de diseño/narrativa).
  - `docs/odisea_mvp_guideline.md` y `docs/odisea_api_cheatsheet.md` (referencias técnicas rápidas).
- Nivel objetivo: `scenes/levels/act1/criogenia.tscn`.

## 7) Contratos de interfaces (críticos)
- `PlayerController.gd` (KinematicBody):
  - `set_external_velocity(v: Vector3) -> void`: suma velocidad externa (plataformas/conveyor) con decaimiento suave por frame.
  - Usar `move_and_slide_with_snap(motion, snap_vec, Vector3.UP, true)` con `snap_vec = -get_floor_normal() * snap_len` cuando en suelo.
  - Implementar coyote time (~120–150 ms) e input buffer (~100–120 ms) para saltos.
- `MovingPlatform.gd`:
  - Debe calcular su velocidad instantánea (Δpos / Δt) y comunicársela al jugador si está sobre ella (vía `Area`/detección).
  - Mantener lista de cuerpos pasajeros y llamar `set_external_velocity()`.
- `Conveyor.gd` (Area):
  - Aplicar `push_velocity` constante a `KinematicBody`/`RigidBody` (para jugador usar `set_external_velocity`).
  - Configurable: dirección y magnitud; coherente con material visual (flechas).
- Diálogos:
  - `autoload/DialogueManager.gd`: carga JSON, expone `start_dialogue(id)` y señales básicas; reproducir voz con `AudioStreamPlayer3D`.

## 8) Priorización de trabajo (orden recomendado)
1) Movimiento base y plataformas
- `PlayerController`: snap + external velocity + coyote/buffer.
- `MovingPlatform`: calcular/emitir velocidad a pasajeros.
2) Piezas del nivel (de mayor impacto a menor)
- `Conveyor.tscn` + material de dirección.
- `GuardrailSegment.tscn` (barandas) en bordes críticos.
- `TubeConnector.tscn` entre alas (backtracking y claridad de ruta).
- `WindZone.tscn` (ascenso controlado) y `PushableBox.tscn` (apilables).
- `KillZone.tscn` + `Checkpoint.tscn` + respawn en `PlayerManager`.
- `GoalBeacon.tscn` (objetivo de alto contraste que cierra el recorrido).
3) Narrativa mínima
- `DialogueManager` + JSON inicial; integrar 2–4 líneas en puntos clave.

## 9) Criterios de aceptación (Done = ✅)
- Plataforma móvil: el jugador viaja sin jitter y mantiene parte de la velocidad al saltar.
- Conveyor: empuje estable; el jugador puede compensar con input, sin perder control.
- Cámara: seguimiento suave, sin clipping molesto; lectura clara del entorno inmediato.
- Nivel Acto I: recorrido continuo con todas las piezas listadas en TODO; objetivo final funcional.
- Diálogos: reproducen y terminan sin cortar; sincronía razonable con texto.
- Rendimiento: desktop 60 FPS; Android ≥30 FPS en escena MVP.

## 10) Riesgos y cómo mitigarlos
- Jitter en plataformas: asegurar `snap` y desactivar `stop_on_slope`; comunicar `external_velocity` cada frame.
- Conveyor irregular: `push_velocity` por `delta` (no por frame); evitar picos de fuerza.
- Apilables inestables: limitar masa/rozamiento y alturas (2–3 cajas), colisiones simples.
- GLES2: reducir luces dinámicas; texturas simples; medir en dispositivo Android temprano.

## 11) Estilo de trabajo (cómo colaborar eficazmente)
- Cambios pequeños y enfocados por feature; evitar refactors amplios no solicitados.
- Mantener nombres/paths consistentes con los docs para reducir fricción.
- Al tocar movimiento, validar en `criogenia.tscn` con pruebas dirigidas (plataformas, conveyor, viento).
- Documentar parámetros críticos en el Inspector (export variables) y anotar valores por defecto razonables.

## 12) Checklist rápida por feature
- ¿Define interfaz pública clara? (`set_external_velocity`, señales, exports)
- ¿Tiene escena `.tscn` + `.gd` y colisiones correctas?
- ¿Existen valores exportados con descripciones claras?
- ¿Probado en `criogenia.tscn` con casos reales?
- ¿Sin romper FPS objetivo (ver Monitor/Profiler)?
- ¿Actualizaste referencias en `README.md`/`docs` si aplica?

## 13) Glosario mínimo
- Snap: vector de adhesión al suelo para `move_and_slide_with_snap`.
- External/Platform Velocity: velocidad de transporte impartida al jugador por entorno dinámico.
- Coyote Time / Input Buffer: ventanas de tolerancia para saltos responsivos.
- MVP Acto I (Criogenia): primer nivel completo y continuo con las piezas listadas en `TODO.md`.

## 14) Enlaces útiles internos
- `docs/odisea_mvp_guideline.md` (guía técnica priorizada)
- `docs/odisea_api_cheatsheet.md` (interfaces rápidas)
- `docs/odisea_resumen_ejecutivo.md` (prioridades y cronograma)
- `data/odisea_wiki.json` (narrativa/diseño)
- `TODO.md` (tareas concretas del nivel)