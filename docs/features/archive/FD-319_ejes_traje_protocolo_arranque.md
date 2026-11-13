# FD-319: Ejes del traje — señal por distancia, urgencia ortogonal y protocolo de arranque

**Status:** In Progress (tareas 2-4 despachadas 2026-09-27)
**Priority:** High
**Effort:** Medium
**Created:** 2026-09-27
**Parent:** FD-296 (OdiseaOS)
**Relacionadas:** FD-310 (widget contextual de interactuables) · FD-312 (faltantes de la GUI) · FD-255 (maestro de sistemas) · FD-259 (energía auxiliar) · FD-289 (canon del domo) · `feat/imgui-diegetic` (mergeada, PR #366)

---

## Propósito

Cristalizar el modelo de **tres ejes** que el traje usa para presentar un widget, y definir
el **protocolo de arranque** como la primera pantalla que lo ejercita. No inventa
infraestructura: se cuelga de OdiseaOS (FD-296) y extiende el widget contextual (FD-310).

## Contexto verificado (2026-09-27)

Dos hechos que condicionan todo el reparto de tareas:

1. **El render ImGui diegético ya está mergeado a `main`.** La rama `feat/imgui-diegetic`
   (~30 commits) entró por PR #366 (merge `3f99f060`), trayendo `ImGuiOdiseaTheme.gd` (tema cian
   monócromo), `ImGuiOdiseaFonts.gd`, `CryoPodImGui.gd` (ECG de fósforo), `FlashlightScreenImGui.gd`,
   `DebugHud*ImGui` y el módulo ImGui en el engine. El pin de `main` ya es **v0.5.4-nightly2**
   (`.github/box3d_release`). **No se rehace el render diegético**: ya está en `main` (D-1 resuelta).

2. **ImPlot3D no está en el repo.** Hay ImPlot 2D usado (`ImPlot_*` en 8 `.gd` de la rama),
   pero **cero ocurrencias de ImPlot3D**. Si existe, vive en el fork del engine, no en el juego.
   Cualquier spec que dependa de ImPlot3D se trata como "promesa a confirmar", no como activo.

3. **FD-310 ya implementó el widget contextual** (aparece en un slot libre al apuntar al prop).
   Pero su presencia es **binaria** (apuntando / no apuntando). Este FD le agrega la **degradación
   por distancia**.

4. **⚠️ El merge de `imgui-diegetic` dejó rojos los Determinism Tests en `main`**
   (run `36346428376`, headBranch `main`); el PR en su rama había pasado. Revisar si es flake o
   regresión real antes de montar este FD encima.

---

## Geografía del despertar (2026-09-27)

Dónde vive el protocolo, según el consenso de diseño con Sebastián:

- El fondo del **octágono** central de la torre (`ScaffoldHubTower`, 8 lados) es un **puerto de
  plataformas on-demand**, no una puerta directa al hangar.
- La **medbay** es la primera plataforma: emerge del pozo, se acopla al anillo, y Elías despierta
  ahí — el tutorial de linterna y traje ocurre en ese espacio chico y controlado (bahía A).
- **Escabullida = premio anticipado**: el elevador corre con respaldo (aux power, paso 1), así que
  Elías baja con la plataforma **sin resolver el protocolo**; abajo ve el blast door rojo (exige las
  4 redes, FD-289) y, junto a la esclusa, **ve el hangar** (cinta + cajas). Sabe por qué pelea.
- El blast door central es la **esclusa al fondo del pozo**; el hangar (escena separada,
  `PushableBoxV2` + `Conveyor`) queda **detrás** de esa esclusa.
- **Dos energías**: aux (respaldo/batería, independiente) enciende luces y consolas primero; principal
  (reactor) viene después de sellar el coolant. El intento de arrancar el reactor tras la aux es lo
  que **revienta la costura** y revela la fuga (respeta FD-289: coolant antes que energía principal).
- El **ducto** queda como **vía alternativa opcional** (backlog, no se construye en esta tanda).

## El modelo de tres ejes

Un widget del traje comunica tres preguntas distintas. Hoy están fundidas en el dot de
estado (que usa el color, y se confunde con el color del sistema). Hay que separarlas:

| Eje | Pregunta | Lenguaje | Cambia |
|---|---|---|---|
| **Identidad** | ¿qué sistema es? | cian / ámbar / verde / blanco (FD-255) | nunca |
| **Urgencia** | ¿cuánto me necesita ahora? | pulso, borde, badge, brillo | por contexto |
| **Señal** | ¿qué tan cerca está mi fuente? | flicker → fuera de rango → offline | por distancia |

- **Identidad** ya tiene token: `OdiseaOSTheme` (`state()`, `accent_for()`). No se toca.
- **Señal** es nuevo; ver abajo. *Fuera de rango ≠ offline*: un widget fuera de rango no está
  roto, estás lejos de su fuente.
- **Urgencia** es nuevo y **ortogonal al color**: nunca se expresa cambiando el color del
  sistema (que es identidad). Se expresa con pulso, borde, badge o brillo.

---

## Señal (presencia por distancia)

Extiende FD-310. Hoy el widget contextual aparece/desaparece por *apuntar*. Ahora la presencia
se degrada con la distancia a la fuente (`screen_id` del prop):

- **En rango** → widget sólido, interactuable al 100 %.
- **Lejano (frontera)** → el widget entra al slot suavizado (fade-in), y si el jugador se aleja
  más, **parpadea** (flicker suave) conforme decae la señal.
- **Fuera de rango** → el widget se marca `FUERA_DE_RANGO` (nuevo estado visual) antes de
  desaparecer; no es un salto seco sino una degradación legible.
- **Online / offline** → sigue el contrato actual de `HudWidget.is_offline()` (Manual §7);
  `FUERA_DE_RANGO` es un estado *previo* al offline, no lo reemplaza.

La señal es **data en el snapshot**, no animación libre: el `screen_id` declara una
`signal_strength` (0..1) derivada de la distancia (u otro aspecto del contexto), y el widget la
pinta. Así sobrevive replay y el terminal auxiliar en otro idioma.

---

## Urgencia (canal ortogonal)

Niveles de urgencia, independientes del color de identidad:

| Nivel | Señal visual (sobre el widget) | Disparador típico |
|---|---|---|
| `quiet` | reposo, sin pulso | sin tarea |
| `notice` | borde sutil | el prop pide atención (válvula pendiente) |
| `urgent` | pulso lento + borde vivo | fallo activo en su sistema |
| `alarm` | pulso rápido + badge | fallo que escala (fuga empeorando) |

Regla de asignación (decisión de diseño a confirmar en el plan):

- **Base**: el prop declara una urgencia base (`default_urgency`).
- **Elevación**: el contexto eleva un nivel (un fallo activo en el sistema sube `notice → urgent`).
- Nunca por debajo de la base del prop, y nunca más de un nivel por tick de evaluación.

Motivo de la regla: permite que *la misma válvula pase de `notice` a `alarm` cuando la fuga
empeora* sin tocar el widget. (Open Question Q-1 si la elevación es automática o manual.)

---

## Protocolo de arranque (la primera pantalla que ejercita los tres ejes)

Es el checklist del traje: la **agenda** de Elías (a diferencia del `SystemStatusWidget`, que es
diagnóstico pasivo). Un solo paso activo a la vez. Seis pasos, mapeados 1:1 al grafo de progresión:

| # | Sistema | Color | Verbo (la instrucción) | Liberación ya implementada |
|---|---|---|---|---|
| 1 | Energía auxiliar | verde | *Restablecer respaldo de emergencia* | Lever → `AuxPowerBus` (FD-259/J4) |
| 2 | Secuencia de arranque | — | *Ejecutar secuencia de arranque* | Consola central (respiro, sin puzzle) |
| 3 | Criocoolant | cian | *Sellar fuga del circuito de refrigeración* | `PipeValve` + `CoolantLeak` (FD-256/J3) |
| 4 | Energía principal | ámbar | *Reacoplar el reactor* | Gate condicionado al paso 3 OK |
| 5 | Atmósfera | blanco/rojo | *Igualar presión del sector* | `PurgeDial` (FD-258/J6) |
| 6 | Acceso hangar | — | *Abrir esclusa inferior del domo* | Premio final → hangar |

**4 estados por paso**, reusando `OdiseaOSTheme`:
- `PENDIENTE` — gris/apagado (STATE_OFFLINE)
- `ACTIVO` — color del sistema, pulso de `notice` (STATE_ACTIVE) — **solo uno a la vez**
- `FALLO` — alarma (STATE_ALARM), transitorio (p. ej. intentaste el 4 sin el 3)
- `HECHO` — tick, se oscurece (STATE_NOMINAL)

**Reglas duras de contrato:**
1. **Un solo `ACTIVO`** — el checklist enfoca tensión; el `SystemStatusWidget` paralelo muestra
   que "además el atmósfera está degradado en el fondo". Ese es el reparto de rol.
2. **El verbo siempre presente** — no dice "criocoolant: fallo", dice *"sellar fuga…"*. Es
   instrucción, no telemetría.
3. **Data pura serializable** — `ProtocolWidget` respeta `HudWidget.set_snapshot(dict)`, sin
   nodos vivos dentro (Manual §8). El estado nace de la lectura, no de `OS.get_ticks`/`rand`.

---

## Render diegético ImGui

Cada widget/pantalla del traje levanta **ImGui cuando no tiene terminal propia**; el HUD de
Elías es la **transición a una pantalla diegética proyectada en primera persona** (FD-297 da el
origen de transición `view_transition_origin()`). La cara ImGui es **solo render**: los datos
siguen viniendo del snapshot.

- **ImPlot 2D** (ya disponible) → curva de temperatura de criocoolant, caudal por criopod.
- **ImPlot3D** → **fuera de alcance de esta tanda** hasta confirmar que existe en el fork
  (ver D-2). El mapa 3D del domo se deja como F2.

---

## Assets a reutilizar (inventario verificado)

| Asset | Estado | Rol |
|---|---|---|
| `core_v2/ui/hud/HudWidget.gd` + `OdiseaOSTheme.gd` | EXISTE | base + tokens de color (no duplicar) |
| `core_v2/ui/hud/SuitOSWidgetHost.gd` + `HudSlots.gd` | EXISTE | 4 slots, arrastre, `show_context/clear_context` (FD-310) |
| widget contextual FD-310 | EXISTE dentro de `SuitOSWidgetHost.gd` (`show_context`/`clear_context`); **no hay** archivo `InteractableContextWidget.*` | punto de extensión de `signal_strength` |
| `core_v2/components/HUDableComponent.gd` | EXISTE | `screen_id`, `relevance()`, `view_transition_origin()` |
| `core_v2/ui/hud/SystemStatusWidget.gd` | EXISTE | diagnóstico pasivo (NO se duplica; rol distinto del checklist) |
| `core_v2/systems/auxpower/` (AuxPowerBus, SealedDoorLock) | EXISTE | gate maestro del paso 1 |
| `core_v2/systems/cryo/CoolantLeak.gd` + `props/pipe/PipeValve.gd` | EXISTE | paso 3 |
| `core_v2/systems/atmosphere/PurgeDial.gd` | EXISTE | paso 5 |
| `feat/imgui-diegetic` (ImGuiOdiseaTheme/Fonts, CryoPodImGui, FlashlightScreenImGui) | MERGEADA (PR #366) | render diegético; pin del engine ya v0.5.4-nightly2 |
| `core_v2/ui/overlays/ProtocolOverlay.gd` + autoload `core_v2/autoloads/ProtocolManager.gd` | EXISTE (FD-312 P2-7) | overlays de protocolo con secuencias (`BtnClose`/`BtnNext`); revisar antes de duplicar |

---

## Decisiones abiertas

| # | Decisión | Por qué importa | Recomendación |
|---|---|---|---|
| D-1 | ~~Destino de `feat/imgui-diegetic`~~ **RESUELTA**: mergeada a `main` (PR #366, `3f99f060`). | El render diegético queda libre para esta tanda. | ✅ Hecho — ver nota de determinism en §Contexto. |
| D-2 | **ImPlot3D**: ¿existe en el fork del engine? | Si no, el "mapa 3D del domo" es un FD aparte. | Confirmar antes de prometerlo; mantenerlo fuera de esta tanda. |
| D-3 | **Signo del eje de urgencia**: ¿quién lo eleva? | Define si la elevación es data o lógica. | Base en el prop + elevación por contexto; nunca por debajo de la base. |

---

## Fuera de alcance (anti-feature-creep)

- ImPlot3D / mapa 3D del domo (F2, condicionado a D-2).
- ImGui para pantallas de **consola de pared** (es otro canal, el diagnóstico de la nave, no el
  traje). Este FD es **solo el traje**.
- Reescribir el render diegético (ya mergeado en PR #366).
- i18n de los textos nuevos (se hereda del retrofit FD-303; los verbos viajan en es/EN y se
  traducen al dibujar).

---

## Riesgos y contratos

- **Determinismo (AGENTS §5.3)**: señal, urgencia y estado del protocolo son **data serializable**
  en el snapshot. Prohibido `OS.get_ticks`, `rand*` o animación libre para decidirlos. El flicker
  y el pulso son **presentación** (interpolación de la lectura), no fuente de estado.
- **Replay / terminal auxiliar**: un nodo vivo dentro del widget rompe el contrato (Manual §8).
  Todo lo que se dibuja sale del snapshot.
- **GLES2 / móvil**: los widgets nuevos son `Control` + ImGui (CPU). Medir draw calls antes de
  montarlos en android (riesgo R5 de FD-255). ImGui flexible: una sola llamada de draw por widget.
- **No tocar** `project.godot` (sin autoload nuevo) ni escenas de nivel en la tanda de lógica.
- **No duplicar** `SystemStatusWidget`: el checklist (instrucción) y el status (diagnóstico) son
  dos roles, dos widgets, no dos copias del mismo dato.

---

## Plan de ejecución (cortes de paralelismo)

| # | Tarea | Ejecutor | Archivos | Aceptación | Depende de |
|---|---|---|---|---|---|
| 1 | ~~Resolver D-1~~ — `imgui-diegetic` ya mergeada a `main` (PR #366) | HECHO | — | render diegético disponible | — |
| 2 | `SignalStrength` en `InteractableContextWidget` + contrato `signal_strength` en el snapshot | JULES | `InteractableContextWidget.gd`, `HUDableComponent.gd`, tests | flicker/fuera-de-rango legible; determinista | 1 |
| 3 | Token de urgencia en `OdiseaOSTheme` (niveles `notice/urgent/alarm`) + contrato `urgency` | JULES | `OdiseaOSTheme.gd`, `HudWidget.gd`, tests | 4 niveles, ortogonales al color | — |
| 4 | `ProtocolWidget` (checklist 6 pasos, 4 estados, un ACTIVO) + `ProtocolScreen` | JULES | `core_v2/ui/hud/ProtocolWidget.*`, `ProtocolScreen.*`, tests | secuencia correcta; verbo presente; determinista | 3 |
| 5 | Cablear pasos 1–6 al grafo de sistemas (AuxPowerBus → CoolantLeak → gate → PurgeDial → hangar) | JULES | un grafo de progresión `ProtocolGraph` (o `LogicCircuitManager`) | cada liberación marca `HECHO` y habilita el siguiente | 4 |
| 6 | Prueba en vivo (legibilidad, urgencia, distancia) | HUMANO | — | Sebastián valida jugando | 2, 4, 5 |

**Cortes**: la tarea 1 (rama diegética) es pre-requisito de 2; 3 y 4 son disjuntas y pueden ir en
paralelo; 5 consume 4. Ninguna tarea toca `project.godot` ni escenas de nivel en la fase de lógica.

---

## Verificación

1. Apuntar a una válvula y alejarse: el widget hace fade-in → flicker → `FUERA_DE_RANGO` →
   desaparece, sin salto seco.
2. El mismo fallo activo sube una válvula de `notice` a `urgent` sin cambiar su color cian.
3. El protocolo muestra un solo paso `ACTIVO`; completar el paso 3 marca `HECHO` y habilita el 4;
   intentar el 4 antes marca `FALLO` transitorio.
4. Tests:
   ```shell
   ./.venv/bin/pytest tests/test_odisea_runner.py -k "signal_strength or urgency or protocol_widget"
   ```
5. Captura visual (`./test_ui.sh`) de: checklist con los 6 pasos, widget con flicker, y un widget
   en `alarm`.

---

## Decisiones tomadas (2026-09-27, Sebastián aceptó las recomendaciones)

- **Q-1 / D-3**: urgencia = base declarada por el prop (`default_urgency`) + elevación automática por
  contexto; nunca por debajo de la base, máximo un nivel por tick de evaluación.
- **Q-2**: `ProtocolWidget` en slot fijo del HUD mientras dure el protocolo; el HUD lo reabsorbe al
  terminar el paso 6.
- **Q-3**: paso 2 = mantener E en la consola central (respiro, sin minijuego).
- Ejecutores (modo despachador de /polish, en vez de Jules): T2 Kilo DeepSeek 4.1, T3 Kilo DeepSeek
  4.1 (Sonnet con cuota agotada), T4 Kilo GLM 5.3 tras T3; T5 queda para la próxima tanda.

## Open Questions

- **Q-1** ¿La elevación de urgencia es automática por contexto (recomendado) o la declara el
  prop a mano? — resuelve D-3.
- **Q-2** ¿El `ProtocolWidget` vive en un slot fijo del HUD o emerge como la linterna
  (auto-mount en `SuitOS._ready()`)? Recomendado: slot fijo mientras dure el protocolo, y
  reabsorbido por el HUD al terminar el paso 6.
- **Q-3** ¿El paso 2 (secuencia de arranque) es "mantener E en la consola central" (recomendado)
  o un minijuego? — no convertirlo en puzzle; es un respiro.