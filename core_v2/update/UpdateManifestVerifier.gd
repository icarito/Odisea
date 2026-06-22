extends Reference

const Utils = preload("res://core_v2/update/UpdateUtils.gd")

const MAX_ENVELOPE_SIZE = 2 * 1024 * 1024 # 2 MiB
const SCHEMA_VERSION = 1

var _keyring: Reference

func _init(keyring: Reference):
	_keyring = keyring

func verify(envelope: Dictionary) -> Dictionary:
	if not envelope.has("payload_b64") or not envelope.has("signatures"):
		return {"error": "missing_fields"}

	if envelope.has("schema_version") and envelope["schema_version"] != SCHEMA_VERSION:
		return {"error": "unknown_schema"}

	var payload_b64 = envelope["payload_b64"]
	if payload_b64.length() > MAX_ENVELOPE_SIZE:
		return {"error": "envelope_too_large"}

	var payload_raw = Marshalls.base64_to_raw(payload_b64)
	if payload_raw.size() == 0:
		return {"error": "invalid_base64"}

	var signatures = envelope["signatures"]
	if not (signatures is Array):
		return {"error": "invalid_signatures_format"}

	var verified = false
	var now = OS.get_unix_time()

	var crypto = Crypto.new()
	var payload_hash = Utils.get_sha256_hash(payload_raw)

	for sig_obj in signatures:
		if not sig_obj.has("key_id") or not sig_obj.has("value_b64"):
			continue

		var key_id = sig_obj["key_id"]
		var key_info = _keyring.get_key(key_id)
		if key_info.empty():
			continue

		# Check validity window
		var nb = Utils.iso8601_to_unix(key_info["not_before"])
		var na = Utils.iso8601_to_unix(key_info["not_after"])
		if now < nb or now > na:
			continue

		var pub_key = _load_pub_key(key_info["public_key_path"])
		if pub_key == null:
			continue

		var signature = Marshalls.base64_to_raw(sig_obj["value_b64"])
		if signature.size() == 0:
			continue

		# RSASSA-PKCS1-v1_5-SHA256
		# Godot 3.6: verify(hash_type, hash, signature, key)
		if crypto.verify(HashingContext.HASH_SHA256, payload_hash, signature, pub_key):
			verified = true
			break

	if not verified:
		return {"error": "invalid_signature"}

	var json_str = payload_raw.get_string_from_utf8()
	var json_res = JSON.parse(json_str)
	if json_res.error != OK:
		return {"error": "invalid_json_payload"}

	var payload = json_res.result
	if not (payload is Dictionary):
		return {"error": "invalid_payload_type"}

	return {"payload": payload}

func _load_pub_key(path: String) -> CryptoKey:
	var key = CryptoKey.new()
	# public_only=true: the keyring ships SPKI public PEMs; without this flag
	# Godot 3.6 expects a private key and load() fails (mbedtls parse error).
	var err = key.load(path, true)
	if err != OK:
		return null
	return key
