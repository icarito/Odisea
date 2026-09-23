shader_type spatial;
render_mode blend_add, cull_disabled, depth_draw_never, unshaded;

// Cono volumetrico de la linterna de casco (HelmetFlashlight).
// Haz aditivo que se ve en el aire cuando el nivel esta a oscuras: no escribe
// profundidad, no recibe luz, y sobrevive a GLES3 desktop / web / moviles sin
// SCREEN_TEXTURE ni DEPTH_TEXTURE (aca se construye todo analiticamente).
//
// El cono es un CylinderMesh de altura 1.0 (base ancha en Y=-0.5, punta en
// Y=+0.5) escalado 5.5 en el eje, con la punta hacia el frente del jugador.

uniform vec3  beam_color = vec3(1.0, 0.96, 0.86);
uniform float beam_energy = 0.35;     // bajo: es aditivo, satura rapido
uniform float edge_softness = 2.2;
uniform float dust_amount = 0.25;     // 0 = sin motas
uniform float dust_speed = 0.35;

// 0.0 en la base (cerca de la lampara), 1.0 en la punta. Se interpola por el
// mesh, asi no dependemos del UV lateral (que en CylinderMesh solo llega a 0.5).
varying float v_axis;

void vertex() {
	// Centro del eje en Y=0 para un cilindro de altura 1.0.
	v_axis = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	// --- Desvanecimiento a lo largo del eje -------------------------------
	// Fuerte cerca de la lampara, tenue en la punta. El cuadrado expone la caida
	// sin cortar abruptamente.
	float axis = 1.0 - v_axis;
	axis *= axis;

	// --- Borde suave (fresnel invertido) ----------------------------------
	// facing = |N . V|: vale 1 donde la superficie mira a la camara (centro del
	// haz al mirarlo de frente) y cae a 0 en la silueta. abs() porque con
	// cull_disabled las caras traseras llegan con la normal invertida.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(clamp(facing, 0.0, 1.0), edge_softness);

	// Solo la parte visible del haz cuenta (la punta del cono queda fuera).
	float beam_mask = axis * smoothstep(0.0, 0.45, facing);

	// --- Motas de polvo dentro del haz ------------------------------------
	// Sin hash noise: combinacion de senos/cosenos de frecuencias no enteras con
	// domain warping, de modo que no se repita un patron obvio. Muy sutil.
	float dust = 0.0;
	if (dust_amount > 0.0) {
		float t = TIME * dust_speed;
		vec2 p = vec2(UV.x * 6.28318, v_axis * 2.0) + vec2(t * 0.35, t * 0.12);

		// Domain warp: deforma el espacio para romper la cuadricula de senos.
		float warp = sin(p.x * 1.3 + t * 0.7) + cos(p.y * 0.8 - t * 0.9);
		p += vec2(cos(warp * 1.7) * 0.6, sin(warp * 1.3) * 0.4);

		float mote = sin(p.x * 2.3 + t * 1.1) * cos(p.y * 1.9 - t * 1.4);
		mote += 0.5 * sin(p.x * 5.1 - t * 1.3) * cos(p.y * 4.3 + t * 0.8);
		mote += 0.25 * cos(p.x * 8.7 + t * 0.5) * sin(p.y * 6.2 - t * 1.9);
		mote *= 0.57; // reescala la suma a ~[-1, 1]

		// Umbral superior: solo quedan los picos (manchas suaves y dispersas).
		mote = smoothstep(0.25, 0.85, mote);
		dust = mote * dust_amount * beam_mask * 0.6;
	}

	ALBEDO = beam_color;
	ALPHA = clamp(axis * edge * beam_energy + dust, 0.0, 1.0);
}