# ASCII rendering constants
POSE_INDICES = {
    'nose': 0,
    'left_shoulder': 12,
    'right_shoulder': 11,
    'left_elbow': 14,
    'right_elbow': 13,
    'left_wrist': 16,
    'right_wrist': 15,
    'left_hip': 24,
    'right_hip': 23,
    'left_knee': 26,
    'right_knee': 25,
    'left_ankle': 28,
    'right_ankle': 27,
}

EDGES = [
    ('left_shoulder', 'right_shoulder'),
    ('left_shoulder', 'left_elbow'),
    ('left_elbow', 'left_wrist'),
    ('right_shoulder', 'right_elbow'),
    ('right_elbow', 'right_wrist'),
    ('left_shoulder', 'left_hip'),
    ('right_shoulder', 'right_hip'),
    ('left_hip', 'right_hip'),
    ('left_hip', 'left_knee'),
    ('left_knee', 'left_ankle'),
    ('right_hip', 'right_knee'),
    ('right_knee', 'right_ankle'),
]

def render_ascii_skeleton(landmarks, frame_shape, grid_w=40, grid_h=20, pose_indices=None, edges=None):
    """
    Renderiza esqueleto ASCII con conjunto configurable de landmarks y edges
    """
    if not landmarks:
        return "(sin landmarks)"
    
    if pose_indices is None:
        pose_indices = POSE_INDICES
    if edges is None:
        edges = EDGES

    grid = [[' ' for _ in range(grid_w)] for _ in range(grid_h)]

    def to_grid(lm):
        x = min(max(lm['x'], 0.0), 1.0)
        y = min(max(lm['y'], 0.0), 1.0)
        gx = int(x * (grid_w - 1))
        gy = int(y * (grid_h - 1))
        return gx, gy

    joint_positions = {}
    for name, idx in pose_indices.items():
        if idx < len(landmarks):
            lm = landmarks[idx]
            if lm.get('visibility', 0) > 0.2:
                joint_positions[name] = to_grid(lm)

    def draw_line(p1, p2, char='.'):
        (x1, y1), (x2, y2) = p1, p2
        dx = abs(x2 - x1)
        dy = abs(y2 - y1)
        x, y = x1, y1
        sx = 1 if x1 < x2 else -1
        sy = 1 if y1 < y2 else -1
        err = dx - dy
        while True:
            if 0 <= y < grid_h and 0 <= x < grid_w and grid[y][x] == ' ':
                grid[y][x] = char
            if x == x2 and y == y2:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x += sx
            if e2 < dx:
                err += dx
                y += sy

    for a, b in edges:
        if a in joint_positions and b in joint_positions:
            draw_line(joint_positions[a], joint_positions[b])

    for name, (jx, jy) in joint_positions.items():
        if 0 <= jy < grid_h and 0 <= jx < grid_w:
            ch = 'L' if name.startswith('left_') else 'R' if name.startswith('right_') else 'O'
            grid[jy][jx] = ch

    lines = [''.join(row) for row in grid]
    lines.append("Leyenda: L=lado izquierdo, R=lado derecho, O=otro, .=conexión")
    
    return '\n'.join(lines)