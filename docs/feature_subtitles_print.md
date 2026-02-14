# Odisea — Especificación: Overlay de Subtítulos (PRINT/ASSERT OYS)

## Objetivo

Implementar un overlay de subtítulos para mostrar mensajes generados por comandos OYS (`PRINT`, `ASSERT`, `CLS`) durante tests, debug y scripts de integración. El overlay debe ser visualmente similar a los subtítulos de video: texto centrado abajo, sin interactividad, con temporización y transiciones suaves.

---

## Requisitos Funcionales

- **Overlay de Subtítulos**
  - Renderiza líneas de texto centradas en la parte inferior de la pantalla.
  - Cada línea tiene su propio temporizador de visibilidad (default: 2.5s, configurable).
  - Las líneas desaparecen con un fade out suave.
  - Si aparece una nueva línea mientras otra está activa, la anterior sube suavemente (animación vertical tipo "stacked subtitles").
  - No bloquea ni captura ningún input (no interfiere con UI ni gameplay).
  - El overlay debe funcionar tanto en runtime como en escenas de test (DebugOverlay, Workbench, etc).

- **Comando PRINT (OYS)**
  - Cada vez que se ejecuta un comando `PRINT` en OYS, el mensaje se muestra como subtítulo.
  - El texto debe respetar variables sustituidas por OYS.
  - Cada mensaje tiene su propio ciclo de aparición/desaparición.

- **Comando CLS (OYS)**
  - Al ejecutar `CLS`, todos los subtítulos activos desaparecen inmediatamente (sin animación de fade).

- **ASSERT (OYS, modo debug)**
  - Cuando un `ASSERT` pasa, muestra un subtítulo verde con el mensaje del assert.
  - Cuando un `ASSERT` falla, muestra un subtítulo rojo con el mensaje del assert.
  - El color debe ser claramente distinguible (verde éxito, rojo error).
  - El mensaje debe incluir el texto del assert y opcionalmente el frame o contexto.

---

## Requisitos Visuales

- **Estilo**
  - Fuente: Igual o similar a la terminal DebugOverlay (monoespaciada, legible).
  - Fondo: Rectángulo negro semitransparente (ej: alpha 0.6).
  - Texto: Blanco por defecto, verde para assert OK, rojo para assert FAIL.
  - Bordes suaves o sombra para legibilidad sobre cualquier fondo.
  - Padding horizontal generoso (mínimo 32px a cada lado).
  - Espaciado vertical entre líneas (stack) de al menos 8px.

- **Animaciones**
  - Fade in/out: Opacidad animada (ej: 200ms).
  - Movimiento vertical suave al apilar nuevas líneas (ej: 120ms).
  - CLS elimina todas las líneas instantáneamente.

---

## Integración Técnica

- **Ubicación**
  - Implementar como escena `Control` (ej: `core_v2/ui/retro/SubtitlesOverlay.tscn` + `SubtitlesOverlay.gd`).
  - El overlay debe poder agregarse como singleton global o como hijo de DebugOverlay/Workbench.
  - No debe interferir con el input ni capturar focus.

- **API**
  - Método `show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5)`
  - Método `clear_subtitles()` para CLS.
  - Soporte para múltiples líneas activas (stack).

- **Hook OYS**
  - El comando `PRINT` debe llamar a `show_subtitle`.
  - El comando `CLS` debe llamar a `clear_subtitles`.
  - Los asserts (`ASSERT`) deben llamar a `show_subtitle` con color verde/rojo según resultado.

- **Debug/Test**
  - El overlay debe poder activarse/desactivarse vía ProjectSetting/env var para evitar interferir en tests headless.

---

## Ejemplo de Uso

```gdscript
# Desde OYS_Interpreter.gd
_subtitles_overlay.show_subtitle("¡Puerta abierta!", Color.white)
_subtitles_overlay.show_subtitle("ASSERT OK: Player en posición", Color.green)
_subtitles_overlay.show_subtitle("ASSERT FAIL: Plataforma no detectada", Color.red)
_subtitles_overlay.clear_subtitles()
```

---

## Notas

- El overlay debe ser desacoplado: no debe depender de DebugOverlay ni de la terminal.
- Si no hay overlay activo, los comandos deben ignorarse silenciosamente (no error).
- El overlay debe ser fácilmente testeable (exponer nodos para asserts en tests UI).

---