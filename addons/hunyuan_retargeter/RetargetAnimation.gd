tool
extends EditorScript

# Este script parchea las animaciones cargadas en un AnimationPlayer
# para que funcionen con el esqueleto del Pilot.
#
# USO:
# 1. Selecciona el AnimationPlayer en el editor
# 2. Ve a Script > Run (o Ctrl+Shift+X)
# 3. Todas las animaciones serán parcheadas automáticamente

# Ruta al skeleton en la escena del Pilot (relativa al AnimationPlayer)
const TARGET_SKELETON_PATH = "Visual/Pivot/Skeleton"

# Mapeo de huesos Hunyuan -> DEF-* del Pilot
const BONE_MAP = {
	"Pelvis": "DEF-hips", "Hips": "DEF-hips", "root": "DEF-hips",
	"Spine1": "DEF-spine", "Spine": "DEF-spine",
	"Spine2": "DEF-spine002", "Chest": "DEF-spine002",
	"Spine3": "DEF-spine003", "UpperChest": "DEF-spine003",
	"Neck": "DEF-neck",
	"Head": "DEF-head",
	"L_Hip": "DEF-thighL", "LeftUpLeg": "DEF-thighL",
	"L_Knee": "DEF-shinL", "LeftLeg": "DEF-shinL",
	"L_Ankle": "DEF-footL", "LeftFoot": "DEF-footL",
	"L_Foot": "DEF-toesL", "LeftToe": "DEF-toesL",
	"R_Hip": "DEF-thighR", "RightUpLeg": "DEF-thighR",
	"R_Knee": "DEF-shinR", "RightLeg": "DEF-shinR",
	"R_Ankle": "DEF-footR", "RightFoot": "DEF-footR",
	"R_Foot": "DEF-toesR", "RightToe": "DEF-toesR",
	"L_Collar": "DEF-shoulderL", "LeftShoulder": "DEF-shoulderL",
	"L_Shoulder": "DEF-upper_armL", "L_UpArm": "DEF-upper_armL",
	"L_Elbow": "DEF-forearmL", "L_LowArm": "DEF-forearmL",
	"L_Wrist": "DEF-handL", "L_Hand": "DEF-handL",
	"R_Collar": "DEF-shoulderR", "RightShoulder": "DEF-shoulderR",
	"R_Shoulder": "DEF-upper_armR", "R_UpArm": "DEF-upper_armR",
	"R_Elbow": "DEF-forearmR", "R_LowArm": "DEF-forearmR",
	"R_Wrist": "DEF-handR", "R_Hand": "DEF-handR",
	# Dedos
	"L_Thumb1": "DEF-thumb01L", "L_Thumb2": "DEF-thumb02L", "L_Thumb3": "DEF-thumb03L",
	"L_Index1": "DEF-f_index01L", "L_Index2": "DEF-f_index02L", "L_Index3": "DEF-f_index03L",
	"L_Middle1": "DEF-f_middle01L", "L_Middle2": "DEF-f_middle02L", "L_Middle3": "DEF-f_middle03L",
	"L_Ring1": "DEF-f_ring01L", "L_Ring2": "DEF-f_ring02L", "L_Ring3": "DEF-f_ring03L",
	"L_Pinky1": "DEF-f_pinky01L", "L_Pinky2": "DEF-f_pinky02L", "L_Pinky3": "DEF-f_pinky03L",
	"R_Thumb1": "DEF-thumb01R", "R_Thumb2": "DEF-thumb02R", "R_Thumb3": "DEF-thumb03R",
	"R_Index1": "DEF-f_index01R", "R_Index2": "DEF-f_index02R", "R_Index3": "DEF-f_index03R",
	"R_Middle1": "DEF-f_middle01R", "R_Middle2": "DEF-f_middle02R", "R_Middle3": "DEF-f_middle03R",
	"R_Ring1": "DEF-f_ring01R", "R_Ring2": "DEF-f_ring02R", "R_Ring3": "DEF-f_ring03R",
	"R_Pinky1": "DEF-f_pinky01R", "R_Pinky2": "DEF-f_pinky02R", "R_Pinky3": "DEF-f_pinky03R",
}


func _run():
	var selection = get_editor_interface().get_selection().get_selected_nodes()
	
	if selection.size() == 0:
		print("ERROR: Selecciona un AnimationPlayer primero!")
		return
	
	var anim_player = selection[0]
	if not anim_player is AnimationPlayer:
		print("ERROR: El nodo seleccionado no es un AnimationPlayer!")
		return
	
	print("=== Retargeting Animations ===")
	print("AnimationPlayer: " + anim_player.name)
	
	var total_fixed = 0
	
	for anim_name in anim_player.get_animation_list():
		var anim = anim_player.get_animation(anim_name)
		var fixed_in_anim = _fix_animation(anim, anim_name)
		total_fixed += fixed_in_anim
	
	print("=== Retargeting Complete ===")
	print("Total tracks fixed: " + str(total_fixed))
	print("")
	print("IMPORTANTE: Guarda la escena (Ctrl+S) para persistir los cambios!")


func _fix_animation(anim: Animation, anim_name: String) -> int:
	var fixed_count = 0
	var track_count = anim.get_track_count()
	
	print("  Animation '" + anim_name + "': " + str(track_count) + " tracks")
	
	for i in range(track_count):
		var path = anim.track_get_path(i)
		var path_str = str(path)
		
		# Separar node path de bone name
		var colon_idx = path_str.find(":")
		if colon_idx == -1:
			continue
		
		var node_path_part = path_str.substr(0, colon_idx)
		var bone_part = path_str.substr(colon_idx + 1)
		
		# Detectar si ya está parcheado
		if node_path_part == TARGET_SKELETON_PATH:
			continue
		
		# Buscar si es un track de skeleton (termina en "Skeleton")
		if not node_path_part.ends_with("Skeleton"):
			continue
		
		# Separar bone name de property suffix (si hay)
		var bone_name = bone_part
		var property_suffix = ""
		var second_colon = bone_part.find(":")
		if second_colon != -1:
			bone_name = bone_part.substr(0, second_colon)
			property_suffix = bone_part.substr(second_colon)
		
		# Mapear el nombre del hueso
		var new_bone_name = bone_name
		if BONE_MAP.has(bone_name):
			new_bone_name = BONE_MAP[bone_name]
		
		# Construir nueva ruta
		var new_path_str = TARGET_SKELETON_PATH + ":" + new_bone_name + property_suffix
		anim.track_set_path(i, NodePath(new_path_str))
		
		print("    - " + path_str + " -> " + new_path_str)
		fixed_count += 1
	
	return fixed_count
