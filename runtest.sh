#!/bin/sh

if [ -z "$GODOT_BIN" ]; then
    GODOT_BIN="godot3-bin"
fi

# Usar --no-window para tests headless (más rápido en CI)
# El issue https://github.com/godotengine/godot/issues/55379 ya no aplica con nuestros tests actuales
GODOT_OPTS="--no-window"

# Ejecutamos el runner guardando la salida en un log para analizarla y decidir el exit code
LOG_DIR="./reports"
LOG_FILE="$LOG_DIR/gdunit_runner.log"
mkdir -p "$LOG_DIR"

# Ejecuta Godot y guarda stdout+stderr en el log, preservando el exit code
$GODOT_BIN $GODOT_OPTS -s -d ./addons/gdUnit3/bin/GdUnitCmdTool.gd -v $* | tee "$LOG_FILE"
exit_code=${PIPESTATUS[0]}

# Volcar log a la salida para que aparezca en los logs de CI
cat "$LOG_FILE" || true

# Analizar la salida para detectar condiciones que deberían hacer fallar el job
if [ $exit_code -eq 0 ]; then
    # Si no se encontraron suites de tests, antes GdUnit devolvía 0; forzamos error
    if grep -q "No test suites found, abort test run!" "$LOG_FILE" || grep -q "No test suites found" "$LOG_FILE"; then
        echo "ERROR: No test suites found. Failing CI run."
        exit_code=2
    fi
    # Detectar errores de carga de recursos que indican proyecto mal configurado en CI
    if grep -qi "Failed to load resource" "$LOG_FILE" || grep -qi "referenced nonexistent resource" "$LOG_FILE" || grep -qi "Can't skip test" "$LOG_FILE"; then
        echo "ERROR: Resource loading errors detected in Godot logs. Failing CI run."
        exit_code=3
    fi
fi

# Copiar logs del propio GdUnit (si existe) - mantener compatibilidad
$GODOT_BIN --no-window --quiet -s -d ./addons/gdUnit3/bin/GdUnitCopyLog.gd $* > /dev/null

exit $exit_code
