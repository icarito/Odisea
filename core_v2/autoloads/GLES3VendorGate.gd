extends Node

# GLES3VendorGate.gd — Contrato §11.10: renderer GLES3 en Mali (handhelds FRT).
#
# En Mali-G31 (GLES3 via FRT/EGL) las pasadas full-screen del Environment —
# fog, glow, DOF y tonemap ACES — fallan en silencio: el mundo se ve blanco/
# cian lavado con el HUD dibujando encima (log limpio, sin errores de shader).
# El mismo build con esas pasadas apagadas renderiza texturizado (verificado
# en device con ANNA, 2026-09-14).
#
# Este gate detecta el adapter por vendor ("Mali") y apaga las pasadas
# riesgosas de CUALQUIER WorldEnvironment que entre al árbol, dejando el
# ambiente en el nivel conservador que se sabe correcto (el equivalente a
# Environment_InteriorLab: bg color, sin post-process). Scope por vendor,
# no por escena: los levels siguen compartiendo sus .tres en desktop/iOS.

const VENDOR_TAG := "mali"

# Test seam: fuerza el gate sin depender del adapter del runner headless.
export var force_vendor_gate := false

var _mali_active := false

func _ready() -> void:
	_detect_mali()
	get_tree().connect("node_added", self, "_on_node_added")

func _detect_mali() -> void:
	var adapter := String(VisualServer.get_video_adapter_name()).to_lower()
	var vendor := String(VisualServer.get_video_adapter_vendor()).to_lower()
	_mali_active = adapter.find(VENDOR_TAG) != -1 or vendor.find(VENDOR_TAG) != -1
	if _mali_active:
		print("[GLES3VendorGate] Mali detectado (%s): ambiente conservador (sin fog/glow/dof/ACES)" % adapter)

func _on_node_added(node: Node) -> void:
	if not (_mali_active or force_vendor_gate):
		return
	if node is WorldEnvironment:
		strip_environment(node.environment)

func strip_environment(env: Environment) -> void:
	if env == null:
		return
	env.fog_enabled = false
	env.glow_enabled = false
	env.dof_blur_far_enabled = false
	env.dof_blur_near_enabled = false
	env.adjustment_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
