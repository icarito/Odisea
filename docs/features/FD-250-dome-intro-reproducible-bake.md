# FD-250: Dome_Intro — Bake reproducible, iluminación híbrida y señalización industrial

**Status:** In Progress
**Priority:** High
**Effort:** Large
**Created:** 2026-08-13
**Completed:** -

## Problem

`Dome_Intro` obtuvo una mejora de rendimiento importante al convertir criopods,
walkways, hub spokes y pisos del hub en geometría precomputada. La optimización
dejó dos problemas de autoría:

- Los seis anillos de criopods fueron horneados desde 218 instancias y la escena
  runtime ya no conserva esas instancias editables.
- Las fuentes de los distintos grupos no están normalizadas: algunos bakers leen
  la escena runtime ya horneada, por lo que un segundo bake puede reutilizar el
  resultado como si fuera fuente.

La iluminación sigue dependiendo de pools `LightPathV2` que nacen en runtime.
Esto impide incluir todos los fixtures en un lightmap y mantiene más luces
dinámicas de las necesarias. También falta señalización visible en las uniones
walkway/ring hub y una paleta industrial coherente en las barandas.

## Solution

Separar explícitamente autoría y runtime:

```
Fuentes editables ──bakers deterministas──> mallas/colliders/materiales ──> Dome_Intro runtime
     │                                                                  │
     └── rig estático BakeLights ── BakedLightmap ─────────────────────┘
```

1. Conservar subescenas fuente para criopods, scaffolds y ring hubs. La fuente
   de criopods reproduce exactamente el layout previo a `93b00907`, sin revertir
   cambios posteriores de la escena.
2. Cada baker recibe una fuente explícita y nunca vuelve a recolectar una malla
   previamente horneada como fuente de edición.
3. Generar marcas planas de transición con franjas amarillas sobre el borde
   exterior de cada ring hub y sobre las uniones stairs/walkways/spokes.
4. Aplicar amarillo/naranja industrial sólo a barandas, manteniendo vigas y
   estructura en acero oscuro.
5. Crear un rig de luces de bake, con una luz estática por fixture relevante.
   Esas luces se usan para el lightmap y no sobreviven como coste runtime. El
   runtime mantiene entre tres y cinco luces dinámicas, sólo para personajes,
   efectos y feedback cercano.

### Considered Options

- **Revertir `Dome_Intro.tscn` completo a pre-bake** — recupera la fuente, pero
  descarta optimizaciones, hielo y trabajo de iluminación posterior.
- **Editar las mallas horneadas** — mantiene rendimiento, pero no permite
  iteración espacial ni rebakes fiables.
- **Fuentes separadas + productos versionados** — conserva los resultados de
  runtime y permite modificar/rehornear desde el layout original.
- **Selected:** fuentes separadas + productos versionados.

## Contracts

- `Dome_Intro.tscn` sigue siendo la escena runtime; no contiene nodos fuente
  pesados de criopods ni luces de bake activas.
- Las posiciones, colisiones y visibilidad de los criopods se verifican contra
  la escena pre-bake (`93b00907^`).
- Los bakers no arrancan `PropDitherManager` ni conservan ShaderMaterial de
  runtime en sus artefactos.
- Las franjas de seam se generan sobre la geometría de deck existente, sin
  colisión: quedan elevadas visualmente, pero no alteran la superficie caminable.
- Las luces de bake se controlan por `light_bake_mode`; ocultar un nodo no es un
  mecanismo válido para excluirlo del bake en Godot 3.

## Files to Modify

- `docs/features/FD-250-dome-intro-reproducible-bake.md` (new)
- `docs/features/FEATURE_INDEX.md` (modify)
- `core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn` (new)
- `core_v2/levels/interiors/DomeIntro_ScaffoldSource.tscn` (modify)
- `core_v2/levels/interiors/DomeIntro_IndustrialRailing.tscn` (new, source
  variant used by radial walkway generation)
- `core_v2/levels/interiors/DomeIntro_IndustrialStairs.tscn` (new, source
  variant used by radial stair generation)
- `core_v2/levels/interiors/DomeIntro_HubTowerSource.tscn` (new, if extraction
  is required to eliminate the runtime scene as source)
- `core_v2/levels/interiors/DomeIntro_BakeLights.tscn` (new)
- `core_v2/levels/interiors/Dome_Intro.tscn` (modify, runtime products/config only)
- `core_v2/props/scaffold/ScaffoldHubRing.gd` (modify)
- `core_v2/props/scaffold/SteelGratePlatform.gd` (modify only if seam/rail
  authoring needs an existing extension)
- `core_v2/props/scaffold/ScaffoldSeamPlate.*` (new)
- `materials/diamondPlateAluminum/seam_hazard_stripes.*` (new stripe overlay)
- `tools/bake_dome_intro_criopods.gd` (modify)
- `tools/bake_scaffold_walkways.gd` (modify)
- `tools/bake_dome_intro_hub_floors.gd` (modify)
- `tools/verify_criopod_bake.gd` (modify)
- `tools/generate_dome_intro_bake_lights.gd` (new)
- `tools/set_dome_intro_bake_lights.gd` (new)
- `tools/verify_dome_intro_seams.gd` (new)
- `tools/verify_dome_intro_bake_lights.gd` (new)
- `tools/verify_dome_intro_runtime_light_budget.gd` (new)

## Implementation Plan

1. Crear este FD y registrar el estado del trabajo.
2. Extraer el layout editable de criopods desde `93b00907^` a una subescena
   fuente; adaptar baker/splicer/verificador para comparar fuente y producto.
3. Hacer que los bakers de scaffold y hub floors carguen una fuente explícita,
   preservando las aperturas y colisiones actuales.
4. Separar la superficie de barandas de los ring hubs; aplicar paleta amarilla/
   naranja a rails y rehornear sus productos.
5. Generar las franjas de seam desde las fuentes: los cinco bordes exteriores
   de hub, diez uniones stairs/walkways y cuatro uniones walkway/spoke, sin
   geometría PBR separada ni colisión.
   Las franjas responden al lightmap; no usan emisión propia.
6. Crear el rig de bake de luces y un workflow de bake que permita encender todos
   los fixtures estáticos, hornear, y volver al presupuesto de runtime acordado.
7. Ejecutar verificación geométrica, inspección visual, smoke de assets, tests
   relevantes y suite completa final.

## Bake Light Workflow

1. Si cambian fixtures o sus MultiMeshes, regenerar el rig:
   `godot3-bin --no-window -s tools/generate_dome_intro_bake_lights.gd`.
2. Activar sólo sus modos de bake:
   `ODISEA_BAKE_LIGHTS=1 godot3-bin --no-window -s tools/set_dome_intro_bake_lights.gd`.
3. Abrir `Dome_Intro.tscn` con Godot 3, seleccionar `BakedLightmap` y ejecutar
   **Bake Lightmaps**. Para iterar, usar calidad Low/bounces 1; para el producto
   final usar la calidad acordada y conservar `Dome_Intro.lmbake` versionado.
4. Desactivar inmediatamente las luces del rig:
   `ODISEA_BAKE_LIGHTS=0 godot3-bin --no-window -s tools/set_dome_intro_bake_lights.gd`.
   Las luces permanecen invisibles y con bake deshabilitado en runtime; el
   lightmap ya cocinado no se pierde.
5. Verificar `verify_dome_intro_bake_lights.gd` y
   `verify_dome_intro_runtime_light_budget.gd`. El presupuesto actual es cinco
   OmniLights dinámicas en pools: 1 exit, 1 ramp, 1 spoke y 2 wall fixtures.

## Verification

1. Ejecutar el bake de criopods desde `DomeIntro_CriopodsSource.tscn` dos veces:
   la segunda ejecución debe producir la misma huella de artefactos y no leer
   `Dome_Intro.tscn` como fuente.
2. Comparar pre-bake y producto con `verify_criopod_bake.gd`: misma huella de
   colisión, AABBs de anillos e integración con `IceSubmergedCuller`.
3. Rehornear walkways, spokes y los cinco ring hubs desde sus fuentes; comprobar
   aperturas, uniones y colisiones en Dome_Intro.
4. Capturar visualmente seams y barandas: sin z-fighting, huecos, escalones ni
   cambio de cámara/movimiento.
5. Hacer un bake de prueba de luces con calidad baja y uno final con el perfil
   aprobado; comprobar que runtime mantiene 3–5 luces dinámicas y que los
   objetos dinámicos siguen recibiendo iluminación de capture.
6. Ejecutar `python3 scripts/check_tracked_imports.py`,
   `python3 scripts/check_critical_import_artifacts.py`, smoke de imports y
   `./runtest.sh` antes de cerrar el FD.

## Out of Scope

- Cambiar gameplay, gravedad, colisiones de plataformas o cámara.
- Añadir nuevos sistemas de iluminación dinámica, reflection probes o postprocesado.
- Modificar otros niveles o assets fuera de Dome_Intro.
- Eliminar artefactos horneados ya versionados: se regeneran y validan, no se
  tratan como caché descartable.
