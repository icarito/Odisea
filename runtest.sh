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
#   --stress  Ejecutar perfil de stress (pytest marker odisea_stress)
#   --nodet   Saltar tests de determinism
#   --debug   Mostrar output completo sin filtrar logs de debug
#   --runner  Selecciona backend: auto|gdunit|pytest (default: pytest)
#   --workers Cantidad de workers para pytest-xdist (numero o "auto")
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

# Por defecto: en sesión gráfica usar solo --no-window; sin DISPLAY forzar headless.
if [ -n "${DISPLAY:-}" ]; then
    HEADLESS="--no-window"
else
    HEADLESS="--headless --no-window"
fi
DEBUG_OUTPUT=0
RUNNER_MODE="${ODISEA_SHELL_RUNNER:-pytest}"
PYTEST_WORKERS="${ODISEA_PYTEST_WORKERS:-auto}"
PYTEST_BIN=""
RUN_STRESS_ONLY=0

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
        -e '/^ERROR: VisualServer attempted to free a NULL RID\.$/d' \
        -e '/^[[:space:]]+at: free \(servers\/visual\/visual_server_raster\.cpp:69\)$/d'
}

list_oys_tests() {
    find ./core_v2/tests -type f -name "*.oys" 2>/dev/null \
        | sed 's|^\./core_v2/tests/||; s|\.oys$||' \
        | sort
}

resolve_oys_file() {
    local oys_name="$1"
    local direct="./core_v2/tests/${oys_name}.oys"
    if [ -f "$direct" ]; then
        echo "$direct"
        return 0
    fi

    local match
    match=$(find ./core_v2/tests -type f -name "${oys_name}.oys" 2>/dev/null | head -n 1)
    if [ -n "$match" ] && [ -f "$match" ]; then
        echo "$match"
        return 0
    fi
    return 1
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

run_import_preflight() {
    local preflight_log="$LOG_DIR/import_preflight_$(date +%Y%m%d_%H%M%S)_$$.log"
    echo "🧩 Preflight import de recursos..."
    echo "📋 Preflight log: $preflight_log"

    # In CI, let scan/import complete for a bounded time.
    # Locally, keep it fast with --quit.
    if [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        set +e
        timeout 45s $GODOT_BIN $HEADLESS ${HEADLESS:+--audio-driver Dummy} -e 2>&1 | tee "$preflight_log" >/dev/null
        local rc="${PIPESTATUS[0]}"
        set -e
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
            echo "❌ Preflight import falló (exit $rc)."
            return "$rc"
        fi
    else
        $GODOT_BIN $HEADLESS ${HEADLESS:+--audio-driver Dummy} -e --quit 2>&1 | tee "$preflight_log" >/dev/null
    fi

    # Señales tempranas de recursos críticos aún no importados.
    ls .import/*sfx100v2_loop_machine_02.ogg-*.oggstr >/dev/null 2>&1 || echo "⚠️ Falta import de sfx100v2_loop_machine_02.ogg"
    ls .import/*phase.wav-*.sample >/dev/null 2>&1 || echo "⚠️ Falta import de phase.wav"
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

# Check if pytest is available for delegated execution.
has_pytest_runner() {
    if [ ! -f "./tests/test_odisea_runner.py" ]; then
        return 1
    fi
    if command -v pytest >/dev/null 2>&1; then
        PYTEST_BIN="$(command -v pytest)"
        return 0
    fi
    if [ -x "./.venv/bin/pytest" ]; then
        PYTEST_BIN="./.venv/bin/pytest"
        return 0
    fi
    return 1
}

pytest_supports_xdist() {
    "$PYTEST_BIN" --help 2>/dev/null | grep -q -- "--numprocesses"
}

# True when target corresponds to "run all core_v2 tests".
is_full_core_suite_target() {
    local i=0
    while [ $i -lt ${#ARGS[@]} ]; do
        if [ "${ARGS[$i]}" = "-a" ]; then
            local next_index=$((i + 1))
            local target="${ARGS[$next_index]}"
            case "$target" in
                "./core_v2/tests"|"./core_v2/tests/"|"core_v2/tests"|"core_v2/tests/"|"res://core_v2/tests"|"res://core_v2/tests/")
                    return 0
                    ;;
            esac
        fi
        i=$((i + 1))
    done
    return 1
}

run_pytest_delegate() {
    local cmd=("$PYTEST_BIN")
    if [ $RUN_STRESS_ONLY -eq 1 ]; then
        cmd+=("tests/test_stress_profile.py" "-m" "odisea_stress" "--odisea-include-stress")
    else
        cmd+=("tests/test_odisea_runner.py" "--odisea-runner" "gdunit" "-m" "not odisea_stress")
    fi
    if pytest_supports_xdist; then
        cmd+=("-n" "$PYTEST_WORKERS")
    fi
    if [ -z "$HEADLESS" ]; then
        cmd+=("--odisea-debug")
    fi
    if [ "${OYS_NODET:-0}" = "1" ]; then
        cmd+=("-k" "not test_det and not test_determinism_batched_case")
    fi

    echo "🐍 Delegando ejecución a pytest..."
    echo "📋 Output guardado en: $LOG_FILE"
    echo "Comando: ${cmd[*]}"
    echo "---"

    "${cmd[@]}" 2>&1 | tee "$LOG_FILE"
    return ${PIPESTATUS[0]}
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

normalize_orphan_exit_code() {
    local code=$1
    if [ $code -ne 101 ]; then
        return $code
    fi

    local cleaned
    cleaned=$(mktemp)
    strip_ansi < "$LOG_FILE" > "$cleaned"

    if grep -Eq '\|[[:space:]]*[0-9]+[[:space:]]+total[[:space:]]+\|[[:space:]]*0[[:space:]]+error[[:space:]]+\|[[:space:]]*0[[:space:]]+failed[[:space:]]+\|' "$cleaned" \
        && grep -qi "orphans" "$cleaned"; then
        echo "⚠️ GdUnit devolvió exit code 101 por orphans/string-name leaks, pero no hubo tests fallidos."
        rm -f "$cleaned"
        return 0
    fi

    rm -f "$cleaned"
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
        --stress)
            RUN_STRESS_ONLY=1
            RUNNER_MODE="pytest"
            shift
            ;;
        --runner)
            RUNNER_MODE="$2"
            if [[ -z "$RUNNER_MODE" || ! "$RUNNER_MODE" =~ ^(auto|gdunit|pytest)$ ]]; then
                echo "ERROR: --runner debe ser uno de: auto, gdunit, pytest"
                exit 1
            fi
            shift 2
            ;;
        --workers)
            PYTEST_WORKERS="$2"
            if [[ -z "$PYTEST_WORKERS" || ! "$PYTEST_WORKERS" =~ ^(auto|[0-9]+)$ ]]; then
                echo "ERROR: --workers debe ser un numero entero o 'auto'"
                exit 1
            fi
            shift 2
            ;;
        --oys)
            OYS_NAME="$2"
            shift 2
            
            if [ -z "$OYS_NAME" ]; then
                echo "ERROR: Especifica el nombre del test OYS (sin extensión)"
                echo "Uso: ./runtest.sh --oys test_salto_vertical"
                echo ""
                echo "Tests OYS disponibles:"
                list_oys_tests
                exit 1
            fi
            
            # Buscar el archivo OYS
            OYS_FILE=$(resolve_oys_file "$OYS_NAME")
            if [ -z "$OYS_FILE" ] || [ ! -f "$OYS_FILE" ]; then
                echo "ERROR: No se encontró test OYS para '$OYS_NAME'"
                echo ""
                echo "Tests OYS disponibles:"
                list_oys_tests
                exit 1
            fi
            
            OYS_FILTER_NAME=$(basename "$OYS_FILE" .oys)
            echo "▶️ Ejecutando test OYS: $OYS_FILTER_NAME (${OYS_FILE#./core_v2/tests/}) ${HEADLESS:+(headless)}"
            echo "📋 Output guardado en: $LOG_FILE"
            echo "---"
            
            # Usar variable de entorno OYS_FILTER para filtrar el test
            export OYS_FILTER="${OYS_FILTER_NAME}"
            run_and_capture $GODOT_BIN $HEADLESS ${HEADLESS:+--audio-driver Dummy} -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd \
                -a "./core_v2/tests/test_determinism_v2.gd" "$@"
            exit_code=$?
            
            echo "---"
            print_summary_table
            
            # Validar logs para detectar SCRIPT ERROR que GdUnit no ve como fail
            validate_logs $exit_code
            exit_code=$?
            normalize_orphan_exit_code $exit_code
            exit_code=$?
            print_failed_asserts

            echo ""
            echo "📋 Output completo en: $LOG_FILE"
            if [ $exit_code -eq 0 ]; then
                echo "✅ Test OYS '$OYS_FILTER_NAME' pasó"
            else
                echo "❌ Test OYS '$OYS_FILTER_NAME' falló con código: $exit_code"
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

# Try pytest delegation for full-suite runs and stress profile.
if [ $RUN_STRESS_ONLY -eq 1 ] || is_full_core_suite_target; then
    run_import_preflight || exit $?
    if [ "$RUNNER_MODE" = "pytest" ]; then
        if ! has_pytest_runner; then
            echo "ERROR: --runner pytest solicitado, pero pytest o tests/test_odisea_runner.py no está disponible."
            exit 127
        fi
        run_pytest_delegate
        exit_code=$?
        echo "---"
        echo "📋 Log guardado en: $LOG_FILE"
        exit $exit_code
    fi

    if [ "$RUNNER_MODE" = "auto" ] && has_pytest_runner; then
        run_pytest_delegate
        exit_code=$?
        echo "---"
        echo "📋 Log guardado en: $LOG_FILE"
        exit $exit_code
    fi
fi

HEADLESS_AUDIO_ARGS=""
if [ -n "$HEADLESS" ]; then
    HEADLESS_AUDIO_ARGS="--audio-driver Dummy"
fi

echo "🧪 Ejecutando tests GdUnit3 ${HEADLESS:+(headless)}..."
echo "📋 Output guardado en: $LOG_FILE"
echo "Comando: $GODOT_BIN $HEADLESS $HEADLESS_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd ${ARGS[*]}"
if [ $DEBUG_OUTPUT -eq 0 ]; then
    echo "Modo salida: limpio (usa --debug para ver logs completos)"
else
    echo "Modo salida: debug completo"
fi
echo "---"

run_import_preflight || exit $?

# Ejecuta Godot con output en tiempo real (filtrado o completo según modo)
run_and_capture $GODOT_BIN $HEADLESS $HEADLESS_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd "${ARGS[@]}"
exit_code=$?

echo "---"
echo "📋 Log guardado en: $LOG_FILE"

# --- Generar Tablita de Resumen ---
print_summary_table

# Analizar la salida para detectar condiciones que deberían hacer fallar el job
validate_logs $exit_code
exit_code=$?
normalize_orphan_exit_code $exit_code
exit_code=$?
print_failed_asserts

if [ $exit_code -eq 0 ]; then
    echo "✅ Todos los tests pasaron"
else
    echo "❌ Tests fallaron con código: $exit_code"
fi

exit $exit_code
