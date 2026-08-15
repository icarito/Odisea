# FD-255: Los 4 Sistemas de la Nave — Documento Maestro

**Status:** Design
**Priority:** High
**Effort:** Medium
**Created:** 2026-08-15
**Children:** FD-256 (Criocoolant), FD-257 (Plasma), FD-258 (Atmósfera), FD-259 (Energía auxiliar)

## Principio rector

La Odisea es una nave colonizadora de 8 km cuyo único trabajo es **mantener viva a la
humanidad en criogenia**. Cada elemento industrial es un *órgano con función*, no decorado.
Si cada prop tiene una tarea real, el layout se lee solo: una válvula de coolant pertenece
junto a los criopods, una conducción de plasma junto a la energía, una esclusa junto a la
presión.

> **Regla de legibilidad:** un peligro ambiental solo es legible si el jugador ve su
> *fuente funcional* antes de sufrirlo. Leer una sala = ver qué circuito domina el espacio.

## Los 4 sistemas como lenguaje de diseño

| Sistema | Color | Función | Vive junto a | Fallo | Aviso | Liberación |
|---|---|---|---|---|---|---|
| **Criocoolant** | cian | Refrigerante que congela los pods | criopods | Fuga de gas frío → niebla (ciega, no daña) | condensación → gotas → nube | Sellar válvula |
| **Plasma** | ámbar | Energía de alta temperatura | conducciones de energía | Fuga de plasma → barrera de daño | tubería brilla → zumbido → chorro | Redirigir flujo |
| **Atmósfera** | blanco/rojo | Presión y aire del sector | esclusas y compuertas | Sobrepresión → explosión ambiental | parpadeo → chispa → boom | Purgar/igualar presión |
| **Energía auxiliar** | verde | Respaldo de emergencia | consolas, levers, salas B | Sin energía → puertas selladas | lectura OD-02 parpadea → bloqueo | Accionar lever/secuencia |

El color dice *qué falla* antes de que dañe; el fallo dice *qué restaurar*. Y cada
liberación es **reordenar ese órgano** — de ahí sale "ganar = recuperar control".

## Mapeo a assets existentes

| Sistema | Assets ya existentes (reutilizar) | Integración pendiente |
|---|---|---|
| Criocoolant | `core_v2/systems/ice/` (IceLevel, IceVisualBand), `props/pipe/` (PipeValve, PipeSection/Corner/Tee), `systems/gas/` (GasArea3D para niebla) | Renombrar/integrar `visual/plasma_exhaust/PlasmaExhaust_D` como **CryoVent** |
| Plasma | `props/exhaust/PlasmaExhaust.tscn` (nozzle con IDLE/FLARE/SURGE), `systems/fire/` (FireSystem/FireEmitter), `systems/gas/` (gas inflamable) | Mantener `props/exhaust/PlasmaExhaust` como plasma real |
| Atmósfera | `systems/AirlockPool.gd`, `props/doors/AirlockChamber.tscn`, `IrisDoorV2.tscn`, `VerticalDoor.tscn` | — |
| Energía auxiliar | `systems/circuit/` (LogicCircuitManager, CircuitGraphResource, CircuitCable destructible, CircuitTerminalBridge), `InteractableBaseV2` (levers, terminales) | — |

## Integración y nombres coherentes de los efectos

Hoy hay dos cosas con nombre casi idéntico que cumplen roles distintos:

- `core_v2/visual/plasma_exhaust/PlasmaExhaust_D.tscn` — pluma **genérica tintable**
  (capa A = cáscara volumétrica + capa C = partículas, con `core_color`/`hot_color`
  compartidos). Por defecto es azul. **Es el crioenfriador**: renombrar a `CryoVent`.
- `core_v2/props/exhaust/PlasmaExhaust.tscn` — nozzle de reactor con máquina de estados
  (IDLE/FLARE/SURGE) y ciclo de color. **Es el plasma real**: queda como está.

Cada FD hijo detalla el renombre/integración que le toca. No se borra nada; se aclaran
nombres y se asigna cada efecto a un sistema.

## Estructura de cada FD hijo (mantener simple)

Cada FD-25x describe UN sistema con el mismo esqueleto mínimo:
1. Función y lugar físico
2. Lenguaje visual (color + señal)
3. Fallo y aviso (patrón legible)
4. Liberación (mini-game de restaurar)
5. Assets a reutilizar + archivos a crear/renombrar
6. Verificación

## Scope y orden

- Cada sistema es independiente y se puede construir/testear aislado (F6 por escena).
- Orden sugerido: Criocoolant → Plasma → Atmósfera → Energía auxiliar (de lo sensorial a lo
  estructural).
- Los mini-games de liberación reutilizan `InteractableBaseV2` y `LogicCircuitManager`;
  **no** se inventa un sistema de interacción nuevo.
