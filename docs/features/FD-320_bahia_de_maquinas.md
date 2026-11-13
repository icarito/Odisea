# FD-320 — Bahía de máquinas («Orden de Trabajo 0001»)

**Estado:** candidata RingHub + bahía, con regresiones focalizadas de máquinas, checkpoint/Continue y retorno. Falta recorrido continuo con control en mano y aprobación visual.
**Alcance de cierre (2026-11-13):** traversal con cuatro máquinas prearmadas; sin editor de construcción ni integración de domos. [Bitácora de verificación](../agents/sessions/2026-11-13_slice_convergence.md).
**Rama:** `feat/vs-bahia-maquinas`
**Contratos:** `.operator-shared/specs/machine-launch.md`, `.operator-shared/specs/machine-layout.md`

## Qué es

Pivote del vertical slice hacia un sandbox de máquinas: Elías cruza una bahía de
mantenimiento lanzándose con mecanismos físicos (Box3D). Fantasía central: *lanzarse*
(contrapesos, péndulos, catapultas). Tono: humor burocrático seco de la IA Odisea.
Principio: sistemas, no puzzles — las variables son continuas (masa, dónde se para el
jugador, cuándo salta) y no hay umbral mágico.

## Referencias de diseño

- Immersive sims; parkour de *Mirror's Edge* y *Tomb Raider* (pedido original).
- **Besiege** (Sebastián, 2026-11-11). Lo que se toma para el banco de pruebas:
  - Dos fases: **armar** (física congelada, piezas que encajan en puntos de anclaje) y
    **probar** (se suelta la simulación); volver a armar restaura el plano guardado.
    El layout JSON es ese plano.
  - Catálogo corto de piezas con un rol claro cada una, que se combinan.
  - El fracaso es parte de la gracia: las máquinas se desarman y fallan de forma legible.
  - Lo que no se toma: la cámara libre fuera del personaje. Elías arma desde adentro del
    mundo, con el multi-tool.

## Enmienda propuesta al GDD y a AGENTS.md (pendiente de decisión de Sebastián)

- GDD v3 §10 dice «no tiene puzzles de reparación / minijuegos». La bahía no es un
  minijuego (es el mismo mundo y la misma física), pero sí cambia el foco del slice.
- AGENTS.md §10 limita el alcance al Acto I y §11.8 pide defender el scope. Este FD es un
  pivote explícito pedido el 2026-11-11, no feature creep silencioso; si se confirma, hay
  que reescribir §10.

## Qué hay hecho

| Pieza | Dónde |
|-------|-------|
| Lanzamiento inercial del jugador sobre piezas rígidas | `PlayerControllerV2._track_rigid_platform`, `PlayerJumpV2.launch`, `PlayerMovementV2.add_launch_velocity` |
| Kit de piezas: `MachinePart` (viga/peso, retención), `MachineHinge` (límite, motor) | `core_v2/props/machines/` |
| Niveles por layout JSON (`MachineLevel`): bloques, piezas, bisagras, escenas, triggers, links con retardo, guardar/cargar | `core_v2/props/machines/MachineLevel.gd` |
| Bahía con cuatro estaciones | `core_v2/levels/machines/MachineBay.tscn` + `machine_bay.json` |
| Voz de Odisea por subtítulos | links `say` en el layout |

### Estaciones

1. **Balancín.** Palanca → a los 2 s cae un contrapeso de 400 kg → el jugador, parado en el
   otro extremo, vuela a la cornisa (apogeo ~9 m).
2. **Péndulo.** Góndola de paralelogramo (dos barras: se mantiene nivelada) retenida por un
   pestillo; la palanca lo suelta y cruza el vacío de 14 m.
3. **Catapulta.** Tres contrapesos, tres palancas: el jugador elige cuánta masa soltar.
   Apogeos medidos: liviano 11 m, medio 20 m, pesado 28 m, los tres 33 m (y 23 m de
   alcance: se pasa de la cornisa final si no corrige en el aire).
4. **Brazo centrífugo.** El brazo de servicio hace de puente; la palanca enciende el motor
   a los 5 s (1.8 rad/s, ~8 m/s en la punta). El jugador elige cuándo saltar: sale por la
   tangente y cae en la plataforma de salida, 15 m más allá.

## Cómo probar

```bash
ODISEA_FORCE_MUTE_AUDIO=1 tools/launch_game.sh --scene res://core_v2/levels/machines/MachineBay.tscn
./.venv/bin/pytest tests/test_odisea_runner.py -q -k "test_machine_launch or test_machine_bay or test_machine_level"
```

## Pendiente

- **Ruta vigente: RingHub → bahía → RingHub.** Existe acceso por `Hub/PedestalMachineBay` y payload de regreso para no repetir el despertar. Falta validar el recorrido completo y continuidad visual jugando. La conexión domo/tubo queda fuera de este cierre; el launcher es una herramienta de inspección, no la entrada de campaña.
- **Multi-tool.** Tractor/agarrar ya existe en `MultiToolV2`; gloo y láser también. Validar claridad de uso; no añadir catálogo/editor como requisito del traversal.
- **Balancín: el vuelo es casi vertical.** Llegar a la cornisa exige corregir en el aire;
  falta confirmar con control en mano que se entiende sin texto.
- **Bug del fork Box3D** (`Box3DDirectBodyState::get_velocity_at_local_position`): toma el
  punto en coordenadas locales del cuerpo. El jugador lo compensa en
  `_track_rigid_platform`; conviene corregirlo en `godot-box3d-3` y borrar la compensación.
- **Cascarón Blender opcional.** El layout carga `build/machine_bay/bay_shell.glb` si existe. Su presencia local no acredita disponibilidad en exports/CI; revisar legibilidad y empaquetado antes de darlo por entregado.
- **Banco de pruebas / editor (backlog, fuera de este cierre).** `MachineLevel.export_layout()` y `save_layout_file()` existen; no implementar una terminal/catálogo para cerrar el slice.
- **i18n** de las líneas de Odisea (hoy texto en español dentro del layout, pasa por `tr()`).
- **Replay.** Los snapshots de vuelo ya incluyen estado balístico en `PlayerMovementV2`; conservar la cobertura focalizada y verificar determinismo cuando se toque movimiento. No tratar la implementación antigua como un pendiente sin volver a leer el código.
