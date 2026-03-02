extends Node

class_name AnnaNPCController

const DEFAULT_ONNX_MODEL_PATH := "res://core_v2/trained_models/anna_best_rl4.onnx"

export(String) var onnx_model_path := ""
export(NodePath) var actor_path := NodePath("..")
export(NodePath) var anna_interface_path := NodePath("AnnaInterface")
export(bool) var auto_start := true

var _actor: Node = null
var _anna: Node = null
var _onnx_model = null
var _onnx_initialized := false
var _active := false
var _warned_missing_model := false

func _ready() -> void:
	_resolve_references()
	set_active(auto_start)

func set_active(active: bool) -> void:
	_active = bool(active)
	if is_instance_valid(_anna) and _anna.has_method("set_rl_active"):
		_anna.call("set_rl_active", _active)
	set_physics_process(_active)

func _physics_process(_delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_anna):
		_resolve_references()
		if not is_instance_valid(_anna):
			return

	if _onnx_model == null:
		_init_onnx_model()
		if _onnx_model == null:
			return

	if not _anna.has_method("get_rl_observation"):
		return
	var obs_dict = _anna.call("get_rl_observation")
	if typeof(obs_dict) != TYPE_DICTIONARY:
		return
	var raw_obs = obs_dict.get("obs", [])
	if typeof(raw_obs) != TYPE_ARRAY or raw_obs.empty():
		return

	var result = _onnx_model.run_inference(raw_obs, 0)
	if typeof(result) != TYPE_DICTIONARY or not result.has("output"):
		return

	var output_tensor = result["output"]
	if typeof(output_tensor) != TYPE_ARRAY or output_tensor.empty():
		return

	var best_action := 0
	var best_val := -1000000000.0
	for i in range(output_tensor.size()):
		var val = float(output_tensor[i])
		if val > best_val:
			best_val = val
			best_action = i

	if _anna.has_method("apply_rl_action"):
		_anna.call("apply_rl_action", best_action)

func _resolve_references() -> void:
	_actor = get_node_or_null(actor_path)
	if not is_instance_valid(_actor):
		_actor = get_parent()

	_anna = get_node_or_null(anna_interface_path)
	if not is_instance_valid(_anna) and is_instance_valid(_actor):
		_anna = _actor.get_node_or_null("AnnaInterface")

	if not is_instance_valid(_anna):
		return

	if _anna.has_method("set_controlled_player") and is_instance_valid(_actor):
		_anna.call("set_controlled_player", _actor)
	if _object_has_property(_anna, "allow_human_heuristic_override"):
		_anna.allow_human_heuristic_override = false
	if _object_has_property(_anna, "allow_command_injection"):
		_anna.allow_command_injection = false

func _init_onnx_model() -> void:
	if _onnx_initialized:
		return
	_onnx_initialized = true

	var model_path := _resolve_model_path()
	if model_path.strip_edges() == "":
		return
	if not File.new().file_exists(model_path):
		if not _warned_missing_model:
			_warned_missing_model = true
			printerr("[AnnaNPCController] ONNX model not found: ", model_path)
		return

	var onnx_wrapper = load("res://addons/godot_rl_agents/onnx/wrapper/ONNX_wrapper.gd")
	if onnx_wrapper == null:
		printerr("[AnnaNPCController] Failed to load ONNX_wrapper.gd")
		return
	_onnx_model = onnx_wrapper.new(model_path, 1)

func _resolve_model_path() -> String:
	if onnx_model_path.strip_edges() != "":
		return onnx_model_path
	var env_path = OS.get_environment("ANNA_ONNX_MODEL").strip_edges()
	if env_path != "":
		return env_path
	return DEFAULT_ONNX_MODEL_PATH

func _object_has_property(obj: Object, prop_name: String) -> bool:
	if not is_instance_valid(obj):
		return false
	for p in obj.get_property_list():
		if String(p.get("name", "")) == prop_name:
			return true
	return false
