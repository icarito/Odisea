extends Spatial

# Dome_Base.gd - ajustes de coste que dependen del nivel que instancia esta base.

# La geometria que entra al lightmap ya lleva su sombra horneada: volver a meterla en el
# shadow map en vivo duplica lo que se dibuja y no cambia un pixel... con una excepcion,
# la linterna del casco. Es un SpotLight en tiempo real (light_bake_mode = INDIRECT), asi
# que esa geometria deja de proyectar cuando el jugador la alumbra.
#
# Por eso es una decision por nivel y no una regla global:
#   Dome_Intro    -> false, la linterna no es parte de la escena
#   Dome_Prologue -> true, ahi la linterna si importa
#
# Medido en Dome_Intro con el replay 1788458596 (peor pose, frame 1050):
# 741 -> 582 draw calls y 2.11 -> 1.54 M de vertices por frame.
export(bool) var baked_geometry_casts_shadows := true

func _ready() -> void:
	# En el editor hay que dejar cast_shadow como esta: el horneado del lightmap lo mira,
	# y un rehorneado con esto aplicado perderia las sombras.
	if Engine.editor_hint:
		return
	if baked_geometry_casts_shadows:
		return
	# Las criopods horneadas cuelgan del nivel, no de Dome_Base: barrer desde la raiz.
	var scope: Node = get_parent()
	if scope == null:
		scope = self
	_drop_baked_shadow_casters(scope)

func _drop_baked_shadow_casters(node: Node) -> void:
	if node is MeshInstance and node.use_in_baked_light:
		node.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_drop_baked_shadow_casters(child)
