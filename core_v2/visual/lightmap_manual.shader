shader_type spatial;

// Aplica el lightmap horneado SIN pasar por el camino del motor.
//
// Godot ata la textura del lightmap a "max_texture_image_units - 4"
// (rasterizer_scene_gles2.cpp, sin guardarraiz). En Android eso cae en la unidad 12 y
// en escritorio en la 28, lejos de todo; en iOS, que expone 8 unidades, cae en la 4 --
// en el medio de las texturas del material y compartida con screen_texture/depth_texture
// (los tres declaran //texunit:-4 en scene.glsl). Una colision de unidad no produce
// error de linkeo, que es lo que veniamos viendo: log limpio y bake ausente.
//
// Aca la textura entra como un uniform normal, asi que el compilador le da una unidad
// secuencial y no hay slot compartido. Es EL MISMO bake, la misma UV2 y las mismas
// texturas: lo unico que cambia es quien la muestrea.
//
// El bake va por EMISSION porque un shader spatial de Godot 3 no puede escribir el
// ambiente directamente, y EMISSION se suma despues de la iluminacion -- el mismo lugar
// donde el motor suma el ambiente horneado.

uniform vec4 albedo_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : hint_albedo;
uniform bool has_albedo_map = false;
uniform sampler2D lightmap_tex : hint_albedo;
uniform float lightmap_energy = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 tex = vec4(1.0);
	if (has_albedo_map) {
		tex = texture(texture_albedo, UV);
	}
	vec3 base = albedo_color.rgb * tex.rgb;
	ALBEDO = base;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = base * texture(lightmap_tex, UV2).rgb * lightmap_energy;
}
