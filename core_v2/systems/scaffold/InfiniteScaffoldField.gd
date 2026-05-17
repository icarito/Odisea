extends Spatial
class_name InfiniteScaffoldField

# ─── Configuration ─────────────────────────────────────────────────
export(NodePath) var player_path
export var cell_size: float = 5.0
export var detail_radius: float = 20.0
export var pipe_radius: float = 0.3
export var scaffold_seed: int = 42

# Variability: probability [0-1] that a segment on each axis exists.
# Operates on SEGMENTS (edges between two junctions), not on cells.
# A segment either fully connects two junctions or is completely absent.
export var segment_x_probability: float = 0.85
export var segment_y_probability: float = 0.90
export var segment_z_probability: float = 0.85

# ─── Runtime state ─────────────────────────────────────────────────
var _player: Spatial
var _active_cells: Dictionary = {}   # Vector3 -> Spatial (cell root)
var _last_center_cell := Vector3(-99999, -99999, -99999)
var _exclusion_areas: Array = []
var _exclusion_cache_frame: int = -1

# ─── Shared resources (created once in _ready) ─────────────────────
var _pipe_material: SpatialMaterial
var _cap_material: SpatialMaterial
var _cyl_mesh: CylinderMesh
var _joint_mesh: SphereMesh
var _cap_mesh: CylinderMesh         # flat disc end-cap (flange)
var _cyl_shape: CylinderShape

func _ready():
	if player_path and has_node(player_path):
		_player = get_node(player_path)

	_build_shared_resources()

	if _player:
		# Defer so all ScaffoldExclusionArea nodes have time to _ready()
		# and register in the "scaffold_exclusion" group first.
		call_deferred("_update_scaffold", true)

# ═══════════════════════════════════════════════════════════════════
#  SHARED RESOURCE CREATION
# ═══════════════════════════════════════════════════════════════════

func _build_shared_resources():
	# --- Materials ---
	_pipe_material = SpatialMaterial.new()
	_pipe_material.albedo_color = Color(0.38, 0.38, 0.42)
	_pipe_material.metallic = 0.85
	_pipe_material.roughness = 0.55

	_cap_material = SpatialMaterial.new()
	_cap_material.albedo_color = Color(0.50, 0.45, 0.30)
	_cap_material.metallic = 0.9
	_cap_material.roughness = 0.4

	# --- Full-length cylinder ---
	_cyl_mesh = CylinderMesh.new()
	_cyl_mesh.top_radius = pipe_radius
	_cyl_mesh.bottom_radius = pipe_radius
	_cyl_mesh.height = cell_size
	_cyl_mesh.radial_segments = 12
	_cyl_mesh.material = _pipe_material

	# --- Joint sphere ---
	_joint_mesh = SphereMesh.new()
	_joint_mesh.radius = pipe_radius * 1.4
	_joint_mesh.height = pipe_radius * 2.8
	_joint_mesh.radial_segments = 12
	_joint_mesh.rings = 6
	_joint_mesh.material = _pipe_material

	# --- End-cap flange (flat disc) ---
	_cap_mesh = CylinderMesh.new()
	_cap_mesh.top_radius = pipe_radius * 2.0
	_cap_mesh.bottom_radius = pipe_radius * 2.0
	_cap_mesh.height = pipe_radius * 0.4
	_cap_mesh.radial_segments = 12
	_cap_mesh.material = _cap_material

	# --- Collision shape ---
	_cyl_shape = CylinderShape.new()
	_cyl_shape.radius = pipe_radius
	_cyl_shape.height = cell_size

# ═══════════════════════════════════════════════════════════════════
#  DETERMINISTIC HASH — operates on SEGMENTS, not cells
# ═══════════════════════════════════════════════════════════════════

func _segment_hash(cell_a: Vector3, axis: int) -> float:
	# Deterministic hash for the segment starting at cell_a going in +axis.
	# cell_a is always the cell with the smaller coordinate on that axis,
	# so the segment between (0,0,0)-(1,0,0) and (1,0,0)-(0,0,0) give the
	# same result.
	var h = hash(Vector3(
		cell_a.x + axis * 7919,
		cell_a.y + axis * 6271,
		cell_a.z + axis * 8087
	))
	h = h ^ (scaffold_seed * 2654435761)
	return abs(h % 10000) / 10000.0

func _segment_exists(cell_a: Vector3, cell_b: Vector3, axis: int) -> bool:
	# Canonical order: always hash from the smaller coordinate
	var origin_cell: Vector3
	match axis:
		0: origin_cell = cell_a if cell_a.x <= cell_b.x else cell_b  # X
		1: origin_cell = cell_a if cell_a.y <= cell_b.y else cell_b  # Y
		_: origin_cell = cell_a if cell_a.z <= cell_b.z else cell_b  # Z

	var prob: float
	match axis:
		0: prob = segment_x_probability
		1: prob = segment_y_probability
		_: prob = segment_z_probability

	return _segment_hash(origin_cell, axis) < prob

# ═══════════════════════════════════════════════════════════════════
#  EXCLUSION QUERIES
# ═══════════════════════════════════════════════════════════════════

func _refresh_exclusions():
	var frame = Engine.get_frames_drawn()
	if frame == _exclusion_cache_frame:
		return
	_exclusion_cache_frame = frame
	_exclusion_areas = get_tree().get_nodes_in_group("scaffold_exclusion")

func _is_cell_excluded(world_pos: Vector3) -> bool:
	for area in _exclusion_areas:
		if area.is_point_excluded(world_pos):
			return true
	return false

func _is_coord_excluded(coord: Vector3) -> bool:
	return _is_cell_excluded(coord * cell_size)

# ═══════════════════════════════════════════════════════════════════
#  CELL CONSTRUCTION — segment-based approach
# ═══════════════════════════════════════════════════════════════════

# Axis directions and their offsets
const AXIS_OFFSETS = [
	Vector3(1, 0, 0),   # axis 0 = X
	Vector3(0, 1, 0),   # axis 1 = Y
	Vector3(0, 0, 1),   # axis 2 = Z
]

# Rotation bases for each axis (orient CylinderMesh along that axis)
const AXIS_ROTATIONS = [
	null,  # X — set in _ready via Basis()
	null,  # Y — identity
	null,  # Z — set in _ready via Basis()
]

func _get_axis_rotation(axis: int) -> Basis:
	match axis:
		0: return Basis(Vector3(0, 0, 1), PI / 2.0)  # X
		1: return Basis.IDENTITY                       # Y
		_: return Basis(Vector3(1, 0, 0), PI / 2.0)   # Z

func _get_axis_dir(axis: int) -> Vector3:
	return AXIS_OFFSETS[axis]

func _create_cell(coord: Vector3) -> Spatial:
	var root = Spatial.new()

	var body = StaticBody.new()
	body.collision_layer = 64  # Layer 7: Props — camera occlusion / dither
	body.collision_mask = 0
	root.add_child(body)

	var pipe_count = 0

	for axis in range(3):
		var offset = AXIS_OFFSETS[axis]
		var neighbor_plus = coord + offset
		var neighbor_minus = coord - offset

		var plus_excluded = _is_coord_excluded(neighbor_plus)
		var minus_excluded = _is_coord_excluded(neighbor_minus)

		# Check segment existence (variability).
		# A cell has a pipe on axis X if EITHER the segment to its +X neighbor
		# or the segment from its -X neighbor exists.  Each segment is a full
		# pipe connecting two junctions.  We draw the half that belongs to
		# THIS cell for each existing segment.
		var seg_plus_exists = (not plus_excluded) and _segment_exists(coord, neighbor_plus, axis)
		var seg_minus_exists = (not minus_excluded) and _segment_exists(coord, neighbor_minus, axis)

		# Also suppress segments that go into excluded neighbors
		# (already handled by the check above)

		if not seg_plus_exists and not seg_minus_exists:
			# No pipe on this axis at all — clean omission, no dangling halves
			continue

		var rot = _get_axis_rotation(axis)
		var axis_dir = _get_axis_dir(axis)

		if seg_plus_exists and seg_minus_exists:
			# Full pipe — both halves connect to neighbors
			_add_full_pipe(body, axis, rot)
			pipe_count += 1
		elif seg_plus_exists:
			# Only the +side segment exists; draw half-pipe toward + and cap at center
			_add_half_pipe_mesh(body, axis, rot, axis_dir, true)
			_add_endcap(body, axis, rot, axis_dir, false)
			pipe_count += 1
		else:
			# Only the -side segment exists; draw half-pipe toward - and cap at center
			_add_half_pipe_mesh(body, axis, rot, axis_dir, false)
			_add_endcap(body, axis, rot, axis_dir, true)
			pipe_count += 1

	# --- Joint sphere (only if 2+ pipes meet) ---
	if pipe_count >= 2:
		var joint = MeshInstance.new()
		joint.name = "joint"
		joint.mesh = _joint_mesh
		body.add_child(joint)

	# If no pipes at all, still return the empty root (it'll just be invisible)
	return root

func _add_full_pipe(body: StaticBody, axis: int, rot: Basis):
	var mesh_inst = MeshInstance.new()
	mesh_inst.name = "pipe_%d" % axis
	mesh_inst.mesh = _cyl_mesh
	mesh_inst.transform.basis = rot
	body.add_child(mesh_inst)

	var col = CollisionShape.new()
	col.name = "col_%d" % axis
	col.shape = _cyl_shape
	col.transform.basis = rot
	body.add_child(col)

func _add_half_pipe_mesh(body: StaticBody, axis: int, rot: Basis, axis_dir: Vector3, toward_plus: bool):
	# Half-length pipe offset toward the + or - direction
	var sign_val = 1.0 if toward_plus else -1.0
	var offset = axis_dir * (cell_size * 0.25) * sign_val

	# Create a half-length cylinder mesh
	var half_mesh = CylinderMesh.new()
	half_mesh.top_radius = pipe_radius
	half_mesh.bottom_radius = pipe_radius
	half_mesh.height = cell_size * 0.5
	half_mesh.radial_segments = 12
	half_mesh.material = _pipe_material

	var mesh_inst = MeshInstance.new()
	mesh_inst.name = "pipe_%d_%s" % [axis, "p" if toward_plus else "m"]
	mesh_inst.mesh = half_mesh
	mesh_inst.transform.basis = rot
	mesh_inst.transform.origin = offset
	body.add_child(mesh_inst)

	var half_shape = CylinderShape.new()
	half_shape.radius = pipe_radius
	half_shape.height = cell_size * 0.5

	var col = CollisionShape.new()
	col.name = "col_%d_%s" % [axis, "p" if toward_plus else "m"]
	col.shape = half_shape
	col.transform.basis = rot
	col.transform.origin = offset
	body.add_child(col)

func _add_endcap(body: StaticBody, axis: int, rot: Basis, axis_dir: Vector3, on_plus_side: bool):
	# Flange disc at the termination point (where the pipe ends)
	var sign_val = 0.0  # Center of cell = termination point for half-pipe
	var offset = Vector3.ZERO

	var cap = MeshInstance.new()
	cap.name = "cap_%d_%s" % [axis, "p" if on_plus_side else "m"]
	cap.mesh = _cap_mesh
	cap.transform.basis = rot
	cap.transform.origin = offset
	body.add_child(cap)

# ═══════════════════════════════════════════════════════════════════
#  MAIN UPDATE LOOP
# ═══════════════════════════════════════════════════════════════════

func _process(_delta):
	if not _player:
		if player_path and has_node(player_path):
			_player = get_node(player_path)
		else:
			return
	_update_scaffold(false)

func _update_scaffold(force: bool):
	var player_pos = _player.global_transform.origin

	var center_cell = Vector3(
		int(round(player_pos.x / cell_size)),
		int(round(player_pos.y / cell_size)),
		int(round(player_pos.z / cell_size))
	)

	if not force and center_cell == _last_center_cell:
		return

	_last_center_cell = center_cell
	_refresh_exclusions()

	var cells_radius = int(ceil(detail_radius / cell_size))
	var needed_cells = {}

	for x in range(int(center_cell.x) - cells_radius, int(center_cell.x) + cells_radius + 1):
		for y in range(int(center_cell.y) - cells_radius, int(center_cell.y) + cells_radius + 1):
			for z in range(int(center_cell.z) - cells_radius, int(center_cell.z) + cells_radius + 1):
				var cell_coord = Vector3(x, y, z)
				var cell_center = cell_coord * cell_size
				if cell_center.distance_to(player_pos) <= detail_radius:
					if not _is_cell_excluded(cell_center):
						needed_cells[cell_coord] = cell_center

	# Remove cells that are no longer needed
	var to_remove = []
	for coord in _active_cells.keys():
		if not needed_cells.has(coord):
			var cell = _active_cells[coord]
			remove_child(cell)
			cell.queue_free()
			to_remove.append(coord)

	for coord in to_remove:
		_active_cells.erase(coord)

	# Add new cells (segment-aware construction)
	for coord in needed_cells.keys():
		if not _active_cells.has(coord):
			var cell = _create_cell(coord)
			cell.translation = needed_cells[coord]
			add_child(cell)
			_active_cells[coord] = cell

## Public API: force a full rebuild around a canonical position.
## Useful for tests and deterministic replay.
func rebuild_around(canonical_pos: Vector3):
	_last_center_cell = Vector3(-99999, -99999, -99999)
	if _player:
		_update_scaffold(true)
