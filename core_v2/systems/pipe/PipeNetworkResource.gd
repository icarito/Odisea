extends Resource
class_name PipeNetworkResource

# PipeNetworkResource.gd — Topología ordenada de red de tuberías de refrigerante.
#
# branches: Dictionary { branch_id (String) -> BranchData }
# BranchData (Dictionary): {
#   "tank": NodePath,
#   "segments": Array of SegmentData   # EN ORDEN, del tanque al sumidero
# }
# SegmentData (Dictionary): {
#   "pipe_run": NodePath,   # el PipeCoolantRun de este tramo
#   "valve": NodePath,      # opcional (puede ser NodePath vacío): válvula EN LA ENTRADA de este tramo
#   "leak": NodePath,       # opcional (puede ser NodePath vacío): fisura EN LA ENTRADA de este tramo
#   "flow_dir": Vector3,    # dirección de este tramo, en coordenadas de mundo
#   "spur": bool            # opcional (default false): RAMAL colgado del tronco (medio toro
#                           # de piso, bucle de criopods). Toma caudal del tramo anterior,
#                           # pero lo que le pasa no vuelve a la columna: su válvula y su
#                           # fisura solo lo afectan a él, nunca a lo que sigue aguas arriba.
#                           # Va DESPUÉS del tramo de tronco que lo alimenta.
# }
export(Dictionary) var branches := {}


func validate(context: Node = null) -> Dictionary:
	var errors := []
	var seen_pipe_run_paths := {}
	var seen_pipe_run_nodes := {}

	for branch_id in branches:
		var branch_data = branches[branch_id]
		if not branch_data is Dictionary:
			errors.append("Branch '%s' is not a Dictionary." % str(branch_id))
			continue

		# 2. Check tank (missing or empty)
		var tank_path = branch_data.get("tank", null)
		if tank_path == null or (tank_path is NodePath and tank_path.is_empty()) or (tank_path is String and tank_path == ""):
			errors.append("Branch '%s' has a missing or empty tank NodePath." % str(branch_id))
		elif context != null:
			var tank_node = context.get_node_or_null(tank_path)
			if tank_node == null:
				errors.append("Branch '%s' tank NodePath '%s' could not be resolved." % [str(branch_id), str(tank_path)])

		# 3. Check segments (empty or invalid)
		var segments = branch_data.get("segments", null)
		if not segments is Array or segments.size() == 0:
			errors.append("Branch '%s' has an empty or invalid segments array." % str(branch_id))
			continue

		for idx in range(segments.size()):
			var seg = segments[idx]
			if not seg is Dictionary:
				errors.append("Branch '%s' segment [%d] is not a Dictionary." % [str(branch_id), idx])
				continue

			# Check pipe_run
			var pipe_run_path = seg.get("pipe_run", null)
			if pipe_run_path == null or (pipe_run_path is NodePath and pipe_run_path.is_empty()) or (pipe_run_path is String and pipe_run_path == ""):
				errors.append("Branch '%s' segment [%d] has a missing or empty pipe_run NodePath." % [str(branch_id), idx])
			else:
				var path_str := str(pipe_run_path)
				# 4. Check duplicate pipe_run by String representation
				if seen_pipe_run_paths.has(path_str):
					errors.append("Branch '%s' segment [%d] reuses pipe_run path '%s' previously seen in branch '%s'." % [str(branch_id), idx, path_str, seen_pipe_run_paths[path_str]])
				else:
					seen_pipe_run_paths[path_str] = str(branch_id)

				if context != null:
					# 1. Resolve pipe_run NodePath
					var pipe_node = context.get_node_or_null(pipe_run_path)
					if pipe_node == null:
						errors.append("Branch '%s' segment [%d] pipe_run NodePath '%s' could not be resolved." % [str(branch_id), idx, path_str])
					else:
						if seen_pipe_run_nodes.has(pipe_node):
							errors.append("Branch '%s' segment [%d] pipe_run node '%s' resolves to a duplicate node instance." % [str(branch_id), idx, path_str])
						else:
							seen_pipe_run_nodes[pipe_node] = true

			if context != null:
				# Check optional valve resolution if non-empty
				var valve_path = seg.get("valve", null)
				if valve_path != null:
					if (valve_path is NodePath and not valve_path.is_empty()) or (valve_path is String and valve_path != ""):
						var valve_node = context.get_node_or_null(valve_path)
						if valve_node == null:
							errors.append("Branch '%s' segment [%d] valve NodePath '%s' could not be resolved." % [str(branch_id), idx, str(valve_path)])

				# Check optional leak resolution if non-empty
				var leak_path = seg.get("leak", null)
				if leak_path != null:
					if (leak_path is NodePath and not leak_path.is_empty()) or (leak_path is String and leak_path != ""):
						var leak_node = context.get_node_or_null(leak_path)
						if leak_node == null:
							errors.append("Branch '%s' segment [%d] leak NodePath '%s' could not be resolved." % [str(branch_id), idx, str(leak_path)])

	return {
		"ok": errors.size() == 0,
		"errors": errors
	}
