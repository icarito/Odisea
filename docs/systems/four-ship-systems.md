# Los cuatro sistemas de la nave — guía de funcionamiento

Guía práctica de los cuatro sistemas industriales de la Odisea: qué hace cada uno, cómo está
armado, y dónde tocar para mejorarlo. El diseño vive en [FD-255](../features/FD-255_systems_master.md)
y sus hijos (FD-256 a FD-259); acá está **cómo funciona lo que ya está construido**.

Banco de pruebas: `core_v2/tests/TestShipSystems.tscn` (F6). Cuatro plataformas de 7×7 m, una
por sistema, separadas 18 m. Cada estación es una sub-escena propia en
`core_v2/tests/stations/`, así dos sistemas se pueden trabajar en paralelo sin tocar el mismo
archivo.

---

## La regla que comparten los cuatro

Todos siguen la misma forma, a propósito:

```
SANO  →  AVISO  →  FALLO  →  (el jugador actúa)  →  LIBERADO  →  SANO
```

- **El color dice de qué sistema es** antes de que el fallo te alcance: cian criocoolant,
  ámbar plasma, blanco/rojo atmósfera, verde energía.
- **El aviso siempre precede al daño**, y siempre en el mismo orden. Esa previsibilidad es lo
  que permite anticipar sin leer un cartel.
- **La liberación es reordenar el órgano**, no matarlo: cerrar, redirigir, purgar, alimentar.

Y una regla de arquitectura: **la lógica y la cara están separadas**. Cada sistema tiene un
script de estado (determinista, con snapshot, sin nada visual) y una escena que lo viste. La
escena lee el estado y traduce; nunca al revés. Eso es lo que permite testear los cuatro
headless y también lo que hace que se pueda cambiar el look sin tocar la mecánica.

---

## 1. Criocoolant (cian) — la fuga que ciega

**Qué hace.** El refrigerante que mantiene fríos los criopods. Su fallo no daña: **ciega**.

| | |
|---|---|
| Lógica | `core_v2/systems/cryo/CoolantLeak.gd` |
| Niebla | `core_v2/systems/cryo/CoolantFogAdapter.gd` → `systems/gas/GasArea3D` |
| Escena | `core_v2/tests/stations/CryoStation.tscn` |
| Tests | `core_v2/tests/test_coolant_leak.gd`, `test_coolant_fog_adapter.gd` |

**El ciclo.** `HEALTHY → WARNING` (condensación, 6 s) `→ LEAKING` (la niebla crece durante 3 s
hasta taparlo todo) `→` el jugador **cierra la válvula** `→ SEALED` (se disipa en 5 s) `→ HEALTHY`.

**El interruptor.** Una `PipeValve` sobre la pared del caño. Es **bidireccional**: cerrar corta
el caudal y detiene la fuga; reabrir la vuelve a soltar, porque el caño sigue roto. La válvula
gobierna el flujo, no repara.

**Cómo se ve.** La tubería lleva el material `PipeCoolant.tres`: un caño azul sólido con vetas
de refrigerante corriendo por dentro. Con la válvula cerrada el patrón **frena hasta parar** en
vez de apagarse — la fase la acumula `PipeCoolantRun.gd`, por eso el frenado es continuo. La
niebla son partículas de `GasParticleManager` con dither (así resuelve GLES2 la transparencia).

**Dónde tocar para mejorarlo.** `FogAdapter.particle_scale` y `particles_at_full` para la
densidad de la nube; `fill_duration` para que entre más o menos rápido; `PipeCoolantRun.base_color`
y `flow_color` para el caño.

---

## 2. Energía auxiliar (verde) — el circuito que abre la puerta

**Qué hace.** El respaldo eléctrico del sector. Su fallo no daña: **bloquea la ruta**.

| | |
|---|---|
| Lógica | `core_v2/systems/auxpower/AuxPowerBus.gd`, `SealedDoorLock.gd` |
| Pegamento | `core_v2/systems/circuit/LogicCircuitManager.gd` |
| Escena | `core_v2/tests/stations/AuxPowerStation.tscn` |
| Tests | `core_v2/tests/test_auxpower.gd`, `test_circuit_determinism.gd` |

**El ciclo.** El sector arranca `OFFLINE`: la lectura OD-02 parpadea y la puerta está sellada.
Bajar la palanca pide arranque al bus → `RESTORING` (la energía sube en 2,5 s) → `POWERED`.
Subir la palanca corta y todo vuelve a sellarse.

**El interruptor — y acá está la parte interesante.** La puerta **no** la abre la palanca: la
abre un **circuito lógico real**. El grafo es:

```
Fuente (gabinete)  ──┐
                     ├─ AND ─→ Puerta
Palanca ─────────────┘
```

Con la palanca abajo pero sin energía, la puerta no abre. Esa es la regla del sistema, y el
`AND` es lo que la vuelve legible. Los **cables amarillos** que se ven en la sala los genera el
propio `LogicCircuitManager` a partir de las conexiones del grafo; la caja de empalmes es el
cuerpo físico de esa compuerta.

**Dónde tocar para mejorarlo.** El grafo está embebido en la escena como `CircuitGraphResource`:
se le pueden agregar nodos (más paneles, una compuerta `DELAY` para una secuencia) sin tocar
código. El editor visual existe en `addons/odyssey_circuit_editor` y está habilitado.

---

## 3. Plasma (ámbar) — la barrera que corta el paso

**Qué hace.** La energía de alta temperatura. Su fallo **sí daña**: un chorro que corta el paso.

| | |
|---|---|
| Lógica | `core_v2/systems/plasma/PlasmaConduit.gd`, `PlasmaRoute.gd` |
| Escena | `core_v2/tests/stations/PlasmaStation.tscn` |
| Tests | `core_v2/tests/test_plasma_conduit.gd` |

**El ciclo.** `NOMINAL → OVERHEATING` (la tubería brilla más, 4 s — **todavía no hay daño**)
`→ VENTING` (el chorro sale y la barrera lastima) `→` el jugador **redirige** `→ REROUTED` (se
apaga en 2,5 s) `→ NOMINAL`.

**La lógica de los interruptores.** La conducción se **bifurca en una junta**: un ramal sigue
de largo y está roto, el otro dobla y está sano.

```
        ┌─ ValveA ─→ ramal ROTO ──→ ✵ rotura
entrada ┤
        └─ ValveB ─→ ramal SANO
```

`PlasmaRoute` vigila las dos válvulas contra un patrón: **cerrar A, abrir B** (`required_pattern
= [0, 1]`). Cuando el patrón coincide llama `reroute()` y el chorro se apaga; si se rompe, el
aviso vuelve a empezar. Redirigir es eso: mandar el plasma por el caño que no está roto.

> Ojo: cerrar **las dos** no es la solución. Eso corta todo y no es "redirigir" — fue justamente
> el error que hacía incomprensible la sala en su primera versión.

**Cómo se ve.** El núcleo dentro del caño translúcido cicla color (azul → violeta → carmesí →
oro) tomado de `PlasmaExhaust`; el chorro de la rotura y la barrera de daño usan
`gas_plasma_flipbook.shader`, una variante donde el atlas aporta la **forma** y el color sale de
la partícula — sin eso, un plasma violeta contra una textura de llamas se ve amarillo.

**Dónde tocar para mejorarlo.** El ramal sano se lee corto: alargarlo y darle un destino visible
haría más obvio a dónde va el plasma redirigido. Y la barrera sigue siendo un `FireEmitter`, que
arrastra vocabulario de incendio.

---

## 4. Atmósfera (blanco/rojo) — la presión que estalla

**Qué hace.** La presión y el aire del sector. Su fallo **mueve**: una explosión ambiental que
no mata pero cambia el recorrido.

| | |
|---|---|
| Lógica | `core_v2/systems/atmosphere/PressureSection.gd`, `PurgeDial.gd` |
| Escena | `core_v2/tests/stations/AtmoStation.tscn` |
| Tests | `core_v2/tests/test_pressure_section.gd` |

**El ciclo.** `NOMINAL → RISING` (8 s: el manómetro trepa, el panel parpadea y las juntas
empiezan a soltar vapor, una por una) `→ CRITICAL` (2,5 s: la chispa, última oportunidad) `→`
**estallido** (`blowout`, una sola vez) `→ VENTED → NOMINAL`.

**Los dos mecanismos.** Esta sala tiene las dos direcciones del sistema:

- **La bomba** (`PressurePump`) presuriza. Se **mantiene presionada**: el pistón baja mientras
  dura el esfuerzo. Es el primer uso de `HoldInteractableV2` en el proyecto.
- **El sintonizador** (`PurgeTuner`) purga. También se sostiene: la aguja **barre** la escala y
  se **suelta** al pasar por la zona verde; si queda dentro 1,2 s, purga.

El manómetro holográfico muestra las tres lecturas en un arco: presión actual, tramo rojo de
peligro y zona verde con la aguja de ajuste. Es UI 2D dibujada en un `Viewport` y proyectada con
`HoloGlass`, el mismo patrón que el selector radial del ascensor.

**Dónde tocar para mejorarlo — es el más flojo visualmente.** El estallido todavía no existe
como imagen: `blowout(radius, force)` es una señal que **nadie escucha**. Ni empuja al jugador,
ni rompe nada, ni cambia el recorrido. Ese es el agujero grande. Igual que `is_sealed()`, que
está expuesto y sin usar. La sala tampoco tiene todavía nada que la explosión pueda alterar:
eso pide un nivel real, no una plataforma.

---

## Interacción sostenida (mantener presionado)

Capacidad nueva que salió de esta tanda y sirve más allá de estos sistemas.

`core_v2/components/HoldInteractableV2.gd` acumula progreso mientras el jugador sostiene la
tecla de interacción y lo descarga al soltar. Expone `hold_progress`, señales por etapa
(`hold_started`, `hold_completed`, `hold_released`) y el gancho `_update_hold_visuals(progress)`
para que la subclase mueva lo que le toque.

Para un resorte que quede cargado: `release_rate = 0` (no se descarga) y `repeatable = false`.

Debajo, `InputDataV2` distingue `interact` (flanco, dispara al pulsar) de `interact_held`
(sostenido). Ambos se serializan, así que una pulsación larga se reproduce igual en un replay.

---

## Cómo probar los cuatro

```bash
# el banco completo, headful, para recorrerlo caminando
tools/launch_game.sh
# y desde el peer, forzar la escena (el --scene se pisa con el arranque):
curl -s -XPOST localhost:4999/command \
  -d '{"action":"execute_script","args":{"script":"SceneManager.goto_scene(\"res://core_v2/tests/TestShipSystems.tscn\")"}}'

# una estación aislada, con capturas
./test_prop.sh CryoStation      # o PlasmaStation, AtmoStation, AuxPowerStation

# la lógica, sin ventana
./runtest.sh -a ./core_v2/tests/test_coolant_leak.gd
./runtest.sh -a ./core_v2/tests/test_plasma_conduit.gd
./runtest.sh -a ./core_v2/tests/test_pressure_section.gd
./runtest.sh -a ./core_v2/tests/test_auxpower.gd
```

> Un comportamiento "espontáneo" visto en una ventana headful no es evidencia de nada hasta
> reproducirlo en `--headless`: la ventana con foco recibe teclado y es un jugador más.

## Colisión

Los props de estas salas viven en la **capa 7 (Prop)**. La cámara enmascara Entorno +
CameraCollision (129), así que no choca con ellos: el spring arm no salta al pasar junto a una
tubería. Al agregar un prop nuevo, ponerle `collision_layer = 64`.
