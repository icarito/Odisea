extends GdUnitTestSuite

# Verifica la inferencia MLP determinista en GDScript contra golden generados con
# torch (double) por agents/export_ppo_mlp.py. Cubre el modelo exportado
# anna_ppo_noorbit_v1 (obs 12 → 64 → 64 → 6, tanh).

const InferenceScript := preload("res://core_v2/agents/MLPPolicyInference.gd")
const WEIGHTS_PATH := "res://core_v2/agents/anna_ppo_noorbit_v1_weights.json"
const GOLDEN_PATH := "res://core_v2/tests/fixtures/anna_ppo_noorbit_v1_golden.json"

func _load_golden() -> Dictionary:
	var f := File.new()
	f.open(GOLDEN_PATH, File.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse(txt)
	assert_int(parsed.error).is_equal(OK)
	return parsed.result

func test_loads_model_metadata() -> void:
	var infer = InferenceScript.new()
	assert_bool(infer.load_from_json(WEIGHTS_PATH)).is_true()
	assert_int(infer.get_obs_dim()).is_equal(12)
	assert_int(infer.get_num_actions()).is_equal(6)

func test_predicts_golden_logits() -> void:
	var infer = InferenceScript.new()
	assert_bool(infer.load_from_json(WEIGHTS_PATH)).is_true()
	var golden = _load_golden()
	var inputs = golden["inputs"]
	var expected = golden["logits"]
	assert_int(inputs.size()).is_equal(expected.size())
	for i in range(inputs.size()):
		var logits: Array = infer.predict_logits(inputs[i])
		assert_int(logits.size()).is_equal(int(golden["num_actions"]))
		for a in range(logits.size()):
			assert_float(logits[a]).is_equal_approx(expected[i][a], 0.00001)

func test_inference_is_deterministic() -> void:
	var infer = InferenceScript.new()
	infer.load_from_json(WEIGHTS_PATH)
	var obs := [0.0, -0.5, 0.25, 1.0, -1.0, 0.0, 0.75, -0.25, 0.5, -0.75, 0.125, 0.625]
	var first = infer.predict_logits(obs)
	var second = infer.predict_logits(obs)
	assert_int(first.size()).is_equal(second.size())
	for i in range(first.size()):
		assert_float(first[i]).is_equal_approx(second[i], 0.0)
