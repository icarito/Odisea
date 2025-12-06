# AGENTS.md — Guía de orientación para agentes (Odisea: El Arca Silenciosa)

Notas:
- GODOT_BIN: godot3-bin 
- Si el usuario te alcanza logs seguramente es que último intento falló y desea que intentes de nuevo.
- Recuerda que en GDScript los ternarios son como en Python no como en JS.
- Debes declarar variables con `=` en lugar de tiparlas explícitamente `:=`. Esto no es Pascal.
- Cuando exportes variables para el Inspector, añade descripciones claras usando `@export_range`, `@export_category`, y encabezados `@export_group("Debug")` (de acuerdo al contexto).

## 1) En una frase
Odisea (MVP) es un juego 3D en Godot 3.6 (GLES2): tercera persona + plataformas con plataformas móviles/conveyor, cámara suave, y narrativa ligera por diálogos JSON; primera entrega jugable: Acto I "Criogenia" como nivel continuo.

## 2) Lo que más importa (Top Goals — MVP Acto I)
- Jugabilidad base estable: `move_and_slide_with_snap`, transferencia de velocidad externa (plataformas/conveyor), coyote time e input buffer.
- Nivel continuo `scenes/levels/act1/criogenia.tscn` con plataformas, conveyor, viento, cajas apilables, kill/respawn y objetivo claro.
- Narrativa mínima: DialogueManager (JSON + AudioStreamPlayer3D).
- Rendimiento: 60 FPS desktop, 30–60 FPS Android (GLES2).

## 7) Contratos de interfaces (críticos)
- `PlayerController.gd` (KinematicBody):
  - `set_external_velocity(v: Vector3) -> void`: suma velocidad externa (plataformas/conveyor) con decaimiento suave por frame.
  - Usar `move_and_slide_with_snap(motion, snap_vec, Vector3.UP, true)` con `snap_vec = -get_floor_normal() * snap_len` cuando en suelo.
  - Implementar coyote time (~120–150 ms) e input buffer (~100–120 ms) para saltos.
- `MovingPlatform.gd`:
  - Calcular velocidad instantánea (Δpos / Δt) y comunicársela al jugador si está sobre ella (vía `Area`/detección).
  - Mantener lista de cuerpos pasajeros y llamar `set_external_velocity()`.
- `Conveyor.gd` (Area):
  - Aplicar `push_velocity` constante a `KinematicBody`/`RigidBody` (para jugador usar `set_external_velocity`).
  - Configurable: dirección y magnitud; coherente con material visual (flechas).
- Diálogos:
  - `autoload/DialogueManager.gd`: carga JSON, expone `start_dialogue(id)` y señales básicas; reproducir voz con `AudioStreamPlayer3D`.

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
- MVP Acto I (Criogenia): primer nivel completo y continuo con piezas clave.