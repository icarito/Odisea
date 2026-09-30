extends Reference

# SnapshotTrace.gd - FD-316 (tarea DD): traza binaria de snapshots para el benchmark
# reproducible del render-esclavo. Se graba en desktop durante un replay y se reproduce
# solo-render en el Anbernic, sin red y sin simular.
#
# Formato (reusa el binario de los paquetes del protocolo, ver RemoteProtocol.encode_packet,
# `ccaa036b`):
#   2 bytes  magic + version de la traza
#   4 bytes  cantidad de snapshots (uint32 little-endian)
#   por snapshot: 4 bytes de largo (uint32 LE) + el paquete binario del snapshot
#     (magic + version + var2bytes), tal cual lo mandaria el sim host.
# El largo por snapshot permite decodificar de a uno: el device no retiene la traza entera
# en memoria (en RingHub cada snapshot lleva cientos de entidades).

const RemoteProtocolScript = preload("res://core_v2/net/RemoteProtocol.gd")

const TRACE_MAGIC := 0x53 # 'S' de Snapshot
const TRACE_VERSION := 1

# Escribe la traza completa en un solo archivo. Devuelve false si no se pudo abrir.
static func write(path: String, snapshots: Array) -> bool:
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		printerr("[SnapshotTrace] no se pudo escribir ", path)
		return false
	f.store_8(TRACE_MAGIC)
	f.store_8(TRACE_VERSION)
	f.store_32(snapshots.size())
	for snap in snapshots:
		var payload: PoolByteArray = RemoteProtocolScript.encode_packet(snap)
		f.store_32(payload.size())
		f.store_buffer(payload)
	f.close()
	print("[SnapshotTrace] traza escrita: ", path, " (", snapshots.size(), " snapshots)")
	return true

# Lee la traza completa (tests y verificacion). El playback usa Reader para no retener todo.
static func read(path: String) -> Array:
	var reader = Reader.new(path)
	var out: Array = []
	while reader.has_next():
		out.append(reader.next())
	reader.close()
	return out

# Cantidad de snapshots de una traza (0 si no se puede abrir).
static func count(path: String) -> int:
	var reader = Reader.new(path)
	var n: int = reader.count()
	reader.close()
	return n

# Lector secuencial: decodifica un snapshot por llamada y descarta el anterior.
class Reader:
	const HDR_MAGIC := 0x53
	const HDR_VERSION := 1

	var _f := File.new()
	var _ok := false
	var _count := 0
	var _index := 0

	func _init(path: String) -> void:
		_ok = _f.open(path, File.READ) == OK
		if not _ok:
			printerr("[SnapshotTrace] no se pudo abrir ", path)
			return
		var magic := _f.get_8()
		var version := _f.get_8()
		if magic != HDR_MAGIC or version != HDR_VERSION:
			printerr("[SnapshotTrace] cabecera invalida en ", path)
			_ok = false
			_f.close()
			return
		_count = _f.get_32()

	func is_open() -> bool:
		return _ok

	func count() -> int:
		return _count if _ok else 0

	func has_next() -> bool:
		return _ok and _index < _count

	func next() -> Dictionary:
		if not has_next():
			return {}
		var length := _f.get_32()
		_index += 1
		if length <= 0:
			return {}
		var payload := _f.get_buffer(length)
		if payload.size() != length:
			return {}
		var decoded = RemoteProtocolScript.decode_packet(payload)
		return decoded if decoded is Dictionary else {}

	func close() -> void:
		if _f.is_open():
			_f.close()
		_ok = false
