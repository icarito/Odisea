#!/bin/bash
# scripts/run_core_tests.sh
# Runs core tests for the drone fixes and stealth logic.

export GODOT_BIN=${GODOT_BIN:-"godot3-bin"}

./runtest.sh --runner gdunit \
    -a res://core_v2/tests/test_ddc_drone.gd \
    -a res://core_v2/tests/test_cargol_determinism.gd \
    -a res://core_v2/tests/test_player_stealth.gd
