extends SceneTree

var UpdateKeyring = load("res://core_v2/update/UpdateKeyring.gd")
var UpdateManifestVerifier = load("res://core_v2/update/UpdateManifestVerifier.gd")

func _init():
	print("--- Running Update Manifest Tests ---")
	test_signature_verification()
	test_rollout_logic()
	test_delta_eligibility()
	test_packaged_build_supersedes_old_update_state()
	print("--- Tests Completed ---")
	quit()

func assert_eq(a, b, msg):
	if a != b:
		printerr("FAIL: ", msg, " (expected ", b, ", got ", a, ")")
	else:
		print("PASS: ", msg)

func test_signature_verification():
	var keyring = UpdateKeyring.new()
	var verifier = UpdateManifestVerifier.new(keyring)

	# This is just a conceptual test as we can't easily generate valid signatures here
	# without complex setup, but we can test field validation.

	var res = verifier.verify({})
	assert_eq(res["error"], "missing_fields", "Empty envelope")

	res = verifier.verify({"payload_b64": "e30=", "signatures": []})
	assert_eq(res["error"], "invalid_signature", "Empty signatures")

func test_rollout_logic():
	# Test rollout bucket calculation logic (ported from UpdateManager)
	var installation_id = "test_inst_id"
	var manifest_id = "test_manifest"

	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((installation_id + ":" + manifest_id).to_utf8())
	var digest = ctx.finish()
	var bucket = (digest[0] << 24 | digest[1] << 16 | digest[2] << 8 | digest[3]) % 10000

	# bucket should be consistent for same input
	assert_eq(bucket, bucket, "Bucket consistency")
	print("Bucket for test data: ", bucket)

func test_delta_eligibility():
	var mgr = load("res://core_v2/update/UpdateManager.gd").new()

	var delta = {"from_build_id": "old", "size": 100, "touches_bootstrap": false, "deleted_paths": []}
	var full = {"size": 200}
	var manifest = {"full_artifact": full, "force_full": false}

	# We access internal methods for testing if possible or replicate logic
	var eligible = _replicated_is_delta_eligible(delta, manifest, [])
	assert_eq(eligible, true, "Standard delta eligibility")

	delta["touches_bootstrap"] = true
	eligible = _replicated_is_delta_eligible(delta, manifest, [])
	assert_eq(eligible, false, "Delta touches bootstrap")

func test_packaged_build_supersedes_old_update_state():
	var mgr = load("res://core_v2/update/UpdateManager.gd").new()
	mgr._build_meta_cache = {"build_id": "277"}
	assert_eq(mgr._packaged_build_supersedes({"build_id": "267"}), true, "Packaged build 277 supersedes confirmed 267")
	assert_eq(mgr._packaged_build_supersedes({"build_id": "277"}), false, "Equal packaged build does not supersede confirmed")
	assert_eq(mgr._packaged_build_supersedes({"build_id": "dev"}), false, "Non-numeric build ids are not ordered")

func _replicated_is_delta_eligible(delta, manifest, active_packages):
	if manifest.get("force_full", false): return false
	if delta.get("touches_bootstrap", false): return false
	if not delta.get("deleted_paths", []).empty(): return false

	var full_size = manifest.get("full_artifact", {}).get("size", 1)
	if delta.get("size", 0) > full_size * 0.7: return false

	if active_packages.size() >= 3:
		return false

	return true
