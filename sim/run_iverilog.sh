#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RTL_DIR="$REPO_ROOT/rtl"
TB_DIR="$REPO_ROOT/tb"
BUILD_ROOT="${CSIP_SIM_BUILD_ROOT:-$SCRIPT_DIR}"
BUILD_DIR="$BUILD_ROOT/build"
WAVE_DIR="$BUILD_ROOT/waves"

mkdir -p "$BUILD_DIR" "$WAVE_DIR"

if ! command -v iverilog >/dev/null 2>&1; then
  echo "ERROR: iverilog is not installed or not in PATH."
  echo "Install Icarus Verilog, then rerun: bash sim/run_iverilog.sh all"
  exit 127
fi

if ! command -v vvp >/dev/null 2>&1; then
  echo "ERROR: vvp is not installed or not in PATH."
  echo "Install Icarus Verilog, then rerun: bash sim/run_iverilog.sh all"
  exit 127
fi

COMMON_RTL=(
  "$RTL_DIR/reset_release_sync.v"
  "$RTL_DIR/pwm_gen.v"
  "$RTL_DIR/pwm_gate.v"
  "$RTL_DIR/current_compare_dual.v"
  "$RTL_DIR/moving_avg_filter.v"
  "$RTL_DIR/sensor_health_monitor.v"
  "$RTL_DIR/transaction_destination_observer.v"
  "$RTL_DIR/fault_classifier.v"
  "$RTL_DIR/protection_fsm.v"
  "$RTL_DIR/protection_core_top.v"
  "$RTL_DIR/protection_reg_bank.v"
  "$RTL_DIR/protection_ip_top_reg_controlled.v"
  "$RTL_DIR/protection_ip_top_axi_lite.v"
)

TESTS=(
  tb_pwm_gen
  tb_current_compare_dual
  tb_moving_avg_filter
  tb_sensor_health_monitor
  tb_fault_classifier
  tb_protection_fsm
  tb_protection_core_top
  tb_protection_reg_bank
  tb_protection_ip_top_reg_controlled
  tb_protection_ip_top_axi_lite
)

usage() {
  echo "Usage: bash sim/run_iverilog.sh [all|tb_name]"
  echo "Available tests:"
  printf '  %s\n' "${TESTS[@]}"
}

requested="${1:-all}"
SELECTED=()

if [ "$requested" = "all" ]; then
  SELECTED=("${TESTS[@]}")
else
  found=0
  for tb in "${TESTS[@]}"; do
    if [ "$requested" = "$tb" ]; then
      SELECTED=("$tb")
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "ERROR: unknown testbench '$requested'"
    usage
    exit 2
  fi
fi

pass_count=0
fail_count=0

for tb in "${SELECTED[@]}"; do
  vvp_file="$BUILD_DIR/$tb.vvp"
  log_file="$BUILD_DIR/$tb.log"

  echo "[RUN] $tb"
  if iverilog -g2012 -I "$RTL_DIR" -I "$TB_DIR/generated" -o "$vvp_file" "${COMMON_RTL[@]}" "$TB_DIR/$tb.sv" >"$log_file" 2>&1; then
    if (cd "$REPO_ROOT" && vvp "$vvp_file" +CSIP_WAVE_DIR="$WAVE_DIR" >>"$log_file" 2>&1); then
      if grep -Eq "(ALL TESTS PASSED| PASS)" "$log_file"; then
        echo "[PASS] $tb"
        pass_count=$((pass_count + 1))
      else
        echo "[FAIL] $tb: simulation completed but no PASS marker was found"
        tail -40 "$log_file"
        fail_count=$((fail_count + 1))
      fi
    else
      echo "[FAIL] $tb: simulation runtime failed"
      tail -40 "$log_file"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "[FAIL] $tb: compile failed"
    tail -40 "$log_file"
    fail_count=$((fail_count + 1))
  fi
done

echo "SUMMARY: PASS=$pass_count FAIL=$fail_count"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
