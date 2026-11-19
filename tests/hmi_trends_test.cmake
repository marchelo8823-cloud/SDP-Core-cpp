# Все окна трендов: кнопка выбирает окно, демонстрационная история обрезается до N минут.
foreach(win IN ITEMS 5 15 60)
  set(shot "${BINARY_DIR}/hmi_trends_${win}.png")
  file(REMOVE "${shot}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
            "${HMI}" --ship "${SOURCE_DIR}/data/Данные_судна_пример.xlsx"
            --sim "${SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx"
            --run 20 --cmd "thr_take all" --cmd position --run 30
            --trend-demo --tab 3 --press "${win} мин" --expect-trend "${win}"
            --size 1366x768 --screenshot "${shot}"
    WORKING_DIRECTORY "${SOURCE_DIR}"
    RESULT_VARIABLE rv OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
  if(NOT rv EQUAL 0)
    message(FATAL_ERROR "Окно ${win} минут не прошло проверку (код ${rv})\n${out}\n${err}")
  endif()
  if(NOT EXISTS "${shot}")
    message(FATAL_ERROR "Не создан снимок окна ${win} минут")
  endif()
endforeach()
# Без демонстрационной истории: живой таймер добавляет курс и возмущение, Canvas отрисовывается без предупреждений QML.
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
          "${HMI}" --ship "${SOURCE_DIR}/data/Данные_судна_пример.xlsx"
          --sim "${SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx"
          --run 20 --cmd "thr_take all" --cmd position --run 30
          --tab 3 --press "5 мин" --expect-trend 5
          --size 1366x768 --screenshot "${BINARY_DIR}/hmi_trends_live.png"
  WORKING_DIRECTORY "${SOURCE_DIR}"
  RESULT_VARIABLE live_rv OUTPUT_VARIABLE live_out ERROR_VARIABLE live_err TIMEOUT 30)
if(NOT live_rv EQUAL 0)
  message(FATAL_ERROR "Живая история трендов не прошла проверку (код ${live_rv})\n${live_out}\n${live_err}")
endif()
message(STATUS "Тренды: окна 5, 15, 60 минут и живая история проверены")
