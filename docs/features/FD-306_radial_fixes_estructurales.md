# FD-306: Fixes estructurales del radial (hub central, orden por relevancia, iconos, escala)

**Status:** Design
**Priority:** P1
**Effort:** Medium
**Created:** 2026-09-19
**Completed:** -
**Parent:** FD-296 F3 (HudModeOverlay / RadialSelectorV2) · FD-304 (interfaz diégetica con gamepad) · FD-305 (drawer y favoritos)
**Relacionadas:** FD-043 (RadialScatter — prop tool, sin relación funcional)

## Problem

`RadialSelectorV2` funciona y tiene buenos cimientos (geoemtría por ángulo, sin
puntero de OS, `NONE = -1`, readout animado, apuntado acumulado), pero **fue
diseñado para elegir entre pocas opciones** y hoy se le pide ser la barra de
acceso del traje. Cuatro huecos concretos, todos verificados en el código:

**1. El centro es una zona muerta que además va a dejar de serlo.**
`HudModeOverlay` configura `dead_zone = AIM_DEAD_ZONE (40 px)`, explícitamente
para que soltar el stick en el medio **no marque nada**. FD-305 pone el item
`...` **en ese mismo centro**. Hoy el código tiene una regla ("el medio no
elige") que el diseño nuevo necesita invertir para un solo item.

**2. El orden de las opciones no significa nada.**
El arco se llena desde `_screen_ids = suit_os.get_registered_screens()`
(`HudModeOverlay.gd:141`), que devuelve `_screens.keys()` — **orden de registro
de escena**. El primer sector del dial puede ser cualquier cosa, y cambia según
el orden en que cargaron las escenas.

**3. `relevance()` está construido y sin consumidor en el juego.**
Está implementado en `HUDableComponent` y en las 5 pantallas
(`FlashlightScreen:60`, `MultiToolScreen:45`, `CargolScreen:45`,
`SystemStatusScreen:39`, `HoloTerminalHUDable:310`), con lógica real (sube con
batería baja, con estado `FALLO`, etc.). **El único consumidor es el control
remoto** (`SuitOSRemoteBridge.gd:113`). El juego lo ignora por completo.

**4. El dial solo dibuja texto, y no hay iconos.**
`set_options(labels)` crea `Label`s con `option_size = 230×104 px`
(`RadialSelectorV2.gd:136`). `hud_screen_icon` está declarado en
`HUDableComponent.gd:11` y **no se usa en una sola línea del juego** (solo en un
test). Con 6 opciones de texto solo, el dial es lento de leer.

Y el límite geométrico que los agrava: `ARC_SPAN = PI` (media vuelta) con
`_step() = ARC_SPAN / (n - 1)`. Con 4 opciones son 60° de arco disponible por
sector; con 6, 36°; con 10, 20° — **los sectores de 230 px se solapan mucho antes
de eso**.

## Solution

### 1. El hub central: de zona muerta a item

`dead_zone` (dial pixels, "dentro no se marca nada") se **reemplaza** por un
**item central con radio propio**:

```
const HUB_RADIUS := 40.0        # el radio que hoy tiene la zona muerta
const HUB_HIT_RADIUS := 34.0    # hitbox del hub, algo menor que su dibujo
```

- Dentro de `HUB_HIT_RADIUS` del centro, el hover es **el hub** (índice propio,
  `HUB_INDEX`), no `NONE`.
- El hub se **dibuja** (círculo con el "..." y su propia iluminación de hover),
  para que la zona tenga dueño visible y no parezca un agujero.
- **El hub es visible pero no seleccionable por accidente**: ver §1.1.
- Se conserva `hub_epsilon` (6 px) como jitter guard: dentro de esos 6 px el
  ángulo no se recalcula, pero el índice sigue siendo el hub. No hay estado
  "nada marcado" en el centro: hay hub.

#### 1.1 Riesgo aceptado y su mitigación

Poner el hub en el centro **elimina el gesto "soltar al centro = no elegir"**,
que era la red de seguridad contra selecciones accidentales. Se acepta
explícitamente (decisión de Sebastián, 2026-09-19) con dos mitigaciones:

- **El hub no se confirma por soltar.** Soltar con el hub marcado **no** abre el
  drawer: cierra el dial sin elegir (equivalente al comportamiento seguro
  anterior). El drawer se abre con **A** (confirmar) o con un **tap sobre el hub**
  (mouse/touch). Así, el movimiento reflejo de "volver el stick al centro y
  soltar" sigue sin consecuencias.
- **Requiere confirmación explícita**: como el resto de las opciones, el hub
  obedece `_confirm_or_dismiss()` — marcar no es elegir.

Esta es la parte del spec que más fácil se rompe en playtest: si abrir el drawer
sin querer se vuelve común, la mitigación pasa a "el hub solo se confirma con tap,
nunca soltando".

### 2. Orden por relevancia

El arco se ordena por `relevance(context)` **descendente**, con desempate estable:

```
order = sort(favorites, by: [-relevance(context), title_nocase])
```

- El **título como desempate** es obligatorio: sin él, dos pantallas con la misma
  relevancia (típicamente 0.0 las dos) cambian de lugar entre frames, porque el
  orden de un sort no es estable en GDScript. Es el mismo tipo de bug que el
  comentario de `reevaluate_slots()` ya documenta para `widget_changed`.
- `SuitOS` ya tiene el contexto vivo (`_context`, `update_context_key()`,
  `set_context()`) y ya lo pasa al control remoto. **No hace falta infraestructura
  nueva**: se expone `get_favorites_ordered(context)` y el overlay lo consume.
- `relevance()` se llama **una vez por apertura del dial**, no por frame. Las
  relevancias de hoy son baratas (comparan floats y strings), pero el dial no debe
  reevaluar mientras está abierto o las opciones se reordenarían bajo el dedo.
- **El dial puede crecer al revés**: relevancia alta va al **primer** sector (6 en
  punto), que es el que el pulgar encuentra sin mirar. Eso es exactamente lo que
  se quiere de una sugerencia.

### 3. Iconos en las opciones

`set_options(labels)` pasa a `set_options(items)`, donde cada item es
`{ id, label, icon, enabled }`:

- La opción dibuja **icono + etiqueta**, no solo texto. Con esto `hud_screen_icon`
  (declarado y muerto desde FD-296) entra en uso.
- **Compatibilidad:** `set_options` acepta un `Array` de `String` (como hoy) y lo
  envuelve en items sin icono. Así `ElevatorFloorSelector` y los tests existentes
  siguen funcionando sin cambios.
- Sin icono declarado → se dibuja solo el texto, centrado (el layout actual). El
  icono es aditivo, nunca un requisito.
- `option_size` sube en consecuencia solo si el icono lo pide; el hitbox por
  sector sigue siendo el arco (`slice_at()` por ángulo), así que los iconos no
  cambian la mecánica de selección.

### 4. Escala: el dial no pagina, el drawer absorbe

Con el tope de **6 favoritos** (FD-305 §2) el arco queda en 36° por sector, que es
el límite práctico de `ARC_SPAN = PI`. Decisión: **el dial no implementa
paginación ni anillos concéntricos** — la lista completa vive en el drawer, que
está diseñado para listas largas.

Esto convierte el problema de escala en un problema de **tope**, y el tope ya está
resuelto con el deny del 7º favorito. Lo que sí hay que endurecer:

- **Degradación entre 1 y 6.** `_step()` divide por `(n - 1)`: con **n = 1** hay
  división por cero. El overlay hoy lo esquiva (`_screen_ids.size() <= 1` va
  directo), pero con el hub + 1 favorito son 2 items. Verificar los bordes
  n = 1 (solo el hub) y n = 2.
- **Con 7 items (hub + 6 favoritos)** los sectores miden 180/6 = 30°: legible.
  Ese es el peor caso real, no 10.
- Si algún día se sube el tope, la forma de escalar es **carrusel circular**, no
  anillos (los anillos hacen ambiguo el apuntado radial). Queda en backlog.

### 5. Frescura de la lista

`HudModeOverlay` lee `_screen_ids` **una sola vez en `_ready()`**
(`HudModeOverlay.gd:141`) y no escucha `screen_registered` / `screen_unregistered`
(los signals existen en `SuitOS.gd:20-21`). Hoy es inofensivo porque el overlay es
efímero. FD-305 lo vuelve un bug real al agregar el drawer. **La suscripción y la
reconstrucción de la lista pertenecen a este FD** (es un fix del radial) y FD-305
solo hereda el resultado.

### 6. Animaciones

Ya especificadas en **FD-304 §8** (apertura en cascada, pulso idle, hover +4 %,
flash de confirmación, retract de cierre). **No se duplican acá.** Este FD solo
agrega una: el **hub respira** con el mismo pulso idle del anillo, pero a mitad de
amplitud, para no robarle foco al arco.

### 7. Chrome compartido (propuesta de refactor)

El mapeo de botones y las leyendas las necesitan el dial y el drawer (FD-305 §3.5).
Propuesta: extraer a `core_v2/ui/hud/HudMenuChrome.gd` lo común
(`HOLD_MSEC`, `DRAG_HOLD_MSEC`, leyenda de botones, estilo de pastilla,
`hud_gamepad_actions()` → leyenda). **No es un refactor gratuito**: son dos vistas
nuevas (drawer, hub) que ya justifican el punto medio, y evita que el mapeo de
FD-304 viva duplicado en dos archivos que van a divergir. Si se descarta, el
drawer duplica el mapeo a conciencia.

## Considered Options

- **Hub central como item (elegida).** Es lo que pediste y es coherente con "el
  centro es la puerta al resto". Contra: pierde la red de seguridad del centro,
  mitigada en §1.1.
- **Paginación del dial.** Descartada por Sebastián (FD-305 Q6): agrega un eje de
  navegación y el jugador puede olvidar que hay más páginas. El drawer resuelve el
  caso largo mejor que cualquier paginación.
- **Anillos concéntricos.** Descartada: vuelve ambiguo el apuntado radial (¿qué
  anillo?) y empeora el peor caso en vez de mejorarlo.
- **Carrusel circular.** Técnicamente la solución que escala mejor, pero es la más
  cara (geometría móvil, entrada/salida de sectores, hit-testing continuo). Con el
  tope de 6 no hace falta. Backlog.
- **Ordenar por uso reciente en vez de `relevance()`.** Más barato (un contador),
  pero `relevance()` ya está implementado en 5 pantallas con lógica contextual
  real (batería baja, fallo de sistema) y hoy está **muerto**. Usarlo es gratis y
  es más expresivo que "lo que abriste últimamente".

## Fuera de scope

- Paginación, anillos o carrusel (§4, backlog).
- Subir el tope de 6 favoritos.
- Iconos para el resto del HUD fuera de las opciones del dial.
- Retraducir los títulos de las opciones (i18n ya cubierto por FD-303; los
  `screen_title()` son estáticos por pantalla).

## Files to Modify

- `core_v2/ui/radial/RadialSelectorV2.gd` — `HUB_RADIUS`/`HUB_HIT_RADIUS`,
  `HUB_INDEX`, hub como item, `set_options(items)` con icono, borde n = 1
  (modificar).
- `core_v2/ui/hud/HudModeOverlay.gd` — hub marcado/confirmado, orden por
  relevancia al abrir, leyenda de botones, suscripción a
  `screen_registered`/`screen_unregistered` (modificar).
- `core_v2/autoloads/SuitOS.gd` — `get_favorites_ordered(context)` (modificar;
  los favoritos en sí son de FD-305).
- `core_v2/ui/hud/HudMenuChrome.gd` — **nuevo** (§7, sujeto a aprobación).
- `core_v2/tests/test_radial_selector.gd` — hub, iconos, bordes n = 1/2/7
  (modificar).
- `core_v2/tests/test_hud_mode.gd` — orden por relevancia estable, lista que se
  reconstruye con el dial abierto (modificar).
- `docs/features/FEATURE_INDEX.md` — alta de FD-306 (modificar).

## Verification

1. **Hub.** Con el stick en el centro, el hover es el hub (no `NONE`); el hub se
   dibuja. **Soltar** con el hub marcado cierra el dial sin abrir el drawer.
   **A** o **tap** sobre el hub sí lo abre.
2. **Sin zona muerta accidental.** Un stick que pasa por el centro camino a
   apuntar otro sector no selecciona el hub ni abre el drawer.
3. **Orden estable.** Abrir el dial dos veces con las mismas relevancias da el
   mismo orden; con relevancias empatadas el desempate es alfabético y no cambia
   entre frames.
4. **Relevancia viva.** Con la linterna por debajo del umbral de batería, su
   opción sube al primer sector.
5. **Iconos.** Una pantalla con `hud_screen_icon` lo muestra junto al título; sin
   icono, el layout es el de hoy. `set_options(["a","b"])` (strings) sigue
   funcionando → `ElevatorFloorSelector` intacto.
6. **Bordes.** n = 1 (solo hub), n = 2 (hub + 1 favorito) y n = 7 (hub + 6
   favoritos) no crashean ni dividen por cero y se leen sin solape.
7. **Frescura.** Registrar una pantalla con el modo HUD abierto la agrega al dial
   y al drawer sin perder el foco; desregistrarla la quita.
8. **Sin regresión.** `test_radial_selector.gd` pasa en sus 8 casos actuales
   (`six_three_and_twelve`, `left_half_is_not_used`, `needle_tracks_the_car`,
   `committed_pick_drops_the_focus`, etc.).

## Open Questions

1. **`HudMenuChrome.gd`** (§7): ¿se aprueba el refactor o el drawer duplica el
   mapeo de botones? Cambia el tamaño de este FD, no su diseño.
2. **El hub con mouse.** ¿El hub se confirma también con **clic** (no solo tap) si
   el puntero está encima? Recomendado que sí, para que mouse y touch se sientan
   iguales.
3. **Iconos: ¿de dónde salen?** El campo existe pero ninguna pantalla tiene textura
   asignada. Se pueden (a) dejar vacíos y usar iconos cuando el arte llegue,
   (b) un set mínimo placeholder por tipo de pantalla. Recomendado (a) + un icono
   por defecto, para no frenar el FD por arte.
