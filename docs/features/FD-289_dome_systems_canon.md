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

## 2. Lo que ya existe (punto de partida)

| Sistema | Assets construidos | Estado |
|---|---|---|
| Iluminación | `DomeLightState` (FD-284), `LightSwitchV2` + `LightGroup` (FD-286), `LightFlicker` (FD-287), fixtures (FD-285 PR #315), `MobileLightBudget` con trinquete, 2 `.lmbake` planificados | Autoload + componentes listos; falta hornear bakes dark/full |
| Tuberías | `PipeRoute` kit modular, `PipeRouter`, `TubeBuilder`, `PipeRun` con fusión de malla, `PipeValve` con animación, `PipeManometer`, `PipeCoolantRun`, serpentina de dome_intro (v5, 2 rieles) | Geometría procedural lista; el circuito de dome_intro existe físicamente |
| Criocoolant | `CoolantLeak`, `CoolantTank`, `CoolantFlowAdapter`, `CoolantFogAdapter`, `LeakPatchPoint`, `LeakFissureVisual`, `ColdRuptureDirector` (OYS), `IceLevel`/`IceVisualBand` | Lógica de fuga/parche/drenaje lista (FD-266); falta conectar al domo real |
| Plasma | `PlasmaConduit` (NOMINAL→OVERHEATING→VENTING→REROUTED), `PlasmaRoute`, `PlasmaExhaust.tscn` (nozzle real), `FireSystem`/`FireEmitter` | Máquina de estados lista; falta conectar al domo real |
| Atmósfera | `PressureSection`, `BlowoutImpulse`, `PurgeDial`, `PressurePump` prop, `AirlockPool`, `GasParticleManager` | Componentes sueltos; no hay red de ductos física |
| Energía | `AuxPowerBus` (OFFLINE→RESTORING→POWERED), `SealedDoorLock`, `LogicCircuitManager` + `CircuitGraphResource` + `CircuitCable` + `CircuitTerminalBridge`, `LeverV2`, `HeavyBlastDoor.tscn` | Bus y puerta sellada listos; falta cablear al domo real |
| Layout físico | `Dome_Base.tscn` (torre central, escaleras, spokes, ascensor), `Dome_Intro.tscn` (criopods, pipes, señalización), `Dome_Prologue.tscn` (variante sin criopods) | Geometría horneada lista |
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
| **Energía** | Cables (`CircuitCable`) | Bus (alimentado por reactor) | Máquinas, manómetros, plataforma | Verde | `#00FF88` |

- Las redes se **cruzan visualmente** (nivel de máquinas), nunca comparten estado simulado.
- El acople entre redes es solo por **eventos guionizados del timeline** (máx. 2-3 por domo).
- El color identifica la red; la forma del prop identifica la acción. Nunca un cartel.

### 3.3 El reactor: raíz energética, no minijuego

El reactor es el corazón del domo:

- **Consume coolant** por su chaqueta de refrigeración (misma red que los criopods).
- **Produce el plasma** que alimenta el bus eléctrico. `PlasmaGenerator` se reutiliza como
  su salida visible.
- **SCRAM**: si falta coolant al reactor → se sobrecalienta → derriba el bus. Consecuencia:
  se apagan manómetros holo, máquinas eléctricas y la plataforma de descenso.
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

## 4. Layout vertical del domo (canónico)

```
────── ANILLO SUPERIOR (entrada + hábitat) ──────
│  Criopods en el perímetro (6 rings de 40)     │
│  El jugador entra aquí y ve el domo entero    │
│  La plataforma de descenso es visible abajo   │
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
│              BLAST DOOR (BASE)                 │
│  Puerta gigante de contención                 │
│  Requisito: 4 redes HEALTHY                   │
│  Al abrirse revela el pozo de descenso        │
│  Altura: ~Y=0                                 │
├────────────────────────────────────────────────┤
│         PLATAFORMA DE DESCENSO                 │
│  Pozo central → cambio de escena              │
│  Verbo: "bajar"                               │
│  Requisito: 4 redes HEALTHY + blast door open │
│  Arranque: beat jugable (luces + shake)       │
│  Altura: Y<0 (subterráneo)                    │
└────────────────────────────────────────────────┘
```

**Ruta crítica del jugador:**

1. Entrar (anillo superior) — ver el domo oscuro, plataforma abajo inalcanzable.
2. Bajar al nivel de máquinas — encontrar las 4 redes en fallo.
3. Restaurar equilibrio — secuencia guiada por el timeline.
4. Las 4 redes HEALTHY → blast door se abre.
5. Accionar plataforma → beat de arranque → `change_scene` a la base.

La plataforma se **ve desde la entrada** para que el jugador sepa desde el minuto uno
que el objetivo es bajar. La luz del pozo cambia de rojo (muerta) → ámbar (restaurando)
→ verde/cian (lista) conforme se reparan los sistemas.

## 5. Beat sheet: timeline de restauración del domo

### Beat 1 — Llegada (OSCURAS)

- El jugador entra al domo. Luces: `OSCURAS` (solo bake oscuro, cero runtime lights).
- Manómetros apagados, plataforma abajo con luz roja tenue.
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

### Beat 6 — Blast Door + Plataforma

- Las 4 redes HEALTHY disparan la apertura del blast door (animación de 2-3 segundos,
  sonido mecánico pesado, shake de cámara vía `TremorZoneV2`).
- Con la puerta abierta, el jugador accede al pozo de descenso.
- **Interacción:** accionar plataforma → beat de arranque (luces del pozo ciclan, tremor
  fuerte, sonido de maquinaria) → `change_scene` a la base.

### Resumen de tiempos estimados

| Beat | Sistema | Tiempo estimado |
|---|---|---|
| 1 | Llegada + intento fallido | 30-60 s |
| 2 | Coolant | 2-4 min |
| 3 | Energía | 1-2 min |
| 4 | Plasma | 2-3 min |
| 5 | Aire + Blast Door | 1-2 min |
| 6 | Plataforma | 30-45 s |
| **Total** | | **7-12 min** |

## 6. Estados del domo y su representación visual

### 6.1 Iluminación (FD-284 + FD-286/287)

| Estado | Bake | Runtime lights | Cuándo |
|---|---|---|---|
| `OSCURAS` | `Dome_Intro_dark.lmbake` | 0 | Beat 1 (llegada) |
| `BAJO` | `Dome_Intro_dark.lmbake` | Pool (3-4 luces) | Beats 2-4 (restaurando) |
| `PLENO` | `Dome_Intro_full.lmbake` | 0 | Beat 5+ (equilibrio) |

Transiciones de luz:
- Beat 1→2: `OSCURAS` → `BAJO` (al primer intento del interruptor, se activa el pool
  de emergencia).
- Beat 5: `BAJO` → `PLENO` (al alcanzar equilibrio, el domo entero se ilumina).

### 6.2 Efectos de la plataforma

La luz del pozo central es el "semáforo" del progreso global:

| Redes HEALTHY | Color del pozo | Significado |
|---|---|---|
| 0 | Rojo tenue (apagado) | Nada funciona |
| 1-2 | Ámbar pulsante | Restaurando |
| 3 | Ámbar fijo | Casi listo |
| 4 | Verde → Cian estable | Plataforma lista |

Cuando el blast door se abre, el pozo ilumina la escena desde abajo (luz volumétrica
barata vía el bake `PLENO` o un `OmniLight` grande).

### 6.3 Cámara y feedback

| Evento | Efecto | Herramienta |
|---|---|---|
| Blowout de presión | Shake fuerte | `TremorZoneV2` (FD-288) |
| Arranque del reactor | Shake sostenido + glow pulsante | `TremorZoneV2` + `PlasmaConduit` |
| Apertura blast door | Shake + sonido | `TremorZoneV2` + SFX |
| Arranque plataforma | Shake progresivo + fade | `TremorZoneV2` + `SceneLighting` |

## 7. Componentes nuevos necesarios (no existen hoy)

### 7.1 `DomeSystemDirector` (nuevo, 1 archivo)

Autoload o nodo en `Dome_Base`. Responsabilidades:

- Lee `DomeEnvConfig.tres` (recurso que declara qué redes, máquinas y timeline tiene
  este domo).
- Maneja el contador de redes HEALTHY (0-4).
- Dispara los eventos del timeline en orden (beat 2→3→4→5).
- Cuando 4/4 HEALTHY, dispara `blast_door_open` y `platform_ready`.
- Expone `get_snapshot()`/`restore_snapshot()` para determinismo Core V2.
- Señal `platform_activated` → `SceneManager.load_scene(target)`.

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
  platform_target_scene = "res://core_v2/levels/Base_Nivel_1.tscn"
  blast_door_path = NodePath("../Doors/BlastDoor")
  platform_path = NodePath("../Platform/Descenso")
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

Controla la puerta gigante de la base. Extiende `DualSlidingObjectV2` (mismo patrón
que `HeavyBlastDoor.tscn` pero a escala de domo: 8-12 m de ancho).

- Abre al recibir señal `DomeSystemDirector.blast_door_open`.
- Animación de apertura + sonido.
- Snapshot-able.

### 7.5 `DomePlatform` (nuevo, 1 archivo)

Nodo de la plataforma de descenso:

- Verbo "bajar" (usa `InteractableBaseV2`).
- Solo interactuable cuando `platform_ready = true`.
- Al activarse: sequencia de arranque (luces, tremor, sonido) → `change_scene`.
- Snapshot-able.

### 7.6 `Fusible` prop (nuevo: 1 `.tscn` + 1 `.gd`)

Prop faltante del vocabulario de máquinas (FD-283 §vocabulario):

- `FusibleV2.gd`: extiende `HoldInteractableV2`, verbo "extraer"/"insertar".
- Tiene un socket del que se saca y al que se vuelve a poner.
- Se usa en el beat de energía (restaurar un circuito quemado).

### 7.7 Integraciones de sistemas existentes al domo

Esto no son archivos nuevos, es **cableado**: conectar los componentes que ya existen
a los nodos del domo real.

| Sistema | Componentes | Qué falta cablear |
|---|---|---|
| Criocoolant | `CoolantLeak` + `CoolantTank` + `LeakPatchPoint` en `Dome_Intro` | Posicionar 1-2 fugas, 1 tanque, 2-3 parches en el nivel de máquinas |
| Plasma | `PlasmaConduit` en ruta del reactor | Posicionar 1 fisura + 2-3 válvulas de redirección en el nivel de máquinas |
| Aire | `PressurePump` + `PurgeTuner` + `PressureSection` | Posicionar bomba, purga y manómetro de aire; sin ductos físicos (el gas es área) |
| Energía | `AuxPowerBus` + `SealedDoorLock` + palancas | Cablear bus → `BlastDoorController`, colocar secuencia de paneles |

## 8. Lo que NO está en este FD (backlog explícito)

- Simulación física de redes entrelazadas (presión compartida, temperatura, causalidad
  bidireccional).
- Reactor como minijuego jugable.
- Ductos físicos para la red de aire (se usa `GasArea3D`).
- Más de 4 redes.
- Modo 2.5D, Actos II-IV, cooperativo.
- Trayecto completo de la plataforma (solo `change_scene`).
- `DomeEnvConfig` como editor visual (es un `.tres` a mano, suficiente para MVP).

## 9. Plan de implementación (8 tareas, delegables a Jules)

### T1 — `DomeNetworkStatus` + `DomeEnvConfig`
Archivos: `core_v2/systems/dome/DomeNetworkStatus.gd`, `DomeEnvConfig.gd` (resource)
Pequeño, sin dependencias. 30-60 min.

### T2 — `DomeSystemDirector` (autoload)
Archivo: `core_v2/systems/dome/DomeSystemDirector.gd` + entry en `project.godot`
Depende de T1. Implementa la máquina de beats. 1-2 h.

### T3 — `BlastDoorController`
Archivo: `core_v2/props/doors/BlastDoorController.gd` + `.tscn`
Usa `HeavyBlastDoor.tscn` como base, escala ×3. 1 h.

### T4 — `DomePlatform`
Archivo: `core_v2/props/controls/DomePlatform.gd` + `.tscn`
InteractableBaseV2 + transición. 1 h.

### T5 — `FusibleV2`
Archivos: `core_v2/props/controls/FusibleV2.gd` + `.tscn`
HoldInteractableV2 con socket. 1 h.

### T6 — Cablear criocoolant y plasma al domo
Posicionar fugas/tanques/válvulas/parches en el nivel de máquinas de `Dome_Intro`.
Conectar señales a `DomeNetworkStatus`. 2-3 h (mitad posicionamiento, mitad señales).

### T7 — Cablear energía y aire al domo
Posicionar bus, paneles, bomba, purga. Conectar a `DomeNetworkStatus`. 2-3 h.

### T8 — Integración completa + test del timeline
Test headless del ciclo completo: beat 1→6. Ajustes de tiempos, valores exportados. 2 h.

### Orden de delegación
T1 → T2 → (T3, T4, T5 en paralelo) → (T6, T7 en paralelo) → T8.

**Total estimado:** 12-16 h de trabajo de implementación, delegables en 4-5 sesiones de Jules.

## 10. Verificación

1. `./runtest.sh -a ./core_v2/tests/test_dome_systems.gd` — ciclo completo headless
   de los 6 beats, determinismo con snapshot/restore.
2. `Dome_Intro.tscn` abierta en el editor: sin errores de script, sin nodos rotos.
3. Timeline manual: entrar al domo, seguir los 6 beats, la plataforma hace
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
| Plataforma | `DomePlatform` |
| Puerta de contención | `BlastDoorController` |
| Reactor | Nodo lógico en `DomeSystemDirector`, set dressing visual |
| SCRAM | Evento guionizado, no es un nodo |
| Bus (eléctrico) | `AuxPowerBus` |