#!/usr/bin/env bash
# Сборка, тесты, сценарии ядра и снимки редактора. Результаты — в test-out/.
# Используется в GitHub Actions (ci.yml и агенты) и вручную: tools/ci_build.sh [--no-editor]
# Код выхода: 0 — сборка и тесты прошли, 1 — нет (сценарии и снимки на код не влияют).
set -u
EDITOR_ON=ON; [ "${1:-}" = "--no-editor" ] && EDITOR_ON=OFF
mkdir -p test-out
# на macOS нет команды timeout: запускаем без ограничения времени
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi
# Qt из Homebrew на Mac
PFX=""; command -v brew >/dev/null 2>&1 && [ -d "$(brew --prefix qt 2>/dev/null)" ] && PFX="-DCMAKE_PREFIX_PATH=$(brew --prefix qt)"
{ cmake -S . -B build -DSDP_BUILD_EDITOR=$EDITOR_ON $PFX && cmake --build build -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"; } > test-out/сборка.txt 2>&1
BUILD=$?
TESTS=1
if [ $BUILD -eq 0 ]; then
  ctest --test-dir build --output-on-failure --timeout 400 > test-out/тесты.txt 2>&1; TESTS=$?
  for s in tests/scenarios/*.txt; do
    n=$(basename "$s" .txt)
    TO 300 ./build/sdp_run --script "$s" --status 30 > "test-out/сценарий_$n.txt" 2>&1 || echo "(сценарий завершён с кодом $?)" >> "test-out/сценарий_$n.txt"
  done
  if [ -x build/shipedit/sdp_ship ]; then
    for t in 0 1 2 3 4 5 6 7; do
      QT_QPA_PLATFORM=offscreen TO 60 ./build/shipedit/sdp_ship "data/чертёж/Данные_судна_с_чертежом.xlsx" --tab $t --screenshot "test-out/снимок_вкладка_$t.png" >/dev/null 2>&1 || true
    done
  fi
else
  echo "Сборка не прошла — тесты не запускались" > test-out/тесты.txt
fi
{ echo "сборка: $([ $BUILD -eq 0 ] && echo успешно || echo ОШИБКА)"; echo "тесты: $([ $TESTS -eq 0 ] && echo прошли || echo ЕСТЬ ОШИБКИ)"; grep -E "tests passed|tests failed" test-out/тесты.txt || true; } > test-out/итог.txt
cat test-out/итог.txt
[ $BUILD -eq 0 ] && [ $TESTS -eq 0 ]
