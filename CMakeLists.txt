cmake_minimum_required(VERSION 3.24)
project(quickapp_runtime_ios LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(QUICKAPP_CORE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-runtime-core")
set(QUICKAPP_JS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-runtime-js")
set(QUICKAPP_RPK "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-toolkit/evidence/tk-s12-lvgl-p0.rpk")
set(QUICKAPP_RPK_INSPECTION_BOARD "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/showcases/inspection-board/dist/inspection-board.rpk")
set(QUICKAPP_RPK_CONTENT_HUB "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/showcases/content-hub/dist/content-hub.rpk")
set(QUICKAPP_RPK_HEALTH_SUMMARY "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/showcases/health-summary/dist/health-summary.rpk")
set(QUICKAPP_RPK_SHOP "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/showcases/shop/dist/shop.rpk")
set(QUICKAPP_RPK_CONTROLS "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/controls-001/dist/controls-001.rpk")
set(QUICKAPP_RPK_CONTROLS_002 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/controls-002/dist/controls-002.rpk")
set(QUICKAPP_RPK_LIST_001 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/list-001/dist/list-001.rpk")
set(QUICKAPP_RPK_PLATFORM_001 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/platform-001/dist/platform-001.rpk")
set(QUICKAPP_RPK_MEDIA_001 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/media-001/dist/media-001.rpk")
set(QUICKAPP_RPK_TABS_001 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/tabs-001/dist/tabs-001.rpk")
set(QUICKAPP_RPK_CAPABILITY_GALLERY_001 "${CMAKE_CURRENT_SOURCE_DIR}/../quickapp-examples/baseline-cases/capability-gallery-001/dist/capability-gallery-001.rpk")
set(QUICKAPP_VIDEO_SAMPLE "${CMAKE_CURRENT_SOURCE_DIR}/../source/third_party/lvgl/tests/src/test_assets/test_video_birds.mp4")

set(QUICKAPP_IOS_RPK_RESOURCES
  "${QUICKAPP_RPK}"
  "${QUICKAPP_RPK_INSPECTION_BOARD}"
  "${QUICKAPP_RPK_CONTENT_HUB}"
  "${QUICKAPP_RPK_HEALTH_SUMMARY}"
  "${QUICKAPP_RPK_SHOP}"
  "${QUICKAPP_RPK_CONTROLS}"
  "${QUICKAPP_RPK_CONTROLS_002}"
  "${QUICKAPP_RPK_LIST_001}"
  "${QUICKAPP_RPK_PLATFORM_001}"
  "${QUICKAPP_RPK_MEDIA_001}"
  "${QUICKAPP_RPK_TABS_001}"
  "${QUICKAPP_RPK_CAPABILITY_GALLERY_001}"
)
set(QUICKAPP_IOS_EXISTING_RPK_RESOURCES)
foreach(QUICKAPP_IOS_RPK IN LISTS QUICKAPP_IOS_RPK_RESOURCES)
  if(EXISTS "${QUICKAPP_IOS_RPK}")
    list(APPEND QUICKAPP_IOS_EXISTING_RPK_RESOURCES "${QUICKAPP_IOS_RPK}")
  endif()
endforeach()

find_package(ZLIB REQUIRED)
option(QUICKAPP_IOS_ENABLE_STAGE_LOG "Enable iOS Runtime stage logs" OFF)

set(QUICKAPP_CORE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(QUICKAPP_JS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
add_subdirectory("${QUICKAPP_CORE_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/quickapp-runtime-core")
add_subdirectory("${QUICKAPP_JS_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/quickapp-runtime-js")

set(QUICKAPP_IOS_SHARED_LIBS
  quickapp_core_foundation
  quickapp_core_page_ir
  quickapp_core_runtime_tree
  quickapp_core_lifecycle
  quickapp_core_surface
  quickapp_core_render
  quickapp_core_package
  quickapp_core_features
  yogacore
  quickapp_js_engine_quickjs
  quickapp_quickjs_vendor
  quickapp_js_static_facades
  quickapp_js_page_host_control
  quickapp_js_vm_lifecycle
  quickapp_js_event
  quickapp_js_alpha_page_stage
  quickapp_js_alpha_initial_binding
  quickapp_js_module_loader
  quickapp_js_alpha_initial_render
  quickapp_js_runtime_abi
  quickapp_js_executor
  quickapp_js_engine_api
  ZLIB::ZLIB
)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  add_library(quickapp_ios_platform STATIC
    src/platform_adapter.cpp
    src/runtime_spine.cpp
    src/ios_gateway.mm
    src/quickapp_kit.mm
  )
  target_include_directories(quickapp_ios_platform PUBLIC include)
  target_link_libraries(quickapp_ios_platform PUBLIC
    quickapp_core_package
    quickapp_core_features
    quickapp_core_render
    quickapp_js_engine_quickjs
    quickapp_js_engine_api
    quickapp_js_executor
    quickapp_js_module_loader
    quickapp_js_static_facades
    quickapp_js_page_host_control
    quickapp_js_vm_lifecycle
    quickapp_js_alpha_initial_binding
    quickapp_js_alpha_initial_render
    quickapp_js_event
    quickapp_js_alpha_page_stage
    "-framework Foundation"
    "-framework UIKit"
    "-framework AVFoundation"
    "-framework AVKit"
    "-framework CoreMedia"
  )
  target_compile_options(quickapp_ios_platform PRIVATE -Wall -Wextra -Wpedantic -fobjc-arc)
  target_compile_definitions(quickapp_ios_platform PRIVATE
    QUICKAPP_IOS_UIKIT=1
    QUICKAPP_IOS_ENABLE_STAGE_LOG=$<BOOL:${QUICKAPP_IOS_ENABLE_STAGE_LOG}>
  )

  add_executable(quickapp_ios_simulator MACOSX_BUNDLE
    src/ios_simulator_main.mm
    ${QUICKAPP_IOS_EXISTING_RPK_RESOURCES}
    "${QUICKAPP_VIDEO_SAMPLE}"
  )
  set_source_files_properties(
    ${QUICKAPP_IOS_EXISTING_RPK_RESOURCES}
    "${QUICKAPP_VIDEO_SAMPLE}"
    PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
  )
  target_link_libraries(quickapp_ios_simulator PRIVATE
    quickapp_ios_platform
    "-framework Foundation"
    "-framework UIKit"
    "-framework AVFoundation"
    "-framework AVKit"
    "-framework CoreMedia"
  )
  target_compile_options(quickapp_ios_simulator PRIVATE -fobjc-arc)
  set_target_properties(quickapp_ios_simulator PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/QuickAppSimulator-Info.plist"
    MACOSX_BUNDLE_GUI_IDENTIFIER "dev.quickappkit.ios.simulator"
    MACOSX_BUNDLE_BUNDLE_NAME "QuickApp Kit iOS A1"
    MACOSX_BUNDLE_INFO_STRING "QuickApp Kit iOS A1"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "1"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
  )

  set(QUICKAPP_KIT_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/libQuickAppKit.a")
  set(QUICKAPP_KIT_INPUTS "$<TARGET_FILE:quickapp_ios_platform>")
  foreach(QUICKAPP_KIT_DEP IN LISTS QUICKAPP_IOS_SHARED_LIBS)
    if(TARGET "${QUICKAPP_KIT_DEP}")
      list(APPEND QUICKAPP_KIT_INPUTS "$<TARGET_FILE:${QUICKAPP_KIT_DEP}>")
    endif()
  endforeach()
  add_custom_command(
    OUTPUT "${QUICKAPP_KIT_ARCHIVE}"
    COMMAND ${CMAKE_COMMAND} -E rm -f "${QUICKAPP_KIT_ARCHIVE}"
    COMMAND /usr/bin/libtool -static -o "${QUICKAPP_KIT_ARCHIVE}" ${QUICKAPP_KIT_INPUTS}
    DEPENDS quickapp_ios_platform ${QUICKAPP_IOS_SHARED_LIBS}
    VERBATIM
  )
  add_custom_target(QuickAppKit DEPENDS "${QUICKAPP_KIT_ARCHIVE}")
else()
  add_library(quickapp_ios_spine_host STATIC
    src/platform_adapter.cpp
    src/runtime_spine.cpp
  )
  target_include_directories(quickapp_ios_spine_host PUBLIC include)
  target_link_libraries(quickapp_ios_spine_host PUBLIC ${QUICKAPP_IOS_SHARED_LIBS} m pthread)
  target_compile_options(quickapp_ios_spine_host PRIVATE -Wall -Wextra -Wpedantic)
  target_compile_definitions(quickapp_ios_spine_host PRIVATE QUICKAPP_IOS_UIKIT=0)
  add_executable(quickapp_ios_spine_probe src/ios_spine_probe.cpp)
  target_link_libraries(quickapp_ios_spine_probe PRIVATE quickapp_ios_spine_host)
  target_compile_options(quickapp_ios_spine_probe PRIVATE -Wall -Wextra -Wpedantic)
endif()
