extends SceneTree

# measure_spoke_gaps.gd — Recorre radialmente cada HubSpoke tirando rayos hacia
# abajo y reporta los tramos SIN piso: son los huecos por los que el jugador se
# cae al pasar del anillo del hub a la pasarela en espiral.
#
# Se mide contra la colision real de Dome_Intro (los cuerpos horneados), no contra
# las AABB de las mallas: una AABB de un anillo octogonal da el circunradio y no
# el borde real en el angulo del spoke.
#
# Run: godot3-bin --no-window -s tools/measure_spoke_gaps.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const STEP := 0.1
const R_MIN := 5.0
const R_MAX := 28.0
const PROP_LAYER := 64

# nombre, angulo (grados, atan2(z,x)), altura de la cubierta
const SPOKES := [
	["Spoke_1", 4.7, Vector3(-10.081, 0.0, -14.6443)],
	["Spoke_2", 9.2, Vector3(5.74222, 0.0, -16.3571)],
	["Spoke_3", 13.7, Vector3(15.9228, 0.0, -4.81623)],
	["Spoke_4", 18.2, Vector3(12.4483, 0.0, 9.34721)],
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dome: Node = (load(SCENE_PATH) as PackedScene).instance()
	get_root().add_child(dome)
	for _i in range(120):
		yield(self, "idle_frame")

	var space: PhysicsDirectSpaceState = (dome as Spatial).get_world().direct_space_state
	for entry in SPOKES:
		var spoke_name: String = entry[0]
		var deck_y: float = entry[1]
		var reference: Vector3 = entry[2]
		var angle: float = atan2(reference.z, reference.x)
		var direction := Vector3(cos(angle), 0.0, sin(angle))

		# La cubierta del spoke tiene 2 m de ancho: un hueco en la union no aparece
		# en el eje central sino contra una de las barandas, donde el borde del
		# anillo (octogonal) o el de la pasarela (en angulo) se separa del spoke.
		var tangent := Vector3(-direction.z, 0.0, direction.x)
		for offset in [-1.2, -1.0, -0.8, -0.4, 0.0, 0.4, 0.8, 1.0, 1.2]:
			var lateral: Vector3 = tangent * offset
			var gaps := []
			var gap_start := -1.0
			var r: float = R_MIN
			while r <= R_MAX:
				var base: Vector3 = direction * r + lateral
				var origin: Vector3 = base + Vector3(0.0, deck_y + 0.35, 0.0)
				var target: Vector3 = base + Vector3(0.0, deck_y - 0.35, 0.0)
				var hit: Dictionary = space.intersect_ray(origin, target, [], PROP_LAYER)
				if hit.empty():
					if gap_start < 0.0:
						gap_start = r
				else:
					if gap_start >= 0.0:
						gaps.append([gap_start, r - STEP])
						gap_start = -1.0
				r += STEP
			if gap_start >= 0.0:
				gaps.append([gap_start, R_MAX])

			var text := ""
			for gap in gaps:
				# Solo interesa el tramo donde el spoke deberia ser continuo:
				# del borde del anillo del hub al borde de la pasarela.
				if gap[1] < 12.0 or gap[0] > 24.0:
					continue
				text += " [r %.1f..%.1f ancho %.2f]" % [gap[0], gap[1], gap[1] - gap[0] + STEP]
			print("SPOKE:%-8s y=%5.2f lateral=%+.1f huecos:%s" % [
				spoke_name, deck_y, offset, text if text != "" else " ninguno"])
	quit(0)
