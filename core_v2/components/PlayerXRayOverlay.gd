extends Spatial
# Attach to the player's Visual node.
# Adds a depth-test-disabled ghost pass to every MeshInstance child so the
# player is always visible through props, styled as a semi-transparent glow.

const _XRAY_SHADER: Shader = preload("res://core_v2/visual/player_xray.shader")

func _ready() -> void:
	_apply_xray(self)

func _apply_xray(node: Node) -> void:
	if node is MeshInstance:
		var mi := node as MeshInstance
		if mi.mesh != null:
			var mat := ShaderMaterial.new()
			mat.shader = _XRAY_SHADER
			mat.render_priority = 100
			# Chain as next_pass on surface 0, or override if no base material
			var base = mi.get_surface_material(0)
			if base == null:
				base = mi.material_override
			if base != null:
				base.next_pass = mat
			else:
				# Fallback: override (won't show base texture, but shows ghost)
				mi.material_override = mat
	for child in node.get_children():
		_apply_xray(child)
