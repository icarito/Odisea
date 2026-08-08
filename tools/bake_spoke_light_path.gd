extends SceneTree

# bake_spoke_light_path.gd — Rehornea los marcadores de SpokeLightPath en Dome_Intro.
#
# Por que hace falta: LightPathV2 deriva sus waypoints de los hijos de
# `waypoint_source`, leyendo platform_height/platform_depth de cada uno. Cuando
# HubSpokes se horneo a un solo CombinedMesh (commit 1102426e "Level decoration")
# esos hijos desaparecieron, el path se reconstruyo leyendo CombinedMesh/StaticBody
# como si fueran waypoints y quedo en 2 marcadores sueltos en el origen del grupo.
# La geometria original de los spokes ya no esta en la escena, pero si en el commit
# 256f472f, que es de donde salen las constantes de abajo.
#
# Que hace: recrea waypoints de mentira con esas transformadas y alturas, apunta el
# SpokeLightPath real a ellos y lo reconstruye DENTRO de Dome_Intro, para que el
# snap a superficie (snap_mask 65) golpee la colision horneada de verdad. Guarda el
# MultiMesh resultante como recurso suelto.
#
# Run: godot3-bin --no-window -s tools/bake_spoke_light_path.gd
# Output: core_v2/levels/interiors/DomeIntro_SpokeLightPath_markers.tres

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const OUT_PATH := "res://core_v2/levels/interiors/DomeIntro_SpokeLightPath_markers.tres"

# Transformadas y medidas de los 4 spokes, tal como estaban en 256f472f.
const SPOKES := [
	{"xf": Transform(Vector3(0.8237, 0, -0.567026), Vector3(0, 1, 0), Vector3(-0.567026, 0, -0.8237), Vector3(-10.081, 0, -14.6443)), "h": 4.7, "d": 8.97227},
	{"xf": Transform(Vector3(0.943548, 0, 0.331236), Vector3(0, 1, 0), Vector3(0.331236, 0, -0.943548), Vector3(5.74222, 0, -16.3571)), "h": 9.2, "d": 8.63199},
	{"xf": Transform(Vector3(0.289519, 0, 0.957172), Vector3(0, 1, 0), Vector3(0.957172, 0, -0.289519), Vector3(15.9228, 0, -4.81623)), "h": 13.7, "d": 7.14267},
	{"xf": Transform(Vector3(-0.600452, 0, 0.79966), Vector3(0, 1, 0), Vector3(0.79966, 0, 0.600452), Vector3(12.4483, 0, 9.34721)), "h": 18.2, "d": 4.29028},
]

const WAYPOINT_SRC := """
extends Spatial
export(float) var platform_height := 0.0
export(float) var platform_depth := 0.0
"""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root: Node = load(SCENE_PATH).instance()
	get_root().add_child(root)
	for _i in range(30):
		yield(self, "idle_frame")

	var path: Spatial = root.get_node_or_null("SpokeLightPath")
	if path == null:
		push_error("[bake_spokes] no encuentro SpokeLightPath")
		quit(1)
		return
	print("[bake_spokes] antes: %d marcadores" % _marker_count(path))

	# Waypoints de mentira con la geometria original.
	var wp_script := GDScript.new()
	wp_script.source_code = WAYPOINT_SRC
	wp_script.reload()

	var holder := Spatial.new()
	holder.name = "SpokeWaypointsTemp"
	root.add_child(holder)
	for i in range(SPOKES.size()):
		var s: Dictionary = SPOKES[i]
		var w := Spatial.new()
		w.name = "Spoke_%d" % (i + 1)
		w.set_script(wp_script)
		holder.add_child(w)
		w.transform = s["xf"]
		w.set("platform_height", s["h"])
		w.set("platform_depth", s["d"])

	path.waypoint_source = path.get_path_to(holder)
	path.rebuild_baked_items = true
	path.build()
	yield(self, "idle_frame")

	# El snap corre normalmente en _process tras encontrar al jugador; aca se
	# dispara directo para que el resultado sea determinista.
	path._snap_markers_to_surface()
	yield(self, "idle_frame")

	var markers: MultiMeshInstance = path.get_node_or_null("Markers") as MultiMeshInstance
	if markers == null or markers.multimesh == null:
		push_error("[bake_spokes] la reconstruccion no produjo Markers")
		quit(1)
		return
	var mm: MultiMesh = markers.multimesh
	print("[bake_spokes] despues: %d marcadores" % mm.instance_count)
	if mm.instance_count < 4:
		push_error("[bake_spokes] muy pocos marcadores; algo no cuadra")
		quit(1)
		return

	var alturas := []
	for i in range(min(mm.instance_count, 6)):
		alturas.append("%.2f" % markers.global_transform.xform(mm.get_instance_transform(i).origin).y)
	print("[bake_spokes] primeras alturas: %s" % str(alturas))

	if ResourceSaver.save(OUT_PATH, mm) != OK:
		push_error("[bake_spokes] no pude guardar %s" % OUT_PATH)
		quit(1)
		return
	print("[bake_spokes] guardado %s" % OUT_PATH)
	quit(0)


func _marker_count(path: Node) -> int:
	var m: MultiMeshInstance = path.get_node_or_null("Markers") as MultiMeshInstance
	if m == null or m.multimesh == null:
		return -1
	return m.multimesh.instance_count
