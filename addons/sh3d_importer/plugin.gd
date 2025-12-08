tool
extends EditorPlugin

var filesystem_dock = null

func _enter_tree():
    filesystem_dock = get_editor_interface().get_resource_filesystem_dock()
    if filesystem_dock.has_method("connect"):
        filesystem_dock.connect("file_dropped", self, "_on_file_dropped")
        filesystem_dock.connect("files_dropped", self, "_on_files_dropped")
    print("🛠️ SH3D Importer: Activo")

func _exit_tree():
    if filesystem_dock:
        filesystem_dock.disconnect("file_dropped", self, "_on_file_dropped")
        filesystem_dock.disconnect("files_dropped", self, "_on_files_dropped")
    print("🛠️ SH3D Importer: Desactivado")

func _on_file_dropped(file: String):
    _process_sh3d(file)

func _on_files_dropped(files: Array, target_folder: String):
    for file in files:
        _process_sh3d(file)

func _process_sh3d(sh3d_path: String):
    if not sh3d_path.ends_with(".sh3d"): return

    print("🔄 Procesando: " + sh3d_path)
    OS.shell_open(sh3d_path)
    print("📤 Sweet Home 3D abierto → F8 → Right-click → Export OBJ")
    print("🎯 Godot auto-importará al guardar OBJ en misma carpeta")
