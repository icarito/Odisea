extends SceneTree

# verify_criopod_bake.gd — Comprueba que el horneado de criopods no cambio nada
# observable, contra la escena original.
#
# Corre igual sobre la escena vieja y sobre la horneada, y emite las MISMAS lineas en
# las dos: asi la comparacion es un diff de texto y no una lectura a ojo.
#
#   1. huella de colision: origen mundial + radio envolvente de cada forma de la capa
#      Prop en los anillos, ordenados. Es lo que consume IceSubmergedCuller, asi que si
#      esta huella coincide el culler se comporta igual.
#   2. caja envolvente mundial de cada anillo dibujado (que la geometria caiga donde
#      estaba, no 1.5x mas lejos por el escalado del anillo).
#   3. lo que ve IceSubmergedCuller: cuantas formas registra y cuantas sepulta al subir
#      el hielo.
#   4. costo del batching de RadialScatter, si la escena todavia lo tiene.
#
# Run: godot3-bin --no-window -s tools/verify_criopod_bake.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const ShapeBounds := preload("res://core_v2/systems/collision/ShapeBounds.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var root: Node = load(SCENE_PATH).instance()
	get_root().add_child(root)

	# El costo del batching se mide ANTES de que corra su call_deferred: si la escena
	# todavia trae RadialScatter, se le pide el batch a mano y se cronometra.
	var t_batch := 0
	var rings := []
	for child in root.get_node("Spatial").get_children():
		if child.name.begins_with("Criopods"):
			rings.append(child)
	for ring in rings:
		if ring.has_method("_batch_static_meshes"):
			var t0 := OS.get_ticks_usec()
			ring._batch_static_meshes()
			t_batch += OS.get_ticks_usec() - t0

	for _i in range(180):
		yield(self, "idle_frame")

	# --- 1 y 2 -------------------------------------------------------------------
	var huella := []
	for ring in rings:
		var aabb := AABB()
		var primera := true
		for n in _walk(ring):
			if n is CollisionShape and n.shape != null:
				huella.append("%s|%.3f" % [
					_v(n.global_transform.origin), ShapeBounds.radius_of(n)])
			var dibuja: bool = (n is MeshInstance and n.mesh != null) \
				or (n is MultiMeshInstance and n.multimesh != null)
			if dibuja and n.visible:
				var caja: AABB = (n as VisualInstance).get_transformed_aabb()
				aabb = caja if primera else aabb.merge(caja)
				primera = false
		print("[aabb] %s pos=%s size=%s" % [ring.name, _v(aabb.position), _v(aabb.size)])
	huella.sort()
	print("[colision] %d formas  hash=%d" % [huella.size(), hash(PoolStringArray(huella).join(";"))])

	# --- 3 -----------------------------------------------------------------------
	var culler: Node = root.get_node_or_null("IceLevel/IceSubmergedCuller")
	if culler != null:
		print("[culler] inicial %s" % str(culler.get_stats()))
		var nivel: Node = root.get_node_or_null("IceLevel")
		if nivel != null and nivel.has_method("get_frost_ceiling"):
			for altura in [6.0, 12.0, 20.0]:
				# El culler NO usa la altura que recibe: relee get_frost_ceiling() del
				# nivel. Pasarle un numero sin mover ice_height lo dejaba midiendo
				# siempre la altura inicial y el test daba 0 sepultadas siempre.
				nivel.ice_height = altura
				culler._on_ice_height_changed(altura)
				var s: Dictionary = culler.get_stats()
				print("[culler] hielo=%.1f -> sepultadas=%d de %d" % [
					altura, s.submerged, s.tracked])
	else:
		print("[culler] NO ENCONTRADO")

	# --- 4 -----------------------------------------------------------------------
	print("[batch] RadialScatter._batch_static_meshes: %.1f ms en %d anillos" % [
		t_batch / 1000.0, rings.size()])
	quit()


func _v(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [v.x, v.y, v.z]


func _walk(node: Node, acc: Array = []) -> Array:
	acc.append(node)
	for c in node.get_children():
		_walk(c, acc)
	return acc
