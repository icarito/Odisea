extends SceneTree

# generate_ringhub_bake_lights.gd — O28: genera el rig de luces estaticas del
# bake del BakedLightmap de RingHub_Level.
#
# Es el analogo de generate_dome_intro_bake_lights.gd para RingHub, pero NO lee
# los fixtures de una escena de domo: las posiciones salen del MultiMesh
# RingHub_WallLightMarkers.tres, que es exactamente el que usa LightPathV2 /
# RingHubLightState para colocar las 16 luminarias runtime. Asi el bake y el
# runtime comparten el mismo origen de posiciones (una OmniLight por lampara de
# pared, en la posicion horneada del marker) y no hay numeros copiados a mano.
#
# Ademas del anillo de 16 lamparas de pared agrega:
#   DomeCore    un relleno central frio que abre el interior del domo, como el
#               DomeLamp de Dome_Intro (no hay una lampara fisica: es un punto de
#               luz de bake, invisible en runtime).
#   PodGlow_N   5 luces tenues sobre el anillo de criopods (r=12, una por piso).
#               Las capsulas no son emisivas (emission_enabled=false), asi que
#               sin estas el anillo interior queda sin definicion en el bake.
#
# El rig NUNCA ilumina en runtime: las luces nacen visible=false,
# light_bake_mode=DISABLED y el script DomeIntroBakeLightRig.gd (reusado, es
# generico) las apaga del todo si el nodo llega a instanciarse fuera del editor.
# RingHub_Level.tscn lo referencia como instance_placeholder, igual que Dome_Intro.
#
# Uso:
#   tools/godot --path . --no-window -s tools/generate_ringhub_bake_lights.gd
#   tools/godot --path . --no-window -s tools/generate_ringhub_bake_lights.gd -- \
#       --wall-energy=1.2 --wall-range=18 --inward-offset=0.75 \
#       --core-energy=0.8 --core-range=45 --pod-energy=0.4 --pod-range=6
#
# Output: core_v2/levels/RingHub_BakeLights.tscn

const OUT_SCENE := "res://core_v2/levels/RingHub_BakeLights.tscn"
const MARKERS_PATH := "res://core_v2/levels/interiors/RingHub_WallLightMarkers.tres"
const RIG_SCRIPT := "res://core_v2/levels/interiors/DomeIntroBakeLightRig.gd"

const WALL_COLOR := Color(0.72, 0.84, 1.0, 1.0)
const CORE_COLOR := Color(0.85, 0.90, 1.0, 1.0)
const POD_COLOR := Color(0.70, 0.86, 1.0, 1.0)
# Mismo radio y alturas que el anillo de criopods del hub (r=12, pisos a 4.5*N).
const POD_RADIUS := 12.0
const POD_HEIGHT_STEP := 4.5
const POD_FLOORS := 5


func _init() -> void:
	var wall_energy := float(_arg("wall-energy", "1.2"))
	var wall_range := float(_arg("wall-range", "18.0"))
	var inward := float(_arg("inward-offset", "0.75"))
	var core_energy := float(_arg("core-energy", "0.8"))
	var core_range := float(_arg("core-range", "45.0"))
	var pod_energy := float(_arg("pod-energy", "0.4"))
	var pod_range := float(_arg("pod-range", "6.0"))

	var markers: MultiMesh = load(MARKERS_PATH)
	if markers == null:
		push_error("[ringhub_bake_lights] falta %s" % MARKERS_PATH)
		quit(1)
		return

	var rig := Spatial.new()
	rig.name = "RingHubBakeLights"
	rig.script = load(RIG_SCRIPT)
	rig.set("bake_rig_enabled", false)

	var added := 0
	for index in range(markers.instance_count):
		var world: Vector3 = markers.get_instance_transform(index).origin
		var inward_dir := Vector3(-world.x, 0.0, -world.z)
		if inward_dir.length_squared() > 0.0001:
			world += inward_dir.normalized() * inward
		_add_light(rig, "WallFixture_%03d" % added, WALL_COLOR, wall_energy, wall_range, world)
		added += 1
	print("[ringhub_bake_lights] wall fixtures: %d (energy=%.2f range=%.1f inward=%.2f)" % [
		added, wall_energy, wall_range, inward])

	_add_light(rig, "DomeCore", CORE_COLOR, core_energy, core_range, Vector3(0.0, 15.0, 0.0))
	print("[ringhub_bake_lights] DomeCore: energy=%.2f range=%.1f" % [core_energy, core_range])

	# Una PodGlow por piso, delante del anillo (r=12), buscando no repetir el
	# angulo: gira 72 grados por piso para repartir el aporte por el domo.
	for floor_index in range(POD_FLOORS):
		var angle: float = TAU * float(floor_index) / float(POD_FLOORS)
		var pos := Vector3(cos(angle) * POD_RADIUS, 1.0 + POD_HEIGHT_STEP * float(floor_index), sin(angle) * POD_RADIUS)
		_add_light(rig, "PodGlow_%d" % floor_index, POD_COLOR, pod_energy, pod_range, pos)
	print("[ringhub_bake_lights] pod glows: %d (energy=%.2f range=%.1f)" % [POD_FLOORS, pod_energy, pod_range])

	var packed := PackedScene.new()
	if packed.pack(rig) != OK:
		push_error("[ringhub_bake_lights] pack failed")
		quit(1)
		return
	if ResourceSaver.save(OUT_SCENE, packed) != OK:
		push_error("[ringhub_bake_lights] save failed")
		quit(1)
		return
	print("[ringhub_bake_lights] saved %s (%d lights)" % [OUT_SCENE, added + 1 + POD_FLOORS])
	quit(0)


func _add_light(rig: Spatial, light_name: String, color: Color, energy: float, light_range: float, pos: Vector3) -> void:
	var light := OmniLight.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	light.light_bake_mode = 0
	light.visible = false
	light.transform = Transform(Basis(), pos)
	rig.add_child(light)
	light.owner = rig


func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_args():
		var arg := String(raw)
		if arg.begins_with("--%s=" % name):
			return arg.substr(len(name) + 3, len(arg))
	return fallback
