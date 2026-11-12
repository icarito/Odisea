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
- `machine-layout.md`
  - Description: Convenciones y recetas del formato JSON de `MachineLevel` (ejes, orden de rotación, retención de piezas, pestillos, paralelogramo).
  - Read If: Armando o editando un nivel de máquinas, o extendiendo `MachineLevel` / el futuro editor.
