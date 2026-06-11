import re
with open('project.godot') as f: text = f.read()
text = re.sub(r'enabled=PoolStringArray\([^)]+\)', 'enabled=PoolStringArray()', text)
with open('project.godot', 'w') as f: f.write(text)
print("Editor plugins disabled.")
