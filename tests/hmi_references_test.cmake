# Опорные системы: четыре карточки, все датчики демонстрационного судна и три палитры на 1366×768.
foreach(palette IN ITEMS day dusk night)
  set(shot "${BINARY_DIR}/hmi_references_${palette}.png")
  file(REMOVE "${shot}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
            "${HMI}" --ship "${SOURCE_DIR}/data/Данные_судна_пример.xlsx"
            --sim "${SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx"
            --run 30 --tab 1 --palette "${palette}" --expect-ref 10
            --size 1366x768 --screenshot "${shot}"
    WORKING_DIRECTORY "${SOURCE_DIR}"
    RESULT_VARIABLE rv OUTPUT_VARIABLE out ERROR_VARIABLE err TIMEOUT 30)
  if(NOT rv EQUAL 0)
    message(FATAL_ERROR "Опорные системы, палитра ${palette}: код ${rv}\n${out}\n${err}")
  endif()
  if(NOT EXISTS "${shot}")
    message(FATAL_ERROR "Не создан снимок опорных систем для палитры ${palette}")
  endif()
  message(STATUS "Опорные системы (${palette}): ${out}")
endforeach()
message(STATUS "Опорные системы: 4 группы, 10 активных датчиков, палитры day/dusk/night проверены")
