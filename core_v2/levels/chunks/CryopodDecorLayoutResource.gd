tool
extends Resource

export(Array, Transform) var pod_transforms := []
export(AABB) var combined_aabb := AABB()
export(Vector3) var runtime_origin_offset := Vector3.ZERO
