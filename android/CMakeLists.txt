project(NitroRealTimeNitro)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME NitroRealTimeNitro)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

#===============================================================================
# libwebsockets - 3rd party library
#===============================================================================
set(LWS_DIR ${CMAKE_SOURCE_DIR}/../3rdparty/output/android/libwebsockets)

# Create imported static library for libwebsockets
add_library(libwebsockets STATIC IMPORTED)
set_target_properties(libwebsockets PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libwebsockets.a"
)

# Create imported static libraries for mbedtls (required by libwebsockets)
add_library(libmbedtls STATIC IMPORTED)
set_target_properties(libmbedtls PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libmbedtls.a"
)

add_library(libmbedx509 STATIC IMPORTED)
set_target_properties(libmbedx509 PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libmbedx509.a"
)

add_library(libmbedcrypto STATIC IMPORTED)
set_target_properties(libmbedcrypto PROPERTIES
    IMPORTED_LOCATION "${LWS_DIR}/${ANDROID_ABI}/lib/libmbedcrypto.a"
)

#===============================================================================
# Define C++ library and add all sources
#===============================================================================
add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    src/main/cpp/AndroidBundleHelper.cpp
    ../cpp/HybridWebSocket.cpp
    # Add more source files here as needed
)

#===============================================================================
# Add Nitrogen specs :)
#===============================================================================
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/NitroRealTimeNitro+autolinking.cmake)

#===============================================================================
# Set up includes
#===============================================================================
include_directories(
    "src/main/cpp"
    "../cpp"
    "${LWS_DIR}/${ANDROID_ABI}/include"    # libwebsockets headers
)

#===============================================================================
# Find system libraries
#===============================================================================
find_library(LOG_LIB log)

#===============================================================================
# Link all libraries together
#===============================================================================
target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android                     # Android core
    libwebsockets               # libwebsockets static library
    libmbedtls                  # mbedTLS library
    libmbedx509                 # mbedTLS X.509 library
    libmbedcrypto               # mbedTLS crypto library
)