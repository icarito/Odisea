extends Spatial
class_name CriopodRingCollisionV2

# FD-314 - Colision del anillo de criopods decorativos, streameada por chunk.
#
# El StaticBody trae una caja por pod. Cuando el chunk entra, lee el slot que el
# despertar bloqueo (el pod funcional ocupa ese lugar) desde el visual del shell y
# libera la caja correspondiente, igual que antes se liberaba el Item_N completo.

export(NodePath) var slot_provider_path := NodePath("")
export(String) var body_path := "Criopods1/StaticBody"
# slot del RadialScatter -> indice de pod (`Pod_%02d`); -1 si no tiene pod.
export(Array, int) var slot_to_pod := []

func _ready() -> void:
	call_deferred("_free_blocked_slot")

func _free_blocked_slot() -> void:
	var slot := _provider_blocked_slot()
	if slot >= 0:
		free_slot(slot)

func free_slot(slot: int) -> int:
	if slot < 0 or slot >= slot_to_pod.size():
		return -1
	var pod := int(slot_to_pod[slot])
	if pod < 0:
		return -1
	var body := get_node_or_null(body_path)
	if body == null:
		return -1
	var shape: CollisionShape = body.get_node_or_null("Pod_%02d" % pod)
	if shape == null:
		return -1
	shape.disabled = true
	body.remove_child(shape)
	shape.free()
	return pod

func _provider_blocked_slot() -> int:
	var provider := get_node_or_null(slot_provider_path)
	if provider != null and provider.has_method("get_blocked_slot"):
		return int(provider.get_blocked_slot())
	return -1
