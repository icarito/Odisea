# FD-030: Cargol — Dron Asistente

> Documento de feature colaborativo (Sebastian + Opus + Odiseo).
> Detalla qué es Cargol, qué hace hoy, qué proponemos agregar,
> y los contratos de determinismo que no se pueden romper.
> Las decisiones abiertas van como `[DECIDIR]`.

**Status:** Draft  
**Acto:** I — Vertical Slice  
**Relacionado:** GDD_v3, PushableBox, core_v2, CargolDroneV2, PR #198, PR #199  

---

## 0. Propósito y alcance

Cargol es el dron compañero no-piloteable de Elías. Este FD cubre tres capacidades
encadenadas: **movimiento/seguimiento** (ya implementado), **carga de objetos**
(implementado en modo clamp rígido), y la familia **tether → winch → polea/contrapeso**
(propuesta post-VS). También define la **capa de comando del player**.

Lo que queda explícito SIN decidir: el reparto lógica/visual de `CargolDroneV2`,
el modo de carga para el VS, y la arquitectura del punto de redirect (§12).

---

## 1. Estado actual (implementado)

`CargolDroneV2` es un `KinematicBody` con `class_name`.

### API pública

| Método | Qué hace |
|--------|----------|
| `move_to(position: Vector3)` | Vuela directo a una posición |
| `follow_path(path: NodePath)` | Sigue una curva `Path` |
| `follow_target(target: Node, distance)` | Sigue a un nodo manteniendo distancia |
| `return_to(position)` | Vuelve a home |
| `set_velocity(vector: Vector3)` | Control manual de velocidad |
| `stop()` | Frenar en seco |
| `pickup(target_node_path)` | Agarra un `RigidBody`, lo reparenta al `CargoAnchor` |
| `release(impulse: Vector3)` | Suelta el objeto con impulso |

### Integración level design

- **`CargolController.gd`** — palanca → `follow_target(player)` / `return_to(home)`
- **`CargolDroneProp.gd`** — wrapper PropZoo equivalente

### Lo que NO existe hoy

- Target navegable por nombre — todo es posición absoluta o `NodePath`
- Modo tethered/winch — `pickup` solo reparenta (clamp rígido)
- Comando directo del player — Cargol se dispara por interactables

---

## 2. Fantasía y rol

Cargol es **esencial pero dependiente**: el player atraviesa el mundo *a través* de
Cargol sin que Cargol sea piloteable. Elías no se vuelve autónomo ni poderoso por
tener a Cargol; gana posibilidad a costa de coordinación.

Restricción de tono: cualquier capacidad de movilidad (hook, swing) se diseña **no**
para disolver la vulnerabilidad ni el sigilo.

---

## 3. Sistema de carga — dos modos

### 3.1 Clamp rígido (ACTUAL — VS)
`pickup()` reparenta el `RigidBody` al `CargoAnchor`. La caja viaja solidaria a
Cargol. Simple, sin oscilación.

### 3.2 Tethered / Winch (PROPUESTO — post-VS)
La caja cuelga de un cable. Oscila (péndulo), conserva momentum. **No** es
reparenting: es un constraint de cable resuelto por un solver determinista (§5).

`[DECIDIR]` — Modo de carga para el VS: solo Clamp. Tethered va al backlog.

### 3.3 Máquina de estados de la caja

```
Free ↔ Held(Clamp) ↔ Tethered ↔ Counterweight
```

Cada arista: hand-off determinista + snapshot. `Counterweight` = caja atada a polea (§7).

---

## 4. Verbos y mapeo al código

| Verbo | Estado | API / sistema |
|-------|--------|---------------|
| Mover / volar | Implementado | `move_to`, `follow_path`, `set_velocity`, `stop` |
| Seguir | Implementado | `follow_target`, `return_to` |
| Cargar (clamp) | Implementado | `pickup` / `release` |
| Cargar (tether) | Propuesto | solver de constraints (§5) |
| Anclar como polea | Propuesto | solver + provider de redirect |

---

## 5. El solver de constraints determinista (PROPUESTO — post-VS)

El swing del payload, el swing de Elías (§6) y la polea/contrapeso (§7) **son la
misma cosa** — masas unidas por constraints de cable. No son tres sistemas: son
tres configuraciones de un solo solver.

Requisitos:
- Modelo propio paso fijo (Verlet + constraint de distancia), **no** `PinJoint`/`RigidBody`
- Orden de iteración fijo, conteo fijo
- Provider de redirect como abstracción

`[DECIDIR]` — Provider: anclaje fijo primero (más barato, más autorable). Cargol-polea después.

---

## 6. Hook de Elías (PROPUESTO — post-VS)

Cargol ancla y Elías rapela/se balancea de ese tether. Reusa el solver de §5.

- Independiente del sistema de carga (código separado, componen vía solver)
- Gating de tono: anclajes designados, NO movimiento libre Spider-Man

`[DECIDIR]` — Interacción con sigilo: ¿balancearse detecta DD?

---

## 7. Puzzles de poleas (PROPUESTO — post-VS)

Caja como lastre/contrapeso. Gramática: masa, geometría de anclajes, largo de cable.
**Un solo puzzle de prueba en backlog** — no entra al VS.

---

## 8. Contratos de determinismo (CRÍTICO)

1. **IK puramente cosmético**, downstream del estado lógico
2. **Trigger por proximidad lógica**, nunca por collider del end-effector
3. **`pickup`**: la caja debe seguir el transform lógico, no el visual → **ROTO** (#200)
4. **`release`**: el impulso debe derivarse de velocidad canónica → **ROTO** (#201)
5. **`move_and_slide`**: same-platform OK, cross-platform riesgo documentado (#202)
6. Separación lógica/visual → **no existe** (#203)
7. **Solver**: paso fijo, orden fijo, snapshot en reposo
8. **Múltiples actores sobre caja**: orden fijo de aplicación de fuerzas
9. **Sensibilidad a floats del péndulo**: fixed-point si se necesita cross-platform

---

## 9. Capa de comando del player (PROPUESTO)

El player **no pilotea** a Cargol. Le da **órdenes contextuales**.

### VS mínimo

| Comando | Condición | Implementación |
|---------|-----------|----------------|
| Seguir | Default / tras terminar tarea | `follow_target` |
| Quieto | Cargol idle | `stop()` |
| Ir a target | Mira interactuable con marker | `move_to(target)` + (#204) |
| Cargar / Soltar | Caja en rango | `pickup` / `release` |

**Input mapping tentativo:**
- Tap C → toggle Seguir ↔ Quieto
- Tap C con retícula sobre target → comando contextual (ir / cargar)
- Menú radial post-VS

`[DECIDIR]` — Plataforma primaria del VS sesga el diseño de input. Empezar con teclado+mouse.

---

## 10. Targeting: markers + enumeración

- **MarkerSystem** (PR #199): screen-space overlay, labels
- **TargetRegistry** (#204): world-space data para Cargol

Ambos se alimentan del mismo `MarkerConfig` + `InteractableEntity`, pero son capas
independientes. YAGNI: con 5-10 waypoints en el VS, array ordenado alcanza.

---

## 11. Morfología / IK (referencia, no spec)

- **Armless (VS)**: caja sostenida por campo/pinza magnética. Cero IK. Barato.
- **Con brazos (post-VS)**: 2 manipuladores, IK 2-huesos (ley de cosenos). Evitar `SkeletonIK`.

---

## 12. Decisiones pendientes

| # | Decisión | Estado |
|---|----------|--------|
| 1 | Separación lógica/visual de CargolDroneV2 | `[DECIDIR]` — Issue #203 |
| 2 | Modo de carga VS: solo Clamp | `[DECIDIR]` — Recomendado Clamp |
| 3 | Provider de redirect: anclaje fijo primero | Diferible |
| 4 | Morfología: armless en VS | Recomendado |
| 5 | Float vs fixed-point para swing | Post-VS |
| 6 | Hook ↔ sigilo / DD | Post-VS |
| 7 | Plataforma primaria: teclado+mouse | Recomendado |
| 8 | ~10 waypoints en VS | YAGNI, sin query espacial |
| 9 | Puzzle de polea: fuera del VS | Backlog |

---

## 13. Issues dependientes (pre-requisitos)

| Issue | Título | Bloquea |
|-------|--------|---------|
| [#200](https://github.com/icarito/Odisea/issues/200) | pickup: CargoAnchor dentro del KB → no-determinista | Carga determinista |
| [#201](https://github.com/icarito/Odisea/issues/201) | release: velocity interpolado → no-determinista | Release determinista |
| [#202](https://github.com/icarito/Odisea/issues/202) | move_and_slide: riesgo cross-platform | Replay garantías |
| [#203](https://github.com/icarito/Odisea/issues/203) | Monolito lógica+visual | IK, fixes #200/#201 |
| [#204](https://github.com/icarito/Odisea/issues/204) | TargetRegistry inexistente | Comando contextual |
| [#205](https://github.com/icarito/Odisea/issues/205) | Sin capa de comando del player | Input de Cargol |

---

## 14. Orden de implementación (VS)

1. **#200 + #201**: Fix determinismo de pickup/release (~6 líneas cada uno)
2. **#204**: TargetRegistry simple dentro de InteractionMarker
3. **#205**: Capa de comando tap-C contextual
4. **Cargol integrado en Módulo Criogenia** con comandos funcionando

Post-VS: #203 (separación lógica/visual), solver de constraints, tethered mode, puzzle de polea.

---

*Fin del documento.*
*Convención: `[DECIDIR]` indica que se espera input de Sebastian u Odiseo.*
