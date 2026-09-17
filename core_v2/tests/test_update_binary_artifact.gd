extends GdUnitTestSuite

# test_update_binary_artifact.gd - El updater debe poder reemplazar el runtime
# (binario de Godot) ademas del .pck cuando el manifest publica
# binary_full_artifact. Un cambio de fork (Box3D/FRT) sin swap de binario deja el
# update a medias y rompe el arranque.

const UpdateManagerScript = preload("res://core_v2/update/UpdateManager.gd")

func _manager() -> Node:
	var um = auto_free(UpdateManagerScript.new())
	um._build_meta_cache = {"channel": "nightly"}
	return um

func test_matching_runtime_hash_does_not_need_binary_update():
	var um = _manager()
	var exe_hash = File.new().get_sha256(OS.get_executable_path())
	var manifest = {"binary_full_artifact": {"sha256": exe_hash}}
	assert_bool(um._check_needs_binary_update(manifest)).is_false()

func test_different_runtime_hash_needs_binary_update():
	var um = _manager()
	var manifest = {"binary_full_artifact": {"sha256": "deadbeef"}}
	assert_bool(um._check_needs_binary_update(manifest)).is_true()

func test_manifest_without_runtime_does_not_need_binary_update():
	var um = _manager()
	assert_bool(um._check_needs_binary_update({})).is_false()

func test_replace_file_swaps_destination():
	var um = _manager()
	var src = "user://update_test_src.bin"
	var dst = "user://update_test_dst.bin"
	var f = File.new()
	f.open(src, File.WRITE)
	f.store_string("new-runtime")
	f.close()
	f.open(dst, File.WRITE)
	f.store_string("old-runtime")
	f.close()

	assert_bool(um._replace_file(src, dst)).is_true()
	assert_bool(File.new().file_exists(src)).is_false()
	f.open(dst, File.READ)
	assert_str(f.get_as_text()).is_equal("new-runtime")
	f.close()
	Directory.new().remove(dst)
