import sys

def patch_file(path, old, new):
    with open(path, 'r') as f:
        content = f.read()
    if old in content:
        with open(path, 'w') as f:
            f.write(content.replace(old, new))
        print(f"Patched {path}")

# Add debug prints to ControllerManager
patch_file('core_v2/player/ControllerManager.gd', 
    'func switch_to(new_mode: int) -> void:', 
    'func switch_to(new_mode: int) -> void:\n\tprint("[ControllerManager] switch_to called with: ", new_mode)')

# Add debug prints to ZeroGravityZone
patch_file('core_v2/props/ZeroGravityZone.gd', 
    'func _on_body_entered(body: Node) -> void:', 
    'func _on_body_entered(body: Node) -> void:\n\tprint("[ZeroGravityZone] Body entered: ", body.name)')

patch_file('core_v2/player/ZeroGravityController.gd',
    'func _physics_process(dt: float) -> void:',
    'func _physics_process(dt: float) -> void:\n\t# print("[ZeroGravityController] ticking")')

