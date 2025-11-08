# Instrucciones de proyecto Copilot para agentes de codificación de IA

Estas instrucciones ayudan a los agentes de IA a ser productivos de inmediato en este proyecto de Godot 4 basado en la plantilla de simulación inmersiva Cogito. Mantén las respuestas concretas, haz referencia a archivos reales y sigue las convenciones del proyecto que se detallan a continuación.

## Panorama General
- **Motor**: Godot 4.6.dev3 (Forward Plus, Jolt Physics). La configuración principal está en `project.godot`.
- **Arquitectura Principal**: Addon Cogito (en `addons/cogito/`) que proporciona:
  - **Singletons de Autoload** (configurados en el plugin y en `project.godot`):
    - `CogitoGlobals` (`addons/cogito/cogito_globals.gd`): Carga `CogitoSettings.tres`, expone logs, prefijos globales y valores de fade.
    - `CogitoSceneManager` (`addons/cogito/SceneManagement/cogito_scene_manager.gd`): Gestiona transiciones de escena, fade in/out, guardado/carga para escenas y jugador, y manejo de slots.
    - `CogitoQuestManager`: Gestiona grupos de misiones y persistencia.
    - `MenuTemplateManager`: Plantillas para menús de UI.
  - **Sistemas Incluidos**: Inventario (`addons/cogito/InventoryPD/`), componentes de interacción, Wieldables (objetos empuñables), sistema de misiones (QuestSystem), menús fáciles (EasyMenus), escenas de demostración, temas, NPCs/Enemigos básicos, sistema dinámico de pisadas (DynamicFootstepSystem), etc.
- **Autoloads Adicionales**:
  - `Audio` (`addons/quick_audio/Audio.gd`): API simple para audio.
  - `InputHelper` (`addons/input_helper/input_helper.gd`): Ayudantes para mapeo de entradas.
  - `AeroUnits` (`addons/godot_aerodynamic_physics/core/singletons/aero_units.gd`).
- **Escena Principal**: Se establece por UID en `project.godot` (`run/main_scene`). El punto de entrada de la demo es típicamente `addons/cogito/DemoScenes/COGITO_0_MainMenu.tscn`.

## Política: no tocar `addons/cogito/` (extender fuera)
- **Inmutabilidad**: Trata `addons/cogito/` y demás plugins como "vendor" inmutables. No edites sus scripts ni escenas para facilitar futuras actualizaciones del addon.
- **Ubicación de código propio**:
  - **Scripts**: `res://scenes/scripts/` (ya existe) o `res://game/Scripts/`.
  - **Escenas**: `res://scenes/` o `res://game/PackedScenes/` para tus propias escenas reutilizables.
  - **UI/Theme**: `res://ui/` y `res://ui/theme/`.
  - **Recursos**: `res://resources/` (ej. `res://resources/items/`, `res://resources/quests/`).
- **Cómo extender sin modificar**:
  - **Herencia de escenas**: Crea escenas que hereden de `addons/cogito/PackedScenes/*` y guárdalas fuera del addon.
  - **Composición**: Añade componentes de `addons/cogito/Components/*` como hijos en tus escenas.
  - **Herencia de scripts**: Usa `extends CogitoWieldable`, `extends CogitoInventory`, etc., en tus propios scripts.
  - **Autoloads**: Utiliza los singletons ya registrados (`CogitoSceneManager`, `CogitoGlobals`, etc.).
  - **Configuración**: Edita `addons/cogito/CogitoSettings.tres` desde el Inspector en lugar de tocar el código del addon.

## Convenciones y Patrones del Proyecto
- **Patrón de Componentes**: Los objetos se componen de nodos hijos "Componentes" (ver `addons/cogito/Components/`). Por ejemplo, una puerta usa un script raíz (`cogito_door.gd`) más un componente de interacción hijo.
- **Persistencia**:
  - El estado del jugador es un `Resource` (`CogitoPlayerState`) guardado en `user://<slot>/COGITO_player_state_.res`.
  - El estado de la escena es un `Resource` (`CogitoSceneState`) guardado en `user://<slot>/COGITO_scene_state_<scene>.res`.
  - Los prefijos provienen de `CogitoSettings.tres` y se cachean en `CogitoGlobals`.
  - `CogitoSceneManager` gestiona la copia entre directorios `temp` y los slots reales. Usa su API para evitar inconsistencias.
- **Slots de Guardado**: El slot activo por defecto es "A". El nombre del autoguardado se define en `CogitoSettings.auto_save_name` (por defecto, `autosave`).
- **Input Map**: Para un proyecto nuevo, usa el botón "Reset Project Input Map" en `addons/cogito/CogitoSettings.tres` para añadir las acciones necesarias. Reinicia Godot después. Para acciones nuevas, añádelas en `Project Settings > Input Map` siguiendo el formato de `CogitoSettings._on_btn_reset_input_map_pressed()`.
- **Uso de Grupos**:
  - Nodos en el grupo `Persist` se re-instancian y serializan a través de métodos `save()` en `CogitoSceneState`.
  - Nodos en el grupo `save_object_state` persisten el estado de sus variables pero no se re-instancian.
- **Logging**: Activa el log global en `is_logging` dentro de `CogitoSettings.tres`. Usa `CogitoGlobals.debug_log(true, "TAG", "mensaje")`.

## Flujos de Trabajo Típicos
- **Ejecutar en Editor**: Abre el proyecto con Godot y presiona F5. Asegúrate de que los plugins (`Cogito`, `Quick Audio`, `Input Helper`, `Godot Aerodynamic Physics`) estén activados.
- **Exportación Web**: El preset "Web" en `export_presets.cfg` escribe en `build/index.html`.
- **Documentación**: La documentación está en `docs/` (Sphinx). Constrúyela con `make html` desde esa carpeta.
- **Control Asistido por IA (Opcional)**: `tools/godot-mcp/` provee un servidor MCP para lanzar y manipular el proyecto programáticamente.

## Ejemplos de Extensión
- **Objeto Interactivo Propio**:
  1. Crea una escena (`Node3D`), añade `MeshInstance3D` y `CollisionShape3D`.
  2. Adjunta un script de objeto de Cogito (`addons/cogito/CogitoObjects/`) o crea uno propio que herede de ellos.
  3. Añade componentes requeridos como hijos (ej. `BasicInteraction` de `addons/cogito/Components/`).
  4. Si debe persistir, añade el nodo al grupo `Persist` o `save_object_state` e implementa `func save()` y `func set_state()`.
- **Ítem/Wieldable Personalizado**:
  - Crea un `Resource` en `res://resources/items/` con un script que haga `extends CogitoWieldable`.
  - Mantén el recurso estable para que las cargas guardadas (`saved_wieldable_charges`) coincidan.
- **Audio**:
  - Llama a `Audio.play_sound(stream)` para 2D o `Audio.play_sound_3d(stream)` para 3D.

## Archivos Clave a Referenciar
- `project.godot`: Autoloads, input map, render, física, UID de escena principal.
- `export_presets.cfg`: Presets de exportación.
- `addons/cogito/cogito_plugin.gd`: Registro de singletons.
- `addons/cogito/cogito_globals.gd`: Carga de `CogitoSettings.tres` y helpers de debug.
- `addons/cogito/cogito_settings.gd` y `CogitoSettings.tres`: Configuración de Cogito y reseteo de input map.
- `addons/cogito/SceneManagement/cogito_scene_manager.gd`: Transiciones, guardado/carga, slots.
- `addons/cogito/SceneManagement/cogito_player_state.gd`, `cogito_scene_state.gd`: Formatos de persistencia.
- `addons/cogito/DemoScenes/`: Ejemplos funcionales.
- `tools/godot-mcp/README.md`: Integración con MCP para herramientas de IA.

## Cómo Actualizar el Addon
- Mantén `addons/cogito/` sin cambios locales para poder reemplazar la carpeta al actualizar.
- Tras actualizar, valida que los plugins sigan habilitados en `project.godot` y que los prefijos en `CogitoSettings.tres` no hayan cambiado.

## Advertencias y Casos Borde
- Las rutas de guardado usan `user://<slot>/...`. `CogitoSceneManager` se encarga de crear los directorios.
- La restauración de escenas re-instancia objetos `Persist` desde su `filename`. No uses nodos que no sean instancias de escenas en este grupo.
- Algunas escenas de demo emiten warnings benignos en el depurador (ver `docs/gettingstarted.rst`). No intentes "arreglarlos" a menos que sea necesario.
- Es posible que algunos archivos no tengan un `.uid` generado. Si es necesario, se pueden generar resguardando los recursos en el editor de Godot.

## Al Generar Código
- Coloca los scripts de juego en `res://scenes/scripts/` y las escenas reutilizables en `res://scenes/`. No modifiques `addons/cogito/`.
- Usa los singletons existentes (`CogitoSceneManager`, `CogitoGlobals`, `CogitoQuestManager`) en lugar de crear gestores paralelos.
- Si añades nuevas acciones de input, sigue la estructura de `CogitoSettings._on_btn_reset_input_map_pressed()`.
- Mantén la consistencia con los nombres de señales y grupos (`Persist`, `save_object_state`) y provee `save()`/`set_state()` donde se espere persistencia.
