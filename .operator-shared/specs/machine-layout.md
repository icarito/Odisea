# Formato de layout de máquinas

Un solo formato JSON (`MachineLevel`) para los niveles prehechos, para guardar lo que arma
el jugador y para el futuro editor (FD-320). La lista de campos por tipo de item vive en la
cabecera de `core_v2/props/machines/MachineLevel.gd`; acá va lo que hay que respetar.

## Convenciones

- **El jugador mira hacia +Z al aparecer.** Los niveles se despliegan hacia +Z.
- **`rot` va en grados, orden de Euler de Godot (YXZ).** Un brazo a lo largo de Z con un
  extremo levantado es `[0, -90, inclinación]`: primero se inclina en su eje local, después
  se orienta.
- **El eje de una bisagra es su Z local.** Para un brazo que corre a lo largo de Z, la
  bisagra lleva `rot: [0, ±90, 0]`.
- **Los nombres de item son la identidad:** `hinge.a`/`hinge.b` y `link.from`/`link.to` los
  referencian, y todos los items son hermanos bajo el `MachineLevel`.
- **Los retardos de `link` se cuentan en ticks de física**, no con `Timer`: es lo que
  mantiene el nivel determinista bajo replay.

## Streaming por estación (área)

Cada item puede declarar `"station": <int>`. Es la **clave de área** con la que
`MachineLevel` agrupa los ítems para el streaming por cercanía
(`ProximityNodeActivatorV2`): se deja todo construido, pero solo queda activo
(visible/colisión/proceso) el grupo cuya estación está dentro de su radio de
alcance; el resto queda dormido. `station 0` (o ausente) es el **shell/ambiente
siempre activo** (cáscara, catwalks, pipes, fuego) y no se apaga nunca.

- El radio/centro de cada estación sale del AABB de sus ítems; el margen de
  liberación es `station_stream_margin` de `MachineLevel` (default 14 m, cubre la
  estación vecina). No hay campo nuevo por item.
- Las estaciones se activan con `MachineLevel.enable_station_streaming = true`
  (opt-in; apagado reproduce el comportamiento previo).
- Un item con `station` debe poder convivir con sus referencias (`hinge.a`/`b`,
  `link.from`/`to`) dentro de la misma estación: apagar un chunk no debe dejar una
  bisagra sin su cuerpo.
- Los ítems de una estación se reactivan en su estado actual, no en el original:
  una pieza cortada sigue cortada. El rearme (`reset_station`) se hace con la
  estación activa (el jugador está cerca para interactuar).

## Recetas que costaron encontrar

- **Retener una pieza suelta:** `"held": true` (queda en `MODE_STATIC`) y un link a `release`.
- **Retener un mecanismo con joints:** no usar `held` en cuerpos que tienen bisagras: en la
  prueba (dos barras retenidas) el mecanismo quedó trabado al soltarlo, causa sin aislar. Se pone un bloque estático como pestillo en su camino
  y el link lo destruye (`"method": "queue_free"`), más un `release` a la pieza para
  despertarla.
- **Plataforma que cuelga nivelada:** dos barras paralelas (paralelogramo). Una sola barra
  con bisagra libre al centro de la plataforma se comporta como péndulo doble y vuelca.
- **Nada estático debajo del recorrido de una pieza:** un muelle que sobresale 20 cm bajo
  la góndola la detiene sin que se note por qué.
- **Señales sin argumentos:** las señales de los interactuables (`activated`) no llevan
  parámetros; los valores van en `"args"` del link.
- **Sin `class_name`** en scripts nuevos: registrarlo exige que el editor reescriba
  `project.godot`. Se usan `preload`.
