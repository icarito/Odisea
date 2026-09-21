#!/bin/bash

# runtest.sh - Ejecuta tests de GdUnit3 para Odisea
# Uso:
#   ./runtest.sh -a ./core_v2/tests/           # Ejecutar todos los tests (headless)
#   ./runtest.sh -a ./core_v2/tests/test_x.gd  # Una sola suite (headless)
#   ./runtest.sh --oys test_salto_vertical     # Ejecutar test OYS específico
#   ./runtest.sh --ci                          # Reproducir el job core de CI
#   ./runtest.sh --filter cryopod              # Nodos pytest que matcheen (pytest -k)
#   ./runtest.sh --list                        # Listar suites/OYS/nodos disponibles
#   ./runtest.sh --print-command -a <suite>    # Mostrar el comando resuelto y salir
#   ./runtest.sh --show -a ./core_v2/tests/    # Con ventana visible (X11, solo mirar)
#
# Opciones:
#   --show    Mostrar ventana de Godot (X11). Por defecto es SIEMPRE Server headless.
#   --oys     Ejecutar un test OYS específico por nombre
#   --ci      Perfil de paridad con CI: gdunit en 8 shards secuenciales (procesos
#             frescos), sin determinismo, timeout de pared 540s (como el job core)
#   --filter  Expresión -k de pytest para correr nodos puntuales (fuerza el delegate)
#   --list    Lista suites GdUnit, casos OYS y cómo descubrir nodos pytest; sale 0
#   --print-command  Imprime el comando headless resuelto y sale (no ejecuta Godot)
#   --stress  Ejecutar perfil de stress (pytest marker odisea_stress)
#   --nodet   Saltar PASS 2 de determinismo (ejecuta solo fase 1)
#   --debug   Mostrar output completo sin filtrar logs de debug
#   --runner  Selecciona backend: auto|gdunit|pytest (default: pytest)
#   --workers Cantidad de workers para pytest-xdist (numero o "auto")
#   --shards  Particionar la corrida gdunit del core en N procesos Godot
#             secuenciales y frescos (solo con -a ./core_v2/tests/). Ver
#             CONTRATO DE SHARDING mas abajo.
#
# CONTRATO DE BACKEND (paridad con CI):
#   El default es el driver Server (--headless --no-window) AUNQUE haya display. CI
#   corre en un runner sin X11 y usa ese backend; un run local con X11 oculto
#   (--no-window solo) NO valida CI porque cambia el driver de ventana/input y el mouse
#   virtual y Box3D pueden dar resultados distintos. --show es la unica via grafica y
#   sirve para mirar, no para validar. tests/test_runtest_runner_contract.py vigila esto.
#
# NOTA PARA AGENTES IA:
#   El output siempre se guarda en ./reports/gdunit_runner.log
#   Si no ves el output del terminal, lee ese archivo:
#     cat ./reports/gdunit_runner.log | tail -100
#   O para ver el resumen:
#     grep -E "(PASSED|FAILED|ERROR|Total|Exit code)" ./reports/gdunit_runner.log

# El binario se resuelve mas abajo (justo antes del parseo), para que --list no
# dispare la build del fork solo por listar targets.

# Backend de display: SIEMPRE Server (--headless --no-window), igual que CI, aunque
# exista un display local. --show es la unica via grafica y no valida CI. No volver a
# bifurcar por display: tests/test_runtest_runner_contract.py lo detecta.
#
# CONTRATO DE SHARDING (job core de CI):
#   Un solo proceso GdUnit sobre 150 suites envejece el SceneTree: orphan count
#   acumulado, autoloads con estado y fisica Box3D recargada hacen que los tests
#   fisico-sensibles de fin de corrida (test_ringhub_wakeup corre en posicion
#   ~148/150) flakeen con el MISMO commit: fallos distintos por intento, verde al
#   reintentar. --shards N reparte las suites (orden alfabetico = membresia
#   determinista, independiente del readdir del filesystem) en N procesos Godot
#   SECUENCIALES (uno a la vez, sin CPU thrash) que arrancan con arbol fresco: la
#   contaminacion solo puede venir de las ~19 suites del propio shard.
#   ODISEA_RETRY_ISOLATED=1 (job de CI) agrega rescue: las suites con tests
#   fallidos se re-corren aisladas en proceso propio; si pasan el gate sale
#   verde con ::warning visible (flake), si siguen fallando es rojo real.
HEADLESS="--headless --no-window"
DEBUG_OUTPUT=0
RUNNER_MODE="${ODISEA_SHELL_RUNNER:-pytest}"
PYTEST_WORKERS="${ODISEA_PYTEST_WORKERS:-3}"
PYTEST_FAIL_FAST="${ODISEA_PYTEST_FAIL_FAST:-0}"
PYTEST_BIN=""
RUN_STRESS_ONLY=0
PRINT_COMMAND=0
CI_PROFILE=0
PYTEST_FILTER=""
GDUNIT_SHARDS="${ODISEA_GDUNIT_SHARDS:-1}"

is_truthy() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

should_skip_preflight() {
    is_truthy "${ODISEA_SKIP_PREFLIGHT:-0}"
}

# Procesar --show antes que otros argumentos
if [ "$1" = "--show" ]; then
    HEADLESS=""
    shift
fi

# Ensure complete silence on headless/no-window test runs unless explicitly overridden.
if [ -n "$HEADLESS" ] && [ -z "${ODISEA_FORCE_MUTE_AUDIO+x}" ]; then
    export ODISEA_FORCE_MUTE_AUDIO=1
fi

# En headless el render por software de escenas 3D pesadas baja el framerate a ~1 FPS
# y dispara timeouts en CI. Los tests de determinismo no dependen del render, así que
# señalamos al harness para desactivarlo. Con --show (ventana visible) se conserva.
if [ -n "$HEADLESS" ] && [ -z "${OYS_RENDER_DISABLED+x}" ]; then
    export OYS_RENDER_DISABLED=1
fi

# Paridad con CI: defaults del job "Run Tests (core)". Todo overrideable por env.
#   ANNA_V2_NO_CENTRAL=1   -> los tests no mandan telemetria al dashboard (CI lo fija a nivel job)
#   ODISEA_TEST_TIMEOUT_SEC=180 -> cada nodo pytest muere a los 180s en vez de colgarse (CI lo fija asi)
export ANNA_V2_NO_CENTRAL="${ANNA_V2_NO_CENTRAL:-1}"
export ODISEA_TEST_TIMEOUT_SEC="${ODISEA_TEST_TIMEOUT_SEC:-180}"

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

list_test_targets() {
    local f base
    echo "GdUnit suites (usar con -a):"
    for f in ./core_v2/tests/*.gd; do
        [ -f "$f" ] || continue
        grep -q "GdUnitTestSuite" "$f" 2>/dev/null || continue
        base="$(basename "$f")"
        if [ "$base" = "test_determinism_v2.gd" ]; then
            echo "  $f  (determinismo: --runner gdunit -a $f)"
        else
            echo "  $f"
        fi
    done
    echo ""
    echo "OYS / determinismo (usar con --oys):"
    list_oys_tests | sed 's/^/  /'
    echo ""
    echo "Nodos pytest (usar con --filter o pytest -k):"
    echo "  ./.venv/bin/pytest tests/test_odisea_runner.py --collect-only -q -k <substring>"
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
    # Paridad con CI: el job core envuelve la corrida con `timeout 540s`. --ci lo activa.
    if [ -n "${ODISEA_RUN_TIMEOUT_SEC:-}" ]; then
        cmd=(timeout "${ODISEA_RUN_TIMEOUT_SEC}s" "${cmd[@]}")
    fi
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

    # GdUnit tests may deliberately execute a failing OYS ASSERT to verify the
    # interpreter.  Its exit code and the GdUnit report are authoritative; do
    # not present that expected stderr as the cause of an unrelated failed test.
    mapfile -t failed_asserts < <(
        grep -E "❌ ASSERT FAILED:|ASSERT_SIGNAL FAILED|Assertion failed \(" "$cleaned" \
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

    # Preserve GdUnit's contextual failure report in the concise runner output.
    # This includes the test name and the actual expected/observed values.
    if grep -q $'\tReport:' "$cleaned"; then
        echo ""
        echo "🚨 REPORTES GdUnit FALLIDOS:"
        awk '
            /Run Test:.*FAILED/ { failed = 1; test = $0; next }
            failed && /Report:/ { print test; print; report = 1; next }
            report && /^[[:space:]]/ { print; next }
            report { failed = 0; report = 0 }
        ' "$cleaned" | awk '!seen[$0]++'
    fi

    rm -f "$cleaned"
}

# Check if pytest is available for delegated execution.
has_pytest_runner() {
    if [ ! -f "./tests/test_odisea_runner.py" ]; then
        return 1
    fi
    # Preferir el venv del repo: CI usa ./.venv/bin/pytest y trae xdist/plugins; el
    # pytest del PATH puede ser otro Python y no tener xdist, lo que cambia el paralelismo.
    if [ -x "./.venv/bin/pytest" ]; then
        PYTEST_BIN="./.venv/bin/pytest"
        return 0
    fi
    if command -v pytest >/dev/null 2>&1; then
        PYTEST_BIN="$(command -v pytest)"
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
    local include_determinism=1
    local marker_expr="not odisea_stress"
    if [ -n "${ODISEA_INCLUDE_DETERMINISM+x}" ]; then
        if ! is_truthy "${ODISEA_INCLUDE_DETERMINISM}"; then
            include_determinism=0
            marker_expr="not odisea_stress and not odisea_determinism"
        fi
    elif [ -n "${ODISEA_RUN_DETERMINISM+x}" ]; then
        if ! is_truthy "${ODISEA_RUN_DETERMINISM}"; then
            include_determinism=0
            marker_expr="not odisea_stress and not odisea_determinism"
        fi
    fi
    if [ $RUN_STRESS_ONLY -eq 1 ]; then
        cmd+=("tests/test_stress_profile.py" "-m" "odisea_stress" "--odisea-include-stress")
    else
        cmd+=("tests/test_odisea_runner.py" "--odisea-runner" "gdunit" "-m" "$marker_expr")
        if [ $include_determinism -eq 1 ]; then
            cmd+=("--odisea-include-determinism")
        fi
    fi
    if [ -n "$PYTEST_FILTER" ]; then
        cmd+=("-k" "$PYTEST_FILTER")
    fi
    if pytest_supports_xdist; then
        cmd+=("-n" "$PYTEST_WORKERS")
    fi
    if is_truthy "$PYTEST_FAIL_FAST"; then
        cmd+=("-x" "--maxfail" "1")
    fi
    if [ -z "$HEADLESS" ]; then
        cmd+=("--odisea-debug")
    fi
    echo "🐍 Delegando ejecución a pytest..."
    echo "📋 Output guardado en: $LOG_FILE"
    echo "Comando: ${cmd[*]}"
    if is_full_core_suite_target && [ $CI_PROFILE -eq 0 ]; then
        echo "ℹ️  Paridad CI: ./runtest.sh --ci reproduce el job core (gdunit en shards secuenciales de procesos frescos, sin determinismo)."
    fi
    echo "---"

    "${cmd[@]}" 2>&1 | tee "$LOG_FILE"
    return ${PIPESTATUS[0]}
}

# --- Sharding gdunit: N procesos Godot secuenciales sobre particiones ordenadas --

# Enumera las suites exactamente como las encuentra el scanner de GdUnitCmdTool
# (recursivo sobre ./core_v2/tests, script que hereda GdUnitTestSuite). El match por
# contenido coincide 1:1 con las 150 suites que descubre CI hoy: "extends GdUnitTestSuite",
# "extends res://addons/gdUnit3/src/GdUnitTestSuite.gd" y subclases. El sort hace la
# membresia de cada shard determinista (independiente del readdir del filesystem).
list_gdunit_shard_suites() {
    grep -rl --include='*.gd' "GdUnitTestSuite" ./core_v2/tests 2>/dev/null | sort -u
}

shard_per_suite_timeout() {
    # Timeout por shard: explicito, o presupuesto restante de --ci, o default.
    if [ -n "${ODISEA_SHARD_TIMEOUT_SEC:-}" ]; then
        echo "${ODISEA_SHARD_TIMEOUT_SEC}"
        return
    fi
    if [ -n "${ODISEA_RUN_TIMEOUT_SEC:-}" ]; then
        local remaining=$(( ODISEA_RUN_TIMEOUT_SEC - SECONDS ))
        if [ "$remaining" -lt 20 ]; then
            echo 20
        else
            echo "$remaining"
        fi
        return
    fi
    echo 180
}

# Corre el job core en GDUNIT_SHARDS procesos frescos. Agrega cada corrida a
# $LOG_FILE (para summary/validate/failed-asserts) y normaliza orphans por shard.
# rc agregado: 100 si algun shard fallo tests; otro rc !={0,100,101} (hang/crash)
# domina porque dejo suites sin correr y el rescue NO debe verdear el gate.
run_gdunit_sharded() {
    mapfile -t ALL_SUITES < <(list_gdunit_shard_suites)
    local total=${#ALL_SUITES[@]}
    if [ "$total" -eq 0 ]; then
        echo "❌ ERROR: no se descubrieron suites en ./core_v2/tests"
        return 3
    fi
    local n="$GDUNIT_SHARDS"
    [ "$n" -gt "$total" ] && n="$total"
    local per=$(( (total + n - 1) / n ))
    local overall=0 hard="" done_shards=0 started=$SECONDS
    for ((shard=0; shard<n; shard++)); do
        local start=$(( shard * per ))
        [ "$start" -ge "$total" ] && break
        local end=$(( start + per )); [ "$end" -gt "$total" ] && end=$total
        local -a SHARD_ARGS=()
        for ((i=start; i<end; i++)); do
            SHARD_ARGS+=("-a" "${ALL_SUITES[$i]}")
        done
        SHARD_ARGS+=("-c")
        done_shards=$((done_shards + 1))
        echo "🧊 Shard ${done_shards}/${n}: $((end - start)) suites (${ALL_SUITES[$start]#\./} … ${ALL_SUITES[$((end-1))]#\./})"
        local shard_log; shard_log=$(mktemp)
        local to; to=$(shard_per_suite_timeout)
        if [ "$n" -eq 1 ]; then
            # Un solo shard: igual al run unico historico, con presupuesto entero.
            to="${ODISEA_RUN_TIMEOUT_SEC:-$to}"
        fi
        timeout "${to}s" "$GODOT_BIN" $HEADLESS $HEADLESS_AUDIO_ARGS \
            -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd "${SHARD_ARGS[@]}" \
            2>&1 | tee "$shard_log" | { [ $DEBUG_OUTPUT -eq 1 ] && cat || filter_noisy_output; }
        local rc="${PIPESTATUS[0]}"
        cat "$shard_log" >> "$LOG_FILE"
        rm -f "$shard_log"
        echo "🧊 Shard ${done_shards}/${n} finalizado con rc=${rc} (elapsed $((SECONDS - started))s)"
        # El rc de cada shard se agrega CRUDO: 101 (orphans sin failures) lo normaliza
        # normalize_orphan_exit_code contra el log merged al final, exactamente como el
        # run unico de CI. Normalizar aca adelantaria un 0 al validate_logs y activaria
        # sus checks estrictos contra humo preexistente (SCRIPT ERROR de suites que
        # hoy son verdes en CI con exit 101).
        case "$rc" in
            0) ;;
            101) [ "$overall" -eq 0 ] && overall=101 ;;
            100) overall=100 ;;
            *) hard="$rc" ;;
        esac
    done
    if [ -n "$hard" ]; then
        return "$hard"
    fi
    return "$overall"
}

# Rescue del gate de CI: las suites con tests fallidos se re-corren AISLADAS en un
# proceso Godot fresco. La corrida aislada es la referencia de "el test funciona":
# el flake de la corrida larga se rescata con ::warning visible; un bug real
# (falla tambien aislado) mantiene el gate rojo. Solo aplica al job core completo.
maybe_retry_isolated() {
    local rc="$1"
    if ! is_truthy "${ODISEA_RETRY_ISOLATED:-0}"; then
        return "$rc"
    fi
    if [ "$rc" -ne 100 ] || ! is_full_core_suite_target; then
        return "$rc"
    fi
    local cleaned; cleaned=$(mktemp)
    strip_ansi < "$LOG_FILE" > "$cleaned"
    mapfile -t FAILED_SUITES < <( \
        grep -aE "Run Test:.*FAILED" "$cleaned" \
        | grep -aoE "res://[^ ]+\.gd" | sort -u )
    rm -f "$cleaned"
    if [ ${#FAILED_SUITES[@]} -eq 0 ]; then
        return "$rc"
    fi
    echo ""
    echo "♻️  ODISEA_RETRY_ISOLATED: ${#FAILED_SUITES[@]} suite(s) con fallos se re-corren aisladas:"
    local rescued=1
    for suite in "${FAILED_SUITES[@]}"; do
        echo "♻️  Reintento aislado: ${suite}"
        # El log reporta res://./core_v2/... (o res://core_v2/...): volver a la forma
        # ./core_v2/... que el scanner acepta comprobado (igual que los shards).
        local suite_arg="${suite#res://}"
        [[ "$suite_arg" != ./* ]] && suite_arg="./${suite_arg}"
        local retry_log; retry_log=$(mktemp)
        timeout "$(shard_per_suite_timeout)s" "$GODOT_BIN" $HEADLESS $HEADLESS_AUDIO_ARGS \
            -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd -a "$suite_arg" -c \
            2>&1 | tee "$retry_log" | { [ $DEBUG_OUTPUT -eq 1 ] && cat || filter_noisy_output; }
        local rc2="${PIPESTATUS[0]}"
        cat "$retry_log" >> "$LOG_FILE"
        if [ "$rc2" -eq 101 ]; then
            local cleaned2; cleaned2=$(mktemp)
            strip_ansi < "$retry_log" > "$cleaned2"
            if grep -Eq '\|[[:space:]]*[0-9]+[[:space:]]+total[[:space:]]+\|[[:space:]]*0[[:space:]]+error[[:space:]]+\|[[:space:]]*0[[:space:]]+failed[[:space:]]+\|' "$cleaned2" \
                && grep -qi "orphans" "$cleaned2"; then
                rc2=0
            fi
            rm -f "$cleaned2"
        fi
        rm -f "$retry_log"
        if [ "$rc2" -ne 0 ]; then
            echo "❌ ${suite} sigue fallando aislada (rc=${rc2}): fallo real, no flake."
            rescued=0
        else
            echo "✅ ${suite} pasó aislada: el fallo era de la corrida larga (flake)."
        fi
    done
    if [ "$rescued" -eq 1 ]; then
        echo "::warning::Gate rescatado por reintentos aislados (${#FAILED_SUITES[@]} suite(s) flakearon en la corrida-larga y pasaron aisladas). Investigar la contaminacion del proceso unico."
        echo "♻️  Todas las suites fallidas pasaron aisladas."
        return 0
    fi
    return "$rc"
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

# --list es descubrimiento puro: no necesita el binario de Godot. Se atiende antes de
# resolverlo para no disparar una build del fork (godot_bin.sh) solo por listar.
for _arg in "$@"; do
    if [ "$_arg" = "--list" ]; then
        list_test_targets
        exit 0
    fi
done

if [ -z "$GODOT_BIN" ]; then
	# No basta pasar --headless al editor X11 de Godot 3: sigue usando su backend X11.
	# Pedir el flavor Server pinneado descarga exactamente el runtime que usa CI.
	if [ -n "$HEADLESS" ]; then
		export ODISEA_GODOT_FLAVOR=headless
	fi
    GODOT_BIN="$(sh "$(dirname "$0")/tools/godot_bin.sh")"
fi

# Parse arguments
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --show)
            HEADLESS=""
            shift
            ;;
        --ci)
            CI_PROFILE=1
            shift
            ;;
        --print-command)
            PRINT_COMMAND=1
            shift
            ;;
        -k|--filter)
            PYTEST_FILTER="$2"
            if [ -z "$PYTEST_FILTER" ]; then
                echo "ERROR: --filter requiere una expresión -k (ej: --filter cryopod)"
                exit 1
            fi
            shift 2
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
        --shards)
            GDUNIT_SHARDS="$2"
            GDUNIT_SHARDS_CLI_SET=1
            if [[ -z "$GDUNIT_SHARDS" || ! "$GDUNIT_SHARDS" =~ ^[0-9]+$ || "$GDUNIT_SHARDS" -lt 1 ]]; then
                echo "ERROR: --shards debe ser un numero entero >= 1"
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

            if [ $PRINT_COMMAND -eq 1 ]; then
                echo "$GODOT_BIN $HEADLESS ${HEADLESS:+--audio-driver Dummy} -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd -a ./core_v2/tests/test_determinism_v2.gd"
                exit 0
            fi

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

# Perfil --ci: reproduce el job "Run Tests (core)" de CI tal cual.
#   CI corre gdunit en 8 shards secuenciales (procesos frescos, ver CONTRATO DE
#   SHARDING), sin determinismo (va en su propio workflow), con preflight ya hecho
#   y timeout de pared de 540s. Un run local con el delegate pytest arranca un
#   Godot por suite: el estado de orfandad acumulada y el orden de ejecucion NO son
#   los de CI, asi que no sirve para reproducir un fallo.
if [ $CI_PROFILE -eq 1 ]; then
    export ODISEA_INCLUDE_DETERMINISM=0
    export ODISEA_RUN_DETERMINISM=0
    # CI ya corrio import+smoke antes de los tests y por eso salta el preflight; en un
    # checkout limpio exportar ODISEA_SKIP_PREFLIGHT=0 para forzarlo.
    export ODISEA_SKIP_PREFLIGHT="${ODISEA_SKIP_PREFLIGHT:-1}"
    export ODISEA_TEST_TIMEOUT_SEC=180
    export ODISEA_RUN_TIMEOUT_SEC="${ODISEA_RUN_TIMEOUT_SEC:-540}"
    # El job core de CI corre sharded en procesos frescos (ver CONTRATO DE SHARDING).
    export ODISEA_GDUNIT_SHARDS="${ODISEA_GDUNIT_SHARDS:-8}"
    if [ -z "${GDUNIT_SHARDS_CLI_SET+x}" ]; then
        GDUNIT_SHARDS="${ODISEA_GDUNIT_SHARDS}"
    fi
    # El rescue por reintento aislado lo fija SOLO el job de CI (ODISEA_RETRY_ISOLATED=1
    # en el env del step): --ci reproduce fallos, no los rescata.
    RUNNER_MODE="gdunit"
    echo "🎯 Perfil --ci: gdunit en ${GDUNIT_SHARDS} shards secuenciales (procesos frescos), sin determinismo, timeout de pared ${ODISEA_RUN_TIMEOUT_SEC}s."
    echo "🎯 El gate de CI agrega ODISEA_RETRY_ISOLATED=1 (rescate por reintento aislado)."
fi

# GdUnit aborta la suite en el primer test fallido ("fail fast"): en CI eso obliga a un ciclo
# completo por cada fallo, y los casos que vienen despues quedan invisibles hasta arreglar el
# anterior. Con -c corre el set entero y reporta todos los fallos de una. ODISEA_FAIL_FAST=1
# vuelve al comportamiento viejo para una corrida puntual.
if ! is_truthy "${ODISEA_FAIL_FAST:-0}"; then
    ARGS+=("-c")
fi

# Full suite default: include determinism cases in phase 1 (--nodet).
# Allows opt-out by exporting ODISEA_RUN_DETERMINISM=0 or OYS_NODET=0 explicitly.
if [ $RUN_STRESS_ONLY -eq 0 ] && is_full_core_suite_target; then
    if [ -z "${ODISEA_RUN_DETERMINISM+x}" ]; then
        export ODISEA_RUN_DETERMINISM=1
        echo "Determinism enabled by default for full core suite (ODISEA_RUN_DETERMINISM=1)."
    fi
    if [ -z "${OYS_NODET+x}" ]; then
        export OYS_NODET=1
        echo "Running determinism in phase 1 by default (OYS_NODET=1)."
    fi
fi

# --print-command: muestra el comando headless resuelto y sale sin tocar Godot.
# Lo usa tests/test_runtest_runner_contract.py para blindar el backend Server.
# Con sharding imprime un comando por shard (suites explicitas, no el directorio).
if [ $PRINT_COMMAND -eq 1 ]; then
    PRINT_AUDIO_ARGS=""
    [ -n "$HEADLESS" ] && PRINT_AUDIO_ARGS="--audio-driver Dummy"
    if [ "$RUNNER_MODE" = "gdunit" ] && [ "$GDUNIT_SHARDS" -gt 1 ] && is_full_core_suite_target; then
        mapfile -t PRINT_SUITES < <(list_gdunit_shard_suites)
        total=${#PRINT_SUITES[@]}
        n="$GDUNIT_SHARDS"; [ "$n" -gt "$total" ] && n="$total"
        per=$(( (total + n - 1) / n ))
        for ((s=0; s<n; s++)); do
            start=$(( s * per )); [ "$start" -ge "$total" ] && break
            end=$(( start + per )); [ "$end" -gt "$total" ] && end=$total
            cmd_suffix=""
            for ((i=start; i<end; i++)); do
                cmd_suffix+=" -a ${PRINT_SUITES[$i]}"
            done
            echo "$GODOT_BIN $HEADLESS $PRINT_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd${cmd_suffix} -c"
        done
    else
        echo "$GODOT_BIN $HEADLESS $PRINT_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd ${ARGS[*]}"
    fi
    exit 0
fi

# Try pytest delegation for full-suite runs, stress profile and filtered node runs.
if [ $RUN_STRESS_ONLY -eq 1 ] || is_full_core_suite_target || [ -n "$PYTEST_FILTER" ]; then
    if ! should_skip_preflight; then
        run_import_preflight || exit $?
    fi
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

if [ "$RUNNER_MODE" = "gdunit" ] && [ "$GDUNIT_SHARDS" -gt 1 ] && is_full_core_suite_target; then
    echo "🧪 Ejecutando tests GdUnit3 ${HEADLESS:+(headless)} en ${GDUNIT_SHARDS} shards secuenciales..."
    echo "📋 Output guardado en: $LOG_FILE"
    if [ $DEBUG_OUTPUT -eq 0 ]; then
        echo "Modo salida: limpio (usa --debug para ver logs completos)"
    else
        echo "Modo salida: debug completo"
    fi
    echo "---"

    # El preflight ya corrio en el bloque de delegacion (todo full-core pasa por ahi).
    run_gdunit_sharded
    exit_code=$?
else
    echo "🧪 Ejecutando tests GdUnit3 ${HEADLESS:+(headless)}..."
    echo "📋 Output guardado en: $LOG_FILE"
    echo "Comando: $GODOT_BIN $HEADLESS $HEADLESS_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd ${ARGS[*]}"
    if [ $DEBUG_OUTPUT -eq 0 ]; then
        echo "Modo salida: limpio (usa --debug para ver logs completos)"
    else
        echo "Modo salida: debug completo"
    fi
    echo "---"

    if ! should_skip_preflight; then
        run_import_preflight || exit $?
    fi

    # Ejecuta Godot con output en tiempo real (filtrado o completo según modo)
    run_and_capture $GODOT_BIN $HEADLESS $HEADLESS_AUDIO_ARGS -s ./addons/gdUnit3/bin/GdUnitCmdTool.gd "${ARGS[@]}"
    exit_code=$?
fi

echo "---"
echo "📋 Log guardado en: $LOG_FILE"

# --- Generar Tablita de Resumen ---
print_summary_table

# Analizar la salida para detectar condiciones que deberían hacer fallar el job
validate_logs $exit_code
exit_code=$?
normalize_orphan_exit_code $exit_code
exit_code=$?

# Rescue del gate (ODISEA_RETRY_ISOLATED=1, job de CI): re-corre las suites con
# fallos en procesos aislados. Solo aplica a fallos de tests (100); un bug real
# sigue fallando aislado y el gate queda rojo. Debe ir DESPUES de validate_logs para
# que errores de recursos/SCRIPT ERROR no sean rescatables.
if [ $exit_code -eq 100 ]; then
    maybe_retry_isolated $exit_code
    exit_code=$?
fi

print_failed_asserts

if [ $exit_code -eq 0 ]; then
    echo "✅ Todos los tests pasaron"
else
    echo "❌ Tests fallaron con código: $exit_code"
fi

exit $exit_code
