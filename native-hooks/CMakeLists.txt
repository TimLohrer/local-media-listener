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

# Option to control static linking
option(STATIC_LINKING "Enable static linking of dependencies" ON)

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
include_directories(src/logging)
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
file(GLOB LOGGING_SOURCES "src/logging/*.cpp")

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
    if(STATIC_LINKING)
        message(STATUS "Windows static linking enabled - using static runtime (/MT)")
    endif()
elseif(APPLE)
    file(GLOB PLATFORM_SOURCES "src/platforms/macos/*.cpp")
    # darwin frameworks
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(COCOA_FRAMEWORK Cocoa)
    set(PLATFORM_LIBS ${FOUNDATION_FRAMEWORK} ${COREFOUNDATION_FRAMEWORK} ${COCOA_FRAMEWORK})
elseif(UNIX)
    file(GLOB PLATFORM_SOURCES "src/platforms/linux/*.cpp")
    # nix libs - prefer static linking if enabled
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(DBUS REQUIRED dbus-1)
    
    if(STATIC_LINKING)
        # Try to use static libraries for D-Bus if available
        pkg_check_modules(DBUS_STATIC QUIET dbus-1 --static)
        if(DBUS_STATIC_FOUND)
            message(STATUS "Using static D-Bus libraries")
            set(PLATFORM_LIBS ${DBUS_STATIC_LIBRARIES})
            include_directories(${DBUS_STATIC_INCLUDE_DIRS})
            link_directories(${DBUS_STATIC_LIBRARY_DIRS})
            set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${DBUS_STATIC_LDFLAGS_OTHER}")
        else()
            message(STATUS "Static D-Bus libraries not found, using dynamic")
            set(PLATFORM_LIBS ${DBUS_LIBRARIES})
            include_directories(${DBUS_INCLUDE_DIRS})
        endif()
    else()
        set(PLATFORM_LIBS ${DBUS_LIBRARIES})
        include_directories(${DBUS_INCLUDE_DIRS})
    endif()
endif()

# Configure static linking if enabled
if(STATIC_LINKING)
    message(STATUS "Static linking enabled")
    # Enable static linking for Boost
    set(Boost_USE_STATIC_LIBS ON)
    set(Boost_USE_MULTITHREADED ON)
    set(Boost_USE_STATIC_RUNTIME OFF)

    # Prefer static libraries globally
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".a" ".lib" ".so" ".dylib" ".dll")

    # Platform-specific static linking flags
    if(WIN32)
        # Windows: Use static runtime library
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        # Force static linking of MSVC runtime
        foreach(flag_var CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_RELWITHDEBINFO)
            if(${flag_var} MATCHES "/MD")
                string(REGEX REPLACE "/MD" "/MT" ${flag_var} "${${flag_var}}")
            endif()
        endforeach()
    elseif(UNIX AND NOT APPLE)
        # Linux: Static linking flags
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libgcc -static-libstdc++")
        set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -static-libgcc -static-libstdc++")
    endif()
else()
    message(STATUS "Dynamic linking enabled")
    set(Boost_USE_STATIC_LIBS OFF)
endif()

# third-party deps
include_directories(third-party)
include_directories(third-party/httplib)
include_directories(third-party/nlohmann)

find_package(Boost 1.70.0 CONFIG REQUIRED COMPONENTS system)
if(Boost_FOUND)
    message(STATUS "found boost: ${Boost_LIBRARIES}")
    # Use modern CMake targets for better static linking control
    if(TARGET Boost::system)
        set(THIRD_PARTY_LIBS Boost::system)
    else()
        include_directories(${Boost_INCLUDE_DIRS})
        set(THIRD_PARTY_LIBS ${Boost_LIBRARIES})
    endif()
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
    ${LOGGING_SOURCES}
    ${PLATFORM_SOURCES}
)

target_link_libraries(native_hook ${PLATFORM_LIBS} ${THIRD_PARTY_LIBS})

# Show what libraries are being linked
message(STATUS "Platform libraries: ${PLATFORM_LIBS}")
message(STATUS "Third-party libraries: ${THIRD_PARTY_LIBS}")

# Additional static linking configuration
if(STATIC_LINKING)
    # Link statically where possible
    if(WIN32)
        # Windows: Link against static runtime
        target_compile_options(native_hook PRIVATE $<$<CONFIG:Release>:/MT> $<$<CONFIG:Debug>:/MTd>)
    elseif(UNIX AND NOT APPLE)
        # Linux: Additional linker options
        target_link_options(native_hook PRIVATE -Wl,--as-needed)
        # Note: For shared libraries, we can't use -static, but we can statically link dependencies
    endif()
endif()

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

 