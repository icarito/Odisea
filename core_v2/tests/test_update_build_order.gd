extends GdUnitTestSuite

const UpdateManagerScript = preload("res://core_v2/update/UpdateManager.gd")

class TestManager extends UpdateManagerScript:
	var current_build := "814"
	func _ready() -> void:
		pass
	func _get_current_build_id() -> String:
		return current_build

func test_fresh_install_rejects_older_and_equal_builds() -> void:
	var manager = auto_free(TestManager.new())
	manager._local_state = {"accepted_sequences": []}
	add_child(manager)
	for build in ["813", "814"]:
		var payload := {"channel": "nightly", "platform": "linux", "build_id": build, "release_sequence": int(build)}
		assert_bool(manager._validate_manifest(payload, "nightly", "linux")).is_false()
		assert_int(manager._state).is_equal(manager.State.IDLE)

func test_newer_and_non_numeric_builds_use_existing_sequence_rules() -> void:
	var manager = auto_free(TestManager.new())
	manager._local_state = {"accepted_sequences": []}
	add_child(manager)
	var payload := {"channel": "nightly", "platform": "linux", "build_id": "815", "release_sequence": 815}
	assert_bool(manager._validate_manifest(payload, "nightly", "linux")).is_true()
	manager.current_build = "dev"
	assert_bool(manager._validate_manifest(payload, "nightly", "linux")).is_true()
	manager.current_build = "814"
	payload["build_id"] = "custom"
	assert_bool(manager._validate_manifest(payload, "nightly", "linux")).is_true()
	manager._local_state = {"accepted_sequences": [815]}
	assert_bool(manager._validate_manifest(payload, "nightly", "linux")).is_false()
