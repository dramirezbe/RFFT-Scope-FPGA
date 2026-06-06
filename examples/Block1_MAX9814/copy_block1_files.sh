#!/usr/bin/env bash
set -e

# Script to copy Block1 Verilog files and ESP32 firmware from the original locations
# Adjust SOURCE_BLOCK1 and SOURCE_ESP paths if your files are elsewhere.

SOURCE_BLOCK1="/Users/nicocasper/digital_design/RFFT/Block1"
SOURCE_ESP="/Users/nicocasper/Real_Time_Systems/UART_MAX9814/main"
DEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_SRC="$DEST_ROOT/src"
DEST_FW="$DEST_ROOT/firmware"

echo "Destination root: $DEST_ROOT"

mkdir -p "$DEST_SRC" "$DEST_FW"

# List of expected Block1 files
block1_files=(
  uart_rx.v
  sample_buffer.v
  pack_real_to_complex.v
  block1_i2s_top.v
  block1_top.v
  sample_fifo.v
  pack_real_to_complex.v
  tb_pack.v
  tb_uart_rx.v
  tb_e2e.v
)

# Copy Block1 files
echo "Copying Block1 Verilog files from $SOURCE_BLOCK1 -> $DEST_SRC"
for f in "${block1_files[@]}"; do
  src="$SOURCE_BLOCK1/$f"
  if [ -f "$src" ]; then
    cp -v "$src" "$DEST_SRC/"
  else
    echo "Warning: $src not found"
  fi
done

# List of expected ESP32 firmware files
esp_files=(
  main_task.c
  max9814_driver.c
  max9814_driver.h
  CMakeLists.txt
  idf_component.yml
  plot_mic.py
  requirements.txt
)

echo "Copying ESP32 firmware files from $SOURCE_ESP -> $DEST_FW"
for f in "${esp_files[@]}"; do
  src="$SOURCE_ESP/$f"
  if [ -f "$src" ]; then
    cp -v "$src" "$DEST_FW/"
  else
    echo "Warning: $src not found"
  fi
done

# add .gitkeep to keep dirs in git if empty
touch "$DEST_SRC/.gitkeep" "$DEST_FW/.gitkeep"

echo "Done. Check $DEST_SRC and $DEST_FW for copied files."

exit 0
