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
  # Настройка рабочего места не подаёт команд: настоящий щелчок по «Взять все» под накладкой ячейки ничего не берёт,
  # а без настройки тот же щелчок берёт все четыре движителя (проверка, что щелчок доходит).
  foreach(cs "edit;0" "noedit;4")
    list(GET cs 0 nm)
    list(GET cs 1 et)
    if(nm STREQUAL "edit")
      set(ed --ws-edit)
    else()
      set(ed)
    endif()
    add_test(NAME hmi_ws_${nm} COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
             $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
             --run 20 --tab 1 --ws-set 1 ${ed} --click "Взять все" --expect-taken ${et}
             WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  endforeach()
  add_test(NAME hmi_ca COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
           $<TARGET_FILE:sdp_hmi> --ship ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx --sim ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx
           --run 20 --cmd "thr_take all" --cmd position --run 30 --press "Класс 2" --expect-ca 2
           WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
  set_tests_properties(hmi_ca PROPERTIES TIMEOUT 120)
  # шапка состояния говорит правду об отказах (замечания операторов и агентов, 17.11.2026)
  set(S ${CMAKE_SOURCE_DIR}/data/Данные_судна_пример.xlsx)
  set(I ${CMAKE_SOURCE_DIR}/tests/scenarios/имитатор_быстро.xlsx)
  set(GY --cmd "sim off GYRO1" --cmd "sim off GYRO2" --cmd "sim off GYRO3")
  set(PS --cmd "sim off GNSS1" --cmd "sim off GNSS2" --cmd "sim off LASER")
  foreach(case "hold|--run;1|УДЕРЖАНИЕ ПОЗИЦИИ" "hdgdr|${GY};--run;2.5|СЧИСЛЕНИЕ КУРСА" "hdglost|${GY};--run;8|УПОР СНЯТ — НЕТ КУРСА"
               "posdr|${PS};--run;60|СЧИСЛЕНИЕ ПОЛОЖЕНИЯ" "return|${PS};--run;120;--cmd;sim reset;--run;15|ВОЗВРАТ В ТОЧКУ")
    string(REPLACE "|" ";" parts "${case}")
    list(GET parts 0 nm)
    list(GET parts -1 lab)
    list(REMOVE_AT parts 0 -1)
    add_test(NAME hmi_state_${nm} COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
             $<TARGET_FILE:sdp_hmi> --ship ${S} --sim ${I} --run 20 --cmd "thr_take all" --cmd position --run 60 ${parts} --expect-state "${lab}"
             WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})
    set_tests_properties(hmi_state_${nm} PROPERTIES TIMEOUT 180)
  endforeach()
endif()
