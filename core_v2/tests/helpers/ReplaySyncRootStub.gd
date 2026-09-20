extends Spatial
# Stub minimo para test_world_snapshot_includes_scene_root_itself_when_in_replay_sync:
# un nodo "replay_sync" con get_snapshot(), como lo tendria el script de un nivel
# pegado a la raiz de su propia escena (ej. RingHubWakeup).

func get_snapshot() -> Dictionary:
	return {"stub": true}
