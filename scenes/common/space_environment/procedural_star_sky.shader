shader_type sky;

uniform float density : hint_range(0.0, 1.0, 0.001) = 0.2;
uniform float star_size : hint_range(0.0, 0.1, 0.001) = 0.01;
uniform vec3 star_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float twinkle_speed : hint_range(0.0, 10.0, 0.1) = 1.0;
uniform float twinkle_amount : hint_range(0.0, 1.0, 0.01) = 0.5;

// A simple hash function to generate pseudo-random numbers
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p = p * (p + 0.113);
    return fract(p.x * p.y * p.z);
}

// Function to generate a star pattern
float star(vec3 p, float size) {
    float d = length(p);
    float star_shape = smoothstep(size, size * 0.5, d);
    return star_shape;
}

void sky() {
    vec3 direction = normalize(EYEDIR); // Direction vector for the current pixel

    // Scale the direction to create a "grid" for star placement
    vec3 grid_uv = direction * 1000.0; // Adjust multiplier for more/fewer grid cells

    vec3 color = vec3(0.0, 0.0, 0.02); // Dark blue space background

    // Iterate over a small neighborhood of grid cells to ensure stars don't disappear at cell boundaries
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            for (int z = -1; z <= 1; z++) {
                vec3 current_cell = floor(grid_uv) + vec3(x, y, z);
                
                // Generate a random value for this cell
                float random_val = hash(current_cell);

                // If random_val is below density, place a star
                if (random_val < density) {
                    // Generate a consistent random offset within the cell for star position
                    vec3 star_pos_offset = vec3(hash(current_cell + vec3(1.0, 0.0, 0.0)),
                                                hash(current_cell + vec3(0.0, 1.0, 0.0)),
                                                hash(current_cell + vec3(0.0, 0.0, 1.0))) * 2.0 - 1.0; // -1 to 1 range

                    vec3 star_center = (current_cell + star_pos_offset) / 1000.0; // Convert back to world scale
                    star_center = normalize(star_center); // Ensure it's on the unit sphere

                    float dist_to_star = length(direction - star_center);
                    
                    // Randomize star size slightly
                    float current_star_size = star_size * (1.0 + hash(current_cell + vec3(2.0, 2.0, 2.0)) * 0.5);

                    float star_intensity = star(direction - star_center, current_star_size);

                    // Add twinkling effect
                    float twinkle = sin(TIME * twinkle_speed + random_val * 100.0) * 0.5 + 0.5;
                    star_intensity *= (1.0 - twinkle_amount) + (twinkle * twinkle_amount);

                    color += star_intensity * star_color;
                }
            }
        }
    }

    COLOR = color;
}
