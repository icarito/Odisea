extends StaticBody

# Cuerpo de chunk con toda su colision horneada en UN compound de Box3D.
#
# Reemplaza los cuerpos que apilaban decenas de primitivas (los sectores de
# scaffold traen 8 CollisionShape cada uno) por una sola shape que Box3D resuelve
# con su arbol AABB interno. Es el camino pensado para que el mapa crezca: los
# tiles se hornean offline, se guardan como bytes y se adjuntan/desadjuntan al
# cargar/descargar la region (`StreamedSceneChunkV2` instancia esta escena
# cuando el jugador entra al trigger y la libera al salir).
#
# STATIC-ONLY: Box3D ignora compounds en cuerpos dinamicos/kinematicos. Si algun
# dia un chunk necesita moverse, esto no sirve.
#
# Los bytes vienen de un `CompoundBytesV2` generado por
# `tools/bake_chunk_compounds.gd`.

# CompoundBytesV2 con la geometria en el espacio LOCAL de este cuerpo.
export(Resource) var compound: Resource

# Los sectores de scaffold definen la superficie de pasos (perfil metalico).
export(bool) var with_footstep_surface := false
export(Resource) var footstep_profile: Resource

const FOOTSTEP_SURFACE_SCRIPT := "res://core_v2/systems/footsteps/footstep_surface.gd"
const COMPOUND_BYTES_SCRIPT := "res://core_v2/levels/chunks/CompoundBytesV2.gd"

func _ready() -> void:
	if compound == null or compound.get_script() == null or String(compound.get_script().resource_path) != COMPOUND_BYTES_SCRIPT:
		push_error("CompoundChunkBodyV2: falta un CompoundBytesV2 valido en %s" % String(get_path()))
		return
	var bytes = compound.get("bytes")
	if not (bytes is PoolByteArray) or (bytes as PoolByteArray).size() < 8:
		push_error("CompoundChunkBodyV2: CompoundBytesV2 vacio en %s" % String(get_path()))
		return

	var shape := Box3DCompoundShape.new()
	shape.set_compound_bytes(bytes)
	var collider := CollisionShape.new()
	collider.name = "Compound"
	collider.shape = shape
	add_child(collider)

	if with_footstep_surface and footstep_profile != null:
		var surface := Spatial.new()
		surface.name = "FootstepSurface"
		surface.set_script(load(FOOTSTEP_SURFACE_SCRIPT))
		surface.set("footstep_profile", footstep_profile)
		add_child(surface)
