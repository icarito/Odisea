import re

with open('project.godot', 'r') as f:
    content = f.read()

# Add rotate_left (Q = scancode 81) and rotate_right (E = scancode 69)
# wait, actually physical_scancode 81 and 69.
if 'rotate_left=' not in content:
    rotate_left = """rotate_left={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":81,"physical_scancode":0,"unicode":0,"echo":false,"script":null)
 ]
}
"""
    content = content.replace('[input]\n', '[input]\n\n' + rotate_left)

if 'rotate_right=' not in content:
    rotate_right = """rotate_right={
"deadzone": 0.5,
"events": [ Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"alt":false,"shift":false,"control":false,"meta":false,"command":false,"pressed":false,"scancode":69,"physical_scancode":0,"unicode":0,"echo":false,"script":null)
 ]
}
"""
    content = content.replace('[input]\n', '[input]\n\n' + rotate_right)

with open('project.godot', 'w') as f:
    f.write(content)

