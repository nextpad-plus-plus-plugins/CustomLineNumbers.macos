cmake_minimum_required(VERSION 3.20)
project(CustomLineNumbers VERSION 1.0.0 LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# Host plugin interface + Scintilla (read-only; NO host changes)
set(NPP_MACOS_DIR      "${CMAKE_SOURCE_DIR}/../../notepad-plus-plus-macos")
set(NPP_PLUGIN_INCLUDE "${NPP_MACOS_DIR}/src")
set(SCINTILLA_INCLUDE  "${NPP_MACOS_DIR}/scintilla/include")

add_library(CustomLineNumbers SHARED src/CustomLineNumbers.mm)
target_include_directories(CustomLineNumbers PRIVATE ${NPP_PLUGIN_INCLUDE} ${SCINTILLA_INCLUDE})
target_link_libraries(CustomLineNumbers PRIVATE "-framework Cocoa")
target_compile_options(CustomLineNumbers PRIVATE
    -Wall -Wno-unused-parameter -fvisibility=hidden
    $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
# Folder is CustomLineNumbers.macos → dylib MUST be CustomLineNumbers.dylib.
# Project name already matches, but pin OUTPUT_NAME for safety per the playbook.
set_target_properties(CustomLineNumbers PROPERTIES
    PREFIX "" SUFFIX ".dylib" OUTPUT_NAME "CustomLineNumbers")
target_link_options(CustomLineNumbers PRIVATE "-Wl,-current_version,${PROJECT_VERSION}")

# Install (real plugins dir). This plugin has no toolbar icon (menu-only on
# Windows too); docs live in resources/.
set(PLUGIN_INSTALL_DIR "$ENV{HOME}/Library/Application Support/Nextpad++/plugins/CustomLineNumbers")
install(TARGETS CustomLineNumbers DESTINATION "${PLUGIN_INSTALL_DIR}")
install(FILES "${CMAKE_SOURCE_DIR}/resources/CustomLineNumbers.txt"
        DESTINATION "${PLUGIN_INSTALL_DIR}/doc")
