extends Node

# ProtocolManager.gd
# Autoload for managing HUD Protocol Overlays

var _overlay: Control = null
const ProtocolOverlayScene = preload("res://core_v2/ui/overlays/ProtocolOverlay.tscn")

func _ready() -> void:
	# Wait for the scene to be fully loaded before adding the overlay to the root
	call_deferred("_setup_overlay")

func _setup_overlay() -> void:
	_overlay = ProtocolOverlayScene.instance()
	# Add to a CanvasLayer to ensure it's on top of everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 120 # High layer to be above other UI
	canvas_layer.add_child(_overlay)
	get_tree().root.add_child(canvas_layer)

func show(config: Dictionary) -> void:
	if _overlay:
		_overlay.show_protocol(config)

func close() -> void:
	if _overlay:
		_overlay.hide_protocol()

func get_overlay() -> Control:
	return _overlay
