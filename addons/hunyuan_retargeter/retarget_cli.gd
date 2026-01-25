extends SceneTree

# Script CLI para retargetear animaciones de Hunyuan al Pilot
#
# USO:
#   godot3-bin --path /path/to/project --script addons/hunyuan_retargeter/retarget_cli.gd -- path/to/animation.tres
#
# También funciona con escenas que contengan AnimationPlayer:
#   godot3-bin --path /path/to/project --script addons/hunyuan_retargeter/retarget_cli.gd -- path/to/scene.tscn

# Ruta al skeleton en la escena del Pilot (relativa al AnimationPlayer)
const TARGET_SKELETON_PATH = "Pivot/Skeleton"

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


func _init():
	var args = OS.get_cmdline_args()
	
	# Buscar argumentos después de "--"
	var file_path = ""
	var found_separator = false
	for arg in args:
		if arg == "--":
			found_separator = true
			continue
		if found_separator and file_path == "":
			file_path = arg
			break
	
	if file_path == "":
		print("ERROR: No se especificó archivo de animación")
		print("")
		print("USO:")
		print("  godot3-bin --path PROJECT_DIR --script addons/hunyuan_retargeter/retarget_cli.gd -- ANIMATION_FILE")
		print("")
		print("Ejemplos:")
		print("  godot3-bin --path . --script addons/hunyuan_retargeter/retarget_cli.gd -- res://animations/backflip.tres")
		print("  godot3-bin --path . --script addons/hunyuan_retargeter/retarget_cli.gd -- res://scenes/Pilot_v2.tscn")
		quit(1)
		return
	
	print("=== Hunyuan Animation Retargeter ===")
	print("Input: " + file_path)
	
	# Determinar si es animación o escena
	if file_path.ends_with(".tscn") or file_path.ends_with(".scn") or file_path.ends_with(".glb") or file_path.ends_with(".gltf"):
		process_scene(file_path)
	elif file_path.ends_with(".tres") or file_path.ends_with(".res") or file_path.ends_with(".anim"):
		process_animation_file(file_path)
	else:
		print("ERROR: Tipo de archivo no soportado. Use .tscn, .glb, .tres, o .anim")
		quit(1)
		return
	
	print("=== Done ===")
	quit(0)


func process_scene(scene_path: String):
	print("Procesando escena...")
	
	var scene = load(scene_path)
	if scene == null:
		print("ERROR: No se pudo cargar la escena: " + scene_path)
		quit(1)
		return
	
	var root = scene.instance()
	var total_fixed = 0
	
	# Buscar todos los AnimationPlayer en la escena
	var anim_players = find_animation_players(root)
	print("Encontrados " + str(anim_players.size()) + " AnimationPlayer(s)")
	
	# Determinar directorio de salida (mismo que el GLB, con sufijo _retargeted)
	var base_path = scene_path.get_base_dir()
	var base_name = scene_path.get_file().get_basename()
	
	for anim_player in anim_players:
		print("  AnimationPlayer: " + anim_player.name)
		for anim_name in anim_player.get_animation_list():
			var anim = anim_player.get_animation(anim_name)
			var fixed = fix_animation(anim, anim_name)
			total_fixed += fixed
			
			# Guardar cada animación como .tres
			if fixed > 0:
				var output_path = base_path + "/" + base_name + "_" + anim_name + ".tres"
				var err = ResourceSaver.save(output_path, anim)
				if err == OK:
					print("    -> Guardado: " + output_path)
				else:
					print("    -> ERROR al guardar: " + str(err))
	
	print("Total tracks modificados: " + str(total_fixed))
	root.queue_free()


func process_animation_file(anim_path: String):
	print("Procesando animación...")
	
	var anim = load(anim_path)
	if anim == null:
		print("ERROR: No se pudo cargar la animación: " + anim_path)
		quit(1)
		return
	
	if not anim is Animation:
		print("ERROR: El archivo no es una animación válida")
		quit(1)
		return
	
	var fixed = fix_animation(anim, anim_path.get_file())
	print("Tracks modificados: " + str(fixed))
	
	if fixed > 0:
		var err = ResourceSaver.save(anim_path, anim)
		if err == OK:
			print("Animación guardada: " + anim_path)
		else:
			print("ERROR al guardar animación: " + str(err))


func find_animation_players(node: Node) -> Array:
	var result = []
	if node is AnimationPlayer:
		result.append(node)
	for child in node.get_children():
		result += find_animation_players(child)
	return result


func fix_animation(anim: Animation, anim_name: String) -> int:
	var fixed_count = 0
	var track_count = anim.get_track_count()
	
	print("    Animation '" + anim_name + "': " + str(track_count) + " tracks")
	
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
		
		print("      - " + path_str + " -> " + new_path_str)
		fixed_count += 1
	
	return fixed_count
