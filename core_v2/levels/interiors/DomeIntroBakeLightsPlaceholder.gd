tool
extends InstancePlaceholder

# DomeIntro_BakeLights.tscn (107 luces, solo para el pase BakedLightmap de Dome_Intro)
# vive en Dome_Intro.tscn como instance_placeholder en vez de instance= directo. Sin
# esto Godot instancia las 107 Light SIEMPRE al cargar la escena, aunque el propio
# rig las apague en su _ready() (DomeIntroBakeLightRig.gd hacia queue_free() ahi,
# pero para entonces el motor ya pago instanciar/registrar cada Light en el arbol
# de culling espacial — el mismo tipo de costo de mantenimiento de broadphase que
# las formas de colision de Bullet, solo que este se paga aunque nunca se dibujen).
#
# Un InstancePlaceholder es casi gratis: no crea los hijos hasta que algo llama
# create_instance()/replace_by_instance(). En juego real eso nunca pasa. En el
# editor (para poder abrir el rig y re-hornear) SI hace falta, asi que este script
# se materializa solo cuando Engine.editor_hint es true.
func _ready() -> void:
	if Engine.editor_hint:
		replace_by_instance()
