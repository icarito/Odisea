tool
extends Reference
class_name PipeKit

# PipeKit.gd — catalogo del kit modular de caneria (assets/models/Modular Pipes).
#
# El kit trae 53 piezas x 2 materiales (metal / pvc) en UN glTF, direccionables por
# nombre de nodo. Este archivo es lo unico que hay que leer para armar geometria:
# guarda, por pieza, DONDE estan sus puertos y hacia donde miran. Esos datos estan
# MEDIDOS de la malla (anillos de seccion), no copiados de la documentacion del
# asset; tools/verify_pipe_kit.gd los vuelve a medir y falla si el kit cambia.
#
# Convenciones del kit, ya verificadas:
#
#   calibre grueso  Ø0.10 (radio de seccion 0.052)
#     recto      pipe_<N>cm         de (0,0,0) a (0,L,0)      -> corre sobre +Y
#     codo       pipe_turn_short    (0,0,0) -Y  ->  (0.10, 0.098, 0) +X
#                pipe_turn_long     (0,0,0) -Y  ->  (0.20, 0.198, 0) +X
#     T          pipe_junction_t    (0,0,0) -Y  +  (-0.10, 0.098, 0) y (0.10, 0.098, 0)
#     cruz       pipe_junction_x    (0,0,0) y (0,0.20,0)  +  (-0.10,0.10,0) y (0.10,0.10,0)
#     reduccion  pipe_to_thin       (0,0,0) grueso -> (0,0.05,0) fino
#     valvula    pipe_valve_small_1 (0,0,0) a (0,0.40,0)  <- MISMOS puertos que un recto
#                                    de 40cm, o sea que entra sin tocar el trazado
#
#   calibre fino    Ø0.06 (radio 0.031)
#     recto      pipe_thin_<N>cm    de (0,0,0) a (L,0,0)      -> corre sobre +X
#
# Ojo: los rectos finos corren sobre X y los gruesos sobre Y. No es un error de
# lectura, el kit viene asi; el builder tiene que rotar el fino 90 grados para
# tratar los dos calibres igual.

const RUTA := "res://assets/models/Modular Pipes/1k/modular_pipes_1k.gltf"

# Largos disponibles, de mayor a menor: el ajuste greedy los consume en este orden.
const LARGOS := [2.0, 1.4, 1.0, 0.6, 0.4, 0.2, 0.1, 0.05]
const LARGO_NOMBRE := {2.0: "200cm", 1.4: "140cm", 1.0: "100cm", 0.6: "60cm",
	0.4: "40cm", 0.2: "20cm", 0.1: "10cm", 0.05: "5cm"}

const GRUESO := "grueso"
const FINO := "fino"

# radio de seccion por calibre, medido
const RADIO := {GRUESO: 0.052, FINO: 0.031}
# eje sobre el que corre un recto de cada calibre, tal como viene el asset
const EJE_RECTO := {GRUESO: Vector3(0, 1, 0), FINO: Vector3(1, 0, 0)}

# Puertos por pieza: lista de [posicion local, direccion saliente].
const PUERTOS := {
	"turn_short": [[Vector3(0, 0, 0), Vector3(0, -1, 0)],
		[Vector3(0.100, 0.098, 0), Vector3(1, 0, 0)]],
	"turn_long": [[Vector3(0, 0, 0), Vector3(0, -1, 0)],
		[Vector3(0.200, 0.198, 0), Vector3(1, 0, 0)]],
	"junction_t": [[Vector3(0, 0, 0), Vector3(0, -1, 0)],
		[Vector3(-0.100, 0.098, 0), Vector3(-1, 0, 0)],
		[Vector3(0.100, 0.098, 0), Vector3(1, 0, 0)]],
	"junction_x": [[Vector3(0, 0, 0), Vector3(0, -1, 0)],
		[Vector3(0, 0.200, 0), Vector3(0, 1, 0)],
		[Vector3(-0.100, 0.100, 0), Vector3(-1, 0, 0)],
		[Vector3(0.100, 0.100, 0), Vector3(1, 0, 0)]],
	"to_thin": [[Vector3(0, 0, 0), Vector3(0, -1, 0)],
		[Vector3(0, 0.050, 0), Vector3(0, 1, 0)]],
}

# Piezas que ocupan un tramo recto y se pueden sustituir por uno: el builder las
# mete sin recalcular nada. El valor es el largo que consumen.
const EN_LINEA := {"valve_small_1": 0.4, "valve_small_2": 0.4, "valve_large": 0.5}

var _cache := {}


func nombre(pieza: String, calibre: String = GRUESO, material: String = "metal") -> String:
	var prefijo: String = "pipe_" + ("thin_" if calibre == FINO else "")
	return prefijo + pieza + "_" + material


# Malla de una pieza, por nombre de nodo del kit. Se cachea: el glTF entero se
# instancia UNA vez por sesion, no una vez por tramo.
func malla(nombre_nodo: String) -> Mesh:
	if _cache.empty():
		var raiz: Node = load(RUTA).instance()
		var pila := [raiz]
		while not pila.empty():
			var n: Node = pila.pop_back()
			if n is MeshInstance and n.mesh != null:
				_cache[n.name] = n.mesh
			for h in n.get_children():
				pila.append(h)
		raiz.free()
	return _cache.get(nombre_nodo)


# Descompone un largo en piezas del catalogo, de mayor a menor. Devuelve la lista de
# largos usados; el resto (< 5cm) se informa como sobrante para que el llamador
# decida si estira la ultima pieza o mueve el nodo.
func ajustar(largo: float) -> Dictionary:
	var piezas := []
	var resto: float = largo
	for l in LARGOS:
		while resto >= l - 0.0005:
			piezas.append(l)
			resto -= l
	return {"piezas": piezas, "sobrante": resto}
