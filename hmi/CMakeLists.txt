# Окно оператора на Qt 6 / QML. Сборка: cmake -S . -B build -DSDP_BUILD_HMI=ON -DCMAKE_PREFIX_PATH=<путь к Qt>
find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Network)
qt_standard_project_setup()

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_executable(sdp_hmi src/main.cpp src/backend.cpp src/planview.cpp src/trendview.cpp src/maploader.cpp src/mapunderlay.cpp)
qt_add_qml_module(sdp_hmi
    URI Sdp
    VERSION 1.0
    QML_FILES
        qml/Main.qml qml/Theme.qml qml/Panel.qml qml/Btn.qml qml/Seg.qml qml/Chip.qml
        qml/ThrusterRow.qml qml/NavIcon.qml qml/HeadingTape.qml qml/ThrusterColumn.qml qml/PositionPanel.qml qml/WorkView.qml qml/ExtForcePanel.qml qml/SettingsPopup.qml qml/Readout.qml qml/LayoutEditor.qml qml/AdminPage.qml qml/DialView.qml qml/DeskView.qml qml/InstSpeed.qml qml/InstForce.qml qml/InstHeading.qml qml/InstRef.qml qml/InstLoad.qml qml/PivotDialog.qml qml/HullDialog.qml qml/InstMru.qml qml/SimDialog.qml qml/PmsDialog.qml qml/PmsPage.qml qml/ThrusterPage.qml
    qml/SensorsPage.qml qml/CapabilityPage.qml qml/HypotPanel.qml qml/ForecastPage.qml
    qml/AdminSession.qml qml/PlannerPage.qml qml/PowerDiagram.qml
        qml/RefQualityDiagram.qml qml/ExtLinkPage.qml qml/CapEndpoint.qml qml/CapturePage.qml qml/SourcesPage.qml qml/AccessPage.qml qml/LimitsPage.qml qml/AgentPage.qml
)
target_link_libraries(sdp_hmi PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Network dpcore Threads::Threads)
target_compile_definitions(sdp_hmi PRIVATE QT_NO_KEYWORDS SDP_KB_DIR="${CMAKE_SOURCE_DIR}/kb")
if(WIN32)
  target_link_libraries(sdp_hmi PRIVATE ws2_32)
  set_target_properties(sdp_hmi PROPERTIES WIN32_EXECUTABLE ON)
endif()
if(APPLE)
  set_target_properties(sdp_hmi PROPERTIES MACOSX_BUNDLE ON)
endif()
# рядом с программой кладём настройки и демонстрационную карту
add_custom_target(sdp_hmi_assets ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/config $<TARGET_FILE_DIR:sdp_hmi>/config
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/maps $<TARGET_FILE_DIR:sdp_hmi>/maps
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/kb $<TARGET_FILE_DIR:sdp_hmi>/kb)
add_dependencies(sdp_hmi_assets sdp_hmi)
