tool
extends Spatial

# Luces exclusivas del pase BakedLightmap de Dome_Intro. El bake se conserva en
# Dome_Intro.lmbake; el rig nunca debe iluminar en runtime.
export(bool) var bake_rig_enabled := false setget set_bake_rig_enabled

func _ready() -> void:
	_apply_bake_state()

func set_bake_rig_enabled(value: bool) -> void:
	bake_rig_enabled = value
	if is_inside_tree():
		_apply_bake_state()

func _apply_bake_state() -> void:
	for child in get_children():
		if not (child is Light):
			continue
		var light := child as Light
		# El flag de bake controla la inclusión, no visible. Mantener invisible el
		# rig evita que estas luces se conviertan en coste runtime durante el bake.
		light.light_bake_mode = 2 if bake_rig_enabled else 0 # Light.BAKE_ALL / DISABLED
		light.visible = false
