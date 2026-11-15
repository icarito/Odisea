extends SceneTree

# Exporta el catalogo de chunks (ScaffoldChunkRegistry) a JSON para el scene script de
# Blender. El registro es la fuente de medidas; este JSON es un derivado, se regenera.
# Run: "$(sh tools/godot_bin.sh)" --path . --no-window -s tools/scaffold_chunks/export_registry.gd

const Registry := preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")
const OUT := "res://tools/scaffold_chunks/chunks.json"


static func metrics() -> Dictionary:
	var fm = FlowMetricsScript.from_scene()
	return {"g": fm.gravity, "v_run": fm.run_speed(), "v_jump": fm.jump_force, "tick": 1.0 / 60.0}


static func _plain(v):
	match typeof(v):
		TYPE_VECTOR3:
			return [v.x, v.y, v.z]
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _plain(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for item in v:
				a.append(_plain(item))
			return a
	return v


func _init() -> void:
	var m := metrics()
	var out := {"chunk_length": Registry.CHUNK_LENGTH, "walkway_width": Registry.WALKWAY_WIDTH,
		"rail_height": Registry.RAIL_HEIGHT, "chunks": {}}
	for id in Registry.chunk_ids():
		out["chunks"][id] = _plain(Registry.build_chunk(id, m))
	var f := File.new()
	f.open(OUT, File.WRITE)
	f.store_string(JSON.print(out, "  ", true))
	f.close()
	print("[export_registry] %d chunks -> %s" % [out["chunks"].size(), OUT])
	quit(0)
