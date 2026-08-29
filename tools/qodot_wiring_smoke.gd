extends SceneTree

# qodot_wiring_smoke.gd — Prueba de humo del cableado targetname -> target.
#
# Construye maps/tests/qodot_wiring_smoke.map de verdad y comprueba que:
#   1. el boton con target queda conectado al ventilador que nombra
#   2. el ventilador suelto (sin target) no queda conectado a nadie
#   3. apuntar a un prop instanciado desde un .tscn no revienta (su raiz no es un
#      QodotEntity y por lo tanto no tiene `properties`)
#
# El caso 2 es el que importa: con `target` declarado en la base class Target,
# apply_properties inyecta target="" en TODAS las entidades, y sin la guarda de
# get_nodes_by_targetname cada entidad del mapa se cablearia contra las demas.
#
# Run: godot3-bin --no-window -s tools/qodot_wiring_smoke.gd

const MAP := "res://maps/tests/qodot_wiring_smoke.map"
const TIMEOUT_FRAMES := 1800

var _failures := []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var QodotMap = load("res://addons/qodot/src/nodes/qodot_map.gd")
	var node = QodotMap.new()
	node.name = "WiringSmoke"
	get_root().add_child(node)
	node.set("map_file", MAP)
	node.connect("build_complete", self, "_on_built", [node])
	node.verify_and_build()

	for _i in range(TIMEOUT_FRAMES):
		yield(self, "idle_frame")
	printerr("TIMEOUT: el mapa no termino de construir")
	quit(1)

func _on_built(map_node) -> void:
	var button: Node = null
	var fans := []
	for child in map_node.get_children():
		if "prop_pedestal_button" in child.name:
			button = child
		elif "prop_industrial_fan" in child.name:
			fans.append(child)

	if button == null:
		_failures.append("no se instancio prop_pedestal_button")
	if fans.size() != 2:
		_failures.append("se esperaban 2 prop_industrial_fan, hay %d" % fans.size())

	if button != null and fans.size() == 2:
		var wired := button.get_signal_connection_list("activated")
		if wired.size() == 0:
			_failures.append("el boton con target no quedo conectado a nada")
		var targets := {}
		for conn in wired:
			targets[conn["target"]] = true

		# fans[0] es el que el boton nombra; fans[1] es el suelto.
		var linked := 0
		var loose := 0
		for fan in fans:
			var hit := targets.has(fan)
			if hit:
				linked += 1
			for conn in fan.get_signal_connection_list("activated"):
				if conn["target"] != fan:
					loose += 1

		if linked != 1:
			_failures.append("el boton quedo conectado a %d ventiladores, se esperaba 1" % linked)
		if loose != 0:
			_failures.append("un ventilador sin target quedo cableado (%d conexiones de mas)" % loose)

	for f in _failures:
		printerr("  FALLA: ", f)
	if _failures.empty():
		print("qodot_wiring_smoke: OK")
		quit(0)
	else:
		quit(1)
