//////////////////////////////////////////
// ODISEA — MESH LOD COMBINADO
//////////////////////////////////////////
// LOD unificado para reemplazar cientos de MultiMesh plates.
// 
// Estructura:
//   - 4 espirales (0°, 90°, 180°, 270°) 
//   - Núcleo central con domo
//   - Domos en las posiciones del DomeRegistry
//
// Uso: abrir en OpenSCAD, elegir $fn para nivel de detalle.
//   $fn=12 → LOD0 (muy lejos, ~1-2K tris)
//   $fn=24 → LOD1 (medio, ~8-10K tris)
//   Exportar como STL y convertir a .glb para Godot.

// -------- DETALLE --------
$fn = 16; // 12=ultra low, 16=low, 24=medium

// -------- PARÁMETROS (matchean TerraceSpiral.gd + platforms.scad) --------
r_spiral = 200;         // radio del eje a las plates
height_total = 8000;    // altura total de la espiral
turns = 8;              // vueltas de cada espiral
plate_step = 40;        // distancia entre plates
plate_count = 200;      // plates por espiral
plate_size = 80;        // ancho de cada plate
plate_thickness = 2;    // grosor de plate

// Offsets angulares de las 4 espirales
spiral_offsets = [0, 90, 180, 270];

// -------- DOMO CENTRAL --------
dome_radius = 120;
dome_height = 4000;

// -------- DOMOS (posiciones del DomeRegistry) --------
// Formato: [spiral_index, plate_index]
domes = [
    [0, 1],   // dome_02 - Bahía de Ingeniería
    [0, 15],  // dome_01 - Laboratorio Biológico
    [2, 5],   // dome_03 - Criogenia
];

// -------- FUNCIONES --------
function lerp(a, b, t) = a + (b - a) * t;

// Posición de una plate en una espiral
function plate_angle(spiral_offset, plate_index) = 
    spiral_offset + plate_index * 360 * turns / plate_count;

function plate_z(plate_index) = 
    plate_index * plate_step;

function plate_xyz(spiral_offset, plate_index) = [
    r_spiral * cos(plate_angle(spiral_offset, plate_index)),
    r_spiral * sin(plate_angle(spiral_offset, plate_index)),
    plate_z(plate_index)
];

// -------- MÓDULOS --------

// Placa individual (plana, rectangular)
module single_plate(spiral_offset, plate_index) {
    pos = plate_xyz(spiral_offset, plate_index);
    ang = plate_angle(spiral_offset, plate_index);
    
    translate([pos[0], pos[1], pos[2]])
        rotate([0, 0, ang])
            rotate([0, -90, 0])  // centrífugo: cara interior hacia +Z
                translate([plate_size/2, 0, 0])
                    cube([plate_size, plate_size, plate_thickness], center=true);
}

// Espiral completa (todas las plates)
module spiral_path(spiral_offset) {
    for (i = [0 : 2 : plate_count - 1]) {  // cada 2da plate para LOD
        single_plate(spiral_offset, i);
    }
}

// Cilindro/rampa simplificada (versión ultra-LOD: un solo tubo helicoidal)
module spiral_ramp(spiral_offset, height_start, height_end) {
    steps = 40;
    step_h = (height_end - height_start) / steps;
    
    for (i = [0 : steps - 1]) {
        z0 = height_start + i * step_h;
        z1 = z0 + step_h;
        plate0 = floor(z0 / plate_step);
        plate1 = floor(z1 / plate_step);
        
        pos0 = plate_xyz(spiral_offset, plate0);
        pos1 = plate_xyz(spiral_offset, plate1);
        
        // Tubo entre plates consecutivas
        hull() {
            translate(pos0)
                rotate([0, 0, plate_angle(spiral_offset, plate0)])
                    rotate([0, -90, 0])
                        translate([plate_size/2, 0, 0])
                            cube([plate_size, plate_size, plate_thickness], center=true);
            translate(pos1)
                rotate([0, 0, plate_angle(spiral_offset, plate1)])
                    rotate([0, -90, 0])
                        translate([plate_size/2, 0, 0])
                            cube([plate_size, plate_size, plate_thickness], center=true);
        }
    }
}

// Domo individual (esfera achatada)
module dome_bump(pos) {
    translate(pos)
        translate([0, 0, 30])  // elevado sobre la plate
            scale([1, 1, 0.5])
                sphere(r = 40);
}

// Cilindro central con domo arriba
module central_core() {
    // Cilindro principal
    cylinder(r = dome_radius, h = dome_height, center = false);
    
    // Domo en la punta
    translate([0, 0, dome_height])
        scale([1, 1, 0.6])
            sphere(r = dome_radius);
    
    // Base ensanchada
    translate([0, 0, -200])
        cylinder(r1 = dome_radius * 1.5, r2 = dome_radius, h = 200);
}

// -------- ENSAMBLE --------

// Núcleo central
color("DarkSlateGray") central_core();

// 4 espirales como rampas continuas
for (offset = spiral_offsets) {
    color("DimGray") spiral_ramp(offset, 0, height_total);
}

// Domos en posiciones registradas
for (dome = domes) {
    pos = plate_xyz(spiral_offsets[dome[0]], dome[1]);
    color("SteelBlue") dome_bump(pos);
}

// Domos sintéticos cada ~20 plates en cada espiral para poblar
for (offset_idx = [0 : 3]) {
    for (pi = [0 : 20 : plate_count - 1]) {
        // Saltar los domos ya puestos
        is_explicit = false;
        for (dome = domes) {
            if (dome[0] == offset_idx && dome[1] == pi) {
                is_explicit = true;
            }
        }
        if (!is_explicit) {
            pos = plate_xyz(spiral_offsets[offset_idx], pi);
            color("SlateGray") dome_bump(pos);
        }
    }
}
