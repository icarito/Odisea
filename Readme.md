# Base de juego en Godot 4 (sobre plantilla COGITO)

Este repositorio es una base jugable para simulaciones inmersivas en primera persona (FPS) construida sobre la plantilla COGITO para Godot 4. Úsalo como punto de partida para tus propios proyectos: ejecuta, explora y extiende.

Recomendación: evita editar `addons/cogito/` u otros plugins para facilitar futuras actualizaciones; coloca tu código en `res://scenes/scripts/` y tus escenas en `res://scenes/`.
- Usa los singletons existentes: `CogitoSceneManager`, `CogitoGlobals`, `CogitoQuestManager`, `Audio`, `InputHelper`.

## Empezar rápido

1. Instala Godot 4.x 
2. Abre este proyecto desde Godot y ejecuta con F5.
3. Activa los plugins (si no lo están):
   - Cogito, Quick Audio, Input Helper, Godot Aerodynamic Physics, Virtual Joystick (Proyecto > Plugins).
4. Escena de entrada: definida por UID en `project.godot` (normalmente `addons/cogito/DemoScenes/COGITO_0_MainMenu.tscn`).
5. Input Map: si faltan acciones, abre `addons/cogito/CogitoSettings.tres` y pulsa “Reset Project Input Map”, luego reinicia Godot.

### Controles táctiles (móvil/tableta)

Este proyecto incluye controles táctiles para dispositivos móviles y tabletas. Los controles se muestran automáticamente en dispositivos con pantalla táctil. Ver `docs/TOUCH_CONTROLS.md` para más detalles.

## Cómo explorar y hacer cambios

- Escenas propias: `res://scenes/`.
- Scripts propios: `res://scenes/scripts/` (utilitarios en `scenes/scripts/system/`).
- Extensión:
  - Hereda escenas desde `addons/cogito/PackedScenes/*` y guarda fuera del addon.
  - Añade componentes desde `addons/cogito/Components/*` como hijos en tus escenas.
  - Hereda scripts (`extends CogitoWieldable`, `extends CogitoInventory`, etc.).
- Persistencia: usa los grupos `Persist` (re-instancia) o `save_object_state` (solo estado) e implementa `save()`/`set_state()` cuando corresponda.

## Subsistemas disponibles (resumen)

- Inventario flexible basado en Resources y UI desacoplada.
- Gestión de escenas, fade, guardado/carga y slots con `CogitoSceneManager`.
- Misiones (QuestSystem) con persistencia.
- Interacciones y objetos empuñables (Wieldables).
- Pisadas dinámicas por superficie (DynamicFootstepSystem).
- Audio simple 2D/3D via `Audio` (Quick Audio).
- Ayudantes de entrada con `InputHelper`.
- NPC/Enemigos básicos con NavigationAgent y estados por componentes.
- Menú principal/pausa/opciones listos para usar.

## Exportación web

- Preset “Web” escribe en `build/index.html` (ver `export_presets.cfg`).

## Herramientas de desarrollo

- Integración opcional de asistente de IA: `tools/godot-mcp/` (ver `tools/godot-mcp/README.md`).

---

## Acerca de COGITO (resumen)

![COGITO_banner](addons/cogito/COGITO_banner.jpg)

[![GodotEngine](https://img.shields.io/badge/Godot_4.x-blue?logo=godotengine&logoColor=white)](https://godotengine.org/) [![COGITO](https://img.shields.io/badge/version_1.1.x-35A1D7?label=COGITO&labelColor=0E887A)](https://github.com/Phazorknight/Cogito)

COGITO es una plantilla de simulación inmersiva para Godot 4 que ofrece un punto de partida completo para juegos FPS: controlador de jugador, objetos interactivos (puertas, cajones, ítems), inventario, misiones, menús, guardado/carga y ejemplos listos.

- Documentación: https://cogito.readthedocs.io/en/latest/
- Tutoriales en video: https://cogito.readthedocs.io/en/latest/tutorials.html
- Asset store (beta): https://store-beta.godotengine.org/asset/philip-drobar/cogito

Características destacadas (breve):
- Controlador en primera persona (correr/saltar/agacharse/deslizamiento/escaleras/sentarse) con pisadas dinámicas.
- Inventario por Resources, UI separada y contenedores.
- Interacciones con verificación de atributos y varios objetos de ejemplo.
- NPC básico con NavigationAgent y máquina de estados por componentes.
- Menú principal/pausa/opciones, sistema de misiones y guardado/carga con persistencia por escena.

> Importante: COGITO v1.1 es software de código abierto mantenido por la comunidad y puede contener errores. Úsalo bajo tu propio riesgo y revisa Issues/Discussions.

- Atribución, Contribuyentes y Licencia: https://cogito.readthedocs.io/en/latest/about.html
- Autor de COGITO: Philip Drobar (Phazorknight).

---

## Notas

- Prefijos o rutas de guardado se ajustan desde `addons/cogito/CogitoSettings.tres`.
- Los slots de guardado usan `user://<slot>/...` y el autoguardado se define en `CogitoSettings.tres`.
