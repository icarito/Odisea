extends Reference

static func iso8601_to_unix(iso_str: String) -> int:
	# Expects "YYYY-MM-DDTHH:MM:SSZ"
	var parts = iso_str.replace("Z", "").split("T")
	if parts.size() != 2:
		return 0

	var date_parts = parts[0].split("-")
	var time_parts = parts[1].split(":")

	if date_parts.size() != 3 or time_parts.size() != 3:
		return 0

	var datetime = {
		"year": int(date_parts[0]),
		"month": int(date_parts[1]),
		"day": int(date_parts[2]),
		"hour": int(time_parts[0]),
		"minute": int(time_parts[1]),
		"second": int(time_parts[2])
	}

	return OS.get_unix_time_from_datetime(datetime)

static func get_sha256_hash(data: PoolByteArray) -> PoolByteArray:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()
