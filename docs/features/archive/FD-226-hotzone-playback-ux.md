# FD-226 — Interfaz de Revisión de Registros de Rendimiento (Hotzone Playback UX)

## Problema

El sistema actual de reproducción de hotzones (ANNAV2/Viewport) tiene carencias de UX que dificultan analizar registros de bajo rendimiento:

- Al terminar un registro, loopa infinitamente sin pausa automática.
- El HotzoneRecorder no se inhibe correctamente durante el playback → puede generar un nuevo registro del mismo evento.
- La barra de progreso no es interactiva (no se puede clickear para adelantar/retroceder).
- Sin metadatos de build, plataforma, jugador, duración ni fecha.
- Sin visualización de FPS histórico.
- Escape cierra el juego en vez de soltar el mouse (como en gameplay normal).

## Requerimientos

### 1. Inhibición del Recorder durante Playback

`HotzonePlayer._start_replay()` ya desactiva `recorder.hotzone_enabled`, pero el loop (`_on_replay_finished`) no lo reafirma. Además `_exit_tree` lo reactiva pero un crash intermedio lo deja inconsistente.

Solución:
- Forzar `SessionManager.is_replaying = true` al inicio del playback y mantenerlo hasta salir del viewer.
- `HotzoneRecorder.record_frame()` ya chequea `SessionManager.is_replaying` → no debería requerir cambios en el recorder.
- En web, notificar al shell que está en modo replay para no registrar.

### 2. Pausa Automática al Final del Registro

En vez de loop infinito, al llegar al último frame:
- `self.is_paused = true`
- Mostrar botón "REINICIAR REGISTRO" (tecla R)
- Indicar visualmente "REGISTRO COMPLETADO — Pausado"

Opcional: toggle manual de loop (para sesiones de debugging visual continuo).

### 3. Barra de Progreso Interactiva

Reemplazar el `ProgressBar` estándar por un `ColorRect` + `TextureProgress` con `_gui_input`:

- Click en cualquier punto → seek a esa posición.
- Arrastre continuo → scrub.
- Feedback visual: tooltip con `"Frame N/M — T: %.1fs"` al hover.
- Marker vertical del frame actual sincronizado.

### 4. UI de Reproducción (Botones)

HUD semi-transparente estilo interfaz de nave Odisea:

```
[⏮] [⏪] [▶/⏸] [⏩] [⏭]  |  [1x] [2x] [4x]  |  [🔄 Reiniciar]
```

Todos los botones tienen su equivalente en teclado:
- ⏮ = Inicio (Home)
- ⏪ = Back 1s (Ctrl+←)
- ▶/⏸ = Pausa/Reanudar (Espacio)
- ⏩ = Forward 1s (Ctrl+→)
- ⏭ = Final (End)
- 1x/2x/4x = Velocidad (teclas 1/2/4)
- 🔄 = Reiniciar (R)

### 5. Metadatos sobre la Barra de Progreso

Encima de la barra, una fila compacta con:

```
Escena: Dome_Crio | Disparador: auto | FPS mín: 14.2 | FPS med: 22.7
Capturado: 2026-06-16 20:30:12 UTC | Duración: 12.4s
Build: ff17c82b | Plataforma: HTML5 | Tripulante: sebastian_libre
```

Datos extraídos del snapshot de registro:
- `timestamp` → ISO-8601
- `capture_duration` → duración en segundos
- `player_id` → nombre del tripulante
- OS: `OS.get_name()`
- Build/commit: `ProjectSettings.get_setting("application/config/version")` o variable de compilación

### 6. Gráfico de FPS Histórico (Mini)

Dibujar un gráfico lineal-miniatura (~400×30px) sobre la barra de progreso:

- Samplear cada N frames (ej. cada 5 → ~120 muestras para 600 frames).
- Colores: verde (>45 fps), amarillo (30–45), rojo (<30).
- Marcador vertical sincronizado con el frame actual.
- Click en cualquier punto del gráfico → seek (misma lógica que la barra).
- Tooltip: `"Frame %d — FPS: %.1f"`.

### 7. Escape → Release Mouse (no salir)

Actualmente Escape cierra el juego. Debe **soltar el ratón** durante el playback (mismo comportamiento que en el juego base: `Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)` toggle).

Escape no cierra nada — para salir se usa la UI o el botón "Cerrar" de la ventana.

### 8. Sin Overhead de Renderizado

El player usa `loaded_scene_node.pause_mode = PAUSE_MODE_STOP`. No debe instanciar física, animaciones ni process del juego mientras está pausado. El gráfico de FPS solo se calcula de datos capturados, no midiendo en vivo.

Sin allocations extraños en el hot path de `_process`. El chart se redibuja solo al seek o cambio visible, no cada frame.

## Archivos a Modificar

| Archivo | Cambio |
|---------|--------|
| `core_v2/tools/HotzonePlayer.gd` | Toda la lógica nueva (inhibición, pausa, seek interactivo, botones, metadatos, chart) |
| `core_v2/tools/HotzonePlayer.tscn` | Añadir nodos UI: botones, metadata labels, chart, progress bar interactivo |

## Out of Scope

- Mejoras al HotzoneRecorder (otro FD).
- Side-scroll o timeline visual de frames.
- Exportar/descargar hotzone desde el player.
- Loop automático (se deja como toggle manual opcional si se pide después).

## Criterio de Aceptación

1. Playback de un hotzone: al final → pausa automática, botón Reiniciar visible.
2. Durante playback: botones y teclas funcionan (seek, velocidad, pausa).
3. Escape suelta el mouse, no cierra el juego.
4. Click/scrub en barra de progreso → seek instantáneo.
5. Metadatos visibles encima de la barra.
6. Gráfico de FPS se ve y es clickeable.
7. Al abrir el player, `SessionManager.is_replaying = true`. Al cerrar, se restaura. No se genera un nuevo hotzone.
8. Sin crashes, sin warnings de null en consola durante reproducción normal.
