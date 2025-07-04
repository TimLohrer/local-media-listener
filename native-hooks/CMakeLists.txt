cmake_minimum_required(VERSION 3.16)
project(LocalMediaListener)

if(POLICY CMP0074)
    cmake_policy(SET CMP0074 NEW)
endif()

# Enable ccache for faster incremental builds
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${CCACHE_PROGRAM}")
    set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "${CCACHE_PROGRAM}")
    message(STATUS "Using ccache for faster builds")
endif()

# windows stuff wooow
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# jni
find_package(JNI REQUIRED)

# platform
if(WIN32)
    set(PLATFORM_NAME "windows")
    set(LIB_EXTENSION ".dll") # windows linkage
elseif(APPLE)
    set(PLATFORM_NAME "darwin")
    set(LIB_EXTENSION ".dylib") # elf/dylib
elseif(UNIX)
    set(PLATFORM_NAME "linux")
    set(LIB_EXTENSION ".so") # elf/so
endif()

# arch detection: detect target arch from VS generator if present
if(DEFINED CMAKE_VS_PLATFORM_NAME)
    string(TOLOWER "${CMAKE_VS_PLATFORM_NAME}" VS_ARCH_LOWER)
    if(VS_ARCH_LOWER MATCHES "x64|amd64|x86_64|x86")
        set(ARCH_NAME "amd64")
    elseif(VS_ARCH_LOWER MATCHES "arm64|aarch64|arm")
        set(ARCH_NAME "arm64")
    else()
        message(FATAL_ERROR "Unsupported VS target arch: ${CMAKE_VS_PLATFORM_NAME}")
    endif()
elseif(APPLE AND CMAKE_OSX_ARCHITECTURES)
    # use first specified architecture for naming
    string(REGEX MATCH "[^;]+" FIRST_ARCH "${CMAKE_OSX_ARCHITECTURES}")
    if(FIRST_ARCH MATCHES "x86_64|amd64|AMD64")
        set(ARCH_NAME "amd64")
    elseif(FIRST_ARCH MATCHES "aarch64|arm64|ARM64")
        set(ARCH_NAME "arm64")
    else()
        message(FATAL_ERROR "Unsupported macOS architecture: ${FIRST_ARCH}")
    endif()
else()
    # native
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
        set(ARCH_NAME "amd64")
    elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|ARM64")
        set(ARCH_NAME "arm64")
    else()
        message(FATAL_ERROR "unsupported host arch: ${CMAKE_HOST_SYSTEM_PROCESSOR}")
    endif()
endif()

# outdir
set(OUTPUT_DIR "${CMAKE_SOURCE_DIR}/../src/main/resources/lib")

# common includes
include_directories(${JNI_INCLUDE_DIRS})
include_directories(src/common)
include_directories(src/core)
include_directories(src/jni)

# platform-specific includes
if(WIN32)
    include_directories(src/platforms/windows)
elseif(APPLE)
    include_directories(src/platforms/macos)
elseif(UNIX)
    include_directories(src/platforms/linux)
endif()

# collect source files from folders
file(GLOB COMMON_SOURCES "src/common/*.cpp")
file(GLOB CORE_SOURCES "src/core/*.cpp")
file(GLOB JNI_SOURCES "src/jni/*.cpp")

# platform-specific sources
if(WIN32)
    file(GLOB PLATFORM_SOURCES "src/platforms/windows/*.cpp")
    # Add WinRT support and link against system libraries by name
    find_package(cppwinrt CONFIG REQUIRED)
    set(PLATFORM_LIBS
        winmm
        ole32
        oleaut32
        Microsoft::CppWinRT
        WindowsApp
    )
elseif(APPLE)
    file(GLOB PLATFORM_SOURCES "src/platforms/macos/*.cpp")
    # darwin frameworks
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(COCOA_FRAMEWORK Cocoa)
    set(PLATFORM_LIBS ${FOUNDATION_FRAMEWORK} ${COREFOUNDATION_FRAMEWORK} ${COCOA_FRAMEWORK})
elseif(UNIX)
    file(GLOB PLATFORM_SOURCES "src/platforms/linux/*.cpp")
    # nix libs
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(DBUS REQUIRED dbus-1)
    set(PLATFORM_LIBS ${DBUS_LIBRARIES})
    include_directories(${DBUS_INCLUDE_DIRS})
endif()

# third-party deps
include_directories(third-party)
include_directories(third-party/httplib)
include_directories(third-party/nlohmann)

find_package(Boost 1.70.0 CONFIG REQUIRED COMPONENTS system)
if(Boost_FOUND)
    message(STATUS "found boost: ${Boost_LIBRARIES}")
    include_directories(${Boost_INCLUDE_DIRS})
    set(THIRD_PARTY_LIBS ${Boost_LIBRARIES})
    # threading
    find_package(Threads REQUIRED)
    list(APPEND THIRD_PARTY_LIBS Threads::Threads)
else()
    message(FATAL_ERROR "Could not find Boost. pls install boost 1.70.0 or later :3")
endif()

# main library
add_library(native_hook SHARED
    ${COMMON_SOURCES}
    ${CORE_SOURCES}
    ${JNI_SOURCES}
    ${PLATFORM_SOURCES}
)

target_link_libraries(native_hook ${PLATFORM_LIBS} ${THIRD_PARTY_LIBS})

# output name
set_target_properties(native_hook PROPERTIES
    OUTPUT_NAME "libnative_hook_${PLATFORM_NAME}_${ARCH_NAME}"
    PREFIX ""
    SUFFIX "${LIB_EXTENSION}"
)

# copy to resources
add_custom_command(TARGET native_hook POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory ${OUTPUT_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:native_hook> ${OUTPUT_DIR}/
    COMMENT "Copying lib to resources"
)

# compile defs
if(WIN32)
    target_compile_definitions(native_hook PRIVATE PLATFORM_WINDOWS)
    target_compile_options(native_hook PRIVATE /W4)
elseif(APPLE)
    target_compile_definitions(native_hook PRIVATE PLATFORM_MACOS)
    target_compile_options(native_hook PRIVATE -Wall -Wextra)
elseif(UNIX)
    target_compile_definitions(native_hook PRIVATE PLATFORM_LINUX)
    target_compile_options(native_hook PRIVATE -Wall -Wextra)
endif()

# Unit tests
option(BUILD_TESTS "Build unit tests" ON)
if(BUILD_TESTS)
    enable_testing()
    find_package(GTest REQUIRED)
    include(GoogleTest)
    file(GLOB TEST_SOURCES "src/tests/*.cpp")
    add_executable(unit_tests ${TEST_SOURCES})
    # Link against native_hook and GTest main (provides main())
    target_link_libraries(unit_tests PRIVATE native_hook GTest::gtest_main pthread)
    # Discover and register each GTest case as a separate CTest test
    gtest_discover_tests(unit_tests)
endif() 