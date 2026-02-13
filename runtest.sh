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
#   --nodet   Saltar tests de determinism
#   --debug   Mostrar output completo sin filtrar logs de debug
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
DEBUG_OUTPUT=0

# Procesar --show antes que otros argumentos
if [ "$1" = "--show" ]; then
    HEADLESS=""
    shift
fi

# Configuración de logging - Generar nombre único para soporte concurrente
LOG_DIR="./reports"
LOG_FILE="$LOG_DIR/gdunit_$(date +%Y%m%d_%H%M%S)_$$.log"
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

strip_ansi() {
    sed -E 's/\x1b\[[0-9;]*m//g'
}

filter_noisy_output() {
    # Mantiene limpio el output por defecto, pero conserva logs completos en $LOG_FILE.
    # Filtra cualquier línea de log con prefijo estilo [Algo].
    sed -E \
        -e '/^[[:space:]]*\[[^]]+\]/d' \
        -e '/^[[:space:]]*$/d' \
        -e '/^DEBUG BASEZONE:/d' \
        -e '/VisualServer attempted to free a NULL RID/d'
}

run_and_capture() {
    local cmd=("$@")
    if [ $DEBUG_OUTPUT -eq 1 ]; then
        "${cmd[@]}" 2>&1 | tee "$LOG_FILE"
    else
        "${cmd[@]}" 2>&1 | tee "$LOG_FILE" | filter_noisy_output
    fi
    return ${PIPESTATUS[0]}
}

print_failed_asserts() {
    local cleaned
    cleaned=$(mktemp)
    strip_ansi < "$LOG_FILE" > "$cleaned"

    mapfile -t failed_asserts < <(
        grep -E "❌ ASSERT FAILED:|\[OYS ASSERT\] FAILED:|ASSERT_SIGNAL FAILED|OYS ASSERT FAILED|Assertion failed \(" "$cleaned" \
        | awk '!seen[$0]++'
    )

    if [ ${#failed_asserts[@]} -gt 0 ]; then
        echo ""
        echo "🚨 ASSERTS FALLIDOS DETECTADOS:"
        local i=1
        for line in "${failed_asserts[@]}"; do
            printf "%d. %s\n" "$i" "$line"
            i=$((i + 1))
        done
    fi

    rm -f "$cleaned"
}

# Función para validar logs y detectar errores silenciosos (como SCRIPT ERROR)
validate_logs() {
    local code=$1
    if [ $code -eq 0 ]; then
        # Si no se encontraron suites de tests, antes GdUnit devolvía 0; forzamos error
        if grep -q "No test suites found, abort test run!" "$LOG_FILE" || grep -q "No test suites found" "$LOG_FILE"; then
            echo "❌ ERROR: No test suites found. Failing run."
            code=2
        fi
        # Detectar errores de carga de recursos que indican proyecto mal configurado
        if grep -qi "Failed to load resource" "$LOG_FILE" || grep -qi "referenced nonexistent resource" "$LOG_FILE"; then
            echo "❌ ERROR: Resource loading errors detected in Godot logs. Failing run."
            code=3
        fi
        # Detectar SCRIPT ERROR que indica bugs en el código
        if grep -q "SCRIPT ERROR:" "$LOG_FILE"; then
            echo "❌ ERROR: Script errors detected. Failing run."
            grep -A 5 "SCRIPT ERROR:" "$LOG_FILE" | head -n 20
            code=4
        fi
    fi
    return $code
}

# Parse arguments
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show)
            HEADLESS=""
            shift
            ;;
        --nodet)
            echo "Skipping JSON replays (--nodet flag detected)"
            export OYS_NODET=1
            shift
            ;;
        --debug)
            DEBUG_OUTPUT=1
            shift
            ;;
        --oys)
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
            run_and_capture $GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd \
                -a "./core_v2/tests/test_determinism_v2.gd" "$@"
            exit_code=$?
            
            echo "---"
            print_summary_table
            
            # Validar logs para detectar SCRIPT ERROR que GdUnit no ve como fail
            validate_logs $exit_code
            exit_code=$?
            print_failed_asserts

            echo ""
            echo "📋 Output completo en: $LOG_FILE"
            if [ $exit_code -eq 0 ]; then
                echo "✅ Test OYS '$OYS_NAME' pasó"
            else
                echo "❌ Test OYS '$OYS_NAME' falló con código: $exit_code"
            fi
            exit $exit_code
            ;;
        *)
            # Collect other arguments
            ARGS+=("$1")
            shift
            ;;
    esac
done

# If no arguments provided, default to all tests
if [ ${#ARGS[@]} -eq 0 ]; then
    ARGS=("-a" "./core_v2/tests/")
fi

echo "🧪 Ejecutando tests GdUnit3 ${HEADLESS:+(headless)}..."
echo "📋 Output guardado en: $LOG_FILE"
echo "Comando: $GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd ${ARGS[*]}"
if [ $DEBUG_OUTPUT -eq 0 ]; then
    echo "Modo salida: limpio (usa --debug para ver logs completos)"
else
    echo "Modo salida: debug completo"
fi
echo "---"

# Ejecuta Godot con output en tiempo real (filtrado o completo según modo)
run_and_capture $GODOT_BIN $HEADLESS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd "${ARGS[@]}"
exit_code=$?

echo "---"
echo "📋 Log guardado en: $LOG_FILE"

# --- Generar Tablita de Resumen ---
print_summary_table

# Analizar la salida para detectar condiciones que deberían hacer fallar el job
validate_logs $exit_code
exit_code=$?
print_failed_asserts

if [ $exit_code -eq 0 ]; then
    echo "✅ Todos los tests pasaron"
else
    echo "❌ Tests fallaron con código: $exit_code"
fi

exit $exit_code
