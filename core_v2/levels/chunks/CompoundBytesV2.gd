extends Resource

# Bytes serializados de un compound de Box3D (`Box3DCompound.bake()`).
#
# Los consume `CompoundChunkBodyV2` para armar UNA shape (`Box3DCompoundShape`)
# en vez de decenas de primitivas. Los genera `tools/bake_chunk_compounds.gd`, que
# deja un `.res` por chunk body al lado de la escena.
#
# Ojo: el compound horneado depende de las versiones de arbol/mesh/hull del engine
# que lo horneo (ver docs del fork). Si se cambia el engine, rehornear.
#
# Sin class_name a proposito: los runs headless (bakes, tests) no registran clases
# globales nuevas hasta que el editor reescribe project.godot.

# Bytes del compound (b3ConvertCompoundToBytes).
export(PoolByteArray) var bytes := PoolByteArray()

# Cantidad de hijos horneados (informativo, para auditar).
export(int) var child_count := 0

# Escena fuente del horneado (informativo).
export(String) var source_scene := ""

# Tipos de collider que no se pudieron hornear (informativo; vacio = todos).
export(Array, String) var unsupported_shapes := []
