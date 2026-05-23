extends Node
class_name PlateSlotConfig

# Inspector-only config node consumed by PlateContentStream on _ready().
export(int) var spiral_idx := 0
export(int) var plate_idx := 0
export(PackedScene) var content_scene: PackedScene
export(Vector3) var content_spawn_offset := Vector3.ZERO
