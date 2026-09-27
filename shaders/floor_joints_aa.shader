shader_type spatial;
// floor_joints_aa.shader — juntas del piso de RingHub con anti-aliasing por cobertura.
//
// Las juntas son GEOMETRIA (cintas de 6 cm en RingHub_Floor_joints_baked.mesh, a
// 1.2 cm sobre el piso), no textura: a distancia o en angulo rasante la cinta queda
// sub-pixel y la rasterizacion aliasa (moire). Los mipmaps no aplican a geometria,
// asi que el antialias se hace aqui bajando la opacidad segun cuantos pixeles de
// pantalla ocupa el ancho de la linea: si queda por debajo de coverage_threshold_px,
// el alpha baja proporcional (lineas finas = tenues, sin chispas). La cobertura se
// estima con la derivada de la posicion mundial (el mesh trae UV planar mundo/4,
// sin coordenada transversal por junta); en rasante el footprint crece y el alpha
// cae solo, que es justo donde vive el moire. El distance fade es refuerzo para el
// borde lejano del domo. Sustituye a RingHub_Floor_joints.tres (SpatialMaterial)
// en desktop; en low-end/flat sigue ese (ver comentario alli y RingHubFloorMaterial.gd).
//
// Asignar a un MeshInstance en Godot 3: seleccionar el nodo -> Inspector ->
// Material Override -> Nuevo ShaderMaterial, y en su propiedad Shader cargar este
// archivo (los uniforms se editan en el mismo Inspector). Desde codigo:
//   var m := ShaderMaterial.new()
//   m.shader = load("res://shaders/floor_joints_aa.shader")
//   mesh_instance.material_override = m
//
// GLES2 (fallback): las derivadas requieren GL_OES_standard_derivatives y el camino
// low-end nunca asigna este material (usa el SpatialMaterial), asi que si un
// dispositivo cae a GLES2 con variant desktop, el shader no compila y las juntas
// desaparecen: degrade aceptable, el piso sigue.
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform vec4 line_color : hint_color = vec4(0.45, 0.52, 0.59, 1.0);
// Emision equivalente a la del .tres clasico (sostiene la junta en DARK sin neon;
// en flat el gate mapea max(em)*4 a glow). Aqui la emision viaja dentro del alpha,
// asi que el fade la apaga junto con el resto en vez de dejar brillos sueltos.
uniform vec4 emission_color : hint_color = vec4(0.03, 0.06, 0.08, 1.0);
uniform float line_opacity : hint_range(0.0, 1.0) = 1.0;
// Ancho real de la cinta horneada (JOINT_WIDTH del bake): calibra width_px.
uniform float joint_width_m : hint_range(0.01, 0.5) = 0.06;
// Pixeles de ancho a partir de los cuales la linea rinde alpha completo.
uniform float coverage_threshold_px : hint_range(1.0, 16.0) = 4.0;
// Distance fade: entre min y max el alpha baja de 1 a 0.
uniform float fade_min_distance : hint_range(0.0, 500.0) = 60.0;
uniform float fade_max_distance : hint_range(0.0, 500.0) = 120.0;

varying vec3 world_pos_v;

void vertex() {
	world_pos_v = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Footprint del pixel en metros sobre el piso: suma de ambas derivadas para
	// no cancelar diagonales. En rasante el footprint crece y width_px baja.
	float pixel_size_m = length(dFdx(world_pos_v)) + length(dFdy(world_pos_v));
	float width_px = joint_width_m / max(pixel_size_m, 1e-5);
	float coverage = clamp(width_px / coverage_threshold_px, 0.0, 1.0);
	float dist_fade = 1.0 - smoothstep(fade_min_distance, fade_max_distance, length(VERTEX));
	ALPHA = line_color.a * line_opacity * coverage * dist_fade;
	ALBEDO = line_color.rgb;
	EMISSION = emission_color.rgb;
	ROUGHNESS = 0.8;
}
