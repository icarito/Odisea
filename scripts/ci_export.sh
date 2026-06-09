#!/bin/bash
# Script de exportación automatizada para CI
# Uso: ./scripts/ci_export.sh [preset_name] [output_dir]
# Ejemplo: ./scripts/ci_export.sh "Linux/X11 x86_64" build/linux

set -e

PRESET_NAME="${1:-Linux/X11 x86_64}"
OUTPUT_DIR="${2:-build}"
GODOT_BIN="${GODOT_BIN:-godot3-bin}"
PROJECT_PATH="${PROJECT_PATH:-.}"

echo "🚀 Iniciando exportación CI..."
echo "   Preset: $PRESET_NAME"
echo "   Directorio de salida: $OUTPUT_DIR"
echo "   Godot binary: $GODOT_BIN"

# Crear directorio de salida si no existe
mkdir -p "$OUTPUT_DIR"

# Determinar el nombre del archivo de salida según el preset
case "$PRESET_NAME" in
    *"Linux/X11 x86_64"*)
        OUTPUT_FILE="$OUTPUT_DIR/odisea.x86_64"
        ;;
    *"Linux/X11 ARM64"*)
        OUTPUT_FILE="$OUTPUT_DIR/odisea.arm64"
        ;;
    *"HTML5"*)
        OUTPUT_FILE="$OUTPUT_DIR/index.html"
        ;;
    *"Android"*)
        OUTPUT_FILE="$OUTPUT_DIR/odisea.apk"
        ;;
    *)
        OUTPUT_FILE="$OUTPUT_DIR/odisea_export"
        ;;
esac

echo "🧹 Limpiando caché de compilación de Godot (.godot/imported/)..."
rm -rf "$PROJECT_PATH/.godot/imported/"
rm -f "$PROJECT_PATH"/**/*.gdc 2>/dev/null || true

echo "🔄 Ejecutando paso de importación forzada (requerido en CI)..."
$GODOT_BIN --path "$PROJECT_PATH" --editor --quit --headless --no-window --audio-driver Dummy

if [ $? -ne 0 ]; then
    echo "⚠️ Advertencia: El paso de importación reportó errores. Revisa los logs de Godot arriba."
fi

echo "📦 Exportando a: $OUTPUT_FILE"

# Ejecutar Godot en modo headless para exportar
$GODOT_BIN --path "$PROJECT_PATH" --export "$PRESET_NAME" "$OUTPUT_FILE" --headless --no-window --audio-driver Dummy

if [ -f "$OUTPUT_FILE" ] || [ -d "$OUTPUT_DIR" ]; then
    echo "✅ Exportación completada exitosamente."
    ls -lh "$OUTPUT_DIR"
else
    echo "❌ Error: La exportación no generó los archivos esperados."
    exit 1
fi
