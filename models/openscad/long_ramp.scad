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

// -------- PARÁMETROS GEOMÉTRICOS --------
r_min = 150;
r_max = 300;

height_total = 8000;
plate_height = 50; // Distancia vertical entre centros de planchas

turns = 8; // más vueltas = menos pendiente en modo rampa

plate_length = 80;  // Dimensión a lo largo de la espiral
plate_depth = 80;   // Dimensión radial
plate_thickness = 2;

// -------- CÁLCULOS DERIVADOS --------
plates = floor(height_total / plate_height);
angle_per_plate = 360 * turns / plates;
// Ángulo de torsión para alinear los bordes de las planchas en la rampa.
// Es la mitad del ángulo entre planchas, para que cada una rote la mitad.
twist_angle = angle_per_plate / 2;

// -------- FUNCIONES --------
// Interpola linealmente entre a y b
function lerp(a, b, t) = a + (b - a) * t;

// Calcula el ángulo de la pendiente de la hélice en un radio 'r'
function helix_angle(r) = atan(height_total / (2 * PI * turns * r));

// -------- PLANCHA --------
module plank(angle, r, z, helix_tilt, twist) {
    translate([0,0,z])
        rotate([0,0,angle]) // 1. Mover a la posición angular en la espiral
            translate([r,0,0])
                // 2. Orientar la plancha según el modo de gravedad
                if (mode == 0) { // MODO AXIAL: Piso horizontal
                    // El piso es paralelo al plano XY. La normal es (0,0,1)
                    cube([plate_length, plate_depth, plate_thickness], center=true);
                } else { // MODO CENTRÍFUGO: Piso radial (rampa)
                    // La secuencia de rotación es crucial aquí:
                    // a. Poner el piso "vertical" para que su normal apunte hacia el eje Z.
                    rotate([0, 90, 0])
                    // b. Inclinar la plancha para que siga la pendiente de la hélice.
                    //    Se rota sobre el eje Y local (que ahora es el eje radial).
                    rotate([0, 0, helix_tilt])
                    // c. Aplicar la torsión para alinear los bordes con la curva.
                    //    Se rota sobre el eje Z local (que ahora es el eje "vertical" de la plancha).
                    rotate([0, 0, twist])
                        // El piso es radial. La normal apunta hacia el eje de rotación.
                        cube([plate_length, plate_depth, plate_thickness], center=true);
                }
}

// -------- ENSAMBLE --------
for (i = [0 : plates-1]) {
    t = i / (plates - 1);
    r = lerp(r_min, r_max, t);
    z = i * plate_height;
    theta = i * angle_per_plate;
    tilt = helix_angle(r); // Ángulo de inclinación local para la rampa

    color("lightgray")
        plank(theta, r, z, tilt, twist_angle);
}
