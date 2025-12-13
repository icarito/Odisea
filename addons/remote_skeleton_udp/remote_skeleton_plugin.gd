tool
extends EditorPlugin

const SCRIPT_PATH = "res://addons/remote_skeleton_udp/RemoteSkeletonUDP.gd"

func _enter_tree():
    # Load the script and a class icon
    var script = load(SCRIPT_PATH)
    var icon = get_editor_interface().get_base_control().get_icon("Spatial", "EditorIcons")
    # Register the custom type
    add_custom_type("RemoteSkeletonUDP", "Spatial", script, icon)

func _exit_tree():
    # Clean up when the plugin is disabled
    remove_custom_type("RemoteSkeletonUDP")
