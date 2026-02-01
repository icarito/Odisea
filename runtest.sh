#!/bin/bash

# runtest.sh - Ejecuta tests de GdUnit3 para Odisea
# Uso:
#   ./runtest.sh -a ./core_v2/tests/           # Ejecutar todos los tests (headless)
#   ./runtest.sh --show -a ./core_v2/tests/    # Con ventana visible
#   ./runtest.sh --oys test_salto_vertical     # Ejecutar test OYS específico
#
# Opciones:
#   --show    Mostrar ventana de Godot (por defecto es headless)
#   --oys     Ejecutar un test OYS específico por nombre
#
# NOTA PARA AGENTES IA:
#   El output siempre se guarda en ./reports/gdunit_runner.log
#   Si no ves el output del terminal, lee ese archivo:
#     cat ./reports/gdunit_runner.log | tail -100
#   O para ver el resumen:
#     grep -E "(PASSED|FAILED|ERROR|Total|Exit code)" ./reports/gdunit_runner.log

if [ -z "$GODOT_BIN" ]; then
    GODOT_BIN="godot3-bin"
fi

# Por defecto, ejecutar en modo headless (más rápido)
HEADLESS="--no-window"

# Procesar --show antes que otros argumentos
if [ "$1" = "--show" ]; then
    HEADLESS=""
    shift
fi

# Configuración de logging - SIEMPRE guardar output
LOG_DIR="./reports"
LOG_FILE="$LOG_DIR/gdunit_runner.log"
mkdir -p "$LOG_DIR"

# Limpiar OYS_FILTER de ejecuciones anteriores
unset OYS_FILTER

# Función para imprimir tablita de resumen
print_summary_table() {
    echo ""
    echo "📊 RESUMEN DE EJECUCIÓN:"
    echo "| Test Scenary                                            | Status   | Time      |"
    echo "|:--------------------------------------------------------|:---------|:----------|"

    # Extraer tests individuales del log
    # Formato: Run Test: path > method [details] :STATUS TIME
    grep -a "Run Test:.*:" "$LOG_FILE" | sed -E 's/\x1b\[[0-9;]*m//g' | while read -r line; do
        # Extraer nombre del test (lo que está entre [] o el método)
        if [[ "$line" =~ \[(.*)\] ]]; then
            tname="${BASH_REMATCH[1]}"
            tname=$(basename "$tname")
        else
            tname=$(echo "$line" | sed -E 's/.* > ([^ ]+).*/\1/')
        fi

        # Extraer status y tiempo
        status=$(echo "$line" | sed -E 's/.*:(PASSED|FAILED|ERROR|STARTED).*/\1/')
        # Solo procesar PASSED/FAILED/ERROR (ignorar STARTED si quedó al final)
        if [[ "$status" == "STARTED" ]]; then continue; fi

        time=$(echo "$line" | sed -E 's/.*:(PASSED|FAILED|ERROR) (.*)/\2/')

        # Formatear Status con iconos
        case "$status" in
            PASSED) s_icon="✅ PASSED" ;;
            FAILED) s_icon="❌ FAILED" ;;
            ERROR)  s_icon="💥 ERROR " ;;
            *)      s_icon="❓ $status" ;;
        esac

        printf "| %-55s | %-8s | %-9s |\n" "$tname" "$s_icon" "$time"
    done
}

# Verificar si es un test OYS específico
if [ "$1" = "--oys" ]; then
    OYS_NAME="$2"
    shift 2

    if [ -z "$OYS_NAME" ]; then
        echo "ERROR: Especifica el nombre del test OYS (sin extensión)"
        echo "Uso: ./runtest.sh --oys test_salto_vertical"
        echo ""
        echo "Tests OYS disponibles:"
        ls -1 ./core_v2/tests/*.oys 2>/dev/null | sed 's|.*/||; s|\.oys$||'
        exit 1
    fi

    # Buscar el archivo OYS
    OYS_FILE="./core_v2/tests/${OYS_NAME}.oys"
    if [ ! -f "$OYS_FILE" ]; then
        echo "ERROR: No se encontró $OYS_FILE"
        echo ""
        echo "Tests OYS disponibles:"
        ls -1 ./core_v2/tests/*.oys 2>/dev/null | sed 's|.*/||; s|\.oys$||'
        exit 1
    fi

    echo "▶️ Ejecutando test OYS: $OYS_NAME ${HEADLESS:+(headless)}"
    echo "📋 Output guardado en: $LOG_FILE"
    echo "---"

    # Usar variable de entorno OYS_FILTER para filtrar el test
    export OYS_FILTER="${OYS_NAME}"
    $GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd -v \
        -a "./core_v2/tests/test_determinism_v2.gd" "$@" 2>&1 | tee "$LOG_FILE"
    exit_code=${PIPESTATUS[0]}

    echo "---"
    print_summary_table
    echo ""
    echo "📋 Output completo en: $LOG_FILE"
    if [ $exit_code -eq 0 ]; then
        echo "✅ Test OYS '$OYS_NAME' pasó"
    else
        echo "❌ Test OYS '$OYS_NAME' falló con código: $exit_code"
    fi
    exit $exit_code
fi

echo "🧪 Ejecutando tests GdUnit3 ${HEADLESS:+(headless)}..."
echo "📋 Output guardado en: $LOG_FILE"
echo "Comando: $GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd -v $*"
echo "---"

# Ejecuta Godot con unbuffered output para ver resultados en tiempo real
$GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd -v "$@" 2>&1 | tee "$LOG_FILE"
exit_code=${PIPESTATUS[0]}

echo "---"
echo "📋 Log guardado en: $LOG_FILE"

# --- Generar Tablita de Resumen ---
print_summary_table

# Analizar la salida para detectar condiciones que deberían hacer fallar el job
if [ $exit_code -eq 0 ]; then
    # Si no se encontraron suites de tests, antes GdUnit devolvía 0; forzamos error
    if grep -q "No test suites found, abort test run!" "$LOG_FILE" || grep -q "No test suites found" "$LOG_FILE"; then
        echo "❌ ERROR: No test suites found. Failing CI run."
        exit_code=2
    fi
    # Detectar errores de carga de recursos que indican proyecto mal configurado en CI
    if grep -qi "Failed to load resource" "$LOG_FILE" || grep -qi "referenced nonexistent resource" "$LOG_FILE"; then
        echo "❌ ERROR: Resource loading errors detected in Godot logs. Failing CI run."
        exit_code=3
    fi
    # Detectar SCRIPT ERROR que indica bugs en el código
    if grep -q "SCRIPT ERROR:" "$LOG_FILE"; then
        echo "❌ ERROR: Script errors detected. Failing CI run."
        grep "SCRIPT ERROR:" "$LOG_FILE" | head -5
        exit_code=4
    fi
fi

if [ $exit_code -eq 0 ]; then
    echo "✅ Todos los tests pasaron"
else
    echo "❌ Tests fallaron con código: $exit_code"
fi

exit $exit_code
