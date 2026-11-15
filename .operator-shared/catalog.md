# Shared Partition Catalog

## Tree

- `operator.md`
  - Description: Operator Instructions for this partition.
  - Read If: Auto-injected.
- `catalog.md`
  - Description: This catalog.
  - Read If: Auto-injected.
- `README.md`
  - Description: Qué es Operator Memory y cómo instalarlo.
  - Read If: Nunca durante el trabajo normal.

### `specs/` - Contratos del sistema

- `machine-launch.md`
  - Description: Contrato de física entre el jugador y las piezas rígidas que pisa: excepción unilateral, sin acarreo por delta, reglas de desprendimiento inercial y vuelo balístico; límites conocidos.
  - Read If: Tocando plataformas rígidas, `_update_platform_tracking`, joints de Box3D o cualquier cosa que lance o acarree al jugador.
- `seamless-transitions.md`
  - Description: Contrato e invariantes de las transiciones seamless (buffer físico, lift, gating determinista) e inventario de transiciones del slice.
  - Read If: Cableando o tocando una transición de escena, un airlock o un productor de `goto_scene`.
- `machine-layout.md`
  - Description: Convenciones y recetas del formato JSON de `MachineLevel` (ejes, orden de rotación, retención de piezas, pestillos, paralelogramo).
  - Read If: Armando o editando un nivel de máquinas, o extendiendo `MachineLevel` / el futuro editor.

### `guides/` - Guías de trabajo

- `tests-de-travesia.md`
  - Description: Presupuesto de CI por shard (180 s, `rc=124` anula el rescate de flakes) y receta para recorrer rutas estáticas con el piloto real más rápido que tiempo real.
  - Read If: Escribiendo o depurando un test que mueve a `Pilot_v2` por un nivel, o cuando CI falla por timeout de un shard.

