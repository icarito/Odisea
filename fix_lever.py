import re

with open("core_v2/props/LeverV2.tscn", "r") as f:
    content = f.read()

# Change HandleMesh transform
content = re.sub(
    r'\[node name="HandleMesh" type="MeshInstance" parent="Handle"\]\ntransform = Transform\( 1, 0, 0, 0, -4.37114e-08, 1, 0, -1, -4.37114e-08, 0, 0, 0.25 \)',
    r'[node name="HandleMesh" type="MeshInstance" parent="Handle"]\ntransform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.25, 0 )',
    content
)

# Top CSGSphere is at 0, 0.25, 0, which is fine since it's local to HandleMesh.
# Wait, if HandleMesh is at 0, 0.25, 0, Top will be at 0, 0.5, 0 globally.
# Actually Top's transform is `Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.25, 0 )`
# Which relative to HandleMesh is +0.25 in Y. That perfectly puts it at the tip of the handle!

with open("core_v2/props/LeverV2.tscn", "w") as f:
    f.write(content)
