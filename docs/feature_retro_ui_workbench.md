Especificación Técnica: Odisea Workbench (Retro Debug UI)
1. Concepto Visual y Estético

Una interfaz gráfica de usuario (GUI) diegética que emula sistemas operativos de principios de los 90.

    Paleta: "Classic Grey" (#C0C0C0), Azul Profundo (#000080) para barras de título activas, Gris Oscuro (#808080) para sombras.

    Estilo: "Chunky Bevels". Botones y ventanas con bordes claros (Top/Left) y oscuros (Bottom/Right) para simular 3D falso.

    Tipografía: Pixelada Monospaced (ej. Topaz de Amiga o PixelOperator).

    Resolución: Pixel-perfect scaling (no antialiasing en fuentes).

2. Secuencia de Arranque (Boot-up Screen)

Antes de mostrar el escritorio, se ejecuta una secuencia de inicio falsa. Nodo: BootSplash.tscn (Control). Secuencia:

    BIOS Post: Fondo negro. Texto blanco apareciendo línea por línea: ODISEA SYSTEMS BIOS v2.0 CHECKING MEMORY... 640K OK MOUNTING VOLUME: SECTOR_07... OK

    OS Load: Logotipo de "OdiseaOS" (ASCII art o Pixel art) con una barra de carga simple.

    Login: "INITIALIZING USER: ELIAS... ACCESS GRANTED".

    Transición: Fade out a la vista 3D del juego con el Overlay de la UI encima.

3. Arquitectura de Nodos (Godot 3.6)

La UI reside en un CanvasLayer con layer = 100 para estar siempre encima.
Jerarquía Propuesta

DebugOverlay (CanvasLayer)
└── Desktop (Control) - Full Rect, Mouse Filter: Pass
    ├── BootScreen (ColorRect) - Visible al inicio
    ├── TaskBar (Panel) - Bottom aligned
    │   ├── StartButton (Button) - "SYSTEM"
    │   ├── ActiveTasks (HBoxContainer)
    │   └── Clock (Label)
    └── WindowArea (Control) - Full Rect, Mouse Filter: Ignore
        ├── Window_NodeExplorer (RetroWindow)
        ├── Window_Inspector (RetroWindow)
        └── Window_Terminal (RetroWindow)

4. Componente Base: RetroWindow.tscn

Todas las herramientas heredan de esta escena base.
Estructura

RetroWindow (PanelContainer) -> Script: RetroWindow.gd
└── VBoxContainer
    ├── TitleBar (Panel) -> Script: Draggable.gd
    │   ├── TitleLabel (Label)
    │   └── BtnClose (TextureButton)
    └── Content (MarginContainer) - Aquí van las Apps

Lógica (RetroWindow.gd)

    Drag & Drop: Al hacer click en TitleBar, cambia rect_position siguiendo al mouse.

    Focus: Al hacer click en la ventana, ejecuta raise() para traerla al frente visualmente y cambia el color de la TitleBar a Azul (Activo) vs Gris (Inactivo).

    Resizable: (Opcional para MVP) Un pequeño control en la esquina inferior derecha.

5. Aplicaciones (Tools)
App 1: The Scanner (Node Explorer)

    Propósito: Inspeccionar la escena 3D actual.

    UI: Un Tree node.

    Lógica: - Botón "Refresh": Recorre get_tree().current_scene.

        Filtra nodos irrelevantes.

        Destaca en negrita nodos de grupos: player, interactable, replay_sync.

        Al seleccionar un ítem, envía señal node_selected(node_ref) al Inspector.

App 2: The Inspector (Property Grid)

    Propósito: Ver variables del nodo seleccionado.

    UI: Tree (Columnas: Variable, Valor).

    Lógica: - Muestra global_transform.origin.

        Si es InteractableV2: muestra is_active, anim_progress.

        Si es Pilot: muestra velocity, state.

        Actualiza los valores en _process (poll) cada 0.1s.

App 3: OYS Shell (Terminal)

    Propósito: Ejecutar OdysseyScript.

    UI: - RichTextLabel (Historial, estilo consola).

        LineEdit (Prompt >_).

    Lógica:

        Recibe comandos de texto.

        Si empieza con run, carga un archivo .oys.

        Si es un comando directo (SET gravity 5), lo pasa al OYS_Interpreter.

6. Definición del Tema (Godot Theme)

Crear un recurso RetroOS.theme.

    Panel (Window/Taskbar): StyleBoxFlat

        Bg Color: #C0C0C0

        Border Width: 2px.

        Border Colors: Left/Top #FFFFFF (Luz), Right/Bottom #404040 (Sombra).

    Button (Normal): Igual que Panel.

    Button (Pressed): Invertir colores de borde (Left/Top oscuro, Right/Bottom claro) para efecto de hundimiento.

    Font: Pixel font tamaño 16px.

7. Integración

    Tecla de Acceso: TAB o F1.

    Comportamiento: Al abrir, Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE). Al cerrar, vuelve a CAPTURED.