extends SceneTree

# bench_dome_intro_startup.gd — Perfila el arranque de Dome_Intro separando
# load(PackedScene) / instance() / _ready(), y desglosa el coste de _ready por
# subarbol de primer nivel.
#
# El coste dominante de esta escena NO es cargar el .tscn (~200 ms) sino el
# trabajo procedural que corre en _ready (~670 ms): RadialScatter con
# rebuild_baked_items=true tira los items ya horneados y los regenera, y cada
# SteelGratePlatform se reconstruye entero una vez por cada propiedad que le
# escribe el scatter (_queue_rebuild llama a _rebuild sincrono).
#
# Run: godot3-bin --no-window -s tools/bench_dome_intro_startup.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"

func _init() -> void:
	var t0 := OS.get_ticks_usec()
	var ps: PackedScene = load(SCENE_PATH)
	var t1 := OS.get_ticks_usec()
	var root: Node = ps.instance()
	var t2 := OS.get_ticks_usec()
	var nodes_on_disk := _count(root)

	# Desprender los hijos de primer nivel para cronometrar su _ready uno por uno.
	var kids := []
	for c in root.get_children():
		kids.append(c)
	for c in kids:
		root.remove_child(c)
	get_root().add_child(root)

	var rows := []
	var ready_total := 0.0
	for c in kids:
		var before := _count(c)
		var a := OS.get_ticks_usec()
		root.add_child(c)
		var b := OS.get_ticks_usec()
		var ms := (b - a) / 1000.0
		ready_total += ms
		rows.append([c.name, ms, _count(c) - before, _ct(c, "MeshInstance"), _ct(c, "CollisionShape")])

	print("[t] load(PackedScene) = %.1f ms" % ((t1 - t0) / 1000.0))
	print("[t] instance()        = %.1f ms   (%d nodos en disco)" % [(t2 - t1) / 1000.0, nodes_on_disk])
	print("[t] _ready()          = %.1f ms   (%d nodos tras construir)" % [ready_total, _count(root)])
	print("[t] TOTAL             = %.1f ms" % ((t1 - t0) / 1000.0 + (t2 - t1) / 1000.0 + ready_total))
	print("[t]")
	print("[t] %-22s %8s %8s %8s %8s" % ["SUBARBOL", "ms", "nodos+", "meshes", "colshp"])
	rows.sort_custom(self, "_by_ms")
	for r in rows:
		if r[1] >= 0.5 or r[2] > 0:
			print("[t] %-22s %8.1f %8d %8d %8d" % r)
	quit()

func _by_ms(a, b) -> bool:
	return a[1] > b[1]

func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c

func _ct(n: Node, t: String) -> int:
	var c := 1 if n.is_class(t) else 0
	for k in n.get_children():
		c += _ct(k, t)
	return c
