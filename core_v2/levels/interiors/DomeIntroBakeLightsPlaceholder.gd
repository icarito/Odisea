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
# create_instance()/replace_by_instance(). En juego real eso nunca pasa.
#
# IMPORTANTE: NO auto-materializar en _ready(). Engine.editor_hint es true tanto
# con el editor abierto en modo edicion como al correr la escena con F5 desde el
# editor (el proceso hijo hereda el flag) — no distingue "quiero editar el rig" de
# "estoy jugando". Auto-materializar ahi convertia cada F5 en un resave de facto:
# las 107 Light reales quedaban en el arbol en memoria y, si el editor volcaba ese
# estado a disco, disparaba el bug de pack() con Viewport anidado que borra nodos
# con owner roto (HangingDisplay/Viewport/TerminalUI). Ver memoria
# project_fd270_pack_owner_bug.
#
# Nunca materializar desde Dome_Intro: abrir DomeIntro_BakeLights.tscn directamente
# para retocar el rig. Eso mantiene el owner del Viewport ajeno al pack del nivel.
