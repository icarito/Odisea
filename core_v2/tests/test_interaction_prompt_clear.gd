extends GdUnitTestSuite

# El prompt/widget del interactuable en rango tiene que bajar cuando el jugador deja de
# tenerlo enfocado, incluso si el prop se libero (streaming en low-tier) mientras estaba
# en rango: antes el clear quedaba encerrado en el if de validez del target y un prop
# liberado dejaba el widget pegado en pantalla.

const PlayerScript = preload("res://core_v2/player/PlayerControllerV2.gd")


class FakeInteractable extends Node:
	var _auto_triggered := false
	var is_interactable := true
	func interact() -> void:
		pass
	func get_interaction_prompt() -> String:
		return "Accionar"


func _player() -> Node:
	return PlayerScript.new() # sin arbol: no corre _ready ni sus onready


func test_clear_interactable_forgets_a_freed_target() -> void:
	var player = _player()
	var prop := FakeInteractable.new()
	player._current_interactable = prop
	player._current_interaction_prompt = "Accionar"
	prop.free()
	player._clear_interactable()
	assert_bool(player.get("_current_interactable") == null).is_true()
	assert_str(String(player.get("_current_interaction_prompt"))).is_equal("")
	player.free()


func test_clear_interactable_resets_a_live_target_auto_trigger() -> void:
	var player = _player()
	var prop := FakeInteractable.new()
	prop._auto_triggered = true
	player._current_interactable = prop
	player._clear_interactable()
	assert_bool(player.get("_current_interactable") == null).is_true()
	assert_bool(prop._auto_triggered).is_false()
	prop.free()
	player.free()


func test_process_interaction_without_area_clears_the_prompt() -> void:
	# Camino salteado: sin area interactuable no se puede resolver target, pero el prompt de
	# un frame anterior no debe quedar pegado.
	var player = _player()
	var prop := FakeInteractable.new()
	player._current_interactable = prop
	player._current_interaction_prompt = "Accionar"
	player._interact_area = null
	player._process_interaction(null)
	assert_bool(player.get("_current_interactable") == null).is_true()
	assert_str(String(player.get("_current_interaction_prompt"))).is_equal("")
	prop.free()
	player.free()
