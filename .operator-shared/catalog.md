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
- `transit-run-autopilot.md`
  - Description: Contrato del modo asistido de Transit-Run: el piloto automático como fuente dentro de `InputProviderV2`, invariantes del relevo humano ↔ máquina y del replay, decisiones de nombres frente al plan WFC, límites conocidos.
  - Read If: Tocando `AutopilotInputV2`, el arbitraje de input del jugador, o planificando el generador WFC de ScaffoldOrbit y sus documentos de métricas.
- `scaffold-chunk-catalog.md`
  - Description: Contrato del catálogo de 10 chunks de andamio y su ensamblado 1D por semilla: registro de datos como fuente única, sockets como desplazamientos, invariantes de la ruta principal, desviaciones abiertas frente al brief y lo pendiente (escenas, cilindro, runtime).
  - Read If: Tocando `ScaffoldChunkRegistry`, creando escenas de chunks de andamio, o cableando la generación de tramos Transit-Run.

### `product/` - Intención de producto

- `entrecasco.md`
  - Description: Visión de diseño del entrecasco (corona entre el tubo de terrazas y el casco): qué es el lugar, secciones con rotación distinta, gravedad variable, peligros, y la navegación asistida como herramienta diegética con TAB sostenido. Incluye lo que falta decidir.
  - Read If: Diseñando o construyendo niveles del entrecasco, el modo asistido/autonavegador, o cualquier cosa con gravedad por sección.

### `guides/` - Guías de trabajo

- `tests-de-travesia.md`
  - Description: Presupuesto de CI por shard (180 s, `rc=124` anula el rescate de flakes) y receta para recorrer rutas estáticas con el piloto real más rápido que tiempo real.
  - Read If: Escribiendo o depurando un test que mueve a `Pilot_v2` por un nivel, o cuando CI falla por timeout de un shard.

