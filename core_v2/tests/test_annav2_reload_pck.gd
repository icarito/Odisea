extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

const UPDATES_DIR = "user://updates/"
const PACKAGES_DIR = "user://updates/packages/"

func before():
	var dir = Directory.new()
	if not dir.dir_exists(UPDATES_DIR):
		dir.make_dir_recursive(UPDATES_DIR)
	if not dir.dir_exists(PACKAGES_DIR):
		dir.make_dir_recursive(PACKAGES_DIR)

func after():
	# Cleanup test artifacts if needed
	pass

# Mock response class since we can't use argument_captor easily
class MockThread:
	extends Node
	var last_response = null
	func send_command_response(resp):
		last_response = resp

func test_reload_pck_rejects_url():
	var args = {"url": "http://evil.com/malicious.pck"}
	var id = "test_url_rejection"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_bool(response != null).is_true()
	assert_str(response.get("error")).contains("no longer accepts URLs")
	assert_bool(response.get("ok")).is_false()

	ANNAV2._net_thread = original_thread
	mock_thread.free()

func test_reload_pck_requires_artifact_id():
	var args = {}
	var id = "test_missing_artifact"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_str(response.get("error")).is_equal("missing artifact_id")

	ANNAV2._net_thread = original_thread
	mock_thread.free()

func test_reload_pck_file_not_found():
	var args = {"artifact_id": "non_existent"}
	var id = "test_file_not_found"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_str(response.get("error")).contains("pck not found")

	ANNAV2._net_thread = original_thread
	mock_thread.free()

func test_reload_pck_hash_mismatch():
	var art_id = "test_mismatch"
	var pck_path = PACKAGES_DIR + art_id + ".pck"
	var sidecar_path = PACKAGES_DIR + art_id + ".json"

	var f = File.new()
	f.open(pck_path, File.WRITE)
	f.store_string("pck_content")
	f.close()

	f.open(sidecar_path, File.WRITE)
	f.store_string(JSON.print({"sha256": "wrong_hash"}))
	f.close()

	var args = {"artifact_id": art_id}
	var id = "test_hash_mismatch"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_str(response.get("error")).is_equal("SHA-256 mismatch")

	ANNAV2._net_thread = original_thread
	mock_thread.free()

	# Cleanup
	var dir = Directory.new()
	dir.remove(pck_path)
	dir.remove(sidecar_path)

func test_reload_pck_success_via_sidecar():
	var art_id = "test_success"
	var pck_path = PACKAGES_DIR + art_id + ".pck"
	var sidecar_path = PACKAGES_DIR + art_id + ".json"

	var content = "valid_pck_content"
	var f = File.new()
	f.open(pck_path, File.WRITE)
	f.store_string(content)
	f.close()

	var actual_hash = f.get_sha256(pck_path)

	f.open(sidecar_path, File.WRITE)
	f.store_string(JSON.print({"sha256": actual_hash}))
	f.close()

	var args = {"artifact_id": art_id}
	var id = "test_success_sidecar"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_str(response.get("error")).is_equal("failed to load resource pack")

	ANNAV2._net_thread = original_thread
	mock_thread.free()

	# Cleanup
	var dir = Directory.new()
	dir.remove(pck_path)
	dir.remove(sidecar_path)

func test_reload_pck_success_via_state_json():
	var art_id = "test_state_json"
	var pck_path = PACKAGES_DIR + art_id + ".pck"
	var state_path = UPDATES_DIR + "state.json"

	var content = "valid_pck_content_state"
	var f = File.new()
	f.open(pck_path, File.WRITE)
	f.store_string(content)
	f.close()

	var actual_hash = f.get_sha256(pck_path)

	var state_data = {
		"active_package_ids": [art_id],
		"artifacts": [
			{"artifact_id": art_id, "sha256": actual_hash}
		]
	}

	f.open(state_path, File.WRITE)
	f.store_string(JSON.print(state_data))
	f.close()

	var args = {"artifact_id": art_id}
	var id = "test_success_state"

	var original_thread = ANNAV2._net_thread
	var mock_thread = MockThread.new()
	ANNAV2._net_thread = mock_thread

	ANNAV2._cmd_reload_pck(id, args)

	var response = mock_thread.last_response
	assert_str(response.get("error")).is_equal("failed to load resource pack")

	ANNAV2._net_thread = original_thread
	mock_thread.free()

	# Cleanup
	var dir = Directory.new()
	dir.remove(pck_path)
	dir.remove(state_path)
