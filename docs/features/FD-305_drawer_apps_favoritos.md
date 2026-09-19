# FD-305: Drawer de apps y favoritos — el "..." del radial

**Status:** Design
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-19
**Completed:** -
**Parent:** FD-296 (OdiseaOS) · FD-296 F3 (HudModeOverlay) · FD-304 (interfaz diégetica con gamepad)
**Relacionadas:** FD-306 (fixes estructurales del radial)

## Problem

Hoy el dial de OdiseaOS lista **todo** lo que esté registrado en SuitOS, en orden de
registro de escena. Eso tiene tres consecuencias que ya se ven venir:

1. **El dial no es curado.** El jugador no elige qué está a mano; lo elige el orden
   en que las escenas cargaron sus `HUDableComponent`. Con 8–10 pantallas
   registrables el dial deja de ser un acceso rápido y pasa a ser un índice.
2. **No hay dónde poner lo que no cabe.** Las pantallas de uso esporádico
   (diagnósticos de criocápsulas, esquemáticos de coolant, paneles de sala) no
   merecen un sector permanente, pero tampoco pueden desaparecer.
3. **No hay curaduría persistida.** `SuitOS.save_state()` guarda **solo**
   `pinned_slots` (4 strings). No existe el concepto de "estas son mis apps".

El resultado: un sistema de 4 slots + un dial que pretenden ser la interfaz del
traje, pero sin un lugar donde el jugador decida qué vive ahí.

## Solution

Se agrega un **item central `...`** al dial (FD-304 §7 lo dejó como decisión
abierta y Sebastián eligió que sea **un item**, sacrificando la zona muerta), y
detrás de él un **drawer**: una lista completa, alfabética y desplazable de todas
las pantallas registradas, donde el jugador **usa** (A) y **cura** (X).

### 1. El "..." como item del dial

- Ocupa el **centro** del dial, con radio propio (`HUB_RADIUS`, ver FD-306 §1).
- Es **siempre el primer item** y **no se puede quitar**: es la puerta al resto.
- **No es una app.** No aparece en su propia lista, no se puede favoritear y no se
  puede asignar a un slot. Se implementa como *chrome* de `HudModeOverlay` (igual
  que el placeholder "SIN PANTALLAS"), **no** como `HUDableComponent` registrado.
  Esto evita la recursión (el drawer listándose a sí mismo) por construcción, no
  por una guarda.
- Elegirlo abre el drawer y **deja el dial cerrado**: el drawer es una vista, no
  un submenú del dial.

### 2. Favoritos = el contenido del radial

Decisión de arquitectura (Sebastián, 2026-09-19): **el radial muestra solo los
favoritos**. Los slots son otra cosa y se llenan arrastrando (mouse o TAB+joypad),
como ya hace `SuitOSWidgetHost` y FD-304 §6.

| Concepto | Qué es | Cómo se llena | Persiste |
|----------|--------|---------------|----------|
| **Favoritos** | Lista curada, **máximo 6** | X en el drawer | Sí |
| **Slots** (4) | Acceso ultra-rápido | Drag/drop o TAB+arrastre | Sí (`pinned_slots`) |
| **Drawer** | Todas las pantallas del registry | Automático | No (derivado) |

- Tope de **6 favoritos** en el dial (FD-306 §2). Al intentar favoritear un 7º, el
  drawer responde con **deny** (haptic + flash ámbar de la fila + leyenda
  "RADIAL LLENO"), sin reemplazar nada en silencio.
- **Set por defecto** en el primer arranque: `player:flashlight` y `ship:systems`,
  para que el dial nunca nazca vacío. Si el jugador los borra todos, el dial queda
  **solo con el "..."** — estado válido, nunca roto.
- **Un favorito no registrado en la escena actual** se sigue mostrando, marcado
  como *offline*. Ya existe el mecanismo: `SuitOS._pinned_snapshot()` cae a
  `_last_snapshots_cache` y marca `source = "offline"`. El drawer usa la misma
  regla; el favorito no se pierde al cambiar de nivel.

### 3. El drawer

Vista a pantalla completa dentro del modo HUD (mundo en pausa).

**3.1 Contenido.** Todas las pantallas de `SuitOS.get_registered_screens()`, una
fila por pantalla:

| Columna | Origen |
|---------|--------|
| Icono | `screen.screen_icon()` (hoy declarado y sin usar — ver FD-306 §3) |
| Título | `screen.screen_title()` |
| Estado | `widget_snapshot()["source"]` → online / offline / alerta |
| Marca | Estrella si está en favoritos |

**3.2 Orden.** **Alfabético** por título, con comparación locale-aware
(`String.nocasecmp_to` sobre la clave normalizada, sin acentos), porque el
jugador busca por nombre, no por importancia. El orden por `relevance` vive en el
arco del dial (FD-306 §2), no acá: son dos preguntas distintas ("¿dónde está X?"
vs. "¿qué me importa ahora?").

Agrupación visual optativa por **inicial** (cabecera de letra cuando cambia), que
es lo que hace legible una lista larga sin agregar jerarquía falsa.

**3.3 Scroll suave y analógico.** El pedido explícito: que "fluya".

- El **stick** da velocidad, no posición: `scroll_velocity += axis * ACCEL * dt`,
  con fricción (`FRICTION` por segundo) y un tope `MAX_SCROLL_SPEED`. La lista
  acelera, acompaña y decae; se siente como una inercia.
- **D-pad** da pasos discretos: una fila por pulsación, con auto-repeat a los
  400 ms (mismo umbral del hold del HUD, para no inventar un tercer tempo).
- **Topes**: overscroll con resistencia elástica y rebote al soltar (no un clamp
  seco), para que el extremo se sienta.
- **Snap**: al detenerse, la fila más cercana al centro se alinea sola.
- Nada de `ScrollContainer`: su scroll nativo no toma velocidad analógica. Se
  controla `rect_position.y` de un contenedor propio.

**3.4 Búsqueda.** El pedido: "que solo busque si empiezas a escribir algo".

- **Desktop:** al recibir el primer carácter imprimible, aparece una **caja de
  filtro** arriba y se filtra incrementalmente por substring del título
  (case- y accent-insensitive). `Escape` limpia el filtro; si ya está vacío, sale
  del drawer. Con el filtro vacío **no hay caja de búsqueda visible**: la vista
  por defecto es la lista alfabética, sin ruido.
- **Gamepad:** **no hay búsqueda de texto.** No hay teclado en el HUD y meter uno
  en pantalla es otro sistema entero. El gamepad navega la lista alfabética
  (stick/D-pad) y el agrupado por inicial ya da el salto corto.
- **Determinismo:** escribir texto **no pasa por el stream** (`InputDataV2` no
  graba teclas de texto). Por lo tanto el filtro es **estado de UI no
  determinista y excluido del replay**, explícitamente. No rompe nada porque el
  mundo está en pausa y el drawer no decide nada de gameplay: elegir por filtro
  desemboca en `open_screen(id)`, que sí es determinista por `id`. El replay
  reproduce la elección, no la búsqueda.

**3.5 Acciones.**

| Botón | Acción |
|-------|--------|
| A (o clic/tap) | **Abrir la app** (cierra el drawer y entra a modo pantalla). |
| X | **Favoritear / quitar** de favoritos. Haptic de confirmación y estrella animada. |
| B / `Escape` | Volver al dial (o al juego, si se entró directo). |
| Stick / D-pad | Scroll. |
| Hold de un hombro | Tomar la fila enfocada y **arrastrarla a un slot** (reusa FD-304 §6). |
| Y (botón HUD) | Salir del modo HUD. |

El **arrastre a slot** es lo que cierra el círculo con los slots: el drawer es el
origen natural de un drag largo, y la ruta `pin_to_slot()` ya existe.

### 4. Persistencia

Se extiende `SuitOS.save_state()` / `restore_state()` de forma **aditiva**:

```
{
  "pinned_slots": [...],          # existente, sin tocar
  "last_snapshots": {...},        # existente, sin tocar
  "favorite_screens": ["player:flashlight", "ship:systems"],   # nuevo
  "favorites_initialized": true   # nuevo
}
```

- `favorites_initialized` distingue "todavía no hay favoritos porque es un save
  nuevo" (→ sembrar los defaults) de "el jugador los borró a propósito" (→ dejar
  el dial solo con el "..."). Sin esa bandera el set por defecto reaparece cada
  vez que alguien limpia su lista, que es exactamente el bug que hay que evitar.
- **Compatibilidad:** un save sin `favorite_screens` se trata como
  `favorites_initialized = false` → siembra los defaults. Los saves viejos no se
  rompen.
- El snapshot de SuitOS ya viaja con el checkpoint de partida y con el replay (lo
  dice el header de `SuitOS.gd`), así que los favoritos entran gratis en
  CONTINUE y en la reproducción.
- `favorite_screens` se **filtra contra el registry al mostrarse**, no al
  guardarse: si un favorito apunta a una pantalla que ya no existe, se muestra
  offline y el jugador lo quita con X. Nunca se pierde data por un nivel que no
  registra tal pantalla.

### 5. Frescura de la lista

`HudModeOverlay` hoy lee `_screen_ids` **una sola vez en `_ready()`**
(`HudModeOverlay.gd:141`) y no escucha `screen_registered` / `screen_unregistered`.
Hoy no es bug porque el overlay es efímero. **Un drawer que puede abrirse con el
mundo corriendo sí lo rompe**: hay que suscribirse a `screen_registered` y
`screen_unregistered` y reconstruir la lista (preservando el scroll, o saltando a
la fila enfocada).

## Considered Options

- **El "..." como item central (elegida).** Coherente con FD-304: un hold de
  hombro abre el dial, el centro es el hub, y el hub es la puerta al resto.
  *Contra:* se pierde el gesto "soltar en el centro = no elegir nada", que era la
  red de seguridad contra selecciones accidentales. **Consecuencia aceptada y
  explícita**: el "..." debe tener radio chico (FD-306 §1) y deny visual al
  soltar sin dirección clara, o los taps accidentales van a abrir el drawer.
- **El "..." fuera del dial** (opción 0 del arco, o botón propio). Más seguro,
  pero desperdicia el centro y agrega un gesto nuevo que hay que enseñar.
- **Búsqueda por teclado en pantalla para gamepad.** Descartada: otro sistema
  completo (teclado virtual, navegación por celdas, i18n de teclas) para un caso
  que la lista alfabética con agrupado por inicial ya cubre.
- **Favoritos = slots.** Descartada por Sebastián: son dos conceptos con
  propósitos distintos (barra rápida vs. acceso instantáneo) y la lista
  ilimitada de favoritos no cabe en 4 slots.

## Fuera de scope

- Búsqueda de texto en gamepad (teclado virtual).
- Categorías/tags de apps (el agrupado es solo por inicial).
- Reordenar el radial a mano (el orden lo da `relevance`, FD-306 §2).
- Favoritos compartidos con el control remoto (F4 los espeja; acá solo se
  persisten y se listan).

## Files to Modify

- `core_v2/ui/hud/SuitOSDrawer.gd` / `.tscn` — **nuevos**. La vista del drawer.
- `core_v2/ui/hud/HudModeOverlay.gd` — montar el drawer, item central "..." del
  dial, suscripción a `screen_registered`/`unregistered`, atajos A/X/B (modificar).
- `core_v2/autoloads/SuitOS.gd` — `favorite_screens` + `favorites_initialized` en
  `save_state()`/`restore_state()`, `is_favorite()` / `toggle_favorite()` /
  `get_favorites()`, siembra de defaults (modificar).
- `core_v2/ui/hud/HudMenuChrome.gd` — **nuevo** (si se confirma la propuesta de
  FD-306 §1 de extraer el chrome del modo HUD: hub, leyendas, mapeo de botones).
- `core_v2/tests/test_suit_os.gd` — persistencia de favoritos, siembra de
  defaults, save viejo sin la clave (modificar).
- `core_v2/tests/test_hud_drawer.gd` — **nuevo**: orden alfabético, filtro, deny
  del 7º favorito, favorito offline.
- `docs/features/FEATURE_INDEX.md` — alta de FD-305 (modificar).

## Verification

1. **Item central.** El dial muestra el "..." en el centro; elegirlo abre el
   drawer. El "..." nunca aparece en su propia lista.
2. **Solo favoritos en el dial.** Favoritear desde el drawer mete la app en el
   arco; quitarla la saca. `save_state()` no persiste `pinned_slots` como efecto
   colateral.
3. **Defaults.** Partida nueva → el dial abre con linterna + sistemas. Borrar los
   dos → el dial queda solo con el "...", y **no** reaparecen tras recargar.
4. **Save viejo.** Un save sin `favorite_screens` carga sin error y siembra los
   defaults una vez.
5. **Deny del 7º.** Con 6 favoritos, X sobre una séptima fila → deny visual, sin
   cambios en la lista.
6. **Scroll.** El stick acelera y decae con inercia; el D-pad da pasos con
   auto-repeat; los extremos rebotan; la fila se alinea sola al detenerse.
7. **Búsqueda.** En desktop, teclear filtra incrementalmente y `Escape` limpia y
   luego sale; con el filtro vacío no se ve caja de búsqueda. En gamepad no
   aparece nunca.
8. **Acciones.** A abre la app y sale del drawer; X alterna favorito con haptic y
   estrella animada; B vuelve; hold de hombro + stick arrastra la fila a un slot.
9. **Favorito offline.** Salir del nivel que registra una app favorita: el dial la
   sigue mostrando marcada offline, y `relevance()` no la hace crashear.
10. **Frescura.** Registrar/desregistrar una pantalla con el modo HUD abierto
    reconstruye la lista sin perder el foco.
11. **Determinismo.** Un replay que abre una app por el filtro reproduce
    `open_screen(id)` igual que en LIVE (el filtro en sí no está en el stream y no
    cambia el resultado).

## Open Questions

1. **Deny del 7º favorito vs. reemplazo.** El spec dice deny (la curaduría es
   explícita). La alternativa es "reemplaza al menos relevante/usado", que es más
   fluido pero le quita al jugador la decisión. ¿Se queda en deny?
2. **Agrupado por inicial** ¿siempre visible, o solo cuando la lista pasa de N
   filas (p. ej. 8)? Recomendado: solo cuando pasa de N, para que hoy no agregue
   ruido.
3. **`HudMenuChrome.gd`** (FD-306 §1) es una propuesta de refactor para que el
   drawer y el dial compartan el mapeo de botones. Si no se aprueba, el drawer
   duplica ese mapeo.
