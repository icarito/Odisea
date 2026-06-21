extends Reference

const Utils = preload("res://core_v2/update/UpdateUtils.gd")

const KEYRING = {
	"release-2026-a": {
		"algorithm": "RSASSA-PKCS1-v1_5-SHA256",
		"public_key_path": "res://core_v2/update/keys/release-2026-a.pub",
		"not_before": "2026-06-21T00:00:00Z",
		"not_after": "2027-06-30T23:59:59Z"
	}
}

func get_key(key_id: String) -> Dictionary:
	if KEYRING.has(key_id):
		return KEYRING[key_id].duplicate()
	return {}

func get_valid_keys(at_time: int) -> Array:
	var valid_keys = []
	for key_id in KEYRING:
		var key_info = KEYRING[key_id]
		var nb = Utils.iso8601_to_unix(key_info["not_before"])
		var na = Utils.iso8601_to_unix(key_info["not_after"])

		if at_time >= nb and at_time <= na:
			var info = key_info.duplicate()
			info["id"] = key_id
			valid_keys.append(info)
	return valid_keys
