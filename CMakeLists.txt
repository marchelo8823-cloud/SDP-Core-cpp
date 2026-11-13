cmake_minimum_required(VERSION 3.16)
project(SDP_Core CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
find_package(Threads REQUIRED)

# Ядро — только заголовочные файлы в include/dp
add_library(dpcore INTERFACE)
target_include_directories(dpcore INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(dpcore INTERFACE Threads::Threads)
if(MSVC)
  target_compile_options(dpcore INTERFACE /W4 /utf-8)
else()
  target_compile_options(dpcore INTERFACE -Wall -Wextra)
endif()
if(WIN32)
  target_link_libraries(dpcore INTERFACE ws2_32)
endif()

# Рабочая программа: sdp_run [--check <книга судна>] [--log <файл>] [--hz <Гц>] [--duration <с>] [--quiet] [--script <файл>]
add_executable(sdp_run apps/sdp_run.cpp)
target_link_libraries(sdp_run dpcore)

enable_testing()
set(D ${CMAKE_CURRENT_SOURCE_DIR}/data)
function(dp_test name)
  add_executable(${name} tests/${name}.cpp)
  target_link_libraries(${name} dpcore)
  add_test(NAME ${name} COMMAND ${name} ${ARGN} WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
endfunction()

# модель, оценщик, регулятор, распределитель
foreach(t closed_loop mru_test prop_test thruster_curve_test env_test soft_zone_test idle_fade_test forecast_test calib_test pivot_test eff_angle_test)
  dp_test(${t})
endforeach()
# приём датчиков
foreach(t sentence_test telegram_test rls_test)
  dp_test(${t})
endforeach()
if(NOT WIN32)   # используют POSIX: виртуальный COM-порт и сокеты
  dp_test(nmea_test)
  dp_test(modbus_test)
endif()
# рабочий цикл и ввод данных судна
dp_test(core_test ${D}/Данные_судна_пример.xlsx ${D}/Данные_имитатора_пример.xlsx ${CMAKE_CURRENT_SOURCE_DIR}/tests/books/нет_упора.xlsx)
dp_test(shipbook_test ${D}/Данные_судна_шаблон.xlsx ${D}/Данные_судна_пример.xlsx ${CMAKE_CURRENT_SOURCE_DIR}/tests/books ${D}/Данные_имитатора_шаблон.xlsx ${D}/Данные_имитатора_пример.xlsx)

# Редактор данных судна на Qt 6 (необязательно): cmake -S . -B build -DSDP_BUILD_EDITOR=ON
option(SDP_BUILD_EDITOR "Собрать редактор данных судна sdp_ship (нужен Qt 6)" OFF)
if(SDP_BUILD_EDITOR)
  add_subdirectory(shipedit)
endif()
dp_test(design_test ${D}/Данные_судна_пример.xlsx ${CMAKE_CURRENT_BINARY_DIR})
