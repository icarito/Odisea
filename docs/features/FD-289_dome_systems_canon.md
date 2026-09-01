# FD-289: Domo Criogénico Estándar — Sistemas, Layout y Plan MVP

**Status:** Draft
**Priority:** High (MVP-blocking)
**Effort:** Large (multi-FD umbrella)
**Created:** 2026-09-01
**Supersedes/absorbs:** FD-283 (DomeEnvRig), FD-255 (Maestro de sistemas)
**Children esperados:** FD-289-t1 a t8 (plan de abajo)
**Completed:** -

## 1. Propósito

Este documento define **cómo funciona un domo criogénico estándar de la Odisea** de
principio a fin — qué máquinas contiene, cómo se cablean entre sí, qué hace el jugador
y en qué orden, y qué assets existen vs. qué falta construir. Es el plano canónico del
que sale toda implementación de domo del Acto I.

No es un FD de "si algún día": es la especificación de lo que **falta para completar el
MVP del domo jugable**, partiendo de lo que ya existe.

**Decisión canónica (2026-09-01):** `Dome_Intro.tscn` es la base del vertical slice.
`Dome_Crio.tscn` (con su `Basement` + `MaintenanceElevator` + `Airlock_Basement`) es
**legacy** y no se reutiliza. El blast door se construye **nuevo** (base mecánica
`FloorHatch.tscn`, modelos/assets propios). El sótano es un **hangar de mantenimiento
grande** que incorpora `PushableBoxV2` y `Conveyor` a los puzzles, y **vive en una escena
separada** (no dentro de `Dome_Intro`): la nave tendrá múltiples domos con sótanos
variados, así que el template de sistemas del domo es fijo y el hangar es la parte
intercambiable por domo.

## 2. Lo que ya existe (punto de partida)

| Sistema | Assets construidos | Estado |
|---|---|---|
| Iluminación | `DomeLightState` (FD-284), `LightSwitchV2` + `LightGroup` (FD-286), `LightFlicker` (FD-287), fixtures (FD-285 PR #315), `MobileLightBudget` con trinquete, 2 `.lmbake` planificados | Autoload + componentes listos; falta hornear bakes dark/full |
| Tuberías | `PipeRoute` kit modular, `PipeRouter`, `TubeBuilder`, `PipeRun` con fusión de malla, `PipeValve` con animación, `PipeManometer`, `PipeCoolantRun`, serpentina de dome_intro (v5, 2 rieles) | Geometría procedural lista; el circuito de dome_intro existe físicamente |
| Criocoolant | `CoolantLeak`, `CoolantTank`, `CoolantFlowAdapter`, `CoolantFogAdapter`, `LeakPatchPoint`, `LeakFissureVisual`, `ColdRuptureDirector` (OYS), `IceLevel`/`IceVisualBand` | Lógica de fuga/parche/drenaje lista (FD-266); falta conectar al domo real |
| Plasma | `PlasmaConduit` (NOMINAL→OVERHEATING→VENTING→REROUTED), `PlasmaRoute`, `PlasmaExhaust.tscn` (nozzle real), `FireSystem`/`FireEmitter` | Máquina de estados lista; falta conectar al domo real |
| Atmósfera | `PressureSection`, `BlowoutImpulse`, `PurgeDial`, `PressurePump` prop, `AirlockPool`, `GasParticleManager` | Componentes sueltos; no hay red de ductos física |
| Energía | `AuxPowerBus` (OFFLINE→RESTORING→POWERED), `SealedDoorLock`, `LogicCircuitManager` + `CircuitGraphResource` + `CircuitCable` + `CircuitTerminalBridge`, `LeverV2`, `HeavyBlastDoor.tscn` (legacy) | Bus y puerta sellada listos; falta cablear al domo real |
| Puzzle físico | `PushableBoxV2` (RigidBody determinista), `Conveyor` + `ConveyorCarrousel` (Area con `speed_x`) | Listos; se incorporan al hangar del sótano |
| Puertas/compuertas | `FloorHatch.tscn` (trampilla de piso con `HatchDoor` KinematicBody) | Base mecánica del blast door nuevo |
| Layout físico | `Dome_Base.tscn` (torre central, escaleras, spokes), `Dome_Intro.tscn` (criopods, pipes, señalización), `Dome_Prologue.tscn` (variante sin criopods) | Geometría horneada lista |
| Hangar / Sótano | Escena separada por domo (p. ej. `Dome_Intro_Hangar.tscn`), blockout de hangar de mantenimiento | A construir; reutiliza `PushableBoxV2` + `Conveyor` |
| Descenso | Plataforma móvil de carga + rampa de servicio en el pozo del blast door | A construir (`HangarPlatform` nuevo) |
| Cámara/VFX | `CinematicManager.trigger_camera_shake`, `TremorZoneV2` (FD-288, delegado), `WindTunnelV2` (empuje direccional), `SceneLighting` (flicker global) | Listo o en progreso |

## 3. Reglas de arquitectura (canonizadas de FD-283)

### 3.1 Nada de grafos lógicos genéricos para máquinas de domo

`LogicCircuitManager` y el editor de circuitos (`CircuitGraphResource`, compuertas
AND/OR/XOR/NOT/DELAY) quedan **exclusivamente** para la puerta sellada del AuxPower.
Son una herramienta de puzzle, no un lenguaje de configuración de domos.

**Regla:** toda máquina del domo declara sus precondiciones como lista simple:

```
requiere = [energía?, caudal_upstream?, presión_en_rango?]
```

Esto cubre el 100% de los casos del Acto I. Si algún día un domo necesita lógica
más compleja, se discute — pero no se anticipa arquitectura para un caso que no
existe.

### 3.2 Cuatro redes, separación estricta

| Red | Portador | Fuente | Consumidores | Color | Color HEX |
|---|---|---|---|---|---|
| **Criocoolant** | Tubos (`PipeRoute` kit) | `CoolantTank` | Criopods, **reactor** (chaqueta) | Cian | `#00E5FF` |
| **Plasma** | Tubos (mismo kit) | **Reactor** (salida `PlasmaGenerator`) | Bus eléctrico | Ámbar | `#FF8F00` |
| **Aire** | Ductos (mayor diámetro) | `PressurePump` | Interior del domo | Blanco/Rojo | `#FF5252` |
| **Energía** | Cables (`CircuitCable`) | Bus (alimentado por reactor) | Máquinas, manómetros, blast door | Verde | `#00FF88` |

- Las redes se **cruzan visualmente** (nivel de máquinas), nunca comparten estado simulado.
- El acople entre redes es solo por **eventos guionizados del timeline** (máx. 2-3 por domo).
- El color identifica la red; la forma del prop identifica la acción. Nunca un cartel.

### 3.3 El reactor: raíz energética, no minijuego

El reactor es el corazón del domo:

- **Consume coolant** por su chaqueta de refrigeración (misma red que los criopods).
- **Produce el plasma** que alimenta el bus eléctrico. `PlasmaGenerator` se reutiliza como
  su salida visible.
- **SCRAM**: si falta coolant al reactor → se sobrecalienta → derriba el bus. Consecuencia:
  se apagan manómetros holo, máquinas eléctricas y el blast door.
- Es un **nodo lógico** con requisito (`caudal de coolant en rango`) y consecuencia
  guionizada. No se simula la generación; no es un minijuego.
- Set dressing a fondo: columna central visible desde la entrada, tubos de plasma saliendo
  hacia arriba, glow pulsante.

### 3.4 Máquinas: 8 tipos, verbos fijos

| Máquina | Verbo | Redes | Prop existente |
|---|---|---|---|
| **Válvula** | accionar (abrir/cerrar) | Criocoolant, Plasma | `PipeValve` (`InteractableBaseV2`) |
| **Interruptor / Palanca** | accionar | Energía | `LeverV2`, `LightSwitchV2` |
| **Fusible** | extraer e insertar | Energía | A diseñar (un `HoldInteractableV2` con socket) |
| **Bomba** | sostener (cargar) | Aire | `PressurePump` (`HoldInteractableV2`) |
| **Purga** | sostener y soltar en zona verde | Aire, Plasma | `PurgeTuner` (`HoldInteractableV2` + gauge) |
| **Parche** | sostener (sellar) | Criocoolant, Plasma | `LeakPatchPoint` (gloo) |
| **Extractor / Radiador** | accionar | Criocoolant, Aire | A diseñar (usa `InteractableBaseV2`) |
| **Manómetro** | lectura (no interactuable) | Todas | `PipeManometer` (`PropBaseV2`) |

Gramática: **un solo verbo por máquina**, consistente en todo el domo. El color dice la
red; la forma dice la acción. Glosario fijo en español (interruptor, fusible, palanca,
válvula, bomba, purga, parche, manómetro, extractor, costura). Código en inglés.

**Extensión del hangar (puzzles físicos):** en el sótano se añaden `PushableBoxV2` (empujar
cajas para bloquear/desbloquear, tapar respiraderos, activar placas de presión) y
`Conveyor` (cintas que transportan cajas o al jugador hacia/desde puntos de puzzle). Estos
son **verbos físicos adicionales** que conviven con los 8 verbos de máquina; no rompen la
gramática de "un verbo por máquina" porque operan sobre el espacio, no sobre una red.

## 4. Layout vertical del domo (canónico)

```
────── ANILLO SUPERIOR (entrada + hábitat) ──────
│  Criopods en el perímetro (6 rings de 40)     │
│  El jugador entra aquí y ve el domo entero    │
│  El blast door del piso es visible abajo      │
│  Luz: PLENO (al final) / OSCURAS (al inicio)  │
├────────────────────────────────────────────────┤
│              NIVEL DE MÁQUINAS                 │
│  Las 4 redes se cruzan a la vista:            │
│  - Gabinete eléctrico (energía, verde)        │
│  - Junta de plasma (ámbar)                    │
│  - Costuras de coolant (cian)                 │
│  - Extractores de aire (blanco/rojo)          │
│  - Manómetros de todas las redes              │
│  Altura: ~Y=8 a Y=14                          │
├────────────────────────────────────────────────┤
│              REACTOR CENTRAL                   │
│  Columna vertebral del domo                   │
│  Coolant baja de criopods → chaqueta          │
│  Plasma sale hacia arriba → bus               │
│  Visible desde la entrada                     │
│  Altura: ~Y=2 a Y=8                           │
├────────────────────────────────────────────────┤
│       BLAST DOOR (compuerta de piso, NUEVO)    │
│  Trampilla gigante de contención              │
│  Base mecánica: FloorHatch ×N (modelos nuevos)│
│  Requisito: 4 redes HEALTHY                   │
│  Al abrirse revela el pozo de descenso        │
│  (plataforma móvil de carga + rampa)          │
│  Altura: ~Y=0                                 │
├═══════════════ change_scene ══════════════════┤
│         SÓTANO / HANGAR (escena separada)      │
│  Hangar de mantenimiento, grande y abierto    │
│  Puzzles: PushableBoxV2 + Conveyor            │
│  Esclusa de salida al exterior al fondo       │
│  Varía por domo (template de sistemas fijo)   │
└────────────────────────────────────────────────┘
```

**Ruta crítica del jugador:**

1. Entrar (anillo superior) — ver el domo oscuro, el blast door abajo inalcanzable.
2. Bajar al nivel de máquinas — encontrar las 4 redes en fallo.
3. Restaurar equilibrio — secuencia guiada por el timeline.
4. Las 4 redes HEALTHY → blast door se abre (compuerta de piso).
5. Descender por el pozo — **plataforma móvil de carga** (cinemática) o **rampa de servicio** (peatonal, sin espera) → `change_scene` al hangar (escena separada).
6. Hangar — puzzles físicos (cajas + cintas) abriendo la ruta a la esclusa.
7. Esclusa al exterior → salir del domo.

El blast door se **ve desde la entrada** para que el jugador sepa desde el minuto uno
que el objetivo es bajar. La luz de su borde cambia de rojo (muerta) → ámbar (restaurando)
→ verde/cian (lista) conforme se reparan los sistemas.

## 5. Beat sheet: timeline de restauración del domo

### Beat 1 — Llegada (OSCURAS)

- El jugador entra al domo. Luces: `OSCURAS` (solo bake oscuro, cero runtime lights).
- Manómetros apagados, blast door abajo con luz roja tenue.
- Objetivo legible: "bajar" es imposible ahora — hay que encender el domo.
- **Interacción inicial:** accionar el interruptor principal (palanca de energía). No
  funciona — el bus está muerto. El manómetro de energía titila en rojo.

### Beat 2 — Coolant (primer sistema)

- Al intentar el interruptor, se revela la primera fuga de coolant (evento guionizado:
  una costura revienta al presurizarse el sistema por el intento de arranque).
- **Fallo:** fuga de coolant → niebla cian que ciega (no daña). El tanque drena.
- **Aviso:** condensación en tubería → cristales → nube.
- **Reparación:** cerrar válvula aguas arriba → despresurizar tramo → parchear con
  gloo → reabrir válvula. Semántica FD-266.
- **Recompensa:** niebla se disipa, manómetro de coolant marca verde.
- Redes: 1/4 HEALTHY.

### Beat 3 — Energía (acoplado al coolant)

- Con coolant fluyendo, el reactor ya no está en riesgo de SCRAM.
- **Interacción:** accionar palanca del bus AuxPower. Secuencia de 2-3 paneles en orden
  (reutiliza `LogicCircuitManager`, la única excepción a la regla 3.1).
- **Recompensa:** bus energizado → gabinete eléctrico se enciende (verde), manómetros
  holo se activan.
- Redes: 2/4 HEALTHY.

### Beat 4 — Plasma (con energía disponible)

- Con el bus vivo, el reactor puede arrancar la generación de plasma.
- **Fallo:** la junta de plasma tiene una fisura. Brillo pulsante → zumbido → chorro
  de plasma (daño por contacto).
- **Reparación:** redirigir el flujo con válvulas (2-3 válvulas, modo bidireccional).
  Al alinear el circuito seguro, el chorro se corta.
- **Recompensa:** tubo de plasma brilla ámbar estable, manómetro de plasma marca verde.
- Redes: 3/4 HEALTHY.

### Beat 5 — Aire/Presión + Blast Door

- **Fallo:** un blowout de presión apaga los extractores. La sala se llena de humo/vapor
  residual (visibilidad reducida, sin daño).
- **Reparación:** accionar bomba de presión (sostener para cargar) + purgar en zona verde
  del manómetro de aire (sostener y soltar a tiempo).
- **Recompensa:** extractores arrancan, el aire se despeja, manómetro de aire marca verde.
- Redes: **4/4 HEALTHY** → equilibrio alcanzado.

### Beat 6 — Blast Door + descenso (plataforma móvil + rampa → change_scene)

- Las 4 redes HEALTHY disparan la apertura del blast door (compuerta de piso, animación
  de 2-3 segundos, sonido mecánico pesado, shake de cámara vía `TremorZoneV2`).
- Con la compuerta abierta, el pozo revela **dos vías de descenso**:
  - **Plataforma móvil de carga** (`HangarPlatform`, nueva): el jugador se sube y desciende
    lentamente (tremor + ruido mecánico). Ruta cinemática; al llegar abajo cruza el trigger
    → `change_scene` al hangar.
  - **Rampa de servicio** (nueva): vía peatonal paralela, sin espera, para bajar caminando.
- Ambas vías terminan en el mismo trigger de transición (frontera interior→interior, sin airlock).

### Beat 7 — Hangar (puzzles físicos)

- El hangar (escena separada) está a oscuras y parcialmente colapsado; el equipo de
  mantenimiento quedó desordenado (cajas, cintas, escombros).
- **Puzzles:** empujar `PushableBoxV2` para tapar un respiradero activo / activar una
  placa de presión / hacer de puente; usar `Conveyor` para mover una caja pesada o
  desplazarse hasta una repisa.
- **Recompensa:** se despeja la ruta hasta la esclusa de salida.

### Beat 8 — Esclusa al exterior

- La esclusa del hangar (misma `AirlockChamber` que las puertas N/S/E/W) se presuriza y
  abre → `ScaffoldOrbit` / `OdiseaExterior` (el anillo exterior, domos como LOD).
- Fin del vertical slice del domo.

### Resumen de tiempos estimados

| Beat | Sistema | Tiempo estimado |
|---|---|---|
| 1 | Llegada + intento fallido | 30-60 s |
| 2 | Coolant | 2-4 min |
| 3 | Energía | 1-2 min |
| 4 | Plasma | 2-3 min |
| 5 | Aire + Blast Door | 1-2 min |
| 6 | Blast door abre + descenso | 20-30 s |
| 7 | Hangar (cajas + cintas) | 2-4 min |
| 8 | Esclusa al exterior | 20-30 s |
| **Total** | | **10-16 min** |

## 6. Estados del domo y su representación visual

### 6.1 Iluminación (FD-284 + FD-286/287)

| Estado | Bake | Runtime lights | Cuándo |
|---|---|---|---|
| `OSCURAS` | `Dome_Intro_dark.lmbake` | 0 | Beat 1 (llegada) |
| `BAJO` | `Dome_Intro_dark.lmbake` | Pool (3-4 luces) | Beats 2-5 (restaurando) |
| `PLENO` | `Dome_Intro_full.lmbake` | 0 | Beat 6+ (equilibrio) |

Transiciones de luz:
- Beat 1→2: `OSCURAS` → `BAJO` (al primer intento del interruptor, se activa el pool
  de emergencia).
- Beat 6: `BAJO` → `PLENO` (al alcanzar equilibrio, el domo entero se ilumina).

### 6.2 Efectos del blast door (semáforo de progreso)

La luz del borde del blast door es el "semáforo" del progreso global:

| Redes HEALTHY | Color del borde | Significado |
|---|---|---|
| 0 | Rojo tenue (apagado) | Nada funciona |
| 1-2 | Ámbar pulsante | Restaurando |
| 3 | Ámbar fijo | Casi listo |
| 4 | Verde → Cian estable | Blast door listo |

Cuando el blast door se abre, la luz del hangar ilumina el domo desde abajo (luz
volumétrica barata vía el bake `PLENO` o un `OmniLight` grande).

### 6.3 Cámara y feedback

| Evento | Efecto | Herramienta |
|---|---|---|
| Blowout de presión | Shake fuerte | `TremorZoneV2` (FD-288) |
| Arranque del reactor | Shake sostenido + glow pulsante | `TremorZoneV2` + `PlasmaConduit` |
| Apertura blast door | Shake + sonido | `TremorZoneV2` + SFX |
| Caída de caja / cinta | Impacto + sonido | `PushableBoxV2` + SFX |

## 7. Componentes nuevos necesarios (no existen hoy)

### 7.1 `DomeSystemDirector` (nuevo, 1 archivo)

Autoload o nodo en `Dome_Base`. Responsabilidades:

- Lee `DomeEnvConfig.tres` (recurso que declara qué redes, máquinas y timeline tiene
  este domo).
- Maneja el contador de redes HEALTHY (0-4).
- Dispara los eventos del timeline en orden (beat 2→3→4→5).
- Cuando 4/4 HEALTHY, dispara `blast_door_open` y `hangar_ready`.
- Expone `get_snapshot()`/`restore_snapshot()` para determinismo Core V2.
- Señal `airlock_exit` → `SceneManager.load_scene(target)`.

### 7.2 `DomeEnvConfig` resource (nuevo, 1 archivo `.tres`)

```
DomeEnvConfig.tres:
  dome_id = "intro"
  networks = ["criocoolant", "plasma", "aire", "energia"]
  timeline = [
    {beat=1, event="on_first_power_attempt", action="spawn_coolant_leak"},
    {beat=2, event="coolant_healthy", action="enable_auxpower_lever"},
    {beat=3, event="energy_healthy", action="enable_plasma_route"},
    {beat=4, event="plasma_healthy", action="enable_air_system"},
    {beat=5, event="air_healthy", action="open_blast_door"},
  ]
  hangar_scene = "res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn"
  hangar_spawn_id = "from_dome_intro_platform"
  exterior_airlock_scene = "res://core_v2/components/ScaffoldOrbit.tscn"
  blast_door_path = NodePath("../Doors/BlastDoor")
```

Dome_Intro y Dome_Prologue comparten el mismo `.tres` o cada uno tiene el suyo.
Crear uno para `dome_intro` y copiarlo para `dome_prologue` es trivial.

### 7.3 `DomeNetworkStatus` (nuevo, 1 archivo)

Componente ligero que cada red notifica cuando pasa a HEALTHY:

```gdscript
# DomeNetworkStatus.gd
signal network_healthy(network_id: String)
signal all_healthy()

var _healthy_networks := {}

func mark_healthy(network_id: String) -> void:
    _healthy_networks[network_id] = true
    emit_signal("network_healthy", network_id)
    if _healthy_networks.size() >= _total_networks:
        emit_signal("all_healthy")
```

Vive en `Dome_Base`; `DomeSystemDirector` lo consulta.

### 7.4 `BlastDoorController` (nuevo, 1 archivo)

Controla la **compuerta de piso** gigante de la base. Base mecánica: `FloorHatch.tscn`
(trampilla con `HatchDoor` KinematicBody), pero a escala de hangar (8-12 m) y con
modelos/assets **nuevos** (no los CSG de FloorHatch; paneles de contención, bisagras,
sellos, luces de borde).

- Abre al recibir señal `DomeSystemDirector.blast_door_open`.
- La apertura es **horizontal** (compuerta de piso que pivota/se desliza revelando el pozo
  de descenso), no una puerta deslizante vertical tipo `DualSlidingObjectV2`.
- Animación de apertura + sonido + luces de borde (semáforo §6.2).
- Snapshot-able.

### 7.5 Transición blast door → hangar (change_scene, patrón AirlockZoneV2)

El hangar es una **escena separada**. La transición reutiliza el patrón de cambio de
escena ya establecido (`AirlockZoneV2`: `target_scene` + `target_spawn_id` +
`target_airlock_path`), como un `HangarTransition` o una `Area` de transición equivalente
en el pozo del blast door.

- El blast door abre → el jugador desciende por una **plataforma móvil de carga** o por
  una **rampa de servicio** paralela hasta el fondo del pozo → cruza el trigger →
  `change_scene` a la escena del hangar.
- **Sin airlock** en esta frontera: domo y hangar son ambos interiores presurizados; es
  un cambio de escena puro, no un ciclo de presurización.
- El hangar es **intercambiable por domo**: cada domo apunta a su propia escena de hangar
  (variada) mientras el rig de sistemas del domo es el mismo template.
- El spawn del hangar se identifica como `from_dome_intro_platform` (uno por domo).
- **Componentes nuevos del descenso** (ver §7.9): `HangarPlatform` (plataforma móvil
  determinista, snapshot-able) y una rampa de servicio estática en el pozo.

> **Regla de reutilización (razón del change_scene):** la nave tendrá múltiples domos
> con sótanos variados. El template de sistemas (anillo + máquinas + reactor + blast
> door) es compartido; lo que varía por domo es el hangar. Separarlos en escenas hace
> trivial mezclar y combinar domos y sótanos sin duplicar geometría ni lógica.

### 7.6 `Fusible` prop (nuevo: 1 `.tscn` + 1 `.gd`)

Prop faltante del vocabulario de máquinas (FD-283 §vocabulario):

- `FusibleV2.gd`: extiende `HoldInteractableV2`, verbo "extraer"/"insertar".
- Tiene un socket del que se saca y al que se vuelve a poner.
- Se usa en el beat de energía (restaurar un circuito quemado).

### 7.7 Hangar (nuevo: 1 escena separada + blockout + puzzles)

- **Escena propia** (`Dome_Intro_Hangar.tscn` u homólogo por domo): recibe el
  `change_scene` desde el blast door del domo. Es el punto de variación por domo.
- **Blockout:** hangar de mantenimiento grande y abierto, con dos niveles (piso +
  repisas/catwalks), iluminación de trabajo (tripodes `light_work_tripod`).
- **Puzzles físicos** con assets ya existentes:
  - `PushableBoxV2`: tapar respiraderos, activar placas de presión, hacer de puente.
  - `Conveyor`/`ConveyorCarrousel`: mover cajas pesadas, desplazar al jugador, alimentar
    un punto de entrega.
- **Salida:** una `AirlockChamber` al fondo → `ScaffoldOrbit`/`OdiseaExterior` (spawn
  `from_dome_intro_hangar`). Única frontera presurizada→vacío.

### 7.8 Integraciones de sistemas existentes al domo

Esto no son archivos nuevos, es **cableado**: conectar los componentes que ya existen
a los nodos del domo real.

| Sistema | Componentes | Qué falta cablear |
|---|---|---|
| Criocoolant | `CoolantLeak` + `CoolantTank` + `LeakPatchPoint` en `Dome_Intro` | Posicionar 1-2 fugas, 1 tanque, 2-3 parches en el nivel de máquinas |
| Plasma | `PlasmaConduit` en ruta del reactor | Posicionar 1 fisura + 2-3 válvulas de redirección en el nivel de máquinas |
| Aire | `PressurePump` + `PurgeTuner` + `PressureSection` | Posicionar bomba, purga y manómetro de aire; sin ductos físicos (el gas es área) |
| Energía | `AuxPowerBus` + `SealedDoorLock` + palancas | Cablear bus → `BlastDoorController`, colocar secuencia de paneles |

### 7.9 Descenso al hangar (nuevo: `HangarPlatform` + rampa de servicio)

- **`HangarPlatform`** (1 `.gd` + 1 `.tscn`): plataforma móvil de carga en el pozo del
  blast door. Cuerpo determinista con estados `TOP`/`DESCENDING`/`BOTTOM`, snapshot-able
  (`get_snapshot`/`restore_snapshot`, grupo `replay_sync`). El jugador se sube y se activa
  (botón o `Area` de pie) para bajar; tremor vía `TremorZoneV2`/`CinematicManager` durante
  el descenso.
- **Rampa de servicio**: rampa estática paralela a la plataforma, vía peatonal sin espera.
  Ambas terminan en el mismo `Area` de transición (`HangarTransition`).
- Ambas vías desembocan en el trigger que dispara `change_scene` al hangar
  (`DomeEnvConfig.hangar_scene`), spawn `from_dome_intro_platform`.

## 8. Lo que NO está en este FD (backlog explícito)

- Simulación física de redes entrelazadas (presión compartida, temperatura, causalidad
  bidireccional).
- Reactor como minijuego jugable.
- Ductos físicos para la red de aire (se usa `GasArea3D`).
- Más de 4 redes.
- Modo 2.5D, Actos II-IV, cooperativo.
- Reutilizar `MaintenanceElevator` de `Dome_Crio` (es legacy). La **plataforma móvil de
  descenso** se construye nueva (`HangarPlatform`). El paso domo→hangar sigue siendo un
  `change_scene` de escena, no una simulación física continua del ascensor.
- El hangar como parte del mismo mapa del domo (es escena separada para permitir sótanos
  variados por domo).
- `DomeEnvConfig` como editor visual (es un `.tres` a mano, suficiente para MVP).

## 9. Plan de implementación (8 tareas, delegables a Jules)

### T1 — `DomeNetworkStatus` + `DomeEnvConfig`
Archivos: `core_v2/systems/dome/DomeNetworkStatus.gd`, `DomeEnvConfig.gd` (resource)
Pequeño, sin dependencias. 30-60 min.

### T2 — `DomeSystemDirector` (autoload)
Archivo: `core_v2/systems/dome/DomeSystemDirector.gd` + entry en `project.godot`
Depende de T1. Implementa la máquina de beats. 1-2 h.

### T3 — `BlastDoorController` + pozo de descenso (plataforma + rampa)
Archivos: `core_v2/props/doors/BlastDoorController.gd` + `.tscn`, `HangarPlatform.gd` + `.tscn`
Base mecánica `FloorHatch.tscn`, modelos nuevos, apertura horizontal. Pozo con plataforma
móvil de carga + rampa de servicio. 3 h.

### T4 — Blockout del hangar como escena separada
Archivo: `core_v2/levels/interiors/Dome_Intro_Hangar.tscn`
Hangar + rampa de descenso + trigger de spawn + colocación de `PushableBoxV2` y `Conveyor`
+ esclusa de salida. 2-3 h.

### T5 — `FusibleV2`
Archivos: `core_v2/props/controls/FusibleV2.gd` + `.tscn`
HoldInteractableV2 con socket. 1 h.

### T6 — Cablear criocoolant y plasma al domo
Posicionar fugas/tanques/válvulas/parches en el nivel de máquinas de `Dome_Intro`.
Conectar señales a `DomeNetworkStatus`. 2-3 h (mitad posicionamiento, mitad señales).

### T7 — Cablear energía y aire al domo
Posicionar bus, paneles, bomba, purga. Conectar a `DomeNetworkStatus`. 2-3 h.

### T8 — Integración completa + test del timeline
Test headless del ciclo completo: beat 1→8. Ajustes de tiempos, valores exportados. 2 h.

### Orden de delegación
T1 → T2 → (T3, T4, T5 en paralelo) → (T6, T7 en paralelo) → T8.

**Total estimado:** 14-18 h de trabajo de implementación, delegables en 4-5 sesiones de Jules.

## 10. Verificación

1. `./runtest.sh -a ./core_v2/tests/test_dome_systems.gd` — ciclo completo headless
   de los 8 beats, determinismo con snapshot/restore.
2. `Dome_Intro.tscn` abierta en el editor: sin errores de script, sin nodos rotos.
3. Timeline manual: entrar al domo, seguir los 8 beats, la esclusa hace
   `change_scene` correctamente.
4. `DomeSystemDirector` snapshot/restore: guardar a mitad de beat 3, restaurar,
   continuar → mismo resultado.
5. Sin regresiones en los 133+ tests existentes (`./runtest.sh -a ./core_v2/tests/`).

## 11. Glosario canónico (español ↔ código)

| Término español (diseño/UI) | Identificador en código |
|---|---|
| Interruptor | `LightSwitchV2` |
| Palanca | `LeverV2` |
| Fusible | `FusibleV2` |
| Válvula | `PipeValve` |
| Bomba | `PressurePump` |
| Purga | `PurgeTuner` |
| Parche / Sellador | `LeakPatchPoint` |
| Manómetro | `PipeManometer` (lectura), `Manometer` (genérico) |
| Extractor / Radiador | `ExtractorV2` (nuevo) |
| Costura | Se refiere a la junta física; en código es `LeakFissureVisual` |
| Compuerta de piso / Blast door | `BlastDoorController` |
| Plataforma de descenso | `HangarPlatform` |
| Rampa de servicio | static mesh en el pozo (no es un nodo) |
| Hangar / Sótano | `Dome_Intro_Hangar.tscn` (escena separada, variada por domo) |
| Caja empujable | `PushableBoxV2` |
| Cinta transportadora | `Conveyor` / `ConveyorCarrousel` |
| Esclusa de salida | `AirlockChamber` → `ScaffoldOrbit` / `OdiseaExterior` |
| Reactor | Nodo lógico en `DomeSystemDirector`, set dressing visual |
| SCRAM | Evento guionizado, no es un nodo |
| Bus (eléctrico) | `AuxPowerBus` |
