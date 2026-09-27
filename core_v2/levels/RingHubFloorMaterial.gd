extends MeshInstance

# RingHubFloorMaterial.gd — Variante del material del piso del domo de RingHub.
#
# Desktop : M_RingHubFloor_desktop (PBR completo: albedo + normal + rough + ao,
#           Rusty Metal Grid sobre las UV1 planares del bake).
# Mobile  : M_RingHubFloor_mobile  (misma textura albedo, sin normal/rough/ao).
#
# En el handheld el tier LOW corre con ODISEA_UNSHADED=2: GLES3VendorGate deja
# los SpatialMaterial unshaded conservando su albedo, asi que la variante movil se
# ve texturada igual y ademas no carga los mapas que ese camino ignora.
#
# La capa de juntas (FloorJoints) tambien elige por tier: desktop usa
# RingHub_Floor_joints_aa.tres (shader con AA por cobertura contra el moire de
# las lineas sub-pixel); low-end sigue con el SpatialMaterial clasico (ver
# resolve_joints_material).
#
# La eleccion se resuelve en _enter_tree(): el gate procesa el nodo en node_added
# (que llega despues de _enter_tree), asi que ve el material final y le aplica su
# aplanado de tier LOW al que quedo puesto.
#
# Forzar para comparar A/B:
#   ODISEA_RINGHUB_FLOOR_VARIANT=desktop|mobile tools/launch_game.sh
# o fijar `variant` (Auto/Desktop/Mobile) en el Inspector.

const DESKTOP_MATERIAL := preload("res://core_v2/levels/interiors/RingHub_Floor_desktop.tres")
const MOBILE_MATERIAL := preload("res://core_v2/levels/interiors/RingHub_Floor_mobile.tres")
const JOINTS_MESH := preload("res://core_v2/levels/RingHub_Floor_joints_baked.mesh")
const JOINTS_MATERIAL := preload("res://core_v2/levels/interiors/RingHub_Floor_joints.tres")
const JOINTS_MATERIAL_AA := preload("res://core_v2/levels/interiors/RingHub_Floor_joints_aa.tres")
const FLOOR_MESH_PATH := "res://core_v2/levels/RingHub_Floor_baked.mesh"
const FORCE_ENV := "ODISEA_RINGHUB_FLOOR_VARIANT"

const VARIANT_AUTO := 0
const VARIANT_DESKTOP := 1
const VARIANT_MOBILE := 2

export(int, "Auto", "Desktop", "Mobile") var variant := VARIANT_AUTO


func _enter_tree() -> void:
	material_override = resolve_material()


# Capa de juntas emisivas (referencia visual del piso en DARK y en low-end). Se
# agrega como nodo hijo porque el material_override del piso pinta TODAS sus
# superficies: las juntas necesitan su propio nodo/material. Va en _ready, no en
# _enter_tree, para que el nodo ya este en el arbol; el gate lo procesa por su
# node_added igual que al piso. Solo aplica al mesh real del piso (los tests
# instancian el script sin mesh y no deben ganar geometria).
func _ready() -> void:
	if mesh == null or mesh.resource_path != FLOOR_MESH_PATH:
		return
	if has_node("FloorJoints"):
		return
	var joints := MeshInstance.new()
	joints.name = "FloorJoints"
	joints.mesh = JOINTS_MESH
	joints.material_override = resolve_joints_material()
	joints.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	joints.use_in_baked_light = false
	add_child(joints)


func resolve_material() -> Material:
	return _pick_tier_material(DESKTOP_MATERIAL, MOBILE_MATERIAL)


# Juntas por tier, misma decision que resolve_material. Desktop lleva el shader
# AA (el moire es rasterizacion de lineas sub-pixel: no lo arregla el piso).
# LOW conserva el SpatialMaterial clasico porque el gate NO preserva un fade:
# en flat (_flat_material) descarta el material fuente y en unshaded=2
# (_low_tier_material) apaga flags_transparent, que romperia el blend; ademas
# un ShaderMaterial sobreviviente quedaria lit en un mundo unshaded (se apaga
# en DARK y pierde la referencia del piso).
func resolve_joints_material() -> Material:
	return _pick_tier_material(JOINTS_MATERIAL_AA, JOINTS_MATERIAL)


# Decision compartida por env -> Inspector -> gate -> desktop. Los tests que
# instancian el script sin mesh ejercitan exactamente estos caminos.
func _pick_tier_material(desktop_mat: Material, mobile_mat: Material) -> Material:
	var forced := OS.get_environment(FORCE_ENV).strip_edges().to_lower()
	if forced == "mobile":
		return mobile_mat
	if forced == "desktop":
		return desktop_mat
	if variant == VARIANT_MOBILE:
		return mobile_mat
	if variant == VARIANT_DESKTOP:
		return desktop_mat
	var gate := get_node_or_null("/root/GLES3VendorGate")
	if gate != null and gate.has_method("is_low_tier") and bool(gate.is_low_tier()):
		return mobile_mat
	return desktop_mat
