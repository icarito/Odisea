#!/usr/bin/env python3
"""Reorganize PushableBoxes into simple tower stacks"""

import re
import shutil
import os

INPUT_FILE = "core_v2/levels/BaseTerrace.tscn"
BACKUP_FILE = "core_v2/levels/BaseTerrace.tscn.backup3"

# Boxes are 2x2x2m - center at y=1 means sitting on ground at y=0
BOX_HEIGHT = 2.0
BOX_GAP = 0.1  # Small gap to prevent collision on load

def main():
    if not os.path.exists(BACKUP_FILE):
        shutil.copy(INPUT_FILE, BACKUP_FILE)
    
    with open(INPUT_FILE, 'r') as f:
        lines = f.readlines()
    
    boxes = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if 'PushableBoxV' in line and 'parent="Scatter3D"' in line:
            name_match = re.search(r'name="(PushableBoxV\d+)"', line)
            if name_match:
                name = name_match.group(1)
                transform_idx = -1
                for j in range(i+1, min(i+4, len(lines))):
                    if 'transform = Transform' in lines[j]:
                        transform_idx = j
                        break
                
                if transform_idx >= 0:
                    transform_line = lines[transform_idx].strip()
                    match = re.search(r'Transform\(([^)]+)\)', transform_line)
                    if match:
                        values = [float(x.strip()) for x in match.group(1).split(',')]
                        boxes.append({
                            'name': name,
                            'transform_idx': transform_idx,
                            'transform_line': transform_line,
                            'orig_x': values[9],
                            'orig_y': values[10],
                            'orig_z': values[11]
                        })
        i += 1
    
    print(f"Found {len(boxes)} boxes")
    
    # Simple tower: all at same x,z position, stacked vertically
    # Place at x=15, z=-30 (out of the way, in an open area)
    TOWER_X = 15.0
    TOWER_Z = -30.0
    
    for idx, box in enumerate(boxes):
        height_idx = idx  # Each box on top of previous
        new_y = BOX_HEIGHT/2 + (height_idx * (BOX_HEIGHT + BOX_GAP))
        
        new_transform = f"transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, {TOWER_X}, {new_y}, {TOWER_Z} )"
        box['new_transform'] = new_transform
        print(f"{box['name']}: y={new_y:.1f}")
        
        lines[box['transform_idx']] = new_transform + '\n'
    
    with open(INPUT_FILE, 'w') as f:
        f.writelines(lines)
    
    print(f"\n✓ Stacked {len(boxes)} boxes in tower at ({TOWER_X}, {TOWER_Z})")

if __name__ == "__main__":
    main()
