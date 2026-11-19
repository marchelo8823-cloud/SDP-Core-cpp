# Пульт оператора (Qt 6 Quick). Собирается, если в корневом CMake включено SDP_BUILD_HMI.
find_package(Qt6 REQUIRED COMPONENTS Gui Quick QuickControls2)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
qt_add_executable(sdp_hmi main.cpp hmicore.cpp hmicore.h hmi.qrc)
target_link_libraries(sdp_hmi PRIVATE dpcore Qt6::Gui Qt6::Quick Qt6::QuickControls2)
set_target_properties(sdp_hmi PROPERTIES MACOSX_BUNDLE OFF WIN32_EXECUTABLE ON)
# проверка без экрана: пульт загружается без ошибок QML и делает снимок в режиме удержания
if(NOT WIN32)
  add_test(NAME hmi_smoke COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 120 --screenshot ${CMAKE_BINARY_DIR}/hmi_smoke.png
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_smoke PROPERTIES TIMEOUT 120)
  # готовый набор рабочего места: панели переставляются по ячейкам без ошибок QML на 1366×768
  add_test(NAME hmi_workspace COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 30 --workspace maneuver --size 1366x768 --screenshot ${CMAKE_BINARY_DIR}/hmi_workspace.png
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_workspace PROPERTIES TIMEOUT 120)
  # pivot/rate и двойное подтверждение усиления: команды доходят до ядра, компоновка сохраняется на 1366×768
  add_test(NAME hmi_control COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 30 --cmd "pivot 12 3" --cmd "rate rot 12" --cmd "rate speed 1.5"
           --press "Высокое" --press "Высокое" --size 1366x768 --screenshot ${CMAKE_BINARY_DIR}/hmi_control.png
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_control PROPERTIES TIMEOUT 120)
  # прогноз: команды включают готовый Forecaster, после спокойного удержания fcValid=1 и есть четыре горизонта
  add_test(NAME hmi_forecast COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 30 --cmd "forecast on" --cmd "forecast apply on" --run 500
           --tab 7 --size 1366x768 --expect-fc 1 --screenshot ${CMAKE_BINARY_DIR}/hmi_forecast.png
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_forecast PROPERTIES TIMEOUT 120)
  # запись сеанса: выгруженный CSV содержит удержание и принимается штатным tools/sdp_report.py
  if(Python3_Interpreter_FOUND)
    add_test(NAME hmi_recording COMMAND ${CMAKE_COMMAND}
             -DHMI=$<TARGET_FILE:sdp_hmi> -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DBINARY_DIR=${CMAKE_BINARY_DIR}
             -DPYTHON=${Python3_EXECUTABLE} -P ${CMAKE_SOURCE_DIR}/tests/hmi_recording_test.cmake)
    set_tests_properties(hmi_recording PROPERTIES TIMEOUT 120)
  endif()
  # пять величин и окна 5/15/60 минут: переключатель и объём истории проверяются для каждого окна
  add_test(NAME hmi_trends COMMAND ${CMAKE_COMMAND}
           -DHMI=$<TARGET_FILE:sdp_hmi> -DSOURCE_DIR=${CMAKE_SOURCE_DIR} -DBINARY_DIR=${CMAKE_BINARY_DIR}
           -P ${CMAKE_SOURCE_DIR}/tests/hmi_trends_test.cmake)
  set_tests_properties(hmi_trends PROPERTIES TIMEOUT 120)
  # подтверждение смены режима (РС ч. XV 8.5.7): одно нажатие «Ожидание» режим не снимает, второе подряд — снимает
  foreach(n 1 2)
    set(pr "")
    foreach(i RANGE 1 ${n})
      list(APPEND pr --press "Ожидание")
    endforeach()
    if(n EQUAL 1)
      set(em 4)
    else()
      set(em 0)
    endif()
    add_test(NAME hmi_confirm_${n} COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
             $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
             --run 20 --cmd "thr_take all" --cmd position --run 30 ${pr} --expect-mode ${em}
             WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
    set_tests_properties(hmi_confirm_${n} PROPERTIES TIMEOUT 120)
  endforeach()
  # анализ последствий: кнопка «Класс 2» на пульте включает анализ
  add_test(NAME hmi_ca COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 30 --press "Класс 2" --expect-ca 2
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_ca PROPERTIES TIMEOUT 120)
endif()
