Specification: Automated Prop Zoo (TestScenePropZoo)

1. Overview

The Prop Zoo is a diagnostic and preview scene that automatically discovers and displays all interactive props located in res://core_v2/props/. Each prop is placed in an isolated "exhibit" cell equipped with an activation lever to test states (Active/Inactive) and deterministic animations.

2. Scene Structure

Spatial (PropZooRoot)

WorldEnvironment (Standard lighting for clarity)

DirectionalLight

GridContainer (Spatial): A script-driven node to manage the layout.

Exhibits (Node): Container for generated exhibit instances.

Player/Camera: A simple flying camera or a static observer with a cyclable view.

3. The "Exhibit" Template (Exhibit.tscn)

Each cell consists of:

Floor Mesh: A 4x4 meter platform.

Label3D: Displays the filename of the prop.

PropAnchor (Spatial): The position where the discovered prop is instantiated.

Lever (RotatingObjectV2):

A predefined lever that signals the prop.

Logic: Connected via code to the set_active() or _on_interact() method of the spawned prop.

4. Automation Logic (PropZoo.gd)

A. Directory Scanning

Use the Directory class to crawl res://core_v2/props/.

Filter for .tscn files.

Exclude base classes (e.g., InteractableBaseV2.tscn).

B. Instantiation Flow

Loop through validated paths.

Instance the Exhibit.tscn.

Instance the Prop and child it to PropAnchor.

Wire Connections:

If the Prop is a subclass of InteractableBaseV2, connect the Lever's activated signal to the Prop's set_active(true).

Update the Label3D with the prop's name.

5. Script Implementation (Draft)

extends Spatial

export(String, DIR) var props_path = "res://core_v2/props/"
export(PackedScene) var exhibit_scene # Preload Exhibit.tscn

func _ready():
    _generate_zoo()

func _generate_zoo():
    var dir = Directory.new()
    if dir.open(props_path) == OK:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        var index = 0
        
        while file_name != "":
            if file_name.ends_with(".tscn") and not "Base" in file_name:
                _create_exhibit(props_path + file_name, index)
                index += 1
            file_name = dir.get_next()

func _create_exhibit(path, idx):
    var exhibit = exhibit_scene.instance()
    add_child(exhibit)
    
    # Simple grid layout logic
    exhibit.translation = Vector3((idx % 5) * 6, 0, (idx / 5) * 6)
    
    var prop_res = load(path)
    var prop_instance = prop_res.instance()
    exhibit.get_node("PropAnchor").add_child(prop_instance)
    exhibit.get_node("Label").text = path.get_file()
    
    # Logic to link Lever -> Prop
    var lever = exhibit.get_node("Lever")
    if prop_instance.has_method("set_active"):
        lever.connect("activated", prop_instance, "set_active", [true])
        lever.connect("deactivated", prop_instance, "set_active", [false])


6. Testing Goals

Visual Check: Are materials and shaders (like HoloGlass) rendering correctly?

Interaction Check: Does the lever trigger the anim_progress correctly?

Determinism Check: Does the prop reach 1.0 or 0.0 exactly as expected?