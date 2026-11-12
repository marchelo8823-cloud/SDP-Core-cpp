#!/bin/bash
# Запуск на macOS: служба ядра и два окна оператора (посты A и B). Сначала соберите: bash scripts/build_hmi_mac.sh
# Запускать из папки проекта: bash scripts/run_two_posts_mac.sh [скорость имитации, по умолчанию 5] [файл настроек, по умолчанию config/demo.json]
# Например, с электростанцией PMS: bash scripts/run_two_posts_mac.sh 5 config/salvage73_pms.json
# Пароль администратора и профиль судна хранятся в sdp_data рядом с проектом. Первый пароль: build/sdp_core config/demo.json --set-admin-password --data-dir sdp_data
cd "$(dirname "$0")/.."
SPEED=${1:-5}
CFG=${2:-config/demo.json}
HMI=build/hmi/sdp_hmi.app/Contents/MacOS/sdp_hmi
[ -x "$HMI" ] && [ -x build/sdp_core ] || { echo "Сначала соберите программу: bash scripts/build_hmi_mac.sh"; exit 1; }
build/sdp_core "$CFG" --port 5300 --speed "$SPEED" --quiet --data-dir "$PWD/sdp_data" &
CORE=$!
trap 'kill $CORE 2>/dev/null' EXIT
sleep 1
"$HMI" --connect 127.0.0.1:5300 --station A --map maps/demo_chart.png --size 1200x760 &
"$HMI" --connect 127.0.0.1:5300 --station B --map maps/demo_chart.png --size 1200x760 &
echo "Работают ядро и два поста. Закройте оба окна, затем нажмите Ctrl+C."
wait
