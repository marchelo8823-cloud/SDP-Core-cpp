# Выгрузка журнала из пульта: CSV должен содержать удержание и читаться штатным отчётом.
set(csv "${BINARY_DIR}/hmi_recording.csv")
set(shot "${BINARY_DIR}/hmi_recording.png")
file(REMOVE "${csv}" "${shot}")
file(WRITE "${csv}" "старая выгрузка: должна быть заменена\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
          "${HMI}" --ship "${SOURCE_DIR}/data/Данные_судна_пример.xlsx"
          --sim "${SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx"
          --run 20 --cmd "thr_take all" --cmd position --run 30
          --tab 8 --size 1366x768 --export-recording "${csv}" --screenshot "${shot}"
  WORKING_DIRECTORY "${SOURCE_DIR}"
  RESULT_VARIABLE rv OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 110)
if(NOT rv EQUAL 0)
  message(FATAL_ERROR "Пульт завершился с кодом ${rv}\n${out}\n${err}")
endif()
if(NOT EXISTS "${csv}" OR NOT EXISTS "${shot}")
  message(FATAL_ERROR "Не созданы CSV или снимок\n${out}\n${err}")
endif()
file(READ "${csv}" head LIMIT 200)
if(NOT head MATCHES "^t_s,состояние,режим,")
  message(FATAL_ERROR "В выгрузке нет штатного заголовка журнала: ${head}")
endif()
execute_process(
  COMMAND "${PYTHON}" "${SOURCE_DIR}/tools/sdp_report.py" "${csv}"
  RESULT_VARIABLE rr OUTPUT_VARIABLE rep ERROR_VARIABLE rerr TIMEOUT 30)
if(NOT rr EQUAL 0)
  message(FATAL_ERROR "Штатный отчёт не принял выгрузку: ${rerr}")
endif()
string(FIND "${rep}" "## Удержание" hold)
string(FIND "${rep}" "Ошибка положения, м" errpos)
if(hold LESS 0 OR errpos LESS 0)
  message(FATAL_ERROR "В отчёте по выгрузке нет данных удержания\n${rep}")
endif()
message(STATUS "Выгрузка CSV и отчёт по ней проверены: ${csv}")
