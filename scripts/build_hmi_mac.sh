#!/bin/bash
# Сборка и запуск окна оператора на macOS. Запускать из папки проекта: bash scripts/build_hmi_mac.sh
set -e
cd "$(dirname "$0")/.."
command -v brew >/dev/null || { echo "Нужен Homebrew (https://brew.sh)"; exit 1; }
brew list qt >/dev/null 2>&1 || brew install qt
brew list cmake >/dev/null 2>&1 || brew install cmake
cmake -S . -B build -DSDP_BUILD_HMI=ON -DCMAKE_PREFIX_PATH="$(brew --prefix qt)"
cmake --build build -j 4
echo "Готово. Запуск:"
echo "  ./build/hmi/sdp_hmi.app/Contents/MacOS/sdp_hmi config/salvage73_pms.json --speed 5 --map maps/demo_chart.png"
