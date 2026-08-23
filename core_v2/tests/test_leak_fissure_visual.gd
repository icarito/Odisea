extends GdUnitTestSuite

# test_leak_fissure_visual.gd - Unit tests for LeakFissureVisual component (FD-268)

const LEAK_SCENE := "res://core_v2/systems/cryo/CoolantLeak.gd"
const PATCH_SCENE := "res://core_v2/systems/cryo/LeakPatchPoint.gd"
const PIPE_RUN_SCENE := "res://core_v2/props/pipe/PipeCoolantRun.gd"
const VISUAL_SCENE := "res://core_v2/systems/cryo/LeakFissureVisual.tscn"

var _runner: GdUnitSceneRunner
var _root: Spatial
var _leak: Node
var _patch_point: Node
var _pipe_run: Node
var _visual: Spatial


func before_test() -> void:
	_root = Spatial.new()

	var leak_script = load(LEAK_SCENE)
	_leak = leak_script.new()
	_leak.name = "CoolantLeak"
	_root.add_child(_leak)

	var patch_script = load(PATCH_SCENE)
	_patch_point = patch_script.new()
	_patch_point.name = "LeakPatchPoint"
	_root.add_child(_patch_point)

	var pipe_run_script = load(PIPE_RUN_SCENE)
	_pipe_run = pipe_run_script.new()
	_pipe_run.name = "PipeCoolantRun"
	_root.add_child(_pipe_run)

	var visual_tscn = load(VISUAL_SCENE)
	_visual = visual_tscn.instance()
	_visual.name = "LeakFissureVisual"
	_root.add_child(_visual)

	_visual.set("leak_path", _visual.get_path_to(_leak))
	_visual.set("patch_point_path", _visual.get_path_to(_patch_point))
	_visual.set("pipe_run_path", _visual.get_path_to(_pipe_run))

	_runner = scene_runner(_root)


func after_test() -> void:
	if is_instance_valid(_root):
		_root.free()


func test_no_leak_fissure_inactive() -> void:
	# Healthy state: fissure intensity 0 and particles inactive
	assert_int(_leak.get("state") if "state" in _leak else _leak.call("get_state")).is_equal(0) # State.HEALTHY = 0
	assert_float(_leak.call("get_leak_intensity")).is_equal(0.0)

	yield(_runner.simulate_frames(5), "completed")

	var gloo: MeshInstance = _visual.get_node("GlooMesh")

	assert_bool(_visual.is_spray_emitting()).is_false()
	assert_bool(_visual.is_mist_emitting()).is_false()
	assert_bool(gloo.visible).is_false()

	assert_float(_visual.get_fissure_intensity()).is_equal(0.0)
	var mat = _pipe_run.get("_material")
	if _exposes_shader_param(mat, "fissure_intensity"):
		assert_float(mat.get_shader_param("fissure_intensity")).is_equal(0.0)


func test_fissure_mist_is_a_cheap_cpu_plume() -> void:
	# FD-270 perf: la fisura dejo de instanciar FrostEmitter/GasParticleManager (volumen de
	# gas simulado, un pool por fisura x24 en Dome_Intro) y usa un CPUParticles. Lo que la
	# prueba cuida es que siga siendo un chorro visible de lejos: sin LOD de distancia que
	# lo apague y con un AABB de visibilidad mas grande que el propio quad.
	var mist: CPUParticles = _visual.get_node("MistParticles") as CPUParticles
	var spray: CPUParticles = _visual.get_node("SprayParticles") as CPUParticles

	assert_object(_visual.get_node_or_null("MistFrost")).is_null()
	assert_int(mist.amount).is_greater(16)
	assert_float(mist.lifetime).is_greater(1.5)
	# Rango, no valor exacto: el alfa del vapor se ajusta a ojo y clavarlo aca solo hace
	# que el test persiga cada retoque. Lo que importa es que se vea y no tape la escena.
	assert_float(mist.color.a).is_between(0.2, 0.6)
	assert_float(spray.color.a).is_equal_approx(0.38, 0.001)
	# El quad se agranda con la curva de escala: sin margen extra el frustum corta la
	# pluma antes de que expire.
	assert_float(mist.extra_cull_margin).is_greater(1.0)


func test_active_leak_fissure_visuals() -> void:
	# Se fuerza el estado directo con _set_state() y se llama _resolve_references()/
	# _update_visuals() a mano, en vez de esperar a que _physics_process() los dispare via
	# simulate_frames(). _physics_process corre en el paso de fisica de Godot, que en 3.x no
	# esta garantizado en lockstep con el idle_frame que usa simulate_frames() (yield del
	# SceneTree) -- reproducido con el binario headless real (godot_v3.6.2-stable_linux_
	# headless.64, el mismo que usa CI): sin dar tiempo de reloj real entre el ultimo
	# idle_frame y el assert, el tick de fisica que actualiza is_mist_emitting() a veces
	# todavia no habia corrido. Insertar un print() (que consume I/O real) "arreglaba" el
	# sintoma, lo que confirma que era una carrera de tiempo real, no una espera de
	# duracion de gameplay ni un problema de cuantos frames simular. Llamando a los metodos
	# del componente directamente, la prueba no depende del scheduler de fisica en absoluto.
	_leak.call("_set_state", CoolantLeak.State.WARNING)
	_visual.call("_resolve_references")
	_visual.call("_update_visuals")

	assert_int(_leak.call("get_state")).is_equal(1) # State.WARNING = 1

	# WARNING state: mist active, spray inactive
	assert_bool(_visual.is_spray_emitting()).is_false()
	assert_bool(_visual.is_mist_emitting()).is_true()

	assert_float(_visual.get_fissure_intensity()).is_greater(0.0)
	var mat = _pipe_run.get("_material")
	if _exposes_shader_param(mat, "fissure_intensity"):
		assert_float(mat.get_shader_param("fissure_intensity")).is_greater(0.0)

	# Transition to LEAKING state. ramp_up_duration=0.0 hace que _physics_process asiente
	# _leak_intensity en 1.0 de inmediato (ver CoolantLeak.gd): forzar _leak_intensity a mano
	# no sirve, el propio _physics_process la recalcula desde _state_timer/ramp_up_duration
	# en cada tick y la pisa. Como aca no dejamos correr _physics_process (ver comentario de
	# arriba), hay que llamarlo una vez a mano para que la rampa a 1.0 se aplique.
	_leak.set("ramp_up_duration", 0.0)
	_leak.call("_set_state", CoolantLeak.State.LEAKING)
	_leak.call("_physics_process", 0.0)
	_visual.call("_resolve_references")
	_visual.call("_update_visuals")

	assert_int(_leak.call("get_state")).is_equal(2) # State.LEAKING = 2
	assert_bool(_visual.is_spray_emitting()).is_true()
	assert_bool(_visual.is_mist_emitting()).is_true()

	assert_float(_visual.get_fissure_intensity()).is_greater(0.2)
	if _exposes_shader_param(mat, "fissure_intensity"):
		assert_float(mat.get_shader_param("fissure_intensity")).is_greater(0.2)


func test_patched_fissure_visuals() -> void:
	# Active leak patched with gloo -> fissure masked, spray cut off, gloo mesh visible
	_leak.set("warning_duration", 0.0)
	_leak.set("ramp_up_duration", 0.0)
	_leak.call("trigger_leak")

	yield(_runner.simulate_frames(5), "completed")
	assert_int(_leak.call("get_state")).is_equal(2) # State.LEAKING = 2

	_patch_point.call("patch_with_gloo")
	assert_bool(_patch_point.call("is_patched")).is_true()

	yield(_runner.simulate_frames(5), "completed")

	var gloo: MeshInstance = _visual.get_node("GlooMesh")

	assert_bool(_visual.is_spray_emitting()).is_false()
	assert_bool(_visual.is_mist_emitting()).is_false()
	assert_bool(gloo.visible).is_true()

	assert_float(_visual.get_fissure_intensity()).is_equal(0.0)
	var mat = _pipe_run.get("_material")
	if _exposes_shader_param(mat, "fissure_intensity"):
		assert_float(mat.get_shader_param("fissure_intensity")).is_equal(0.0)


func test_fissure_visual_snapshot_determinism() -> void:
	_visual.set("enabled", false)
	var snap = _visual.call("get_snapshot")

	assert_bool(snap.get("enabled", true)).is_false()

	_visual.set("enabled", true)
	_visual.call("restore_snapshot", snap)

	assert_bool(_visual.get("enabled")).is_false()


# Cerrar la valvula despresuriza el tramo (FD-266): el chorro tiene que apagarse aunque
# el cano siga roto. Sin este caso, un match sobre enteros del enum se desalinea ante un
# estado nuevo y el visual queda congelado en la fuga sin que ningun test lo note.
#
# Se maneja por API publica (depressurize()) y no escribiendo _state a mano: _set_state()
# es quien reinicia _state_timer y _start_intensity, y sin eso _physics_process recalcula
# la intensidad desde el arranque viejo. Escrito a mano el test pasaba o fallaba segun el
# timing de frames — verde local, rojo en CI.
func test_depressurized_state_winds_down_spray() -> void:
	_leak.set("warning_duration", 0.0)
	_leak.set("ramp_up_duration", 0.0)
	_leak.set("dissipate_duration", 0.05)
	_leak.call("trigger_leak")
	yield(_runner.simulate_frames(5), "completed")

	assert_int(_leak.call("get_state")).is_equal(CoolantLeak.State.LEAKING)
	assert_bool(_visual.is_spray_emitting()).is_true()

	_leak.call("depressurize")
	yield(_runner.simulate_frames(15), "completed") # holgado sobre dissipate_duration

	assert_int(_leak.call("get_state")).is_equal(CoolantLeak.State.DEPRESSURIZED)
	assert_float(_visual.get_fissure_intensity()).is_equal(0.0)
	assert_bool(_visual.is_spray_emitting()).is_false()


# El binario headless de CI usa el rasterizer dummy: los ShaderMaterial no guardan
# parametros (ni siquiera los que declara el .tres, porque duplicate() deriva la lista de
# propiedades de los uniforms del shader, que ahi no existen) y get_shader_param() devuelve
# null. La decision del componente se asierta sobre el estado del nodo; el material se
# revisa solo donde el rasterizer si lo expone. Mismo criterio que test_ice_level.gd.
func _exposes_shader_param(material, param: String) -> bool:
	return material != null and material.get_shader_param(param) != null
