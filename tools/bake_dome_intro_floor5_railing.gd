extends SceneTree

# bake_dome_intro_floor5_railing.gd — Regenerates ScaffoldHubTower/Floor_5's baked
# CombinedMesh/CombinedCollision in Dome_Intro.
#
# Pass 1 closed the elevator-side rail opening (106.048-123.196 deg) and kept the
# original deck/walkway opening (86.022-94.820 deg, from the tower's authored
# inner_opening_angles_deg[5]=90.4). Pass 2 widened that to (86.02,106.05),
# assuming the walkway docked along a wide arc.
#
# Both were wrong. Measured live via global_transform (SpiralWalkways/Item_4's
# _deck_point at all four corners), Item_4 is oriented with its WIDTH axis
# radial and its DEPTH axis tangential: "front" and "back" are radial edges at
# fixed angles (78 deg and 105 deg), "left"/"right" are the tangential-direction
# rails along the ramp. So Item_4 meets the ring at a single angle (~105 deg,
# its "back" edge), not across a wide arc — a corner-to-corner point contact,
# matching what was described as "la union en esquina". Item_4's own
# rail_back_opening (width 2.5, gravity 0.0) is a radial doorway starting right
# at its inner corner (r=13.26) and running out to ~r=15.76, at that same fixed
# angle. The ring only needs a narrow angular gap there — the same width
# (2.5m) projected onto the ring's radius — not a 20 degree arc. The wide arc
# left a real hole (nothing on the other side of most of it) plus a dangling
# rail stub where the old opening boundary didn't line up with anything on
# Item_4's side.
#
# Floor_5 is a ScaffoldHubRing instance whose children are normally pre-baked (see
# ScaffoldHubRing.gd _ready()), so editing its outer_openings_deg text in the .tscn
# has no runtime effect on its own — the mesh has to be rebuilt and re-saved.
# Instead of re-deriving ScaffoldHubTower's build() parameter plumbing, this loads
# the actual Dome_Intro scene, finds the already-configured Floor_5 node, edits its
# opening arrays, forces a synchronous rebuild, and saves the result as loose
# .mesh/.shape resources (same pattern as DomeTerrace_baked.mesh).
#
# Run: godot3-bin --no-window -s tools/bake_dome_intro_floor5_railing.gd
# Output: core_v2/levels/interiors/Dome_Intro_Floor5_baked.mesh / .shape

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const FLOOR_PATH := "ScaffoldHubTower/Floor_5"
const OUT_MESH := "res://core_v2/levels/interiors/Dome_Intro_Floor5_baked.mesh"
const OUT_SHAPE := "res://core_v2/levels/interiors/Dome_Intro_Floor5_baked.shape"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return

	var root: Node = scene.instance()
	get_root().add_child(root)

	var floor5: Spatial = root.get_node_or_null(FLOOR_PATH)
	if floor5 == null:
		push_error("Could not find %s in %s" % [FLOOR_PATH, SCENE_PATH])
		quit(1)
		return

	print("[bake_floor5] before: outer_openings_deg=%s outer_opening_docks=%s" % [
		floor5.outer_openings_deg, floor5.outer_opening_docks])

	# Ground truth from inspecting Item_4's actual named rail segments (not just
	# its corners): it has TWO of its own gaps — one in its LEFT rail (86.7-94.4
	# deg, right against the ring) and one in its BACK rail (~105 deg, with a
	# solid "BackBRail" remnant hanging past the gate into open space). Per
	# live confirmation, the real walkway-to-ring crossing is the LEFT gap; the
	# back gate was never the intended path. Item_4's back rail opening got
	# closed separately (see bake_scaffold_walkways.gd's source scene edit).
	# This just restores the ring's ORIGINAL deck opening (86.0223, 94.8197,
	# authored via the tower's inner_opening_angles_deg[5]=90.421) which lines
	# up with Item_4's left-rail gap almost exactly — it was correct from the
	# start; the actual bugs were the elevator opening (fixed earlier) and
	# Item_4's stray back gate (fixed in the mesh bake).
	# Reverted: narrowing back to the original deck opening was wrong too (per
	# live feedback it closed the elevator side again and re-broke the
	# ramp/hub union that was half-working at the wide 90-135 setting). Back to
	# the full-face opening as the known baseline while this gets sorted out
	# interactively.
	floor5.outer_openings_deg = [ Vector2(90.0, 135.0) ]
	floor5.outer_opening_docks = [ 0.4 ]
	floor5.rebuild_baked_items = true
	floor5.build()

	# build() itself is synchronous (SurfaceTool commit happens inline), but give
	# the tree a frame in case anything downstream expects to observe it live.
	yield(self, "idle_frame")

	var visual: MeshInstance = floor5.get_node_or_null("CombinedMesh")
	var body: StaticBody = floor5.get_node_or_null("StaticBody")
	var collision: CollisionShape = body.get_node_or_null("CombinedCollision") if body else null
	if visual == null or visual.mesh == null or collision == null or collision.shape == null:
		push_error("[bake_floor5] rebuild did not produce CombinedMesh/CombinedCollision")
		quit(1)
		return

	var dir := Directory.new()
	if ResourceSaver.save(OUT_MESH, visual.mesh) != OK:
		push_error("[bake_floor5] failed to save %s" % OUT_MESH)
		quit(1)
		return
	if ResourceSaver.save(OUT_SHAPE, collision.shape) != OK:
		push_error("[bake_floor5] failed to save %s" % OUT_SHAPE)
		quit(1)
		return

	print("[bake_floor5] saved %s and %s" % [OUT_MESH, OUT_SHAPE])
	print("[bake_floor5] after: outer_openings_deg=%s outer_opening_docks=%s" % [
		floor5.outer_openings_deg, floor5.outer_opening_docks])
	quit(0)
