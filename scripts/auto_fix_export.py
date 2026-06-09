#!/usr/bin/env python3
import subprocess
import re
import os
import sys

MAX_ITERATIONS = 5
BUILD_DIR = "build"
EXECUTABLE = f"{BUILD_DIR}/odisea.x86_64"
LOG_FILE = "/tmp/godot_run.log"
PRESETS_FILE = "export_presets.cfg"

def run_export():
    print("🚀 Ejecutando exportación...")
    result = subprocess.run(["./scripts/ci_export.sh", "Linux/X11 x86_64", BUILD_DIR], capture_output=True, text=True)
    if result.returncode != 0:
        print("❌ Error en la exportación:")
        print(result.stderr[-500:]) # Last 500 chars of error
        return False
    return True

def run_and_capture():
    print("🏃 Ejecutando binario headless por 5 segundos...")
    if not os.path.exists(EXECUTABLE):
        print(f"❌ No se encontró el ejecutable: {EXECUTABLE}")
        return ""
    try:
        # Run headless, timeout after 5s (expected to timeout, we just want the boot log)
        result = subprocess.run(
            ["timeout", "5s", EXECUTABLE, "--headless"],
            capture_output=True, text=True, timeout=6
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        # We still get the output even if it times out
        pass
    return ""

def find_missing_files(log_output):
    patterns = [
        r"Cannot open file '(res://[^']+)'",
        r"Cannot load source code from file '(res://[^']+)'",
        r"referenced nonexistent resource at: (res://[^\s]+)",
        r"Failed loading resource: (res://[^\.]+\.(gd|tres|tscn|ttf|png|jpg))"
    ]
    missing = set()
    for pattern in patterns:
        matches = re.findall(pattern, log_output)
        # Handle tuple matches from groups
        for m in matches:
            if isinstance(m, tuple):
                missing.add(m[0])
            else:
                missing.add(m)
    
    # Clean up and validate
    valid_missing = []
    for f in missing:
        f = f.strip().strip("'").strip('"')
        if f.startswith("res://") and not f.endswith(".import"):
            valid_missing.append(f)
            
    return list(set(valid_missing))

def update_presets(missing_files):
    print(f"🔧 Añadiendo {len(missing_files)} recursos faltantes a include_filter...")
    with open(PRESETS_FILE, "r") as f:
        content = f.read()
    
    preset1_start = content.find("[preset.1]")
    preset1_end = content.find("[preset.2]", preset1_start)
    if preset1_start == -1 or preset1_end == -1:
        print("❌ No se pudo encontrar preset.1")
        return False
        
    preset1_block = content[preset1_start:preset1_end]
    
    match = re.search(r'(include_filter=")([^"]*)(")', preset1_block)
    if match:
        current_includes = match.group(2)
        new_includes_list = [x.strip() for x in current_includes.split(",") if x.strip()]
        
        added_count = 0
        for f in missing_files:
            if f not in new_includes_list:
                new_includes_list.append(f)
                added_count += 1
        
        if added_count == 0:
            print("⚠️ Los archivos ya estaban en include_filter. El problema puede ser otro.")
            
        new_includes_str = ", ".join(new_includes_list)
        new_preset1_block = preset1_block.replace(match.group(0), f'include_filter="{new_includes_str}"')
        
        content = content[:preset1_start] + new_preset1_block + content[preset1_end:]
        
        with open(PRESETS_FILE, "w") as f:
            f.write(content)
        print(f"✅ export_presets.cfg actualizado (+{added_count} archivos).")
        return True
    return False

def main():
    print("🔄 Iniciando ciclo de exportación y prueba automática...")
    for i in range(1, MAX_ITERATIONS + 1):
        print(f"\n--- Iteración {i}/{MAX_ITERATIONS} ---")
        if not run_export():
            sys.exit(1)
        
        log_output = run_and_capture()
        with open(LOG_FILE, "w") as f:
            f.write(log_output)
            
        missing = find_missing_files(log_output)

        if not missing:
            print("🎉 ¡Éxito! El juego arranca sin errores de recursos faltantes.")
            pck_path = f"{BUILD_DIR}/odisea.pck"
            if os.path.exists(pck_path):
                pck_size = os.path.getsize(pck_path) / (1024 * 1024)
                print(f"📦 Tamaño final del .pck: {pck_size:.2f} MB")
            sys.exit(0)
        else:
            print(f"⚠️ Se encontraron {len(missing)} recursos faltantes:")
            for m in missing[:5]:
                print(f"   - {m}")
            if len(missing) > 5:
                print(f"   ... y {len(missing) - 5} más.")
            
            if i == MAX_ITERATIONS:
                print("❌ Se alcanzó el máximo de iteraciones. Revisa el log en /tmp/godot_run.log")
                sys.exit(1)
            
            update_presets(missing)

if __name__ == "__main__":
    main()
