# OdiseaOS — Manual del Tripulante

**Documento:** ARK-OS-001 · **Revisión:** 1 · **Clasificación:** Operación rutinaria
**Destinatario:** personal de mantenimiento, nivel 2 y superiores
**Emitido por:** Odisea, sistemas de a bordo

---

> **Nota para quien desarrolla, no para quien lo lee en ficción.**
>
> Este documento es **la especificación de la interfaz**. Está escrito en voz de a bordo
> porque esa restricción es el instrumento de diseño: *si una función no se puede
> explicar en una línea de este manual, no pertenece a la interfaz.* Lo que no entró
> está en el **Apéndice A**, y esa lista es trabajo pendiente, no adorno.
>
> Reemplaza a `docs/engineering/gui-map-2026-09-20.md` como referencia de intención; el
> mapa queda como apéndice técnico. Todo lo afirmado acá está verificado contra `main`
> `be301b06` (2026-09-20) y cada sección dice dónde. **Regla de mantenimiento: si el
> código cambia de forma que invalida una sección, se actualiza en el mismo PR.**

---

## 0. Antes de empezar

Usted recibió este manual porque se le asignó una cápsula y, con ella, un traje.

El traje trae OdiseaOS instalado. No se puede desinstalar. No requiere entrenamiento
previo y no se ofrece ninguno. Lea las nueve páginas que siguen; el sistema asume que
lo hizo.

Odisea no responde consultas sobre este documento.

---

## 1. Qué es OdiseaOS

OdiseaOS es el sistema que le muestra lo que la nave sabe.

No controla la nave. No toma decisiones por usted. Muestra **pantallas**: una por cada
cosa del Arca que tenga algo que reportar — su linterna, su multi-herramienta, el dron
de carga asignado, el estado del domo, cada criocápsula.

Una pantalla tiene siempre las mismas cuatro propiedades, y esto no cambia nunca:

| Propiedad | Qué significa |
|---|---|
| **Identidad** | Un nombre que no cambia. Si usted guarda una pantalla y vuelve tres turnos después, es la misma. |
| **Título** | Cómo se llama en su idioma. |
| **Lectura** | Lo que reporta ahora mismo. Siempre completa: OdiseaOS no envía diferencias, envía el estado entero. |
| **Operaciones** | Lo que usted puede hacerle. La mayoría de las pantallas no tiene ninguna: solo informan. |

> *Contrato:* `core_v2/components/HUDableComponent.gd`. La identidad es `screen_id()` y
> es **contrato de guardado**: si cambia, se rompe la persistencia de slots y el estado
> del terminal auxiliar. La lectura es `widget_snapshot()` y es **data pura
> serializable** — nunca nodos, `NodePath` ni texturas. Esa es la línea roja que hace
> funcionar el terminal auxiliar (§8).

---

## 2. Las dos superficies

OdiseaOS es **uno**, y aparece en dos lugares. Puede distinguirlos sin leer nada:

| | **El traje** | **A bordo** |
|---|---|---|
| Qué es | lo que usted lleva puesto | terminales fijas del Arca |
| Color | **cian** | **verde fósforo**, con **ámbar** para lo que requiere atención |
| De quién es | suyo | de la nave |
| Se apaga | cuando usted se quita el traje | nunca |

**La regla es el color.** Cian significa "esto es suyo y viaja con usted". Verde
significa "esto es del Arca y se queda donde está".

Cuando usted guarda una pantalla de a bordo en un slot del traje, verá **marco cian con
contenido verde**: es una lectura remota de un sistema de la nave, traída a su casco.
El Arca le presta el dato; no le presta el terminal.

> *Estado:* la superficie de a bordo existe (`core_v2/ui/retro/`, tema en
> `RetroOS.tres`) y ya está puenteada: `DebugConsoleManager` la registra como pantalla
> de `SuitOS` y `HoloTerminalV2:533` la monta dentro de un terminal del mundo. Lo que
> falta es declarar los colores como tokens compartidos en vez de literales sueltos, y
> unificar la marca. Ver Apéndice A, punto 7.

---

## 3. Las cuatro piezas

### 3.1 La pantalla
Una unidad de contenido con identidad estable (§1). Existe mientras exista su fuente.

### 3.2 El widget
La cara chica de una pantalla: lo que se ve sin abrirla. Un widget no piensa. Muestra la
última lectura y nada más.

### 3.3 Los slots
Usted tiene **cuatro**. Dos a la izquierda, dos a la derecha. Están numerados 1 a 4.

**Los llena usted. Solamente usted.** OdiseaOS no decide qué le conviene ver: puede
ordenar el dial por urgencia, pero **no mueve nada a un slot por su cuenta**. Un slot
vacío es un contorno vacío, no una falla.

El slot 1 viene con su linterna. Puede cambiarlo.

Una pantalla no puede ocupar dos slots. Si la guarda en uno nuevo, sale del anterior.

> *Contrato:* `core_v2/ui/hud/HudSlots.gd` (`COUNT = 4`, `pin_to` garantiza la
> exclusividad) y `SuitOS.gd:43` (`DEFAULT_PINS`). **Esta sección declara resuelto el
> drift #1**: el modelo "Slot A automático por relevancia + Slot B fijado" de las
> versiones viejas de FD-296 **queda derogado**. `relevance()` ordena el dial y nada más.

### 3.4 El dial
El círculo que aparece al abrir OdiseaOS. Muestra **sus favoritos**, hasta seis,
ordenados por urgencia: lo que está fallando sube.

En el centro hay un **hub**, marcado `…`. Apuntar al centro no es un error ni una zona
muerta: es apuntar al hub. Soltar ahí cierra sin elegir nada. Confirmarlo abre el cajón.

Si usted tiene una sola pantalla, el dial no aparece: se abre esa. No se le va a pedir
que elija entre una cosa.

> *Contrato:* `core_v2/ui/radial/RadialSelectorV2.gd` (`HUB_INDEX := -2`,
> `HUB_RADIUS := 40.0`), tope de seis en `SuitOS.gd:47` (`MAX_FAVORITES`), atajo de una
> sola pantalla en `HudModeOverlay._open_radial():1318-1320`.

---

## 4. El cajón

El dial muestra lo que usted eligió ver seguido. El cajón muestra **todo**.

Se abre de dos maneras: **sostenga el botón del HUD** desde donde esté, o confirme el hub
`…` del centro del dial. La primera es la corta; la segunda es la que se descubre sola
cuando usted ya está mirando el dial. Las pantallas salen en orden alfabético, ignorando acentos.
Cada fila tiene una estrella: marcarla la sube al dial.

**Puede tener seis favoritos.** El séptimo se rechaza: destello ámbar y *RADIAL LLENO*.
No hay cola de espera. Saque uno antes de poner otro.

Una fila puede decir **OFFLINE** (§7). Sigue estando: el Arca recuerda la última lectura
aunque la fuente ya no esté a su alcance.

> *Contrato:* `core_v2/ui/hud/SuitOSDrawer.gd`. **Deuda conocida:** el manejo del cajón
> no vive ahí sino dentro de `HudModeOverlay.gd` — 14 funciones y 105 menciones. Ver
> Apéndice A, punto 6.

---

## 5. Los verbos

Nueve. No hay más.

| # | Verbo | Teclado | Mando | Dedo / puntero |
|---|---|---|---|---|
| 1 | **Abrir el dial** — sus favoritos | `Tab` | `Y` | botón del HUD |
| 2 | **Abrir el cajón** — todo | sostener `Tab` | sostener `Y` | sostener el botón |
| 3 | **Cerrar OdiseaOS** | `Tab` o `Esc` | `Y` o `B` | botón del HUD |
| 4 | **Apuntar el dial** | `WASD` | stick izquierdo | mover / arrastrar |
| 5 | **Confirmar** | `Enter` | `A` | tocar el sector |
| 6 | **Abrir la pantalla de un slot** | `1`–`4` | un hombro | tocar el widget |
| 7 | **Guardar en un slot** | sostener `1`–`4` | sostener un hombro | sostener y arrastrar |
| 8 | **Operar una pantalla** | `Enter` sobre el botón | `A` / `B` / `X` | tocar el botón |
| 9 | **Vaciar un slot** | arrastrar al reciclaje | arrastrar al reciclaje | arrastrar al reciclaje |

**Toque para lo que usa siempre, sostenga para lo demás.** Esa es toda la regla. Vale
para el botón del HUD (dial / cajón) y para los botones de slot (abrir / reasignar).

**El botón de un slot abre su pantalla, y si ya está en ella, la cierra.** Un botón, un
destino. Un slot vacío no tiene nada que abrir: le ofrece el dial para que lo llene.

**Mientras OdiseaOS está abierto, el Arca espera.** El mundo queda en pausa. Esto es
deliberado: la consola del traje no le pide que lea mientras algo se mueve.

> *Verificado:* `HudModeOverlay._physics_process():279-358`, `_tap_slot()` y
> `_open_drawer_direct()`. Nueve verbos, no ocho: el cajón dejó de ser un rincón del dial
> y pasó a ser un verbo propio (decisión de Sebastián, 2026-09-20).

---

## 6. Código de color

Cinco estados. Los mismos en las dos superficies.

| Color | Estado | Qué debe hacer usted |
|---|---|---|
| **Verde** | Nominal | Nada. |
| **Ámbar** | Atención | Anotarlo. Todavía no es su problema. |
| **Rojo** | Alarma | Es su problema. |
| **Turquesa** | Activo | Algo suyo está encendido: la linterna, el gloo, un señuelo. |
| **Gris** | Inactivo o sin lectura | No es una falla del sistema. Ver §7. |

El ámbar también marca un **rechazo**: cuando usted pide algo que el sistema no puede
dar (un séptimo favorito, un slot que no acepta lo que arrastra), destella en ámbar.
Ámbar nunca significa avería del traje.

> *Contrato:* `core_v2/ui/OdiseaOSTheme.gd`. Si un color de la GUI no sale de ahí, o es
> un token que falta o es un error. **Pendiente:** los widgets todavía tienen valores
> escritos a mano que hay que reemplazar por estos tokens — el rojo aparece con dos
> opacidades y `CargolWidget` mantiene una escala propia de siete colores que no
> coincide con estos cinco estados. Ver Apéndice A, punto 5.

---

## 7. Cuando dice OFFLINE

**OFFLINE no es un error.**

Significa que la fuente ya no está a su alcance: usted salió del módulo, la cápsula se
cerró, el dron se apagó. La pantalla sigue en su slot y sigue mostrando **la última
lectura conocida**, en gris.

El Arca no borra lo que ya le mostró. Si vuelve al alcance, la lectura se reanuda sola.

> *Contrato:* `SuitOS._pinned_snapshot()` marca `"source": "offline"` cuando la pantalla
> no está registrada pero hay caché. Cada widget tiene que respetarlo.

---

## 8. El terminal auxiliar

Si dispone de una unidad portátil compatible, puede emparejarla y ver **los mismos
slots** en ella.

Lo que viaja a esa unidad son **lecturas, no pantallas**. El terminal auxiliar no ejecuta
OdiseaOS: lo refleja. Por eso el Arca **no** se detiene cuando usted lo usa — la pausa
es del traje, no del sistema.

> *Contrato:* `core_v2/ui/hud/RemoteHudBackend.gd` emite las mismas señales que `SuitOS`;
> `RemoteControlHome.gd` monta el **mismo** `SuitOSWidgetHost`. El modo HUD **no** viaja.
> Esto funciona **solo** porque las lecturas son data pura. Meter un nodo en una lectura
> rompe el terminal auxiliar. Sin excepciones.

---

## Apéndice A — Lo que este manual no pudo explicar

Cada punto es una función que existe en el código y **no entró en las nueve páginas**,
porque no se dejó escribir en una línea. Cada uno es una decisión pendiente: se corta, o
se rediseña hasta que se pueda explicar.

| # | Qué no se pudo explicar | Evidencia | Propuesta |
|---|---|---|---|
| ~~1~~ | ~~**Sostener `Tab`/`Y` no hace nada distinto de tocarlo.**~~ **RESUELTO 2026-09-20 (Sebastián): sostener abre el cajón** (§5, verbo 2). Tap y hold ahora son dos verbos distintos y enseñables, y el hint de descubrimiento de `FD-296:89-92` deja de hacer falta. Lo que sigue es el diagnóstico original: Con nada abierto, tap y hold **abren los dos el dial**. La distinción solo existe desde una pantalla ya abierta. FD-296:89-92 pide un "hint de descubrimiento" para enseñar una diferencia que casi no hay — y ese hint nunca se implementó. | `HudModeOverlay.gd:300-318` (`TAP` → `_open_radial()`; `HOLD` → `_begin_hold_radial(-1)`) | **Cortar el hold de nivel superior.** Un gesto, un resultado. El hint deja de hacer falta. |
| ~~2~~ | ~~**Tocar un slot cierra OdiseaOS, ignorando cuál fue.**~~ **RESUELTO 2026-09-20 (Sebastián): el botón de un slot abre su pantalla, y la cierra si ya está en ella** (§5, verbo 6). Diagnóstico original: `_tap_slot()` descarta su argumento y llama `_exit()`. El doc de casos de uso afirma que abre la pantalla de ese slot: es falso ahí dentro. Hubo **tres revisiones de esta semántica el mismo día** (2026-09-19). | `HudModeOverlay.gd:369-373` | Decidir una y escribirla acá. Un verbo cuyo efecto cambió tres veces en un día no está diseñado. |
| 3 | **El acorde rápido existe solo en mando.** Sostener un hombro sobre un slot con pantalla y pulsar `A` ejecuta su operación primaria sin abrir nada. No hay equivalente con teclado ni con puntero. | `HudModeOverlay._drive_hud_buttons` | Declararlo afordancia exclusiva del mando **en el manual**, o darle paridad. Hoy no está en ninguna de las dos. |
| 4 | **`Esc` y `B` hacen cosas distintas en el cajón.** `B` vuelve al dial; `Esc` sale de OdiseaOS entero. Y con puntero **no hay ninguna salida** del cajón salvo el botón del HUD. | casos de uso U21, hueco 5 | Una sola regla de retroceso para las tres entradas. |
| 5 | **No hay código de color: hay 47 colores.** `core_v2/ui/hud/` tiene 47 valores distintos escritos a mano (140 sumando dial y a bordo), 11 constantes con nombre en 3 archivos, y ninguna de las 7 escenas de widget declara tema. El gris de OFFLINE está copiado 11 veces; el cian aparece como `0.83` y como `0.835`. | medición 2026-09-20 | §6 es la especificación; falta el juego de tokens que la implemente. |
| 6 | **El cajón no vive en el cajón.** `SuitOSDrawer.gd` existe (359 líneas) pero su manejo está dentro de `HudModeOverlay.gd`: 14 funciones, 105 menciones. | medición 2026-09-20 | Mover. No cambia nada para quien lee este manual, y es la condición para que el §4 siga siendo cierto. |
| 7 | **El sistema tiene cuatro nombres, y uno está mal usado.** `OdiseaOS`, `ODISEA OS`, `ODISEAOS`, `SuitOS`, más `OdiseaOS Workbench`. Y `OYS` **no es un sistema operativo**: es *OdysseyScript*, el lenguaje de guiones de a bordo. Llamar "capa OYS" a la consola confunde dos cosas distintas. | `locale/ui_strings.csv:271-273`; `core_v2/systems/OYS_Interpreter.gd` | Un nombre en ficción (**OdiseaOS**), uno en código (`SuitOS`), y la consola deja de llamarse OYS. |
| 8 | **Los iconos de pantalla no existen.** `hud_screen_icon` está declarado desde FD-296 y no se usa en una sola línea. Este manual no pudo ilustrar ninguna pantalla. | FD-306 §3 | O se dibujan, o se borra el campo. |
| 9 | **Hay tres formas de ser una pantalla**, y una invierte las capas: la vista registra en el modelo (`SuitOSWidgetHost.gd:780`). Invisible para quien lee el manual; decisivo para quien agrega una pantalla nueva. | §2.3 del mapa | Un solo contrato. |
| 11 | **Sostener un slot todavía tiene tres resultados distintos según qué haya adentro**, y dos son invisibles: si la pantalla del slot es favorita, el dial abre con ella marcada; si **no** es favorita, se abre el **cajón** con su fila marcada; si el slot está vacío, el dial abre sin nada marcado. Tres destinos para un mismo gesto. | `HudModeOverlay._open_radial():1336-1345` | Elegir uno. El manual describe el verbo 6 como si tuviera un solo destino, porque un verbo con tres no se puede enseñar. |
| 10 | **Sostener se mide con tres relojes distintos.** Dos usan el reloj de pared (`HudModeOverlay.gd:36`, `SuitOSWidgetHost.gd:24`), uno cuenta muestras del stream (`HudTabGesture.gd:12`). Los dos primeros **no se pueden reproducir en un replay**. | comentario `# ponytail:` en `SuitOSWidgetHost.gd` | Un solo reloj, el determinista. |

**Nueve páginas describen nueve verbos. El código implementa doce lazos de entrada
distintos (`_drive_*`) y lleva 24 banderas booleanas sin máquina de estados. Esa
diferencia es el trabajo.**

---

## Apéndice B — Para quien mantiene el sistema

### Cómo se agrega una pantalla

1. Escribir `<Nombre>Screen.gd` que `extends HUDableComponent`, con `hud_screen_id`
   estable, `hud_screen_title`, `widget_snapshot()` puro, y `allowed_actions_list` +
   `perform_action()` si tiene operaciones.
2. Escribir su widget. Debe respetar §6 (colores) y §7 (OFFLINE).
3. Colgar el componente del prop. El registro es automático al entrar al árbol.
4. **No tocar** `SuitOS`, `HudModeOverlay` ni `SuitOSWidgetHost`.

### Las cuatro líneas rojas

1. Las lecturas son data pura serializable. Un nodo en una lectura rompe §8.
2. `PauseManager` es el único dueño de la pausa. `SuitOS` no la toca.
3. `relevance()` es pura y **no asigna slots** (§3.3).
4. La identidad de una pantalla es contrato de guardado (§1).

### Dónde está cada cosa

| | |
|---|---|
| Registro, slots, favoritos, persistencia | `core_v2/autoloads/SuitOS.gd` |
| Contrato de pantalla | `core_v2/components/HUDableComponent.gd` |
| Geometría de los slots | `core_v2/ui/hud/HudSlots.gd` |
| Mapa técnico completo | `docs/engineering/gui-map-2026-09-20.md` |
| Faltantes priorizados | `docs/features/FD-312_gui_faltantes_urgencia.md` |
| Review y plan de refactor | `docs/engineering/gui-refactor-review.md` |
| Casos de uso verificados | `docs/engineering/casos-uso-FD304-305-306.md` |

---

*Odisea no responde consultas sobre este documento.*
