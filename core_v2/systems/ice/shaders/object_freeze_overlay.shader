shader_type spatial;
// Unshaded on purpose: this scene has ~20 overlapping OmniLights (GLES2 has no deferred
// renderer, so each one that reaches a surface is another lit pass), and a normally-lit
// next_pass here washed out against them — worst on the criopods, whose own base material
// is already a bright near-white, so frost_color barely read as different once lit. The
// old frost_decal.shader this replaces was unshaded for the same reason. A fixed fake
// key light (fake_light below) keeps some surface variation without depending on the
// scene's actual dynamic lights.
render_mode depth_draw_never, cull_back, unshaded;

// next_pass overlay: makes arbitrary static props freeze over as the rising ice line
// reaches them. Reuses the freeze-band/crack/restrained-emission visual language of
// core_v2/player/shaders/pilot_damage.shader (the Pilot's cold-damage suit shader), but
// keys off world-space height against a single shared ice_height_world uniform instead
// of a per-mesh local_y range — one shared material works for props of any size/shape
// with no per-object calibration, and updating that one uniform (on ice_height_changed)
// freezes/thaws every wrapped object at once.
//
// Uses sin/dot noise, not the dot+fract hash pilot_damage.shader/frost_decal.shader use:
// Adreno runs fragment math in mediump and that hash's large multiplied constants lose
// enough precision there to break into visible blocks (see gas_flipbook.shader's dither
// fix and the main ice shader's low-cost sine variation for the same issue).
// frost_color is deliberately more saturated than crack_color now: with roughness/specular
// toned down (matte, to kill the view-angle flicker) the only contrast left to make the
// rim/cracks read is color, so the two need to be visibly distinct instead of both being
// near-white — that's what made the pass look flat/uniform after the matte fix.
uniform vec4 frost_color : hint_color = vec4(0.62, 0.8, 0.96, 1.0);
// Pulled back from near-1.0-white: combined with the fake key light's own boost above
// 1.0 and any emission, this was crossing the environment's glow_hdr_threshold (1.6 in
// Environment_DomeIntro.tres) and bloomed hard right where the rim/cracks peak together.
uniform vec4 crack_color : hint_color = vec4(0.78, 0.89, 0.98, 1.0);
uniform bool low_end_mobile = false;
uniform float ice_height_world = 0.0;
// World-space distance above the ice line over which the freeze front fades in.
uniform float freeze_band_height : hint_range(0.1, 8.0) = 3.0;
uniform float crack_density : hint_range(0.05, 2.0) = 0.35;
uniform float emission_strength : hint_range(0.0, 1.0) = 0.02;
// Bright rim right at the freeze front, like a waterline — the main visibility cue.
uniform float rim_width : hint_range(0.0, 1.0) = 0.32;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.85;
// Evita que el next_pass compita por exactamente el mismo depth que metales y shaders
// complejos. Es suficientemente pequeño para no cambiar la silueta del prop.
uniform float surface_offset : hint_range(0.0, 0.01) = 0.002;
// Alpha-tested (opaque queue), not alpha-blended: this pass sits on the same geometry as
// dozens of other props near the ice line, several already blended (the ice surface
// itself). Blending it too would put it in the sorted-transparency queue, competing for
// draw order with all of those every frame — sort order isn't stable frame to frame in
// that queue, which read as the surface flickering. frost_decal.shader (the old decal
// system this replaces) hit the same issue and fixed it the same way.
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.4;
// Optional cutout mask, copied from a wrapped grate/rail material's own texture: without
// this, wrapping a flat quad that fakes a "bars" look via texture alpha (steel grating,
// railings) would draw solid ice across the whole quad, filling in the gaps the texture
// normally hides. When enabled, this pass only shows up where that same texture says the
// base material is solid too — see IceObjectFreezer._wrap_cutout_material().
uniform bool use_cutout = false;
uniform sampler2D cutout_texture : hint_albedo;
uniform float cutout_threshold : hint_range(0.0, 1.0) = 0.0;

// --- Camera/player occlusion cone (mirrors shaders/prop_dither_occlusion.gdshader) ---
// This overlay's next_pass sits on top of props that PropDitherManager already fades
// out with its own discard when they're between the camera and the player. If this
// pass ignored that, the base mesh would vanish while a solid sheet of ice from this
// pass kept drawing — a chunk of ice floating in the air where the wall used to be.
// IceObjectFreezer registers the shared instance of this material with
// PropDitherManager, so these uniforms get the same per-frame values as every other
// dithered prop; replicating the exact discard here keeps the two passes in lockstep
// pixel-for-pixel (same FRAGCOORD, same noise, same threshold).
uniform vec3 player_pos;
uniform vec3 camera_pos;
uniform float hole_radius = 0.5;
uniform float is_active = 0.0;
uniform float edge_fade : hint_range(0.1, 3.0) = 1.0;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.3;
uniform float transparency_max : hint_range(0.0, 1.0) = 0.95;
uniform float floor_protect_radius : hint_range(0.5, 5.0) = 1.0;
uniform bool stable_mobile_dither = false;

varying vec3 world_position;
varying vec3 world_normal;

float ice_octave(vec2 p) {
	float n = sin(dot(p, vec2(0.98, 0.17)) * 3.1);
	n += sin(dot(p, vec2(-0.65, 0.76)) * 4.7);
	n += sin(dot(p, vec2(0.34, -0.94)) * 2.3);
	return n / 3.0;
}

// Interleaved gradient noise — same as prop_dither_occlusion.gdshader.
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// Same fixed 4x4 Bayer matrix as prop_dither_occlusion.gdshader (avoids IGN's diagonal
// precision bands at large FRAGCOORD values on GLES2/mediump Android drivers).
float bayer4(vec2 p) {
	float x = mod(floor(p.x), 4.0);
	float y = mod(floor(p.y), 4.0);
	if (y < 1.0) return (x < 1.0 ? 0.0 : (x < 2.0 ? 8.0 : (x < 3.0 ? 2.0 : 10.0))) / 16.0;
	if (y < 2.0) return (x < 1.0 ? 12.0 : (x < 2.0 ? 4.0 : (x < 3.0 ? 14.0 : 6.0))) / 16.0;
	if (y < 3.0) return (x < 1.0 ? 3.0 : (x < 2.0 ? 11.0 : (x < 3.0 ? 1.0 : 9.0))) / 16.0;
	return (x < 1.0 ? 15.0 : (x < 2.0 ? 7.0 : (x < 3.0 ? 13.0 : 5.0))) / 16.0;
}

void vertex() {
	float stable_offset = surface_offset;
	if (low_end_mobile) {
		// La precisión del depth buffer cae con la distancia: un offset fijo que funciona
		// cerca vuelve a compartir el mismo Z en la pared opuesta del domo.
		vec3 source_world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
		stable_offset += clamp(distance(source_world, CAMERA_POSITION_WORLD) * 0.00032, 0.0, 0.016);
	}
	VERTEX += NORMAL * stable_offset;
	world_position = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((WORLD_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (is_active > 0.5) {
		vec3 cam_to_player = player_pos - camera_pos;
		float dist_cam_player = length(cam_to_player);
		vec3 dir_cam_player = cam_to_player / dist_cam_player;
		vec3 cam_to_frag = world_position - camera_pos;
		float t = dot(cam_to_frag, dir_cam_player);
		if (t > 0.1 && t < dist_cam_player) {
			vec3 projection = camera_pos + dir_cam_player * t;
			float dist_radial = distance(world_position, projection);
			float taper = 1.0 - smoothstep(dist_cam_player - 1.5, dist_cam_player, t);
			float cylinder_radius = hole_radius * edge_fade * taper;
			if (dist_radial < cylinder_radius && cylinder_radius > 0.01) {
				float horizontal_dist = length(world_position.xz - player_pos.xz);
				bool near_h = horizontal_dist < floor_protect_radius;
				bool floor_under = world_normal.y > 0.5 && camera_pos.y > world_position.y && near_h && world_position.y < (player_pos.y - 0.5);
				bool ceiling_above = world_normal.y < -0.5 && camera_pos.y < world_position.y && near_h && world_position.y > (player_pos.y + 2.0);
				if (!floor_under && !ceiling_above) {
					float depth_in_cone = 1.0 - (dist_radial / cylinder_radius);
					float dither_transparency = mix(transparency_min, transparency_max, depth_in_cone);
					float dither_threshold = stable_mobile_dither ? bayer4(FRAGCOORD.xy) : ign(FRAGCOORD.xy);
					if (dither_threshold < dither_transparency) {
						discard;
					}
				}
			}
		}
	}

	if (use_cutout && texture(cutout_texture, UV).a < cutout_threshold) {
		discard;
	}

	// Above the freeze front: nothing to draw. Keeps this pass free everywhere the ice
	// hasn't reached yet, which is most of the level most of the time.
	float depth_below = ice_height_world - world_position.y;
	if (depth_below < -freeze_band_height) {
		discard;
	}
	// Steeper than a linear ramp: reads as "frozen, with a short transition" instead of
	// a long hazy gradient, which is what made the first pass feel too subtle.
	float freeze_band = clamp(depth_below / freeze_band_height + 1.0, 0.0, 1.0);
	freeze_band = pow(freeze_band, 0.6);

	vec2 p = world_position.xz * crack_density + world_position.y * crack_density * 0.3;
	float broad = ice_octave(p) * 0.5 + 0.5;
	float fine = broad;
	if (!low_end_mobile) {
		fine = ice_octave(p * 2.3 + vec2(11.0, -4.0)) * 0.5 + 0.5;
	}
	float crack_mask = smoothstep(0.62, 0.85, broad * 0.55 + fine * 0.45);
	// Only thins coverage in a few spots instead of holding half the surface at 50%:
	// the old mix(0.5, 1.0, ...) floor was a big part of why this read as too faint.
	float frost_patch = smoothstep(0.05, 0.55, broad);

	// Bright waterline right at the freeze front — the actual "oh, that's frozen" cue.
	float rim = 1.0 - abs(freeze_band - (1.0 - rim_width)) / max(rim_width, 0.001);
	rim = clamp(rim, 0.0, 1.0) * step(0.02, freeze_band) * (1.0 - step(0.999, freeze_band));
	rim *= rim_strength;

	// Disolución anclada al mundo. FRAGCOORD hacía que el patrón cambiara al mover la
	// cámara sobre superficies curvas o animadas (IrisDoor/criopods), leyendo como flicker.
	// La oclusión cámara-jugador de arriba sí conserva su dither de pantalla intencional.
	float dither_noise = broad * 0.58 + fine * 0.42;
	float fog_visibility = smoothstep(0.0, 0.7, freeze_band);
	bool fogged_out = dither_noise > fog_visibility && rim < 0.35;

	vec3 frozen_tint = mix(frost_color.rgb, crack_color.rgb, clamp(crack_mask * 0.5 + rim * 0.85, 0.0, 1.0));
	// Solid almost immediately once past the discard cutoff, instead of ramping up with
	// freeze_band: multiplying by freeze_band here meant coverage didn't cross
	// alpha_scissor_threshold until ~40% into the band, so the first chunk of the "frozen"
	// zone silently drew nothing at all — read as the effect starting late/being too subtle.
	float coverage = mix(0.6, 1.0, freeze_band) * mix(0.92, 1.0, frost_patch);
	if (fogged_out) {
		coverage = 0.0;
	}

	// Fixed fake key light (fixed direction, not the scene's real lights): unshaded has no
	// light interaction at all, so without this the surface would be flat-shaded with zero
	// depth cue. This is baked math, not a real Light — same result at every camera/light
	// angle, which is the point.
	vec3 fake_light_dir = normalize(vec3(0.4, 0.8, 0.3));
	float fake_diffuse = dot(world_normal, fake_light_dir) * 0.5 + 0.5;
	// Capped at 1.0, not 1.15: pushing albedo above 1.0 is exactly what was tipping the
	// brightest pixels (rim + crack_color, already near-white) over glow_hdr_threshold.
	vec3 shaded_tint = frozen_tint * mix(0.65, 1.0, fake_diffuse);

	ALBEDO = shaded_tint;
	EMISSION = frozen_tint * (crack_mask * 0.6 + rim) * emission_strength * freeze_band;
	// Alpha-tested, not blended (see alpha_scissor_threshold above): below the threshold
	// this pixel is skipped entirely and the base pass shows through untouched, at/above
	// it this pixel draws fully opaque. No partial blend, so no transparency-sort flicker.
	ALPHA = clamp(coverage + rim * 0.5, 0.0, 1.0);
	ALPHA_SCISSOR = alpha_scissor_threshold;
}
