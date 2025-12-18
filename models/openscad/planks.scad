//////////////////////////////////////////
// ESPIRAL CON PLANCHAS ROTABLES
//////////////////////////////////////////

// -------- PARÁMETROS --------
r_min = 150;
r_max = 300;

height_total = 8000;
plate_height = 50;
plates = height_total / plate_height;

turns = 8;
angle_per_plate = 360 * turns / plates;

plate_width = 16;
plate_length = 40;
plate_thickness = 2;

// -------- FUNCIONES --------
function lerp(a,b,t) = a + (b-a)*t;

// -------- PLANCHA --------
module plate(angle, r, z, tilt=0) {

    translate([0,0,z])
        rotate([0,0,angle])
            translate([r,0,0])
                rotate([tilt,0,0])
                    cube(
                        [plate_thickness, plate_length, plate_width],
                        center=true
                    );
}

// -------- ENSAMBLE --------
for (i = [0 : plates-1]) {

    t = i / plates;
    r = lerp(r_min, r_max, t);
    z = i * plate_height;
    theta = i * angle_per_plate;

    // ---- MODO AXIAL ----
    // tilt = 0;

    // ---- MODO CENTRÍPETO ----
    tilt = 0;

    color("lightgray")
        plate(theta, r, z, tilt);
}
