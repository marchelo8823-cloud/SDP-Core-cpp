# Редактор данных судна (Qt 6: Widgets, Network). Собирается, если в корневом CMake включено SDP_BUILD_EDITOR.
find_package(Qt6 REQUIRED COMPONENTS Widgets Network)
set(CMAKE_AUTOMOC ON)
qt_add_executable(sdp_ship main.cpp mainwindow.cpp mainwindow.h viewedit.cpp viewedit.h)
target_link_libraries(sdp_ship PRIVATE dpcore Qt6::Widgets Qt6::Network)
set_target_properties(sdp_ship PROPERTIES MACOSX_BUNDLE OFF WIN32_EXECUTABLE ON)
