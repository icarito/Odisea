#!/usr/bin/env python3
import subprocess
import re
import os
import sys

MAX_ITERATIONS = 6
BUILD_DIR = "build/linux_auto"
EXECUTABLE = f"{BUILD_DIR}/odisea.x86_64"
PRESETS_FILE = "export_presets.cfg"

BASE_SCENES = [
    "res://core_v2/bootstrap/Boot.tscn",
    "res://scenes/Menu.tscn",
    "res://core_v2/levels/interiors/Dome_Crio.tscn",
    "res://core_v2/levels/OdiseaExterior.tscn",
    "res://core_v2/components/ScaffoldOrbit.tscn"
]

BASE_INCLUDE = "*.ttf, *.oys, *.shader, *.gdshader, *.anim, assets/themes/*.tres, core_v2/ghost/*.tscn, core_v2/levels/shader_cache/*.tscn, textures/kenney_prototype_textures/*"
BASE_EXCLUDE = "agents/*, dashboard/*, android/*, .venv/*, .mono/*, ports/*, reports/*, test_output/*, docs/*, core_v2/tests/*, tests/*, addons/*, models/backflip.glb, models/sde_1.glb, models/boy_Rigging_Fwd_lambert4.material, assets/flipbook_particles/*, assets/FX/particle_system_effects_Godot3/*, assets/DisplayCase_2/*, assets/music/*, assets/hdris/*"

def update_preset(missing_files):
    with open(PRESETS_FILE, "r") as f:
        content = f.read()
    
    preset1_start = content.find("[preset.1]")
    preset1_end = content.find("[preset.1.options]", preset1_start)
    if preset1_start == -1 or preset1_end == -1:
        print("❌ No se pudo encontrar preset.1")
        return False
        
    preset1_block = content[preset1_start:preset1_end]
    
    scenes_str = ", ".join([f'"{s}"' for s in BASE_SCENES])
    preset1_block = re.sub(r'export_files=PoolStringArray\(.*?\)', f'export_files=PoolStringArray( {scenes_str} )', preset1_block, flags=re.DOTALL)
    
    current_include_match = re.search(r'include_filter="([^"]*)"', preset1_block)
    if current_include_match:
        current_include = current_include_match.group(1)
        includes = [x.strip() for x in current_include.split(",") if x.strip()]
        
        for f in missing_files:
            f = f.strip().strip("'").strip('"')
            if f not in includes:
                dir_name = os.path.dirname(f).replace("res://", "")
                ext = os.path.splitext(f)[1]
                if dir_name and ext:
                    glob_pattern = f"{dir_name}/*{ext}"
                elif ext:
                    glob_pattern = f"*{ext}"
                else:
                    glob_pattern = f
                    
                if glob_pattern not in includes:
                    includes.append(glob_pattern)
        
        new_include = ", ".join(includes)
        preset1_block = re.sub(r'include_filter="[^"]*"', f'include_filter="{new_include}"', preset1_block)

    preset1_block = re.sub(r'exclude_filter="[^"]*"', f'exclude_filter="{BASE_EXCLUDE}"', preset1_block)
    preset1_block = re.sub(r'export_filter="[^"]*"', 'export_filter="scenes"', preset1_block)
    preset1_block = re.sub(r'export_path="[^"]*"', f'export_path="{BUILD_DIR}/odisea.x86_64"', preset1_block)
    
    content = content[:preset1_start] + preset1_block + content[preset1_end:]
    
    with open(PRESETS_FILE, "w") as f:
        f.write(content)
    return True

def run_export():
    print("🚀 Ejecutando exportación...")
    os.makedirs(BUILD_DIR, exist_ok=True)
    result = subprocess.run(["./scripts/ci_export.sh", "Linux/X11 x86_64", BUILD_DIR], capture_output=True, text=True)
    if result.returncode != 0:
        print("❌ Error en la exportación:")
        print(result.stderr[-1000:])
        return False
    return True

def run_and_capture():
    print("🏃 Ejecutando binario headless por 5 segundos...")
    if not os.path.exists(EXECUTABLE):
        print(f"❌ No se encontró el ejecutable: {EXECUTABLE}")
        return ""
    try:
        result = subprocess.run(
            ["timeout", "5s", EXECUTABLE, "--headless"],
            capture_output=True, text=True, timeout=6
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        pass
    return ""

def find_missing_files(log_output):
    patterns = [
        r"Cannot open file '(res://[^']+)'",
        r"Cannot load source code from file '(res://[^']+)'",
        r"referenced nonexistent resource at: (res://[^\s]+)",
        r"Failed loading resource: (res://[^\.]+\.(gd|tres|tscn|ttf|png|jpg|shader|gdshader|oys|anim|mp3|ogg|wav))"
    ]
    missing = set()
    for pattern in patterns:
        matches = re.findall(pattern, log_output)
        for m in matches:
            if isinstance(m, tuple):
                missing.add(m[0])
            else:
                missing.add(m)
    
    valid_missing = []
    for f in missing:
        f = f.strip().strip("'").strip('"')
        if f.startswith("res://") and not f.endswith(".import") and not f.endswith(".remap"):
            valid_missing.append(f)
            
    return list(set(valid_missing))

def main():
    print("🔄 Iniciando ciclo de exportación y prueba automática...")
    update_preset([])
    
    for i in range(1, MAX_ITERATIONS + 1):
        print(f"\n--- Iteración {i}/{MAX_ITERATIONS} ---")
        if not run_export():
            sys.exit(1)
        
        log_output = run_and_capture()
        missing = find_missing_files(log_output)

        if not missing:
            print("🎉 ¡Éxito! El juego arranca sin errores de recursos faltantes.")
            pck_path = f"{BUILD_DIR}/odisea.pck"
            if os.path.exists(pck_path):
                pck_size = os.path.getsize(pck_path) / (1024 * 1024)
                print(f"📦 Tamaño final del .pck: {pck_size:.2f} MB")
            
            # Show final include filter
            with open(PRESETS_FILE, "r") as f:
                content = f.read()
            match = re.search(r'include_filter="([^"]*)"', content[content.find("[preset.1]"):content.find("[preset.1.options]")])
            if match:
                print(f"\n✅ include_filter final:\n{match.group(1)}")
            sys.exit(0)
        else:
            print(f"⚠️ Se encontraron {len(missing)} recursos faltantes:")
            for m in missing[:15]:
                print(f"   - {m}")
            if len(missing) > 15:
                print(f"   ... y {len(missing) - 15} más.")
            
            if i == MAX_ITERATIONS:
                print("❌ Se alcanzó el máximo de iteraciones. Revisa el log.")
                with open("/tmp/godot_auto_fix.log", "w") as f:
                    f.write(log_output)
                print("Log completo guardado en /tmp/godot_auto_fix.log")
                sys.exit(1)
            
            update_preset(missing)

if __name__ == "__main__":
    main()
