//////////////////////////////////////////
// ESPIRAL CON PLANCHAS ROTABLES (REFINADA)
//////////////////////////////////////////
//
// Este modelo representa una estructura en espiral que puede reconfigurarse
// en dos modos distintos según el vector de gravedad:
//
// 1. MODO AXIAL (mode=0): Gravedad lineal a lo largo del eje Z.
//    - Las planchas son terrazas horizontales discretas.
//    - La normal del piso es <0, 0, 1>.
//
// 2. MODO CENTRÍFUGO (mode=1): Gravedad radial desde el eje Z.
//    - Las planchas rotan para formar una rampa helicoidal continua.
//    - La normal del piso apunta hacia el eje Z.
//////////////////////////////////////////

// -------- PARÁMETROS DE CONTROL --------
mode = 1; // 0 = Axial (terrazas), 1 = Centrífugo (rampa)

// -------- CONTROLES DE ANIMACIÓN --------
// Si `animate` es true, la animación usará el valor global `$t`
// (OpenSCAD Animate: 0..1). Si es false, usa `anim_value` manual.
animate = false; // true para usar $t (Animate), false para usar anim_value
anim_value = 0;   // rango 0..1 cuando animate == false (0:Axial, 1:Centrífugo)
animation_easing = "smooth"; // "linear" | "smooth" | "inout"

// Funciones de easing simples
function ease_linear(x) = x;
function ease_smooth(x) = x*x*(3 - 2*x); // smoothstep
function ease_inout(x) = x < 0.5 ? 2*x*x : 1 - pow(-2*x + 2, 2)/2;
function ease(x) = animation_easing == "linear" ? ease_linear(x)
                    : (animation_easing == "inout" ? ease_inout(x) : ease_smooth(x));

// Valor de mezcla entre 0 (Axial) y 1 (Centrífugo)
blend_raw = animate ? $t : anim_value;
blend = ease(blend_raw);

// -------- INTERBLOQUEO (evitar colisiones) --------
// Ángulo (grados) de giro alrededor del eje local de la plancha.
// Se multiplica por `blend` para activarse en modo centrífugo.
interlock_angle_deg = 45; // ajustable
interlock = interlock_angle_deg * blend;

// -------- PARÁMETROS GEOMÉTRICOS --------
r_min = 150;
r_max = 300;

height_total = 8000;
plate_height = 50;

turns = 8; // más vueltas = menos pendiente en modo rampa

plate_length = 80;  // Dimensión a lo largo de la espiral
plate_depth = 80;   // Dimensión radial
plate_thickness = 2;

// -------- CÁLCULOS DERIVADOS --------
plates = floor(height_total / plate_height);
angle_per_plate = 360 * turns / plates;

// -------- FUNCIONES --------
function lerp(a,b,t) = a + (b-a)*t;

// -------- PLANCHA --------
module plank(angle, r, z) {
    // `blend` controla la interpolación entre los dos estados:
    // blend=0 -> axial (sin rotación local, la cara interior mira -X)
    // blend=1 -> centrífugo (queremos que la cara interior mire +Z)
    // Para lograrlo, rotaremos localmente alrededor de Y desde 0 hasta -90 grados,
    // de modo que el eje local X pase a apuntar hacia -Z (la cara interior queda hacia +Z).
    y_ang = -90 * blend;

    translate([0,0,z])
        rotate([0,0,angle]) // 1. Posicionar en la espiral
            translate([r,0,0])
                // Primero inclinamos la plancha para apuntar la cara interior hacia +Z
                // y luego aplicamos un pequeño giro alrededor del eje local Z (interlock)
                rotate([0, y_ang, 0])
                    rotate([0, 0, interlock])
                        cube([plate_length, plate_depth, plate_thickness], center=true);
}

// -------- ENSAMBLE --------
for (i = [0 : plates-1]) {
    u = i / (plates - 1);
    r = lerp(r_min, r_max, u);
    z = i * plate_height;
    theta = i * angle_per_plate;

    color("lightgray")
        plank(theta, r, z);
}
