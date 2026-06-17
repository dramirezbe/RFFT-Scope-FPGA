#!/usr/bin/env bash
# ===========================================================================
# Plan de verificación — RFFT Scope FPGA
#
# Ejecuta UNA A UNA las pruebas RTL del documento de diseño (Sección 3,
# Tabla 1) con Icarus Verilog y reporta PASS/FAIL. Están organizadas por
# bloque, de abajo hacia arriba (bottom-up), e incluyen específicamente el
# camino implicado en el error que presentamos (mic -> UART -> Block1 ->
# display), más posibles causas en los bloques siguientes (B2..B5).
#
# La prueba de grabar audio (mic_record_test) NO se ejecuta aquí: es
# hardware-in-the-loop (ESP32 + micrófono real). Se lista como prueba manual.
#
# Uso:   ./run_tests.sh
# Requiere: iverilog + vvp (Icarus Verilog).  brew install icarus-verilog
# ===========================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
FINAL="$ROOT/final"
RESULTS="$HERE/results"
mkdir -p "$RESULTS"
cd "$FINAL"   # los TB usan rutas relativas (tb/vectors/..., src/block3/*.hex)

PASS=0; FAIL=0

command -v iverilog >/dev/null 2>&1 || { echo "ERROR: falta 'iverilog'"; exit 1; }

# run <nombre> <patron_exito> <tb + fuentes...>
run() {
    local name="$1" ok="$2"; shift 2
    local vvp="$RESULTS/$name.vvp" log="$RESULTS/$name.log"
    printf "  ▶ %-22s ... " "$name"
    if ! iverilog -g2012 -o "$vvp" "$@" >"$log" 2>&1; then
        echo "FAIL (compilación)  -> results/$name.log"; FAIL=$((FAIL+1)); return
    fi
    vvp "$vvp" >>"$log" 2>&1
    if grep -qiE 'FAIL|mismatch|ERROR:' "$log"; then
        echo "FAIL (errores en sim)  -> results/$name.log"; FAIL=$((FAIL+1)); return
    fi
    if grep -qE "$ok" "$log"; then echo "PASS"; PASS=$((PASS+1));
    else echo "FAIL (no se vio '$ok')  -> results/$name.log"; FAIL=$((FAIL+1)); fi
}

echo "=== Plan de verificación RFFT Scope (repo: $ROOT) ==="
echo

echo "[Bloque 1] Entrada: recepción UART + buffer + empaquetado  (CAMINO DEL ERROR)"
run uart_rx        "errors=0" tb/tb_uart_rx.v src/block1/uart_rx.v
run ram_buffer     "FIN TEST dual_port_ram_buffer" tb/tb_ram_buffer.v src/block2/dual_port_ram_buffer.v
run pack           "PASS"     tb/tb_pack.v src/block1/*.v
run e2e_block1     "errors=0" tb/tb_e2e.v src/block1/*.v
echo

echo "[Bloque 2] Bit-reversal / permutación"
run bit_reverse            "PASS" tb/tb_bit_reverse.v src/block2/bit_reverse.v
run permutation            "PASS" tb/tb_permutation.v src/block2/*.v
run permutation_1024       "PASS" tb/tb_permutation_1024.v src/block2/*.v
run permutation_ready_pause "PASS" tb/tb_permutation_ready_pause.v src/block2/*.v
echo

echo "[Bloques 3+4] Núcleo FFT 1024-pt (mariposa + twiddles)"
run complex_fft_core "PASS" tb/tb_complex_fft_core.v src/block4/*.v src/block3/twiddle_rom.v src/block3/butterfly_radix2.v
echo

echo "[Bloque 5] Recombinación RFFT (1025 bins)"
run rfft_recombine "PASS" tb/tb_rfft_recombine.v src/block5/rfft_recombine.v src/block3/twiddle_rom.v src/block3/butterfly_radix2.v
echo

echo "[Integración] Cadenas combinadas y pipeline completo"
run chain_b2b4recomb "PASS" tb/tb_chain_b2b4recomb.v src/block2/*.v src/block4/*.v src/block5/rfft_recombine.v src/block3/twiddle_rom.v src/block3/butterfly_radix2.v
run block1_2_fusion  "PASS" tb/tb_block1_2_fusion.v src/rfft_block1_2_top.v src/block1/*.v src/block2/*.v
run scope_e2e        "PASS" tb/tb_rfft_scope_e2e.v src/rfft_scope_top.v src/block1/*.v src/block2/*.v src/block3/twiddle_rom.v src/block3/butterfly_radix2.v src/block4/*.v src/block5/*.v src/lcd/lcd_ctrl.v
echo

echo "=== Prueba manual (NO automatizada — hardware-in-the-loop) ==="
echo "  5. mic_record_test : grabar audio del micrófono y escucharlo (ESP32 + MAX9814)."
echo "     Ver examples/Block1_MAX9814/mic_record_test/README.md"
echo

echo "=== Resumen ==="
echo "  PASS: $PASS   FAIL: $FAIL   (logs en verification_plan/results/)"
[ "$FAIL" -eq 0 ]
