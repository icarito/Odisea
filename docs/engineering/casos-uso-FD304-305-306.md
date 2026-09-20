# Casos de uso — FD-304 / FD-305 / FD-306 (verificados contra `main`)

**Fecha:** 2026-09-20
**Base:** `origin/main` @ `e58bc4c5` (FD-304, FD-305, FD-306 = **Implemented**)
**Archivos leídos:** `HudModeOverlay.gd` (1589), `SuitOSDrawer.gd` (341), `RadialSelectorV2.gd` (872),
`CryoPodsHUDable.gd` (143), `test_hud_drawer.gd` (250), `SuitOS.gd` (496), `InputDataV2.gd`,
`InputProviderV2.gd`, `project.godot`.

> **Corrección:** la primera versión de este documento dijo que las FDs no estaban implementadas.
> Falso: se leyó la rama de trabajo (`feature/FD-309`), no `main`. Todo lo de abajo está verificado
> en el código que sí está mergeado.

---

## 1. Mapa de entrada real (el contrato del que cuelga todo)

| Acción | Teclado | Mouse / touch | Gamepad |
|--------|---------|---------------|---------|
| `hud_mode` | **Tab** | botón virtual HUD (móvil) | **Y** = botón 3 |
| `hud_slot_1..4` | **1 2 3 4** | — | **L1**=4, **L2**=6, **R1**=5, **R2**=7 |
| `hud_nav` (cruceta) | — | — | **D-pad** arriba=12, abajo=13 |
| A (cara) | **C** (`crouch`) | clic sobre el botón del widget | botón **0** |
| B (cara) | **Espacio** (`jump`) | — | botón **1** |
| X (cara) | **F** (`interact`) | — | botón **2** |
| Apuntar el dial | **WASD** (`move_vec`) | movimiento del mouse | **stick izquierdo** |
| Confirmar | **Enter** (`ui_accept`) | clic / tap | **A** |
| Cancelar | **Esc** (`ui_cancel`) | clic fuera | **B** o **X** |
| Arrastrar | — | hold + arrastrar | **hombre + stick** |

Notas del código:
- Los botones de cara se leen del stream (`FACE_FIELDS = {a: crouch, b: jump, x: interact}`), no de un
  mapa nuevo. **Y = `hud_mode`**.
- La leyenda de botones solo se dibuja **si hay un mando conectado**
  (`if Input.get_connected_joypads().empty(): return`).
- `hud_nav` sale de `camera_up`/`camera_down`, que **solo tienen binding de mando**.
- **No hay manejo de rueda del mouse** (ni en el dial ni en el drawer).

---

## 2. Casos de uso

### A. Entrar y salir del modo HUD

**U1 — Entrar.**
- Teclado: **Tab** → mundo en pausa, HUD a la vista.
- Mando: **Y** → igual.
- Móvil: botón virtual del HUD → igual.
- *Esperado:* los tres entran. Con el dial abierto, Tab **tap** cierra y sale.

**U2 — Salir.**
- Teclado: **Tab** o **Esc** → vuelve al juego.
- Mando: **Y** o **B** → vuelve.
- *Esperado:* los tres salen. Con el dibujante cerrado y el mundo pausado, esto siempre sale del modo HUD.

**U3 — Salir desde una pantalla abierta.**
- Cualquier dispositivo: **Tab/Y** (botón del HUD) vuelve al jugador; si la pantalla declara
  `hud_gamepad_actions()`, **B/X** también salen.

### B. El dial (radial)

**U4 — Abrir el dial.**
- Teclado: **Tab tap** → abre el radial (si no hay pantalla abierta).
- Mando: **Y tap** → igual. **Y hold** → también (`Gesture.HOLD` → `_begin_hold_radial(-1)`).
- *Esperado:* el dial abre con los favoritos ordenados por relevancia.

**U5 — Apuntar.**
- Teclado: **WASD** → el sector apuntado se marca (solo si no se movió el mouse antes).
- Mouse: **movimiento** → apunta acumulando el delta (`mouse_delta_accum`).
- Mando: **stick** → apunta; soltar el stick devuelve al centro (nada marcado).
- *Esperado:* los tres apuntan. **Este es el caso que desmiente el "hueco H1" de la versión previa:
  el dial sí se navega con teclado (WASD).**

**U6 — Confirmar.**
- Teclado: **Enter**. Mouse: **clic** sobre el sector (o clic con algo apuntado). Mando: **A**.
- *Esperado:* los tres abren/ejecutan lo elegido, con haptic (si hay mando) y flash del sector.

**U7 — Cancelar.**
- **Esc** / clic fuera / **B** o **X** → cierra el dial y sale del modo HUD.
- *Esperado:* los tres. Soltar el stick en el centro **también** cierra sin elegir (no elige nada).

**U8 — Cruceta (solo mando).**
- **D-pad arriba/abajo** → recorre el arco en pasos, con auto-repeat a 400 ms.
- Teclado: **no hay equivalente** (ver Hueco 3).

**U9 — Hub "…".**
- Con el stick/WASD al centro, el hover es el hub (no `NONE`) y se dibuja.
- **Soltar** con el hub marcado → cierra sin abrir el drawer.
- **A** (mando), **clic** (mouse) o **tap** (dedo) → abre el drawer.
- *Esperado:* las tres formas de confirmar abren; soltar, no.

**U10 — Sin pantallas.**
- Cualquier dispositivo: tap de `hud_mode` con cero pantallas registradas → muestra "SIN PANTALLAS";
  el siguiente tap sale.

### C. La pantalla (widget)

**U11 — Abrir la pantalla de un slot.**
- Teclado: **1–4** (tap) → abre esa pantalla. Mando: **L1/L2/R1/R2** (tap). Mouse: clic en el widget.
- *Esperado:* los tres abren la misma pantalla.
- Si el slot está **vacío**, tap del hombro/tecla abre el dial; **hold** abre el dial fijado a ese slot.

**U12 — Cerrar la pantalla.**
- Misma tecla/hombro otra vez, o **Tab/Y**.

**U13 — Accionar el widget (botones internos).**
- Mouse: clic. Teclado: foco GUI + **Enter**. Mando: **A/B/X** según lo que declare `hud_gamepad_actions()`.
- *Esperado:* los tres accionan; el `widget_snapshot()` refleja el cambio en el mismo frame.

**U14 — Acorde rápido (sin abrir la pantalla).**
- Mando: `hold de un hombro sobre un slot con pantalla + A` → ejecuta la operación primaria
  (`confirm: true`) sin abrir nada; el dial **no** se cierra.
- Mouse/teclado: **no existe** (ver Hueco 1).

**U15 — Feedback de hold.**
- Cualquier dispositivo con hombro: el marco se rellena 0→400 ms; al completar, anillo cerrado +
  haptic + entra el radial. Soltar antes: se vacía, no pasa nada.

### D. El drawer "…"

**U16 — Abrir.** Con el hub marcado y confirmado (A / clic / tap). El dial se retrae y el drawer entra.

**U17 — Orden alfabético.** Las filas salen alfabéticas, sin acentos ("Área" va con la A).
Registrar/desregistrar una pantalla con el drawer abierto reconstruye la lista **sin perder el foco**.

**U18 — Scroll.**
- Mando: **stick** (velocidad con inercia, topes elásticos, snap al detenerse) + **D-pad** (pasos a 400 ms).
- Mouse: **arrastrar** una fila (levanta el fantasma). **Rueda: no hace nada** (Hueco 2).
- Teclado: **WASD** mueve la lista con la misma física (el teclado alimenta `move_vec`).
- *Esperado:* los tres llegaron al mismo `drive()`.

**U19 — Abrir una app.** Mando **A**. Mouse: **clic en la fila** (fuera de la estrella).
Teclado: **C** (= `crouch` = la A del mando).

**U20 — Favoritear.** Mando **X**, o **clic sobre la estrella** (margen izquierdo de la fila).
Teclado: **F** (= `interact` = la X del mando). Con 6 favoritos, la séptima da deny (haptic +
flash ámbar + "RADIAL LLENO").

**U21 — Volver.** Mando **B** → vuelve al dial (o al juego si se entró directo). Teclado: **Espacio**
(= `jump` = la B del mando) hace lo mismo; **Esc** sale del modo HUD entero, **no** vuelve al dial.
Mouse: **no hay ruta de salida** salvo Tab/Y (Hueco 5).

**U22 — Arrastrar una fila a un slot.** Mando: hombro sostenido + stick. Mouse: hold sobre la fila
+ arrastrar. Teclado: **tecla del slot sostenida + WASD** (el arrastre por hombro lee `move_vec`,
que el teclado también alimenta).

**U23 — Favorito offline.** Salir del nivel que registra un favorito: la fila sigue, marcada OFFLINE,
y `relevance()` no crashea.

### E. Slots y arrastre

**U24 — Reasignar un slot.** Mando: hombro + stick con el cursor virtual. Mouse: hold + arrastrar.
*Esperado:* el widget queda re-pinneado en el slot destino; soltar fuera lo devuelve.

**U25 — Vaciar un slot.** Arrastrarlo a la zona de reciclaje (mouse o mando).

**U26 — Drag de la pantalla abierta.** Mando: hombro + stick; el cursor virtual se mueve.
Mouse: arrastrar desde el **asa** de la vista.

### F. Criocápsulas (FD-304 §10)

**U27 — Registrar la bahía.** `CryoPodsHUDable` aparece en el registry de SuitOS en el domo.
Su widget lista el roster (28 cápsulas, declarativas + relleno vacío).

**U28 — Navegar el roster.** Con la pantalla abierta, la **cruceta** recorre las cápsulas
(`select`); **A** escanea la enfocada (`scan`).

**U29 — Relevancia viva.** Con el circuito de criocoolant en FALLO, la bahía sube al primer sector
del dial; cada cápsula ocupada pasa a ALERTA y su fila se marca ALERTA.

**U30 — Determinismo.** Un replay reproduce un guion de hombros + botones de cara igual que en LIVE.

---

## 3. Matriz de paridad (resultado)

| # | Capacidad | Teclado | Mouse/Touch | Gamepad |
|---|-----------|---------|-------------|---------|
| 1 | Entrar / salir del HUD | ✅ | ✅ (móvil) | ✅ |
| 2 | Abrir / cerrar el dial | ✅ | ✅ | ✅ |
| 3 | Apuntar el dial | ✅ WASD | ✅ | ✅ stick |
| 4 | Confirmar / cancelar | ✅ | ✅ | ✅ |
| 5 | Recorrer el arco en pasos | ❌ (WASD apunta, pero no hay paso discreto) | ❌ | ✅ D-pad |
| 6 | Abrir pantalla de slot | ✅ 1–4 | ✅ clic | ✅ L1/L2/R1/R2 |
| 7 | Accionar el widget | ✅ | ✅ | ✅ A/B/X |
| 8 | **Acorde rápido** | ❌ | ❌ | ✅ |
| 9 | Abrir el drawer | ✅ (WASD→hub→Enter) | ✅ | ✅ |
| 10 | **Navegar el drawer** | ✅ WASD | ✅ arrastre | ✅ stick+D-pad |
| 11 | **Usar / favoritear en el drawer** | ✅ C / F | ✅ clic | ✅ A / X |
| 12 | **Salir del drawer** | ✅ Espacio (B); Esc sale del HUD | ❌ | ✅ B |
| 13 | Scroll con rueda | — | ❌ | — |
| 14 | Drag / drop de slots | ✅ slot + WASD | ✅ | ✅ |
| 15 | Criocápsulas (roster, scan) | ❌ (la cruceta es de mando) | ✅ clic | ✅ cruceta+A |

---

## 4. Huecos reales (verificados en código, no supuestos)

| # | Hueco | Evidencia | Gravedad |
|---|-------|-----------|----------|
| **1** | **El acorde solo existe en mando.** `_drive_hud_buttons` lee los botones de cara del stream; el mouse no tiene hombros y no hay gesto alternativo. | `HudModeOverlay.gd:1270` | Media — es una capacidad exclusiva del mando; aceptable, pero hay que decirlo |
| **2** | **No hay scroll con la rueda.** Cero referencias a `BUTTON_WHEEL_*`. | `grep WHEEL` = vacío | Baja |
| **3** | **La cruceta solo existe en mando.** `hud_nav` sale de `camera_up`/`camera_down`, que no tienen binding de teclado. | `InputProviderV2.gd:263-268` | Baja |
| ~~4~~ | ~~El drawer no es usable con teclado~~ **FALSO.** Los “botones de cara” salen del stream (`crouch`/`jump`/`interact`), y el teclado los alimenta: **C** abre, **F** favoritea, **Espacio** vuelve, **WASD** desplaza, **1–4** arrastran. Usable, pero con una ergonomía que nadie eligió. | `_face_edges` → `FACE_FIELDS` → `Input.is_action_pressed` (incluye teclado) | **Resuelto: no es hueco** |
| **4bis** | **Faltan las flechas.** `ui_up/ui_down/ui_left/ui_right` existen en el mapa de entrada y **ningún** archivo del HUD las lee. Son la asignación obvia para el paso discreto del arco y del drawer, y hoy no hacen nada. | `grep ui_up HudModeOverlay/SuitOSDrawer/RadialSelectorV2` = vacío | Baja (¿mejora de ergonomía?) |
| **5** | **El drawer no tiene salida con mouse.** Clic fuera de una fila → `row < 0: return`. La única salida es Tab/Y. | `HudModeOverlay.gd:1502` | Media |
| **6** | **El hub se confirma distinto según el dispositivo.** Clic/tap lo confirman; soltar el stick lo descarta. Es la decisión de FD-306 §1.1, pero es la parte más frágil del diseño. | `HudModeOverlay.gd:583-591` vs `_confirm_or_dismiss` | Media (de playtest) |
| **7** | **⚠️ `Espacio` cae en dos acciones a la vez dentro del dial.** `ui_select = Espacio` (override del proyecto) y `jump = Espacio` (física 32); además el `ui_accept` built-in de Godot 3 incluye Espacio y JoyButton 0 (A). Consecuencia: al pulsar Espacio con el dial abierto, `_input` puede llamar `confirm()` y `_drive_hud_buttons` puede llamar `_dismiss_radial()` **en el mismo frame**. Cuál gana depende del orden input/physics → el jugador no puede saber qué hace Espacio. **Fix: quitar Espacio de `ui_select`** (que quede Enter, y que `ui_accept` sea la puerta de confirmar en mando con A). | `ui_select=32` + `jump` phys 32; `HudModeOverlay.gd:589` vs `:1264` | **Alta (sospecha, 10 s de verificación)** |
| **8** | **Start no está mapeado.** `hud_mode` = Tab + Y (botón 3). El Start del mando (botón 7 en SDL; el proyecto ya usa el back/select = 11 en `ui_cancel`) no abre nada. Un jugador de mando espera Start para el menú/HUD. | input map: sin `button_index:7` en ninguna acción | Media |
| **9** | **JoyButton crudo fuera del InputMap.** `VirtualMouse.gd:294` mapea A/B→clic con `JOY_BUTTON_0/1` crudos (deliberado, con comentario: no depende de `ui_accept`). `ControlSteering.gd:71-74` (addon flightsim) usa `is_joy_button_pressed(joy_id, 4/5)` — addon de terceros. `OYS_Console.gd:693` es debug. `RemoteProtocol/RemoteControlHome` pasan el evento crudo a propósito (el host re-mapea). | `git grep JOY_BUTTON` | Media — los que importan son VirtualMouse (decidir conscientemente) y los addons (no tocar) |

**Resumen por dispositivo (corregido):**
- **Mando:** paridad completa. Es el dispositivo para el que se diseñó todo el FD-304.
- **Mouse/touch:** todo salvo el acorde (1) y la rueda (2); falla la salida del drawer (5).
- **Teclado:** cubre HUD, dial **y drawer**. Lo que le falta es ergonomía (4bis: flechas) y el paso
discreto del arco, y arrastra la colisión de Espacio (7).

---

## 5. Qué probar primero (orden barato → caro)
1. **Hueco 7 — U6 con teclado:** abrir el dial y pulsar **Espacio**. Hay que ver si la pantalla abre,
   si el HUD sale, o si las dos cosas se pelean. Con **Enter** no debe pasar nada raro. Es una prueba
   de 10 segundos y decide si hay que tocar algo.
2. **U4→U9** (dial + hub): es lo que más se rompe en playtest y lo que más cambió (FD-306 §1.1).
3. **U16–U21** (drawer) con **mando** y con **teclado**, para ver si la ergonomía `C`/`F`/`Espacio`
   es tolerable o si hay que sumar flechas (4bis).
4. **U14** (acorde) y **U24** (drag a slot): son las capacidades exclusivas del mando.
5. **U27–U29** (criocápsulas): es lo único que toca contenido de escena.
6. **U30** (replay): al final, para no contaminar el resto.

---

## 6. Correcciones recomendadas (revisión de coherencia 2026-09-20)

Revisión pedida por Sebastián. Solo lo que tiene evidencia dura en `main` @ `e58bc4c5`.

### 6.1 Input map (`project.godot`) — orden de código
1. **Quitar Espacio de `ui_select`.** `ui_select` (scancode 32) y `jump` (phys 32) son la misma tecla:
   Espacio confirma y cancela a la vez en el dial (Hueco 7). Dejar `ui_select` = Enter; `ui_accept`
   (built-in: Enter + A) queda como confirmar universal.
2. **Mapear Start.** Añadir JoyButton 7 (start) a `hud_mode` (o crear `ui_enter` con Start + Enter)
   para que el menú/HUD se abra con Start, como espera cualquier jugador de mando. Hoy solo Tab/Y.
3. **Flechas vivas.** `ui_up/ui_down/ui_left/ui_right` son built-in y **ningún** archivo del juego las
   lee (`git grep` = solo ejemplos de addons FX). Son la asignación natural del paso discreto del arco
   y del drawer.

### 6.2 Código del HUD — refactor y buenas prácticas
4. **`InputProviderV2`:** que `hud_nav` unifique D-pad **+ flechas** (`ui_up`/`ui_down`), para que el
   teclado tenga paso discreto (Hueco 3 se cierra solo).
5. **`SuitOSDrawer._feed_dpad` / `drive`:** alimentar el paso también desde `ui_up`/`ui_down`, no solo
   desde `hud_nav`.
6. **`HudModeOverlay._drive_nav`:** misma fuente unificada; hoy lee `input.hud_nav` únicamente.
7. **Salida del drawer con mouse (Hueco 5):** en `_drawer_pointer_input` (L1502), `if row < 0:` hoy
   hace `return`; que cierre el drawer (volver al dial o salir del HUD). Una línea.
8. **Rueda del mouse (Hueco 2, opcional):** `BUTTON_WHEEL_UP/DOWN` → `drive()` del drawer. Baja prioridad.

### 6.3 JoyButton crudo → input actions (decisión consciente, no barrida)
9. **`VirtualMouse.gd:294`:** mapeo crudo A/B→clic con comentario explícito (no depende de `ui_accept`).
   Dejarlo como está o leer `ui_accept`/`ui_cancel` con fallback; NO borrar el comentario sin decidir.
10. **Addons (no tocar):** `simplified_flightsim/ControlSteering.gd` (L1/R1 crudos) y ejemplos de FX.
11. **Debug y red (legítimos):** `OYS_Console` joy_debug y `RemoteProtocol`/`RemoteControlHome`
    necesitan el evento crudo para re-mapeo en el host.

**Orden de implementación sugerido:** 1 (input map) → 4–6 (flechas) → 7 (drawer mouse) → 2 (Start)
→ 8 (rueda) → 9 (decisión VirtualMouse). El 1 y el 4–6 son los que cierran huecos de dispositivo;
el resto es ergonomía.
