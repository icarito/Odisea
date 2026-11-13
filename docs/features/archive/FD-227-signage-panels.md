# FD-227 — Paneles de Señalización Ambiental (Signage)

## Problema

El entorno de Odisea usa HoloTerminalV2 y TableTerminal para toda comunicación visual con el jugador. Son interactivos, corren OdiseaOS/DebugOverlay, y tienen complejidad de UI. No existe un elemento visual "liviano" para:

- Letreros direccionales o de advertencia (ej: "SALIDA", "PELIGRO", "SOLO PERSONAL AUTORIZADO")
- Alertas ambientales no interactivas (ej: "FUGA DETECTADA", "SECTOR EN CUARENTENA")
- Hologramas simples que no requieran interacción
- Indicadores de estado de puertas/áreas (ej: "BLOQUEADO", "DESPRESURIZADO")

No necesitan input del jugador, ni correr OdiseaOS, ni ser piezas de UI complejas.

## Requerimientos

### 1. Componente base: `SignagePanel`

Escena base `res://core_v2/props/signage/SignagePanel.tscn` + script adjunto.

Un `MeshInstance` plano (cuadrilátero) con material emissivo (emission_enabled + emission_energy controlable por script). Se le asigna una textura desde el inspector. Variantes del mismo asset:

- **WallSign**: pegado a una pared (collision_shape como StaticBody para que Elías pueda chocar contra él). Mesh: `QuadMesh` 0.5×0.3m (apaisado) o 0.3×0.5m (vertical).
- **HangingSign**: cuelga del techo con cadena/soporte decorativo. Misma lógica.
- **FloorLabel**: en el piso, Mesh rotado 90°.

### 2. Modo holograma (opcional)

El script permite toggle `hologram_mode` que:
- Reduce emission_alpha
- Aplica efecto `spatial_material.flags_transparent = true`
- Oscila levemente la escala (wave sinusoidal ±1%) para sensación de proyección
- Sin textura → usa color sólido con borde más brillante

No necesita partículas ni shaders complejos. Es un efecto barato de 3 líneas en `_process`.

### 3. Contenido: texturas renderizadas a código

En vez de exigir textures externas, el script genera el contenido con un `Viewport` invisible + `Label`:

```
─ VIEWPORT (64×64 a 256×64, configurable)
  └─ ColorRect (fondo: negro/azul/ámbar/rojo según color preseteado)
     └─ Label (texto, font, alineación)
```

- El Viewport se renderiza una vez en `_ready()` y se asigna como albedo/emission de la textura.
- No se procesa cada frame (renderizado estático), a menos que se llame a `update_text()`.
- Presets de color: `warning` (ámbar/#FF8800), `danger` (rojo/#FF2200), `info` (azul/#2288FF), `terminal` (verde/#00FF88), `hologram` (cian/#00CCFF con alpha).
- Font: usa `res://assets/fonts/terminal.ttf` si existe, sino DroidSansMono.

### 4. Interacción: opcional

El SignagePanel puede ser completamente pasivo (solo se ve) o tener interacción simple a través de un área de colisión:

- `is_interactive: bool` — si true, añade un `Area` para detectar al jugador cerca.
- Al acercarse: muestra un tooltip estilo "Leer letrero" (E).
- Al presionar E: ejecuta `signage_read()` que puede:
  - Mostrar el texto ampliado en un popup HUD (tipo `PlayerHintManager`)
  - O simplemente activar un trigger en el EventBus (para puzzles: "se ha leído el letrero X")

Por defecto `is_interactive = false` — no añade área, no consume E.

### 5. Rotación y facing

El script permite `face_player: bool` en modo holograma:
- En `_process`, el mesh rota suavemente (`lerp`) hacia la cámara del jugador (solo eje Y, como un billboard suave).
- No es un SpatialMaterial con billboard=true (eso es muy rígido). El lerp da sensación de proyección volumétrica.

### 6. Performance

- Viewport de baja resolución (máx 256×64, default 128×64).
- El Viewport se libera tras generar la textura. No queda en el árbol de escena.
- Los SignagePanel estáticos (no holograma, no face_player, no interactivos) pueden ponerse en modo `sleep` tras `_ready`.
- Sin `_process` para los estáticos.

### 7. Preview en editor

El script detecta `Engine.editor_hint` y en `_ready` renderiza el Viewport inmediatamente para que se vea en el viewport del editor. Sin esto, solo se ve un mesh blanco.

## Archivos a crear

| Archivo | Descripción |
|---------|-------------|
| `core_v2/props/signage/SignagePanel.tscn` | Escena base (MeshInstance + StaticBody + script) |
| `core_v2/props/signage/SignagePanel.gd` | Script con generación de textura, modos, interacción |
| `core_v2/props/signage/WallSign.tscn` | Variante escena hija (rotación/scale preconfigurado) |
| `core_v2/props/signage/HangingSign.tscn` | Variante colgante |
| `core_v2/props/signage/FloorLabel.tscn` | Variante en piso |

## Out of scope

- Animaciones complejas de holograma (parpadeo, interferencia)
- Partículas en emisores holográficos
- Textos dinámicos que cambien con lógica de juego (eso es un HoloTerminalV2 ligero, mejor otro FD)
- Sonidos de proyección o encendido

## Criterio de Aceptación

1. Arrastrar WallSign a una escena → se ve con texto editable en inspector, color según preset.
2. Cambiar texto en inspector → se actualiza en el viewport (no requiere recompilar).
3. Poner `hologram_mode=true` → se ve semitransparente, oscila, rota hacia el jugador.
4. `is_interactive=true` + E → se activa hint.
5. Sin warnings en consola. Sin `_process` en SignagePanel estáticos.
6. Vista previa en editor funcional.
