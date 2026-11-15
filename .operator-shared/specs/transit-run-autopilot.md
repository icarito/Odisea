# Transit-Run: modo asistido (piloto automático)

Contrato del relevo humano ↔ máquina. Métricas y umbrales de la ruta: `docs/canon/WFC_FLOW_METRICS.md`.

## Decisiones

- **No hay `InputMultiplexer` ni un frame de input nuevo.** El árbitro es `InputProviderV2` y el
  frame es `InputDataV2`. El piloto automático (`core_v2/input/AutopilotInputV2.gd`) es una
  fuente opcional que el proveedor aplica dentro de `get_input()` en modo LIVE.
- **`docs/canon/WFC_FLOW_METRICS.md` es el único documento de métricas.** No crear un
  `SCAFFOLD_METRICS.md` paralelo: lo propio del andamio (celda, sockets P/S sobre el cilindro)
  se agrega allí como sección.
- La ruta principal usa la banda 70–80 % del alcance a `v_run`. El «70 % del potencial» del
  piloto automático es eso: corre a `v_run` sobre una ruta calibrada, no a velocidad reducida.

## Invariantes

- El piloto automático **solo escribe intents** (`move_vec`, `sprint`, `jump`). Nunca toca
  velocidad, transform ni cámara: el relevo no puede alterar el momentum.
- Cualquier intent humano de gameplay lo apaga **en el mismo tick**. Mirar (`mouse_delta`) no
  lo apaga.
- El tiempo de inactividad se cuenta en **ticks de simulación**, no en reloj.
- Su salida queda en el stream grabado; el replay no ejecuta el piloto automático. Un replay
  de una sesión asistida es indistinguible de uno manual.
- No corre con `hardware_input_enabled = false` ni con el puntero liberado por el juego: ahí
  el silencio del jugador no es inactividad.
- `autopilot == null` (por defecto) deja al proveedor exactamente como antes.

## Límites conocidos

- El conductor es heurístico (apuntar al waypoint, saltar ante hueco o desnivel dentro del
  alcance de `FlowMetrics`). La política PPO de ANNA (`MLPPolicyInference`, obs 13) no está
  conectada: no percibe huecos y tiene sesgo a `SprintForward`.
- Con `size`, apunta al punto más cercano de la plataforma y exige estar bien adentro para dar
  el waypoint por alcanzado. Con `rise` (rampa) apunta a su extremo alto.
- **Carril primero:** si la plataforma destino empieza más adelante y la actual llega hasta
  ahí, avanza recto y recién entonces cruza de costado. Cortar en diagonal atraviesa lo que
  haya entre ambas (un mamparo, el canto de una rampa).
- **Cadencia:** de plataforma corta a plataforma corta fija en el suelo la velocidad de
  despegue para que un toque de salto (o el salto completo si el toque no alcanza) caiga
  sobre el punto de mira, y la conserva en el aire. El frenado en el aire queda como red.
- Verificado con el piloto real sobre tramos generados de 12 chunks horneados
  (`test_scaffold_chunk_run.gd`; `SCAFFOLD_RUN_SEED=<n>` prueba otra semilla).
- `size` de un waypoint es una AABB en el espacio de la ruta. Con `frame` (un
  `ScaffoldChunkOrbit`) la ruta está en el espacio plano del registro y el piloto se convierte
  a ese espacio cada tick; sin `frame`, los waypoints son coordenadas de mundo alineadas a los
  ejes. Asume avance hacia +Z de ese espacio.
- No gira la cámara: el personaje puede correr de lado respecto a la vista.
- Ningún nivel lo activa todavía; falta quién arme la ruta en runtime y la señal diegética
  en el visor.
