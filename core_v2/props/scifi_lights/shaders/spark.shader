shader_type spatial;
render_mode blend_add,depth_draw_opaque,cull_disabled,unshaded;

uniform vec4 spark_color : hint_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform sampler2D spark_texture : hint_albedo;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	VERTEX.yz *= 5.0;
	VERTEX.x *= 0.05;
}

void fragment() {
	vec4 tex = texture(spark_texture, UV);
	float glow = tex.a * COLOR.a * brightness;
	ALBEDO = spark_color.rgb * glow * 2.0;
	ALPHA = glow;
}
