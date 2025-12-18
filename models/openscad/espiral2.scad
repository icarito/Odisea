//////////////////////////////////////////
// DOBLE HÉLICE MODULAR – NAVE 8 KM
// 1 unidad = 1 metro
//////////////////////////////////////////

// -----------------
// PARÁMETROS GLOBALES
// -----------------
r_min = 15;
r_max = 30;

height_total = 800;
segment_height = 200;
segments = height_total / segment_height;

turns = 6;
angle_per_segment = 360 * turns / segments;

ramp_width = 16;
thickness = 2;
steps_per_segment = 30;

// -----------------
// FUNCIONES
// -----------------
function lerp(a,b,t) = a + (b-a)*t;

// -----------------
// SLICE DE RAMPA
// -----------------
module ramp_slice(r, angle, z) {
    translate([0,0,z])
        rotate([0,0,angle])
            translate([r,0,0])
                cube([thickness, ramp_width, thickness], center=true);
}

// -----------------
// HÉLICE SIMPLE
// -----------------
module helix_segment(z0, theta0, phase) {

    for (i = [0:steps_per_segment-1]) {

        t1 = i / steps_per_segment;
        t2 = (i+1) / steps_per_segment;

        global_t1 = (z0 + t1*segment_height) / height_total;
        global_t2 = (z0 + t2*segment_height) / height_total;

        r1 = lerp(r_min, r_max, global_t1);
        r2 = lerp(r_min, r_max, global_t2);

        z1 = z0 + t1 * segment_height;
        z2 = z0 + t2 * segment_height;

        a1 = theta0 + t1 * angle_per_segment + phase;
        a2 = theta0 + t2 * angle_per_segment + phase;

        hull() {
            ramp_slice(r1, a1, z1);
            ramp_slice(r2, a2, z2);
        }
    }
}

// -----------------
// SEGMENTO COMPLETO (DOBLE HÉLICE)
// -----------------
module segment(index) {

    z0 = index * segment_height;
    theta0 = index * angle_per_segment;

    // eje central (para debug / mecánica)
    color("silver")
        translate([0,0,z0 + segment_height/2])
            cylinder(h=segment_height, r=5, center=true);

    // hélice A
    color("lightgray")
        helix_segment(z0, theta0, 0);

    // hélice B (opuesta 180°)
    color("darkgray")
        helix_segment(z0, theta0, 180);
}

// -----------------
// ENSAMBLE TOTAL
// -----------------
union() {
    for (s = [0 : segments-1])
        segment(s);
}
