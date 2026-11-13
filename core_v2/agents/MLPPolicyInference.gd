extends Reference
class_name MLPPolicyInference

# Inferencia MLP ligera y determinista para políticas PPO (Stable-Baselines3)
# exportadas por agents/export_ppo_mlp.py. Sin dependencias externas: solo aritmética
# en GDScript (floats de 64 bits). Pensada para usar un modelo entrenado en el juego
# sin meter torch/onnxruntime en el export de Godot.
#
# Formato de pesos (JSON):
#   { "obs_dim": 12, "num_actions": 6, "activation": "tanh",
#     "layers": [ {"in","out","W":[[..]],"b":[..]}, ... ],
#     "head": {"in","out","W","b"} }

var _obs_dim := 0
var _num_actions := 0
var _activation := "tanh"
var _layers: Array = []
var _head := {}

func load_from_json(path: String) -> bool:
	var f := File.new()
	if not f.file_exists(path):
		return false
	f.open(path, File.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed := JSON.parse(txt)
	if parsed.error != OK:
		return false
	var data = parsed.result
	_obs_dim = int(data.get("obs_dim", 0))
	_num_actions = int(data.get("num_actions", 0))
	_activation = str(data.get("activation", "tanh"))
	_layers = data.get("layers", [])
	_head = data.get("head", {})
	return _obs_dim > 0 and _num_actions > 0 and _layers.size() > 0 and not _head.empty()

func get_obs_dim() -> int:
	return _obs_dim

func get_num_actions() -> int:
	return _num_actions

func predict_logits(obs: Array) -> Array:
	var h := _to_vector(obs, _obs_dim)
	for layer in _layers:
		h = _affine_tanh(h, layer["W"], layer["b"])
	return _affine(h, _head["W"], _head["b"])

func _affine(h: Array, W: Array, b: Array) -> Array:
	var n_out: int = W.size()
	var n_in: int = h.size()
	var out := []
	out.resize(n_out)
	for i in range(n_out):
		var row: Array = W[i]
		var acc := 0.0
		for j in range(n_in):
			acc += float(row[j]) * h[j]
		out[i] = acc + float(b[i])
	return out

func _affine_tanh(h: Array, W: Array, b: Array) -> Array:
	var out := _affine(h, W, b)
	for i in range(out.size()):
		out[i] = tanh(out[i])
	return out

func _to_vector(a: Array, size: int) -> Array:
	var v := []
	v.resize(size)
	for i in range(size):
		v[i] = float(a[i])
	return v
